# plot_pt() and its renderers. Offline: both renderers build objects without
# drawing them.

demo_df <- function() {
  data.frame(concelho = c("Porto", "Lisboa", "Faro"), score = c(1, 5, 9))
}

# --- Input dispatch -----------------------------------------------------------------

test_that("plot_pt draws a blank map with no data", {
  skip_if_not_installed("ggplot2")
  p <- plot_pt()
  expect_s3_class(p, "ggplot")
})

test_that("plot_pt joins a data.frame via by", {
  skip_if_not_installed("ggplot2")
  p <- suppressMessages(
    plot_pt(demo_df(), value = "score", by = c(municipio = "concelho"))
  )
  expect_s3_class(p, "ggplot")

  expect_error(plot_pt(demo_df(), value = "score"), "`by` is required")
})

test_that("plot_pt accepts a prebuilt get_map() sf", {
  skip_if_not_installed("ggplot2")
  m <- suppressMessages(
    get_map("nuts2", data = data.frame(nuts2 = "Norte", v = 1), by = "nuts2")
  )
  p <- plot_pt(m, value = "v")
  expect_s3_class(p, "ggplot")

  # ... is ignored (with a warning) for prebuilt maps
  expect_warning(plot_pt(m, value = "v", islands = "none"), "ignored")

  # Non-get_map sf is rejected
  plain <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(0, 0)), crs = 4326))
  expect_error(plot_pt(plain), "get_map")
})

test_that("plot_pt passes islands on to get_map", {
  skip_if_not_installed("ggplot2")
  p <- plot_pt(level = "nuts2", islands = "none")
  expect_false(any(p$layers[[1]]$data$nuts2_cod %in% c("PT20", "PT30")))
})

test_that("plot_pt draws a map filtered to one region", {
  skip_if_not_installed("ggplot2")
  m <- get_map("municipio")
  norte <- m[m$nuts2_cod %in% "PT11", ]
  p <- plot_pt(norte, value = "area_ha")
  expect_s3_class(ggplot2::ggplot_build(p), "ggplot_built")
})

test_that("plot_pt validates renderer, value and data", {
  expect_error(plot_pt(renderer = "tmap"),
               "`renderer` must be one of \"ggplot\" or \"echarts\"")
  expect_error(plot_pt(renderer = c("ggplot", "echarts")), "`renderer` must be one of")
  expect_error(plot_pt(value = "nope"), "not found")
  expect_error(plot_pt(value = c("a", "b")), "single column")
  expect_error(plot_pt(data = 1L), "must be NULL")
})

# --- ggplot renderer -------------------------------------------------------------------

test_that("ggplot renderer separates boundaries and island labels", {
  skip_if_not_installed("ggplot2")

  m <- get_map("nuts3", islands = "box")
  m$val <- seq_len(nrow(m))
  p <- plot_pt(m, value = "val")

  # boundary fill layer + island label layer (no frames in box style)
  expect_gte(length(p$layers), 2L)

  built <- ggplot2::ggplot_build(p)
  expect_s3_class(built, "ggplot_built")

  # Legend titled by the value column
  expect_equal(p$labels$fill, "val")
})

test_that("ggplot renderer handles discrete values and legend = FALSE", {
  skip_if_not_installed("ggplot2")

  df <- data.frame(nuts2 = c("Norte", "Centro"), grp = c("a", "b"))
  p <- suppressMessages(
    plot_pt(df, value = "grp", level = "nuts2", by = "nuts2", legend = FALSE)
  )
  built <- ggplot2::ggplot_build(p)
  expect_s3_class(built, "ggplot_built")
  expect_equal(p$theme$legend.position, "none")
})

test_that("ggplot renderer draws frame overlays for the inset style", {
  skip_if_not_installed("ggplot2")
  p <- plot_pt(level = "nuts2")
  # blank fill layer + frames layer
  expect_gte(length(p$layers), 2L)
  # no island labels: frames are named, but only rectangles get labels
  expect_false(any(vapply(p$layers, function(l) inherits(l$geom, "GeomText"),
                          logical(1L))))
})

# --- echarts renderer ---------------------------------------------------------------------

test_that("echarts renderer keys features by code, not name", {
  skip_if_not_installed("echarts4r")
  skip_if_not_installed("htmlwidgets")

  m <- suppressMessages(get_map("municipio", islands = island_layout(frames = FALSE)))
  m$val <- seq_len(nrow(m))
  e <- plot_pt(m, value = "val", renderer = "echarts")

  expect_s3_class(e, "echarts4r")
  series <- e$x$opts$series[[1]]
  expect_equal(series$type, "map")
  expect_true(series$roam)
  expect_equal(length(series$data), nrow(m))

  # The geojson must be registered on the widget, and the options must NOT
  # carry a cartesian axis: a stray x/yAxis makes the map render blank.
  expect_false(is.null(e$x$registerMap))
  expect_equal(e$x$registerMap[[1]]$mapName, "geopt")
  expect_equal(series$map, "geopt")
  expect_null(e$x$opts$xAxis)
  expect_null(e$x$opts$yAxis)

  item_names <- vapply(series$data, `[[`, character(1L), "name")
  # Keys are the 4-digit DTMN codes -> both Lagoas are distinct
  expect_true(all(grepl("^[0-9]{4}$", item_names)))
  expect_false(anyDuplicated(item_names) > 0)

  # Continuous visual map present with min/max (every feature has a value
  # here, so none are omitted).
  vm <- e$x$opts$visualMap[[1]]
  expect_equal(vm$type, "continuous")
  expect_equal(vm$min, 1)
  expect_equal(vm$max, nrow(m))
  # visualMap colours are CSS hex, not R colour names
  expect_true(all(grepl("^#", unlist(vm$inRange$color))))

  # Tooltip formatter carries display names
  expect_s3_class(e$x$opts$tooltip$formatter, "JS_EVAL")
  expect_match(as.character(e$x$opts$tooltip$formatter), "Porto")
})

test_that("echarts renderer supports blank, discrete, NA, and frames", {
  skip_if_not_installed("echarts4r")
  skip_if_not_installed("htmlwidgets")

  # Blank: no visualMap
  e <- plot_pt(level = "nuts2", renderer = "echarts")
  expect_null(e$x$opts$visualMap)

  # Frames become transparent overlay items
  m <- get_map("nuts2")
  m$val <- seq_len(nrow(m))
  e <- plot_pt(m, value = "val", renderer = "echarts")
  data_items <- e$x$opts$series[[1]]$data
  frame_items <- Filter(function(d) !is.null(d$itemStyle) &&
                          identical(d$itemStyle$areaColor, "rgba(0,0,0,0)"),
                        data_items)
  expect_equal(length(frame_items), sum(m$geopt_type == "frame"))

  # Discrete: piecewise visual map with categories; legend = FALSE hides it
  m2 <- suppressMessages(get_map("nuts2", islands = island_layout(frames = FALSE)))
  m2$grp <- rep_len(c("low", "high"), nrow(m2))
  e2 <- plot_pt(m2, value = "grp", renderer = "echarts", legend = FALSE)
  vm <- e2$x$opts$visualMap[[1]]
  expect_equal(vm$type, "piecewise")
  expect_setequal(unlist(vm$categories), c("low", "high"))
  expect_false(vm$show)

  # NA values are omitted from the data (so the visual map can't paint them)
  # and render at the series-level na_color instead.
  m2$grp2 <- c(NA, rep("x", nrow(m2) - 1L))
  e3 <- plot_pt(m2, value = "grp2", renderer = "echarts", na_color = "#123456")
  expect_equal(e3$x$opts$series[[1]]$itemStyle$areaColor, "#123456")
  expect_equal(length(e3$x$opts$series[[1]]$data), sum(!is.na(m2$grp2)))
})

test_that("echarts renderer converts R colour names to CSS hex", {
  skip_if_not_installed("echarts4r")
  skip_if_not_installed("htmlwidgets")

  # "grey85" is a valid R colour but NOT a valid CSS colour: passed through
  # verbatim the browser canvas drops it. It must reach echarts as hex.
  m <- suppressMessages(get_map("nuts2", islands = island_layout(frames = FALSE)))
  m$val <- c(NA, seq_len(nrow(m) - 1L))
  e <- plot_pt(m, value = "val", renderer = "echarts")  # default na_color grey85
  expect_equal(e$x$opts$series[[1]]$itemStyle$areaColor, to_css_hex("grey85"))
  expect_match(e$x$opts$series[[1]]$itemStyle$areaColor, "^#")
})

test_that("echarts renderer injects island labels for box style", {
  skip_if_not_installed("echarts4r")
  skip_if_not_installed("htmlwidgets")

  m <- get_map("nuts3", islands = "box")
  m$val <- seq_len(nrow(m))
  e <- plot_pt(m, value = "val", renderer = "echarts")
  label <- e$x$opts$series[[1]]$label
  expect_false(is.null(label))
  expect_true(label$show)
})

test_that("echarts renderer draws freguesia maps with frames", {
  skip_if_not_installed("echarts4r")
  skip_if_not_installed("htmlwidgets")

  e <- plot_pt(level = "freguesia", renderer = "echarts")
  expect_s3_class(e, "echarts4r")
})

# --- Shared helpers ---------------------------------------------------------------------------

test_that("resolve_palette expands names and passes through vectors", {
  expect_length(resolve_palette(NULL, 5L), 5L)
  expect_length(resolve_palette("Blues 3", 7L), 7L)
  expect_equal(resolve_palette(c("#000000", "#ffffff"), 9L),
               c("#000000", "#ffffff"))
})

test_that("detect_map_level picks the most specific code column", {
  expect_equal(detect_map_level(get_dataset("pt_municipios")), "municipio")
  expect_equal(detect_map_level(get_dataset("pt_nuts2")), "nuts2")
  expect_equal(detect_map_level(get_dataset("pt_freguesias")), "freguesia")
})
