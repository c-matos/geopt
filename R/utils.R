# --- Null coalescing operator ------------------------------------------------

`%||%` <- function(x, y) if (is.null(x)) y else x

# --- Constants ---------------------------------------------------------------

VALID_REGIONS <- c("continente", "raa", "ram")

VALID_LEVELS <- c("freguesia", "municipio", "distrito", "nuts1", "nuts2", "nuts3")

# Extra map levels derived from pt_health_codes (not CAOP layers, so valid
# for get_map()/plot_pt() but not for GeoClient$get_caop()). "uls"/"reg_saude"
# are the 2024 health reform; "aces" is the organization it superseded. The
# *_municipio levels merge the units that share a municipio, for data by
# municipio.
HEALTH_LEVELS <- c("uls", "reg_saude", "aces", "uls_municipio", "aces_municipio")

VALID_MAP_LEVELS <- c(VALID_LEVELS, HEALTH_LEVELS)

CAOP_BASE_URL <- "https://geo2.dgterritorio.gov.pt/caop"

DEFAULT_CRS <- 4326L

SIMPLIFY_PRESETS <- list(
  full   = 1,
  high   = 0.5,
  medium = 0.1,
  low    = 0.01,
  very_low = 0.005
)

REGION_URL_MAP <- c(
  continente = "Continente",
  raa        = "RAA",
  ram        = "RAM"
)

# Patterns to identify which gpkg files belong to which region.
# RAA extracts into two files (different CRS per island group).
REGION_GPKG_PATTERNS <- list(
  continente = "(?i)continente",
  raa = "(?i)(acores|a\u00e7ores|arqacores|raa)",
  ram = "(?i)(madeira|arqmadeira|ram_)"
)

# Patterns to match layer names for each admin level.
# Ordered: most specific first, then broader fallbacks.
LEVEL_LAYER_PATTERNS <- list(
  freguesia = "(?i)freg",
  municipio = "(?i)(munic|concel)",
  distrito  = "(?i)distr",
  nuts1     = "(?i)nuts.?1$",
  nuts2     = "(?i)nuts.?2$",
  nuts3     = "(?i)nuts.?3$"
)

# --- Validation helpers ------------------------------------------------------

#' @noRd
check_suggested_pkg <- function(pkg, reason = NULL) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    msg <- sprintf("Package '%s' is required", pkg)
    if (!is.null(reason)) msg <- paste0(msg, " ", reason)
    msg <- paste0(msg, ". Install it with: install.packages('", pkg, "')")
    stop(msg, call. = FALSE)
  }
}

#' @noRd
validate_region <- function(region) {
  region <- tolower(region)
  if (!region %in% VALID_REGIONS) {
    stop(
      sprintf("Invalid region '%s'. Must be one of: %s", region, paste(VALID_REGIONS, collapse = ", ")),
      call. = FALSE
    )
  }
  region
}

#' @noRd
validate_level <- function(level) {
  level <- tolower(level)
  if (!level %in% VALID_LEVELS) {
    stop(
      sprintf("Invalid level '%s'. Must be one of: %s", level, paste(VALID_LEVELS, collapse = ", ")),
      call. = FALSE
    )
  }
  level
}

#' @noRd
validate_map_level <- function(level) {
  level <- tolower(level)
  if (!level %in% VALID_MAP_LEVELS) {
    stop(
      sprintf("Invalid level '%s'. Must be one of: %s",
              level, paste(VALID_MAP_LEVELS, collapse = ", ")),
      call. = FALSE
    )
  }
  level
}

#' @noRd
validate_detail <- function(detail) {
  detail <- tolower(detail)
  if (!detail %in% names(SIMPLIFY_PRESETS)) {
    stop(
      sprintf("Invalid detail '%s'. Must be one of: %s", detail, paste(names(SIMPLIFY_PRESETS), collapse = ", ")),
      call. = FALSE
    )
  }
  detail
}

# --- URL and year resolution -------------------------------------------------

#' @noRd
build_caop_url <- function(region, year, format = "gpkg") {
  sprintf("%s/CAOP_%s_%s-%s.zip", CAOP_BASE_URL, REGION_URL_MAP[region], year, format)
}

#' @noRd
url_exists <- function(url, timeout = 15) {
  tryCatch({
    req <- httr2::request(url)
    req <- httr2::req_method(req, "HEAD")
    req <- httr2::req_timeout(req, timeout)
    req <- httr2::req_error(req, is_error = function(resp) FALSE)
    resp <- httr2::req_perform(req)
    httr2::resp_status(resp) < 400L
  }, error = function(e) NA)
}

#' Resolve the latest CAOP year published for a region.
#'
#' Stops with a download error when DGT's server can't be reached or none of
#' the last three years is published (the download address has changed).
#' @noRd
resolve_year <- function(region, year = NULL) {
  if (!is.null(year)) return(as.integer(year))

  current_year <- as.integer(format(Sys.Date(), "%Y"))
  years <- current_year:(current_year - 2L)

  for (y in years) {
    available <- url_exists(build_caop_url(region, y))
    if (is.na(available)) {
      stop_download(sprintf(
        "Could not reach %s to find the latest CAOP year. Check your internet connection, or try again later.",
        httr2::url_parse(CAOP_BASE_URL)$hostname
      ))
    }
    if (available) return(y)
  }

  stop_download(sprintf(
    "Could not find CAOP data for '%s' for %d to %d at %s. The address may have changed; pass `year` to choose a year.",
    region, min(years), max(years), CAOP_BASE_URL
  ))
}

# --- Download errors -----------------------------------------------------------
#
# A failed download stops with an error saying which server or file failed and
# why, instead of httr2's raw error. Its class, "geopt_download_error", lets a
# script catch download failures alone. (CRAN's policy on internet resources is
# met by never downloading during R CMD check: examples, tests and vignettes
# are guarded.)

#' Stop with a download error.
#' @noRd
stop_download <- function(message) {
  stop(structure(
    class = c("geopt_download_error", "error", "condition"),
    list(message = message, call = NULL)
  ))
}

#' Perform a request, stopping with a download error if it fails.
#'
#' @param req An httr2 request.
#' @param path Optional file to save the body to; removed if the request fails.
#' @return The httr2 response.
#' @noRd
perform_request <- function(req, path = NULL) {
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform(req, path = path), error = function(e) e)
  if (inherits(resp, "httr2_response") && httr2::resp_status(resp) < 400L) {
    return(resp)
  }
  if (!is.null(path) && file.exists(path)) file.remove(path)
  stop_download(download_failure_message(req$url, resp))
}

#' Explain a failed request: an error status from the server, or the condition
#' raised when it couldn't be reached.
#' @noRd
download_failure_message <- function(url, problem) {
  if (inherits(problem, "httr2_http")) problem <- problem$resp
  if (inherits(problem, "httr2_response")) {
    return(sprintf(
      "Could not download %s: the server answered %d %s. The data may have moved, or the service may be down; try again later.",
      url, httr2::resp_status(problem), httr2::resp_status_desc(problem)
    ))
  }
  cause <- if (inherits(problem$parent, "condition")) problem$parent else problem
  cause <- gsub("[[:space:]]+", " ", conditionMessage(cause))
  sprintf(
    "Could not reach %s: %s. Check your internet connection, or try again later.",
    httr2::url_parse(url)$hostname, sub("[.[:space:]]+$", "", cause)
  )
}

# --- Raw GeoPackage file discovery -------------------------------------------

#' Find extracted GeoPackage files for a given region and year.
#' RAA yields one file per CRS zone (CAOP 2022 has three: Ocidental, Central and
#' Oriental), all others yield one.
#' @noRd
find_region_gpkgs <- function(raw_dir, region, year) {
  all_gpkgs <- list.files(raw_dir, pattern = "\\.gpkg$",
                          full.names = TRUE, recursive = TRUE)
  if (length(all_gpkgs) == 0L) return(character(0))

  year_gpkgs <- grep(as.character(year), all_gpkgs, value = TRUE)
  if (length(year_gpkgs) == 0L) return(character(0))

  pattern <- REGION_GPKG_PATTERNS[[region]]
  grep(pattern, year_gpkgs, value = TRUE, perl = TRUE)
}

# --- GeoPackage layer detection ----------------------------------------------

#' Find the layer name for a given admin level inside a GeoPackage.
#' Returns a string (direct layer name) or a list with $layer and $dissolve_by
#' if the level must be derived by dissolving a finer layer.
#' @noRd
find_gpkg_layer <- function(gpkg_path, level) {
  layers <- sf::st_layers(gpkg_path)$name

  if (length(layers) == 0L) {
    stop("No layers found in ", basename(gpkg_path), call. = FALSE)
  }

  match_by_name <- function(lvl) {
    pattern <- LEVEL_LAYER_PATTERNS[[lvl]]
    if (is.null(pattern)) return(NULL)
    matched <- grep(pattern, layers, value = TRUE, perl = TRUE)
    if (length(matched) > 0L) matched[1L] else NULL
  }

  # Try direct match
  result <- match_by_name(level)
  if (!is.null(result)) return(result)

  # For NUTS levels without a dedicated layer, dissolve from municipio
  if (level %in% c("nuts1", "nuts2", "nuts3")) {
    for (base_level in c("municipio", "freguesia")) {
      base_result <- match_by_name(base_level)
      if (!is.null(base_result)) {
        return(list(layer = base_result, dissolve_by = level))
      }
    }
  }

  # Last resort: single usable layer
  usable <- setdiff(layers, c("layer_styles", "inf_fonte_troco"))
  if (length(usable) == 1L) return(usable[1L])

  stop(
    sprintf(
      "Could not find layer for '%s' in %s.\nAvailable: %s",
      level, basename(gpkg_path), paste(layers, collapse = ", ")
    ),
    call. = FALSE
  )
}

# --- Dissolve helpers --------------------------------------------------------

#' @noRd
find_dissolve_column <- function(sf_obj, level) {
  patterns <- list(
    nuts1 = "(?i)^nuts.?[_]?1$",
    nuts2 = "(?i)^nuts.?[_]?2$",
    nuts3 = "(?i)^nuts.?[_]?3$"
  )

  pattern <- patterns[[level]]
  if (is.null(pattern)) {
    stop(sprintf("No dissolve pattern for level '%s'", level), call. = FALSE)
  }

  cols <- setdiff(names(sf_obj), attr(sf_obj, "sf_column"))
  matched <- grep(pattern, cols, value = TRUE, perl = TRUE)

  if (length(matched) == 0L) {
    broad <- sprintf("(?i)%s", gsub("[\\^\\$]", "", pattern))
    matched <- grep(broad, cols, value = TRUE, perl = TRUE)
  }

  if (length(matched) == 0L) {
    stop(
      sprintf(
        "Could not find column for '%s'. Available: %s",
        level, paste(cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  matched[1L]
}

#' @noRd
dissolve_by <- function(sf_obj, group_col) {
  vals <- sf_obj[[group_col]]
  # For município, add nuts3 to disambiguate same-named features
  # (e.g. two "Lagoa" in Faro and São Miguel).
  if (group_col == "municipio" && "nuts3" %in% names(sf_obj)) {
    vals <- paste0(vals, "|", sf_obj[["nuts3"]])
  }

  groups <- unique(vals[!is.na(vals)])
  results <- lapply(groups, function(g) {
    sub <- sf_obj[vals == g & !is.na(vals), , drop = FALSE]
    geom <- sf::st_union(sub)
    attrs <- sf::st_drop_geometry(sub[1L, , drop = FALSE])
    sf::st_sf(attrs, geometry = geom)
  })

  do.call(rbind, results)
}

# --- OGC API: constants ------------------------------------------------------

OGC_BASE_URL <- "https://ogcapi.dgterritorio.gov.pt"

OGC_DEFAULT_LIMIT <- 1000L

# Hardcoded collection registry. `type` distinguishes feature vs coverage
# (coverages are rejected, with a message on how to read them otherwise).
# `requires_filter = TRUE` blocks unfiltered pulls for collections that are
# too large to fetch whole (COS, cadastro).
OGC_COLLECTIONS <- list(
  freguesias  = list(type = "feature",  requires_filter = FALSE),
  municipios  = list(type = "feature",  requires_filter = FALSE),
  distritos   = list(type = "feature",  requires_filter = FALSE),
  nuts1       = list(type = "feature",  requires_filter = FALSE),
  nuts2       = list(type = "feature",  requires_filter = FALSE),
  nuts3       = list(type = "feature",  requires_filter = FALSE),
  admin       = list(type = "feature",  requires_filter = FALSE),
  trocos      = list(type = "feature",  requires_filter = FALSE),
  cos2018v3   = list(type = "feature",  requires_filter = TRUE),
  cos2023v1   = list(type = "feature",  requires_filter = TRUE),
  cadastro    = list(type = "feature",  requires_filter = TRUE),
  `ortos-rgb` = list(type = "coverage", requires_filter = NA),
  `ortos-irg` = list(type = "coverage", requires_filter = NA),
  cosc2018    = list(type = "coverage", requires_filter = NA),
  cosc2020    = list(type = "coverage", requires_filter = NA),
  cosc2021    = list(type = "coverage", requires_filter = NA),
  cosc2022    = list(type = "coverage", requires_filter = NA)
)

# --- OGC API: validation -----------------------------------------------------

#' @noRd
validate_ogc_collection <- function(collection) {
  if (!is.character(collection) || length(collection) != 1L) {
    stop("`collection` must be a single character string.", call. = FALSE)
  }
  meta <- OGC_COLLECTIONS[[collection]]
  if (is.null(meta)) {
    known <- paste(names(OGC_COLLECTIONS), collapse = ", ")
    stop(
      sprintf(
        "Unknown OGC collection '%s'.\nKnown collections: %s\nUse client$list_ogc_collections() to see what the server reports live.",
        collection, known
      ),
      call. = FALSE
    )
  }
  if (identical(meta$type, "coverage")) {
    stop(
      sprintf(
        "Collection '%s' is a coverage (raster). Coverage support is not yet implemented in geopt. Use a feature collection or fetch the raster via sf::gdal_utils() / terra directly.",
        collection
      ),
      call. = FALSE
    )
  }
  meta
}

#' @noRd
validate_bbox <- function(bbox) {
  if (is.null(bbox)) return(NULL)
  if (inherits(bbox, "bbox")) bbox <- as.numeric(bbox)
  if (!is.numeric(bbox) || length(bbox) != 4L || anyNA(bbox)) {
    stop("`bbox` must be a numeric vector of length 4: c(xmin, ymin, xmax, ymax).", call. = FALSE)
  }
  if (bbox[1] >= bbox[3] || bbox[2] >= bbox[4]) {
    stop("`bbox` must satisfy xmin < xmax and ymin < ymax.", call. = FALSE)
  }
  bbox
}

# --- OGC API: URLs and query strings -----------------------------------------

#' @noRd
build_ogc_items_url <- function(collection) {
  sprintf("%s/collections/%s/items", OGC_BASE_URL, collection)
}

#' @noRd
ogc_crs_uri <- function(epsg) {
  # OGC API expects a URI form for the `crs` parameter.
  # http://www.opengis.net/def/crs/EPSG/0/<code> is the canonical form.
  sprintf("http://www.opengis.net/def/crs/EPSG/0/%d", as.integer(epsg))
}

#' Build the query parameter list for an OGC API Features request.
#'
#' Returns a named list; pass to httr2 via `req_url_query(!!!params)`.
#' Server-side filtering: bbox + bbox-crs + crs + limit + filter (CQL2-Text)
#' + arbitrary `properties` (passed through as `name=value` query params,
#' which pygeoapi treats as equality filters on attribute columns).
#' @noRd
build_ogc_query <- function(bbox = NULL, bbox_crs = 4326L, crs = NULL,
                            properties = NULL, cql_filter = NULL,
                            limit = OGC_DEFAULT_LIMIT) {
  params <- list()

  if (!is.null(bbox)) {
    params$bbox <- paste(bbox, collapse = ",")
    # bbox-crs only needs to be set when not 4326/CRS84
    if (!is.null(bbox_crs) && as.integer(bbox_crs) != 4326L) {
      params[["bbox-crs"]] <- ogc_crs_uri(bbox_crs)
    }
  }

  if (!is.null(crs)) {
    params$crs <- ogc_crs_uri(crs)
  }

  if (!is.null(cql_filter)) {
    if (!is.character(cql_filter) || length(cql_filter) != 1L) {
      stop("`cql_filter` must be a single CQL-Text string.", call. = FALSE)
    }
    params$filter <- cql_filter
    # DGT's pygeoapi accepts `cql-text` (CQL1), not `cql2-text`. Verified
    # empirically: cql2-text returns HTTP 400 "Invalid filter language".
    params[["filter-lang"]] <- "cql-text"
  }

  if (!is.null(properties)) {
    if (!is.list(properties) || is.null(names(properties)) || any(names(properties) == "")) {
      stop("`properties` must be a named list of equality filters.", call. = FALSE)
    }
    # Equality filters on attribute columns are supported as plain query params
    # (e.g. ?distrito=Lisboa) by the DGT pygeoapi backend.
    for (nm in names(properties)) {
      v <- properties[[nm]]
      if (length(v) != 1L) {
        stop(sprintf("`properties$%s` must be length 1 (use cql_filter for IN/OR).", nm),
             call. = FALSE)
      }
      params[[nm]] <- as.character(v)
    }
  }

  params$limit <- as.integer(limit)
  params$f     <- "json"
  params
}

#' Hash an OGC request's params to derive a stable cache key.
#' @noRd
ogc_cache_key <- function(collection, params, crs) {
  # Drop the `f` parameter from the hash (always json here).
  hash_in <- params
  hash_in$f <- NULL
  hash_in <- hash_in[order(names(hash_in))]
  digest_str <- digest::digest(list(collection = collection, params = hash_in, crs = crs),
                               algo = "xxhash64")
  sprintf("ogc_%s_%s.rds", collection, digest_str)
}

# --- OGC API: pagination and parsing -----------------------------------------

#' Walk OGC API `rel="next"` links and accumulate features.
#'
#' Returns a single sf object, or NULL if zero features came back. A failed
#' request, or a page that can't be read, stops with a download error.
#' Uses httr2::req_perform_iterative() (httr2 >= 1.0.0).
#' @noRd
ogc_fetch_features <- function(url, params, max_features = Inf,
                               user_agent = "geopt R package") {
  req <- httr2::request(url)
  req <- httr2::req_url_query(req, !!!params)
  req <- httr2::req_user_agent(req, user_agent)
  req <- httr2::req_timeout(req, 300)
  req <- httr2::req_retry(req, max_tries = 3L)

  next_req <- function(resp, req) {
    body <- httr2::resp_body_json(resp, simplifyVector = FALSE)
    links <- body$links %||% list()
    nxt <- NULL
    for (lk in links) {
      if (identical(lk$rel, "next") && !is.null(lk$href)) {
        nxt <- lk$href
        break
      }
    }
    if (is.null(nxt)) return(NULL)
    httr2::request(nxt) |>
      httr2::req_user_agent(user_agent) |>
      httr2::req_timeout(300) |>
      httr2::req_retry(max_tries = 3L)
  }

  unreadable <- function(e) {
    stop_download(sprintf(
      "Could not read the response from %s: %s. The service may have changed.",
      httr2::url_parse(url)$hostname, conditionMessage(e)
    ))
  }

  # on_error = "return" hands back HTTP and connection failures as conditions;
  # anything else (e.g. a page that isn't JSON) is caught around the call.
  resps <- tryCatch(
    httr2::req_perform_iterative(
      req,
      next_req = next_req,
      max_reqs = if (is.finite(max_features)) {
        # Roughly cap requests so we don't iterate forever.
        ceiling(max_features / max(params$limit %||% OGC_DEFAULT_LIMIT, 1L)) + 1L
      } else {
        Inf
      },
      on_error = "return"
    ),
    httr2_error = function(e) list(e),
    error = unreadable
  )
  failed <- httr2::resps_failures(resps)
  if (length(failed) > 0L) {
    stop_download(download_failure_message(url, failed[[1L]]))
  }

  feature_count <- 0L
  page_sf <- vector("list", length(resps))

  for (i in seq_along(resps)) {
    body <- httr2::resp_body_string(resps[[i]])
    # Empty FeatureCollection -> skip; geojsonsf would error otherwise.
    if (nchar(body) == 0L) next
    page <- tryCatch(geojsonsf::geojson_sf(body), error = unreadable)
    if (nrow(page) == 0L) next
    page_sf[[i]] <- page
    feature_count <- feature_count + nrow(page)
    if (feature_count >= max_features) {
      page_sf <- page_sf[seq_len(i)]
      break
    }
  }

  page_sf <- Filter(Negate(is.null), page_sf)
  if (length(page_sf) == 0L) return(NULL)

  out <- if (length(page_sf) == 1L) page_sf[[1L]] else do.call(rbind, page_sf)

  if (is.finite(max_features) && nrow(out) > max_features) {
    out <- out[seq_len(max_features), , drop = FALSE]
  }
  out
}
