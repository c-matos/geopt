# Converting data between freguesia vintages.
#
# The pairing is DERIVED from the atom model (R/atoms.R): two units correspond
# when they share territory, so atom_link() answers for any pair of vintages
# that exist, and a new vintage needs no table of its own.

# Freguesia code vintages, by number of freguesias:
#   "2011" (4260) > "2001" (4241) > "2025" (3259) > "2013" (3092).
# The two pre-2013 maps are named after the census that recorded them, because
# neither was made by a single law; the later ones after their reform.
# Vintages are only ever named by their year (see check_vintage()): there is no
# alias for "the newest", which would silently change meaning after a reform.

# Codes that other sources use for a unit of a vintage. INE's code list for the
# 2001 census, which the "2001" vintage is built from, files Vale de Amoreira
# under Manteigas and Moita under Marinha Grande; the 2001 census areas (BGRI,
# see get_censos()) still carry the codes they had under Guarda and Alcobaca.
# Both are accepted wherever a 2001 code is read.
FREGUESIA_CODE_ALIASES <- data.frame(
  vintage = c("2001", "2001"),
  alias   = c("090756", "100117"),
  code    = c("090804", "101003"),
  stringsAsFactors = FALSE
)

#' Replace alias codes by the vintage's own code
#' @noRd
resolve_code_aliases <- function(codes, vintage) {
  a <- FREGUESIA_CODE_ALIASES[FREGUESIA_CODE_ALIASES$vintage %in% vintage, ,
                              drop = FALSE]
  hit <- match(codes, a$alias)
  ifelse(is.na(hit), codes, a$code[hit])
}

#' The correspondence between two vintages, with the target units' names
#'
#' Built from shared atoms rather than read off a stored table. Columns `from`,
#' `to` and `name` (the target unit's name).
#' @noRd
recode_link <- function(from, to) {
  link <- atom_link(from, to, "freguesia")
  data.frame(from = link$from, to = link$to,
             name = atom_unit_name("freguesia", to, link$to),
             stringsAsFactors = FALSE)
}

#' Convert freguesia-level data between code vintages
#'
#' Portugal's freguesias were aggregated into "uniões de freguesias" in 2013
#' and partially de-aggregated in 2025; the maps before 2013 are finer still.
#' This function converts freguesia-level data between four vintages: `"2001"`
#' (the map the 2001 census used, 4241 freguesias), `"2011"` (the map the 2011
#' census used, 4260), `"2013"` (the uniões, 3092) and `"2025"` (the current
#' map, 3259). The correspondence is derived from shared territory rather than
#' stored, so any pair of vintages works; it handles the value semantics
#' explicitly:
#'
#' * **finer → coarser (merges),** e.g. `2025` → `2013`, `2011` → `2025`:
#'   freguesias collapse into a shared unit. Value columns must be aggregated,
#'   and only values for which aggregation is meaningful may be converted (raw
#'   counts can be summed; rates and medians cannot) — so `aggregate` is
#'   required whenever a merge occurs. If only some constituents of a target
#'   are present in `data`, the aggregate covers the present ones and a warning
#'   reports the partial groups.
#' * **coarser → finer (splits),** e.g. `2013` → `2025`, `2025` → `2011`,
#'   `2001` → `2011` (22 freguesias created between the two censuses):
#'   a unit's value cannot be exactly disaggregated. You must opt in to a
#'   strategy: `split = "replicate"` copies the value to every constituent;
#'   `split = "weight"` distributes it proportionally to `weights` (`"area"`,
#'   only when splitting towards the newest vintage, or a named vector keyed by
#'   the target `dtmnfr`, e.g. population). The default (`"error"`) refuses.
#'
#' Codes not present in the relevant crosswalk (including current freguesias
#' created after 2011, which have no pre-2013 predecessor) convert to `NA`
#' with a warning. For `"2001"`, the codes the 2001 census areas use for Vale
#' de Amoreira (`090756`) and Moita (`100117`) are accepted alongside INE's
#' (`090804`, `101003`).
#'
#' @param data A data.frame with freguesia-level rows.
#' @param by Name of the column in `data` holding the freguesia codes
#'   (DTMNFR, zero-padding is repaired). Default `"dtmnfr"`.
#' @param from Which vintage the codes in `data` belong to (required):
#'   `"2025"` (the current map), `"2013"` (the uniões, in force 2013–2025),
#'   `"2011"` (the map the 2011 census used, in force 2004–2013) or `"2001"`
#'   (the map the 2001 census used). The 1991 census used an earlier map again,
#'   which geopt does not have.
#' @param to Target vintage, one of the same four. Leave it out for the newest
#'   (`"2025"`); when `from` is already the newest, `to` must be given.
#' @param values Character vector naming the numeric value columns to
#'   convert. Other columns are carried along: replicated on splits, kept on
#'   merges when constant within the group (otherwise set to `NA`). Columns
#'   called `dtmnfr` or `freguesia` are not carried: the result's own are the
#'   target vintage's.
#' @param aggregate Function (or named list of functions, one per value
#'   column) used to combine values on merges, e.g. `sum`. Required when any
#'   merge occurs and `values` is non-empty.
#' @param split How to distribute values on splits: `"error"` (default),
#'   `"replicate"`, or `"weight"`.
#' @param weights For `split = "weight"`: `"area"` (proportional to the area of
#'   the newest vintage's freguesias) or a named numeric vector keyed by the
#'   target `dtmnfr` (e.g. population).
#' @param quiet Logical. Suppress informational warnings? Default `FALSE`.
#'
#' @return A data.frame with the target vintage's freguesia code (`dtmnfr`)
#'   and name (`freguesia`), followed by the carried and converted columns. The
#'   column names are the same whichever vintage you convert to, as in
#'   [pt_lookup()].
#'
#' @examplesIf identical(Sys.getenv("NOT_CRAN"), "true")
#' # 2013-era data onto the current map: sum-able counts, split by area
#' old <- data.frame(dtmnfr = c("010121", "010109"), cases = c(30, 10))
#' new <- pt_recode(old, from = "2013", values = "cases",
#'                  split = "weight", weights = "area")
#' get_map("freguesia", data = new, by = "dtmnfr")
#'
#' # Current data backwards to 2013 units (counts: aggregate = sum). Conde and
#' # Gandarela (Guimarães) were one união from 2013 until 2025.
#' now <- data.frame(dtmnfr = c("030895", "030897"), n = c(12, 7))
#' pt_recode(now, from = "2025", to = "2013", values = "n", aggregate = sum)
#'
#' # 2011-census freguesia counts onto the current map: many old freguesias
#' # merged into today's uniões, so aggregate = sum
#' old <- data.frame(dtmnfr = c("010101", "010102"), pop = c(500, 800))
#' pt_recode(old, from = "2011", to = "2025", values = "pop",
#'           aggregate = sum)
#'
#' # a 2001-census rate onto the 2011 map: Agualva-Cacém became four
#' # freguesias, and a rate is copied to each
#' pt_recode(data.frame(dtmnfr = "111101", rate = 12.5), from = "2001",
#'           to = "2011", values = "rate", split = "replicate")
#'
#' @seealso [pt_crosswalk()], [pt_registry], [pt_join()]
#'
#' @export
pt_recode <- function(data,
                      by = "dtmnfr",
                      from,
                      to = NULL,
                      values = NULL,
                      aggregate = NULL,
                      split = c("error", "replicate", "weight"),
                      weights = NULL,
                      quiet = FALSE) {
  if (!is.data.frame(data)) stop("`data` must be a data.frame.", call. = FALSE)
  if (missing(from) || is.null(from)) {
    stop(sprintf("`from` is required: the vintage of the codes in `data` (%s).",
                 paste(shQuote(axis_vintages("admin")), collapse = ", ")),
         call. = FALSE)
  }
  from <- check_vintage(from, "admin", "from")
  newest <- current_admin_vintage()
  if (is.null(to) && identical(from, newest)) {
    stop(sprintf("`from` is already the newest vintage (\"%s\"): say which vintage to convert to with `to`.",
                 newest), call. = FALSE)
  }
  to <- check_vintage(to, "admin", "to") %||% newest
  if (identical(from, to)) {
    stop("`from` and `to` are the same vintage; nothing to convert.", call. = FALSE)
  }
  split <- match.arg(split)
  if (!by %in% names(data)) {
    stop(sprintf("Column '%s' not found in data.", by), call. = FALSE)
  }
  values <- values %||% character(0)
  missing_vals <- setdiff(values, names(data))
  if (length(missing_vals) > 0L) {
    stop(sprintf("`values` column(s) not in data: %s",
                 paste(missing_vals, collapse = ", ")), call. = FALSE)
  }

  usable <- recode_link(from, to)

  codes_in <- resolve_code_aliases(pt_pad_code(data[[by]], "freguesia"), from)
  known <- codes_in %in% usable$from
  if (any(!known) && !quiet) {
    bad <- unique(codes_in[!known])
    warning(sprintf(
      "pt_recode: %d code(s) not in the crosswalk convert to NA: %s%s",
      length(bad), paste(utils::head(bad, 5L), collapse = ", "),
      if (length(bad) > 5L) ", ..." else ""
    ), call. = FALSE)
  }

  # Expand each input row to its target rows
  map_rows <- lapply(seq_len(nrow(data)), function(i) {
    if (!known[i]) {
      return(data.frame(row = i, dst = NA_character_, name = NA_character_,
                        stringsAsFactors = FALSE))
    }
    hit <- usable[usable$from == codes_in[i], , drop = FALSE]
    data.frame(row = i, dst = hit$to, name = hit$name,
               stringsAsFactors = FALSE)
  })
  map <- do.call(rbind, map_rows)

  # --- Splits (one source row -> several target rows) -----------------------------
  n_per_row <- table(map$row)
  split_rows <- as.integer(names(n_per_row)[n_per_row > 1L])
  if (length(split_rows) > 0L && length(values) > 0L) {
    if (split == "error") {
      stop(sprintf(
        "%d row(s) split into multiple %s freguesias. Values cannot be exactly disaggregated; opt in with split = \"replicate\" or split = \"weight\" (see ?pt_recode).",
        length(split_rows), to
      ), call. = FALSE)
    }
    if (split == "weight" && is.null(weights)) {
      stop("split = \"weight\" requires `weights` (\"area\" or a named numeric vector).",
           call. = FALSE)
    }
  }

  w_lookup <- NULL
  if (split == "weight" && length(split_rows) > 0L) {
    if (identical(weights, "area")) {
      if (!identical(to, newest)) {
        stop(sprintf("weights = \"area\" is only available when splitting towards the newest vintage (\"%s\").",
                     newest), call. = FALSE)
      }
      freg <- get_dataset("pt_freguesias")
      w_lookup <- stats::setNames(freg$area_ha, freg$dtmnfr)
    } else if (is.numeric(weights) && !is.null(names(weights))) {
      w_lookup <- weights
    } else {
      stop("`weights` must be \"area\" or a named numeric vector keyed by target codes.",
           call. = FALSE)
    }
  }

  # Assemble the expanded frame. The code and name columns are named the same
  # whatever the target vintage, as in pt_lookup(), so the result keeps working
  # with `by = "dtmnfr"` downstream. An input column of either name describes
  # the SOURCE units, which the result no longer has, so it is not carried.
  out <- data.frame(dtmnfr = map$dst, freguesia = map$name,
                    stringsAsFactors = FALSE)
  carry_cols <- setdiff(names(data), c(by, values, names(out)))
  for (col in carry_cols) out[[col]] <- data[[col]][map$row]

  for (col in values) {
    v <- data[[col]][map$row]
    if (length(split_rows) > 0L && split == "weight") {
      for (r in split_rows) {
        sel <- which(map$row == r)
        w <- w_lookup[map$dst[sel]]
        if (anyNA(w) || sum(w) == 0) {
          stop(sprintf(
            "Missing or zero weights for target code(s): %s",
            paste(map$dst[sel][is.na(w) | w == 0], collapse = ", ")
          ), call. = FALSE)
        }
        v[sel] <- v[sel] * w / sum(w)
      }
    }
    out[[col]] <- v
  }

  # Warn when a coarser target unit sees only part of its constituent
  # freguesias (a single member converting alone silently under-represents the
  # merged unit). A no-op for splits, where each target has one source.
  if (!quiet) {
    targets <- out$dtmnfr[!is.na(out$dtmnfr)]
    expected <- table(usable$to)
    got <- table(targets)
    partial <- names(got)[got < expected[names(got)]]
    if (length(partial) > 0L) {
      warning(sprintf(
        "pt_recode: %d target unit(s) are missing some constituent freguesias in `data`; aggregates cover the present ones only: %s%s",
        length(partial), paste(utils::head(partial, 5L), collapse = ", "),
        if (length(partial) > 5L) ", ..." else ""
      ), call. = FALSE)
    }
  }

  # --- Merges (several rows -> the same target code) --------------------------------
  dup_targets <- unique(out$dtmnfr[duplicated(out$dtmnfr) & !is.na(out$dtmnfr)])
  if (length(dup_targets) > 0L) {
    if (length(values) > 0L && is.null(aggregate)) {
      stop(sprintf(
        "%d target unit(s) receive multiple rows (merge). Pass `aggregate` (e.g. sum) \u2014 and only convert values for which aggregation is meaningful (counts yes, rates no).",
        length(dup_targets)
      ), call. = FALSE)
    }

    agg_fun <- function(col) {
      if (is.function(aggregate)) return(aggregate)
      if (is.list(aggregate) && !is.null(aggregate[[col]])) return(aggregate[[col]])
      stop(sprintf("No aggregate function given for value column '%s'.", col),
           call. = FALSE)
    }

    grp <- out$dtmnfr
    keep_first <- !duplicated(grp) | is.na(grp)
    merged <- out[keep_first, , drop = FALSE]

    for (col in values) {
      f <- agg_fun(col)
      agg <- tapply(out[[col]], grp, f)
      idx <- !is.na(merged$dtmnfr)
      merged[[col]][idx] <- as.numeric(agg[merged$dtmnfr[idx]])
    }
    for (col in carry_cols) {
      n_distinct <- tapply(out[[col]], grp, function(v) length(unique(v)))
      varying <- names(n_distinct)[n_distinct > 1L]
      if (length(varying) > 0L) {
        sel <- merged$dtmnfr %in% varying
        merged[[col]][sel] <- NA
        if (!quiet) {
          message(sprintf(
            "pt_recode: column '%s' is not constant within merged unit(s); set to NA there.",
            col
          ))
        }
      }
    }
    out <- merged
  }

  rownames(out) <- NULL
  out
}
