# Building maps of other vintages (R/derive.R). Offline: the CAOP download is
# replaced by a fake client serving bundled freguesias under CAOP's column names.

# Municipios whose freguesias are the same on the 2013 and 2025 maps, one per
# region, so bundled geometries can stand in for CAOP's.
FAKE_CAOP_DTMN <- c(continente = "1106", ram = "3201", raa = "4901")

# Freguesias as a CAOP release delivers them: upper-case column names, PT-TM06
# coordinates, and columns geopt doesn't use.
fake_caop_freguesias <- function(dtmn) {
  f <- get_dataset("pt_freguesias")
  f <- f[f$dtmn %in% dtmn, ]
  raw <- sf::st_sf(
    DTMNFR = f$dtmnfr,
    Freguesia = f$freguesia,
    Municipio = f$municipio,
    Area_ha = f$area_ha,
    Perimetro_km = f$perimetro_km,
    geometry = sf::st_geometry(f)
  )
  sf::st_transform(raw, 3763L)
}

# Stands in for GeoClient: the derive code only uses get_caop(), cache_dir and
# use_cache. `calls` records each get_caop() request.
fake_client <- function(cache_dir) {
  calls <- new.env()
  calls$args <- list()
  list(
    cache_dir = cache_dir,
    use_cache = TRUE,
    calls = calls,
    get_caop = function(region, level, year = NULL, crs = NULL, detail = "full") {
      calls$args[[length(calls$args) + 1L]] <-
        list(region = region, level = level, year = year, detail = detail)
      raw <- fake_caop_freguesias(FAKE_CAOP_DTMN[[region]])
      # columns that differ between regions are dropped when they are combined
      if (region == "raa") raw$only_in_raa <- "x"
      raw
    }
  )
}

# --- dissolve_level() ---------------------------------------------------------

test_that("dissolve_level needs at least one key column", {
  freg <- get_dataset("pt_freguesias")[1:2, ]
  expect_error(dissolve_level(freg, c("nope", "missing")),
               "None of the dissolve key columns")
})

test_that("dissolve_level refuses a key column that varies within a unit", {
  freg <- get_dataset("pt_freguesias")
  freg <- freg[freg$dtmn == "1106", ][1:2, ]
  freg$municipio[2] <- "Not Lisboa"
  expect_error(dissolve_level(freg, c("dtmn", "municipio")),
               "'dtmn': 1 unit[(]s[)] split .*e[.]g[.] 1106")
})

# --- attach_nuts() --------------------------------------------------------------

test_that("maps without dtmn keep their columns under any NUTS revision", {
  # distritos carry only NUTS 1, the same in every revision
  expect_identical(get_map("distrito", nuts_vintage = "2013"), get_map("distrito"))
})

# --- harmonize_caop_freguesias() ------------------------------------------------

test_that("harmonize_caop_freguesias reads the 2022-2023 column names", {
  reg <- pt_lookup(level = "freguesia", admin_vintage = "2013", nuts_vintage = NA)
  codes <- c("010121", "010122", "010123")  # uniões of Águeda, 2013 map only
  geoms <- sf::st_geometry(get_dataset("pt_freguesias")[1:3, ])
  raw <- sf::st_sf(
    DICOFRE = as.numeric(codes),          # leading zero lost, as in a numeric column
    Freguesia = c("raw name 1", "raw name 2", "raw name 3"),
    Des_Simpli = c("raw short 1", "raw short 2", "raw short 3"),
    geometry = geoms
  )

  out <- harmonize_caop_freguesias(raw, 2022L, "2013")

  expect_equal(out$dtmnfr, codes)
  expect_equal(out$dtmn, rep("0101", 3))
  expect_equal(out$dt, rep("01", 3))
  # names come from geopt's 2013 registry, not from the download
  idx <- match(codes, reg$dtmnfr)
  expect_equal(out$freguesia, reg$freguesia[idx])
  expect_equal(out$designacao_simplificada, reg$designacao_simplificada[idx])
  ctx <- pt_lookup(level = "municipio", admin_vintage = "2013", nuts_vintage = NA)
  expect_equal(out$municipio, rep(ctx$municipio[ctx$dtmn == "0101"], 3))
  expect_equal(out$distrito_ilha, rep(ctx$distrito_ilha[ctx$dtmn == "0101"], 3))
  # without an area column the area is computed from the geometry
  expect_equal(out$area_ha, round(as.numeric(sf::st_area(geoms)) / 1e4, 2))
  # NUTS columns are placeholders for attach_nuts()
  expect_true(all(is.na(sf::st_drop_geometry(out)[NUTS_COLS])))
  # pt_freguesias' column order
  expect_identical(names(out),
                   intersect(names(get_dataset("pt_freguesias")), names(out)))
})

test_that("harmonize_caop_freguesias keeps CAOP's names for codes not in the registry", {
  raw <- sf::st_sf(
    dtmnfr = "999901",
    freguesia = "Nowhere",
    geometry = sf::st_geometry(get_dataset("pt_freguesias")[1, ])
  )
  expect_warning(
    out <- harmonize_caop_freguesias(raw, 2024L, "2013"),
    "CAOP 2024: 1 freguesia[(]s[)] belong to a municipality not in the 2013 registry"
  )
  expect_equal(out$freguesia, "Nowhere")
  expect_true(is.na(out$municipio))
  expect_true(is.na(out$distrito_ilha))
  expect_false("designacao_simplificada" %in% names(out))
})

test_that("harmonize_caop_freguesias says which columns it found when the code is missing", {
  raw <- sf::st_sf(
    nome = "x",
    geometry = sf::st_geometry(get_dataset("pt_freguesias")[1, ])
  )
  expect_error(harmonize_caop_freguesias(raw, 2023L, "2013"),
               "Could not find a DTMNFR column in the CAOP 2023 freguesias [(]columns: nome[)]")
})

# --- get_vintage_dataset() and build_caop_freguesias() -------------------------

test_that("a 2013 map is downloaded once per region, simplified and cached", {
  skip_if_not_installed("rmapshaper")
  client <- fake_client(withr::local_tempdir())
  release <- CAOP_RELEASE_FOR_ADMIN[["2013"]]

  expect_message(
    m <- get_vintage_dataset("municipio", "2013", "2013", client = client),
    "Simplifying the 2013 map's freguesias [(]CAOP 2024; once, then cached[)]"
  )

  # every region, at full detail, from the release that carries the 2013 map
  args <- client$calls$args
  expect_setequal(vapply(args, `[[`, "", "region"), VALID_REGIONS)
  expect_true(all(vapply(args, `[[`, "", "level") == "freguesia"))
  expect_true(all(vapply(args, `[[`, 0L, "year") == release))
  expect_true(all(vapply(args, `[[`, "", "detail") == "full"))

  expect_s3_class(m, "sf")
  expect_equal(sf::st_crs(m)$epsg, 4326L)
  expect_equal(m$dtmn, unname(sort(FAKE_CAOP_DTMN)))
  expect_false("only_in_raa" %in% names(m))
  bundled <- get_dataset("pt_municipios")
  expect_equal(m$n_freguesias,
               bundled$n_freguesias[match(m$dtmn, bundled$dtmn)])
  # the NUTS revision asked for, not the newest
  n <- as.data.frame(pt_nuts_codes)
  expect_equal(m$nuts3, n$nuts3[n$nuts_vintage == "2013"][
    match(m$dtmn, n$dtmn[n$nuts_vintage == "2013"])])
  expect_identical(names(m), names(bundled))

  # both the freguesias and the level are cached
  freg_file <- vintage_cache_file(client, "freguesia", "2013", release)
  expect_true(file.exists(freg_file))
  expect_true(file.exists(
    vintage_cache_file(client, "municipio", "2013", release, "2013")
  ))
  freg <- get_dataset("pt_freguesias")
  expect_setequal(readRDS(freg_file)$dtmnfr,
                  freg$dtmnfr[freg$dtmn %in% FAKE_CAOP_DTMN])
})

test_that("a cached 2013 level is served without rebuilding", {
  skip_if_not_installed("rmapshaper")
  client <- fake_client(withr::local_tempdir())
  first <- suppressMessages(get_vintage_dataset("nuts3", "2013", "2024", client = client))
  n_calls <- length(client$calls$args)

  expect_message(
    again <- get_vintage_dataset("nuts3", "2013", "2024", client = client),
    "Using cached nuts3 boundaries for the 2013 map"
  )
  expect_identical(again, first)
  expect_length(client$calls$args, n_calls)

  # another level of the same map reuses the cached freguesias
  expect_no_message(
    get_vintage_dataset("distrito", "2013", "2024", client = client),
    message = "Simplifying"
  )
  expect_length(client$calls$args, n_calls)
})

test_that("use_cache = FALSE builds the map without writing to the cache", {
  skip_if_not_installed("rmapshaper")
  client <- fake_client(withr::local_tempdir())
  client$use_cache <- FALSE
  m <- suppressMessages(get_vintage_dataset("municipio", "2013", "2024", client = client))
  expect_equal(nrow(m), length(FAKE_CAOP_DTMN))
  expect_length(list.files(client$cache_dir, pattern = "[.]rds$", recursive = TRUE), 0L)
})
