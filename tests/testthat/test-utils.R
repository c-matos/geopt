# --- %||% ---------------------------------------------------------------------

test_that("%||% returns lhs unless NULL", {
  expect_equal(1 %||% 2, 1)
  expect_equal(NULL %||% 2, 2)
  expect_equal(NA %||% 2, NA)
  expect_equal(list() %||% 2, list())
})

# --- Validators ----------------------------------------------------------------

test_that("validate_region accepts valid regions, case-insensitively", {
  expect_equal(validate_region("continente"), "continente")
  expect_equal(validate_region("RAA"), "raa")
  expect_equal(validate_region("Ram"), "ram")
})

test_that("validate_region rejects unknown regions", {
  expect_error(validate_region("portugal"), "Invalid region")
  expect_error(validate_region("azores"), "Invalid region")
})

test_that("validate_level accepts valid levels, case-insensitively", {
  expect_equal(validate_level("freguesia"), "freguesia")
  expect_equal(validate_level("MUNICIPIO"), "municipio")
  expect_equal(validate_level("Nuts3"), "nuts3")
})

test_that("validate_level rejects unknown levels", {
  expect_error(validate_level("concelho"), "Invalid level")
  expect_error(validate_level("nuts4"), "Invalid level")
})

test_that("validate_detail accepts presets and rejects others", {
  expect_equal(validate_detail("full"), "full")
  expect_equal(validate_detail("HIGH"), "high")
  expect_equal(validate_detail("medium"), "medium")
  expect_equal(validate_detail("low"), "low")
  expect_error(validate_detail("ultra"), "Invalid detail")
})

# --- URL building and year resolution ------------------------------------------

test_that("build_caop_url builds the expected URL", {
  expect_equal(
    unname(build_caop_url("continente", 2024)),
    "https://geo2.dgterritorio.gov.pt/caop/CAOP_Continente_2024-gpkg.zip"
  )
  expect_equal(
    unname(build_caop_url("raa", 2023)),
    "https://geo2.dgterritorio.gov.pt/caop/CAOP_RAA_2023-gpkg.zip"
  )
  expect_equal(
    unname(build_caop_url("ram", 2024)),
    "https://geo2.dgterritorio.gov.pt/caop/CAOP_RAM_2024-gpkg.zip"
  )
})

test_that("resolve_year returns explicit years as integers without network", {
  expect_identical(resolve_year("continente", 2023), 2023L)
  expect_identical(resolve_year("raa", "2024"), 2024L)
})

# --- Raw GeoPackage discovery ---------------------------------------------------

test_that("find_region_gpkgs matches region and year patterns", {
  raw_dir <- withr::local_tempdir()
  dir.create(file.path(raw_dir, "sub"))
  files <- c(
    "Continente_CAOP2024.gpkg",
    "sub/ArqAcores_GOcidental_CAOP2024.gpkg",
    "sub/ArqAcores_GCentralOriental_CAOP2024.gpkg",
    "ArqMadeira_CAOP2024.gpkg",
    "Continente_CAOP2023.gpkg",
    "notes.txt"
  )
  for (f in files) file.create(file.path(raw_dir, f))

  cont <- find_region_gpkgs(raw_dir, "continente", 2024)
  expect_length(cont, 1L)
  expect_match(cont, "Continente_CAOP2024")

  raa <- find_region_gpkgs(raw_dir, "raa", 2024)
  expect_length(raa, 2L)

  ram <- find_region_gpkgs(raw_dir, "ram", 2024)
  expect_length(ram, 1L)
  expect_match(ram, "Madeira")

  expect_length(find_region_gpkgs(raw_dir, "continente", 2023), 1L)
  expect_length(find_region_gpkgs(raw_dir, "raa", 2022), 0L)
})

test_that("find_region_gpkgs returns empty when directory has no gpkgs", {
  raw_dir <- withr::local_tempdir()
  expect_identical(find_region_gpkgs(raw_dir, "continente", 2024), character(0))
})

# --- GeoPackage layer detection -------------------------------------------------

make_test_sf <- function(n = 2L, cols = list()) {
  polys <- lapply(seq_len(n), function(i) {
    x0 <- (i - 1) * 2
    sf::st_polygon(list(matrix(
      c(x0, 0, x0 + 1, 0, x0 + 1, 1, x0, 1, x0, 0),
      ncol = 2, byrow = TRUE
    )))
  })
  df <- data.frame(id = seq_len(n))
  for (nm in names(cols)) df[[nm]] <- cols[[nm]]
  sf::st_sf(df, geometry = sf::st_sfc(polys, crs = 4326))
}

test_that("find_gpkg_layer matches level layers directly", {
  gpkg <- withr::local_tempfile(fileext = ".gpkg")
  obj <- make_test_sf()
  sf::st_write(obj, gpkg, layer = "cont_municipios", quiet = TRUE)
  sf::st_write(obj, gpkg, layer = "cont_freguesias", quiet = TRUE)

  expect_equal(find_gpkg_layer(gpkg, "municipio"), "cont_municipios")
  expect_equal(find_gpkg_layer(gpkg, "freguesia"), "cont_freguesias")
})

test_that("find_gpkg_layer falls back to dissolve for NUTS levels", {
  gpkg <- withr::local_tempfile(fileext = ".gpkg")
  sf::st_write(make_test_sf(), gpkg, layer = "municipios", quiet = TRUE)

  result <- find_gpkg_layer(gpkg, "nuts3")
  expect_type(result, "list")
  expect_equal(result$layer, "municipios")
  expect_equal(result$dissolve_by, "nuts3")
})

test_that("find_gpkg_layer uses a single unmatched layer as last resort", {
  gpkg <- withr::local_tempfile(fileext = ".gpkg")
  sf::st_write(make_test_sf(), gpkg, layer = "outra_coisa", quiet = TRUE)

  expect_equal(find_gpkg_layer(gpkg, "distrito"), "outra_coisa")
})

test_that("find_gpkg_layer errors when the level cannot be resolved", {
  gpkg <- withr::local_tempfile(fileext = ".gpkg")
  sf::st_write(make_test_sf(), gpkg, layer = "coisa_a", quiet = TRUE)
  sf::st_write(make_test_sf(), gpkg, layer = "coisa_b", quiet = TRUE)

  expect_error(find_gpkg_layer(gpkg, "distrito"), "Could not find layer")
})

test_that("bundled caop_simplified.gpkg layers are found for every level", {
  gpkg <- system.file("extdata", "caop_simplified.gpkg", package = "geopt")
  skip_if(gpkg == "", "bundled gpkg not available")

  for (level in c("freguesia", "municipio", "distrito", "nuts1", "nuts2", "nuts3")) {
    result <- find_gpkg_layer(gpkg, level)
    layer <- if (is.list(result)) result$layer else result
    expect_true(layer %in% sf::st_layers(gpkg)$name, info = level)
  }
  # The uls_municipio and aces_municipio layers also match "munic"; the
  # municipio layer is written first, so it wins.
  expect_equal(find_gpkg_layer(gpkg, "municipio"), "municipio")
})

# --- Dissolve helpers ------------------------------------------------------------

test_that("find_dissolve_column matches NUTS column name variants", {
  obj <- make_test_sf(cols = list(NUTS3 = c("a", "b"), other = c("x", "y")))
  expect_equal(find_dissolve_column(obj, "nuts3"), "NUTS3")

  obj2 <- make_test_sf(cols = list(nuts_2 = c("a", "b")))
  expect_equal(find_dissolve_column(obj2, "nuts2"), "nuts_2")
})

test_that("find_dissolve_column falls back to a broad match", {
  obj <- make_test_sf(cols = list(cod_nuts1_2024 = c("a", "b")))
  expect_equal(find_dissolve_column(obj, "nuts1"), "cod_nuts1_2024")
})

test_that("find_dissolve_column errors informatively", {
  obj <- make_test_sf(cols = list(foo = c("a", "b")))
  expect_error(find_dissolve_column(obj, "nuts3"), "Could not find column")
  expect_error(find_dissolve_column(obj, "municipio"), "No dissolve pattern")
})

test_that("dissolve_by merges geometries by group", {
  obj <- make_test_sf(n = 4L, cols = list(grp = c("a", "a", "b", "b")))
  out <- dissolve_by(obj, "grp")

  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 2L)
  expect_setequal(out$grp, c("a", "b"))
  # Total area is preserved by the union
  expect_equal(
    sum(sf::st_area(out)),
    sum(sf::st_area(obj))
  )
})

test_that("dissolve_by disambiguates same-named municipios by nuts3", {
  # Two municipios named "Lagoa" in different NUTS3 regions must stay separate
  obj <- make_test_sf(
    n = 3L,
    cols = list(
      municipio = c("Lagoa", "Lagoa", "Lagoa"),
      nuts3 = c("Algarve", "Algarve", "RA Acores")
    )
  )
  out <- dissolve_by(obj, "municipio")
  expect_equal(nrow(out), 2L)
})

test_that("dissolve_by drops NA groups", {
  obj <- make_test_sf(n = 3L, cols = list(grp = c("a", NA, "b")))
  out <- dissolve_by(obj, "grp")
  expect_equal(nrow(out), 2L)
})
