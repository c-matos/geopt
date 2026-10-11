# INE Censos geographies: BGRI subsecções/secções and the 1 km GRID.
#
# INE distributes these as static zipped GeoPackages (one file per
# municipality, NUTS region, or autonomous region) behind the download trees
# at https://mapas.ine.pt/download/. The URL inventory is parsed from those
# pages by data-raw/censos_manifest.R and shipped as the internal
# `censos_manifest` table, so nothing is scraped at runtime.

# --- Constants ---------------------------------------------------------------

CENSOS_BASE_URL <- "https://mapas.ine.pt/download"

CENSOS_YEARS <- c(1991L, 2001L, 2011L, 2021L)

CENSOS_LEVELS <- c("subseccao", "seccao", "grid")

# INE census files follow the NUTS 2013 geography. Mainland NUTS2 files are
# named, NUTS3 files use the 2013 code sans the "PT" prefix.
CENSOS_NUTS2_IDS <- c(
  PT11 = "NORTE", PT16 = "CENTRO", PT17 = "LISBOA",
  PT18 = "ALENTEJO", PT15 = "ALGARVE"
)

# Identifier columns per product/year -> tidy, year-stable names. A length-2
# entry means the tidy code is the concatenation of the two columns.
CENSOS_ID_SPECS <- list(
  bgri_1991 = list(
    bgri = "BGRE1991", dtmn = "DTCC91", dtmnfr = "DTCCFR91",
    seccao = "SECNUM91", subseccao = "SSNUM91",
    lugar = "LUG_1991", lugar_nome = "LUG91DSG"
  ),
  bgri_2001 = list(
    bgri = "BGRI2001", dtmn = "DTCC01", dtmnfr = "DTCCFR01",
    seccao = "SECNUM01", subseccao = "SSNUM01",
    lugar = "LUG_2001", lugar_nome = "LUG01DSG"
  ),
  bgri_2011 = list(
    bgri = "BGRI11", dtmn = "DTMN11", dtmnfr = c("DTMN11", "FR11"),
    seccao = "SEC11", subseccao = "SS11",
    lugar = "LUG11", lugar_nome = "LUG11DESIG"
  ),
  bgri_2021 = list(
    bgri = "BGRI2021", dtmn = "DTMN21", dtmnfr = "DTMNFR21",
    seccao = "SECNUM21", subseccao = "SSNUM21"
  ),
  seccoes_2021 = list(
    dtmn = "DTMN21", dtmnfr = "DTMNFR21", seccao = "SECNUM21"
  ),
  grid_2021 = list(
    grd_id = "GRD_ID2021"
  )
)

# INE join/GIS artifacts dropped on read (case-insensitive exact match).
# `n_aloj` is an undocumented column that appears only in the Açores 2011
# files (not mainland/Madeira) and matches no known dwelling total; it is
# dropped so the 2011 schema is identical across regions.
CENSOS_DROP_COLS <- c(
  "objectid", "shape_length", "shape_area", "shape_leng",
  "ano", "nivel", "nivel_dsg", "ordem", "geo_cod", "geo_cod_dsg",
  "geog_2002", "designacao", "n_aloj"
)

# Enumerated GIS join keys (OBJECTID, OBJECTID_1, OBJECTID_12, ...): some
# per-municipality exports carry a stray one, others do not.
CENSOS_DROP_PATTERN <- "^objectid(_[0-9]+)?$"

# --- Public API ---------------------------------------------------------------

#' Get INE census geographies (BGRI, secções, GRID)
#'
#' Downloads and reads the census geographies that INE distributes at
#' <https://mapas.ine.pt/download/index2021.phtml>: BGRI subsecções
#' (city-block/place-part polygons) for the 1991, 2001, 2011, and 2021
#' censuses, statistical secções, and the 1 km grid — each with the
#' census variables INE embeds in the files. Files are fetched at the
#' smallest scope that covers the request (per-municipality files are
#' typically 1–3 MB) and cached.
#'
#' @section Scope:
#' Exactly one scope must be given (there is no default: a whole-country
#' request is ~250 MB and must be explicit):
#'
#' * `municipio`: one or more municipality names or 4-digit DTMN codes,
#'   resolved via [pt_match()] (qualifiers like `"Lagoa (Açores)"` work).
#'   Downloads the per-municipality file(s).
#' * `freguesia`: one or more freguesia names or 6-digit DTMNFR codes.
#'   Downloads the enclosing municipality file(s) and filters. May be
#'   combined with `municipio` to disambiguate names.
#' * `region`: `"portugal"`, `"continente"`, `"raa"`/`"açores"`,
#'   `"ram"`/`"madeira"`, a NUTS2 or NUTS3 name, or a NUTS 2013 code
#'   (`"PT16D"`/`"16D"`). Census files follow the NUTS 2013 geography;
#'   NUTS 2024 names are accepted when they map unambiguously to it.
#'
#' @section Levels and years:
#' * `"subseccao"` (default): BGRI subsecções, available for all four
#'   censuses. 2021 files embed 32 census variables, 2011 files 122,
#'   1991/2001 files seven basic counts.
#' * `"seccao"`: statistical secções. For 2021 these are INE's native files
#'   with ~180 variables (more detail than the subsecção set). For earlier
#'   censuses no secção product exists: subsecções are downloaded and
#'   dissolved, summing that year's variables (adds `n_subseccoes`).
#' * `"grid"`: the 2021-only 1 km grid (EPSG:3035 cells crossing
#'   administrative boundaries), `region` scope only.
#'
#' See [pt_censos_vars] for every variable with its INE description.
#'
#' @section Identifiers:
#' INE's identifier columns are year-suffixed and inconsistent
#' (`DTCC91`, `DTMN21`, `FR11`, ...). Year-stable tidy columns are added
#' alongside the originals: `censos_year`, `bgri` (full subsecção code),
#' `dtmn`, `dtmnfr`, `seccao`, `subseccao`, and — where the file carries
#' them (1991–2011) — `lugar`/`lugar_nome`. GIS artifacts (`OBJECTID`,
#' `SHAPE_*`) and INE join metadata are dropped.
#'
#' Freguesia codes are vintage-specific: each census uses the freguesia map
#' in force at the time. The `dtmnfr` codes of the 2021 census are the
#' `"2013"` vintage, those of 2011 the `"2011"` vintage and those of 2001 the
#' `"2001"` vintage, so [pt_recode()] converts them to today's map. The 1991
#' census used an earlier map (4208 freguesias in 305 municípios, before
#' Odivelas, Trofa and Vizela were created in 1998), which geopt has no
#' vintage for.
#'
#' Name-based `freguesia` scoping resolves against the current registry and,
#' for 2021, also matches through [pt_crosswalk()]; for older censuses pass
#' that era's codes if a name does not resolve. In the 2001 files, two
#' freguesias still carry the code of the municipality they belonged to before
#' a transfer: Vale de Amoreira is `090756` (Guarda, now Manteigas) and Moita
#' `100117` (Alcobaça, now Marinha Grande). [pt_recode()] and [pt_match()]
#' accept those codes for the `"2001"` vintage, and a `freguesia` filter finds
#' either form.
#'
#' @param municipio Municipality name(s) or DTMN code(s). See *Scope*.
#' @param year Census year: 1991, 2001, 2011, or 2021 (default).
#' @param level `"subseccao"` (default), `"seccao"`, or `"grid"`.
#' @param region Region keyword, NUTS2/NUTS3 name, or NUTS 2013 code.
#'   See *Scope*.
#' @param freguesia Freguesia name(s) or DTMNFR code(s). See *Scope*.
#' @param variables Optional character vector of census variables to keep
#'   (case-insensitive; identifier columns are always kept). See
#'   [pt_censos_vars].
#' @param geometry Logical. `FALSE` drops the geometry and returns a plain
#'   data.frame. Default `TRUE`.
#' @param crs Output EPSG code. If `NULL`, uses the client default (4326).
#' @param client Optional [GeoClient] to use (for a custom cache directory
#'   or CRS). Defaults to `GeoClient$new()`.
#'
#' @return An sf object (or a data.frame when `geometry = FALSE`) with one
#'   row per subsecção, secção, or grid cell. A failed download stops with an
#'   error of class `geopt_download_error` saying why (see [GeoClient]).
#'
#' @examplesIf identical(Sys.getenv("NOT_CRAN"), "true")
#' # City blocks of Braga with the 2021 census variables (~2 MB download)
#' bgri <- get_censos("Braga")
#'
#' # Population density by subsecção
#' bgri$dens <- bgri$N_INDIVIDUOS / sf::st_area(bgri)
#'
#' # 2011 vintage, only the resident population variables
#' get_censos("Braga", year = 2011,
#'            variables = c("N_INDIVIDUOS_RESIDENT", "N_INDIVIDUOS_RESIDENT_H"))
#'
#' # Secção-level detail (native 2021 product, ~180 variables)
#' get_censos("Braga", level = "seccao")
#'
#' # A whole NUTS3, and the 1 km grid for the mainland
#' get_censos(region = "Cávado")
#' get_censos(region = "continente", level = "grid")
#'
#' # Just the data, no geometry
#' get_censos("Braga", geometry = FALSE)
#'
#' @seealso [pt_censos_vars], [GeoClient] (for `client`), [get_map()] for
#'   administrative boundaries.
#'
#' @export
get_censos <- function(municipio = NULL,
                       year = 2021,
                       level = "subseccao",
                       region = NULL,
                       freguesia = NULL,
                       variables = NULL,
                       geometry = TRUE,
                       crs = NULL,
                       client = NULL) {
  client <- client %||% GeoClient$new()
  censos_get(
    client,
    municipio = municipio, year = year, level = level, region = region,
    freguesia = freguesia, variables = variables, geometry = geometry,
    crs = crs
  )
}

# --- Orchestration -------------------------------------------------------------

#' @noRd
censos_get <- function(client, municipio = NULL, year = 2021,
                       level = "subseccao", region = NULL, freguesia = NULL,
                       variables = NULL, geometry = TRUE, crs = NULL) {
  year <- validate_censos_year(year)
  level <- validate_censos_level(level)
  validate_censos_scope_args(level, year, municipio, region, freguesia)

  product <- censos_product(level, year)
  scope <- censos_resolve_scope(product, year, municipio, freguesia, region)
  out_crs <- as.integer(crs %||% client$crs)

  cache_path <- censos_cache_path(client, product, year, level, scope, out_crs)
  out <- NULL
  if (!is.null(cache_path) && file.exists(cache_path)) {
    message(sprintf("Using cached: %s", sub("\\.rds$", "", basename(cache_path))))
    out <- readRDS(cache_path)
  }

  if (is.null(out)) {
    rows <- censos_manifest_rows(product, year, scope)
    # One manifest row can yield several layers (island groups), each with its
    # own CRS/schema, so tidy + reproject each layer before merging.
    parts <- unlist(lapply(seq_len(nrow(rows)), function(i) {
      gpkg <- censos_download(client, rows[i, ])
      lapply(censos_read(gpkg), function(layer) {
        sf::st_transform(censos_tidy(layer, product, year), out_crs)
      })
    }), recursive = FALSE)

    if (length(parts) > 1L) {
      common <- Reduce(intersect, lapply(parts, names))
      parts <- lapply(parts, function(x) x[, common, drop = FALSE])
    }
    out <- do.call(rbind, parts)
    rownames(out) <- NULL

    if (level == "seccao" && product == "bgri") {
      message("Dissolving subsec\u00e7\u00f5es to sec\u00e7\u00f5es (summing counts)...")
      out <- censos_dissolve_seccao(out)
    }

    if (!is.null(cache_path)) {
      dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
      saveRDS(out, cache_path)
    }
  }

  if (!is.null(scope$dtmnfr_filter)) {
    out <- censos_filter_dtmnfr(out, scope$dtmnfr_filter, year)
  }
  if (!is.null(variables)) {
    out <- censos_select_vars(out, variables, year, level)
  }
  if (!geometry) {
    out <- sf::st_drop_geometry(out)
  }
  out
}

# --- Validation ----------------------------------------------------------------

#' @noRd
validate_censos_year <- function(year) {
  year <- suppressWarnings(as.integer(year))
  if (length(year) != 1L || is.na(year) || !year %in% CENSOS_YEARS) {
    stop(
      sprintf("`year` must be one of: %s.", paste(CENSOS_YEARS, collapse = ", ")),
      call. = FALSE
    )
  }
  year
}

#' @noRd
validate_censos_level <- function(level) {
  if (!is.character(level) || length(level) != 1L) {
    stop("`level` must be a single character string.", call. = FALSE)
  }
  norm <- gsub(" ", "", pt_normalize(level))
  if (!norm %in% CENSOS_LEVELS) {
    stop(
      sprintf("Invalid level '%s'. Must be one of: %s.",
              level, paste(CENSOS_LEVELS, collapse = ", ")),
      call. = FALSE
    )
  }
  norm
}

#' @noRd
validate_censos_scope_args <- function(level, year, municipio, region, freguesia) {
  has_mun <- !is.null(municipio)
  has_reg <- !is.null(region)
  has_frg <- !is.null(freguesia)

  if (level == "grid") {
    if (year != 2021L) {
      stop("The 1 km grid is only available for the 2021 census.", call. = FALSE)
    }
    if (has_mun || has_frg) {
      stop(
        "level = \"grid\" is only available by `region` (cells are not tied to municipalities). Use region = \"portugal\", \"continente\", \"raa\", or \"ram\".",
        call. = FALSE
      )
    }
  }

  if (!has_mun && !has_reg && !has_frg) {
    stop(
      paste0(
        "No scope given. Pass one of:\n",
        "  municipio = \"Braga\"            (a municipality, ~1-3 MB)\n",
        "  freguesia = \"Gualtar (Braga)\"  (a freguesia)\n",
        "  region    = \"C\u00e1vado\"           (NUTS2/NUTS3, \"continente\", \"raa\", \"ram\", or \"portugal\")"
      ),
      call. = FALSE
    )
  }
  if (has_reg && (has_mun || has_frg)) {
    stop("`region` cannot be combined with `municipio`/`freguesia`.", call. = FALSE)
  }
}

# --- Scope resolution ------------------------------------------------------------

#' Map (level, year) to the manifest product to download.
#' @noRd
censos_product <- function(level, year) {
  switch(level,
    subseccao = "bgri",
    seccao    = if (year == 2021L) "seccoes" else "bgri",
    grid      = "grid"
  )
}

#' Resolve municipio/freguesia/region to manifest scope + optional row filter.
#'
#' Returns list(scope_type, scope_ids, dtmnfr_filter). scope_type/ids follow
#' the manifest vocabulary; dtmnfr_filter is a character vector of candidate
#' freguesia codes to keep, or NULL.
#' @noRd
censos_resolve_scope <- function(product, year, municipio, freguesia, region) {
  if (!is.null(region)) {
    return(censos_resolve_region(product, year, region))
  }

  dtmnfr_filter <- NULL
  dtmns <- character(0)

  if (!is.null(freguesia)) {
    codes <- censos_resolve_freguesia(freguesia, municipio)
    dtmnfr_filter <- codes
    dtmns <- unique(substr(codes, 1L, 4L))
  } else {
    dtmns <- pt_match(municipio, level = "municipio", quiet = TRUE)
    if (anyNA(dtmns)) {
      bad <- municipio[is.na(dtmns)]
      stop(
        sprintf(
          "Could not resolve municipio(s): %s. Ambiguous names take a qualifier, e.g. \"Lagoa (A\u00e7ores)\"; see pt_match().",
          paste(shQuote(bad), collapse = ", ")
        ),
        call. = FALSE
      )
    }
    dtmns <- unique(dtmns)
  }

  list(scope_type = "municipio", scope_ids = dtmns, dtmnfr_filter = dtmnfr_filter)
}

#' Freguesia names/codes -> candidate DTMNFR codes for filtering.
#'
#' Digit inputs are treated as (possibly historic) DTMNFR codes and passed
#' through padded; names resolve against the current registry, expanded with
#' their 2013-era code (the vocabulary of the 2021 census).
#' @noRd
censos_resolve_freguesia <- function(freguesia, municipio = NULL) {
  x <- trimws(as.character(freguesia))
  is_code <- grepl("^[0-9]{4,6}$", x)

  codes <- character(0)
  if (any(is_code)) {
    codes <- pt_pad_code(x[is_code], "freguesia")
  }

  if (any(!is_code)) {
    resolved <- pt_match(
      x[!is_code], level = "freguesia",
      context = municipio, quiet = TRUE
    )
    if (anyNA(resolved)) {
      bad <- x[!is_code][is.na(resolved)]
      stop(
        sprintf(
          "Could not resolve freguesia(s): %s. Pass `municipio` for context, use a qualifier (\"Pinheiro (Guimar\u00e3es)\"), or pass DTMNFR codes (historic codes are accepted for older censuses).",
          paste(shQuote(bad), collapse = ", ")
        ),
        call. = FALSE
      )
    }
    codes <- c(codes, resolved)
  }

  # Expand with the 2013-era codes (the 2021 census vocabulary).
  link <- atom_link(current_admin_vintage(), "2013", "freguesia")
  extra <- link$to[link$from %in% codes]
  # ...and with the other form of a code that has an alias, since the census
  # files and INE's code lists disagree on it (see FREGUESIA_CODE_ALIASES).
  a <- FREGUESIA_CODE_ALIASES
  alias <- c(a$code[a$alias %in% codes], a$alias[a$code %in% codes])
  unique(c(codes, extra, alias))
}

#' Region string -> manifest scope. Census files follow NUTS 2013.
#' @noRd
censos_resolve_region <- function(product, year, region) {
  if (!is.character(region) || length(region) != 1L) {
    stop("`region` must be a single character string.", call. = FALSE)
  }
  r <- pt_normalize(region)

  scope <- NULL
  if (r %in% c("portugal", "pt")) {
    scope <- list(scope_type = "portugal", scope_ids = "PT")
  } else if (r %in% c("continente", "cont", "mainland")) {
    scope <- list(scope_type = "region", scope_ids = "CONT")
  } else if (r %in% c("raa", "r a a", "acores", "azores",
                      "regiao autonoma dos acores")) {
    scope <- list(scope_type = "region", scope_ids = "RAA")
  } else if (r %in% c("ram", "r a m", "madeira", "regiao autonoma da madeira")) {
    scope <- list(scope_type = "region", scope_ids = "MAD")
  }

  if (is.null(scope)) {
    scope <- censos_resolve_nuts(year, region)
  }

  # Grid files exist only at portugal/region scope
  if (product == "grid" && !scope$scope_type %in% c("portugal", "region")) {
    stop(
      "level = \"grid\" is only distributed for \"portugal\", \"continente\", \"raa\", and \"ram\".",
      call. = FALSE
    )
  }

  scope
}

#' NUTS2/NUTS3 name or code -> manifest nuts2/nuts3 scope (NUTS 2013 based).
#' The id vocabulary comes from the BGRI rows (the NUTS geography is shared
#' by all products; the grid simply has no NUTS-scoped files).
#' @noRd
censos_resolve_nuts <- function(year, region) {
  # Both revisions side by side, because the FILES speak NUTS 2013 while a
  # caller may well name a region by its 2024 name.
  n13 <- pt_lookup("municipio", nuts_vintage = "2013")
  n24 <- pt_lookup("municipio", nuts_vintage = "2024")
  codes <- data.frame(
    nuts2_2013 = n13$nuts2, nuts2_cod_2013 = n13$nuts2_cod,
    nuts3_2013 = n13$nuts3, nuts3_cod_2013 = n13$nuts3_cod,
    nuts2 = n24$nuts2[match(n13$dtmn, n24$dtmn)],
    nuts3 = n24$nuts3[match(n13$dtmn, n24$dtmn)],
    stringsAsFactors = FALSE
  )
  n3_ids <- unique(censos_manifest$scope_id[
    censos_manifest$product == "bgri" & censos_manifest$year == year &
      censos_manifest$scope_type == "nuts3"
  ])

  # Direct code forms: "16D", "PT16D", "pt16d"
  up <- toupper(gsub("[^A-Za-z0-9]", "", region))
  bare <- sub("^PT", "", up)
  if (bare %in% n3_ids) {
    return(list(scope_type = "nuts3", scope_ids = bare))
  }
  if (up %in% names(CENSOS_NUTS2_IDS) || paste0("PT", bare) %in% names(CENSOS_NUTS2_IDS)) {
    id <- CENSOS_NUTS2_IDS[[if (up %in% names(CENSOS_NUTS2_IDS)) up else paste0("PT", bare)]]
    return(list(scope_type = "nuts2", scope_ids = id))
  }

  r <- pt_normalize(region)
  match_name <- function(name_col, code_col) {
    hit <- unique(codes[[code_col]][pt_normalize(codes[[name_col]]) == r])
    hit[!is.na(hit)]
  }

  # NUTS 2013 names first (the vocabulary of the files), then NUTS 2024
  # names when they map to a single 2013 unit.
  for (cols in list(c("nuts2_2013", "nuts2_cod_2013"),
                    c("nuts3_2013", "nuts3_cod_2013"),
                    c("nuts2", "nuts2_cod_2013"),
                    c("nuts3", "nuts3_cod_2013"))) {
    hit <- match_name(cols[1L], cols[2L])
    if (length(hit) == 1L) {
      if (hit %in% c("PT20", "PT200")) {
        return(list(scope_type = "region", scope_ids = "RAA"))
      }
      if (hit %in% c("PT30", "PT300")) {
        return(list(scope_type = "region", scope_ids = "MAD"))
      }
      if (hit %in% names(CENSOS_NUTS2_IDS)) {
        return(list(scope_type = "nuts2", scope_ids = CENSOS_NUTS2_IDS[[hit]]))
      }
      bare <- sub("^PT", "", hit)
      if (bare %in% n3_ids) {
        return(list(scope_type = "nuts3", scope_ids = bare))
      }
    }
    if (length(hit) > 1L) {
      stop(
        sprintf(
          "Region '%s' does not map to a single NUTS 2013 unit (census files follow NUTS 2013). Matches: %s. Use a NUTS 2013 name or code, or a broader region.",
          region, paste(hit, collapse = ", ")
        ),
        call. = FALSE
      )
    }
  }

  stop(
    sprintf(
      "Unknown region '%s'. Use \"portugal\", \"continente\", \"raa\", \"ram\", a NUTS2/NUTS3 name, or a NUTS 2013 code (e.g. \"16D\").",
      region
    ),
    call. = FALSE
  )
}

# --- Manifest lookup and download ---------------------------------------------

#' Manifest rows to download for a resolved scope.
#'
#' A "portugal" request for gpkg products is served as the union of the
#' three region files (their per-region CRS are documented; the monolithic
#' portugal zip is not smaller and has an unversioned layout). The grid has
#' a true country-wide file.
#' @noRd
censos_manifest_rows <- function(product, year, scope) {
  m <- censos_manifest[censos_manifest$product == product &
                         censos_manifest$year == year, ]

  if (scope$scope_type == "portugal" && product != "grid") {
    rows <- m[m$scope_type == "region", ]
  } else {
    rows <- m[m$scope_type == scope$scope_type &
                m$scope_id %in% scope$scope_ids, ]
  }

  missing <- setdiff(scope$scope_ids, rows$scope_id)
  if (nrow(rows) == 0L ||
      (scope$scope_type != "portugal" && length(missing) > 0L)) {
    stop(
      sprintf("No INE census file for %s %d (%s: %s).",
              product, year, scope$scope_type,
              paste(scope$scope_ids, collapse = ", ")),
      call. = FALSE
    )
  }
  rows
}

#' Download one manifest row's zip and return the path of its GeoPackage.
#' Stops with a download error if the download fails or holds no GeoPackage.
#' @noRd
censos_download <- function(client, row) {
  raw_dir <- file.path(client$cache_dir, "raw", "censos", row$year)
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)

  zip_path <- file.path(raw_dir, basename(row$url))
  gpkg_guess <- sub("\\.zip$", ".gpkg", zip_path)
  if (file.exists(gpkg_guess)) return(gpkg_guess)

  if (!file.exists(zip_path)) {
    message(sprintf("Downloading Censos %d %s (%s)...",
                    row$year, row$scope_id, basename(row$url)))
    req <- httr2::request(paste0(CENSOS_BASE_URL, "/", row$url))
    req <- httr2::req_timeout(req, 600)
    req <- httr2::req_user_agent(req, "geopt R package")
    perform_request(req, path = zip_path)
  }

  # A file that isn't a zip (e.g. an error page saved in its place) lists nothing.
  members <- tryCatch(utils::unzip(zip_path, list = TRUE)$Name,
                      error = function(e) character(0))
  gpkg <- members[grepl("\\.gpkg$", members)]
  if (length(gpkg) != 1L) {
    # Remove it so the next call downloads again.
    file.remove(zip_path)
    stop_download(sprintf(
      "Expected one GeoPackage in %s, found %d. The file at %s/%s may have changed.",
      basename(zip_path), length(gpkg), CENSOS_BASE_URL, row$url
    ))
  }
  utils::unzip(zip_path, files = gpkg, exdir = raw_dir, overwrite = TRUE)
  file.remove(zip_path)

  # Normalize to <zipname>.gpkg so the cache short-circuit above always hits,
  # even if INE names the member differently from the zip.
  extracted <- file.path(raw_dir, gpkg)
  if (!identical(normalizePath(extracted, mustWork = FALSE),
                 normalizePath(gpkg_guess, mustWork = FALSE))) {
    file.rename(extracted, gpkg_guess)
  }
  gpkg_guess
}

#' Read every layer of a censos GeoPackage as a list of sf objects.
#'
#' Most files have a single layer, but the Açores region/country files split
#' the archipelago into island-group layers (e.g. `BGRI11_AC25` /
#' `BGRI11_AC26`) with different CRS and slightly different schemas. Callers
#' tidy, reproject, and merge the pieces on their common columns.
#'
#' A few INE polygons are curved (MULTISURFACE: 8 of Braga's 2021 subsecções),
#' which s2 can't read, so `sf::st_area()` and the like fail on them. Such a
#' layer is read again with GDAL converting every feature to MULTIPOLYGON; the
#' areas then match INE's own `SHAPE_Area`.
#' @noRd
censos_read <- function(gpkg_path) {
  layers <- sf::st_layers(gpkg_path)$name
  if (length(layers) == 0L) {
    stop(sprintf("No layers found in %s.", basename(gpkg_path)), call. = FALSE)
  }
  curved <- c("CURVEPOLYGON", "MULTISURFACE")
  lapply(layers, function(lyr) {
    x <- sf::st_read(gpkg_path, layer = lyr, quiet = TRUE)
    if (any(sf::st_geometry_type(x) %in% curved)) {
      x <- sf::st_read(gpkg_path, layer = lyr, quiet = TRUE, type = 6L)
    }
    x
  })
}

# --- Tidying --------------------------------------------------------------------

#' Drop INE artifacts, add year-stable identifier columns, and normalize the
#' geometry column name (files vary between "Shape", "geom", ...).
#' @noRd
censos_tidy <- function(x, product, year) {
  attrs <- sf::st_drop_geometry(x)
  lc <- tolower(names(attrs))
  drop <- lc %in% CENSOS_DROP_COLS | grepl(CENSOS_DROP_PATTERN, lc)
  attrs <- attrs[, !drop, drop = FALSE]

  spec <- CENSOS_ID_SPECS[[paste0(product, "_", year)]]
  ids <- list(censos_year = rep(year, nrow(attrs)))
  for (tidy_name in names(spec)) {
    src <- spec[[tidy_name]]
    if (!all(src %in% names(attrs))) next
    val <- if (length(src) == 2L) {
      paste0(attrs[[src[1L]]], attrs[[src[2L]]])
    } else {
      attrs[[src]]
    }
    ids[[tidy_name]] <- as.character(val)
  }

  out <- cbind(
    as.data.frame(ids, stringsAsFactors = FALSE, check.names = FALSE),
    attrs
  )
  sf::st_sf(out, geometry = sf::st_geometry(x))
}

#' Dissolve subsecções to secções: union geometry, sum the (numeric) census
#' counts, keep identifier columns that are constant within every secção.
#' @noRd
censos_dissolve_seccao <- function(x) {
  if (!all(c("dtmnfr", "seccao") %in% names(x))) {
    stop("Cannot dissolve to sec\u00e7\u00e3o: identifier columns missing.", call. = FALSE)
  }
  key <- paste0(x$dtmnfr, "_", x$seccao)
  groups <- split(seq_len(nrow(x)), key)
  groups <- groups[unique(key)]  # preserve first-occurrence order

  attrs <- sf::st_drop_geometry(x)
  is_num <- vapply(attrs, is.numeric, logical(1L))
  num_cols <- names(attrs)[is_num]
  cand_cols <- setdiff(names(attrs)[!is_num],
                       c("bgri", "subseccao", "lugar", "lugar_nome"))
  constant_cols <- cand_cols[vapply(cand_cols, function(col) {
    all(vapply(groups, function(idx) {
      length(unique(attrs[[col]][idx])) == 1L
    }, logical(1L)))
  }, logical(1L))]

  geom <- sf::st_geometry(x)
  rows <- lapply(groups, function(idx) {
    row <- attrs[idx[1L], constant_cols, drop = FALSE]
    counts <- lapply(attrs[idx, num_cols, drop = FALSE], sum, na.rm = TRUE)
    row <- cbind(row, as.data.frame(counts, check.names = FALSE),
                 n_subseccoes = length(idx))
    sf::st_sf(row, geometry = sf::st_union(geom[idx]))
  })

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# --- Post-processing --------------------------------------------------------------

#' @noRd
censos_filter_dtmnfr <- function(x, candidates, year) {
  keep <- x$dtmnfr %in% candidates
  if (!any(keep)) {
    stop(
      sprintf(
        paste0(
          "No rows match the requested freguesia(s) in the %d census. ",
          "Freguesia codes are vintage-specific%s. Pass the %d-era DTMNFR codes directly."
        ),
        year,
        if (year <= 2011L) " and pre-2013 censuses use the pre-aggregation map" else "",
        year
      ),
      call. = FALSE
    )
  }
  x[keep, , drop = FALSE]
}

#' @noRd
censos_select_vars <- function(x, variables, year, level) {
  id_cols <- intersect(
    c("censos_year", "bgri", "dtmn", "dtmnfr", "seccao", "subseccao",
      "lugar", "lugar_nome", "grd_id", "n_subseccoes"),
    names(x)
  )
  pool <- setdiff(names(x), c(id_cols, attr(x, "sf_column")))
  hit <- pool[match(toupper(variables), toupper(pool))]

  if (anyNA(hit)) {
    bad <- variables[is.na(hit)]
    stop(
      sprintf(
        "Unknown variable(s) for the %d census at level \"%s\": %s.\nSee pt_censos_vars[pt_censos_vars$year == %d & pt_censos_vars$level == \"%s\", ].",
        year, level, paste(shQuote(bad), collapse = ", "), year, level
      ),
      call. = FALSE
    )
  }
  x[, c(id_cols, hit), drop = FALSE]
}

# --- Caching -----------------------------------------------------------------------

#' Path for the processed cache entry, or NULL when caching is off.
#' @noRd
censos_cache_path <- function(client, product, year, level, scope, crs) {
  if (!client$use_cache) return(NULL)
  ids <- paste(sort(scope$scope_ids), collapse = "-")
  if (nchar(ids) > 40L) {
    ids <- digest::digest(ids, algo = "xxhash64")
  }
  file.path(
    client$cache_dir, "processed",
    sprintf("censos_%s_%d_%s_%s_%s_%d.rds",
            product, year, level, scope$scope_type, ids, crs)
  )
}
