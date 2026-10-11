# Assembling a flat view across the three vintage axes.
#
# The axes are independent and change on different schedules: which
# administrative units exist (Portuguese law), how municipios group into NUTS
# (EU regulation), and the health geography (Portuguese law). Nothing about one
# implies anything about another -- INE publishes the 2013 freguesia set under
# both the 2013 and the 2024 NUTS revision -- so each is a separate argument and
# the chosen combination is visible at the call site.
#
# The shipped tables (pt_registry, pt_nuts_codes, pt_health_codes) are each long
# on their own axis. This assembles them.

# Levels pt_lookup() can aggregate to: the column identifying a unit, and the
# column naming it. Both are hoisted to the front of the result.
LOOKUP_LEVELS <- list(
  freguesia = c("dtmnfr", "freguesia"),
  municipio = c("dtmn", "municipio"),
  distrito  = c("dt", "distrito_ilha"),
  nuts1     = c("nuts1_cod", "nuts1"),
  nuts2     = c("nuts2_cod", "nuts2"),
  nuts3     = c("nuts3_cod", "nuts3"),
  reg_saude = c("reg_saude"),
  uls       = c("unit"),
  aces      = c("unit"),
  uls_municipio  = c("unit_municipio"),
  aces_municipio = c("unit_municipio")
)

#' Administrative, NUTS and health codes for one choice of each vintage
#'
#' Assembles a wide lookup table from [pt_registry], [pt_nuts_codes] and
#' [pt_health_codes]. Each axis is chosen independently, because they are
#' independent: the same freguesia set is published by INE under more than one
#' NUTS revision, and a NUTS revision says nothing about which freguesias exist.
#'
#' @section Vintages:
#' `admin_vintage` selects which administrative units exist:
#'
#' * `"2025"` — 3259 freguesias, the current set (Lei 25-A/2025, in force from
#'   the 2025 autárquicas, which restored units aggregated in 2013).
#' * `"2013"` — 3092 freguesias (Lei 11-A/2013). **This is what INE still
#'   publishes**, including on indicators labelled "NUTS - 2024".
#' * `"2011"` — 4260 freguesias, the map the 2011 census used, in force from
#'   2004 until the 2013 reform.
#' * `"2001"` — 4241 freguesias, the map the 2001 census used. 22 freguesias
#'   were created and 3 dissolved between the two censuses.
#'
#' The pre-2013 maps are named after the census that recorded them, because
#' neither was made by a single law. The 1991 census used an earlier map again
#' (4208 freguesias in 305 municípios, before Odivelas, Trofa and Vizela were
#' created in 1998), which geopt does not have.
#'
#' `nuts_vintage` selects the NUTS revision: `"2024"` (9 NUTS II, 26 NUTS III),
#' `"2013"` (7 / 25) or `"2002"` (7 / 30).
#'
#' `health_vintage` selects the health geography: `"2024"` (regiões de saúde +
#' ULS) or `"2022"` (the former ARS + ACES). Health columns are omitted unless
#' asked for, or unless `level` is a health level: those read the geography
#' their units belong to, `"2024"` for `"reg_saude"`, `"uls"` and
#' `"uls_municipio"`, and `"2022"` for `"aces"` and `"aces_municipio"`.
#'
#' @section Codes are vintage-local:
#' A DTMNFR identifies a unit *within its own vintage only*. None of the 302
#' freguesias restored in 2025 reused its pre-2013 code, so comparing a code
#' across vintages — or joining data of one vintage onto codes of another —
#' silently mismatches. Use [pt_crosswalk()] to convert, and [pt_recode()] to
#' carry values across.
#'
#' @param level Grain of the result: `"freguesia"` (default), `"municipio"`,
#'   `"distrito"`, `"nuts1"`, `"nuts2"`, `"nuts3"`, or the health levels
#'   `"reg_saude"`, `"uls"`, `"aces"`, `"uls_municipio"`, `"aces_municipio"`.
#'   Coarser levels return one row per unit with only the columns that are
#'   constant within it. A health level reads its own health geography
#'   unless `health_vintage` says otherwise (see *Vintages*).
#' @param admin_vintage Which administrative unit set: `"2025"`, `"2013"`,
#'   `"2011"` or `"2001"`. Leave it out for the newest (`"2025"`).
#' @param nuts_vintage Which NUTS revision: `"2024"`, `"2013"` or `"2002"`.
#'   Leave it out for the newest (`"2024"`); `NA` drops the NUTS columns.
#' @param health_vintage Which health geography: `"2024"` or `"2022"`. Unlike
#'   the other two, leaving it out omits the health columns, except at a health
#'   `level`. ULS exist only in `"2024"` and ACES only in `"2022"`, so
#'   `level = "uls"` with `"2022"` returns that geography's ACES, and
#'   `level = "aces"` with `"2024"` its ULS (likewise for the `*_municipio`
#'   levels), with a warning.
#'
#' @return A data.frame, one row per unit of `level`.
#'
#' @examples
#' head(pt_lookup())
#'
#' # the combination INE actually publishes: 2013 freguesias, 2024 NUTS
#' head(pt_lookup(admin_vintage = "2013", nuts_vintage = "2024"))
#'
#' # one row per municipio, with its 2002 NUTS grouping
#' head(pt_lookup("municipio", nuts_vintage = "2002"))
#'
#' # one row per ULS (the 2024 health geography, without asking)
#' head(pt_lookup("uls"))
#'
#' @seealso [pt_registry], [pt_nuts_codes], [pt_health_codes],
#'   [pt_crosswalk()], [pt_match()]
#'
#' @export
pt_lookup <- function(level = "freguesia",
                      admin_vintage = NULL,
                      nuts_vintage = NULL,
                      health_vintage = NULL) {
  level <- match.arg(level, names(LOOKUP_LEVELS))

  reg <- as.data.frame(get_dataset("pt_registry"))
  admin_vintage <- check_vintage(admin_vintage, "admin") %||% current_admin_vintage()
  out <- reg[reg$admin_vintage == admin_vintage, setdiff(names(reg), "admin_vintage"),
             drop = FALSE]

  # Joined by match() rather than merge(), which would hoist the `by` column and
  # scramble the registry's column order.
  drop_nuts <- length(nuts_vintage) == 1L && is.na(nuts_vintage)
  if (!drop_nuts) {
    nuts <- as.data.frame(get_dataset("pt_nuts_codes"))
    nuts_vintage <- check_vintage(nuts_vintage, "nuts") %||% max(axis_vintages("nuts"))
    nuts <- nuts[nuts$nuts_vintage == nuts_vintage, , drop = FALSE]
    add <- setdiff(names(nuts), c("nuts_vintage", "dtmn"))
    out[add] <- nuts[match(out$dtmn, nuts$dtmn), add, drop = FALSE]
  }

  # A health level can't do without health columns, so it defaults to the
  # geography its units belong to, as get_map() and pt_match() do.
  health_vintage <- check_vintage(health_vintage, "health")
  if (level %in% HEALTH_LEVELS) {
    health_vintage <- health_vintage %||% level_health_vintage(level)
    warn_health_level_vintage(level, health_vintage)
  }

  if (!is.null(health_vintage)) {
    health <- as.data.frame(get_dataset("pt_health_codes"))
    health <- health[health$health_vintage == health_vintage, , drop = FALSE]
    add <- setdiff(names(health), c("health_vintage", "scheme", "dtmnfr"))
    # Health mappings are recorded against the CURRENT freguesia, so an earlier
    # admin vintage reaches them through its atoms. A 2011 unit falls inside one
    # current freguesia, but a 2001 unit that later lost territory to a new
    # freguesia reaches several: its value is the one they share, and NA if
    # they differ.
    if (identical(admin_vintage, current_admin_vintage())) {
      out[add] <- health[match(out$dtmnfr, health$dtmnfr), add, drop = FALSE]
    } else {
      link <- atom_link(admin_vintage, current_admin_vintage())
      for (col in add) {
        v <- health[[col]][match(link$to, health$dtmnfr)]
        one <- tapply(v, link$from, function(z) {
          z <- unique(z)
          if (length(z) == 1L) z else NA_character_
        })
        out[[col]] <- unname(one[out$dtmnfr])
      }
    }
  }

  # Only a NUTS level can lack its columns: health levels always get theirs.
  spec <- LOOKUP_LEVELS[[level]]
  if (!spec[[1L]] %in% names(out)) {
    stop(sprintf("level = '%s' needs the NUTS columns, which `nuts_vintage = NA` drops.",
                 level), call. = FALSE)
  }
  out <- collapse_to_level(out, spec)
  rownames(out) <- NULL
  out
}

#' Restrict a table to the columns that are constant within the level's unit
#'
#' A coarser level may only expose what it actually determines: asking for
#' municipios must not hand back one arbitrary freguesia's dtmnfr. `spec` is
#' the level's code column and, where it has one, its name column; both are
#' hoisted to the front.
#' @noRd
collapse_to_level <- function(df, spec) {
  key <- spec[[1L]]
  if (!identical(key, "dtmnfr")) {
    keep <- vapply(names(df), function(cc) {
      identical(cc, key) ||
        all(tapply(df[[cc]], df[[key]],
                   function(v) length(unique(v[!is.na(v)])) <= 1L))
    }, logical(1L))
    df <- df[, keep, drop = FALSE]
  }
  df <- unique(df[!is.na(df[[key]]), , drop = FALSE])
  front <- intersect(spec, names(df))
  df[order(df[[key]]), c(front, setdiff(names(df), front)), drop = FALSE]
}

#' The health vintage a level is read at when none is given
#'
#' ACES, merged or not, exist only before the 2024 reform; every other level
#' uses the reform's geography.
#' @noRd
level_health_vintage <- function(level) {
  if (level %in% c("aces", "aces_municipio")) "2022" else "2024"
}

#' Warn when a health level is read in the other health geography
#'
#' ULS exist only from the 2024 reform and ACES only before it. pt_lookup()'s
#' `unit` column is generic, so `level = "uls"` with the 2022 geography still
#' returns units -- that geography's ACES -- but not the ones the level names.
#' The regiões de saúde exist in both, so `"reg_saude"` never warns.
#' @noRd
warn_health_level_vintage <- function(level, health_vintage) {
  if (identical(level, "reg_saude") ||
      identical(health_vintage, level_health_vintage(level))) {
    return(invisible())
  }
  is_aces <- startsWith(level, "aces")
  got <- if (is_aces) "ULS" else "ACES"
  named <- if (is_aces) "ACES" else "ULS"
  warning(sprintf(
    paste0("level = \"%s\" with health_vintage = \"%s\" returns %s, not %s: ",
           "that is how the %s health geography is organized. Use level = ",
           "\"%s\" to say so."),
    level, health_vintage, got, named, health_vintage,
    sub(if (is_aces) "^aces" else "^uls", if (is_aces) "uls" else "aces", level)
  ), call. = FALSE)
}

#' The administrative vintage pt_registry treats as current
#'
#' Read from the data rather than hardcoded, so a future reform is picked up by
#' rebuilding rather than by editing this file.
#' @noRd
current_admin_vintage <- function() {
  max(axis_vintages("admin"))
}

#' The vintages one axis has, oldest first
#' @noRd
axis_vintages <- function(axis) {
  v <- switch(axis,
    admin  = as.data.frame(get_dataset("pt_registry"))$admin_vintage,
    nuts   = as.data.frame(get_dataset("pt_nuts_codes"))$nuts_vintage,
    health = as.data.frame(get_dataset("pt_health_codes"))$health_vintage,
    stop(sprintf("Internal error: unknown vintage axis '%s'.", axis), call. = FALSE)
  )
  sort(unique(v))
}

#' Validate a vintage argument
#'
#' The one rule for every function that takes a vintage: a value must be one of
#' the years the data has, and `NULL` is returned as `NULL` for the caller to
#' read as "the newest". There is deliberately no label for the newest vintage:
#' a year always means that year, so a script cannot change meaning when a
#' newer vintage is added. `extra` admits non-year values a caller supports
#' (`"auto"` in pt_match()).
#' @noRd
check_vintage <- function(value, axis, arg = paste0(axis, "_vintage"),
                          extra = character(0)) {
  if (is.null(value)) return(NULL)
  available <- axis_vintages(axis)
  value <- as.character(value)
  if (length(value) != 1L || is.na(value) || !value %in% c(available, extra)) {
    stop(sprintf("`%s` must be one of %s.", arg,
                 paste(shQuote(c(available, extra)), collapse = ", ")),
         call. = FALSE)
  }
  value
}
