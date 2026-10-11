# ULS / regiao de saude / ACES as map levels. Offline.

test_that("health datasets have the expected units", {
  uls <- get_dataset("pt_uls")
  expect_equal(nrow(uls), 55L)
  expect_true(all(c("uls", "area_ha", "n_municipios", "n_freguesias") %in% names(uls)))
  expect_false(anyDuplicated(uls$uls) > 0)

  rs <- get_dataset("pt_reg_saude")
  expect_equal(nrow(rs), 7L)

  aces <- get_dataset("pt_aces")
  expect_equal(nrow(aces), 71L)
  expect_false(anyDuplicated(aces$aces) > 0)
})

test_that("health maps carry only the region columns constant within a unit", {
  for (d in c("pt_uls", "pt_reg_saude", "pt_aces",
              "pt_uls_municipio", "pt_aces_municipio")) {
    x <- get_dataset(d)
    expect_true(all(c("nuts1_cod", "nuts1") %in% names(x)), info = d)
    expect_false(anyNA(x$nuts1_cod), info = d)
    # Not constant within every unit, so not carried
    expect_false(any(c("nuts2_cod", "nuts3_cod", "dt") %in% names(x)),
                 info = d)
  }
  # ULS Medio Tejo spans two regioes de saude
  expect_false("reg_saude" %in% names(get_dataset("pt_uls")))
  expect_false("reg_saude" %in% names(get_dataset("pt_uls_municipio")))
  # pt_aces is 2022 data throughout, so its regiao de saude has no suffix
  for (d in c("pt_aces", "pt_aces_municipio")) {
    expect_true("reg_saude" %in% names(get_dataset(d)), info = d)
    expect_false("reg_saude_2022" %in% names(get_dataset(d)), info = d)
  }

  uls <- get_dataset("pt_uls")
  expect_equal(as.vector(table(uls$nuts1_cod)[c("PT1", "PT2", "PT3")]), c(39L, 9L, 7L))
})

test_that("a health map can be filtered to one archipelago", {
  m <- get_map("uls", islands = "in_place")
  az <- m[m$nuts1_cod %in% "PT2", ]
  expect_equal(nrow(az), 9L)
  expect_true(all(startsWith(az$uls, "USI ")))
})

test_that("both health vintages cover every freguesia consistently", {
  # 2024 reform, and the organization it superseded
  h24 <- pt_lookup(health_vintage = "2024")
  h22 <- pt_lookup(health_vintage = "2022")
  expect_identical(h22$dtmnfr, h24$dtmnfr)
  expect_false(anyNA(h24$unit))
  expect_false(anyNA(h22$unit))
  expect_equal(length(unique(h24$unit)), 55L)
  expect_equal(length(unique(h22$unit)), 71L)

  # The 2024 regiao de saude moved exactly four municipalities
  moved <- unique(h24$dtmn[h24$reg_saude != h22$reg_saude])
  expect_setequal(moved, c("0115", "1001", "1011", "1421"))
  expect_equal(h24$reg_saude[h24$dtmn == "0115"][1], "Norte")
  expect_equal(h22$reg_saude[h22$dtmn == "0115"][1], "Centro")

  # Braga and Barcelos/Esposende are separate ULS
  expect_equal(unique(h24$unit[h24$dtmn == "0303"]), "ULS Braga")
  expect_equal(unique(h24$unit[h24$dtmn == "0302"]), "ULS Barcelos/Esposende")

  # Island health units, not "ULS"
  expect_true(all(c("USI São Miguel", "CS Funchal Zona I") %in% h24$unit))
  expect_false(any(grepl("^Regi", h24$unit)))
})

test_that("uls_municipio and aces_municipio are usable at municipality grain", {
  h24 <- pt_lookup(health_vintage = "2024")
  h22 <- pt_lookup(health_vintage = "2022")

  # One value per municipality, by construction
  hs <- list(uls_municipio = h24, aces_municipio = h22)
  for (col in names(hs)) {
    h <- hs[[col]]
    per_dtmn <- tapply(h$unit_municipio, h$dtmn, function(v) length(unique(v)))
    expect_true(all(per_dtmn == 1L), info = col)
  }

  # Lomba is the only Gondomar freguesia outside both ULS Santo Antonio and
  # ACES Gondomar. Its freguesia-grain units are accurate, but at municipio
  # grain it is reported with the rest of Gondomar -- which is what keeps
  # ULS Gaia/Espinho and ACES Gondomar reportable on their own.
  lomba24 <- h24[h24$dtmnfr == "130405", ]
  lomba22 <- h22[h22$dtmnfr == "130405", ]
  expect_equal(lomba24$unit, "ULS Vila Nova de Gaia/Espinho")
  expect_equal(lomba22$unit, "ACES Espinho/Gaia")
  expect_equal(lomba24$unit_municipio, "ULS Santo António + São João")
  expect_equal(lomba22$unit_municipio, "ACES Gondomar")

  expect_true("ULS Vila Nova de Gaia/Espinho" %in% h24$unit_municipio)
  expect_true("ACES Gondomar" %in% h22$unit_municipio)

  # ... and the whole municipio agrees with it
  expect_equal(unique(h22$unit_municipio[h22$dtmn == "1304"]), "ACES Gondomar")
})

test_that("the municipio-grain maps hold the uls_municipio/aces_municipio units", {
  h <- list("2024" = pt_lookup(health_vintage = "2024"),
            "2022" = pt_lookup(health_vintage = "2022"))
  maps <- c(uls_municipio = "2024", aces_municipio = "2022")
  for (lv in names(maps)) {
    x <- get_dataset(paste0("pt_", lv))
    u <- h[[maps[[lv]]]]
    expect_false(anyDuplicated(x[[lv]]) > 0, info = lv)
    expect_setequal(x[[lv]], u$unit_municipio)
    # Whole municipalities: n_municipios and n_freguesias add up from the lookup
    n_freg <- table(u$unit_municipio)
    expect_equal(x$n_freguesias, as.vector(n_freg[x[[lv]]]), info = lv)
    n_mun <- tapply(u$dtmn, u$unit_municipio, function(d) length(unique(d)))
    expect_equal(x$n_municipios, as.vector(n_mun[x[[lv]]]), info = lv)
    expect_equal(sum(x$area_ha), sum(get_dataset("pt_freguesias")$area_ha),
                 tolerance = 1e-6, info = lv)
  }
  expect_equal(nrow(get_dataset("pt_uls_municipio")), 50L)
  expect_equal(nrow(get_dataset("pt_aces_municipio")), 66L)
})

test_that("the municipio-grain maps draw Lomba with Gondomar", {
  fr <- get_dataset("pt_freguesias")
  lomba <- suppressWarnings(sf::st_point_on_surface(fr[fr$dtmnfr == "130405", ]))
  u <- get_dataset("pt_uls_municipio")
  a <- get_dataset("pt_aces_municipio")
  expect_equal(u$uls_municipio[sf::st_intersects(lomba, u)[[1]]],
               "ULS Santo António + São João")
  expect_equal(a$aces_municipio[sf::st_intersects(lomba, a)[[1]]], "ACES Gondomar")
})

test_that("municipio-grain units match by their merged name only", {
  merged <- "ULS Santo António + São João"
  expect_equal(pt_match(c(merged, "uls santo antonio + sao joao", "ULS Coimbra"),
                        level = "uls_municipio", quiet = TRUE),
               c(merged, merged, "ULS Coimbra"), ignore_attr = TRUE)
  # A member of a merged unit is not a unit at this level
  expect_true(is.na(pt_match("ULS São João", level = "uls_municipio",
                             quiet = TRUE)))
  expect_equal(pt_match("ACES Espinho/Gaia + Gaia", level = "aces_municipio",
                        quiet = TRUE),
               "ACES Espinho/Gaia + Gaia", ignore_attr = TRUE)
  expect_equal(nrow(pt_lookup("uls_municipio", health_vintage = "2024")), 50L)
})

test_that("data by municipio aggregates onto the uls_municipio map", {
  df <- data.frame(concelho = c("Lisboa", "Odivelas", "Porto", "Maia"),
                   v = c(10, 5, 7, 3))
  df <- pt_join(df, by = c(municipio = "concelho"), quiet = TRUE)
  agg <- aggregate(v ~ uls_municipio, data = df, FUN = sum)
  m <- suppressMessages(get_map("uls_municipio", data = agg, by = "uls_municipio"))
  got <- unique(sf::st_drop_geometry(m[!is.na(m$v), c("uls_municipio", "v")]))
  expect_equal(nrow(got), 2L)
  expect_equal(got$v[startsWith(got$uls_municipio, "ULS Lisboa Ocidental")], 15)
  expect_equal(got$v[startsWith(got$uls_municipio, "ULS Santo Ant")], 10)
  expect_equal(detect_map_level(m), "uls_municipio")

  # pt_join at this level brings the region columns constant within a unit
  out <- pt_join(data.frame(aces_municipio = "ACES Gondomar"),
                 by = "aces_municipio", quiet = TRUE)
  expect_equal(out$reg_saude, "Norte")
})

test_that("a uls map carrying a uls_municipio column is still detected as uls", {
  m <- get_map("uls")
  m$uls_municipio <- "x"
  expect_equal(detect_map_level(m), "uls")
})

test_that("aces is matchable and joinable", {
  expect_equal(pt_match("ACES Baixo Vouga", level = "aces", quiet = TRUE),
               "ACES Baixo Vouga", ignore_attr = TRUE)

  df <- data.frame(aces = c("ACES Baixo Vouga", "aces braga"), v = 1:2)
  out <- suppressMessages(pt_join(df, by = "aces"))
  expect_false(any(is.na(out$v)))
  # The ACES vintage brings its own regiao de saude, not the 2024 one, and as
  # the only one it needs no suffix
  expect_true("reg_saude" %in% names(out))
  expect_false("reg_saude_2022" %in% names(out))
  expect_equal(out$reg_saude[out$aces == "ACES Baixo Vouga"], "Centro")
})

test_that("health geographies area matches the freguesia total", {
  uls <- get_dataset("pt_uls")
  freg <- get_dataset("pt_freguesias")
  expect_equal(sum(uls$area_ha), sum(freg$area_ha), tolerance = 1e-6)
})

test_that("get_map works at health levels with composition", {
  for (level in HEALTH_LEVELS) {
    m <- get_map(level)
    expect_s3_class(m, "sf")
    expect_true(any(m$geopt_type == "frame"))
    # Islands repositioned like any other level
    cent <- suppressWarnings(sf::st_centroid(m[m$geopt_type == "boundary", ]))
    expect_true(all(sf::st_coordinates(cent)[, 1] > -12))
  }
})

test_that("ULS split municipalities are drawn freguesia-accurately", {
  m <- get_map("uls", islands = island_layout(frames = FALSE))
  # The Lisbon municipality is split across three ULS; all three exist
  expect_true(all(c("ULS São José", "ULS Santa Maria",
                    "ULS Lisboa Ocidental") %in% m$uls))
  # Islands carry their own health units
  expect_true(all(c("USI São Miguel", "USI Terceira", "CS Funchal Zona I")
                  %in% m$uls))
})

test_that("data joins work at health levels", {
  uls_names <- get_dataset("pt_uls")$uls
  second <- setdiff(uls_names, "ULS Coimbra")[1]
  # Second name in lowercase: matches through normalization
  df <- data.frame(unit = c("ULS Coimbra", tolower(second)), v = c(1, 2))
  m <- suppressMessages(
    get_map("uls", data = df, by = c(uls = "unit"), islands = island_layout(frames = FALSE))
  )
  # Count matched UNITS, not rows: island units are cropped into several
  # inset rows that legitimately share the unit's value
  expect_setequal(unique(m$uls[!is.na(m$v)]), c("ULS Coimbra", second))
  expect_equal(unique(m$v[m$uls == "ULS Coimbra"]), 1)

  df2 <- data.frame(reg = "LVT", v = 9)
  m2 <- suppressMessages(
    get_map("reg_saude", data = df2, by = c(reg_saude = "reg"), islands = island_layout(frames = FALSE))
  )
  expect_equal(sum(!is.na(m2$v)), 1L)
})

test_that("pt_join works at reg_saude level", {
  df <- data.frame(reg_saude = c("Norte", "Algarve"), v = 1:2)
  out <- suppressMessages(pt_join(df, by = "reg_saude"))
  expect_false(any(is.na(out$v)))
})

test_that("plot_pt renders health levels with both renderers", {
  skip_if_not_installed("ggplot2")
  m <- get_map("uls")
  m$val <- seq_len(nrow(m))

  expect_equal(detect_map_level(m), "uls")
  p <- plot_pt(m, value = "val")
  expect_s3_class(p, "ggplot")

  skip_if_not_installed("echarts4r")
  skip_if_not_installed("htmlwidgets")
  e <- plot_pt(m, value = "val", renderer = "echarts")
  expect_s3_class(e, "echarts4r")
  keys <- vapply(e$x$opts$series[[1]]$data, `[[`, character(1L), "name")
  expect_true("ULS São José" %in% keys)
})

test_that("plot_pt builds health maps directly from level", {
  skip_if_not_installed("ggplot2")
  p <- plot_pt(level = "reg_saude")
  expect_s3_class(p, "ggplot")
})

test_that("health levels exist on the 2025 map only, and not in get_caop", {
  expect_error(get_map("uls", admin_vintage = "2013"),
               "only available on the 2025 map")
  expect_error(get_map("uls_municipio", admin_vintage = "2013"),
               "only available on the 2025 map")
  # NUTS 1, all a health map carries, is the same in every revision
  expect_equal(get_map("uls", nuts_vintage = "2002"), get_map("uls"))
  expect_error(local_client()$get_caop("continente", "uls"), "Invalid level")
})
