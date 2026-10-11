# Deriving higher-level boundaries from freguesias, and building maps of other
# vintages on demand.
#
# The same dissolve logic serves two callers: data-raw/derive_datasets.R
# (bundled data, built once) and get_map(admin_vintage =, nuts_vintage =)
# (other vintages, built on demand; downloaded ones cached).

# Identity columns per level. Dissolving keeps these (they are constant
# within a unit) and sums area_ha.
LEVEL_KEY_COLS <- list(
  municipio = c("dtmn", "municipio", "dt", "distrito_ilha",
                "nuts1_cod", "nuts1", "nuts2_cod", "nuts2",
                "nuts3_cod", "nuts3"),
  distrito  = c("dt", "distrito_ilha", "nuts1_cod", "nuts1"),
  nuts3     = c("nuts3_cod", "nuts3", "nuts2_cod", "nuts2", "nuts1_cod", "nuts1"),
  nuts2     = c("nuts2_cod", "nuts2", "nuts1_cod", "nuts1"),
  nuts1     = c("nuts1_cod", "nuts1"),
  # Health units carry only the region columns that are constant within every
  # unit: nuts1 always (no unit crosses between the mainland and the islands),
  # plus the regiao de saude for ACES (the 2022 one, the only vintage an ACES
  # has). reg_saude is NOT constant within every ULS (ULS Medio Tejo spans two
  # regioes de saude), and NUTS 2/3 and distrito vary within several units of
  # each scheme.
  uls       = c("uls", "nuts1_cod", "nuts1"),
  reg_saude = c("reg_saude", "nuts1_cod", "nuts1"),
  aces      = c("aces", "reg_saude", "nuts1_cod", "nuts1"),
  # Merges of the units above, so the same columns are constant within them.
  uls_municipio  = c("uls_municipio", "nuts1_cod", "nuts1"),
  aces_municipio = c("aces_municipio", "reg_saude", "nuts1_cod", "nuts1")
)

# Count columns per level (functions of the constituent freguesia rows).
LEVEL_EXTRA_COLS <- list(
  municipio = list(n_freguesias = function(d) nrow(d)),
  distrito  = list(
    n_municipios = function(d) length(unique(d$dtmn)),
    n_freguesias = function(d) nrow(d)
  ),
  nuts3 = list(n_municipios = function(d) length(unique(d$dtmn))),
  nuts2 = list(),
  nuts1 = list(),
  uls = list(
    n_municipios = function(d) length(unique(d$dtmn)),
    n_freguesias = function(d) nrow(d)
  ),
  reg_saude = list(n_municipios = function(d) length(unique(d$dtmn))),
  aces = list(
    n_municipios = function(d) length(unique(d$dtmn)),
    n_freguesias = function(d) nrow(d)
  ),
  uls_municipio = list(
    n_municipios = function(d) length(unique(d$dtmn)),
    n_freguesias = function(d) nrow(d)
  ),
  aces_municipio = list(
    n_municipios = function(d) length(unique(d$dtmn)),
    n_freguesias = function(d) nrow(d)
  )
)

#' Dissolve freguesias into a higher level
#'
#' Groups by the key columns, unions geometry, sums area_ha, and computes the
#' per-level count columns. Key columns missing from the input are skipped.
#' @noRd
dissolve_level <- function(sf_obj, key_cols, extra = list()) {
  key_cols <- intersect(key_cols, names(sf_obj))
  if (length(key_cols) == 0L) {
    stop("None of the dissolve key columns are present.", call. = FALSE)
  }

  df <- sf::st_drop_geometry(sf_obj)
  key <- do.call(paste, c(df[key_cols], sep = "\r"))
  groups <- unique(key)

  rows <- lapply(groups, function(g) {
    sel <- key == g
    sub <- sf_obj[sel, , drop = FALSE]
    attrs <- sf::st_drop_geometry(sub)[1L, key_cols, drop = FALSE]
    if ("area_ha" %in% names(df)) {
      attrs$area_ha <- round(sum(as.numeric(sf::st_drop_geometry(sub)$area_ha)), 2)
    }
    for (nm in names(extra)) attrs[[nm]] <- extra[[nm]](sf::st_drop_geometry(sub))
    geom <- sf::st_cast(sf::st_union(sub), "MULTIPOLYGON")
    sf::st_sf(attrs, geometry = geom)
  })
  out <- do.call(rbind, rows)

  # The first key identifies the unit; the others must be constant within it.
  # One that varies would quietly split the unit into several rows.
  split_units <- unique(out[[key_cols[1L]]][duplicated(out[[key_cols[1L]]])])
  if (length(split_units) > 0L) {
    stop(sprintf(
      "Dissolving by '%s': %d unit(s) split because another key column varies within them (e.g. %s). Keep only columns constant within each unit.",
      key_cols[1L], length(split_units), split_units[1L]
    ), call. = FALSE)
  }

  out <- out[order(out[[key_cols[1L]]]), ]
  rownames(out) <- NULL
  out
}

#' Build one administrative level from an enriched freguesias sf
#' @noRd
build_level_from_freguesias <- function(freg, level) {
  if (level == "freguesia") return(freg)
  dissolve_level(freg, LEVEL_KEY_COLS[[level]],
                 extra = LEVEL_EXTRA_COLS[[level]] %||% list())
}

# --- Maps of other vintages -------------------------------------------------------

# The CAOP release that carries each administrative vintage's freguesia map,
# checked 2026-10-01 against every release DGT publishes: 2022, 2023 and 2024
# hold exactly the 2013 map's freguesias, 2024_1 and 2025 the 2025 map's. The
# newest vintage is the bundled data, so it has no entry. The 2011 and 2001
# maps are only in DGT's older shapefile releases (CAOP 2012.1 carries the 2011
# map exactly), which geopt doesn't read: INE's census areas of those years
# carry the same freguesia codes.
CAOP_RELEASE_FOR_ADMIN <- c("2013" = 2024L)

NUTS_LEVELS <- c("nuts1", "nuts2", "nuts3")
NUTS_COLS <- c("nuts1_cod", "nuts1", "nuts2_cod", "nuts2", "nuts3_cod", "nuts3")

#' Give a boundary sf the NUTS columns of one revision
#'
#' Every NUTS revision groups whole municipios, so the columns follow from
#' `dtmn` alone, whatever the administrative vintage. Existing NUTS columns are
#' overwritten in place, so the column order does not change. Without `dtmn`
#' (distrito and health maps) only NUTS 1 can be present, and NUTS 1 is the same
#' in every revision.
#' @noRd
attach_nuts <- function(sf_obj, nuts_vintage) {
  if (!"dtmn" %in% names(sf_obj)) return(sf_obj)
  n <- as.data.frame(get_dataset("pt_nuts_codes"))
  n <- n[n$nuts_vintage == nuts_vintage, , drop = FALSE]
  idx <- match(sf_obj$dtmn, n$dtmn)
  for (col in NUTS_COLS) sf_obj[[col]] <- n[[col]][idx]
  geom <- attr(sf_obj, "sf_column")
  sf_obj[, c(setdiff(names(sf_obj), geom), geom)]
}

#' The boundaries get_map() draws for a level, on one admin vintage's map with
#' one NUTS revision's regions
#'
#' The newest of both is the bundled data. A NUTS revision on the bundled map
#' swaps the NUTS columns, or for a NUTS level dissolves the bundled freguesias
#' (about 1.5 s, so not cached). Another admin vintage is downloaded from the
#' CAOP release that carries it, simplified, and cached, as are the levels
#' built from it.
#' @noRd
get_vintage_dataset <- function(level, admin_vintage, nuts_vintage,
                                client = NULL) {
  newest_admin <- identical(admin_vintage, current_admin_vintage())
  newest_nuts <- identical(nuts_vintage, max(axis_vintages("nuts")))
  bundled <- function() get_dataset(paste0("pt_", level_to_dataset(level)))

  if (level %in% HEALTH_LEVELS) {
    if (!newest_admin) {
      stop(sprintf(
        "Level '%s' is only available on the %s map: the health mappings are defined for its freguesias only.",
        level, current_admin_vintage()
      ), call. = FALSE)
    }
    return(bundled())  # health maps carry only NUTS 1, the same in every revision
  }

  if (newest_admin) {
    if (newest_nuts) return(bundled())
    if (!level %in% NUTS_LEVELS) return(attach_nuts(bundled(), nuts_vintage))
    freg <- attach_nuts(get_dataset("pt_freguesias"), nuts_vintage)
    return(build_level_from_freguesias(freg, level))
  }

  release <- CAOP_RELEASE_FOR_ADMIN[admin_vintage]
  if (is.na(release)) {
    stop(sprintf(
      "There are no boundaries for the %s map. To draw it, merge INE's %s census areas by their dtmnfr column: get_censos(..., year = %s) downloads them (see vignette(\"vintages\")). Or convert the data to the %s or %s map with pt_recode().",
      admin_vintage, admin_vintage, admin_vintage,
      names(CAOP_RELEASE_FOR_ADMIN)[1L], current_admin_vintage()
    ), call. = FALSE)
  }

  client <- client %||% GeoClient$new()
  freg_file <- vintage_cache_file(client, "freguesia", admin_vintage, release)
  level_file <- vintage_cache_file(client, level, admin_vintage, release,
                                   nuts_vintage)

  if (client$use_cache && file.exists(level_file)) {
    message(sprintf("Using cached %s boundaries for the %s map", level,
                    admin_vintage))
    return(readRDS(level_file))
  }

  if (client$use_cache && file.exists(freg_file)) {
    freg <- readRDS(freg_file)
  } else {
    freg <- build_caop_freguesias(release, admin_vintage, client)
    if (client$use_cache) saveRDS(freg, freg_file)
  }

  out <- build_level_from_freguesias(attach_nuts(freg, nuts_vintage), level)
  if (client$use_cache) saveRDS(out, level_file)
  out
}

#' Where get_vintage_dataset() caches a map. The CAOP release is part of the
#' name, so a change to CAOP_RELEASE_FOR_ADMIN never reuses an old file.
#' @noRd
vintage_cache_file <- function(client, level, admin_vintage, release,
                               nuts_vintage = NULL) {
  dir <- file.path(client$cache_dir, "processed")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  nuts <- if (is.null(nuts_vintage)) "" else paste0("_nuts", nuts_vintage)
  file.path(dir, sprintf("geopt_map_%s_admin%s%s_caop%d.rds", level,
                         admin_vintage, nuts, release))
}

#' Harmonize a raw CAOP freguesias download into the geopt schema
#'
#' Column names drift between CAOP years (the freguesia code is `dicofre` in
#' 2022 and 2023, `dtmnfr` from 2024). This keeps only the vintage-specific
#' identity (dtmnfr, freguesia names, area) from the download, attaches the
#' municipio and distrito names of that admin vintage via the stable DTMN code,
#' and puts the columns in pt_freguesias' order. NUTS columns are attached
#' separately, by attach_nuts().
#' @noRd
harmonize_caop_freguesias <- function(freg, release, admin_vintage) {
  names(freg) <- tolower(names(freg))

  pick_col <- function(candidates) {
    hit <- intersect(candidates, names(freg))
    if (length(hit) > 0L) hit[1L] else NULL
  }

  # CAOP's own column names, not geopt's.
  dtmnfr_col <- pick_col(c("dtmnfr", "dicofre", "di_co_fre", "cod_dicofre"))
  if (is.null(dtmnfr_col)) {
    stop(sprintf(
      "Could not find a DTMNFR column in the CAOP %d freguesias (columns: %s).",
      release, paste(setdiff(names(freg), attr(freg, "sf_column")), collapse = ", ")
    ), call. = FALSE)
  }
  name_col <- pick_col(c("freguesia", "designacao", "des_simpli", "freg"))
  simpl_col <- pick_col(c("designacao_simplificada", "des_simpli"))
  area_col <- pick_col(c("area_ha", "area_h", "areaha"))
  perim_col <- pick_col("perimetro_km")

  out <- sf::st_sf(
    dtmnfr = pt_pad_code(freg[[dtmnfr_col]], "freguesia"),
    geometry = sf::st_geometry(freg)
  )
  out$freguesia <- if (!is.null(name_col)) as.character(freg[[name_col]]) else NA_character_
  if (!is.null(simpl_col) && !identical(simpl_col, name_col)) {
    out$designacao_simplificada <- as.character(freg[[simpl_col]])
  }
  out$dtmn <- substr(out$dtmnfr, 1L, 4L)
  out$dt <- substr(out$dtmnfr, 1L, 2L)
  out$area_ha <- if (!is.null(area_col)) {
    round(as.numeric(freg[[area_col]]), 2)
  } else {
    round(as.numeric(sf::st_area(freg)) / 1e4, 2)
  }
  if (!is.null(perim_col)) out$perimetro_km <- round(as.numeric(freg[[perim_col]]), 2)

  # Names from geopt's registry, as on the bundled map, so the map and
  # pt_lookup() name every unit alike. For the 2013 map the official names
  # already are CAOP 2024's; the simplified ones are not, because DGT's list
  # leaves 32 uniões unsimplified.
  reg <- pt_lookup(level = "freguesia", admin_vintage = admin_vintage,
                   nuts_vintage = NA)
  idx_reg <- match(out$dtmnfr, reg$dtmnfr)
  for (col in c("freguesia", "designacao_simplificada")) {
    if (!col %in% names(out)) next
    from_reg <- reg[[col]][idx_reg]
    out[[col]] <- ifelse(is.na(from_reg), out[[col]], from_reg)
  }

  # municipio and distrito names of this vintage (DTMN codes are stable since
  # 1998, so every freguesia finds its municipio).
  ctx <- pt_lookup(level = "municipio", admin_vintage = admin_vintage,
                   nuts_vintage = NA)
  idx <- match(out$dtmn, ctx$dtmn)
  for (col in c("municipio", "distrito_ilha")) out[[col]] <- ctx[[col]][idx]

  n_orphan <- sum(is.na(idx))
  if (n_orphan > 0L) {
    warning(sprintf(
      "CAOP %d: %d freguesia(s) belong to a municipality not in the %s registry; their municipio and distrito columns are NA.",
      release, n_orphan, admin_vintage
    ), call. = FALSE)
  }

  # NUTS placeholders, so attach_nuts() fills them in pt_freguesias' order.
  for (col in NUTS_COLS) out[[col]] <- NA_character_
  ord <- intersect(names(get_dataset("pt_freguesias")), names(out))
  out[, ord]
}

#' Download, simplify, and harmonize the freguesias of one CAOP release
#' @noRd
build_caop_freguesias <- function(release, admin_vintage, client) {
  # Before any download: a missing rmapshaper would otherwise only show up
  # after about 140 MB.
  check_suggested_pkg("rmapshaper", "to build maps of other vintages")

  parts <- lapply(VALID_REGIONS, function(r) {
    sf_obj <- client$get_caop(r, "freguesia", year = release, detail = "full")
    sf::st_transform(sf_obj, 4326L)
  })
  common_cols <- Reduce(intersect, lapply(parts, names))
  freg <- do.call(rbind, lapply(parts, function(x) x[, common_cols]))

  message(sprintf(
    "Simplifying the %s map's freguesias (CAOP %d; once, then cached)...",
    admin_vintage, release
  ))
  freg <- rmapshaper::ms_simplify(freg, keep = 0.01, keep_shapes = TRUE)

  harmonize_caop_freguesias(freg, release, admin_vintage)
}
