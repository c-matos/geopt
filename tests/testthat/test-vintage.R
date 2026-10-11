# pt_crosswalk("2013", "2025") sanity + pt_recode() semantics. All offline.

xw <- pt_crosswalk("2013", "2025")

# Helper: one 2013 união split into at least 2 current freguesias
a_union <- {
  tab <- table(xw$from[xw$relation == "split"])
  names(tab)[tab >= 2][1]
}
union_members <- xw$to[xw$from == a_union]

# --- the 2013 -> 2025 crosswalk --------------------------------------------------

test_that("the crosswalk covers every current freguesia exactly once", {
  expect_setequal(xw$to, pt_lookup()$dtmnfr)
  expect_false(anyDuplicated(xw$to) > 0)
  expect_true(all(xw$relation %in% c("unchanged", "renumbered", "split")))
})

test_that("every current freguesia resolves to a 2013 code", {
  expect_false(anyNA(xw$from))
})

test_that("unchanged rows map to themselves, the rest to a different code", {
  unchanged <- xw[xw$relation == "unchanged", ]
  expect_true(all(unchanged$to == unchanged$from))

  moved <- xw[xw$relation != "unchanged", ]
  expect_gt(nrow(moved), 0)
  expect_true(all(moved$to != moved$from))
  # Most 2013-era counterparts are uniões named as such; a few unions carry
  # bare compound names ("Frazão Arreigada") or are plain recodings ("Colos")
  expect_gt(mean(grepl("(?i)uni[aã]o", moved$name_from, perl = TRUE)), 0.9)
  # União codes never appear as current codes
  expect_false(any(moved$from %in% xw$to))
})

test_that("split members stay within their união's municipality", {
  moved <- xw[xw$relation != "unchanged", ]
  expect_true(all(substr(moved$from, 1, 4) == substr(moved$to, 1, 4)))
})

# --- pt_recode: merges (2025 -> 2013) -----------------------------------------------

test_that("merging requires an aggregate function", {
  df <- data.frame(dtmnfr = union_members, cases = seq_along(union_members))
  expect_error(
    pt_recode(df, from = "2025", to = "2013", values = "cases"),
    "aggregate"
  )
})

test_that("merges aggregate values into the união", {
  df <- data.frame(dtmnfr = union_members, cases = rep(10, length(union_members)))
  out <- pt_recode(df, from = "2025", to = "2013", values = "cases", aggregate = sum,
                   quiet = TRUE)

  expect_equal(nrow(out), 1L)
  expect_equal(out$dtmnfr, a_union)
  expect_equal(out$cases, 10 * length(union_members))
  expect_match(out$freguesia, "(?i)uni[aã]o", perl = TRUE)
})

test_that("per-column aggregate functions are supported", {
  df <- data.frame(dtmnfr = union_members,
                   n = rep(2, length(union_members)),
                   peak = seq_along(union_members))
  out <- pt_recode(df, from = "2025", to = "2013", values = c("n", "peak"),
                   aggregate = list(n = sum, peak = max), quiet = TRUE)
  expect_equal(out$n, 2 * length(union_members))
  expect_equal(out$peak, length(union_members))
})

test_that("partial merges warn and aggregate the present members", {
  df <- data.frame(dtmnfr = union_members[1], cases = 7)
  # A single member of a multi-member união: still merges, but warns
  expect_warning(
    out <- pt_recode(df, from = "2025", to = "2013", values = "cases", aggregate = sum),
    "missing some constituent"
  )
  expect_equal(out$cases, 7)
})

test_that("carried columns survive merges only when constant", {
  df <- data.frame(
    dtmnfr = union_members,
    cases = rep(1, length(union_members)),
    region = "same",
    label = paste0("x", seq_along(union_members))
  )
  expect_message(
    out <- pt_recode(df, from = "2025", to = "2013", values = "cases", aggregate = sum),
    "not constant"
  )
  expect_equal(out$region, "same")
  expect_true(is.na(out$label))
})

test_that("unchanged codes convert 1:1 without aggregate", {
  unchanged_code <- xw$to[xw$relation == "unchanged"][1]
  df <- data.frame(dtmnfr = unchanged_code, cases = 5)
  out <- pt_recode(df, from = "2025", to = "2013", values = "cases", quiet = TRUE)
  expect_equal(nrow(out), 1L)
  expect_equal(out$dtmnfr, unchanged_code)
  expect_equal(out$cases, 5)
})

# --- pt_recode: splits (2013 -> current) ----------------------------------------------

test_that("splits refuse by default", {
  df <- data.frame(dtmnfr = a_union, cases = 100)
  expect_error(
    pt_recode(df, from = "2013", values = "cases"),
    "split"
  )
})

test_that("split = 'replicate' copies the value to every member", {
  df <- data.frame(dtmnfr = a_union, cases = 100)
  out <- pt_recode(df, from = "2013", values = "cases", split = "replicate",
                   quiet = TRUE)
  expect_equal(nrow(out), length(union_members))
  expect_setequal(out$dtmnfr, union_members)
  expect_true(all(out$cases == 100))
})

test_that("split = 'weight' with area distributes proportionally and exactly", {
  df <- data.frame(dtmnfr = a_union, cases = 100)
  out <- pt_recode(df, from = "2013", values = "cases", split = "weight",
                   weights = "area", quiet = TRUE)
  expect_equal(sum(out$cases), 100)
  expect_true(all(out$cases > 0))
  expect_true(all(out$cases < 100))

  freg <- get_dataset("pt_freguesias")
  areas <- freg$area_ha[match(out$dtmnfr, freg$dtmnfr)]
  expect_equal(out$cases, 100 * areas / sum(areas))
})

test_that("split = 'weight' accepts a custom named vector (e.g. population)", {
  df <- data.frame(dtmnfr = a_union, cases = 90)
  w <- stats::setNames(rep(1, length(union_members)), union_members)
  w[1] <- 2  # first member gets double weight
  out <- pt_recode(df, from = "2013", values = "cases", split = "weight",
                   weights = w, quiet = TRUE)
  expect_equal(sum(out$cases), 90)
  expect_equal(out$cases[match(names(w)[1], out$dtmnfr)],
               90 * 2 / (length(union_members) + 1))
})

test_that("split = 'weight' validates weights", {
  df <- data.frame(dtmnfr = a_union, cases = 1)
  expect_error(
    pt_recode(df, from = "2013", values = "cases", split = "weight"),
    "requires `weights`"
  )
  expect_error(
    pt_recode(df, from = "2013", values = "cases", split = "weight",
              weights = "population"),
    "named numeric vector"
  )
  incomplete <- stats::setNames(1, union_members[1])
  expect_error(
    pt_recode(df, from = "2013", values = "cases", split = "weight",
              weights = incomplete),
    "Missing or zero weights"
  )
})

test_that("non-value columns replicate across splits", {
  df <- data.frame(dtmnfr = a_union, cases = 10, source = "registry")
  out <- pt_recode(df, from = "2013", values = "cases", split = "replicate",
                   quiet = TRUE)
  expect_true(all(out$source == "registry"))
})

# --- pt_recode: edge cases -------------------------------------------------------------

test_that("unknown codes convert to NA with a warning", {
  df <- data.frame(dtmnfr = c("999999", xw$to[xw$relation == "unchanged"][1]),
                   cases = c(1, 2))
  expect_warning(
    out <- pt_recode(df, from = "2025", to = "2013", values = "cases", aggregate = sum),
    "not in the crosswalk"
  )
  expect_true(is.na(out$dtmnfr[1]))
  expect_equal(out$cases[2], 2)
})

test_that("codes with lost leading zeros are repaired", {
  unchanged_code <- xw$to[xw$relation == "unchanged" &
                                 substr(xw$to, 1, 1) == "0"][1]
  df <- data.frame(dtmnfr = as.numeric(unchanged_code), cases = 3)
  out <- pt_recode(df, from = "2025", to = "2013", values = "cases", quiet = TRUE)
  expect_equal(out$dtmnfr, unchanged_code)
})

test_that("pt_recode validates arguments", {
  df <- data.frame(dtmnfr = "010103", cases = 1)
  expect_error(pt_recode("nope", from = "2025"), "data.frame")
  expect_error(pt_recode(df, by = "missing_col", from = "2013"), "not found")
  expect_error(pt_recode(df, from = "2013", to = "2013"), "same vintage")
  expect_error(pt_recode(df, from = "2013", values = "nope"), "not in data")
})

test_that("pt_recode needs `from`, and `to` when `from` is the newest", {
  df <- data.frame(dtmnfr = "010103", cases = 1)
  # the data's vintage is never assumed
  expect_error(pt_recode(df), "`from` is required")
  # leaving `to` out means the newest, so from the newest there is nowhere to go
  expect_error(pt_recode(df, from = "2025"), "already the newest")
})

test_that("pt_recode names its columns the same for every target vintage", {
  df <- data.frame(dtmnfr = union_members, cases = 1, freguesia = "old name")
  to13 <- pt_recode(df, from = "2025", to = "2013", values = "cases",
                    aggregate = sum, quiet = TRUE)
  expect_named(to13, c("dtmnfr", "freguesia", "cases"))
  # an input `freguesia` names the source units, so the target's replaces it
  expect_match(to13$freguesia, "(?i)uni[aã]o", perl = TRUE)

  back <- pt_recode(to13, from = "2013", values = "cases",
                    split = "replicate", quiet = TRUE)
  expect_named(back, c("dtmnfr", "freguesia", "cases"))
  expect_setequal(back$dtmnfr, union_members)
})

# --- get_map(admin_vintage =, nuts_vintage =) ------------------------------------------

test_that("get_map draws the NUTS regions of the revision asked for", {
  n <- as.data.frame(pt_nuts_codes)
  for (v in c("2002", "2013", "2024")) {
    m <- get_map("nuts3", nuts_vintage = v)
    b <- m[m$geopt_type == "boundary", ]
    expect_setequal(b$nuts3_cod, unique(n$nuts3_cod[n$nuts_vintage == v]))
  }
  # leaving it out means the newest revision: the bundled map
  expect_identical(get_map("nuts3"), get_map("nuts3", nuts_vintage = "2024"))
})

test_that("nuts_vintage sets the NUTS columns of the other levels", {
  m13 <- get_map("municipio", nuts_vintage = "2013")
  m24 <- get_map("municipio")
  expect_equal(m13$nuts3[m13$dtmn %in% "1106"], "Área Metropolitana de Lisboa")
  expect_equal(m24$nuts3[m24$dtmn %in% "1106"], "Grande Lisboa")
  # same columns, in the same order
  expect_identical(names(m13), names(m24))
})

test_that("there are no boundaries for the 2011 and 2001 maps", {
  expect_error(get_map("municipio", admin_vintage = "2011"),
               "no boundaries for the 2011 map")
  expect_error(get_map("municipio", admin_vintage = "2001"), "pt_recode")
  expect_error(get_map("municipio", admin_vintage = "2001"),
               "get_censos[(][.][.][.], year = 2001[)]")
  expect_error(get_map("municipio", admin_vintage = "1999"), "must be one of")
  expect_error(get_map("municipio", nuts_vintage = "2010"), "must be one of")
})

test_that("a 2013 map is built from its cached freguesias and joins 2013 names", {
  client <- local_client()
  release <- CAOP_RELEASE_FOR_ADMIN[["2013"]]

  # One 2013 uniao standing in for the downloaded, simplified CAOP freguesias
  freg <- get_dataset("pt_freguesias")
  freg <- freg[freg$dtmn == "0308", ][1, ]
  freg$dtmnfr <- "030882"
  freg$freguesia <- "União das freguesias de Conde e Gandarela"
  for (col in NUTS_COLS) freg[[col]] <- NA_character_
  saveRDS(freg, vintage_cache_file(client, "freguesia", "2013", release))
  local_no_download()

  m <- get_map(
    "freguesia", admin_vintage = "2013", client = client,
    data = data.frame(freg = "União das freguesias de Conde e Gandarela",
                      mun = "Guimarães", v = 7),
    by = c(freguesia = "freg", municipio = "mun")
  )
  b <- m[m$geopt_type == "boundary", ]
  # matched by its 2013 name, which today's registry no longer has
  expect_equal(b$v, 7)
  n <- as.data.frame(pt_nuts_codes)
  expect_equal(b$nuts3, n$nuts3[n$nuts_vintage == "2024" & n$dtmn == "0308"])
  expect_true(file.exists(
    vintage_cache_file(client, "freguesia", "2013", release, "2024")
  ))
})
