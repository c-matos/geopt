# data-raw/fetch_2001_registry.R
#
# Writes data-raw/freguesia_registry_2001.csv: the freguesia map the 2001
# census used, as pairs of (2001 unit, 2011 unit) that share territory.
#
# Source. INE indicator 0000535, whose geography dimension is
# "Local de residencia (Freguesia - a data dos Censos 2001)": 4241 six-digit
# codes. Between that census and the 2011 one, 22 freguesias were created and 3
# dissolved (4241 - 3 + 22 = 4260). data-raw/freguesia_changes_2001_2011.csv
# lists the 25 changes with their laws and, for each created freguesia, the
# 2001 freguesia(s) its territory came from (`from_2001`). Every other code
# covers the same territory in both maps.
#
# Grain. One row per pair, not per 2001 unit: the 2011 map is finer everywhere
# except two freguesias that were carved out of TWO 2001 freguesias each --
# Boavista dos Pinheiros (Salvador and Santa Maria, Odemira; Lei 18-F/2001) and
# Santa Cruz/Trindade (Outeiro Seco and Santa Maria Maior, Chaves). Both were
# confirmed by overlaying the 2011 census areas on the 2001 ones and counting
# the 2001 residents in each part; the other `from_2001` values were checked the
# same way (column `from_2001_checked`).
#
# Names. INE's 2001 labels, with the region qualifier it appends to Azorean and
# Madeiran names ("Calheta (R.A.Acores)") removed. Some labels are abbreviated
# to fit INE's 40-character field ("Torres V (Sta Maria do Castelo S Miguel)");
# they are kept as published, since that is how 2001 data spells them, and the
# 2011 spelling still matches at the 2001 vintage through pt_match()'s
# historic names.
#
# Requires the ineptr2 package and network access.
#
# Usage:
#   source("data-raw/fetch_2001_registry.R")
# then rebuild:
#   source("data-raw/derive_datasets.R")

stopifnot(requireNamespace("ineptr2", quietly = TRUE))
pkgload::load_all(".", quiet = TRUE)   # for pt_pad_code()

INDICATOR <- "0000535"
GEO_DIM   <- "2"
OUT       <- "data-raw/freguesia_registry_2001.csv"
CHANGES   <- "data-raw/freguesia_changes_2001_2011.csv"
REG11     <- "data-raw/freguesia_registry_2011.csv"

# --- 1. Fetch the geography dimension -------------------------------------------

cli <- ineptr2::INEClient$new(lang = "PT", timeout = 300)

meta <- cli$get_dim_info(INDICATOR)
geo_label <- meta$abrv[meta$dim_num == GEO_DIM]
message(sprintf("Indicator %s, dimension %s: %s", INDICATOR, GEO_DIM, geo_label))
if (!grepl("Censos 2001", geo_label)) {
  stop("Dimension ", GEO_DIM, " is not the Censos 2001 geography: ", geo_label)
}

dims <- cli$get_dim_values(INDICATOR, dims = GEO_DIM)
freg <- dims[nchar(dims$categ_cod) == 6L, ]
api <- unique(data.frame(
  dtmnfr_2001 = pt_pad_code(freg$categ_cod, "freguesia"),
  name         = trimws(freg$categ_dsg),
  stringsAsFactors = FALSE
))
message(sprintf("Fetched %d freguesia names.", nrow(api)))

if (anyDuplicated(api$dtmnfr_2001)) stop("Duplicate codes in the API response.")
bad_enc <- grepl("�", api$name) | is.na(nchar(api$name))
if (any(bad_enc)) {
  stop(sprintf("%d name(s) came back with replacement characters -- encoding is broken: %s",
               sum(bad_enc), paste(utils::head(api$name[bad_enc], 3), collapse = ", ")))
}
if (any(!nzchar(api$name))) stop("Empty name(s) in the API response.")

# INE's region qualifier: "(R.A.Acores)", "(R.A.Madeira)", and one truncated
# "(R.A.Acor)" where the label hit the field limit.
api$name <- trimws(sub("[(]R[.]A[.][^)]*[)]?$", "", api$name))

# --- 2. Check the two maps differ by exactly the listed changes -----------------

reg11 <- utils::read.csv(REG11, colClasses = "character", encoding = "UTF-8")
c11 <- pt_pad_code(reg11$dtmnfr_2011, "freguesia")
ch <- utils::read.csv(CHANGES, colClasses = "character", encoding = "UTF-8")
ch$dtmnfr_2011 <- pt_pad_code(ch$dtmnfr_2011, "freguesia")
created   <- ch[ch$change == "created", ]
dissolved <- ch[ch$change == "dissolved", ]

only11 <- setdiff(c11, api$dtmnfr_2001)
only01 <- setdiff(api$dtmnfr_2001, c11)
if (!setequal(only11, created$dtmnfr_2011) || !setequal(only01, dissolved$dtmnfr_2011)) {
  stop(sprintf(paste0(
    "The 2001 and 2011 code lists differ by something other than the listed changes.\n",
    "  only in 2011, not listed as created: %s\n  listed as created, not only in 2011: %s\n",
    "  only in 2001, not listed as dissolved: %s\n  listed as dissolved, not only in 2001: %s"),
    paste(setdiff(only11, created$dtmnfr_2011), collapse = ", "),
    paste(setdiff(created$dtmnfr_2011, only11), collapse = ", "),
    paste(setdiff(only01, dissolved$dtmnfr_2011), collapse = ", "),
    paste(setdiff(dissolved$dtmnfr_2011, only01), collapse = ", ")))
}

# --- 3. Pairs ----------------------------------------------------------------------

parents <- strsplit(created$from_2001, ";", fixed = TRUE)
pairs <- rbind(
  data.frame(dtmnfr_2011 = setdiff(c11, created$dtmnfr_2011),
             dtmnfr_2001 = setdiff(c11, created$dtmnfr_2011),
             stringsAsFactors = FALSE),
  data.frame(dtmnfr_2011 = rep(created$dtmnfr_2011, lengths(parents)),
             dtmnfr_2001 = pt_pad_code(unlist(parents), "freguesia"),
             stringsAsFactors = FALSE)
)

unknown <- setdiff(pairs$dtmnfr_2001, api$dtmnfr_2001)
if (length(unknown)) stop("Parent code(s) not in the 2001 map: ", paste(unknown, collapse = ", "))
uncovered <- setdiff(api$dtmnfr_2001, pairs$dtmnfr_2001)
if (length(uncovered)) {
  stop("2001 freguesia(s) with no 2011 successor: ", paste(uncovered, collapse = ", "))
}
if (anyDuplicated(pairs)) stop("Duplicate (2001, 2011) pairs.")

pairs$freguesia_2001 <- api$name[match(pairs$dtmnfr_2001, api$dtmnfr_2001)]
pairs <- pairs[order(pairs$dtmnfr_2001, pairs$dtmnfr_2011),
               c("dtmnfr_2001", "freguesia_2001", "dtmnfr_2011")]

message(sprintf("%d pairs: %d 2001 freguesias, %d 2011 freguesias; %d 2011 freguesia(s) with two 2001 parents.",
                nrow(pairs), length(unique(pairs$dtmnfr_2001)),
                length(unique(pairs$dtmnfr_2011)),
                sum(table(pairs$dtmnfr_2011) > 1L)))

# --- 4. Write --------------------------------------------------------------------------

con <- file(OUT, open = "wb", encoding = "UTF-8")
utils::write.csv(pairs, con, row.names = FALSE, quote = TRUE, fileEncoding = "UTF-8")
close(con)
message(sprintf("Wrote %s (%d rows).", OUT, nrow(pairs)))
