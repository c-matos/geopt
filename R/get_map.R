#' Get a composed map of Portugal
#'
#' Returns an sf object with mainland Portugal and the islands moved next to
#' it as insets, ready for plotting. Uses the pre-simplified bundled datasets.
#'
#' Every result has the same columns, in the same order, whatever the
#' options: the level's own columns (and any joined `data`), then
#' `geopt_type`, `geopt_label` and `geopt_frame_level`, then the geometry.
#' `geopt_type` is `"boundary"` for the regions and `"frame"` for the frames
#' drawn around the insets (see [island_layout()]). `geopt_label` holds a
#' frame's name, or the label of an archipelago drawn as a rectangle
#' (`islands = "box"`).
#'
#' For a map of one region, filter the result: rows keep their codes and
#' names. For an archipelago, use `islands = "in_place"` first, so it is in its
#' true position rather than moved and enlarged.
#'
#' @param level Administrative level: `"freguesia"`, `"municipio"`,
#'   `"distrito"`, `"nuts1"`, `"nuts2"`, `"nuts3"` — or one of the health
#'   geographies dissolved from freguesias via [pt_health_codes]: `"uls"`,
#'   `"reg_saude"` (regiões de saúde) for the 2024 reform,
#'   or `"aces"`. If you have data by municipality, you might need
#'   `"uls_municipio"` and `"aces_municipio"`: the units that share a
#'   municipality are merged into one (see `vignette("health-geographies")`).
#'   Health levels are defined on the 2025 map only.
#' @param islands How to show the Açores and Madeira: `"compact"` (the
#'   default), `"groups"`, `"box"`, `"in_place"` or `"none"` (mainland only),
#'   or a layout made with [island_layout()] for anything else, such as a
#'   different setting per archipelago or no frames.
#' @param data Optional data.frame to join onto the boundaries, producing a
#'   map ready for a choropleth. Requires `by`.
#' @param by How to join `data`: which column identifies the unit and what it
#'   contains. Same forms as [pt_join()]. The unit keyword
#'   must correspond to `level`. Rows of `data` for an archipelago left out
#'   with `"none"` are dropped without a warning.
#' @param fuzzy Logical. Enable fuzzy name matching for the join (see
#'   [pt_match()]). Default `FALSE`.
#' @param aliases Optional named character vector of extra name aliases for
#'   the join (see [pt_match()]).
#' @param admin_vintage Which freguesia map to draw. Available values are
#'   `"2025"` (the default, the bundled data) or `"2013"`, the map in force
#'   from the 2013 reform until freguesias were restored in 2025.
#'   The 2013 map is downloaded from DGT (CAOP 2024, the last release that used
#'   the 2013 freguesias division), simplified and cached the first
#'   time, which needs the rmapshaper package and an internet connection. For
#'   `"2011"` and `"2001"` maps, use INE's BGRI by merging census areas of
#'   that year instead (see [get_censos()]), or convert the data with
#'   [pt_recode()]. Names in `data` are matched against this vintage. See
#'   `vignette("vintages")`.
#' @param nuts_vintage Which NUTS revision to use: `"2024"` (the default),
#'   `"2013"` or `"2002"`. Independent of `admin_vintage`, because every
#'   revision groups whole municipalities.
#' @param client Optional [GeoClient] to download and cache with (for a custom
#'   cache directory).
#'
#' @return An sf object in WGS84 (EPSG:4326).
#'
#' @examplesIf identical(Sys.getenv("NOT_CRAN"), "true")
#' library(ggplot2)
#'
#' m <- get_map("municipio")
#' ggplot(m) + geom_sf()
#'
#' # Mainland only
#' m <- get_map("municipio", islands = "none")
#'
#' # Regions and frames drawn separately
#' m <- get_map("nuts2")
#' ggplot() +
#'   geom_sf(data = m[m$geopt_type == "boundary", ], aes(fill = nuts2)) +
#'   geom_sf(data = m[m$geopt_type == "frame", ], fill = NA, linewidth = 0.5)
#'
#' # The archipelagos as labelled rectangles
#' get_map("nuts3", islands = "box")
#'
#' # The Açores in their three official groups, no frames
#' get_map("municipio", islands = island_layout(raa = "groups", frames = FALSE))
#'
#' # Join your own data by municipality name
#' df <- data.frame(concelho = c("Porto", "Lisboa"), value = c(10, 20))
#' m <- get_map("municipio", data = df, by = c(municipio = "concelho"))
#' ggplot(m) + geom_sf(aes(fill = value))
#'
#' # The NUTS 3 regions of the 2013 revision (25, against 26 today)
#' get_map("nuts3", nuts_vintage = "2013")
#'
#' @seealso [island_layout()], [plot_pt()]
#' @export
get_map <- function(level = "municipio",
                    islands = "compact",
                    data = NULL,
                    by = NULL,
                    fuzzy = FALSE,
                    aliases = NULL,
                    admin_vintage = NULL,
                    nuts_vintage = NULL,
                    client = NULL) {

  level <- validate_map_level(level)
  layout <- as_island_layout(islands)
  admin_vintage <- check_vintage(admin_vintage, "admin") %||%
    current_admin_vintage()
  nuts_vintage <- check_vintage(nuts_vintage, "nuts") %||%
    max(axis_vintages("nuts"))

  sf_all <- get_vintage_dataset(level, admin_vintage, nuts_vintage, client)
  sf_all <- sf::st_transform(sf_all, 4326L)
  # Every part is rebound below, so all must share one geometry column name.
  if (!identical(attr(sf_all, "sf_column"), "geometry")) {
    sf::st_geometry(sf_all) <- "geometry"
  }

  # Split into regions by centroid longitude
  centroids <- suppressWarnings(sf::st_centroid(sf_all))
  lon <- sf::st_coordinates(centroids)[, 1L]
  sf_cont <- sf_all[lon > -12, ]
  regions <- list(
    raa = sf_all[lon <= -20, ],
    ram = sf_all[lon > -20 & lon <= -12, ]
  )

  check_box_units(layout, regions, level)

  parts <- list(boundary_rows(sf_cont))
  frames <- list()
  left_out <- list()

  for (r in c("raa", "ram")) {
    cfg <- layout[[r]]
    sf_r <- regions[[r]]
    if (nrow(sf_r) == 0L) next
    if (cfg$show == "none") {
      left_out <- c(left_out, list(sf_r))
    } else if (cfg$show == "in_place") {
      parts <- c(parts, list(boundary_rows(sf_r)))
    } else if (cfg$show == "inset") {
      result <- compose_region(sf_r, cfg)
      parts <- c(parts, result$boundaries)
      if (layout$frames) frames <- c(frames, result$frames)
    }
  }

  # Rectangles stack from the bottom: Madeira first, the Açores above
  box_regions <- Filter(
    function(r) layout[[r]]$show == "box" && nrow(regions[[r]]) > 0L,
    c("ram", "raa")
  )
  if (length(box_regions) > 0L) {
    labels <- vapply(box_regions, function(r) layout[[r]]$label, character(1L))
    parts <- c(parts, compose_island_boxes(
      sf_cont, regions[box_regions], labels, layout$box_position
    ))
  }

  combined <- bind_map_rows(parts)

  if (!is.null(data)) {
    key_col <- MATCH_LEVELS[[level]]$code
    not_drawn <- unlist(lapply(left_out, function(x) x[[key_col]]))
    combined <- join_map_data(combined, level, data, by,
                              fuzzy = fuzzy, aliases = aliases,
                              not_drawn = not_drawn,
                              admin_vintage = admin_vintage,
                              nuts_vintage = nuts_vintage)
  }

  finalize_map_columns(bind_map_rows(c(list(combined), frames)))
}

#' Build echarts frame styling data
#'
#' Creates a list of data items suitable for passing to
#' `echarts4r::e_map(data = ...)` to style the frames around the island
#' insets, with line widths based on `geopt_frame_level`. Because the `data`
#' parameter in echarts replaces the entire series data, this function returns
#' entries for **all** features — preserving the mapped values for real
#' regions and styling frames as transparent overlays.
#'
#' @param sf_obj An sf object returned by [get_map()].
#' @param value_col Name of the value column being mapped (as a string).
#' @param level_widths Numeric vector mapping frame level to border width.
#'   Position 1 corresponds to `geopt_frame_level == 1`, etc.
#' @param border_color Border color string. Default `"#333"`.
#'
#' @return A list of named lists, each with `name`, `value`, and (for frames)
#'   `itemStyle`. Pass this to `echarts4r::e_map(data = ...)`.
#'
#' @examplesIf identical(Sys.getenv("NOT_CRAN"), "true")
#' m <- get_map("municipio")
#' m$name <- dplyr::coalesce(m$municipio, m$geopt_label)
#' geojson <- geojsonsf::sf_geojson(m)
#'
#' m |>
#'   echarts4r::e_charts(name) |>
#'   echarts4r::e_map_register("pt", geojson) |>
#'   echarts4r::e_map(area_ha, map = "pt", roam = TRUE,
#'                    data = frame_data_echarts(m, "area_ha")) |>
#'   echarts4r::e_visual_map(area_ha)
#'
#' @export
frame_data_echarts <- function(sf_obj,
                               value_col,
                               level_widths = c(0.8, 0.4, 0.2),
                               border_color = "#333") {
  name_col <- if ("name" %in% names(sf_obj)) "name" else "geopt_label"
  is_frame <- sf_obj[["geopt_type"]] == "frame"

  lapply(seq_len(nrow(sf_obj)), function(i) {
    if (is_frame[i]) {
      lvl <- sf_obj[["geopt_frame_level"]][i]
      width <- if (lvl <= length(level_widths)) level_widths[lvl] else 0.2
      list(
        name = sf_obj[[name_col]][i],
        value = 0,
        itemStyle = list(
          areaColor = "rgba(0,0,0,0)",
          borderColor = border_color,
          borderWidth = width
        )
      )
    } else {
      list(
        name = sf_obj[[name_col]][i],
        value = sf_obj[[value_col]][i]
      )
    }
  })
}


#' Add labels to an echarts map
#'
#' Pipe-able function that injects series-level label configuration into
#' an existing echarts widget, labelling the rectangles drawn for
#' `islands = "box"`. Uses a JavaScript formatter that shows the
#' `geopt_label` text for those rectangles and an empty string for every other
#' feature.
#'
#' @param e An echarts widget created by `echarts4r::e_charts()`.
#' @param sf_obj An sf object returned by [get_map()]. Features are matched by
#'   its `name` column (the one the widget was built with), or by
#'   `geopt_label` if there is none.
#' @param font_size Font size for labels. Default `12`.
#' @param color Color for labels. Default `"#333"`.
#' @param position Label position relative to the feature bounding box.
#'   Default `"right"`. See echarts label position options.
#' @param offset Numeric vector of length 2 (`c(x, y)`) to shift the label
#'   in pixels. Default `c(92, 0)`.
#' @param ... Additional echarts label properties (e.g. `align`,
#'   `verticalAlign`, `fontWeight`, `rotate`).
#'
#' @return The modified echarts widget.
#'
#' @examplesIf identical(Sys.getenv("NOT_CRAN"), "true")
#' m <- get_map("nuts3", islands = "box")
#' m$name <- dplyr::coalesce(m$geopt_label, m$nuts3)
#' geojson <- geojsonsf::sf_geojson(m)
#'
#' m |>
#'   echarts4r::e_charts(name) |>
#'   echarts4r::e_map_register("pt", geojson) |>
#'   echarts4r::e_map(area_ha, map = "pt", roam = TRUE) |>
#'   box_labels_echarts(m) |>
#'   echarts4r::e_visual_map(area_ha)
#'
#' @export
box_labels_echarts <- function(e,
                               sf_obj,
                               font_size = 12,
                               color = "#333",
                               position = "right",
                               offset = c(92, 0),
                               ...) {
  if (!"geopt_label" %in% names(sf_obj)) return(e)

  # Frames carry their name in geopt_label too; only rectangles get a label.
  is_box <- !is.na(sf_obj[["geopt_label"]])
  if ("geopt_type" %in% names(sf_obj)) {
    is_box <- is_box & sf_obj[["geopt_type"]] == "boundary"
  }
  labeled <- sf_obj[is_box, ]
  if (nrow(labeled) == 0L) return(e)

  name_col <- if ("name" %in% names(labeled)) "name" else "geopt_label"
  pairs <- paste0(
    '"', gsub('"', '\\\\"', labeled[[name_col]]), '":"',
    gsub('"', '\\\\"', labeled[["geopt_label"]]), '"'
  )
  lookup_js <- paste0("{", paste(pairs, collapse = ","), "}")

  formatter_js <- sprintf(
    "function(params){var m=%s;var t=m[params.name];return t?'{lbl|'+t+'}':'';}",
    lookup_js
  )

  n <- length(e$x$opts$series)
  if (n > 0L) {
    e$x$opts$series[[n]]$label <- c(list(
      show = TRUE,
      formatter = htmlwidgets::JS(formatter_js),
      fontSize = font_size,
      color = color,
      position = position,
      offset = offset,
      width = 120,
      verticalAlign = "middle",
      rich = list(
        lbl = list(
          align = "left",
          fontSize = font_size,
          color = color
        )
      )
    ), list(...))
  }

  e
}


# --- Internal helpers --------------------------------------------------------

GEOPT_COLUMNS <- c("geopt_type", "geopt_label", "geopt_frame_level")

#' Map level name to dataset name suffix
#' @noRd
level_to_dataset <- function(level) {
  suffixes <- c(
    freguesia = "freguesias",
    municipio = "municipios",
    distrito  = "distritos",
    nuts1     = "nuts1",
    nuts2     = "nuts2",
    nuts3     = "nuts3",
    uls       = "uls",
    reg_saude = "reg_saude",
    aces      = "aces",
    uls_municipio  = "uls_municipio",
    aces_municipio = "aces_municipio"
  )
  suffixes[[level]]
}

#' Get a bundled dataset by name
#' @noRd
get_dataset <- function(name) {
  env <- new.env(parent = emptyenv())
  utils::data(list = name, package = "geopt", envir = env)
  env[[name]]
}

#' Crop an sf object using a WGS84 bounding box vector
#' @noRd
crop_to_bbox <- function(sf_obj, bbox_vec) {
  bbox <- sf::st_bbox(
    c(xmin = bbox_vec[["xmin"]], ymin = bbox_vec[["ymin"]],
      xmax = bbox_vec[["xmax"]], ymax = bbox_vec[["ymax"]]),
    crs = sf::st_crs(4326L)
  )
  suppressWarnings(sf::st_crop(sf_obj, bbox))
}

#' Mark rows as regions (as opposed to frames)
#' @noRd
boundary_rows <- function(sf_obj, label = NA_character_) {
  sf_obj$geopt_type <- rep("boundary", nrow(sf_obj))
  sf_obj$geopt_label <- rep(label, nrow(sf_obj))
  sf_obj$geopt_frame_level <- rep(NA_integer_, nrow(sf_obj))
  sf_obj
}

#' Bind sf parts that may have different columns, filling the gaps with NA
#' @noRd
bind_map_rows <- function(parts) {
  parts <- Filter(function(p) !is.null(p) && nrow(p) > 0L, parts)
  cols <- unique(unlist(lapply(parts, function(p) {
    setdiff(names(p), attr(p, "sf_column"))
  })))
  parts <- lapply(parts, function(p) {
    for (col in setdiff(cols, names(p))) p[[col]] <- rep(NA, nrow(p))
    p[, cols, drop = FALSE]
  })
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}

#' Put the geopt_* columns last (before the geometry), whatever the options
#' @noRd
finalize_map_columns <- function(m) {
  m$geopt_label <- as.character(m$geopt_label)
  m$geopt_frame_level <- as.integer(m$geopt_frame_level)
  others <- setdiff(names(m), c(GEOPT_COLUMNS, attr(m, "sf_column")))
  m[, c(others, GEOPT_COLUMNS), drop = FALSE]
}

#' Stop when "box" would draw more than one rectangle per archipelago
#' @noRd
check_box_units <- function(layout, regions, level) {
  n <- vapply(c("raa", "ram"), function(r) {
    if (layout[[r]]$show == "box") nrow(regions[[r]]) else 0L
  }, integer(1L))
  over <- n[n > 1L]
  if (length(over) == 0L) return(invisible())

  says <- c(raa = "the A\u00e7ores have %d units", ram = "Madeira has %d units")
  counts <- vapply(names(over), function(r) sprintf(says[[r]], over[[r]]),
                   character(1L))
  stop(sprintf(
    paste0(
      "\"box\" draws each archipelago as one rectangle, but at level \"%s\" ",
      "%s. Use islands = \"compact\", or a level where each archipelago is a ",
      "single unit (nuts1, nuts2, nuts3, reg_saude)."
    ),
    level, paste(counts, collapse = " and ")
  ), call. = FALSE)
}

#' Compose one archipelago as insets
#'
#' Crops each group of the region config, moves and scales it around the
#' anchor, and builds the frames: one around the archipelago, one per
#' sub-frame, and one per group that has a label.
#' @noRd
compose_region <- function(sf_raw, cfg) {
  group_defs <- cfg$groups

  # Crop each group
  cropped <- lapply(group_defs, function(g) {
    if (is.null(g$crop)) return(sf_raw)
    crop_to_bbox(sf_raw, g$crop)
  })

  # Drop empty crops
  non_empty <- vapply(cropped, function(x) nrow(x) > 0L, logical(1L))
  cropped <- cropped[non_empty]
  group_defs <- group_defs[non_empty]
  if (length(cropped) == 0L) return(list(boundaries = list(), frames = list()))

  groups <- Map(function(g, sf_obj) {
    list(sf = sf_obj, offset = g$offset, scale = g$scale %||% 1)
  }, group_defs, cropped)
  insets <- offset_group(groups, anchor = cfg$anchor)

  # Archipelago frame
  frames <- list(make_frame_row(
    cfg$label,
    do.call(bbox_around, c(unname(insets), list(buffer = cfg$frame_buffer %||% 0.1))),
    frame_level = 1L
  ))

  # Frames around several groups at once
  for (sf_def in cfg$sub_frames %||% list()) {
    members <- insets[intersect(sf_def$groups, names(insets))]
    if (length(members) > 0L) {
      frames <- c(frames, list(make_frame_row(
        sf_def$label,
        do.call(bbox_around, c(unname(members), list(buffer = sf_def$frame_buffer %||% 0.05))),
        frame_level = sf_def$frame_level %||% 2L
      )))
    }
  }

  # Frames around single groups
  for (nm in names(group_defs)) {
    g <- group_defs[[nm]]
    if (!is.null(g$label)) {
      frames <- c(frames, list(make_frame_row(
        g$label,
        bbox_around(insets[[nm]], buffer = g$frame_buffer %||% 0.05),
        frame_level = g$frame_level %||% 3L
      )))
    }
  }

  list(boundaries = unname(lapply(insets, boundary_rows)), frames = frames)
}

#' Compose island regions as labelled rectangles next to the mainland
#'
#' One rectangle per archipelago (check_box_units() guarantees a single unit
#' each), stacked from the bottom. Each rectangle carries the region's
#' attributes, so choropleth fills work as for any other boundary.
#' @param sf_cont Mainland sf object (used to place the preset positions).
#' @param island_rows List of one-row sf objects, one per archipelago.
#' @param labels Character vector of labels (same length as island_rows).
#' @param position `"bottom_left"`, `"top_left"`, or `c(x, y)` for the
#'   bottom-left corner of the stack.
#' @noRd
compose_island_boxes <- function(sf_cont, island_rows, labels,
                                 position = "bottom_left") {
  bbox <- sf::st_bbox(sf_cont)

  box_w <- 0.55
  box_h <- 0.25
  # One empty slot between archipelagos, so they read as separate
  step <- 2 * (box_h + 0.01)
  n <- length(island_rows)
  stack_h <- (n - 1L) * step + box_h

  if (is.numeric(position)) {
    x_left <- position[1L]
    y_base <- position[2L]
  } else {
    x_left <- bbox[["xmin"]] - 0.75
    y_base <- if (position == "bottom_left") {
      bbox[["ymin"]] + 0.15
    } else {
      bbox[["ymax"]] - 1 - stack_h
    }
  }

  unname(lapply(seq_len(n), function(i) {
    y0 <- y_base + (i - 1L) * step
    rect <- sf::st_polygon(list(matrix(c(
      x_left,         y0,
      x_left + box_w, y0,
      x_left + box_w, y0 + box_h,
      x_left,         y0 + box_h,
      x_left,         y0
    ), ncol = 2, byrow = TRUE)))
    geom <- sf::st_sfc(rect, crs = sf::st_crs(island_rows[[i]]))
    row <- sf::st_drop_geometry(island_rows[[i]])
    out <- sf::st_sf(row, geometry = sf::st_cast(geom, "MULTIPOLYGON"))
    boundary_rows(out, label = labels[[i]])
  }))
}

#' Create an sf row for a frame
#' @noRd
make_frame_row <- function(label, sfc_box, frame_level) {
  sf::st_sf(
    geopt_type = "frame",
    geopt_label = label,
    geopt_frame_level = as.integer(frame_level),
    geometry = sf::st_cast(sfc_box, "MULTILINESTRING")
  )
}
