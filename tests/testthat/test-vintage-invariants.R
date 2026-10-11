# Invariants the atom model rests on. Offline.
#
# These assert facts about the DATA, not about any particular schema. Each one
# is load-bearing: if it stops holding, some part of the atom model is no longer
# valid and the build should fail rather than ship something subtly wrong.

# One row per 2011 freguesia -- an atom, bar POST_2011_CREATIONS -- with its
# name and municipio on that map and the 2013 and 2025 units it falls in.
atoms_2011 <- function() {
  a <- pt_crosswalk("2011", "2025")
  b <- pt_crosswalk("2011", "2013")
  r <- pt_lookup(admin_vintage = "2011")
  data.frame(dtmnfr_2011 = a$from, freguesia_2011 = a$name_from,
             dtmn = r$dtmn[match(a$from, r$dtmnfr)],
             municipio = r$municipio[match(a$from, r$dtmnfr)],
             dtmnfr_2013 = b$to[match(a$from, b$from)], dtmnfr = a$to,
             stringsAsFactors = FALSE)
}

# Freguesias created after 2011 by subdividing a 2011 unit, so the 2011
# partition alone does not cover them and they become atoms in their own right.
# Asserted as an exact inventory: a NEW post-2011 creation must fail here, not
# slip through a blanket allowance.
#
# Parque das Nacoes (Lisboa, Lei 56/2012) was carved out of Santa Maria dos
# Olivais and is the only case.
POST_2011_CREATIONS <- "110662"                # Parque das Nacoes

# --- the atom set ---------------------------------------------------------------

test_that("the 2011 partition (plus known creations) covers every later unit", {
  a <- atoms_2011()

  expect_setequal(setdiff(pt_lookup()$dtmnfr, a$dtmnfr), POST_2011_CREATIONS)
  expect_setequal(setdiff(pt_lookup(admin_vintage = "2013")$dtmnfr, a$dtmnfr_2013),
                  POST_2011_CREATIONS)
})

test_that("no 2011 unit is attributed to a sibling of its own restored self", {
  # A 2011 unit that was merged in 2013 and restored in 2025 must land on the
  # restored unit bearing its own name, not on a sibling from the same uniao.
  a <- atoms_2011()
  x <- pt_crosswalk("2013", "2025")
  cw <- data.frame(dtmnfr = x$to, dtmnfr_2013 = x$from, freguesia = x$name_to,
                   stringsAsFactors = FALSE)
  a$cur_name <- cw$freguesia[match(a$dtmnfr, cw$dtmnfr)]

  cand <- a[!is.na(a$freguesia_2011) &
              pt_normalize(a$freguesia_2011) != pt_normalize(a$cur_name), ]
  sib <- merge(cand[, c("dtmnfr_2011", "freguesia_2011", "dtmnfr_2013", "dtmnfr")],
               cw[, c("dtmnfr", "dtmnfr_2013", "freguesia")],
               by = "dtmnfr_2013", suffixes = c("", "_sib"))
  misattributed <- sib[sib$dtmnfr != sib$dtmnfr_sib &
                         pt_normalize(sib$freguesia_2011) ==
                         pt_normalize(sib$freguesia), ]
  expect_equal(nrow(misattributed), 0L)
})

test_that("vintages nest: an atom belongs to exactly one unit per vintage", {
  a <- atoms_2011()

  # single-valued membership -- the atom-model equivalent of `share` summing
  # to 1 once membership is materialised
  expect_equal(anyDuplicated(a$dtmnfr_2011), 0L)
  expect_false(anyNA(a$dtmnfr_2013))
  expect_false(anyNA(a$dtmnfr))

  # and the 2011 grain is finer than the later ones: no 2011 unit spans two
  # current ones
  expect_equal(max(table(a$dtmnfr_2011)), 1L)
})

test_that("codes are never recycled across vintages", {
  a <- atoms_2011()
  # territory, expressed as the set of atoms a unit covers
  by_vintage <- list(
    "2011" = split(a$dtmnfr_2011, a$dtmnfr_2011),
    "2013" = split(a$dtmnfr_2011, a$dtmnfr_2013),
    "2025" = split(a$dtmnfr_2011, a$dtmnfr)
  )
  for (pair in list(c("2011", "2013"), c("2013", "2025"), c("2011", "2025"))) {
    A <- by_vintage[[pair[1]]]; B <- by_vintage[[pair[2]]]
    shared <- intersect(names(A), names(B))
    expect_gt(length(shared), 2000)          # the check must have teeth
    differs <- vapply(shared, function(i) {
      !identical(sort(unique(A[[i]])), sort(unique(B[[i]])))
    }, logical(1L))
    expect_equal(sum(differs), 0L,
                 info = sprintf("%s vs %s", pair[1], pair[2]))
  }
})

# --- the dtmn spine -------------------------------------------------------------

test_that("dtmn is the first four digits of the dtmnfr, in every vintage", {
  d <- pt_lookup(); a <- atoms_2011()
  expect_true(all(substr(d$dtmnfr, 1, 4) == d$dtmn))
  expect_true(all(substr(a$dtmnfr_2011, 1, 4) == a$dtmn))
})

test_that("a vintage's municipio name follows from its own dtmn", {
  # Municipio codes and names are stable since the 1998 creation of Trofa,
  # Vizela and Odivelas, so ONE 308-row name table serves every vintage. This
  # is what makes vintage-scoped municipio membership free.
  d <- pt_lookup(); a <- atoms_2011()
  nm <- unique(d[, c("dtmn", "municipio")])

  expect_equal(nrow(nm), 308L)
  expect_equal(anyDuplicated(nm$dtmn), 0L)          # dtmn -> name is a function

  expect_equal(nm$municipio[match(substr(a$dtmnfr_2011, 1, 4), nm$dtmn)],
               a$municipio)
})

test_that("municipio names are not unique, and the duplicates are known", {
  # The reverse direction is NOT a function, which is why pt_match() needs
  # `context` at all. Asserted as an exact inventory so a new collision has to
  # be looked at rather than silently widening an ambiguity.
  #
  # Calheta is absent only because the registry stores the Azorean one as
  # "Calheta de Sao Jorge"; NAME_VARIANTS reintroduces the collision on
  # purpose. See R/match.R.
  d <- pt_lookup()
  nm <- unique(d[, c("dtmn", "municipio")])
  expect_setequal(unique(nm$municipio[duplicated(nm$municipio)]), "Lagoa")
  expect_setequal(nm$dtmn[nm$municipio == "Lagoa"], c("0806", "4201"))
})

test_that("a freguesia may change municipality between vintages", {
  # Guards the previous test against being trivially true. Pombalinho was
  # Santarem's in 2011 (141615) and is Golega's today (141203), which is why
  # municipio membership cannot be read off the current registry alone.
  a <- atoms_2011(); d <- pt_lookup()
  now <- d$dtmn[match(a$dtmnfr, d$dtmnfr)]
  moved <- which(!is.na(now) & substr(a$dtmnfr_2011, 1, 4) != now)
  expect_gt(length(moved), 0L)
  expect_true("141615" %in% a$dtmnfr_2011[moved])
})

# --- NUTS is a function of dtmn -------------------------------------------------

# How many municipios does `col` take more than one value inside?
n_varying_within_dtmn <- function(d, cols) {
  vapply(cols, function(cc) {
    sum(tapply(d[[cc]], d$dtmn, function(v) length(unique(v))) > 1)
  }, integer(1L))
}

test_that("every NUTS scheme is constant within a municipio", {
  # The load-bearing fact of the whole design: NUTS is a function of
  # (dtmn, nuts_vintage), so it is not a freguesia attribute and has no
  # relationship to the freguesia vintage.
  for (v in c("2002", "2013", "2024")) {
    d <- pt_lookup(nuts_vintage = v)
    nuts_cols <- grep("^nuts[123]", names(d), value = TRUE)
    expect_length(nuts_cols, 6L)
    expect_equal(n_varying_within_dtmn(d, nuts_cols),
                 stats::setNames(rep(0L, length(nuts_cols)), nuts_cols), info = v)
  }
})

test_that("health geographies are NOT constant within a municipio", {
  # The reason health must be keyed on dtmnfr while NUTS is keyed on dtmn.
  for (v in c("2022", "2024")) {
    d <- pt_lookup(health_vintage = v)
    expect_gt(n_varying_within_dtmn(d, "unit"), 0L, label = v)
  }
})

# --- the simplified-name rule ---------------------------------------------------

# DGT's own rule, recovered by inspection and used to derive the column for the
# 2013 vintage, where DGT's list (in CAOP 2024) leaves 32 uniões unsimplified.
# Deliberately NOT anchored: two names carry the phrase inside a parenthetical
# and are simplified in place.
UNIAO_RX <- "União d[aeo]s? freguesias d[eao]s? "

# The single name DGT leaves unsimplified: stripping yields the lowercase
# fragment "cidade de Santarem", so the rule only fires when what remains
# begins with a capital.
SIMPLIFY_EXCEPTION <- "União de freguesias da cidade de Santarém"

test_that("designacao_simplificada is reproducible from the official name", {
  d <- pt_lookup()
  derived <- ifelse(d$freguesia == SIMPLIFY_EXCEPTION, d$freguesia,
                    sub(UNIAO_RX, "", d$freguesia))
  expect_equal(derived, d$designacao_simplificada)
})

test_that("the simplify exception is still needed and still unique", {
  d <- pt_lookup()
  naive <- sub(UNIAO_RX, "", d$freguesia)
  off <- which(naive != d$designacao_simplificada)
  expect_equal(d$freguesia[off], SIMPLIFY_EXCEPTION)
})

test_that("the 2011 vintage needs no simplification", {
  # Unioes were created by Lei 11-A/2013, so no pre-2013 name carries the
  # phrase and simplified == official for that whole vintage.
  a <- atoms_2011()
  expect_equal(sum(grepl(UNIAO_RX, a$freguesia_2011)), 0L)
})
