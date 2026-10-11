# Internal accessors over the atom model in R/sysdata.rda.
#
# `atoms` / `units` / `unit_names` / `membership` are the normalized source of
# truth built by data-raw/build_atoms.R:
#
#   atoms       one row per invariant territory unit: the 2011 freguesia
#               partition, with a 2011 unit carved out of two 2001 freguesias
#               split into its two parts (Boavista dos Pinheiros, Santa
#               Cruz/Trindade), plus an atom for any later unit created by
#               subdividing one (Parque das Nacoes is the only such case)
#   units       (scheme, vintage, code) -> official name
#   unit_names  the matching pool: official + simplified spellings, and the
#               earlier names of the 2013 map's freguesias (kind "former")
#   membership  atom -> unit per (scheme, vintage), with `share`
#
# Everything vintage-related composes through atoms: a crosswalk between two
# vintages is the set of unit pairs that share an atom, which is why crosswalks
# are derived here rather than stored. Derived, they cover any pair of
# vintages, and they tell a unit whose territory changed from one that was
# merely renumbered.

#' Membership rows for one scheme and vintage
#' @noRd
atom_membership <- function(scheme, vintage) {
  m <- membership
  m[m$scheme == scheme & m$vintage == vintage, , drop = FALSE]
}

#' Official name for units of a scheme/vintage, indexed by code
#' @noRd
atom_unit_name <- function(scheme, vintage, code) {
  u <- units
  u$name[match(paste(scheme, vintage, code),
               paste(u$scheme, u$vintage, u$code))]
}

#' Unit code pairs that share an atom, between two vintages of a scheme
#'
#' The primitive every vintage conversion is built on. Returns one row per
#' (from, to) pair; a merge yields several `from` for one `to`, a split several
#' `to` for one `from`.
#' @noRd
atom_link <- function(from, to, scheme = "freguesia") {
  a <- atom_membership(scheme, from)
  b <- atom_membership(scheme, to)
  j <- merge(a[, c("atom_id", "unit_code")], b[, c("atom_id", "unit_code")],
             by = "atom_id", suffixes = c("_from", "_to"))
  out <- unique(data.frame(from = j$unit_code_from, to = j$unit_code_to,
                           stringsAsFactors = FALSE))
  out[order(out$to, out$from), ]
}

#' Vintages available for a scheme
#' @noRd
atom_vintages <- function(scheme) {
  sort(unique(membership$vintage[membership$scheme == scheme]))
}

#' The NUTS I region(s) a unit lies in, normalized
#'
#' Used to check a context's trailing qualifier against the unit a curated
#' spelling names: `"Calheta (Madeira)"` must not reach the Azorean Calheta just
#' because NAME_VARIANTS gives it the bare spelling. NUTS I names are stable
#' across revisions, so the newest is as good as any.
#' @noRd
unit_region <- function(scheme, code) {
  m <- membership
  ats <- m$atom_id[m$scheme == scheme & m$unit_code %in% code]
  if (length(ats) == 0L) return(character(0))
  v <- max(atom_vintages("nuts1"))
  r <- m[m$scheme == "nuts1" & m$vintage == v & m$atom_id %in% ats, ]
  pt_normalize(unique(atom_unit_name("nuts1", v, r$unit_code)))
}

#' Correspondence between two administrative vintages
#'
#' Which units of one vintage correspond to which of another, and how each
#' changed. Derived from shared territory rather than stored, so any pair of
#' vintages works and nothing goes stale when a new one is added.
#'
#' @section Codes are vintage-local:
#' A DTMNFR identifies a unit *within its own vintage only*. None of the 302
#' freguesias restored in 2025 reused its pre-2013 code, so this table — not
#' string comparison — is the only safe way to relate codes across vintages.
#'
#' @section Relations:
#' `relation` is computed from the correspondence itself:
#' \describe{
#'   \item{`unchanged`}{same territory, same code, same name.}
#'   \item{`renamed`}{same territory and code, different name.}
#'   \item{`renumbered`}{same territory, different code. Colos kept its territory
#'     across the 2025 reform and changed only its code (`021118` → `021124`).}
#'   \item{`merged`}{several `from` units became one — the 2013 uniões.}
#'   \item{`split`}{one `from` unit became several — the 2025 reposição.}
#' }
#'
#' @param from,to Administrative vintages: `"2001"`, `"2011"`, `"2013"` or
#'   `"2025"`. `from` defaults to `"2013"`; leave `to` out for the newest
#'   (`"2025"`).
#' @param level Which units to relate. Only `"freguesia"` changes across these
#'   vintages; `"municipio"` and `"distrito"` are included for completeness.
#'
#' @return A data.frame with one row per corresponding pair: `from`, `to`,
#'   `name_from`, `name_to`, `relation`.
#'
#' @examples
#' x <- pt_crosswalk("2013", "2025")
#' table(x$relation)
#'
#' # what became of the 2013 "030882" code
#' x[x$from == "030882", ]
#'
#' @seealso [pt_recode()] to carry values across vintages, [pt_registry] for the
#'   units themselves.
#'
#' @export
pt_crosswalk <- function(from = "2013", to = NULL,
                         level = c("freguesia", "municipio", "distrito")) {
  level <- match.arg(level)
  scheme <- MATCH_LEVELS[[level]]$scheme
  if (is.null(from)) stop("`from` is required.", call. = FALSE)
  fv <- check_vintage(from, "admin", "from")
  tv <- check_vintage(to, "admin", "to") %||% current_admin_vintage()

  available <- atom_vintages(scheme)
  for (v in c(fv, tv)) {
    if (!v %in% available) {
      stop(sprintf("No %s data for vintage '%s'. Available: %s.",
                   level, v, paste(shQuote(available), collapse = ", ")),
           call. = FALSE)
    }
  }
  if (identical(fv, tv)) {
    stop("`from` and `to` are the same vintage; nothing to relate.", call. = FALSE)
  }
  out <- atom_relations(fv, tv, scheme)
  rownames(out) <- NULL
  out
}

#' How a unit changed between two vintages
#'
#' Derived, never stored. Cardinality separates `merged` and `split`; comparing
#' code and name separates the 1:1 cases, `renumbered` among them: Colos kept
#' its territory across the 2025 reform and changed only its code
#' (021118 -> 021124).
#'
#' "restored" is deliberately absent: it is a *reason* (Lei 25-A/2025 reposicao),
#' not a structure, and it is exactly the 2013 -> 2025 `split` set.
#' @noRd
atom_relations <- function(from, to, scheme = "freguesia") {
  p <- atom_link(from, to, scheme)
  p$name_from <- atom_unit_name(scheme, from, p$from)
  p$name_to   <- atom_unit_name(scheme, to,   p$to)

  n_to   <- table(p$from)
  n_from <- table(p$to)
  p$relation <- ifelse(
    n_to[p$from] > 1L, "split",
    ifelse(n_from[p$to] > 1L, "merged",
           ifelse(p$from != p$to, "renumbered",
                  ifelse(!is.na(p$name_from) & !is.na(p$name_to) &
                           p$name_from != p$name_to, "renamed", "unchanged"))))
  p
}
