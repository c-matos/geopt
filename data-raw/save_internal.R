# data-raw/save_internal.R
#
# R/sysdata.rda is written by more than one data-raw script, and
# usethis::use_data(internal = TRUE) REPLACES the whole file with whatever
# objects it was handed. Re-running censos_manifest.R would therefore drop the
# atom model, and re-running derive_datasets.R would drop censos_manifest.
#
# save_internal() merges instead: it reads what is already there, overwrites
# only the named objects, and writes everything back. Both scripts use it, so
# either can be run alone.

save_internal <- function(..., path = "R/sysdata.rda") {
  new <- list(...)
  if (is.null(names(new)) || any(names(new) == "")) {
    stop("save_internal() takes named arguments only.", call. = FALSE)
  }

  env <- new.env(parent = emptyenv())
  if (file.exists(path)) load(path, envir = env)
  kept <- setdiff(ls(env, all.names = TRUE), names(new))
  for (nm in names(new)) assign(nm, new[[nm]], envir = env)

  # version = 3 + compress = "xz" matches what usethis::use_data() produces
  # (DESCRIPTION already requires R >= 4.1).
  save(list = ls(env, all.names = TRUE), envir = env, file = path,
       compress = "xz", version = 3)

  message(sprintf("  %s: %s%s", path,
                  paste(sort(names(new)), collapse = ", "),
                  if (length(kept)) sprintf(" (kept %s)",
                                            paste(sort(kept), collapse = ", ")) else ""))
  invisible(path)
}
