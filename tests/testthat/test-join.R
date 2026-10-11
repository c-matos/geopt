# --- pt_join ---------------------------------------------------------------------

test_that("pt_join appends codes and administrative context by name", {
  df <- data.frame(
    concelho = c("Porto", "Águeda", "Lagoa (Açores)"),
    value = c(1, 2, 3)
  )
  out <- suppressMessages(pt_join(df, by = c(municipio = "concelho")))

  expect_equal(nrow(out), 3L)
  expect_equal(out$value, df$value)
  expect_true(all(c("dtmn", "municipio", "nuts2_cod", "nuts3_cod") %in% names(out)))
  expect_equal(out$municipio[1], "Porto")
  expect_false(any(is.na(out$dtmn)))

  # Municipality grain: the freguesia-accurate uls column must NOT be
  # appended (it is not constant within Lisboa/Porto/Ourem), but the
  # coarsened uls_municipio must be.
  expect_false("uls" %in% names(out))
  expect_true("uls_municipio" %in% names(out))
  expect_false("dtmnfr" %in% names(out))
})

test_that("pt_join works with a bare keyword and code columns", {
  df <- data.frame(dtmn = c("1106", "1312"), x = 1:2)
  out <- suppressMessages(pt_join(df, by = "dtmn"))
  expect_equal(out$municipio, c("Lisboa", "Porto"))

  # Codes that lost their leading zero still join
  df2 <- data.frame(dtmn = c(115, 1106), x = 1:2)
  out2 <- suppressMessages(pt_join(df2, by = "dtmn"))
  expect_false(any(is.na(out2$municipio)))
})

test_that("pt_join disambiguates freguesias via a context column", {
  codes <- pt_lookup()
  reused <- names(which(table(codes$freguesia) > 1))[1]
  muns <- codes$municipio[codes$freguesia == reused][1:2]

  df <- data.frame(freg = c(reused, reused), mun = muns)
  out <- suppressMessages(pt_join(df, by = c(freguesia = "freg", municipio = "mun")))

  expect_false(any(is.na(out$dtmnfr)))
  expect_equal(length(unique(out$dtmnfr)), 2L)
  # Freguesia grain gets the full table, including uls
  expect_true("uls" %in% names(out))
})

test_that("pt_join does not overwrite existing columns", {
  df <- data.frame(concelho = "Porto", municipio = "keep me")
  out <- suppressMessages(pt_join(df, by = c(municipio = "concelho")))
  expect_equal(out$municipio, "keep me")
})

test_that("pt_join attaches the match report and reports counts", {
  df <- data.frame(concelho = c("Porto", "Atlantis"))
  expect_message(
    out <- suppressWarnings(pt_join(df, by = c(municipio = "concelho"))),
    "1/2 row"
  )
  rep <- pt_match_report(out)
  expect_equal(rep$method, c("exact", "unmatched"))
})

test_that("pt_join validates arguments", {
  df <- data.frame(concelho = "Porto")
  expect_error(pt_join("not a df", by = "municipio"), "data.frame")
  expect_error(pt_join(df, by = c(planeta = "concelho")), "Unknown `by` keyword")
  expect_error(pt_join(df, by = "municipio"), "not found in data")
  expect_error(
    pt_join(df, by = c(freguesia = "concelho", municipio = "concelho",
                       distrito = "concelho")),
    "at most 2"
  )
  expect_error(pt_join(df, by = c(municipio = "concelho"), admin_vintage = "2002"),
               "`admin_vintage` must be one of")
  expect_error(pt_join(df, by = c(municipio = "concelho"), nuts_vintage = "2025"),
               "`nuts_vintage` must be one of")
})

test_that("pt_join keeps data on its own freguesia map", {
  # The uniao of Conde and Gandarela (Guimaraes) was split in 2025, so its code
  # exists on the 2013 map only -- the map INE publishes on.
  ine <- data.frame(dtmnfr = "030882", v = 1)
  expect_true(is.na(suppressWarnings(pt_join(ine, by = "dtmnfr", quiet = TRUE))$freguesia))

  out <- pt_join(ine, by = "dtmnfr", admin_vintage = "2013", quiet = TRUE)
  expect_equal(out$freguesia, "Uni\u00e3o das freguesias de Conde e Gandarela")
  expect_equal(out$dtmn, "0308")
  # health is recorded on the current map, and both halves share their units
  expect_equal(out$uls, "ULS Alto Ave")

  # names are matched on that map too
  by_name <- pt_join(data.frame(f = "Uni\u00e3o das freguesias de Conde e Gandarela",
                                m = "Guimar\u00e3es"),
                     by = c(freguesia = "f", municipio = "m"),
                     admin_vintage = "2013", quiet = TRUE)
  expect_equal(by_name$dtmnfr, "030882")

  # "auto" finds the map, says which, and appends that map's columns
  expect_message(auto <- pt_join(ine, by = "dtmnfr", admin_vintage = "auto"),
                 "pt_join: matching against the 2013")
  expect_equal(auto, out, ignore_attr = TRUE)
})

test_that("pt_join appends the NUTS regions of the revision asked for", {
  df <- data.frame(concelho = "Lisboa")
  expect_equal(pt_join(df, by = c(municipio = "concelho"), quiet = TRUE)$nuts2_cod,
               "PT1A")
  old <- pt_join(df, by = c(municipio = "concelho"), nuts_vintage = "2013",
                 quiet = TRUE)
  expect_equal(old$nuts2_cod, "PT17")
  expect_false(any(grepl("_20[0-9]{2}$", grep("^nuts", names(old), value = TRUE))))

  # at a NUTS level, the names are matched in that revision
  n <- pt_join(data.frame(r = "Minho-Lima"), by = c(nuts3 = "r"),
               nuts_vintage = "2002", quiet = TRUE)
  expect_equal(n$nuts3_cod, "PT111")
})

test_that("pt_join ignores admin_vintage at the health levels", {
  u <- data.frame(uls = "ULS Coimbra")
  expect_equal(pt_join(u, by = "uls", admin_vintage = "2013", quiet = TRUE),
               pt_join(u, by = "uls", quiet = TRUE))
})

# --- get_map(data =, by =) ----------------------------------------------------------

test_that("get_map joins user data onto boundaries", {
  df <- data.frame(concelho = c("Porto", "Lisboa"), value = c(10, 20))
  m <- suppressMessages(
    get_map("municipio", data = df, by = c(municipio = "concelho"), islands = island_layout(frames = FALSE))
  )

  expect_true("value" %in% names(m))
  expect_equal(m$value[m$municipio == "Porto"], 10)
  expect_equal(m$value[m$municipio == "Lisboa"], 20)
  expect_equal(sum(!is.na(m$value)), 2L)
})

test_that("get_map join fills frames and unmatched boundaries with NA", {
  df <- data.frame(dtmn = c("1106"), value = 99)
  m <- suppressMessages(
    get_map("municipio", data = df, by = "dtmn")
  )
  frames <- m[m$geopt_type == "frame", ]
  expect_gt(nrow(frames), 0)
  expect_true(all(is.na(frames$value)))
  expect_equal(sum(!is.na(m$value)), 1L)
})

test_that("get_map join works at nuts levels with codes and names", {
  df <- data.frame(nuts2 = c("Norte", "Centro"), value = 1:2)
  m <- suppressMessages(
    get_map("nuts2", data = df, by = "nuts2", islands = island_layout(frames = FALSE))
  )
  expect_equal(m$value[m$nuts2 == "Norte"], 1)

  df2 <- data.frame(cod = c("PT11"), value = 5)
  m2 <- suppressMessages(
    get_map("nuts2", data = df2, by = c(nuts2_cod = "cod"), islands = island_layout(frames = FALSE))
  )
  expect_equal(m2$value[m2$nuts2 == "Norte"], 5)
})

test_that("get_map join validates by-level agreement and requires by", {
  df <- data.frame(concelho = "Porto", value = 1)
  expect_error(
    get_map("nuts2", data = df, by = c(municipio = "concelho")),
    "must match the map level"
  )
  expect_error(get_map("municipio", data = df), "`by` is required")
})

test_that("get_map join warns about unmatched data and duplicated keys", {
  df <- data.frame(concelho = c("Porto", "Atlantis"), value = 1:2)
  warns <- character(0)
  m <- withCallingHandlers(
    suppressMessages(
      get_map("municipio", data = df, by = c(municipio = "concelho"),
              islands = island_layout(frames = FALSE))
    ),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_true(any(grepl("did not match any boundary", warns)))
  expect_equal(m$value[m$municipio == "Porto"], 1)

  df_dup <- data.frame(concelho = c("Porto", "Porto"), value = 1:2)
  expect_warning(
    suppressMessages(
      get_map("municipio", data = df_dup, by = c(municipio = "concelho"),
              islands = island_layout(frames = FALSE))
    ),
    "duplicated key"
  )
})

test_that("get_map join skips clashing column names with a warning", {
  df <- data.frame(concelho = "Porto", area_ha = 123, value = 1)
  expect_warning(
    m <- suppressMessages(
      get_map("municipio", data = df, by = c(municipio = "concelho"),
              islands = island_layout(frames = FALSE))
    ),
    "not joined"
  )
  expect_true("value" %in% names(m))
  # Boundary area_ha wins
  expect_false(any(m$area_ha == 123, na.rm = TRUE))
})

test_that("get_map join skips a clashing column silently when it agrees", {
  # the names pt_recode() and pt_join() add are the map's own: nothing is lost
  df <- data.frame(concelho = c("Porto", "Faro"), municipio = c("Porto", "Faro"),
                   value = 1:2)
  expect_no_warning(
    m <- suppressMessages(
      get_map("municipio", data = df, by = c(municipio = "concelho"),
              islands = island_layout(frames = FALSE))
    )
  )
  expect_equal(m$value[m$municipio == "Faro"], 2L)
})
