# All tests here are offline: they cover validation, URL/query construction,
# and cache-key hashing. Network behaviour (pagination, live collections) is
# exercised by test-network.R.

# --- Collection validation -----------------------------------------------------

test_that("validate_ogc_collection returns metadata for known feature collections", {
  meta <- validate_ogc_collection("municipios")
  expect_equal(meta$type, "feature")
  expect_false(meta$requires_filter)

  meta <- validate_ogc_collection("cadastro")
  expect_true(meta$requires_filter)
})

test_that("validate_ogc_collection rejects unknown collections", {
  expect_error(validate_ogc_collection("nope"), "Unknown OGC collection")
  expect_error(validate_ogc_collection(c("a", "b")), "single character string")
  expect_error(validate_ogc_collection(1L), "single character string")
})

test_that("validate_ogc_collection rejects coverage collections", {
  expect_error(validate_ogc_collection("ortos-rgb"), "coverage")
  expect_error(validate_ogc_collection("cosc2022"), "coverage")
})

# --- bbox validation -------------------------------------------------------------

test_that("validate_bbox passes through NULL and valid vectors", {
  expect_null(validate_bbox(NULL))
  expect_equal(validate_bbox(c(-9.5, 38.6, -9.0, 38.9)), c(-9.5, 38.6, -9.0, 38.9))
})

test_that("validate_bbox accepts sf bbox objects", {
  obj <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_polygon(list(matrix(c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE))),
    crs = 4326
  ))
  out <- validate_bbox(sf::st_bbox(obj))
  expect_equal(out, c(0, 0, 1, 1))
})

test_that("validate_bbox rejects malformed input", {
  expect_error(validate_bbox(c(1, 2, 3)), "length 4")
  expect_error(validate_bbox(c(1, 2, 3, NA)), "length 4")
  expect_error(validate_bbox("a bbox"), "length 4")
  # xmin >= xmax
  expect_error(validate_bbox(c(2, 0, 1, 1)), "xmin < xmax")
  # ymin >= ymax
  expect_error(validate_bbox(c(0, 2, 1, 1)), "xmin < xmax")
})

# --- URL helpers ------------------------------------------------------------------

test_that("build_ogc_items_url and ogc_crs_uri build canonical strings", {
  expect_equal(
    build_ogc_items_url("municipios"),
    "https://ogcapi.dgterritorio.gov.pt/collections/municipios/items"
  )
  expect_equal(ogc_crs_uri(3763), "http://www.opengis.net/def/crs/EPSG/0/3763")
  expect_equal(ogc_crs_uri("4326"), "http://www.opengis.net/def/crs/EPSG/0/4326")
})

# --- Query construction -----------------------------------------------------------

test_that("build_ogc_query defaults include limit and json format only", {
  params <- build_ogc_query()
  expect_identical(params$limit, OGC_DEFAULT_LIMIT)
  expect_equal(params$f, "json")
  expect_setequal(names(params), c("limit", "f"))
})

test_that("build_ogc_query serializes bbox and adds bbox-crs only when non-4326", {
  params <- build_ogc_query(bbox = c(-9.5, 38.6, -9.0, 38.9))
  expect_equal(params$bbox, "-9.5,38.6,-9,38.9")
  expect_false("bbox-crs" %in% names(params))

  params <- build_ogc_query(bbox = c(0, 0, 1, 1), bbox_crs = 3763L)
  expect_equal(params[["bbox-crs"]], "http://www.opengis.net/def/crs/EPSG/0/3763")
})

test_that("build_ogc_query requests server-side CRS", {
  params <- build_ogc_query(crs = 3763L)
  expect_equal(params$crs, "http://www.opengis.net/def/crs/EPSG/0/3763")
})

test_that("build_ogc_query passes CQL filters with cql-text language", {
  params <- build_ogc_query(cql_filter = "distrito = 'Lisboa'")
  expect_equal(params$filter, "distrito = 'Lisboa'")
  expect_equal(params[["filter-lang"]], "cql-text")

  expect_error(build_ogc_query(cql_filter = c("a", "b")), "single CQL-Text string")
  expect_error(build_ogc_query(cql_filter = 42), "single CQL-Text string")
})

test_that("build_ogc_query passes properties as equality query params", {
  params <- build_ogc_query(properties = list(distrito = "Lisboa", tipo = 3))
  expect_equal(params$distrito, "Lisboa")
  expect_equal(params$tipo, "3")
})

test_that("build_ogc_query validates properties", {
  expect_error(build_ogc_query(properties = list("Lisboa")), "named list")
  expect_error(build_ogc_query(properties = c(distrito = "Lisboa")), "named list")
  expect_error(
    build_ogc_query(properties = list(distrito = c("Lisboa", "Porto"))),
    "length 1"
  )
})

test_that("build_ogc_query coerces limit to integer", {
  params <- build_ogc_query(limit = 500)
  expect_identical(params$limit, 500L)
})

# --- Cache keys --------------------------------------------------------------------

test_that("ogc_cache_key is stable under parameter order", {
  p1 <- list(bbox = "0,0,1,1", limit = 1000L, f = "json")
  p2 <- list(limit = 1000L, f = "json", bbox = "0,0,1,1")
  expect_equal(ogc_cache_key("municipios", p1, 4326L), ogc_cache_key("municipios", p2, 4326L))
})

test_that("ogc_cache_key changes with collection, params, and crs", {
  p <- list(bbox = "0,0,1,1", limit = 1000L, f = "json")
  base <- ogc_cache_key("municipios", p, 4326L)

  expect_false(ogc_cache_key("freguesias", p, 4326L) == base)
  expect_false(ogc_cache_key("municipios", p, 3763L) == base)

  p2 <- p
  p2$bbox <- "0,0,2,2"
  expect_false(ogc_cache_key("municipios", p2, 4326L) == base)
})

test_that("ogc_cache_key ignores the f parameter and names an rds file", {
  p1 <- list(bbox = "0,0,1,1", limit = 1000L, f = "json")
  p2 <- list(bbox = "0,0,1,1", limit = 1000L)
  expect_equal(ogc_cache_key("municipios", p1, 4326L), ogc_cache_key("municipios", p2, 4326L))
  expect_match(ogc_cache_key("municipios", p1, 4326L), "^ogc_municipios_.*\\.rds$")
})
