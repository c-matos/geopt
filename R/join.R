# Joining user data to Portuguese administrative units.

# Maps the accepted `by` keywords to a matchable level. Both names and code
# columns are accepted, plus the common synonym "concelho".
BY_LEVEL_MAP <- c(
  freguesia    = "freguesia",
  dtmnfr      = "freguesia",
  municipio    = "municipio",
  concelho     = "municipio",
  dtmn         = "municipio",
  distrito     = "distrito",
  dt = "distrito",
  distrito_ilha = "distrito",
  nuts1     = "nuts1",
  nuts1_cod = "nuts1",
  nuts2     = "nuts2",
  nuts2_cod = "nuts2",
  nuts3     = "nuts3",
  nuts3_cod = "nuts3",
  uls = "uls",
  reg_saude = "reg_saude",
  aces = "aces",
  uls_municipio = "uls_municipio",
  aces_municipio = "aces_municipio"
)

#' Add official codes and administrative context to a data frame
#'
#' Matches a column of `data` against the [pt_registry] (via
#' [pt_match()]) and appends the administrative columns that are well-defined
#' at that level: codes, names of parent units, the NUTS regions of one
#' revision, and health mappings of both vintages. A column is only appended
#' when its value is constant within each matched unit. If you have data by
#' municipio, for example, pt_join will add `uls_municipio` and not `uls`.
#'
#' @section Vintages:
#' `admin_vintage` says which freguesia map `data` is on, and the codes and
#' names appended are that map's. INE publishes freguesias on the 2013 map, so
#' its data joins with `admin_vintage = "2013"` (or `"auto"`) and keeps its
#' 2013 codes; on the default, the current map, the uniões split in 2025
#' would not match. Health mappings are recorded on the current map, so on an
#' earlier one they are reached through shared territory, as in [pt_lookup()]:
#' a unit whose territory now lies in more than one ULS gets `NA`.
#'
#' `nuts_vintage` says which NUTS revision the NUTS columns are, and at a NUTS
#' level which revision `by` is matched against.
#'
#' @param data A data.frame.
#' @param by Which column of `data` identifies the unit, and what it contains.
#'   Forms:
#'   * `"municipio"` -- the column `municipio` in `data` holds municipality
#'     names or DTMN codes. Any keyword from the `by` registry works:
#'     `freguesia`/`dtmnfr`, `municipio`/`concelho`/`dtmn`,
#'     `distrito`/`dt`, `nuts1`-`nuts3` (`*_cod`), `uls`,
#'     `reg_saude`, `aces`, `uls_municipio`, `aces_municipio`.
#'   * `c(municipio = "muni_name")` -- similar to tidyverse join logic. This
#'     example assumes the municipio column in your data is called `muni_name`.
#'   * `c(freguesia = "freg", municipio = "mun")` -- first entry is the unit
#'     to match; further entries give context columns used to disambiguate.
#'     In this example, freguesia names scoped by municipio
#' @param admin_vintage Which administrative vintage `data` is on: `"2025"`,
#'   `"2013"`, `"2011"`, `"2001"`, or `"auto"` to infer it from the `by`
#'   column. Leave it out for the newest (`"2025"`). Ignored at the health
#'   levels, which exist on the current map only. See *Vintages*.
#' @param nuts_vintage Which NUTS revision the NUTS columns are: `"2024"`,
#'   `"2013"` or `"2002"`. Leave it out for the newest (`"2024"`). See
#'   *Vintages*.
#' @param fuzzy,aliases,quiet Passed to [pt_match()].
#'
#' @return `data` with the matched code column and administrative columns
#'   appended. Columns already present in `data` are not overwritten. The
#'   match report is attached and retrievable with [pt_match_report()].
#'
#' @examplesIf identical(Sys.getenv("NOT_CRAN"), "true")
#' df <- data.frame(concelho = c("Porto", "Lagoa (Acores)"), value = 1:2)
#' pt_join(df, by = c(municipio = "concelho"))
#'
#' # Data on the 2013 map, as INE publishes it: the uniao of Conde and
#' # Gandarela (Guimaraes) was split in 2025, so its code only exists there
#' ine <- data.frame(dtmnfr = "030882", value = 3)
#' pt_join(ine, by = "dtmnfr", admin_vintage = "2013")
#'
#' # The NUTS regions of the 2013 revision, under which Lisboa was PT17
#' pt_join(data.frame(concelho = "Lisboa"), by = c(municipio = "concelho"),
#'         nuts_vintage = "2013")
#'
#' @seealso [pt_match()], [get_map()] (which joins directly onto geometry)
#'
#' @export
pt_join <- function(data, by, fuzzy = FALSE, aliases = NULL,
                    admin_vintage = NULL, nuts_vintage = NULL, quiet = FALSE) {
  if (!is.data.frame(data)) stop("`data` must be a data.frame.", call. = FALSE)
  spec <- parse_by(by, data)
  admin_vintage <- check_vintage(admin_vintage, "admin", extra = "auto")
  nuts_vintage <- check_vintage(nuts_vintage, "nuts")

  # Resolved here rather than by pt_match(), because the columns appended below
  # have to come from the same vintage the codes were matched in.
  if (identical(admin_vintage, "auto")) {
    admin_vintage <- detect_admin_vintage(as.character(data[[spec$col]]),
                                          spec$level, quiet = quiet,
                                          caller = "pt_join")
  }

  context <- NULL
  if (!is.null(spec$context_col)) context <- data[[spec$context_col]]

  matched <- pt_match(
    data[[spec$col]],
    level = spec$level,
    context = context,
    admin_vintage = admin_vintage,
    nuts_vintage = nuts_vintage,
    fuzzy = fuzzy,
    aliases = aliases,
    quiet = quiet
  )

  code_col <- MATCH_LEVELS[[spec$level]]$code
  block <- codes_at_level(spec$level, admin_vintage = admin_vintage,
                          nuts_vintage = nuts_vintage)

  idx <- match(matched, block[[code_col]])
  new_cols <- setdiff(names(block), names(data))
  for (col in new_cols) {
    data[[col]] <- block[[col]][idx]
  }

  if (!quiet) {
    n_ok <- sum(!is.na(matched))
    message(sprintf("pt_join: %d/%d row(s) matched at %s level.",
                    n_ok, nrow(data), spec$level))
  }

  attr(data, "report") <- attr(matched, "report")
  data
}

# --- Internal helpers ------------------------------------------------------------

#' Join user data onto a composed boundary sf (used by get_map)
#'
#' Resolves `data[[by]]` to the map level's code column via pt_match() and
#' appends the data columns to `sf_obj`, preserving row order. Boundaries
#' without a data row get NA. `not_drawn` holds the codes of units left off
#' the map on purpose (an archipelago with `islands = "none"`): data rows for
#' them matched, so they are not reported as unmatched. Names are matched
#' against the map's own vintages.
#' @noRd
join_map_data <- function(sf_obj, level, data, by, fuzzy = FALSE, aliases = NULL,
                          not_drawn = NULL, admin_vintage = NULL,
                          nuts_vintage = NULL) {
  if (is.null(by)) {
    stop("`by` is required when `data` is supplied. Example: by = c(municipio = \"concelho\").",
         call. = FALSE)
  }
  if (!is.data.frame(data)) stop("`data` must be a data.frame.", call. = FALSE)

  spec <- parse_by(by, data)
  if (spec$level != level) {
    stop(sprintf(
      "`by` keyword '%s' resolves to level '%s', but the map level is '%s'. Join keys must match the map level.",
      names(BY_LEVEL_MAP)[match(spec$level, BY_LEVEL_MAP)][1L] %||% spec$level,
      spec$level, level
    ), call. = FALSE)
  }

  key_col <- MATCH_LEVELS[[level]]$code
  if (!key_col %in% names(sf_obj)) {
    stop(sprintf("Internal error: boundary data lacks key column '%s'.", key_col),
         call. = FALSE)
  }

  # Values that already are keys of THIS map join directly — this keeps
  # vintage-specific codes working on maps of another vintage (a 2013-era
  # dtmnfr on the 2013 map) without a round trip through the registry. Everything else
  # (names, stray codes) resolves through pt_match().
  vals <- data[[spec$col]]
  raw <- if (level %in% c("freguesia", "municipio", "distrito")) {
    pt_pad_code(vals, level)
  } else {
    toupper(trimws(as.character(vals)))
  }
  matched <- ifelse(!is.na(raw) & raw %in% sf_obj[[key_col]], raw, NA_character_)

  todo <- which(is.na(matched) & !is.na(vals))
  if (length(todo) > 0L) {
    context <- if (!is.null(spec$context_col)) data[[spec$context_col]] else NULL
    resolved <- pt_match(
      vals[todo],
      level = level,
      context = if (!is.null(context)) context[todo] else NULL,
      fuzzy = fuzzy,
      aliases = aliases,
      admin_vintage = admin_vintage,
      nuts_vintage = nuts_vintage
    )
    matched[todo] <- as.character(resolved)
  }

  dup <- duplicated(matched) & !is.na(matched)
  if (any(dup)) {
    warning(sprintf(
      "get_map: %d duplicated key(s) in `data`; keeping the first row of each.",
      sum(dup)
    ), call. = FALSE)
  }

  idx <- match(sf_obj[[key_col]], matched)

  # A data column the boundaries already have is never joined. Only say so when
  # its values differ from the map's: then something of the user's is being left
  # out. When they agree -- the `freguesia` names pt_recode() and pt_join() add,
  # say -- nothing is lost, and a warning would only be noise.
  data_cols <- setdiff(names(data), c(spec$col, spec$context_col))
  clash <- intersect(data_cols, names(sf_obj))
  differs <- vapply(clash, function(col) {
    ours <- as.character(sf_obj[[col]])
    theirs <- as.character(data[[col]][idx])
    both <- !is.na(ours) & !is.na(theirs)
    any(ours[both] != theirs[both])
  }, logical(1L))
  if (any(differs)) {
    warning(sprintf(
      "get_map: column(s) already present in the boundaries, with different values, were not joined: %s",
      paste(clash[differs], collapse = ", ")
    ), call. = FALSE)
  }
  data_cols <- setdiff(data_cols, clash)

  for (col in data_cols) {
    sf_obj[[col]] <- data[[col]][idx]
  }

  n_data_unmatched <- sum(is.na(matched) |
                            !(matched %in% c(sf_obj[[key_col]], not_drawn)))
  if (n_data_unmatched > 0L) {
    warning(sprintf(
      "get_map: %d row(s) of `data` did not match any boundary. See pt_match() for disambiguation options.",
      n_data_unmatched
    ), call. = FALSE)
  }
  n_bound_unmatched <- sum(!sf_obj[[key_col]] %in% matched, na.rm = TRUE)
  if (n_bound_unmatched > 0L) {
    message(sprintf(
      "get_map: %d boundar%s ha%s no data row (NA fill).",
      n_bound_unmatched,
      if (n_bound_unmatched == 1L) "y" else "ies",
      if (n_bound_unmatched == 1L) "s" else "ve"
    ))
  }

  sf_obj
}

#' Parse the `by` argument shared by pt_join() and get_map()
#'
#' Returns list(level, col, context_col). `by` entries are
#' keyword = data-column pairs; unnamed entries mean the keyword doubles as
#' the column name.
#' @noRd
parse_by <- function(by, data) {
  if (!is.character(by) || length(by) < 1L) {
    stop("`by` must be a character vector, e.g. by = \"municipio\" or by = c(municipio = \"my_col\").",
         call. = FALSE)
  }

  keys <- names(by) %||% rep("", length(by))
  keys[keys == ""] <- by[keys == ""]
  keys <- tolower(keys)

  unknown <- setdiff(keys, names(BY_LEVEL_MAP))
  if (length(unknown) > 0L) {
    stop(sprintf(
      "Unknown `by` keyword(s): %s. Use one of: %s",
      paste(unknown, collapse = ", "),
      paste(unique(names(BY_LEVEL_MAP)), collapse = ", ")
    ), call. = FALSE)
  }

  missing_cols <- setdiff(unname(by), names(data))
  if (length(missing_cols) > 0L) {
    stop(sprintf("Column(s) not found in data: %s",
                 paste(missing_cols, collapse = ", ")), call. = FALSE)
  }

  if (length(by) > 2L) {
    stop("`by` accepts at most 2 entries: the unit column and one context column.",
         call. = FALSE)
  }

  list(
    level = unname(BY_LEVEL_MAP[keys[1L]]),
    col = unname(by[1L]),
    context_col = if (length(by) == 2L) unname(by[2L]) else NULL
  )
}

#' The lookup table aggregated to a level
#'
#' Unique rows of the columns that are constant within each unit of `level`,
#' with the level's own code column first -- which is exactly what pt_lookup()
#' does, so this delegates to it.
#'
#' Both health vintages are attached, under their own names, because a join may
#' legitimately want either. This is the only place both vintages sit side by
#' side, and it is confined to here.
#' @noRd
codes_at_level <- function(level, admin_vintage = NULL, nuts_vintage = NULL) {
  spec <- MATCH_LEVELS[[level]]
  code_col <- spec$code
  is_health <- identical(unname(SCHEME_AXIS[[spec$scheme]]), "health")
  args <- list(level = level)
  # Health units are defined on the current map's freguesias only, so a health
  # level's table never depends on the admin vintage (pt_match() ignores it at
  # those levels too).
  if (!is.null(admin_vintage) && !is_health) args$admin_vintage <- admin_vintage
  if (!is.null(nuts_vintage)) args$nuts_vintage <- nuts_vintage

  # pt_health_codes is long over both vintages, so its columns are generic;
  # pt_join()'s output names them by vintage. The 2022 regiao de saude is
  # reg_saude_2022 only next to the 2024 one: alone (an ACES join) it is plain
  # reg_saude, as in pt_aces.
  health_names <- list(
    "2024" = c(reg_saude = "reg_saude", unit = "uls",
               unit_municipio = "uls_municipio"),
    "2022" = c(reg_saude = "reg_saude_2022", unit = "aces",
               unit_municipio = "aces_municipio")
  )
  at_vintage <- function(hv, alone = FALSE) {
    t <- do.call(pt_lookup, c(args, list(health_vintage = hv)))
    ren <- health_names[[hv]]
    if (alone) ren <- ren[names(ren) != "reg_saude"]
    for (k in names(ren)) {
      if (k %in% names(t)) names(t)[names(t) == k] <- ren[[k]]
    }
    t
  }

  if (is_health) {
    # A health level's own key column only exists once health is attached, and
    # only its OWN vintage is meaningful here: an ACES has a 2022 regiao de
    # saude, and asking it for a 2024 one would be a category error.
    out <- at_vintage(level_health_vintage(level), alone = TRUE)
  } else {
    out <- at_vintage("2024")
    other <- at_vintage("2022")
    add <- setdiff(names(other), names(out))
    if (length(add) > 0L && code_col %in% names(other)) {
      out[add] <- other[match(out[[code_col]], other[[code_col]]), add,
                        drop = FALSE]
    }
  }
  rownames(out) <- NULL
  out
}
