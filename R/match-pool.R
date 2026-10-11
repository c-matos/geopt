# Building the name pool pt_match() searches.
#
# Everything here is derived from the atom model (R/atoms.R), which is what makes
# the three vintage axes independent. Two things INE's own geographic labels
# need follow from that, with no special handling:
#
#   - a NUTS context from any revision is recognised, because context columns are
#     built for every vintage of every context scheme. INE labels an indicator's
#     parent with the NUTS revision of that indicator, so "Minho-Lima" (2002) and
#     "Alto Minho" (2024) both scope a municipio;
#   - a name from another vintage of the level itself is matched and resolved to
#     the requested vintage's code, which covers both pre-2013 freguesia names
#     and pre-2024 NUTS III names with one mechanism.

# Vintages whose names are only a fallback when matching ANOTHER vintage: used
# when no later vintage has the name. Almost every 2001 freguesia kept its code
# and name in 2011, so a 2001 spelling is nearly always a 2011 one too, and the
# 2011 sense is the one to use: for the 14 freguesias that lost territory to a
# new one between the censuses, the 2001 sense reaches several of today's units
# and would make the name ambiguous.
FALLBACK_NAME_VINTAGES <- "2001"

# Which vintage axis each scheme moves on. The level's own vintage comes from
# that axis's argument to pt_match(); context schemes accept ALL their vintages.
SCHEME_AXIS <- c(
  freguesia = "admin", municipio = "admin", distrito = "admin",
  nuts1 = "nuts", nuts2 = "nuts", nuts3 = "nuts",
  reg_saude = "health", uls = "health", aces = "health",
  uls_municipio = "health", aces_municipio = "health"
)

#' The vintage a level is matched at
#'
#' Taken from the axis the level moves on. Health schemes exist at one vintage
#' each -- ULS only from 2024, ACES only before it -- so the argument is ignored
#' where it cannot apply, rather than erroring on a value the caller had no
#' reason to set.
#' @noRd
level_vintage <- function(scheme, admin_vintage, nuts_vintage, health_vintage) {
  available <- atom_vintages(scheme)
  want <- switch(SCHEME_AXIS[[scheme]],
                 admin = admin_vintage, nuts = nuts_vintage,
                 health = health_vintage)
  if (length(available) == 1L) return(available)
  if (is.null(want) || is.na(want)) return(max(available))
  want <- as.character(want)
  if (!want %in% available) {
    stop(sprintf("No %s data for vintage '%s'. Available: %s.",
                 scheme, want, paste(shQuote(available), collapse = ", ")),
         call. = FALSE)
  }
  want
}

#' Every spelling of every unit of `scheme` at `vintage`, keyed by code
#'
#' Official designations plus the simplified forms (`"União das freguesias de"`
#' dropped). INE publishes the simplified form, DGT the official one, so both
#' have to resolve. For the 2013 freguesias it also holds the names they carried
#' earlier on that map (kind `"former"`): they were that vintage's names too.
#' @noRd
scheme_names <- function(scheme, vintage) {
  n <- unit_names
  out <- n[n$scheme == scheme & n$vintage == vintage,
           c("code", "name"), drop = FALSE]
  out[!is.na(out$name) & nzchar(out$name), , drop = FALSE]
}

#' The parent unit of each unit, where it is unambiguous
#'
#' Computed through atoms, so it works for any (child scheme, child vintage,
#' parent scheme, parent vintage) combination. A unit whose atoms fall in more
#' than one parent gets `NA`: a parent that does not contain it whole cannot
#' scope it, and saying so is better than picking one.
#' @noRd
parent_names <- function(child_scheme, child_vintage,
                         parent_scheme, parent_vintage) {
  ch <- atom_membership(child_scheme, child_vintage)
  pa <- atom_membership(parent_scheme, parent_vintage)
  if (nrow(ch) == 0L || nrow(pa) == 0L) return(NULL)

  ch$parent <- pa$unit_code[match(ch$atom_id, pa$atom_id)]
  ch <- ch[!is.na(ch$parent), , drop = FALSE]
  if (nrow(ch) == 0L) return(NULL)

  sole <- tapply(ch$parent, ch$unit_code, function(v) {
    u <- unique(v)
    if (length(u) == 1L) u else NA_character_
  })
  data.frame(
    code = names(sole),
    parent_name = atom_unit_name(parent_scheme, parent_vintage, unname(sole)),
    stringsAsFactors = FALSE
  )
}

# Pools are derived entirely from R/sysdata.rda, so for a given set of arguments
# the answer never changes within a session. Building the freguesia pool costs
# ~2s (15 context columns, each an atom-level join), and pt_match() needs one per
# call -- so without this, repeated calls dominate anything that loops over
# pt_match().
.match_pool_cache <- new.env(parent = emptyenv())

#' Clear the memoized match pools
#'
#' Only useful after the internal tables are replaced in a live session, which
#' happens during `data-raw/` development.
#' @noRd
clear_match_pool_cache <- function() {
  rm(list = ls(.match_pool_cache, all.names = TRUE), envir = .match_pool_cache)
  invisible(NULL)
}

#' The pool pt_match() searches, for one level and one choice of vintages
#'
#' One row per (spelling, unit). Columns:
#'   code          the unit's code AT THE REQUESTED VINTAGE
#'   display_name  the spelling as published
#'   norm_name     pt_normalize(display_name)
#'   loose_name    pt_normalize_loose(display_name)
#'   tier          0 for a name of the requested vintage, 1 for another vintage's,
#'                 2 for a FALLBACK_NAME_VINTAGES one
#'   ctx_<scheme>_<vintage>  normalized parent names, one column per combination
#'
#' `tier` is what keeps the present tense winning: 161 pre-2013 freguesia names
#' spell the same as a live freguesia meaning a different unit, so match_one()
#' discards tier 1 whenever a tier 0 row matched.
#' @noRd
build_match_pool <- function(level,
                             admin_vintage = NULL,
                             nuts_vintage = NULL,
                             health_vintage = NULL,
                             historic = TRUE) {
  key <- paste(level, admin_vintage %||% "", nuts_vintage %||% "",
               health_vintage %||% "", isTRUE(historic), sep = "\r")
  hit <- .match_pool_cache[[key]]
  if (!is.null(hit)) return(hit)
  pool <- build_match_pool_uncached(level, admin_vintage, nuts_vintage,
                                    health_vintage, historic)
  assign(key, pool, envir = .match_pool_cache)
  pool
}

#' @noRd
build_match_pool_uncached <- function(level,
                                      admin_vintage = NULL,
                                      nuts_vintage = NULL,
                                      health_vintage = NULL,
                                      historic = TRUE) {
  spec <- MATCH_LEVELS[[level]]
  scheme <- spec$scheme
  v <- level_vintage(scheme, admin_vintage, nuts_vintage, health_vintage)

  # tier 0: the requested vintage's own spellings
  own <- scheme_names(scheme, v)
  pool <- data.frame(code = own$code, display_name = own$name, tier = 0L,
                     stringsAsFactors = FALSE)

  # Curated extra spellings -- see NAME_VARIANTS. Its codes are stated in the
  # CURRENT vintage, so they are mapped to the requested one rather than
  # discarded: "Vila da Praia da Vitoria" has to work whichever vintage is being
  # matched. A code unknown even in the current vintage is a table error and is
  # reported as one.
  variants <- NAME_VARIANTS[[level]]
  if (!is.null(variants) && nrow(variants) > 0L) {
    current <- max(atom_vintages(scheme))
    src <- if ("vintage" %in% names(variants)) variants$vintage else NA_character_
    src[is.na(src)] <- current

    bad <- !mapply(function(cd, sv) {
      cd %in% atom_membership(scheme, sv)$unit_code
    }, variants$code, src)
    if (any(bad)) {
      warning(sprintf(
        "NAME_VARIANTS[['%s']]: unknown code(s) %s -- entry ignored.",
        level, paste(sprintf("%s@%s", variants$code[bad], src[bad]),
                     collapse = ", ")), call. = FALSE)
      variants <- variants[!bad, , drop = FALSE]
      src <- src[!bad]
    }
    if (nrow(variants) > 0L) {
      # Each row's code is stated at its own vintage, so map from there.
      code_at_v <- mapply(function(cd, sv) {
        if (identical(sv, v)) return(cd)
        link <- atom_link(sv, v, scheme)
        hit <- link$to[link$from == cd]
        if (length(hit) == 1L) hit else NA_character_
      }, variants$code, src, USE.NAMES = FALSE)

      keep <- !is.na(code_at_v)
      if (any(keep)) {
        pool <- rbind(pool, data.frame(
          code = code_at_v[keep], display_name = variants$name[keep], tier = 0L,
          stringsAsFactors = FALSE))
      }
    }
  }

  # tier 1: spellings from the scheme's OTHER vintages, resolved to a code of
  # the requested one. A unit that became several is genuinely ambiguous and
  # contributes several rows, which match_one() reports rather than settling.
  # Tier 2 for a fallback vintage, so its names only count when nothing else has
  # them.
  if (isTRUE(historic)) {
    for (w in setdiff(atom_vintages(scheme), v)) {
      other <- scheme_names(scheme, w)
      if (nrow(other) == 0L) next
      link <- atom_link(w, v, scheme)
      j <- merge(other, link, by.x = "code", by.y = "from")
      if (nrow(j) == 0L) next
      pool <- rbind(pool, data.frame(
        code = j$to, display_name = j$name,
        tier = if (w %in% FALLBACK_NAME_VINTAGES) 2L else 1L,
        stringsAsFactors = FALSE))
    }
  }

  pool$norm_name  <- pt_normalize(pool$display_name)
  pool$loose_name <- pt_normalize_loose(pool$display_name)
  pool <- pool[!is.na(pool$norm_name) & nzchar(pool$norm_name), , drop = FALSE]

  # A spelling that belongs to the requested vintage must not also arrive as
  # another vintage's; keep the tier-0 row.
  pool <- pool[order(pool$code, pool$norm_name, pool$tier), ]
  pool <- pool[!duplicated(pool[, c("code", "norm_name")]), ]

  # context columns, one per (scheme, vintage) the caller might name. The
  # columns hold normalized names; ctx_display maps them back to the official
  # spelling, for warnings.
  ctx_display <- character()
  for (ps in spec$context) {
    for (pv in atom_vintages(ps)) {
      p <- parent_names(scheme, v, ps, pv)
      if (is.null(p)) next
      col <- paste0("ctx_", ps, "_", pv)
      pool[[col]] <- pt_normalize(p$parent_name[match(pool$code, p$code)])
      nm <- unique(p$parent_name[!is.na(p$parent_name)])
      ctx_display[pt_normalize(nm)] <- nm
    }
  }

  attr(pool, "vintage") <- v
  attr(pool, "ctx_display") <- ctx_display
  attr(pool, "level") <- level
  rownames(pool) <- NULL

  # scope_lookup() runs once per input element, so it must not scan the pool.
  # Index each context SCHEME to the rows each of its values selects, unioned
  # across that scheme's vintages -- which is the semantics scope_lookup wants
  # anyway, and turns up to 15 column scans into one hash lookup.
  attr(pool, "ctx_index") <- build_ctx_index(pool, spec)
  pool
}

#' scheme -> (normalized parent value -> row indices), in spec$context order
#' @noRd
build_ctx_index <- function(pool, spec) {
  idx <- list()
  for (ps in spec$context) {
    cols <- grep(paste0("^ctx_", ps, "_"), names(pool), value = TRUE)
    if (length(cols) == 0L) next
    rows <- unlist(lapply(cols, function(cc) seq_len(nrow(pool))), use.names = FALSE)
    vals <- unlist(lapply(cols, function(cc) pool[[cc]]), use.names = FALSE)
    keep <- !is.na(vals) & nzchar(vals)
    if (!any(keep)) next
    idx[[ps]] <- lapply(split(rows[keep], vals[keep]), unique)
  }
  idx
}

#' Guess which administrative vintage a vector of names or codes belongs to
#'
#' Not for mixed-vintage input. INE's long series accumulate several vintages of
#' names in one dimension (~5200 names for 4260 units); detection picks the ONE
#' vintage that resolves most of them, which is the best single answer but still
#' leaves the rest unmatched. Where a dimension is known to be single-vintage,
#' naming it outright is better than detecting it.
#'
#' The point of `admin_vintage = "auto"`. INE publishes the 2013 freguesia set
#' even on indicators labelled "NUTS - 2024", so assuming the current set turns
#' 134 units that were disaggregated in 2025 into ambiguous names. Detecting
#' instead of assuming is what makes that work without the caller having to know.
#'
#' Scored by how many distinct inputs each vintage can RESOLVE -- match to
#' exactly one code -- not merely recognize. The difference matters: a dimension
#' accumulating several vintages of names (INE's long series carry ~5200 for 4260
#' units) recognizes most of them at the 2011 vintage, but names from later
#' vintages then map backward onto several 2011 units each and resolve to
#' nothing. Counting recognition would pick the worst vintage on exactly those
#' inputs; counting unambiguous resolution picks the best.
#'
#' A tie that includes the current vintage goes to it: without evidence, present
#' tense is the safer reading. Otherwise it goes to the newest tied vintage --
#' in practice 2011 over 2001, which share almost every code and name, so data
#' containing none of the 25 units that differ cannot tell them apart. The
#' message says so.
#' @noRd
detect_admin_vintage <- function(x, level, quiet = FALSE, caller = "pt_match") {
  scheme <- MATCH_LEVELS[[level]]$scheme
  if (!identical(unname(SCHEME_AXIS[[scheme]]), "admin")) return(NULL)

  vints <- atom_vintages(scheme)
  current <- max(vints)
  vals <- unique(trimws(x[!is.na(x) & trimws(x) != ""]))
  if (length(vals) == 0L) return(current)

  padded <- pt_pad_code(vals, level)
  normed <- pt_normalize(vals)
  score <- vapply(vints, function(v) {
    pool <- build_match_pool(level, admin_vintage = v)
    # A fallback spelling that another vintage also has is never picked (see
    # match_one()), so it must not make that name look ambiguous here.
    shadowed <- pool$tier == 2L & pool$norm_name %in% pool$norm_name[pool$tier < 2L]
    pool <- pool[!shadowed, , drop = FALSE]
    # names resolving to exactly one code at this vintage
    per_name <- tapply(pool$code, pool$norm_name, function(z) length(unique(z)))
    ok_name <- normed %in% names(per_name)[per_name == 1L]
    codes_v <- if (identical(level, "freguesia")) resolve_code_aliases(padded, v) else padded
    ok_code <- codes_v %in% unique(pool$code)
    sum(ok_name | ok_code)
  }, integer(1L))

  tied <- vints[score == max(score)]
  best <- if (current %in% tied) current else max(tied)
  if (!identical(best, current) && !isTRUE(quiet)) {
    also <- setdiff(tied, best)
    message(sprintf(
      "%s: matching against the %s %s vintage (%d of %d inputs accounted for; %s would account for %d%s). Pass `admin_vintage` to override.",
      caller, best, scheme, max(score), length(vals), current,
      score[match(current, vints)],
      if (length(also)) sprintf(", and %s fits equally well", paste(also, collapse = ", ")) else ""))
  }
  best
}

#' Map each unit code to the value of a requested `to` column
#'
#' `to` names a column of the lookup assembled for these vintages, so it can
#' reach any level -- `dtmn` or `nuts3` from a freguesia, `reg_saude` from a
#' municipio. Returns `NULL` when `to` is the level's own code column.
#' @noRd
lookup_target <- function(level, to, admin_vintage = NULL,
                          nuts_vintage = NULL, health_vintage = NULL) {
  spec <- MATCH_LEVELS[[level]]
  if (identical(to, spec$code)) return(NULL)
  key <- spec$lookup_code %||% spec$code

  reg <- as.data.frame(get_dataset("pt_registry"))
  av <- admin_vintage %||% max(reg$admin_vintage)
  # ULS and ACES each exist in one health geography, so pt_match() ignores
  # `health_vintage` at those levels (see level_vintage()). Reading the table in
  # the other one would key it by the other scheme's units.
  hv <- if (level %in% setdiff(HEALTH_LEVELS, "reg_saude")) {
    level_health_vintage(level)
  } else {
    health_vintage %||% level_health_vintage(level)
  }
  args <- list(level = level, admin_vintage = av, health_vintage = hv)
  if (!is.null(nuts_vintage)) args$nuts_vintage <- nuts_vintage
  tab <- do.call(pt_lookup, args)

  if (!to %in% names(tab)) {
    # A column that exists at a finer level is simply not representable here --
    # `to = "dtmnfr"` for a municipio. That is NA, not an error. A name that is
    # no column at all is a mistake worth reporting.
    finest <- do.call(pt_lookup, utils::modifyList(args, list(level = "freguesia")))
    if (to %in% names(finest)) {
      return(stats::setNames(rep(NA_character_, nrow(tab)), tab[[key]]))
    }
    stop(sprintf("`to` must be a column of pt_lookup(). Unknown: '%s'.\nAvailable at level '%s': %s",
                 to, level, paste(names(tab), collapse = ", ")), call. = FALSE)
  }
  stats::setNames(as.character(tab[[to]]), tab[[key]])
}

#' Names of the context columns in a pool, most specific scheme first
#'
#' Ordered by `spec$context` so that a value naming both a municipio and a NUTS
#' region resolves as the narrower one, then by vintage descending so the current
#' nomenclature wins a tie.
#' @noRd
pool_ctx_cols <- function(pool, spec) {
  cols <- grep("^ctx_", names(pool), value = TRUE)
  ord <- unlist(lapply(spec$context, function(ps) {
    hit <- cols[startsWith(cols, paste0("ctx_", ps, "_"))]
    hit[order(hit, decreasing = TRUE)]
  }), use.names = FALSE)
  unique(c(ord, cols))
}
