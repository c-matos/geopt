# data-raw/derive_datasets.R
#
# Derives every bundled dataset from the simplified freguesias:
#   - pt_freguesias ... pt_nuts1 and the health maps (pt_uls, pt_reg_saude,
#     pt_aces, pt_uls_municipio, pt_aces_municipio): boundary sf objects where
#     each level carries its OWN identity columns (codes + names) and correctly
#     aggregated area.
#   - pt_registry, pt_nuts_codes, pt_health_codes: the lookup tables, one per
#     vintage axis.
#   - the atom model in R/sysdata.rda (build_atoms.R), which pt_crosswalk(),
#     pt_recode() and pt_match() derive every vintage conversion from.
# pt_codes (a wide lookup table) and two crosswalk tables are built only as the
# targets the atom model is checked against; they are not shipped (see
# section 5).
#
# Inputs -- see data-raw/README.md. Four CSVs are the SOURCE OF TRUTH; all
# already hold the correct values, so this script only joins and validates, it
# does not infer anything:
#
#   - data-raw/freguesia_registry_2025.csv one row per CURRENT freguesia (the
#       2025 map, 3259). Everything keyed on the current dtmnfr: the 2013 code,
#       health units (both vintages), NUTS 2013 and NUTS 2002. Its
#       freguesia_2013 column is not hand-edited: fetch_2013_names.R writes it
#       from CAOP 2024.
#   - data-raw/freguesia_names_2013.csv    the earlier names of the 2013 map's
#       freguesias: 25 were renamed by law while that map was in force, and DGT
#       corrected some spellings. They match as names of the 2013 vintage.
#   - data-raw/freguesia_registry_2011.csv one row per freguesia of the map the
#       2011 census used (4260), the one in force until 2013. A separate file
#       because that vintage is a finer grain -- 751 current freguesias have more
#       than one predecessor there, so these rows cannot live in the 3259-row
#       registry.
#   - data-raw/freguesia_registry_2001.csv one row per (2001, 2011) freguesia
#       pair sharing territory: the map the 2001 census used (4241 freguesias).
#       Written by fetch_2001_registry.R.
#
#   - data-raw/freg_simplified.rds  (written by prepare_boundaries.R), or the
#       currently bundled pt_freguesias as a fallback (no network needed).
#       Supplies geometry and the CAOP identity/NUTS 2024 columns.
#
# To correct the data, edit the CSV -- the underlying authority is legislation,
# not any upstream file.
#
# Vintages carried by pt_codes (section 3):
#   NUTS      current (2024, from CAOP) | *_2013 | *_2002 (pre-2013 scheme)
#   health    reg_saude + uls (2024 reform) | reg_saude_2022 + aces (former ARS/ACES)
#   freguesia current (3259) | 2013 (3092, pt_crosswalk) | 2011 (4260, pt_crosswalk_2011)
#             | 2001 (4241, freguesia_registry_2001.csv)
#
# Usage:
#   source("data-raw/derive_datasets.R")

library(sf)
devtools::load_all()

# --- 1. Load and normalize the base freguesias --------------------------------

if (file.exists("data-raw/freg_simplified.rds")) {
  message("Using data-raw/freg_simplified.rds")
  freg <- readRDS("data-raw/freg_simplified.rds")
} else {
  message("Using bundled pt_freguesias as base")
  freg <- get_dataset("pt_freguesias")
}

# CAOP and geopt both call the freguesia code `dtmnfr`. dtmn and dt are
# recomputed below.
stopifnot("dtmnfr" %in% names(freg))

# Every bundled boundary dataset names its geometry column `geometry`, so that
# get_map() can bind rows across datasets. CAOP's GeoPackages call it `geom`.
if (!identical(attr(freg, "sf_column"), "geometry")) sf::st_geometry(freg) <- "geometry"

# NUTS codes: CAOP ships the Eurostat suffix ("11A"); use the full form.
pt_prefix <- function(x) ifelse(is.na(x) | x == "", NA_character_,
                                paste0("PT", sub("^PT", "", x)))

freg$dtmnfr      <- pt_pad_code(freg$dtmnfr, "freguesia")
freg$dtmn         <- substr(freg$dtmnfr, 1L, 4L)
freg$dt <- substr(freg$dtmnfr, 1L, 2L)
freg$nuts3_cod    <- pt_prefix(freg$nuts3_cod)
freg$nuts2_cod    <- substr(freg$nuts3_cod, 1L, 4L)
freg$nuts1_cod    <- substr(freg$nuts3_cod, 1L, 3L)

# --- 2. Consistency assertions -------------------------------------------------

assert_nested <- function(df, child, parent) {
  bad <- stats::aggregate(df[[parent]], list(df[[child]]),
                          function(v) length(unique(v)))
  bad <- bad[bad$x > 1L, ]
  if (nrow(bad) > 0L) {
    stop(sprintf("'%s' does not nest in '%s': %s",
                 child, parent, paste(bad[[1]], collapse = ", ")))
  }
}

fdf <- sf::st_drop_geometry(freg)
assert_nested(fdf, "dtmn", "municipio")
assert_nested(fdf, "dtmn", "nuts3_cod")
assert_nested(fdf, "dtmn", "dt")
assert_nested(fdf, "dt", "distrito_ilha")
assert_nested(fdf, "nuts3_cod", "nuts3")
assert_nested(fdf, "nuts3_cod", "nuts2")
assert_nested(fdf, "nuts2_cod", "nuts2")
assert_nested(fdf, "nuts1_cod", "nuts1")
stopifnot(!anyDuplicated(fdf$dtmnfr))
message(sprintf("Base: %d freguesias, all nesting assertions passed", nrow(fdf)))

# --- 3. Build pt_codes ----------------------------------------------------------
# The registry is already at current freguesia grain and already correct, so
# this is a plain join plus assertions. Nothing is inferred.

reg <- utils::read.csv("data-raw/freguesia_registry_2025.csv",
                       colClasses = "character", encoding = "UTF-8")
reg$dtmnfr <- pt_pad_code(reg$dtmnfr, "freguesia")
reg$dtmnfr_2013 <- pt_pad_code(reg$dtmnfr_2013, "freguesia")
stopifnot(!anyDuplicated(reg$dtmnfr))

# The registry must describe exactly the freguesias CAOP ships.
missing_reg <- setdiff(fdf$dtmnfr, reg$dtmnfr)
extra_reg   <- setdiff(reg$dtmnfr, fdf$dtmnfr)
if (length(missing_reg) > 0L || length(extra_reg) > 0L) {
  stop(sprintf(
    "freguesia_registry_2025.csv does not match the CAOP freguesias.\n  missing: %s\n  extra: %s",
    paste(missing_reg, collapse = ", "), paste(extra_reg, collapse = ", ")))
}

codes <- fdf[, c("dtmnfr", "freguesia", "designacao_simplificada",
                 "dtmn", "municipio", "dt", "distrito_ilha",
                 "nuts1_cod", "nuts1", "nuts2_cod", "nuts2",
                 "nuts3_cod", "nuts3")]

ir <- match(codes$dtmnfr, reg$dtmnfr)

# The registry carries freguesia/municipio purely as editing aids. Check them
# against CAOP rather than trusting them, so a stale row is caught here.
drift <- which(reg$freguesia[ir] != codes$freguesia |
                 reg$municipio[ir] != codes$municipio)
if (length(drift) > 0L) {
  stop(sprintf(
    "freguesia_registry_2025.csv names disagree with CAOP for %d row(s), e.g. %s",
    length(drift),
    paste(sprintf("%s ('%s'/'%s' vs CAOP '%s'/'%s')", codes$dtmnfr[drift[1]],
                  reg$freguesia[ir][drift[1]], reg$municipio[ir][drift[1]],
                  codes$freguesia[drift[1]], codes$municipio[drift[1]]),
          collapse = "; ")))
}

REGISTRY_COLS <- c("reg_saude", "uls", "reg_saude_2022", "aces",
                   "nuts2_cod_2013", "nuts2_2013", "nuts3_cod_2013", "nuts3_2013",
                   "nuts3_cod_2002", "nuts3_2002")
for (col in REGISTRY_COLS) codes[[col]] <- reg[[col]][ir]

# --- 3a. Registry assertions ---------------------------------------------------
# Hand-edited source: fail loudly rather than shipping a silent inconsistency.

for (col in REGISTRY_COLS) {
  n <- sum(is.na(codes[[col]]) | codes[[col]] == "")
  if (n > 0L) stop(sprintf("freguesia_registry_2025.csv: '%s' is empty on %d row(s)", col, n))
}

# NUTS 2013 nests: the NUTS2 code must be the NUTS3 code's prefix.
bad <- which(codes$nuts2_cod_2013 != substr(codes$nuts3_cod_2013, 1L, 4L))
if (length(bad) > 0L) {
  stop(sprintf("nuts2_cod_2013 is not the prefix of nuts3_cod_2013 for %d row(s), e.g. %s",
               length(bad), paste(codes$dtmnfr[bad[1:min(5, length(bad))]], collapse = ", ")))
}

# Every code <-> name pair must be 1:1, in both directions.
assert_code_name <- function(df, code_col, name_col) {
  for (pair in list(c(code_col, name_col), c(name_col, code_col))) {
    agg <- tapply(df[[pair[2]]], df[[pair[1]]], function(v) length(unique(v)))
    bad <- names(agg)[agg > 1L]
    if (length(bad) > 0L) {
      stop(sprintf("'%s' is not 1:1 with '%s': %s has %s",
                   code_col, name_col, pair[1],
                   paste(sprintf("%s -> %d values", bad, agg[bad]), collapse = "; ")))
    }
  }
}
assert_code_name(codes, "nuts2_cod_2013", "nuts2_2013")
assert_code_name(codes, "nuts3_cod_2013", "nuts3_2013")
assert_code_name(codes, "nuts3_cod_2002", "nuts3_2002")

# Statistical geographies are municipio-level: they must not split a municipio.
for (col in c("nuts3_cod_2013", "nuts3_cod_2002")) {
  assert_nested(codes, "dtmn", col)
}

message(sprintf(
  "Registry: %d freguesias | %d nuts3_2013 | %d nuts3_2002 | %d uls | %d aces",
  nrow(codes), length(unique(codes$nuts3_cod_2013)),
  length(unique(codes$nuts3_cod_2002)), length(unique(codes$uls)),
  length(unique(codes$aces))))

# --- 3b. uls_municipio / aces_municipio ----------------------------------------
# The coarsest health unit that is well-defined for data at municipio grain.
# Units that share any municipio are merged into one "fictitious" unit
# (connected components of the dtmn <-> unit graph).
#
# Overrides: a municipio with a single outlier freguesia would drag two
# otherwise-disjoint units into one merged unit. Where the established practice
# is to report that freguesia with the rest of its municipio, we follow it, so
# the outlier's unit stays one of its own at municipio grain. Lomba is the only
# such case -- the one freguesia of Gondomar outside both ULS Santo Antonio and
# ACES Gondomar. Without it, neither ULS Vila Nova de Gaia/Espinho nor ACES
# Gondomar could be reported separately. The freguesia-grain `uls` and `aces`
# columns are left untouched.
MUNICIPIO_GRAIN_OVERRIDES <- "130405"   # Lomba, Gondomar

#' Value to count a freguesia under at municipio grain: normally its own, but
#' for an override the (necessarily unique) value of the rest of its municipio.
#' @noRd
municipio_grain_key <- function(codes, unit_col) {
  key <- codes[[unit_col]]
  for (fr in MUNICIPIO_GRAIN_OVERRIDES) {
    i <- which(codes$dtmnfr == fr)
    if (length(i) != 1L) stop("Override freguesia not found: ", fr)
    rest <- unique(codes[[unit_col]][codes$dtmn == codes$dtmn[i] & codes$dtmnfr != fr])
    if (length(rest) != 1L) {
      stop(sprintf("Override %s: the rest of municipio %s spans %d '%s' values (%s)",
                   fr, codes$dtmn[i], length(rest), unit_col,
                   paste(rest, collapse = ", ")))
    }
    if (!identical(key[i], rest)) {
      message(sprintf("  %s_municipio override: %s (%s -> %s)",
                      unit_col, fr, key[i], rest))
    }
    key[i] <- rest
  }
  key
}

#' Merge units that share a municipio into one label (connected components)
#' @noRd
municipio_grain_unit <- function(dtmn, key) {
  edges <- unique(data.frame(dtmn = dtmn, u = key, stringsAsFactors = FALSE))
  comp <- seq_along(unique(edges$u))
  names(comp) <- unique(edges$u)
  repeat {
    changed <- FALSE
    for (d in unique(edges$dtmn)) {
      us <- edges$u[edges$dtmn == d]
      target <- min(comp[us])
      if (any(comp[us] != target)) {
        comp[us] <- target
        changed <- TRUE
      }
    }
    if (!changed) break
  }
  # Label a merged component by factoring out the unit-type prefix the members
  # share ("ULS ", "ACES ", "USI ", "CS "), falling back to the full names.
  lab <- vapply(comp, function(id) {
    members <- sort(names(comp)[comp == id])
    if (length(members) == 1L) return(members)
    pre <- sub("^([A-Za-z]+) .*$", "\\1 ", members[1L])
    if (nzchar(pre) && all(startsWith(members, pre))) {
      paste0(pre, paste(substring(members, nchar(pre) + 1L), collapse = " + "))
    } else {
      paste(members, collapse = " + ")
    }
  }, character(1L))
  unname(lab[key])
}

message("Municipio-grain health units:")
for (u in c("uls", "aces")) {
  key <- municipio_grain_key(codes, u)
  codes[[paste0(u, "_municipio")]] <- municipio_grain_unit(codes$dtmn, key)
  # By construction this must be constant within every municipio -- that is the
  # whole point of the column.
  assert_nested(codes, "dtmn", paste0(u, "_municipio"))
  # Genuine merges only: an overridden freguesia also differs from its own
  # unit, but its municipio-grain unit is not a merged one.
  merged <- sort(unique(grep(" [+] ", codes[[paste0(u, "_municipio")]], value = TRUE)))
  if (length(merged) > 0L) {
    message(sprintf("  merged %s units:\n    %s", u, paste(merged, collapse = "\n    ")))
  }
}

# Explicit column order: identity -> geography -> NUTS 2024 ->
# current health (2024 reform) -> former health (ARS/ACES) -> NUTS 2013 -> 2002.
PT_CODES_COLS <- c(
  "dtmnfr", "freguesia", "designacao_simplificada",
  "dtmn", "municipio", "dt", "distrito_ilha",
  "nuts1_cod", "nuts1", "nuts2_cod", "nuts2", "nuts3_cod", "nuts3",
  "reg_saude", "uls", "uls_municipio",
  "reg_saude_2022", "aces", "aces_municipio",
  "nuts2_cod_2013", "nuts2_2013", "nuts3_cod_2013", "nuts3_2013",
  "nuts3_cod_2002", "nuts3_2002"
)
stopifnot(setequal(PT_CODES_COLS, names(codes)))
pt_codes <- codes[order(codes$dtmnfr), PT_CODES_COLS]
rownames(pt_codes) <- NULL

# --- 3c. Crosswalks -------------------------------------------------------------
# current <-> 2013 comes straight off the registry; `relation` is a function of
# the two codes.

pt_crosswalk <- data.frame(
  dtmnfr        = codes$dtmnfr,
  freguesia      = codes$freguesia,
  dtmn           = codes$dtmn,
  municipio      = codes$municipio,
  dtmnfr_2013   = reg$dtmnfr_2013[ir],
  freguesia_2013 = ifelse(reg$freguesia_2013[ir] == "", NA_character_,
                          reg$freguesia_2013[ir]),
  stringsAsFactors = FALSE
)
stopifnot(!anyNA(pt_crosswalk$dtmnfr_2013))

# The 2013 names are the last ones that map had (CAOP 2024's), written by
# fetch_2013_names.R: exactly one per 2013 freguesia, repeated on the row of
# each current freguesia it became.
n13 <- tapply(pt_crosswalk$freguesia_2013, pt_crosswalk$dtmnfr_2013,
              function(v) length(unique(v)))
if (anyNA(pt_crosswalk$freguesia_2013) || any(n13 != 1L)) {
  stop(sprintf(
    "freguesia_registry_2025.csv: freguesia_2013 must give each 2013 freguesia exactly one name. Rerun data-raw/fetch_2013_names.R. Offending: %s",
    paste(utils::head(c(names(n13)[n13 != 1L],
                        pt_crosswalk$dtmnfr_2013[is.na(pt_crosswalk$freguesia_2013)]), 10),
          collapse = ", ")))
}

# The names those freguesias carried earlier. A closed historical record, kept
# by hand; see data-raw/README.md.
names13 <- utils::read.csv("data-raw/freguesia_names_2013.csv",
                           colClasses = "character", encoding = "UTF-8")
names13$dtmnfr_2013 <- pt_pad_code(names13$dtmnfr_2013, "freguesia")
last13 <- pt_crosswalk$freguesia_2013[match(names13$dtmnfr_2013,
                                            pt_crosswalk$dtmnfr_2013)]
bad13 <- c(
  "unknown 2013 code" = sum(is.na(last13)),
  "freguesia_2013 out of date" = sum(names13$freguesia_2013 != last13, na.rm = TRUE),
  "former_name empty or equal to the last name" =
    sum(!nzchar(names13$former_name) | names13$former_name == last13, na.rm = TRUE),
  "duplicate (code, former_name)" =
    sum(duplicated(names13[, c("dtmnfr_2013", "former_name")])),
  "change not renamed/corrected" =
    sum(!names13$change %in% c("renamed", "corrected")),
  "renamed without law or date" =
    sum(names13$change == "renamed" &
          (!nzchar(names13$law) | !nzchar(names13$published))),
  "CAOP years out of order or past 2023" =
    sum(!(as.integer(names13$caop_first) <= as.integer(names13$caop_last) &
            as.integer(names13$caop_first) >= 2013L &
            as.integer(names13$caop_last) <= 2023L))
)
if (any(bad13 > 0L)) {
  stop("freguesia_names_2013.csv: ",
       paste(sprintf("%s (%d row(s))", names(bad13)[bad13 > 0L], bad13[bad13 > 0L]),
             collapse = "; "))
}
message(sprintf("freguesia_names_2013: %d earlier names of %d freguesias (%d by law)",
                nrow(names13), length(unique(names13$dtmnfr_2013)),
                sum(names13$change == "renamed")))

pt_crosswalk$relation <- ifelse(
  pt_crosswalk$dtmnfr == pt_crosswalk$dtmnfr_2013, "unchanged", "restored")
pt_crosswalk <- pt_crosswalk[order(pt_crosswalk$dtmnfr), ]
rownames(pt_crosswalk) <- NULL
message(sprintf("pt_crosswalk: %d rows | %s", nrow(pt_crosswalk),
                paste(names(table(pt_crosswalk$relation)),
                      table(pt_crosswalk$relation), sep = "=", collapse = " ")))

# The 2011 vintage is a finer grain (4260 rows), so it lives in its own file.
# Everything except dtmnfr_2011/freguesia_2011/dtmnfr/relation is recomputed
# here from the current-grain tables, keeping the layers consistent.

reg11 <- utils::read.csv("data-raw/freguesia_registry_2011.csv",
                         colClasses = "character", encoding = "UTF-8")
reg11$dtmnfr_2011 <- pt_pad_code(reg11$dtmnfr_2011, "freguesia")
reg11$dtmnfr      <- pt_pad_code(reg11$dtmnfr, "freguesia")
stopifnot(!anyDuplicated(reg11$dtmnfr_2011))

i11 <- match(reg11$dtmnfr, pt_crosswalk$dtmnfr)
if (anyNA(i11)) {
  stop(sprintf("freguesia_registry_2011.csv maps to %d unknown current freguesia(s): %s",
               sum(is.na(i11)),
               paste(utils::head(unique(reg11$dtmnfr[is.na(i11)]), 5), collapse = ", ")))
}
pt_crosswalk_2011 <- data.frame(
  dtmnfr_2011   = reg11$dtmnfr_2011,
  freguesia_2011 = ifelse(reg11$freguesia_2011 == "", NA_character_,
                          reg11$freguesia_2011),
  dtmn           = substr(reg11$dtmnfr_2011, 1L, 4L),
  municipio      = pt_codes$municipio[match(substr(reg11$dtmnfr_2011, 1L, 4L),
                                            pt_codes$dtmn)],
  dtmnfr_2013   = pt_crosswalk$dtmnfr_2013[i11],
  freguesia_2013 = pt_crosswalk$freguesia_2013[i11],
  dtmnfr        = reg11$dtmnfr,
  freguesia      = pt_crosswalk$freguesia[i11],
  relation       = reg11$relation,
  stringsAsFactors = FALSE
)
pt_crosswalk_2011 <- pt_crosswalk_2011[order(pt_crosswalk_2011$dtmnfr_2011), ]
rownames(pt_crosswalk_2011) <- NULL
stopifnot(!anyNA(pt_crosswalk_2011$dtmnfr), !anyNA(pt_crosswalk_2011$dtmnfr_2013),
          !anyNA(pt_crosswalk_2011$municipio), !anyNA(pt_crosswalk_2011$relation))
message(sprintf("pt_crosswalk_2011: %d freguesias | %s",
                nrow(pt_crosswalk_2011),
                paste(names(table(pt_crosswalk_2011$relation)),
                      table(pt_crosswalk_2011$relation), sep = "=", collapse = " ")))

# The 2001 vintage: pairs of (2001, 2011) freguesias sharing territory. Coarser
# than 2011 except where a 2011 freguesia was carved out of two 2001 ones, which
# build_atoms() turns into one atom per part.
reg01 <- utils::read.csv("data-raw/freguesia_registry_2001.csv",
                         colClasses = "character", encoding = "UTF-8")
reg01$dtmnfr_2001 <- pt_pad_code(reg01$dtmnfr_2001, "freguesia")
reg01$dtmnfr_2011 <- pt_pad_code(reg01$dtmnfr_2011, "freguesia")
stopifnot(!anyDuplicated(reg01[, c("dtmnfr_2001", "dtmnfr_2011")]),
          setequal(reg01$dtmnfr_2011, reg11$dtmnfr_2011),
          !anyNA(reg01$freguesia_2001), all(nzchar(reg01$freguesia_2001)))
n_names <- tapply(reg01$freguesia_2001, reg01$dtmnfr_2001, function(v) length(unique(v)))
if (any(n_names > 1L)) {
  stop("freguesia_registry_2001.csv gives more than one name for: ",
       paste(names(n_names)[n_names > 1L], collapse = ", "))
}
message(sprintf("freguesia_registry_2001: %d freguesias, %d pairs with 2011",
                length(unique(reg01$dtmnfr_2001)), nrow(reg01)))

# --- 3d. Atom model (internal) ---------------------------------------------------
# The normalized form the vintage axes rest on: atoms -> units -> membership,
# from which pt_codes and both crosswalks above are DERIVABLE. The shipped
# lookup tables and the vintage functions (pt_crosswalk(), pt_recode()) are
# views over these.
#
# verify_atom_model() is Gate A: it proves the reshape loses nothing by
# rebuilding pt_codes and both crosswalks from the atoms and comparing. The
# build stops if it cannot.

source("data-raw/build_atoms.R")

message("\n=== Atom model ===")
atoms      <- build_atoms(pt_codes, pt_crosswalk, pt_crosswalk_2011, reg01)
atom_freg  <- atom_freguesias(atoms, pt_codes, pt_crosswalk, pt_crosswalk_2011, reg01)
atom_model <- build_units_membership(atoms, atom_freg, pt_codes,
                                     pt_crosswalk, pt_crosswalk_2011, reg01,
                                     names13)
units      <- atom_model$units
unit_names <- atom_model$unit_names
membership <- atom_model$membership

message(sprintf("  atoms %d | units %d | unit_names %d | membership %d",
                nrow(atoms), nrow(units), nrow(unit_names), nrow(membership)))

message("\n--- Gate A ---")
verify_atom_model(atoms, atom_freg, atom_model,
                  pt_codes, pt_crosswalk, pt_crosswalk_2011, reg01)

# A unit without a name is a data gap the model surfaces rather than hides.
# There are none: fetch_2013_names.R names every 2013 freguesia, and the NUTS2
# 2002 names, which cannot be borrowed from 2013 ("Lisboa" became "Area
# Metropolitana de Lisboa"), are NUTS2_2002_NAMES in build_atoms.R.
unnamed <- units[is.na(units$name), ]
if (nrow(unnamed)) {
  message(sprintf("  units without a name: %d", nrow(unnamed)))
  for (i in seq_len(nrow(unnamed))) {
    message(sprintf("    %-10s %-5s %s", unnamed$scheme[i], unnamed$vintage[i],
                    unnamed$code[i]))
  }
}

# --- 3e. Exported tables ---------------------------------------------------------
# Three long tables, each on its own axis. The wide tables built above are only
# the targets the atom model is checked against, and are not shipped (see
# section 5).

message("\n=== Exported vintage tables ===")
exported       <- build_exported(atoms, atom_freg, atom_model, pt_codes)
pt_registry     <- exported$pt_registry
pt_nuts_codes   <- exported$pt_nuts_codes
pt_health_codes <- exported$pt_health_codes

message(sprintf("  pt_registry     %5d rows  (%s)", nrow(pt_registry),
                paste(names(table(pt_registry$admin_vintage)),
                      table(pt_registry$admin_vintage), sep = "=", collapse = " ")))
message(sprintf("  pt_nuts_codes   %5d rows  (%s)", nrow(pt_nuts_codes),
                paste(names(table(pt_nuts_codes$nuts_vintage)),
                      table(pt_nuts_codes$nuts_vintage), sep = "=", collapse = " ")))
message(sprintf("  pt_health_codes %5d rows  (%s)", nrow(pt_health_codes),
                paste(names(table(pt_health_codes$health_vintage)),
                      table(pt_health_codes$health_vintage), sep = "=", collapse = " ")))

message("\n--- Gate B ---")
verify_exported(exported, pt_codes)

# --- 4. Boundary datasets --------------------------------------------------------
# Dissolving uses the package internals (LEVEL_KEY_COLS / dissolve_level in
# R/derive.R), shared with get_map(admin_vintage =, nuts_vintage =).

freg_cols <- c("dtmnfr", "freguesia", "designacao_simplificada",
               "dtmn", "municipio", "dt", "distrito_ilha",
               "nuts1_cod", "nuts1", "nuts2_cod", "nuts2",
               "nuts3_cod", "nuts3", "area_ha", "perimetro_km")
pt_freguesias <- freg[, intersect(freg_cols, names(freg))]
pt_freguesias <- pt_freguesias[order(pt_freguesias$dtmnfr), ]

message("Dissolving municipios...")
pt_municipios <- build_level_from_freguesias(freg, "municipio")
message("Dissolving distritos...")
pt_distritos <- build_level_from_freguesias(freg, "distrito")
message("Dissolving nuts3...")
pt_nuts3 <- build_level_from_freguesias(freg, "nuts3")
message("Dissolving nuts2...")
pt_nuts2 <- build_level_from_freguesias(freg, "nuts2")
message("Dissolving nuts1...")
pt_nuts1 <- build_level_from_freguesias(freg, "nuts1")

# Health geographies: join the pt_codes mappings onto the freguesias and
# dissolve. Same simplified base, so edges align with every other level. Each
# carries nuts1 (and ACES their 2022 regiao de saude) so it can be filtered by
# region; dissolve_level() stops if a key column is not constant in a unit.
freg_h <- freg
idx_codes <- match(freg_h$dtmnfr, pt_codes$dtmnfr)
for (col in c("uls", "uls_municipio", "reg_saude",
              "aces", "aces_municipio", "reg_saude_2022")) {
  freg_h[[col]] <- pt_codes[[col]][idx_codes]
  stopifnot(!anyNA(freg_h[[col]]))
}

message("Dissolving uls...")
pt_uls <- build_level_from_freguesias(freg_h, "uls")
message("Dissolving reg_saude...")
pt_reg_saude <- build_level_from_freguesias(freg_h, "reg_saude")
message("Dissolving aces...")
# pt_aces is 2022 data throughout, so its regiao de saude is plain `reg_saude`,
# as pt_lookup(health_vintage = "2022") names it.
freg_aces <- freg_h
freg_aces$reg_saude <- freg_aces$reg_saude_2022
pt_aces <- build_level_from_freguesias(freg_aces, "aces")

# The municipio-grain units, for data by municipio. Their column is constant
# within every municipio (asserted in 3b), so each unit is a set of whole
# municipios: Lomba is drawn with the rest of Gondomar, as it is counted.
message("Dissolving uls_municipio...")
pt_uls_municipio <- build_level_from_freguesias(freg_h, "uls_municipio")
message("Dissolving aces_municipio...")
pt_aces_municipio <- build_level_from_freguesias(freg_aces, "aces_municipio")

# --- 5. Save --------------------------------------------------------------------

# The GeoPackage layers are written in this order. Keep `municipio` ahead of
# the *_municipio levels: find_gpkg_layer() takes the first layer whose name
# matches the level.
results <- list(
  freguesia = pt_freguesias, municipio = pt_municipios,
  distrito = pt_distritos, nuts1 = pt_nuts1, nuts2 = pt_nuts2, nuts3 = pt_nuts3,
  uls = pt_uls, reg_saude = pt_reg_saude, aces = pt_aces,
  uls_municipio = pt_uls_municipio, aces_municipio = pt_aces_municipio
)

message("\n=== Summary ===")
for (nm in names(results)) {
  message(sprintf("  %-12s %4d features", nm, nrow(results[[nm]])))
}
message(sprintf("  %-12s %4d rows", "pt_codes", nrow(pt_codes)))
message(sprintf("  %-12s %4d rows", "pt_crosswalk", nrow(pt_crosswalk)))
message(sprintf("  %-14s %4d rows", "pt_crosswalk_2011", nrow(pt_crosswalk_2011)))

message("\n=== Saving .rda files ===")
save_datasets <- list(
  pt_freguesias = pt_freguesias, pt_municipios = pt_municipios,
  pt_distritos = pt_distritos, pt_nuts1 = pt_nuts1, pt_nuts2 = pt_nuts2,
  pt_nuts3 = pt_nuts3, pt_uls = pt_uls, pt_reg_saude = pt_reg_saude,
  pt_aces = pt_aces, pt_uls_municipio = pt_uls_municipio,
  pt_aces_municipio = pt_aces_municipio,
  pt_registry = pt_registry, pt_nuts_codes = pt_nuts_codes,
  pt_health_codes = pt_health_codes
)
# pt_codes, pt_crosswalk and pt_crosswalk_2011 are BUILT above but not shipped:
# they are the comparison targets for Gate A and Gate B, which prove the atom
# model reproduces them exactly. The wide shape conflates the vintage axes, so
# users get pt_registry / pt_nuts_codes / pt_health_codes, pt_lookup() and
# pt_crosswalk() instead.
# Written with base save() rather than usethis::use_data(): use_data() reads
# the object NAMES off its unevaluated arguments, so it cannot be driven from a
# named list via do.call(). version = 3 + compress = "xz" matches what
# use_data() produces (DESCRIPTION already requires R >= 4.1).
dir.create("data", showWarnings = FALSE)
save_env <- list2env(save_datasets, parent = emptyenv())
for (nm in names(save_datasets)) {
  save(list = nm, envir = save_env,
       file = file.path("data", paste0(nm, ".rda")),
       compress = "xz", version = 3)
  message(sprintf("  saved data/%s.rda", nm))
}

message("\n=== Saving internal data ===")
source("data-raw/save_internal.R")
save_internal(atoms = atoms, units = units, unit_names = unit_names,
              membership = membership)

message("\n=== Saving GeoPackage ===")
gpkg_path <- file.path("inst/extdata", "caop_simplified.gpkg")
dir.create(dirname(gpkg_path), recursive = TRUE, showWarnings = FALSE)
if (file.exists(gpkg_path)) file.remove(gpkg_path)
for (nm in names(results)) {
  st_write(results[[nm]], gpkg_path, layer = nm, quiet = TRUE)
}

rda_files <- list.files("data", pattern = "\\.rda$", full.names = TRUE)
message(sprintf(
  "\n=== Package data size ===\n  .rda total:  %.1f MB\n  .gpkg:       %.1f MB",
  sum(file.size(rda_files)) / 1024^2, file.size(gpkg_path) / 1024^2
))

message("\nDone!")
