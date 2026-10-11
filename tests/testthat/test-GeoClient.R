# Offline tests: construction, cache management, validation paths, and export.
# Network-dependent behaviour (CAOP download, OGC fetch) is covered by
# test-network.R.

# --- Construction and fields -----------------------------------------------------

test_that("GeoClient initializes with defaults and creates cache dirs", {
  cache_dir <- withr::local_tempdir()
  client <- GeoClient$new(cache_dir = cache_dir)

  expect_equal(client$cache_dir, cache_dir)
  expect_true(client$use_cache)
  expect_identical(client$crs, DEFAULT_CRS)
  expect_true(dir.exists(file.path(cache_dir, "raw")))
  expect_true(dir.exists(file.path(cache_dir, "processed")))
})

test_that("active bindings validate assignments", {
  client <- local_client()

  new_dir <- withr::local_tempdir()
  client$cache_dir <- new_dir
  expect_equal(client$cache_dir, new_dir)
  expect_true(dir.exists(file.path(new_dir, "raw")))
  expect_error(client$cache_dir <- 1L, "single character string")
  expect_error(client$cache_dir <- c("a", "b"), "single character string")

  client$use_cache <- FALSE
  expect_false(client$use_cache)
  expect_error(client$use_cache <- "yes", "single logical")
  expect_error(client$use_cache <- c(TRUE, FALSE), "single logical")

  client$crs <- 3763
  expect_identical(client$crs, 3763L)
})

test_that("print summarizes the client", {
  client <- local_client()
  expect_output(print(client), "<GeoClient>")
  expect_output(print(client), "EPSG:4326")
  expect_output(print(client), "0 processed, 0 raw")
})

# --- Cache management -----------------------------------------------------------

test_that("list_cached and clear_cache reflect cache contents", {
  client <- local_client()
  processed_dir <- file.path(client$cache_dir, "processed")
  raw_dir <- file.path(client$cache_dir, "raw")

  saveRDS(1, file.path(processed_dir, "continente_municipio_2024_full.rds"))
  file.create(file.path(raw_dir, "Continente_CAOP2024.gpkg"))

  cached <- client$list_cached()
  expect_equal(cached$processed, "continente_municipio_2024_full")
  expect_equal(cached$raw, "Continente_CAOP2024.gpkg")

  expect_message(client$clear_cache("processed"), "Cleared 1 processed")
  expect_length(client$list_cached()$processed, 0L)
  expect_length(client$list_cached()$raw, 1L)

  suppressMessages(expect_message(client$clear_cache("all"), "Cleared 1 raw"))
  expect_length(client$list_cached()$raw, 0L)
})

test_that("get_caop serves processed cache without network", {
  client <- local_client()
  fake <- sf::st_sf(
    municipio = "Fake",
    geometry = sf::st_sfc(sf::st_point(c(0, 0)), crs = 4326)
  )
  saveRDS(fake, file.path(client$cache_dir, "processed",
                          "continente_municipio_2024_full.rds"))

  expect_message(
    out <- client$get_caop("continente", "municipio", year = 2024),
    "Using cached"
  )
  expect_equal(out$municipio, "Fake")
})

test_that("cached results are transformed to the requested crs", {
  client <- local_client()
  fake <- sf::st_sf(
    municipio = "Fake",
    geometry = sf::st_sfc(sf::st_point(c(-9, 39)), crs = 4326)
  )
  saveRDS(fake, file.path(client$cache_dir, "processed",
                          "continente_municipio_2024_full.rds"))

  out <- suppressMessages(
    client$get_caop("continente", "municipio", year = 2024, crs = 3763)
  )
  expect_equal(sf::st_crs(out)$epsg, 3763)
})

test_that("find_cached_year discovers the latest cached year", {
  client <- local_client()
  this_year <- as.integer(format(Sys.Date(), "%Y"))
  fake <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(0, 0)), crs = 4326))
  saveRDS(fake, file.path(
    client$cache_dir, "processed",
    sprintf("continente_municipio_%d_full.rds", this_year - 1L)
  ))

  # Resolved year comes from the cache, so no network call is made and the
  # cached object is returned.
  expect_message(
    out <- client$get_caop("continente", "municipio"),
    "Using cached"
  )
  expect_s3_class(out, "sf")
})

# --- Download, read and cache (server mocked) -------------------------------------

# A CAOP GeoPackage holding one municipios layer, in the region's own CRS and
# with CAOP's NUTS columns, made from the bundled municipios of districts `dt`.
write_fake_gpkg <- function(path, dt, crs, extra = list()) {
  m <- get_dataset("pt_municipios")
  m <- m[m$dt %in% dt, c("dtmn", "municipio", "nuts1", "nuts2", "nuts3")]
  for (nm in names(extra)) m[[nm]] <- extra[[nm]]
  sf::st_write(sf::st_transform(m, crs), path, layer = "municipios", quiet = TRUE)
  path
}

madeira_dt <- c("31", "32")

test_that("get_caop downloads, extracts, reads and caches a region", {
  skip_if(!nzchar(Sys.which(Sys.getenv("R_ZIPCMD", "zip"))), "no zip program")
  client <- local_client()

  src <- withr::local_tempdir()
  gpkg <- write_fake_gpkg(file.path(src, "ArqMadeira_CAOP2024.gpkg"), madeira_dt, 5016L)
  zip_file <- file.path(src, "caop.zip")
  utils::zip(zip_file, gpkg, flags = "-jq")

  # The server's answer is the zip, saved where download_and_extract() asks.
  urls <- character()
  local_mocked_bindings(perform_request = function(req, path = NULL) {
    urls <<- c(urls, req$url)
    file.copy(zip_file, path)
    invisible(NULL)
  })

  msgs <- testthat::capture_messages(
    out <- client$get_caop("ram", "municipio", year = 2024)
  )
  expect_equal(urls, build_caop_url("ram", 2024L))
  expect_match(msgs, "Downloading CAOP data for ram [(]2024[)]", all = FALSE)
  expect_match(msgs, "Extracting", all = FALSE)

  bundled <- get_dataset("pt_municipios")
  expect_s3_class(out, "sf")
  expect_equal(sf::st_crs(out)$epsg, 4326L)
  expect_setequal(out$dtmn, bundled$dtmn[bundled$dt %in% madeira_dt])
  expect_equal(client$list_cached()$processed, "ram_municipio_2024_full")
  expect_equal(basename(client$list_cached()$raw), "ArqMadeira_CAOP2024.gpkg")

  # the second call is served from the cache
  expect_message(client$get_caop("ram", "municipio", year = 2024), "Using cached")
  expect_length(urls, 1L)
})

test_that("NUTS levels without a layer are dissolved from the municipios", {
  client <- local_client()
  write_fake_gpkg(file.path(client$cache_dir, "raw", "ArqMadeira_CAOP2024.gpkg"),
                  madeira_dt, 5016L)
  local_no_download()

  msgs <- testthat::capture_messages(
    out <- client$get_caop("ram", "nuts3", year = 2024, crs = 3763L)
  )
  expect_match(msgs, "Using cached raw data: ram [(]2024[)]", all = FALSE)
  expect_match(msgs, "Dissolving by 'nuts3' to create nuts3 boundaries", all = FALSE)
  expect_equal(nrow(out), 1L)
  expect_equal(out$nuts3, unique(get_dataset("pt_municipios")$nuts3[
    get_dataset("pt_municipios")$dt %in% madeira_dt]))
  # the cache keeps the client's CRS; the CRS asked for is applied on top
  expect_equal(sf::st_crs(out)$epsg, 3763L)
  cached <- readRDS(file.path(client$cache_dir, "processed", "ram_nuts3_2024_full.rds"))
  expect_equal(sf::st_crs(cached)$epsg, 4326L)
})

test_that("the Açores' GeoPackages are merged on their common columns", {
  client <- local_client()
  raw <- file.path(client$cache_dir, "raw")
  # one file per CRS zone, each with a column the other lacks
  write_fake_gpkg(file.path(raw, "ArqAcores_GOcidental_CAOP2024.gpkg"),
                  c("48", "49"), 5014L, extra = list(zona = "Ocidental"))
  write_fake_gpkg(file.path(raw, "ArqAcores_GCentral_GOriental_CAOP2024.gpkg"),
                  as.character(41:47), 5015L, extra = list(ilha = "x"))
  local_no_download()

  out <- suppressMessages(client$get_caop("raa", "municipio", year = 2024))
  bundled <- get_dataset("pt_municipios")
  expect_setequal(out$dtmn, bundled$dtmn[bundled$dt %in% as.character(41:49)])
  expect_false(any(c("zona", "ilha") %in% names(out)))
  expect_equal(sf::st_crs(out)$epsg, 4326L)
})

test_that("get_caop simplifies and caches each detail level apart", {
  skip_if_not_installed("rmapshaper")
  client <- local_client()
  write_fake_gpkg(file.path(client$cache_dir, "raw", "ArqMadeira_CAOP2024.gpkg"),
                  madeira_dt, 5016L)
  local_no_download()

  full <- suppressMessages(client$get_caop("ram", "municipio", year = 2024))
  low <- suppressMessages(client$get_caop("ram", "municipio", year = 2024,
                                          detail = "low"))
  expect_equal(nrow(low), nrow(full))
  n_points <- function(x) nrow(sf::st_coordinates(x))
  expect_lt(n_points(low), n_points(full))
  expect_setequal(client$list_cached()$processed,
                  c("ram_municipio_2024_full", "ram_municipio_2024_low"))
})

test_that("use_cache = FALSE neither reads nor writes cached results", {
  client <- local_client(use_cache = FALSE)
  write_fake_gpkg(file.path(client$cache_dir, "raw", "ArqMadeira_CAOP2024.gpkg"),
                  madeira_dt, 5016L)
  fake <- sf::st_sf(municipio = "Fake",
                    geometry = sf::st_sfc(sf::st_point(c(0, 0)), crs = 4326))
  saveRDS(fake, file.path(client$cache_dir, "processed",
                          "ram_municipio_2024_full.rds"))
  local_no_download()

  out <- suppressMessages(client$get_caop("ram", "municipio", year = 2024))
  expect_false("Fake" %in% out$municipio)
  # the cached copy is left as it was
  cached <- readRDS(file.path(client$cache_dir, "processed",
                              "ram_municipio_2024_full.rds"))
  expect_equal(cached$municipio, "Fake")

  # nor is anything new written
  suppressMessages(client$get_caop("ram", "nuts3", year = 2024))
  expect_equal(client$list_cached()$processed, "ram_municipio_2024_full")
})

test_that("the year of a cached GeoPackage is used when no year is given", {
  client <- local_client()
  this_year <- as.integer(format(Sys.Date(), "%Y"))
  write_fake_gpkg(
    file.path(client$cache_dir, "raw", sprintf("ArqMadeira_CAOP%d.gpkg", this_year)),
    madeira_dt, 5016L
  )
  local_no_download()

  out <- suppressMessages(client$get_caop("ram", "municipio"))
  expect_s3_class(out, "sf")
  expect_equal(client$list_cached()$processed,
               sprintf("ram_municipio_%d_full", this_year))

  msgs <- testthat::capture_messages(paths <- client$download_caop("ram"))
  expect_match(msgs, "Data available at", all = FALSE)
  expect_equal(basename(paths), sprintf("ArqMadeira_CAOP%d.gpkg", this_year))
})

test_that("get_ogc reprojects, caches, and returns NULL for no features", {
  client <- local_client()
  feature <- paste0(
    '{"type":"FeatureCollection","features":[{"type":"Feature",',
    '"properties":{"municipio":"Corvo"},',
    '"geometry":{"type":"Point","coordinates":[-31.1,39.7]}}]}'
  )
  n_requests <- 0L
  httr2::local_mocked_responses(function(req) {
    n_requests <<- n_requests + 1L
    body <- if (grepl("Nowhere", req$url)) {
      '{"type":"FeatureCollection","features":[]}'
    } else {
      feature
    }
    httr2::response(status_code = 200,
                    headers = "Content-Type: application/geo+json",
                    body = charToRaw(body))
  })

  # the server answers in WGS 84 although EPSG:3763 was asked for
  out <- suppressMessages(
    client$get_ogc("municipios", properties = list(municipio = "Corvo"), crs = 3763L)
  )
  expect_equal(out$municipio, "Corvo")
  expect_equal(sf::st_crs(out)$epsg, 3763L)

  expect_message(
    again <- client$get_ogc("municipios", properties = list(municipio = "Corvo"),
                            crs = 3763L),
    "Using cached OGC"
  )
  expect_identical(again, out)
  expect_equal(n_requests, 1L)

  msgs <- testthat::capture_messages(
    none <- client$get_ogc("municipios", properties = list(municipio = "Nowhere"))
  )
  expect_match(msgs, "Query returned 0 features", all = FALSE)
  expect_null(none)
})

# --- Validation paths (fail before any network use) --------------------------------

test_that("get_caop validates arguments upfront", {
  client <- local_client()
  expect_error(client$get_caop("mars", "municipio"), "Invalid region")
  expect_error(client$get_caop("continente", "bairro"), "Invalid level")
  expect_error(client$get_caop("continente", "municipio", detail = "x"), "Invalid detail")
})

test_that("get_caop asks for rmapshaper before downloading anything", {
  client <- local_client()
  local_mocked_bindings(check_suggested_pkg = function(pkg, reason = NULL) {
    stop(sprintf("Package '%s' is required", pkg), call. = FALSE)
  })
  requested <- FALSE
  httr2::local_mocked_responses(function(req) {
    requested <<- TRUE
    httr2::response(status_code = 404)
  })

  expect_error(
    client$get_caop("ram", "municipio", year = 2024, detail = "medium"),
    "Package 'rmapshaper' is required"
  )
  expect_false(requested)

  # a simplified result already in the cache needs no rmapshaper
  fake <- sf::st_sf(
    municipio = "Fake",
    geometry = sf::st_sfc(sf::st_point(c(0, 0)), crs = 4326)
  )
  saveRDS(fake, file.path(client$cache_dir, "processed",
                          "ram_municipio_2024_medium.rds"))
  out <- suppressMessages(
    client$get_caop("ram", "municipio", year = 2024, detail = "medium")
  )
  expect_equal(out$municipio, "Fake")
})

test_that("get_ogc rejects unknown and coverage collections", {
  client <- local_client()
  expect_error(client$get_ogc("nope"), "Unknown OGC collection")
  expect_error(client$get_ogc("ortos-rgb"), "coverage")
})

test_that("get_ogc blocks unfiltered pulls of large collections", {
  client <- local_client()
  expect_error(client$get_ogc("cadastro"), "too large to fetch unfiltered")
  expect_error(client$get_ogc("cos2023v1"), "too large to fetch unfiltered")
})

test_that("get_ogc validates bbox before any request", {
  client <- local_client()
  expect_error(client$get_ogc("municipios", bbox = c(1, 2, 3)), "length 4")
})

# --- simplify_boundaries -------------------------------------------------------------

test_that("simplify_boundaries returns input unchanged for detail = 'full'", {
  skip_if_not_installed("rmapshaper")
  client <- local_client()
  obj <- get_dataset("pt_nuts1")
  expect_identical(client$simplify_boundaries(obj, "full"), obj)
})

test_that("simplify_boundaries validates detail", {
  skip_if_not_installed("rmapshaper")
  client <- local_client()
  obj <- get_dataset("pt_nuts1")
  expect_error(client$simplify_boundaries(obj, "extreme"), "Invalid detail")
})

# --- export_boundaries ---------------------------------------------------------------

test_that("export_boundaries writes geojson and gpkg", {
  client <- local_client()
  obj <- get_dataset("pt_nuts1")

  geojson <- withr::local_tempfile(fileext = ".geojson")
  expect_message(
    out <- client$export_boundaries(obj, geojson, format = "geojson"),
    "Exported to"
  )
  expect_equal(out, geojson)
  expect_true(file.exists(geojson))
  reread <- sf::st_read(geojson, quiet = TRUE)
  expect_equal(nrow(reread), nrow(obj))

  gpkg <- withr::local_tempfile(fileext = ".gpkg")
  suppressMessages(client$export_boundaries(obj, gpkg, format = "gpkg"))
  expect_true(file.exists(gpkg))
})

test_that("export_boundaries reprojects to the requested crs", {
  client <- local_client()
  obj <- get_dataset("pt_nuts1")

  path <- withr::local_tempfile(fileext = ".gpkg")
  suppressMessages(client$export_boundaries(obj, path, format = "gpkg", crs = 3763L))
  reread <- sf::st_read(path, quiet = TRUE)
  expect_equal(sf::st_crs(reread)$epsg, 3763)
})

test_that("export_boundaries simplifies on request and overwrites the file", {
  skip_if_not_installed("rmapshaper")
  client <- local_client()
  obj <- get_dataset("pt_nuts1")
  path <- withr::local_tempfile(fileext = ".geojson")

  suppressMessages(client$export_boundaries(obj, path))
  full_size <- file.size(path)
  suppressMessages(client$export_boundaries(obj, path, detail = "low"))
  expect_lt(file.size(path), full_size)
  expect_equal(nrow(sf::st_read(path, quiet = TRUE)), nrow(obj))
})

test_that("export_boundaries rejects unsupported formats", {
  client <- local_client()
  obj <- get_dataset("pt_nuts1")
  expect_error(
    client$export_boundaries(obj, tempfile(), format = "shp"),
    "Unsupported format"
  )
})
