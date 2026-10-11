# pt_lookup() and the three long vintage tables. Offline.

reg  <- get_dataset("pt_registry")
nuts <- get_dataset("pt_nuts_codes")
hlth <- get_dataset("pt_health_codes")

# --- dataset shape --------------------------------------------------------------

test_that("pt_registry is long on admin_vintage with the documented counts", {
  expect_named(reg, c("admin_vintage", "dtmnfr", "freguesia",
                      "designacao_simplificada", "dtmn", "municipio",
                      "dt", "distrito_ilha"))
  expect_equal(table(reg$admin_vintage),
               table(rep(c("2001", "2011", "2013", "2025"),
                         c(4241L, 4260L, 3092L, 3259L))),
               ignore_attr = TRUE)
  # No unit in any vintage lacks a name
  expect_false(anyNA(reg))
  # a dtmnfr identifies one unit within its vintage, never more
  expect_equal(anyDuplicated(paste(reg$admin_vintage, reg$dtmnfr)), 0L)
  expect_true(all(substr(reg$dtmnfr, 1L, 4L) == reg$dtmn))
})

test_that("pt_nuts_codes is 308 municipios per revision and complete", {
  expect_named(nuts, c("nuts_vintage", "dtmn", "nuts1_cod", "nuts1",
                       "nuts2_cod", "nuts2", "nuts3_cod", "nuts3"))
  expect_true(all(table(nuts$nuts_vintage) == 308L))
  expect_false(anyNA(nuts))
  expect_equal(anyDuplicated(paste(nuts$nuts_vintage, nuts$dtmn)), 0L)

  # NUTS nests: the NUTS2 code is the NUTS3 code's prefix, NUTS1 is NUTS2's
  expect_true(all(nuts$nuts2_cod == substr(nuts$nuts3_cod, 1L, 4L)))
  expect_true(all(nuts$nuts1_cod == substr(nuts$nuts2_cod, 1L, 3L)))

  counts <- tapply(nuts$nuts3_cod, nuts$nuts_vintage, function(v) length(unique(v)))
  expect_equal(as.integer(counts[c("2002", "2013", "2024")]), c(30L, 25L, 26L))
})

test_that("PT17 is named for its own revision, not borrowed", {
  # The one NUTS II name that changed, and the reason the 2002 names could not
  # be derived from the 2013 ones.
  nm <- function(v) unique(nuts$nuts2[nuts$nuts_vintage == v & nuts$nuts2_cod == "PT17"])
  expect_equal(nm("2002"), "Lisboa")
  expect_equal(nm("2013"), "Área Metropolitana de Lisboa")
})

test_that("pt_health_codes is freguesia-grained for a reason", {
  expect_named(hlth, c("health_vintage", "dtmnfr", "reg_saude", "scheme",
                       "unit", "unit_municipio"))
  expect_equal(as.integer(table(hlth$health_vintage)), c(3259L, 3259L))
  expect_setequal(unique(paste(hlth$health_vintage, hlth$scheme)),
                  c("2022 aces", "2024 uls"))

  # `unit` varies within a municipio -- if it did not, this could be keyed on
  # dtmn like pt_nuts_codes is
  h <- hlth[hlth$health_vintage == "2024", ]
  h$dtmn <- substr(h$dtmnfr, 1L, 4L)
  expect_gt(sum(tapply(h$unit, h$dtmn, function(v) length(unique(v))) > 1L), 0L)
})

# --- pt_lookup ------------------------------------------------------------------

test_that("each admin vintage returns its own unit set", {
  expect_equal(nrow(pt_lookup(admin_vintage = "2001")), 4241L)
  expect_equal(nrow(pt_lookup(admin_vintage = "2011")), 4260L)
  expect_equal(nrow(pt_lookup(admin_vintage = "2013")), 3092L)
  expect_equal(nrow(pt_lookup(admin_vintage = "2025")), 3259L)
})

test_that("the 2013 freguesias carry the last name they had on that map", {
  # As in CAOP 2024 and INE's tables. Renamed by Lei 87/2015, Lei 108/2015,
  # Lei 50/2015 and Lei 22/2020, after the 2013 reform created them.
  r <- pt_lookup(admin_vintage = "2013")
  nm <- function(code) r$freguesia[r$dtmnfr == code]
  expect_equal(nm("060520"), "Buarcos e São Julião")
  expect_equal(nm("080708"), "São Gonçalo de Lagos")
  expect_equal(nm("171438"), "Vila Real")
  expect_equal(nm("030719"), "Paços")
  expect_false(anyNA(r$freguesia))
  expect_false(any(r$freguesia != trimws(r$freguesia)))
})

test_that("leaving a vintage out means the newest; NA drops the NUTS columns", {
  expect_equal(pt_lookup(), pt_lookup(admin_vintage = "2025", nuts_vintage = "2024"))
  expect_false(any(grepl("^nuts", names(pt_lookup(nuts_vintage = NA)))))
  # health columns are the exception: only there when asked for
  expect_false("reg_saude" %in% names(pt_lookup()))
})

test_that("the axes are independent", {
  # The combination INE actually publishes -- 2013 freguesias under NUTS 2024 --
  # must be expressible, and must differ from the same freguesias under 2013.
  a <- pt_lookup(admin_vintage = "2013", nuts_vintage = "2024")
  b <- pt_lookup(admin_vintage = "2013", nuts_vintage = "2013")
  expect_equal(nrow(a), 3092L)
  expect_equal(a$dtmnfr, b$dtmnfr)
  expect_false(identical(a$nuts3_cod, b$nuts3_cod))
})

test_that("coarser levels expose only what they determine", {
  m <- pt_lookup("municipio")
  expect_equal(nrow(m), 308L)
  expect_false("dtmnfr" %in% names(m))       # not constant within a municipio
  expect_equal(names(m)[1:2], c("dtmn", "municipio"))

  n3 <- pt_lookup("nuts3")
  expect_equal(nrow(n3), 26L)
  expect_equal(names(n3)[1:2], c("nuts3_cod", "nuts3"))
  expect_false("dtmn" %in% names(n3))

  expect_equal(nrow(pt_lookup("nuts3", nuts_vintage = "2002")), 30L)
})

test_that("health is opt-in and reachable from any admin vintage", {
  expect_false("unit" %in% names(pt_lookup()))

  h <- pt_lookup(health_vintage = "2024")
  expect_true(all(c("reg_saude", "unit", "unit_municipio") %in% names(h)))
  expect_false(anyNA(h$unit))

  # a pre-2013 freguesia falls inside exactly one current one, so its health
  # unit is well defined even though the mapping is recorded for 2025
  old <- pt_lookup(admin_vintage = "2011", health_vintage = "2024")
  expect_equal(nrow(old), 4260L)
  expect_false(anyNA(old$unit))

  expect_equal(nrow(pt_lookup("uls", health_vintage = "2024")), 55L)
  expect_equal(nrow(pt_lookup("aces", health_vintage = "2022")), 71L)
})

test_that("a health level reads its own health geography when none is given", {
  expect_equal(pt_lookup("uls"), pt_lookup("uls", health_vintage = "2024"))
  expect_equal(pt_lookup("uls_municipio"),
               pt_lookup("uls_municipio", health_vintage = "2024"))
  expect_equal(pt_lookup("reg_saude"), pt_lookup("reg_saude", health_vintage = "2024"))
  expect_equal(pt_lookup("aces"), pt_lookup("aces", health_vintage = "2022"))
  expect_equal(pt_lookup("aces_municipio"),
               pt_lookup("aces_municipio", health_vintage = "2022"))
  expect_equal(nrow(pt_lookup("uls")), 55L)
  expect_equal(nrow(pt_lookup("aces")), 71L)
})

test_that("a health level read in the other geography returns its units, with a warning", {
  # ULS exist only in 2024 and ACES only in 2022: the units come back, but they
  # are not the ones the level names, so say so.
  expect_warning(u22 <- pt_lookup("uls", health_vintage = "2022"),
                 "returns ACES, not ULS.*level = \"aces\"")
  expect_equal(u22, suppressWarnings(pt_lookup("aces")))
  expect_warning(a24 <- pt_lookup("aces", health_vintage = "2024"),
                 "returns ULS, not ACES.*level = \"uls\"")
  expect_equal(a24, pt_lookup("uls"))
  expect_warning(pt_lookup("uls_municipio", health_vintage = "2022"),
                 "level = \"aces_municipio\"")
  expect_warning(pt_lookup("aces_municipio", health_vintage = "2024"),
                 "level = \"uls_municipio\"")

  # the regioes de saude exist in both, and a level's own geography is no news
  expect_no_warning(pt_lookup("reg_saude", health_vintage = "2022"))
  expect_no_warning(pt_lookup("uls", health_vintage = "2024"))
  expect_no_warning(pt_lookup("aces", health_vintage = "2022"))
})

test_that("bad arguments fail loudly rather than returning something", {
  expect_error(pt_lookup(admin_vintage = "1999"), "must be one of")
  expect_error(pt_lookup(nuts_vintage = "2021"), "must be one of")
  expect_error(pt_lookup(health_vintage = "2019"), "must be one of")
  expect_error(pt_lookup("concelho"))
  # a level whose columns were dropped must not silently return freguesias
  expect_error(pt_lookup("nuts2", nuts_vintage = NA), "NUTS columns")
})

# --- derived crosswalks ---------------------------------------------------------

test_that("crosswalks derive from shared atoms, in both directions", {
  x <- atom_relations("2013", "2025")
  expect_setequal(unique(x$from), pt_lookup(admin_vintage = "2013")$dtmnfr)
  expect_setequal(unique(x$to), reg$dtmnfr[reg$admin_vintage == "2025"])

  # every vintage pair works, not just adjacent ones
  for (p in list(c("2011", "2013"), c("2011", "2025"), c("2013", "2025"),
                 c("2001", "2011"), c("2001", "2025"))) {
    y <- atom_relations(p[1], p[2])
    expect_gt(nrow(y), 3000L)
    expect_false(anyNA(y$from))
    expect_false(anyNA(y$to))
  }
})

test_that("the relation taxonomy separates renumbering from splitting", {
  # No 2013 freguesia that kept its code into 2025 is "renamed": the 2013 names
  # are the last ones that map had, which the 2025 map kept.
  x <- atom_relations("2013", "2025")
  expect_setequal(unique(x$relation), c("unchanged", "renumbered", "split"))

  # Renames do happen between the 2011 and 2013 maps
  expect_true("renamed" %in% atom_relations("2011", "2013")$relation)

  # Colos kept its territory and changed only its code
  colos <- x[x$from == "021118", ]
  expect_equal(nrow(colos), 1L)
  expect_equal(colos$to, "021124")
  expect_equal(colos$relation, "renumbered")

  # and a genuine split is a split
  expect_equal(x$relation[x$from == "021122" & x$to == "021123"], "split")
})
