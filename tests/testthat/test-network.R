# Network behaviour, in two parts.
#
# Failures run everywhere, CRAN included: the server is mocked, or the cache
# holds a broken file. A server that can't be reached, or a file that has moved
# or changed, must stop with an error of class "geopt_download_error" that says
# which server or file and why, never with httr2's raw error.
#
# Live downloads are skipped on CRAN and when offline. Each makes the smallest
# real request to one source, so a change at DGT or INE shows up here. The full
# CAOP download (~15 MB per region) is not run here.

# The server answers, but the file isn't there.
mock_404 <- function(req) httr2::response(status_code = 404)

# The server can't be reached: httr2 raises an "httr2_failure".
mock_offline <- function(req) {
  stop(structure(
    class = c("httr2_failure", "httr2_error", "error", "condition"),
    list(message = "Could not resolve host", call = NULL)
  ))
}

# The server answers 200 with something that isn't the expected data.
mock_html <- function(req) {
  httr2::response(status_code = 200, headers = "Content-Type: text/html",
                  body = charToRaw("<html>Service moved</html>"))
}

# A download error whose message matches `pattern`. The progress messages
# ("Downloading ...") are silenced.
expect_download_error <- function(expr, pattern) {
  suppressMessages(expect_error(expr, pattern, class = "geopt_download_error"))
}

# --- Failures: run everywhere -------------------------------------------------

test_that("a failed download leaves no partial file behind", {
  path <- withr::local_tempfile(fileext = ".zip")
  writeLines("partial", path)
  httr2::local_mocked_responses(mock_404)

  expect_download_error(
    perform_request(httr2::request("https://mapas.ine.pt/x.zip"), path = path),
    "404 Not Found"
  )
  expect_false(file.exists(path))
})

test_that("get_censos says why when INE fails", {
  client <- local_client()

  httr2::local_mocked_responses(mock_offline)
  expect_download_error(get_censos("Corvo", client = client), "Could not reach mapas[.]ine[.]pt")

  httr2::local_mocked_responses(mock_404)
  expect_download_error(get_censos("Corvo", client = client),
                        "BGRI2021_4901[.]zip.*404 Not Found")

  # nothing was cached, so the next call tries again
  expect_length(list.files(client$cache_dir, recursive = TRUE), 0L)
})

test_that("get_censos reports a census file that has changed", {
  client <- local_client()
  raw_dir <- file.path(client$cache_dir, "raw", "censos", "2021")
  dir.create(raw_dir, recursive = TRUE)
  zip_path <- file.path(raw_dir, "BGRI2021_4901.zip")
  writeLines("not a zip", zip_path)

  expect_download_error(get_censos("Corvo", client = client), "may have changed")
  # removed, so the next call downloads it again
  expect_false(file.exists(zip_path))
})

test_that("get_caop says why when DGT fails", {
  client <- local_client()

  httr2::local_mocked_responses(mock_offline)
  expect_download_error(client$get_caop("ram", "municipio", year = 2024),
                        "Could not reach geo2[.]dgterritorio[.]gov[.]pt")
  expect_download_error(client$download_caop("ram", year = 2024), "Could not reach")

  httr2::local_mocked_responses(mock_404)
  expect_download_error(client$get_caop("ram", "municipio", year = 2024),
                        "CAOP_RAM_2024-gpkg[.]zip.*404 Not Found")

  expect_length(list.files(client$cache_dir, recursive = TRUE), 0L)
})

test_that("get_caop without a year says why it found none", {
  client <- local_client()

  httr2::local_mocked_responses(mock_offline)
  expect_download_error(client$get_caop("ram", "municipio"),
                        "Could not reach geo2[.]dgterritorio[.]gov[.]pt to find the latest CAOP year")

  # every recent year missing: the address has changed
  httr2::local_mocked_responses(mock_404)
  expect_download_error(client$get_caop("ram", "municipio"),
                        "Could not find CAOP data for 'ram'")
  expect_download_error(client$download_caop("ram"), "Could not find CAOP data")
})

test_that("get_caop reports a CAOP file that has changed", {
  client <- local_client()
  zip_path <- file.path(client$cache_dir, "raw", "CAOP_RAM_2024.zip")
  writeLines("not a zip", zip_path)

  expect_download_error(client$get_caop("ram", "municipio", year = 2024),
                        "has no GeoPackage in it")
  expect_false(file.exists(zip_path))
})

test_that("get_ogc says why when the OGC API fails", {
  client <- local_client()

  httr2::local_mocked_responses(mock_offline)
  expect_download_error(client$get_ogc("municipios"),
                        "Could not reach ogcapi[.]dgterritorio[.]gov[.]pt")

  httr2::local_mocked_responses(mock_404)
  expect_download_error(client$get_ogc("municipios"), "404 Not Found")

  httr2::local_mocked_responses(mock_html)
  expect_download_error(client$get_ogc("municipios"), "may have changed")

  # a failure is not cached as a result
  expect_length(list.files(client$cache_dir, recursive = TRUE), 0L)
})

test_that("list_ogc_collections says why when the OGC API fails", {
  client <- local_client()

  httr2::local_mocked_responses(mock_offline)
  expect_download_error(client$list_ogc_collections(), "Could not reach")

  httr2::local_mocked_responses(mock_404)
  expect_download_error(client$list_ogc_collections(), "404 Not Found")

  httr2::local_mocked_responses(mock_html)
  expect_download_error(client$list_ogc_collections(), "may have changed")
})

test_that("maps of the 2013 vintage say why when DGT fails", {
  skip_if_not_installed("rmapshaper")
  # get_map() uses the default cache: point it away from the user's own
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir())
  httr2::local_mocked_responses(mock_offline)

  expect_download_error(get_map("municipio", admin_vintage = "2013"),
                        "Could not reach")
  expect_download_error(plot_pt(admin_vintage = "2013"), "Could not reach")
  expect_download_error(
    get_map("municipio", admin_vintage = "2013", client = local_client()),
    "Could not reach geo2[.]dgterritorio[.]gov[.]pt"
  )
})

test_that("download errors can be caught on their own", {
  client <- local_client()
  httr2::local_mocked_responses(mock_404)

  out <- suppressMessages(tryCatch(
    get_censos("Corvo", client = client),
    geopt_download_error = function(e) "skipped"
  ))
  expect_equal(out, "skipped")

  # a bad argument is an ordinary error, not a download error
  err <- tryCatch(get_censos("Xyzzyland", client = client), error = function(e) e)
  expect_s3_class(err, "error")
  expect_false(inherits(err, "geopt_download_error"))
})

# --- Live downloads: skipped on CRAN and offline -------------------------------

test_that("DGT publishes a recent CAOP for every region", {
  skip_on_cran()
  skip_if_offline()
  for (region in VALID_REGIONS) {
    expect_type(resolve_year(region), "integer")
  }
})

test_that("get_censos downloads a municipality from INE", {
  skip_on_cran()
  skip_if_offline()
  client <- local_client()

  # Corvo is the smallest file INE publishes (~75 KB)
  out <- suppressMessages(get_censos("Corvo", client = client))
  expect_s3_class(out, "sf")
  expect_true(all(out$dtmn == "4901"))
  expect_true("N_INDIVIDUOS" %in% names(out))
})

test_that("get_ogc fetches features inside a bbox", {
  skip_on_cran()
  skip_if_offline()
  client <- local_client()

  out <- suppressMessages(
    client$get_ogc("freguesias", bbox = c(-9.20, 38.74, -9.13, 38.78))
  )
  expect_s3_class(out, "sf")
  expect_gt(nrow(out), 0L)
})

test_that("list_ogc_collections lists the collections geopt knows", {
  skip_on_cran()
  skip_if_offline()
  out <- local_client()$list_ogc_collections()
  expect_true(all(c("municipios", "freguesias") %in% out$id))
})
