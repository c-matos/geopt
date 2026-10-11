# data-raw/fetch_2013_names.R
#
# Fills the freguesia_2013 column of data-raw/freguesia_registry_2025.csv with the
# last name each freguesia of the 2013 map carried: its name in CAOP 2024, DGT's
# last release on that map (CAOP_RELEASE_FOR_ADMIN in R/derive.R), checked name
# by name against INE's.
#
# Why the last names. The 2013 map was in force from the 2013 reform until the
# 2025 restorations, and 25 of its freguesias were renamed by law in that time:
# "Buarcos" became "Buarcos e São Julião" (Lei 87/2015), the união of Lagos
# became "São Gonçalo de Lagos" (Lei 108/2015), and so on. The last names are
# the ones INE publishes for the 2013 map -- the 2021 census and every series it
# still issues on that map -- and the ones on the boundaries that
# get_map(admin_vintage = "2013") draws. A unit that kept its code into 2025
# keeps its name too, so it does not look renamed. The earlier names are in
# data-raw/freguesia_names_2013.csv, and match as names of the 2013 map as well.
#
# Sources. DGT: CAOP 2024, through the package's own GeoClient (about 140 MB;
# cached after the first run). INE: indicator 0012396, whose geography dimension
# ("Local de residência à data dos Censos [2021] (NUTS - 2024)") is the 2013
# map's 3092 freguesias. The two agree on every name; the script stops if that
# ever stops being true, rather than choosing between them.
#
# Requires the ineptr2 package and network access.
#
# Usage:
#   source("data-raw/fetch_2013_names.R")
# then rebuild:
#   source("data-raw/derive_datasets.R")

stopifnot(requireNamespace("ineptr2", quietly = TRUE))
pkgload::load_all(".", quiet = TRUE)   # GeoClient, pt_pad_code(), CAOP_RELEASE_FOR_ADMIN

RELEASE   <- unname(CAOP_RELEASE_FOR_ADMIN[["2013"]])
INDICATOR <- "0012396"
GEO_DIM   <- "2"
CSV       <- "data-raw/freguesia_registry_2025.csv"

# --- 1. DGT: the names in CAOP 2024 ------------------------------------------------

client <- GeoClient$new()
caop <- do.call(rbind, lapply(VALID_REGIONS, function(r) {
  x <- sf::st_drop_geometry(client$get_caop(r, "freguesia", year = RELEASE))
  names(x) <- tolower(names(x))
  code_col <- intersect(c("dtmnfr", "dicofre"), names(x))[1L]
  if (is.na(code_col) || !"freguesia" %in% names(x)) {
    stop(sprintf("CAOP %d (%s): no code or freguesia column among %s",
                 RELEASE, r, paste(names(x), collapse = ", ")))
  }
  data.frame(dtmnfr_2013 = pt_pad_code(x[[code_col]], "freguesia"),
             caop = x$freguesia, stringsAsFactors = FALSE)
}))
caop <- unique(caop)
if (anyDuplicated(caop$dtmnfr_2013)) {
  stop(sprintf("CAOP %d gives more than one name for some codes.", RELEASE))
}
message(sprintf("CAOP %d: %d freguesias.", RELEASE, nrow(caop)))

# --- 2. INE: the names of the 2013 map ---------------------------------------------

cli <- ineptr2::INEClient$new(lang = "PT", timeout = 300)

meta <- cli$get_dim_info(INDICATOR)
geo_label <- meta$abrv[meta$dim_num == GEO_DIM]
message(sprintf("Indicator %s, dimension %s: %s", INDICATOR, GEO_DIM, geo_label))
if (!grepl("Censos [2021]", geo_label, fixed = TRUE)) {
  stop("Dimension ", GEO_DIM, " is not the Censos 2021 geography: ", geo_label)
}

dims <- cli$get_dim_values(INDICATOR, dims = GEO_DIM)
freg <- dims[nchar(dims$categ_cod) == 6L, ]
ine <- unique(data.frame(
  dtmnfr_2013 = pt_pad_code(freg$categ_cod, "freguesia"),
  ine         = trimws(freg$categ_dsg),
  stringsAsFactors = FALSE
))
message(sprintf("INE: %d freguesias.", nrow(ine)))

# Both are authorities here, so check they arrived intact rather than trusting
# them -- a mojibaked response would otherwise go straight into the registry.
for (src in list(list("CAOP", caop$caop), list("INE", ine$ine))) {
  bad <- is.na(src[[2]]) | !nzchar(src[[2]]) | grepl("�", src[[2]], fixed = TRUE)
  if (any(bad)) {
    stop(sprintf("%s: %d empty or mis-encoded name(s), e.g. %s", src[[1]],
                 sum(bad), paste(utils::head(src[[2]][bad], 3), collapse = ", ")))
  }
}
if (anyDuplicated(ine$dtmnfr_2013)) stop("Duplicate codes in the INE response.")

# --- 3. Both must describe the registry's 2013 map, with the same names ----------

reg <- utils::read.csv(CSV, colClasses = "character", encoding = "UTF-8")
codes13 <- pt_pad_code(reg$dtmnfr_2013, "freguesia")

sets <- list(registry = unique(codes13), CAOP = caop$dtmnfr_2013,
             INE = ine$dtmnfr_2013)
for (nm in c("CAOP", "INE")) {
  missing <- setdiff(sets$registry, sets[[nm]])
  extra   <- setdiff(sets[[nm]], sets$registry)
  if (length(missing) || length(extra)) {
    stop(sprintf("%s's code set differs from the registry's 2013 codes: %d missing, %d extra.\n  %s",
                 nm, length(missing), length(extra),
                 paste(utils::head(c(missing, extra), 10), collapse = ", ")))
  }
}

cmp <- merge(caop, ine, by = "dtmnfr_2013")
differ <- cmp[cmp$caop != cmp$ine, ]
if (nrow(differ)) {
  print(differ, row.names = FALSE)
  stop(sprintf("CAOP %d and INE disagree on %d name(s). Decide which is right before writing.",
               RELEASE, nrow(differ)))
}
message(sprintf("CAOP %d and INE agree on all %d names.", RELEASE, nrow(cmp)))

# --- 4. Write back ----------------------------------------------------------------

new <- caop$caop[match(codes13, caop$dtmnfr_2013)]
changed <- which(reg$freguesia_2013 != new)
message(sprintf("%d row(s) change, covering %d 2013 freguesia(s):",
                length(changed), length(unique(codes13[changed]))))
if (length(changed)) {
  print(unique(data.frame(dtmnfr_2013 = codes13[changed],
                          was = reg$freguesia_2013[changed],
                          now = new[changed])), row.names = FALSE)
}

reg$freguesia_2013 <- new
stopifnot(!anyNA(reg$freguesia_2013), all(nzchar(reg$freguesia_2013)))

con <- file(CSV, open = "wb", encoding = "UTF-8")
utils::write.csv(reg, con, row.names = FALSE, quote = TRUE, fileEncoding = "UTF-8")
close(con)
message(sprintf("Wrote %s (%d rows).", CSV, nrow(reg)))
