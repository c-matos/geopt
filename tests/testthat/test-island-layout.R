# island_layout() and the `islands` argument of get_map(). Offline.

# --- Construction --------------------------------------------------------------

test_that("the default layout is compact for both archipelagos", {
  lay <- island_layout()

  expect_s3_class(lay, "geopt_island_layout")
  expect_equal(lay$raa$show, "inset")
  expect_equal(lay$raa$preset, "compact")
  expect_named(lay$raa$groups, c("ocidental", "central", "s_miguel", "s_maria"))
  expect_named(lay$ram$groups, c("madeira", "porto_santo"))
  expect_true(lay$frames)
})

test_that("`both` sets both archipelagos and raa/ram override it", {
  lay <- island_layout("groups")
  expect_equal(c(lay$raa$preset, lay$ram$preset), c("groups", "groups"))
  expect_named(lay$raa$groups, c("ocidental", "central", "oriental"))

  lay <- island_layout("none", ram = "whole")
  expect_equal(c(lay$raa$show, lay$ram$show), c("none", "inset"))
  expect_named(lay$ram$groups, "madeira")
})

test_that("a string for `islands` is shorthand for island_layout()", {
  for (value in c("compact", "groups", "box", "in_place", "none")) {
    expect_equal(get_map("nuts3", islands = value),
                 get_map("nuts3", islands = island_layout(value)),
                 info = value)
  }
})

# --- Errors ----------------------------------------------------------------------

test_that("unknown values list the valid ones", {
  expect_error(island_layout("tiny"), "`both` must be one of \"compact\", \"groups\"")
  expect_error(island_layout(raa = "tiny"), "`raa` must be one of")
  expect_error(island_layout(ram = 1), "`ram` must be a single value")
  expect_error(get_map("nuts3", islands = "tiny"), "`islands` must be one of")
  expect_error(get_map("nuts3", islands = list(raa = "compact")),
               "made with island_layout\\(\\)")
})

test_that("'whole' is available for Madeira only", {
  expect_error(island_layout(raa = "whole"), "can't be drawn as one inset")
  expect_error(island_layout("whole"), "`both = \"whole\"` isn't available")
  expect_error(get_map("nuts3", islands = "whole"), "`islands = \"whole\"`")
  expect_equal(island_layout(ram = "whole")$ram$preset, "whole")
})

test_that("box can't be combined with insets", {
  expect_error(island_layout(raa = "box"), "can't be combined with insets")
  expect_silent(island_layout("box", ram = "none"))
  expect_silent(island_layout(raa = "box", ram = "in_place"))
})

test_that("frames and box_position are checked", {
  expect_error(island_layout(frames = NA), "TRUE or FALSE")
  expect_error(island_layout("box", box_position = "middle"), "box_position")
  expect_error(island_layout("box", box_position = 1), "box_position")
})

# --- Warnings --------------------------------------------------------------------

test_that("arguments with no effect warn, but only when given", {
  expect_warning(island_layout("none", frames = FALSE), "`frames` has no effect")
  expect_warning(island_layout("box", frames = TRUE), "`frames` has no effect")
  expect_warning(island_layout(box_position = "top_left"),
                 "`box_position` has no effect")
  expect_silent(island_layout("box", box_position = "top_left"))
  expect_silent(island_layout(frames = FALSE))
  expect_silent(island_layout("none"))
  expect_silent(get_map("nuts3", islands = "box"))
})

# --- Editing -----------------------------------------------------------------------

test_that("an edited layout moves and relabels the islands", {
  frames_of <- function(m) m[m$geopt_type == "frame", ]
  az_frame <- function(m) sf::st_bbox(m[m$geopt_label %in% "A\u00e7ores", ])

  base <- get_map("nuts3")
  lay <- island_layout()
  lay$raa$anchor <- lay$raa$anchor + c(-0.5, 0)
  moved <- get_map("nuts3", islands = lay)
  expect_equal(az_frame(moved)[["xmin"]], az_frame(base)[["xmin"]] - 0.5)

  lay$raa$label <- "Azores"
  relabelled <- get_map("nuts3", islands = lay)
  expect_true("Azores" %in% frames_of(relabelled)$geopt_label)
  expect_false("A\u00e7ores" %in% relabelled$geopt_label)

  # A smaller Madeira gets a smaller frame
  madeira_width <- function(m) {
    b <- sf::st_bbox(m[m$geopt_label %in% "Madeira", ])
    b[["xmax"]] - b[["xmin"]]
  }
  lay <- island_layout()
  lay$ram$groups$madeira$scale <- 2.5
  expect_lt(madeira_width(get_map("nuts3", islands = lay)), madeira_width(base))
})

test_that("an edited box label is used on the rectangle", {
  lay <- island_layout("box")
  lay$raa$label <- "Azores"
  m <- get_map("nuts2", islands = lay)
  expect_setequal(m$geopt_label[!is.na(m$geopt_label)], c("Azores", "Madeira"))
})

test_that("a broken edit is caught with a clear message", {
  lay <- island_layout()
  lay$raa$anchor <- "west"
  expect_error(get_map("nuts3", islands = lay), "`raa` layout is not valid: `anchor`")

  lay <- island_layout()
  lay$ram$groups$madeira$offset <- 1
  expect_error(get_map("nuts3", islands = lay), "groups\\$madeira\\$offset")

  lay <- island_layout()
  lay$raa$show <- "box"
  expect_error(get_map("nuts3", islands = lay), "can't be combined with insets")
})

test_that("a custom region config can be passed as raa or ram", {
  custom <- list(
    anchor = c(-10.5, 37.5),
    groups = list(all = list(offset = c(0, 0), scale = 2))
  )
  lay <- island_layout(ram = custom)
  expect_equal(lay$ram$preset, "custom")
  expect_equal(lay$ram$label, "Madeira")

  m <- get_map("municipio", islands = lay)
  mad <- m[m$nuts2_cod %in% "PT30", ]
  expect_equal(nrow(mad), 11L)
  # The whole archipelago (no crop), centred on the anchor
  b <- sf::st_bbox(mad)
  expect_equal(c((b[["xmin"]] + b[["xmax"]]) / 2, (b[["ymin"]] + b[["ymax"]]) / 2),
               c(-10.5, 37.5))
  expect_true("Madeira" %in% m$geopt_label[m$geopt_type == "frame"])
})

# --- Printing -------------------------------------------------------------------------

test_that("print shows what each archipelago does", {
  expect_output(print(island_layout()),
                "raa \\(A\u00e7ores\\):\\s+compact\\s+4 insets: ocidental, central, s_miguel, s_maria")
  expect_output(print(island_layout()), "frames:\\s+yes")
  expect_output(print(island_layout(ram = "whole")), "whole\\s+1 inset: madeira")
  expect_output(print(island_layout("box", box_position = c(-20, 45))),
                "box position:\\s+c\\(-20, 45\\)")
  expect_output(print(island_layout("none")), "left out")
  expect_output(print(island_layout("in_place")), "in its true position")
})
