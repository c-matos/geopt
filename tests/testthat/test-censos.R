# Offline tests: manifest integrity, argument validation, scope resolution,
# and the tidy/dissolve/select helpers on synthetic data. Network-dependent
# behaviour (actual INE downloads) is covered by test-network.R.

make_bgri21 <- function() {
  poly <- function(x0) {
    sf::st_polygon(list(matrix(
      c(x0, 0, x0 + 1, 0, x0 + 1, 1, x0, 1, x0, 0),
      ncol = 2, byrow = TRUE
    )))
  }
  sf::st_sf(
    OBJECTID = 1:4,
    BGRI2021 = c("03030100101", "03030100102", "03030100201", "03030200101"),
    DTMN21 = "0303",
    DTMNFR21 = c("030301", "030301", "030301", "030302"),
    SECNUM21 = c("001", "001", "002", "001"),
    SSNUM21 = c("01", "02", "01", "01"),
    N_INDIVIDUOS = c(10, 20, 30, 40),
    N_EDIFICIOS_CLASSICOS = c(1, 2, 3, 4),
    Shape_Area = runif(4),
    geom = sf::st_sfc(poly(0), poly(1), poly(2), poly(3), crs = 3763)
  )
}

# --- Manifest integrity -----------------------------------------------------------

test_that("censos_manifest covers every product, year, and scope", {
  m <- censos_manifest
  expect_true(all(c("product", "year", "scope_type", "scope_id", "url") %in% names(m)))
  expect_false(anyNA(m$url))
  expect_true(all(grepl("^filesGPG/.*\\.zip$", m$url)))

  dtmns <- unique(pt_lookup()$dtmn)
  for (yr in c(1991L, 2001L, 2011L, 2021L)) {
    b <- m[m$product == "bgri" & m$year == yr, ]
    expect_setequal(b$scope_id[b$scope_type == "municipio"], dtmns)
    expect_length(b$scope_id[b$scope_type == "nuts3"], 23L)
    expect_setequal(b$scope_id[b$scope_type == "nuts2"],
                    unname(CENSOS_NUTS2_IDS))
    expect_setequal(b$scope_id[b$scope_type == "region"],
                    c("CONT", "RAA", "MAD"))
    expect_equal(sum(b$scope_type == "portugal"), 1L)
  }

  s <- m[m$product == "seccoes", ]
  expect_true(all(s$year == 2021L))
  expect_setequal(s$scope_id[s$scope_type == "municipio"], dtmns)

  g <- m[m$product == "grid", ]
  expect_equal(nrow(g), 4L)
  expect_setequal(g$scope_id, c("PT", "CONT", "RAA", "MAD"))

  # NUTS3 ids are the NUTS 2013 mainland codes sans "PT"
  n13 <- pt_lookup(nuts_vintage = "2013")
  n3 <- unique(sub("^PT", "", n13$nuts3_cod[n13$nuts1_cod == "PT1"]))
  expect_setequal(m$scope_id[m$product == "bgri" & m$year == 2021L &
                               m$scope_type == "nuts3"], n3)

  # No duplicate keys
  key <- with(m, paste(product, year, scope_type, scope_id))
  expect_false(any(duplicated(key)))
})

test_that("pt_censos_vars matches the documented shape", {
  v <- get_dataset("pt_censos_vars")
  expect_named(v, c("year", "level", "variable", "description"))
  counts <- table(v$year, v$level)
  expect_equal(counts["1991", "subseccao"], 7L, ignore_attr = TRUE)
  expect_equal(counts["2001", "subseccao"], 7L, ignore_attr = TRUE)
  expect_equal(counts["2011", "subseccao"], 122L, ignore_attr = TRUE)
  expect_equal(counts["2021", "subseccao"], 32L, ignore_attr = TRUE)
  expect_equal(counts["2021", "seccao"], 178L, ignore_attr = TRUE)
  expect_equal(counts["2021", "grid"], 10L, ignore_attr = TRUE)
  # Every variable is documented, and the dropped artifacts are absent
  expect_false(anyNA(v$description))
  expect_false("N_ALOJ" %in% v$variable)
})

# --- Validation --------------------------------------------------------------------

test_that("get_censos validates year, level, and scope without network", {
  client <- local_client()
  expect_error(get_censos("Braga", year = 2016, client = client), "must be one of")
  expect_error(get_censos("Braga", level = "distrito", client = client), "Invalid level")
  expect_error(get_censos(client = client), "No scope given")
  expect_error(get_censos("Braga", region = "norte", client = client),
               "cannot be combined")
  expect_error(get_censos("Braga", level = "grid", client = client), "grid")
  expect_error(get_censos(region = "ram", level = "grid", year = 2011, client = client),
               "2021")
  expect_error(get_censos(municipio = "Xyzzyland", client = client),
               "Could not resolve municipio")
  # Ambiguous without qualifier
  expect_error(get_censos(municipio = "Lagoa", client = client), "Lagoa")
})

test_that("level accepts accented/case variants", {
  expect_equal(validate_censos_level("Subsecção"), "subseccao")
  expect_equal(validate_censos_level("SECÇÃO"), "seccao")
  expect_equal(validate_censos_level("grid"), "grid")
})

# --- Scope resolution -----------------------------------------------------------

test_that("municipio and freguesia scopes resolve to dtmns", {
  s <- censos_resolve_scope("bgri", 2021L, "Braga", NULL, NULL)
  expect_equal(s$scope_type, "municipio")
  expect_equal(s$scope_ids, "0303")
  expect_null(s$dtmnfr_filter)

  s2 <- censos_resolve_scope("bgri", 2021L, c("Braga", "0303", "Porto"), NULL, NULL)
  expect_setequal(s2$scope_ids, c("0303", "1312"))

  # freguesia by code: passes through padded, scopes the parent municipio
  s3 <- censos_resolve_scope("bgri", 2011L, NULL, "30401", NULL)
  expect_equal(s3$scope_type, "municipio")
  expect_equal(s3$scope_ids, "0304")
  expect_true("030401" %in% s3$dtmnfr_filter)
})

test_that("freguesia names expand with their 2013-era codes", {
  cw <- pt_crosswalk("2013", "2025")
  moved <- cw[cw$from != cw$to, ]
  skip_if(nrow(moved) == 0L)
  pick <- moved[1L, ]

  cand <- censos_resolve_freguesia(pick$to)
  expect_true(all(c(pick$to, pick$from) %in% cand))
})

test_that("get_censos accepts a dissolved freguesia by name", {
  expect_equal(censos_resolve_freguesia("Sé (Braga)", municipio = "Braga"),
               "030364")
  s <- censos_resolve_scope("bgri", 2021L, "Braga", "Sé (Braga)", NULL)
  expect_equal(s$scope_ids, "0303")
  expect_equal(s$dtmnfr_filter, "030364")
})

test_that("region scopes resolve across keyword, NUTS2, NUTS3, and code forms", {
  r <- censos_resolve_region("bgri", 2021L, "portugal")
  expect_equal(r[c("scope_type", "scope_ids")], list(scope_type = "portugal", scope_ids = "PT"))

  expect_equal(censos_resolve_region("bgri", 2021L, "Continente")$scope_ids, "CONT")
  expect_equal(censos_resolve_region("bgri", 2021L, "Açores")$scope_ids, "RAA")
  expect_equal(censos_resolve_region("bgri", 2021L, "madeira")$scope_ids, "MAD")

  r_norte <- censos_resolve_region("bgri", 2021L, "Norte")
  expect_equal(r_norte$scope_type, "nuts2")
  expect_equal(r_norte$scope_ids, "NORTE")
  expect_equal(censos_resolve_region("bgri", 2021L, "Cávado")$scope_ids, "112")
  expect_equal(censos_resolve_region("bgri", 2021L, "cavado")$scope_ids, "112")
  expect_equal(censos_resolve_region("bgri", 2021L, "16D")$scope_ids, "16D")
  expect_equal(censos_resolve_region("bgri", 2021L, "PT16D")$scope_ids, "16D")

  # Island NUTS3 names route to the region files
  expect_equal(censos_resolve_region("bgri", 2021L, "Região Autónoma dos Açores")$scope_ids, "RAA")

  expect_error(censos_resolve_region("bgri", 2021L, "Atlantis"), "Unknown region")
  expect_error(censos_resolve_region("grid", 2021L, "Cávado"), "grid")
})

test_that("2024-only NUTS names that straddle NUTS 2013 units are rejected", {
  ovt <- "Oeste e Vale do Tejo"
  skip_if(!ovt %in% pt_lookup()$nuts2, "NUTS 2024 name not in pt_lookup()")
  expect_error(censos_resolve_region("bgri", 2021L, ovt), "single NUTS 2013")
})

test_that("censos_product maps levels to products by year", {
  expect_equal(censos_product("subseccao", 2011L), "bgri")
  expect_equal(censos_product("seccao", 2021L), "seccoes")
  expect_equal(censos_product("seccao", 2011L), "bgri")
  expect_equal(censos_product("grid", 2021L), "grid")
})

test_that("manifest lookup expands portugal to region files and errors on gaps", {
  rows <- censos_manifest_rows("bgri", 2021L,
                               list(scope_type = "portugal", scope_ids = "PT"))
  expect_setequal(rows$scope_id, c("CONT", "RAA", "MAD"))

  rows_g <- censos_manifest_rows("grid", 2021L,
                                 list(scope_type = "portugal", scope_ids = "PT"))
  expect_equal(rows_g$scope_id, "PT")

  expect_error(
    censos_manifest_rows("bgri", 2021L,
                         list(scope_type = "municipio", scope_ids = "9999")),
    "No INE census file"
  )
})

# --- Tidy / dissolve / select on synthetic data --------------------------------

test_that("censos_tidy adds year-stable ids and drops artifacts", {
  tidied <- censos_tidy(make_bgri21(), "bgri", 2021L)

  expect_s3_class(tidied, "sf")
  expect_equal(attr(tidied, "sf_column"), "geometry")
  expect_true(all(c("censos_year", "bgri", "dtmn", "dtmnfr", "seccao",
                    "subseccao") %in% names(tidied)))
  expect_false(any(c("OBJECTID", "Shape_Area") %in% names(tidied)))
  # Originals kept alongside
  expect_true(all(c("BGRI2021", "DTMN21") %in% names(tidied)))
  expect_equal(tidied$censos_year, rep(2021L, 4))
  expect_equal(tidied$dtmnfr, c("030301", "030301", "030301", "030302"))
})

test_that("censos_tidy drops N_ALOJ and enumerated OBJECTID artifacts", {
  x <- make_bgri21()
  x$N_ALOJ <- 99                 # Açores-only 2011 artifact
  x$OBJECTID_12 <- 1:4           # stray GIS key seen in some municipality files
  tidied <- censos_tidy(x, "bgri", 2021L)
  expect_false(any(c("N_ALOJ", "OBJECTID_12") %in% names(tidied)))
  # A real variable with a similar name is untouched
  expect_true("N_EDIFICIOS_CLASSICOS" %in% names(tidied))
})

test_that("censos_tidy concatenates the split 2011 freguesia code", {
  x <- make_bgri21()
  names(x)[names(x) == "BGRI2021"] <- "BGRI11"
  names(x)[names(x) == "DTMN21"] <- "DTMN11"
  names(x)[names(x) == "SECNUM21"] <- "SEC11"
  names(x)[names(x) == "SSNUM21"] <- "SS11"
  x$FR11 <- substr(x$DTMNFR21, 5, 6)
  x$DTMNFR21 <- NULL

  tidied <- censos_tidy(x, "bgri", 2011L)
  expect_equal(tidied$dtmnfr, c("030301", "030301", "030301", "030302"))
})

test_that("censos_dissolve_seccao sums counts and keeps constant ids", {
  tidied <- censos_tidy(make_bgri21(), "bgri", 2021L)
  sec <- censos_dissolve_seccao(tidied)

  expect_equal(nrow(sec), 3L)
  expect_equal(sec$n_subseccoes, c(2L, 1L, 1L))
  expect_equal(sec$N_INDIVIDUOS, c(30, 30, 40))
  expect_equal(sec$dtmn, rep("0303", 3))
  # Subsecção-grain identifiers are gone
  expect_false(any(c("bgri", "subseccao", "BGRI2021", "SSNUM21") %in% names(sec)))
  expect_true(all(c("dtmnfr", "seccao") %in% names(sec)))
  # Union really merged the two subsecção polygons
  expect_equal(as.numeric(sf::st_area(sec$geometry[1L])),
               2 * as.numeric(sf::st_area(tidied$geometry[1L])),
               tolerance = 1e-6)
})

test_that("censos_select_vars keeps ids and matches case-insensitively", {
  tidied <- censos_tidy(make_bgri21(), "bgri", 2021L)
  sel <- censos_select_vars(tidied, "n_individuos", 2021L, "subseccao")
  expect_true("N_INDIVIDUOS" %in% names(sel))
  expect_false("N_EDIFICIOS_CLASSICOS" %in% names(sel))
  expect_true(all(c("censos_year", "bgri", "dtmn", "dtmnfr") %in% names(sel)))
  expect_error(
    censos_select_vars(tidied, "N_UNICORNIOS", 2021L, "subseccao"),
    "pt_censos_vars"
  )
})

test_that("censos_filter_dtmnfr keeps matches and errors clearly on none", {
  tidied <- censos_tidy(make_bgri21(), "bgri", 2021L)
  kept <- censos_filter_dtmnfr(tidied, "030302", 2021L)
  expect_equal(nrow(kept), 1L)
  expect_error(censos_filter_dtmnfr(tidied, "999999", 2011L),
               "vintage-specific")
})

test_that("censos_read turns curved polygons into ordinary ones", {
  # INE's Braga 2021 file has 8 MULTISURFACE subsecções, which st_area() can't
  # measure on the sphere.
  gpkg <- withr::local_tempfile(fileext = ".gpkg")
  x <- sf::st_sf(
    id = 1:2,
    geometry = sf::st_as_sfc(c(
      "MULTIPOLYGON(((0 0, 100 0, 100 100, 0 100, 0 0)))",
      "MULTISURFACE(CURVEPOLYGON(CIRCULARSTRING(200 0, 300 100, 400 0, 300 -100, 200 0)))"
    ), crs = 3763)
  )
  sf::st_write(x, gpkg, quiet = TRUE)

  out <- censos_read(gpkg)[[1L]]
  expect_equal(as.character(sf::st_geometry_type(out)), c("MULTIPOLYGON", "MULTIPOLYGON"))
  # the circle of radius 100 keeps its area once linearized
  expect_equal(as.numeric(sf::st_area(out))[2], pi * 100^2, tolerance = 0.01)
  expect_no_error(sf::st_area(sf::st_transform(out, 4326)))
})

# --- Caching ------------------------------------------------------------------------

test_that("censos_cache_path respects use_cache and hashes long scopes", {
  client <- local_client()
  scope <- list(scope_type = "municipio", scope_ids = c("0303", "0301"))
  p <- censos_cache_path(client, "bgri", 2021L, "subseccao", scope, 4326L)
  expect_match(basename(p), "^censos_bgri_2021_subseccao_municipio_0301-0303_4326\\.rds$")

  long_scope <- list(scope_type = "municipio", scope_ids = sprintf("%04d", 1:20))
  p2 <- censos_cache_path(client, "bgri", 2021L, "subseccao", long_scope, 4326L)
  # ids are hashed, not enumerated
  expect_false(grepl("0001", basename(p2)))
  expect_lt(nchar(basename(p2)), 80L)

  client$use_cache <- FALSE
  expect_null(censos_cache_path(client, "bgri", 2021L, "subseccao", scope, 4326L))
})

test_that("get_censos serves processed cache without network", {
  client <- local_client()
  tidied <- censos_tidy(make_bgri21(), "bgri", 2021L)
  scope <- list(scope_type = "municipio", scope_ids = "0303")
  path <- censos_cache_path(client, "bgri", 2021L, "subseccao", scope, 4326L)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(tidied, path)

  expect_message(
    out <- get_censos("Braga", client = client),
    "Using cached"
  )
  expect_equal(nrow(out), 4L)

  # Variables/geometry apply on top of the cache
  out2 <- suppressMessages(
    get_censos("Braga", variables = "N_INDIVIDUOS", geometry = FALSE, client = client)
  )
  expect_s3_class(out2, "data.frame")
  expect_false(inherits(out2, "sf"))
  expect_true("N_INDIVIDUOS" %in% names(out2))
})
