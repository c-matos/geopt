unit_square_sf <- function(x0 = 0, y0 = 0, w = 1, h = 1, crs = 4326) {
  poly <- sf::st_polygon(list(matrix(
    c(x0, y0, x0 + w, y0, x0 + w, y0 + h, x0, y0 + h, x0, y0),
    ncol = 2, byrow = TRUE
  )))
  sf::st_sf(name = "sq", geometry = sf::st_sfc(poly, crs = crs))
}

bbox_center <- function(obj) {
  b <- sf::st_bbox(obj)
  c(unname((b["xmin"] + b["xmax"]) / 2), unname((b["ymin"] + b["ymax"]) / 2))
}

# --- offset_geometry -----------------------------------------------------------

test_that("offset_geometry recenters geometry at the target position", {
  obj <- unit_square_sf(x0 = 10, y0 = 20)
  out <- offset_geometry(obj, x_offset = -5, y_offset = 3)

  expect_equal(bbox_center(out), c(-5, 3))
  # Size unchanged with scale = 1
  b <- sf::st_bbox(out)
  expect_equal(unname(b["xmax"] - b["xmin"]), 1)
  expect_equal(unname(b["ymax"] - b["ymin"]), 1)
})

test_that("offset_geometry scales around the center", {
  obj <- unit_square_sf()
  out <- offset_geometry(obj, x_offset = 0, y_offset = 0, scale = 3)

  b <- sf::st_bbox(out)
  expect_equal(unname(b["xmax"] - b["xmin"]), 3)
  expect_equal(unname(b["ymax"] - b["ymin"]), 3)
  expect_equal(bbox_center(out), c(0, 0))
})

test_that("offset_geometry preserves CRS and attributes", {
  obj <- unit_square_sf(crs = 3763)
  obj$value <- 42
  out <- offset_geometry(obj, 100, 200, scale = 2)

  expect_equal(sf::st_crs(out), sf::st_crs(3763))
  expect_equal(out$value, 42)
  expect_equal(out$name, "sq")
})

# --- offset_group ----------------------------------------------------------------

test_that("offset_group positions each group at anchor + offset", {
  groups <- list(
    a = list(sf = unit_square_sf(), offset = c(1, 1)),
    b = list(sf = unit_square_sf(x0 = 50, y0 = 50), offset = c(-2, 0), scale = 2)
  )
  out <- offset_group(groups, anchor = c(-10, 40))

  expect_named(out, c("a", "b"))
  expect_equal(bbox_center(out$a), c(-9, 41))
  expect_equal(bbox_center(out$b), c(-12, 40))

  # b was scaled 2x
  b <- sf::st_bbox(out$b)
  expect_equal(unname(b["xmax"] - b["xmin"]), 2)
})

test_that("offset_group defaults scale to 1", {
  groups <- list(a = list(sf = unit_square_sf(), offset = c(0, 0)))
  out <- offset_group(groups, anchor = c(0, 0))
  b <- sf::st_bbox(out$a)
  expect_equal(unname(b["xmax"] - b["xmin"]), 1)
})

# --- bbox_around -------------------------------------------------------------------

test_that("bbox_around buffers the bounding box of one object", {
  obj <- unit_square_sf()
  box <- bbox_around(obj, buffer = 0.5)

  expect_s3_class(box, "sfc")
  expect_length(box, 1L)
  b <- sf::st_bbox(box)
  expect_equal(unname(b["xmin"]), -0.5)
  expect_equal(unname(b["ymin"]), -0.5)
  expect_equal(unname(b["xmax"]), 1.5)
  expect_equal(unname(b["ymax"]), 1.5)
})

test_that("bbox_around spans multiple objects", {
  box <- bbox_around(unit_square_sf(), unit_square_sf(x0 = 9, y0 = 9), buffer = 0)
  b <- sf::st_bbox(box)
  expect_equal(unname(b["xmin"]), 0)
  expect_equal(unname(b["xmax"]), 10)
  expect_equal(unname(b["ymax"]), 10)
})

test_that("bbox_around accepts sfc inputs and preserves CRS", {
  geom <- sf::st_geometry(unit_square_sf(crs = 3763))
  box <- bbox_around(geom, buffer = 0.1)
  expect_equal(sf::st_crs(box), sf::st_crs(3763))
})
