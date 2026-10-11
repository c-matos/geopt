# get_map() works entirely from the bundled datasets, so these tests are offline.

centroid_lons <- function(sf_obj) {
  cent <- suppressWarnings(sf::st_centroid(sf_obj))
  sf::st_coordinates(cent)[, 1L]
}

no_frames <- island_layout(frames = FALSE)

frame_area <- function(m, label) {
  b <- sf::st_bbox(m[m$geopt_type == "frame" & m$geopt_label %in% label, ])
  (b[["xmax"]] - b[["xmin"]]) * (b[["ymax"]] - b[["ymin"]])
}

# --- Basics ------------------------------------------------------------------

test_that("get_map returns a WGS84 sf object with geopt columns", {
  m <- get_map("nuts2")

  expect_s3_class(m, "sf")
  expect_equal(sf::st_crs(m)$epsg, 4326)
  expect_true(all(m$geopt_type %in% c("boundary", "frame")))
})

test_that("get_map validates the level", {
  expect_error(get_map("concelho"), "Invalid level")
})

test_that("get_map works for every administrative level", {
  for (level in c("municipio", "distrito", "nuts1", "nuts2", "nuts3")) {
    m <- get_map(level, islands = no_frames)
    expect_s3_class(m, "sf")
    expect_gt(nrow(m), 0)
  }
})

test_that("levels are nested: more rows at finer levels", {
  n_nuts2 <- nrow(get_map("nuts2", islands = no_frames))
  n_nuts3 <- nrow(get_map("nuts3", islands = no_frames))
  n_mun <- nrow(get_map("municipio", islands = no_frames))

  expect_lt(n_nuts2, n_nuts3)
  expect_lt(n_nuts3, n_mun)
})

# --- Output columns ------------------------------------------------------------

test_that("every map has the same columns, geopt_* last, whatever the options", {
  tail_cols <- c("geopt_type", "geopt_label", "geopt_frame_level", "geometry")
  layouts <- list("compact", "groups", "box", "in_place", "none", no_frames,
                  island_layout(raa = "in_place", ram = "whole"))
  col_sets <- lapply(layouts, function(isl) {
    m <- get_map("nuts3", islands = isl)
    n <- length(names(m))
    expect_equal(names(m)[(n - 3L):n], tail_cols)
    expect_type(m$geopt_label, "character")
    expect_type(m$geopt_frame_level, "integer")
    names(m)
  })
  for (cols in col_sets[-1L]) expect_equal(cols, col_sets[[1L]])
})

test_that("joined data columns go before the geopt columns", {
  df <- data.frame(nuts3 = "Alto Minho", v = 1)
  m <- suppressMessages(get_map("nuts3", data = df, by = "nuts3"))
  expect_lt(match("v", names(m)), match("geopt_type", names(m)))
})

test_that("every bundled boundary dataset names its geometry column 'geometry'", {
  for (lv in VALID_MAP_LEVELS) {
    d <- get_dataset(paste0("pt_", level_to_dataset(lv)))
    expect_equal(attr(d, "sf_column"), "geometry", info = lv)
  }
})

test_that("a freguesia map with frames has one geometry column", {
  # A second, stray geometry column left by binding the frames would break the
  # echarts renderer.
  m <- get_map("freguesia")
  expect_true(any(m$geopt_type == "frame"))
  expect_false("geometry" %in% names(sf::st_drop_geometry(m)))
})

# --- Islands -------------------------------------------------------------------

test_that("islands = 'none' leaves both archipelagos out", {
  full <- get_map("nuts2", islands = no_frames)
  mainland <- get_map("nuts2", islands = "none")

  expect_lt(nrow(mainland), nrow(full))
  expect_true(all(mainland$geopt_type == "boundary"))
  expect_false(any(mainland$nuts2_cod %in% c("PT20", "PT30")))
})

test_that("islands are repositioned near the mainland as insets", {
  m <- get_map("nuts2", islands = no_frames)
  # After composition all features sit near the mainland frame (lon > -12):
  # original island coordinates (lon < -16) must be gone.
  expect_true(all(centroid_lons(m) > -12))
})

test_that("one archipelago can be left out", {
  m <- get_map("nuts2", islands = island_layout(raa = "none"))
  expect_false("PT20" %in% m$nuts2_cod)
  expect_true("PT30" %in% m$nuts2_cod)
  expect_false("A\u00e7ores" %in% m$geopt_label)
  expect_true("Madeira" %in% m$geopt_label)
})

test_that("in_place keeps the islands in their true position, without frames", {
  m <- get_map("municipio", islands = "in_place")
  expect_false(any(m$geopt_type == "frame"))

  az <- m[m$nuts2_cod %in% "PT20", ]
  true_az <- get_dataset("pt_municipios")
  true_az <- true_az[true_az$nuts2_cod == "PT20", ]
  expect_equal(nrow(az), 19L)
  # The stored dataset's CRS WKT lists the datum ensemble members of the PROJ
  # that built it, so only the coordinates are compared.
  expect_equal(sf::st_bbox(az), sf::st_bbox(true_az), ignore_attr = "crs")
})

test_that("in_place combines with insets", {
  m <- get_map("municipio", islands = island_layout(raa = "in_place"))
  az <- m[m$nuts2_cod %in% "PT20", ]
  expect_lt(sf::st_bbox(az)[["xmin"]], -31)
  expect_false("A\u00e7ores" %in% m$geopt_label)
  # Madeira is still an inset, framed
  expect_true("Madeira" %in% m$geopt_label[m$geopt_type == "frame"])
  expect_true(all(centroid_lons(m[m$nuts2_cod %in% "PT30", ]) > -12))
})

# --- Frames --------------------------------------------------------------------

test_that("frames = FALSE returns only boundaries", {
  m <- get_map("nuts2", islands = no_frames)
  expect_true(all(m$geopt_type == "boundary"))
})

test_that("frames are labelled rows at three levels", {
  m <- get_map("nuts2")
  frames <- m[m$geopt_type == "frame", ]

  expect_gt(nrow(frames), 0)
  expect_true(all(c("A\u00e7ores", "Madeira") %in% frames$geopt_label))
  expect_true(all(frames$geopt_frame_level %in% 1:3))
  # Archipelago frames are level 1
  expect_true(all(
    frames$geopt_frame_level[frames$geopt_label %in% c("A\u00e7ores", "Madeira")] == 1L
  ))
  expect_true(all(sf::st_geometry_type(frames) == "MULTILINESTRING"))
  # Boundaries carry no frame level
  expect_true(all(is.na(m$geopt_frame_level[m$geopt_type == "boundary"])))
})

test_that("the default layout frames island groups and single islands", {
  m <- get_map("municipio")
  frames <- m[m$geopt_type == "frame", ]

  expect_true(all(
    c("Grupo Ocidental", "Grupo Oriental", "Santa Maria", "Porto Santo") %in%
      frames$geopt_label
  ))
})

test_that("frame rows have NA for boundary attribute columns", {
  m <- get_map("nuts2")
  frames <- sf::st_drop_geometry(m[m$geopt_type == "frame", ])
  attr_cols <- setdiff(names(frames), c("geopt_type", "geopt_label", "geopt_frame_level"))
  expect_gt(length(attr_cols), 0)
  expect_true(all(is.na(frames[, attr_cols])))
})

test_that("frames for excluded regions are not drawn", {
  m <- get_map("nuts2", islands = island_layout(ram = "none"))
  frames <- m[m$geopt_type == "frame", ]
  expect_false("Madeira" %in% frames$geopt_label)
  expect_true("A\u00e7ores" %in% frames$geopt_label)
})

# --- Presets -------------------------------------------------------------------

test_that("groups draws the A\u00e7ores in the three official groups", {
  compact <- get_map("nuts2")
  groups <- get_map("nuts2", islands = island_layout(raa = "groups"))

  # Santa Maria only gets its own inset (and frame) in "compact"
  expect_true("Santa Maria" %in% compact$geopt_label)
  expect_false("Santa Maria" %in% groups$geopt_label)
  expect_true("Grupo Oriental" %in% groups$geopt_label)
})

test_that("ram = 'whole' draws Madeira in one inset", {
  m <- get_map("nuts2", islands = island_layout(ram = "whole"))
  frames <- m[m$geopt_type == "frame", ]
  expect_false("Porto Santo" %in% frames$geopt_label)
  expect_true("Madeira" %in% frames$geopt_label)
})

test_that("'groups' means 'compact' for Madeira", {
  expect_equal(
    get_map("municipio", islands = island_layout(raa = "none", ram = "groups")),
    get_map("municipio", islands = island_layout(raa = "none", ram = "compact"))
  )
})

test_that("'compact' takes less room than 'groups' and 'whole'", {
  compact <- get_map("municipio")
  other <- get_map("municipio", islands = island_layout(raa = "groups", ram = "whole"))
  for (lab in c("A\u00e7ores", "Madeira")) {
    expect_lt(frame_area(compact, lab), frame_area(other, lab))
  }
})

# --- Box style -------------------------------------------------------------------

test_that("islands = 'box' replaces each archipelago with a labelled rectangle", {
  m <- get_map("nuts2", islands = "box")

  islands <- m[!is.na(m$geopt_label), ]
  expect_equal(sort(islands$geopt_label), sort(c("A\u00e7ores", "Madeira")))
  expect_true(all(islands$geopt_type == "boundary"))
  expect_false(any(m$geopt_type == "frame"))

  # Rectangles: 5 points forming a closed ring
  for (i in seq_len(nrow(islands))) {
    coords <- sf::st_coordinates(islands[i, ])
    expect_equal(nrow(coords), 5L)
  }

  # Attributes preserved so choropleth joins still work
  attrs <- sf::st_drop_geometry(islands)
  attrs <- attrs[, setdiff(names(attrs), c("geopt_type", "geopt_label", "geopt_frame_level")),
                 drop = FALSE]
  expect_true(all(rowSums(!is.na(attrs)) > 0))
})

test_that("box places rectangles at a numeric position", {
  m <- get_map("nuts2", islands = island_layout("box", box_position = c(-20, 45)))
  islands <- m[!is.na(m$geopt_label), ]

  b <- sf::st_bbox(islands)
  expect_equal(unname(b["xmin"]), -20)
  expect_equal(unname(b["ymin"]), 45)
})

test_that("box supports position presets", {
  for (pos in c("bottom_left", "top_left")) {
    m <- get_map("nuts2", islands = island_layout("box", box_position = pos))
    islands <- m[!is.na(m$geopt_label), ]
    expect_equal(nrow(islands), 2L)
    # Boxes sit left of the mainland
    mainland <- m[is.na(m$geopt_label), ]
    expect_lt(sf::st_bbox(islands)["xmax"], sf::st_bbox(mainland)["xmin"] + 0.01)
  }
})

test_that("top_left and bottom_left stacks have the same height", {
  # Both stacks include the gap between the archipelagos, so they are the same
  # height.
  stack <- function(pos) {
    m <- get_map("nuts2", islands = island_layout("box", box_position = pos))
    list(islands = sf::st_bbox(m[!is.na(m$geopt_label), ]),
         mainland = sf::st_bbox(m[is.na(m$geopt_label), ]))
  }
  bl <- stack("bottom_left")
  tl <- stack("top_left")
  expect_equal(tl$islands[["ymax"]] - tl$islands[["ymin"]],
               bl$islands[["ymax"]] - bl$islands[["ymin"]])
  expect_equal(tl$islands[["ymax"]], tl$mainland[["ymax"]] - 1)
})

test_that("box respects archipelagos left out", {
  m <- get_map("nuts2", islands = island_layout("box", raa = "none"))
  islands <- m[!is.na(m$geopt_label), ]
  expect_equal(islands$geopt_label, "Madeira")
})

test_that("box draws one rectangle per archipelago, and stops otherwise", {
  expect_error(get_map("uls", islands = "box"),
               "the A\u00e7ores have 9 units and Madeira has 7 units")
  expect_error(get_map("municipio", islands = "box"), "one rectangle")
  expect_error(get_map("freguesia", islands = "box"), "one rectangle")
  expect_error(get_map("distrito", islands = island_layout("box", ram = "none")),
               "the A\u00e7ores have 9 units\\.")
  for (level in c("nuts1", "nuts2", "nuts3", "reg_saude")) {
    m <- get_map(level, islands = "box")
    expect_equal(sum(!is.na(m$geopt_label)), 2L, info = level)
  }
})

# --- Joins with islands left out ---------------------------------------------------

test_that("data for archipelagos left out is not reported as unmatched", {
  # 1106 Lisboa, 4201 Lagoa (Açores)
  df <- data.frame(dtmn = c("1106", "4201"), v = 1:2)
  expect_no_warning(
    m <- suppressMessages(get_map("municipio", islands = "none", data = df, by = "dtmn"))
  )
  expect_equal(sum(!is.na(m$v)), 1L)

  # A row that matches nothing still warns
  df2 <- data.frame(municipio = c("Lisboa", "Nowhere"), v = 1:2)
  w <- capture_warnings(suppressMessages(
    get_map("municipio", islands = "none", data = df2, by = "municipio")
  ))
  expect_match(w, "did not match any boundary", all = FALSE)
})
