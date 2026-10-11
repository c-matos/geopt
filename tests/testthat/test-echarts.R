# --- frame_data_echarts --------------------------------------------------------

make_map_with_values <- function() {
  m <- get_map("nuts2")
  m$val <- seq_len(nrow(m))
  m
}

test_that("frame_data_echarts returns one entry per feature", {
  m <- make_map_with_values()
  out <- frame_data_echarts(m, "val")

  expect_type(out, "list")
  expect_length(out, nrow(m))
})

test_that("frame_data_echarts styles frames and keeps values for boundaries", {
  m <- make_map_with_values()
  out <- frame_data_echarts(m, "val", level_widths = c(2, 1, 0.5))

  is_frame <- m$geopt_type == "frame"

  for (i in which(!is_frame)) {
    expect_equal(out[[i]]$value, m$val[i])
    expect_null(out[[i]]$itemStyle)
  }

  for (i in which(is_frame)) {
    entry <- out[[i]]
    expect_equal(entry$value, 0)
    expect_equal(entry$itemStyle$areaColor, "rgba(0,0,0,0)")
    lvl <- m$geopt_frame_level[i]
    expect_equal(entry$itemStyle$borderWidth, c(2, 1, 0.5)[lvl])
  }
})

test_that("frame_data_echarts falls back to 0.2 width for deep frame levels", {
  m <- make_map_with_values()
  is_frame <- m$geopt_type == "frame"
  out <- frame_data_echarts(m, "val", level_widths = c(5))

  deep <- which(is_frame & m$geopt_frame_level > 1)
  skip_if(length(deep) == 0, "no deep frames in this layout")
  expect_equal(out[[deep[1]]]$itemStyle$borderWidth, 0.2)
})

test_that("frame_data_echarts prefers a 'name' column when present", {
  m <- make_map_with_values()
  m$name <- paste0("feat_", seq_len(nrow(m)))
  out <- frame_data_echarts(m, "val")
  expect_equal(out[[1]]$name, "feat_1")

  # Without 'name', geopt_label is used (NA for boundaries, name for frames)
  m$name <- NULL
  out <- frame_data_echarts(m, "val")
  i_frame <- which(m$geopt_type == "frame")[1]
  expect_equal(out[[i_frame]]$name, m$geopt_label[i_frame])
})

test_that("frame_data_echarts sets custom border color", {
  m <- make_map_with_values()
  out <- frame_data_echarts(m, "val", border_color = "#ff0000")
  i_frame <- which(m$geopt_type == "frame")[1]
  expect_equal(out[[i_frame]]$itemStyle$borderColor, "#ff0000")
})

# --- box_labels_echarts -----------------------------------------------------------

mock_echarts_widget <- function(n_series = 1L) {
  series <- replicate(n_series, list(type = "map"), simplify = FALSE)
  list(x = list(opts = list(series = series)))
}

test_that("box_labels_echarts injects a label config into the last series", {
  skip_if_not_installed("htmlwidgets")

  m <- get_map("nuts3", islands = "box")
  m$name <- ifelse(is.na(m$geopt_label), "mainland", m$geopt_label)
  e <- mock_echarts_widget(n_series = 2L)

  out <- box_labels_echarts(e, m, font_size = 14, color = "#000")

  label <- out$x$opts$series[[2]]$label
  expect_false(is.null(label))
  expect_true(label$show)
  expect_equal(label$fontSize, 14)
  expect_equal(label$color, "#000")
  expect_s3_class(label$formatter, "JS_EVAL")
  # The JS lookup embeds the label texts
  expect_match(as.character(label$formatter), "Madeira")
  # First series untouched
  expect_null(out$x$opts$series[[1]]$label)
})

test_that("box_labels_echarts passes extra echarts properties through", {
  skip_if_not_installed("htmlwidgets")

  m <- get_map("nuts3", islands = "box")
  m$name <- ifelse(is.na(m$geopt_label), "mainland", m$geopt_label)
  e <- mock_echarts_widget()

  out <- box_labels_echarts(e, m, fontWeight = "bold")
  expect_equal(out$x$opts$series[[1]]$label$fontWeight, "bold")
})

test_that("box_labels_echarts is a no-op without labels", {
  e <- mock_echarts_widget()

  # No geopt_label column at all
  m <- get_map("nuts2", islands = island_layout(frames = FALSE))
  m$geopt_label <- NULL
  expect_identical(box_labels_echarts(e, m), e)

  # Column present but all NA
  m <- get_map("nuts2", islands = "none")
  expect_identical(box_labels_echarts(e, m), e)

  # Frames carry their name in geopt_label, but are not labelled
  m <- get_map("nuts2")
  expect_true(any(!is.na(m$geopt_label)))
  expect_identical(box_labels_echarts(e, m), e)
})
