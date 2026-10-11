# Quick choropleth plots of Portugal, rendered with ggplot2 or echarts4r.
#
# plot_pt() standardizes CONTENT across renderers (value fill, frame line
# widths, island labels, NA fill) and returns each renderer's NATIVE object
# (a ggplot, an echarts4r widget) so all further styling happens in the
# native grammar. Adding a renderer means writing render_plot_<name>() and
# adding it to PLOT_RENDERER_NAMES and the switch() in plot_pt().

# Order matters: most specific first, so a map's level can be detected from
# the code columns it carries. uls and aces precede reg_saude because their maps
# may also carry health-region columns; nuts levels never carry health columns.
# uls_municipio and aces_municipio come after uls and aces, because data joined
# onto a uls or aces map may carry them.
PLOT_LEVEL_ORDER <- c("freguesia", "municipio", "distrito",
                      "uls", "aces", "uls_municipio", "aces_municipio",
                      "nuts3", "nuts2", "reg_saude", "nuts1")

PLOT_RENDERER_NAMES <- c("ggplot", "echarts")

#' Quick map of Portugal
#'
#' One-liner choropleths on the composed Portugal map (mainland + island
#' insets), rendered with ggplot2 or echarts4r. Returns the renderer's native
#' object -- a `ggplot` you can extend with `+`, or an `echarts4r` widget you
#' can pipe into `e_*()` functions -- with deliberately light styling.
#'
#' @section Input forms:
#' * `plot_pt()` -- blank administrative map.
#' * `plot_pt(df, value = "cases", by = "dtmn")` -- joins `df` onto the
#'   boundaries via [get_map()] and fills by `value`.
#' * `plot_pt(m, value = "cases")` where `m` is an sf returned by
#'   [get_map()] -- renders an already-composed map directly. Build the map
#'   once, render it with several renderers.
#'
#' @section Renderers:
#' * `"ggplot"` (default): returns a `ggplot` object. Suited to static
#'   reports; style further with `+ theme(...)`, `+ labs(...)`, etc.
#' * `"echarts"`: returns an `echarts4r` htmlwidget with tooltip and roam
#'   enabled, suited to Shiny. Features are keyed internally by official
#'   code (not by name), so duplicate unit names (two "Lagoa" municipalities,
#'   196 reused freguesia names) cannot mis-map values; tooltips show the
#'   display name. Style further with `|> echarts4r::e_title(...)`, etc.
#'
#' @param data `NULL` (blank map), a data.frame to join (requires `by`), or
#'   an sf object returned by [get_map()].
#' @param value Name of the column to fill by (a column of `data`). Numeric
#'   columns get a continuous scale; character/factor columns a discrete one.
#'   `NULL` draws boundaries only.
#' @param level Administrative level, as in [get_map()]. Ignored (detected)
#'   when `data` is an sf map.
#' @param by How to join a data.frame `data`; see [get_map()].
#' @param renderer `"ggplot"` or `"echarts"`.
#' @param palette Fill palette: a vector of colors, or a single string naming
#'   a [grDevices::hcl.colors()] palette (e.g. `"Blues 3"`, `"Viridis"`).
#'   Defaults to `"Viridis"`.
#' @param na_color Fill for boundaries without a data value.
#' @param legend Logical. Show the fill legend?
#' @param ... Passed to [get_map()] (`islands`, `admin_vintage`,
#'   `nuts_vintage`, `fuzzy`, `aliases`, `client`).
#'   Ignored when `data` is already an sf map.
#'
#' @return A `ggplot` object or an `echarts4r` widget, depending on
#'   `renderer`.
#'
#' @examplesIf identical(Sys.getenv("NOT_CRAN"), "true")
#' # blank municipality map
#' plot_pt()
#'
#' df <- data.frame(concelho = c("Porto", "Lisboa"), value = c(10, 20))
#' plot_pt(df, value = "value", by = c(municipio = "concelho"))
#' plot_pt(df, value = "value", by = c(municipio = "concelho"), islands = "none")
#'
#' # Build once, render twice
#' m <- get_map("nuts3", islands = "box")
#' m$area_ha <- as.numeric(m$area_ha)
#' plot_pt(m, value = "area_ha")
#' plot_pt(m, value = "area_ha", renderer = "echarts")
#'
#' @seealso [get_map()], [island_layout()], [pt_join()]
#'
#' @export
plot_pt <- function(data = NULL,
                    value = NULL,
                    level = "municipio",
                    by = NULL,
                    renderer = "ggplot",
                    palette = NULL,
                    na_color = "grey85",
                    legend = TRUE,
                    ...) {
  if (!is.character(renderer) || length(renderer) != 1L ||
      !renderer %in% PLOT_RENDERER_NAMES) {
    stop(sprintf("`renderer` must be one of %s.",
                 quote_values(PLOT_RENDERER_NAMES)), call. = FALSE)
  }

  if (inherits(data, "sf")) {
    if (!"geopt_type" %in% names(data)) {
      stop("sf input must be a map returned by get_map().", call. = FALSE)
    }
    if (length(list(...)) > 0L) {
      warning("`...` is ignored when `data` is an already-composed sf map.",
              call. = FALSE)
    }
    m <- data
    level <- detect_map_level(m) %||% validate_map_level(level)
  } else if (is.data.frame(data)) {
    if (is.null(by)) {
      stop("`by` is required when `data` is a data.frame. Example: by = c(municipio = \"concelho\").",
           call. = FALSE)
    }
    level <- validate_map_level(level)
    m <- get_map(level, data = data, by = by, ...)
  } else if (is.null(data)) {
    level <- validate_map_level(level)
    m <- get_map(level, ...)
  } else {
    stop("`data` must be NULL, a data.frame, or an sf map from get_map().",
         call. = FALSE)
  }

  if (!is.null(value)) {
    if (!is.character(value) || length(value) != 1L) {
      stop("`value` must be a single column name.", call. = FALSE)
    }
    if (!value %in% names(m)) {
      stop(sprintf("Column '%s' not found in the map data.", value), call. = FALSE)
    }
  }

  render <- switch(renderer,
    ggplot  = render_plot_ggplot,
    echarts = render_plot_echarts
  )
  render(m, value = value, level = level,
         palette = palette, na_color = na_color, legend = legend)
}

# --- Shared helpers ----------------------------------------------------------------

#' Detect the administrative level of a composed map from its code columns
#' @noRd
detect_map_level <- function(m) {
  for (lv in PLOT_LEVEL_ORDER) {
    if (MATCH_LEVELS[[lv]]$code %in% names(m)) return(lv)
  }
  NULL
}

#' Expand the palette argument into >= n colors
#' @noRd
resolve_palette <- function(palette, n) {
  palette <- palette %||% "Viridis"
  if (length(palette) == 1L && !grepl("^#", palette)) {
    return(grDevices::hcl.colors(max(n, 2L), palette))
  }
  as.character(palette)
}

#' Normalise R colours to CSS hex for web renderers
#'
#' echarts runs in the browser, where R colour names like `"grey85"` are not
#' valid CSS colours: the canvas silently drops them and falls back to a
#' default, painting features the wrong colour. `hcl.colors()` palettes are
#' already hex, but `na_color` and user-supplied palettes may be R names, so
#' everything handed to echarts passes through here first.
#' @noRd
to_css_hex <- function(x) {
  rgb <- grDevices::col2rgb(x, alpha = FALSE)
  grDevices::rgb(rgb[1L, ], rgb[2L, ], rgb[3L, ], maxColorValue = 255)
}

#' Frame line width from geopt_frame_level
#' @noRd
frame_linewidths <- function(levels, widths = c(0.4, 0.25, 0.15)) {
  lv <- pmin(pmax(as.integer(levels), 1L), length(widths))
  widths[lv]
}

# --- ggplot renderer ------------------------------------------------------------------

#' @noRd
render_plot_ggplot <- function(m, value, level, palette, na_color, legend) {
  check_suggested_pkg("ggplot2", "for renderer = \"ggplot\"")

  boundaries <- m[m$geopt_type == "boundary", ]
  frames <- m[m$geopt_type == "frame", ]

  p <- ggplot2::ggplot()

  if (is.null(value)) {
    p <- p + ggplot2::geom_sf(
      data = boundaries,
      fill = "grey93", color = "grey45", linewidth = 0.15
    )
  } else {
    p <- p + ggplot2::geom_sf(
      data = boundaries,
      ggplot2::aes(fill = .data[[value]]),
      color = "grey45", linewidth = 0.15
    )

    v <- boundaries[[value]]
    if (is.numeric(v)) {
      cols <- resolve_palette(palette, 9L)
      p <- p + ggplot2::scale_fill_gradientn(colors = cols, na.value = na_color)
    } else {
      n <- length(unique(v[!is.na(v)]))
      cols <- resolve_palette(palette, n)
      p <- p + ggplot2::scale_fill_manual(
        values = rep_len(cols, max(n, 1L)), na.value = na_color
      )
    }
    p <- p + ggplot2::labs(fill = value)
  }

  if (nrow(frames) > 0L) {
    p <- p + ggplot2::geom_sf(
      data = frames,
      fill = NA, color = "grey30",
      linewidth = frame_linewidths(frames$geopt_frame_level)
    )
  }

  # Island labels (islands = "box"): plain geom_text at precomputed
  # coordinates, to the right of each rectangle. (geom_sf_text would warn
  # about point-on-surface on lat/lon at every render.)
  if ("geopt_label" %in% names(m)) {
    labeled <- m[m$geopt_type == "boundary" & !is.na(m$geopt_label), ]
    labeled <- labeled[!duplicated(labeled$geopt_label), ]
    if (nrow(labeled) > 0L) {
      bb <- lapply(seq_len(nrow(labeled)), function(i) sf::st_bbox(labeled[i, ]))
      lab_df <- data.frame(
        x = vapply(bb, function(b) b[["xmax"]], numeric(1L)) + 0.1,
        y = vapply(bb, function(b) (b[["ymin"]] + b[["ymax"]]) / 2, numeric(1L)),
        label = labeled$geopt_label
      )
      p <- p + ggplot2::geom_text(
        data = lab_df,
        ggplot2::aes(x = .data[["x"]], y = .data[["y"]], label = .data[["label"]]),
        size = 3, hjust = 0, color = "grey20"
      )
    }
  }

  p <- p + ggplot2::theme_void()
  if (!legend) p <- p + ggplot2::theme(legend.position = "none")
  p
}

# --- echarts renderer --------------------------------------------------------------------

#' @noRd
render_plot_echarts <- function(m, value, level, palette, na_color, legend) {
  check_suggested_pkg("echarts4r", "for renderer = \"echarts\"")
  check_suggested_pkg("htmlwidgets", "for renderer = \"echarts\"")

  # Colours reach a browser canvas here, which rejects R colour names.
  na_color <- to_css_hex(na_color)

  # Key features by official code, never by display name: names are not
  # unique (two "Lagoa" municipalities; 196 reused freguesia names).
  key_col <- MATCH_LEVELS[[level]]$code
  name_col <- MATCH_LEVELS[[level]]$name
  is_frame <- m$geopt_type == "frame"

  m$name <- NA_character_
  if (key_col %in% names(m)) m$name[!is_frame] <- m[[key_col]][!is_frame]
  # Fall back to display names where codes are missing; frames use their label
  fallback <- !is_frame & is.na(m$name) & name_col %in% names(m)
  m$name[fallback] <- m[[name_col]][fallback]
  m$name[is_frame] <- m$geopt_label[is_frame]

  display <- if (name_col %in% names(m)) m[[name_col]] else m$name
  display[is_frame] <- m$geopt_label[is_frame]

  v <- if (!is.null(value)) m[[value]] else NULL
  discrete <- !is.null(v) && !is.numeric(v)

  # Series data holds frames (transparent overlays) and the boundaries that
  # actually carry a value; no-data boundaries are OMITTED. This omission is
  # what lets the visualMap below colour the map correctly: a `map` series
  # colours regions from their data value, but regions *absent* from the data
  # are left to the series-level itemStyle (na_color). Including a no-data
  # region with a null value instead makes the visualMap paint it. Frames stay
  # in the data with no value so the visualMap ignores them and their
  # transparent itemStyle wins.
  items <- lapply(seq_len(nrow(m)), function(i) {
    if (is_frame[i]) {
      list(
        name = m$name[i],
        itemStyle = list(
          areaColor = "rgba(0,0,0,0)",
          borderColor = "#4d4d4d",
          borderWidth = frame_linewidths(m$geopt_frame_level[i], c(1.2, 0.7, 0.4))
        )
      )
    } else if (is.null(v)) {
      list(name = m$name[i], value = 0)
    } else if (is.na(v[i])) {
      NULL
    } else {
      list(name = m$name[i], value = if (discrete) as.character(v[i]) else v[i])
    }
  })
  items <- Filter(Negate(is.null), items)

  geojson <- geojsonsf::sf_geojson(m)

  # Build through echarts4r's real e_map() pipeline (which sets up the map
  # coordinate system correctly), then override the series data with our
  # code-keyed items. Hand-assembling the widget instead leaves a stray
  # cartesian axis in the options and renders a blank canvas.
  base_df <- data.frame(
    name = m$name,
    .geopt_value = if (is.null(v)) 0 else suppressWarnings(as.numeric(
      if (discrete) as.integer(factor(v)) else v
    )),
    stringsAsFactors = FALSE
  )
  e <- echarts4r::e_charts_(base_df, "name")
  e <- echarts4r::e_map_register(e, "geopt", geojson)
  e <- echarts4r::e_map_(e, ".geopt_value", map = "geopt", roam = TRUE)

  s <- length(e$x$opts$series)
  e$x$opts$series[[s]]$data <- items
  e$x$opts$series[[s]]$name <- value %||% ""
  # Series-level fill is what every no-data region (omitted from `items`)
  # renders as: a blank map keeps a light neutral, otherwise na_color.
  e$x$opts$series[[s]]$itemStyle <- list(
    areaColor = if (is.null(v)) "#ededed" else na_color,
    borderColor = "#999999", borderWidth = 0.4
  )
  # Hover: keep the region's fill (a grey-out would hide the value colour and
  # read as "selected"); just draw a darker border.
  e$x$opts$series[[s]]$emphasis <- list(
    label = list(show = FALSE),
    itemStyle = list(borderColor = "#333333", borderWidth = 1)
  )

  # Tooltip shows the display name (codes stay internal)
  lookup <- display
  names(lookup) <- m$name
  lookup <- lookup[!is.na(names(lookup)) & !duplicated(names(lookup))]
  pairs <- paste0(
    '"', gsub('"', '\\\\"', names(lookup)), '":"',
    gsub('"', '\\\\"', lookup), '"'
  )
  tooltip_js <- sprintf(
    "function(params){var m=%s;var n=m[params.name]||params.name;var v=params.value;return (v==null||v===''||(typeof v==='number'&&isNaN(v)))?n:n+': '+v;}",
    paste0("{", paste(pairs, collapse = ","), "}")
  )
  e$x$opts$tooltip <- list(
    trigger = "item",
    formatter = htmlwidgets::JS(tooltip_js)
  )

  # Legend + interactivity: a visualMap over the value range. It colours only
  # the boundaries present in the series data (no-data regions were omitted),
  # and gives the interactive range slider / hover indicator. Colours pass
  # through to_css_hex() because the browser canvas rejects R colour names.
  if (!is.null(v)) {
    if (discrete) {
      cats <- sort(unique(as.character(v[!is.na(v)])))
      cols <- to_css_hex(rep_len(resolve_palette(palette, length(cats)), length(cats)))
      vm <- list(
        type = "piecewise",
        categories = as.list(cats),
        inRange = list(color = as.list(cols)),
        show = legend
      )
    } else {
      vmin <- suppressWarnings(min(v, na.rm = TRUE))
      vmax <- suppressWarnings(max(v, na.rm = TRUE))
      vm <- list(
        type = "continuous",
        min = vmin,
        max = vmax,
        inRange = list(color = as.list(to_css_hex(resolve_palette(palette, 9L)))),
        calculable = TRUE,
        show = legend
      )
    }
    e$x$opts$visualMap <- list(vm)
  }

  # Island labels (islands = "box")
  e <- box_labels_echarts(e, m)

  e
}
