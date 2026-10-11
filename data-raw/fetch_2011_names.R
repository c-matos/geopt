# data-raw/fetch_2011_names.R
#
# Fills the freguesia_2011 column of data-raw/freguesia_registry_2011.csv with
# the names those units actually carried before the 2013 reform. These are
# often not the current unit's name: a unit merged into a union, such as "Se"
# (Braga) or "Maximinos", is matched by its own name from this column.
#
# Source. INE indicator 0006393, whose geography dimension is
# "Local de residencia (Freguesia - a data dos Censos 2011)", version 02563.
# That dimension is the pre-2013 freguesia map itself: 4260 six-digit codes,
# exactly the registry's 4260, no extras and none missing.
#
# Not the 2001-vintage indicator 0000535 ("a data dos Censos 2001"): that is a
# different, earlier map of 4241 codes -- the "2001" vintage, built by
# fetch_2001_registry.R. Between the two censuses 22 freguesias were created and
# 3 dissolved (4241 - 3 + 22 = 4260), by laws of July 2001, July 2002 and August
# 2003; the last took effect on 2004-01-01. 13 of the 22 were carved out of a
# freguesia that kept its code, so a code shared by both maps does not always
# cover the same territory. The 25 changes, with their laws, are listed in
# data-raw/freguesia_changes_2001_2011.csv.
#
# Requires the ineptr2 package and network access.
#
# Usage:
#   source("data-raw/fetch_2011_names.R")
# then rebuild:
#   source("data-raw/derive_datasets.R")

stopifnot(requireNamespace("ineptr2", quietly = TRUE))
pkgload::load_all(".", quiet = TRUE)   # for pt_pad_code()

INDICATOR <- "0006393"
GEO_DIM   <- "2"
CSV       <- "data-raw/freguesia_registry_2011.csv"

# --- 1. Fetch the geography dimension -------------------------------------------

cli <- ineptr2::INEClient$new(lang = "PT", timeout = 300)

meta <- cli$get_dim_info(INDICATOR)
geo_label <- meta$abrv[meta$dim_num == GEO_DIM]
message(sprintf("Indicator %s, dimension %s: %s", INDICATOR, GEO_DIM, geo_label))
if (!grepl("Censos 2011", geo_label)) {
  stop("Dimension ", GEO_DIM, " is not the Censos 2011 geography: ", geo_label)
}

dims <- cli$get_dim_values(INDICATOR, dims = GEO_DIM)
freg <- dims[nchar(dims$categ_cod) == 6L, ]
api <- unique(data.frame(
  dtmnfr_2011 = pt_pad_code(freg$categ_cod, "freguesia"),
  name         = trimws(freg$categ_dsg),
  stringsAsFactors = FALSE
))
message(sprintf("Fetched %d freguesia names.", nrow(api)))

# The API is the authority here, so check it arrived intact rather than trusting
# it blindly -- a mojibaked or truncated response would otherwise be written
# straight into the source of truth.
if (anyDuplicated(api$dtmnfr_2011)) {
  stop("Duplicate codes in the API response.")
}
bad_enc <- grepl("�", api$name) | is.na(nchar(api$name))
if (any(bad_enc)) {
  stop(sprintf("%d name(s) came back with replacement characters -- encoding is broken: %s",
               sum(bad_enc), paste(utils::head(api$name[bad_enc], 3), collapse = ", ")))
}
if (any(!nzchar(api$name))) stop("Empty name(s) in the API response.")

# --- 2. Check it against the registry --------------------------------------------

reg <- utils::read.csv(CSV, colClasses = "character", encoding = "UTF-8")
reg$dtmnfr_2011 <- pt_pad_code(reg$dtmnfr_2011, "freguesia")

missing <- setdiff(reg$dtmnfr_2011, api$dtmnfr_2011)
extra   <- setdiff(api$dtmnfr_2011, reg$dtmnfr_2011)
if (length(missing) || length(extra)) {
  stop(sprintf("Code sets differ: %d registry code(s) absent from the API, %d extra.\n  %s",
               length(missing), length(extra),
               paste(utils::head(c(missing, extra), 10), collapse = ", ")))
}

# Report every name that differs from what the CSV holds, so a rerun shows
# exactly what it changes.
had <- !is.na(reg$freguesia_2011) & trimws(reg$freguesia_2011) != ""
cmp <- merge(reg[had, c("dtmnfr_2011", "freguesia_2011")], api, by = "dtmnfr_2011")
changed <- cmp[cmp$freguesia_2011 != cmp$name, ]
message(sprintf("Of %d rows that already had a name, %d disagree with the 2011 vintage.",
                nrow(cmp), nrow(changed)))
if (nrow(changed)) {
  print(utils::head(changed[order(changed$dtmnfr_2011), ], 40), row.names = FALSE)
}
message(sprintf("Filling %d previously blank name(s).", sum(!had)))

# --- 3. Write back ----------------------------------------------------------------

reg$freguesia_2011 <- api$name[match(reg$dtmnfr_2011, api$dtmnfr_2011)]
stopifnot(!anyNA(reg$freguesia_2011), all(nzchar(reg$freguesia_2011)))

reg <- reg[order(reg$dtmnfr_2011), c("dtmnfr_2011", "freguesia_2011",
                                      "dtmnfr", "relation")]
con <- file(CSV, open = "wb", encoding = "UTF-8")
utils::write.csv(reg, con, row.names = FALSE, quote = TRUE, fileEncoding = "UTF-8")
close(con)
message(sprintf("Wrote %s (%d rows).", CSV, nrow(reg)))
