# data-raw/prepare_boundaries.R
#
# Generates simplified, topologically consistent boundaries for all
# administrative levels. Simplification happens once at the freguesia level;
# higher levels are derived by dissolving, so edges are guaranteed to align.
#
# Prerequisites:
#   - geopt must be loadable (devtools::load_all())
#   - rmapshaper must be installed
#   - usethis must be installed (for use_data)
#
# Usage:
#   source("data-raw/prepare_boundaries.R")

library(sf)
library(rmapshaper)
devtools::load_all()

# --- Configuration -----------------------------------------------------------

KEEP    <- 0.01   # "low" simplification preset
OUT_CRS <- 4326L  # WGS84 for portability
REGIONS <- c("continente", "raa", "ram")

# --- Download full-resolution freguesias -------------------------------------

message("=== Downloading full-resolution freguesias ===")
client <- GeoClient$new()

freg_list <- lapply(REGIONS, function(r) {
  message(sprintf("  %s...", r))
  sf_obj <- client$get_caop(r, "freguesia", detail = "full")
  st_transform(sf_obj, OUT_CRS)
})

common_cols <- Reduce(intersect, lapply(freg_list, names))
freg_all <- do.call(rbind, lapply(freg_list, function(x) x[, common_cols]))

message(sprintf(
  "Combined: %d freguesias, %d columns",
  nrow(freg_all), length(common_cols)
))
message(
  "Columns: ",
  paste(setdiff(common_cols, attr(freg_all, "sf_column")), collapse = ", ")
)

# --- Simplify at freguesia level ---------------------------------------------

message(sprintf("\n=== Simplifying freguesias (keep = %s) ===", KEEP))
pt_freguesias <- ms_simplify(freg_all, keep = KEEP, keep_shapes = TRUE)

# --- Hand off to derivation ----------------------------------------------------
# Dissolving, attribute enrichment, pt_codes, and saving live in
# derive_datasets.R so they can be re-run without re-downloading.

saveRDS(pt_freguesias, "data-raw/freg_simplified.rds")
message("Saved data-raw/freg_simplified.rds")

source("data-raw/derive_datasets.R")
