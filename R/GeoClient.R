#' GeoClient
#'
#' R6 class for downloading, processing, and caching Portuguese geographic
#' boundaries from CAOP (Carta Administrativa Oficial de Portugal), and for
#' filtered queries to DGT's OGC API. [get_censos()] and [get_map()] use one for
#' their downloads too.
#'
#' @section Failed downloads:
#' When a download fails, because a server can't be reached or a file has
#' moved or changed, the method stops with an error saying which and why. The
#' error has class `geopt_download_error`, so a script can catch download
#' failures alone with `tryCatch(..., geopt_download_error = ...)`.
#'
#' @section Usage:
#' ```r
#' client <- GeoClient$new()
#' sf <- client$get_caop("continente", "municipio")
#' ```
#'
#' @importFrom R6 R6Class
#' @export
GeoClient <- R6::R6Class(
  "GeoClient",

  # --- Private ---------------------------------------------------------------

  private = list(
    .cache_dir = NULL,
    .use_cache = TRUE,
    .crs = DEFAULT_CRS,

    raw_dir = function() file.path(private$.cache_dir, "raw"),

    processed_dir = function() file.path(private$.cache_dir, "processed"),

    ensure_dirs = function() {
      dir.create(private$raw_dir(), recursive = TRUE, showWarnings = FALSE)
      dir.create(private$processed_dir(), recursive = TRUE, showWarnings = FALSE)
    },

    cache_key = function(region, level, year, detail) {
      sprintf("%s_%s_%d_%s.rds", region, level, year, detail)
    },

    get_cached = function(region, level, year, detail) {
      if (!private$.use_cache) return(NULL)
      path <- file.path(private$processed_dir(), private$cache_key(region, level, year, detail))
      if (file.exists(path)) readRDS(path) else NULL
    },

    save_cache = function(sf_obj, region, level, year, detail) {
      private$ensure_dirs()
      path <- file.path(private$processed_dir(), private$cache_key(region, level, year, detail))
      saveRDS(sf_obj, path)
      invisible(path)
    },

    # When year is NULL, scan local cache for the most recent year available
    # before making any network requests. Checks processed RDS first, then raw
    # GeoPackage files, iterating from current year backwards.
    find_cached_year = function(region) {
      current_year <- as.integer(format(Sys.Date(), "%Y"))

      for (y in current_year:(current_year - 2L)) {
        pattern <- sprintf("^%s_.*_%d_.*\\.rds$", region, y)
        if (length(list.files(private$processed_dir(), pattern = pattern)) > 0L) return(y)
        if (length(find_region_gpkgs(private$raw_dir(), region, y)) > 0L) return(y)
      }

      NULL
    },

    # Returns a character vector of gpkg paths (may be >1 for RAA). Stops with
    # a download error if the download fails or holds no GeoPackage.
    download_and_extract = function(region, year) {
      private$ensure_dirs()

      gpkg_files <- find_region_gpkgs(private$raw_dir(), region, year)
      if (length(gpkg_files) > 0L) {
        message(sprintf("Using cached raw data: %s (%d)", region, year))
        return(gpkg_files)
      }

      zip_name <- sprintf("CAOP_%s_%d.zip", REGION_URL_MAP[region], year)
      zip_path <- file.path(private$raw_dir(), zip_name)

      if (!file.exists(zip_path)) {
        url <- build_caop_url(region, year)
        message(sprintf("Downloading CAOP data for %s (%d)...", region, year))

        req <- httr2::request(url)
        req <- httr2::req_timeout(req, 600)
        req <- httr2::req_user_agent(req, "geopt R package")

        perform_request(req, path = zip_path)
      }

      message("Extracting...")
      # A file that isn't a zip only warns here; the check below reports it.
      tryCatch(
        suppressWarnings(utils::unzip(zip_path, exdir = private$raw_dir())),
        error = function(e) NULL
      )

      gpkg_files <- find_region_gpkgs(private$raw_dir(), region, year)
      if (length(gpkg_files) == 0L) {
        # Remove it so the next call downloads again.
        file.remove(zip_path)
        stop_download(sprintf(
          "The CAOP download for %s (%d) has no GeoPackage in it. The file at %s may have changed.",
          region, year, build_caop_url(region, year)
        ))
      }

      gpkg_files
    },

    # Read a single level from one or more gpkg files, merge, and reproject.
    read_level = function(gpkg_paths, region, level) {
      parts <- lapply(gpkg_paths, function(gpkg_path) {
        layer_info <- find_gpkg_layer(gpkg_path, level)

        if (is.list(layer_info)) {
          sf_obj <- sf::st_read(gpkg_path, layer = layer_info$layer, quiet = TRUE)
          dissolve_col <- find_dissolve_column(sf_obj, layer_info$dissolve_by)
          message(sprintf("Dissolving by '%s' to create %s boundaries...", dissolve_col, level))
          sf_obj <- dissolve_by(sf_obj, dissolve_col)
        } else {
          sf_obj <- sf::st_read(gpkg_path, layer = layer_info, quiet = TRUE)
        }

        sf::st_transform(sf_obj, private$.crs)
      })

      if (length(parts) == 1L) return(parts[[1L]])

      # Merge parts from multiple files (RAA case: one gpkg per CRS zone)
      common_cols <- Reduce(intersect, lapply(parts, names))
      parts <- lapply(parts, function(x) x[, common_cols, drop = FALSE])
      do.call(rbind, parts)
    }
  ),

  # --- Active bindings -------------------------------------------------------

  active = list(
    #' @field cache_dir Character. Path to the cache directory. Defaults to
    #'   `tools::R_user_dir("geopt", "cache")`.
    cache_dir = function(value) {
      if (missing(value)) return(private$.cache_dir)
      if (!is.character(value) || length(value) != 1L) {
        stop("cache_dir must be a single character string.", call. = FALSE)
      }
      private$.cache_dir <- value
      private$ensure_dirs()
    },

    #' @field use_cache Logical. Whether to read and write cached results
    #'   (default `TRUE`). With `FALSE`, cached results are neither read nor
    #'   written: each call builds its result again, and the latest CAOP year is
    #'   looked up online instead of taken from the cache. Downloaded files (CAOP
    #'   and census GeoPackages) are kept and reused either way;
    #'   `$clear_cache("raw")` removes them.
    use_cache = function(value) {
      if (missing(value)) return(private$.use_cache)
      if (!is.logical(value) || length(value) != 1L) {
        stop("use_cache must be a single logical value.", call. = FALSE)
      }
      private$.use_cache <- value
    },

    #' @field crs Integer EPSG code for the default coordinate reference system.
    #'   Defaults to 4326 (WGS84). Output can be transformed to any CRS via the
    #'   `crs` argument of `$get_caop()`.
    crs = function(value) {
      if (missing(value)) return(private$.crs)
      private$.crs <- as.integer(value)
    }
  ),

  # --- Public ----------------------------------------------------------------

  public = list(

    #' @description Create a new GeoClient.
    #' @param cache_dir Path to cache directory. Defaults to user cache dir.
    #' @param use_cache Whether to read and write cached results. Downloaded
    #'   files are kept either way; see the `use_cache` field.
    #' @param crs Default EPSG code. Defaults to 4326 (WGS84).
    initialize = function(cache_dir = NULL, use_cache = TRUE, crs = DEFAULT_CRS) {
      private$.cache_dir <- cache_dir %||% tools::R_user_dir("geopt", "cache")
      private$.use_cache <- use_cache
      private$.crs <- as.integer(crs)
      private$ensure_dirs()
      invisible(self)
    },

    #' @description Get geographic boundaries as an sf object.
    #' @param region One of "continente", "raa", "ram".
    #' @param level One of "freguesia", "municipio", "distrito",
    #'   "nuts1", "nuts2", "nuts3".
    #' @param year CAOP year. If NULL, resolves to the latest available.
    #' @param crs Output EPSG code. If NULL, uses the client default.
    #' @param detail Simplification level: "full", "high", "medium", "low" or
    #'   "very_low".
    #' @return An sf object.
    get_caop = function(region, level, year = NULL, crs = NULL, detail = "full") {
      region <- validate_region(region)
      level  <- validate_level(level)
      detail <- validate_detail(detail)
      if (is.null(year) && private$.use_cache) {
        year <- private$find_cached_year(region)
      }
      year    <- resolve_year(region, year)
      out_crs <- crs %||% private$.crs

      cached <- private$get_cached(region, level, year, detail)
      if (!is.null(cached)) {
        message(sprintf("Using cached: %s %s %d (%s)", region, level, year, detail))
        if (!is.na(sf::st_crs(cached)$epsg) && sf::st_crs(cached)$epsg != out_crs) {
          cached <- sf::st_transform(cached, out_crs)
        }
        return(cached)
      }

      # Before downloading: a missing rmapshaper would otherwise only show up
      # after a download of 15 MB or more.
      if (detail != "full") {
        check_suggested_pkg("rmapshaper", "for boundary simplification")
      }

      gpkg_paths <- private$download_and_extract(region, year)
      sf_obj <- private$read_level(gpkg_paths, region, level)

      if (detail != "full") {
        sf_obj <- self$simplify_boundaries(sf_obj, detail)
      }

      if (private$.use_cache) private$save_cache(sf_obj, region, level, year, detail)

      if (!is.na(sf::st_crs(sf_obj)$epsg) && sf::st_crs(sf_obj)$epsg != out_crs) {
        sf_obj <- sf::st_transform(sf_obj, out_crs)
      }

      sf_obj
    },

    #' @description Get features from a DGT OGC API collection.
    #'
    #' Queries `https://ogcapi.dgterritorio.gov.pt/` and returns the response
    #' as an sf object. Use this for filtered or bounded subsets (single
    #' municipio, bbox around a city, COS land-cover by area). For bulk
    #' country-wide downloads of CAOP, `$get_caop()` is faster.
    #'
    #' @param collection Collection id, e.g. "freguesias", "municipios",
    #'   "nuts3", "cos2023v1". See `$list_ogc_collections()`; an id geopt
    #'   doesn't know is an error that lists the ones it does. The large
    #'   collections (`"cos2018v3"`, `"cos2023v1"`, `"cadastro"`) need a
    #'   `bbox`, `properties` or `cql_filter`.
    #' @param bbox Numeric length-4 vector `c(xmin, ymin, xmax, ymax)` or an
    #'   sf `bbox` object. If NULL, no spatial filter is applied.
    #' @param bbox_crs Integer EPSG code that `bbox` is expressed in.
    #'   Defaults to 4326. Only sent to the server when not 4326.
    #' @param properties Named list of equality filters on attribute columns,
    #'   e.g. `list(distrito = "Lisboa")`. Use `cql_filter` for more complex
    #'   predicates.
    #' @param cql_filter Optional CQL-Text filter string, passed through
    #'   verbatim. Example: `"distrito_ilha = 'Lisboa'"`. DGT's server
    #'   accepts CQL1 syntax (`cql-text`), not CQL2.
    #' @param crs Output EPSG code. If NULL, uses the client default. Requested
    #'   server-side to avoid client-side reprojection.
    #' @param limit Page size sent to the server. Default 1000.
    #' @param max_features Stop pagination after this many features. Defaults
    #'   to `Inf` (fetch everything).
    #' @return An sf object, or NULL if the query returned zero features.
    get_ogc = function(collection, bbox = NULL, bbox_crs = 4326L,
                       properties = NULL, cql_filter = NULL, crs = NULL,
                       limit = OGC_DEFAULT_LIMIT, max_features = Inf) {
      meta <- validate_ogc_collection(collection)
      bbox <- validate_bbox(bbox)

      no_filter <- is.null(bbox) && is.null(properties) && is.null(cql_filter)
      if (isTRUE(meta$requires_filter) && no_filter) {
        stop(sprintf(
          "Collection '%s' is too large to fetch unfiltered. Pass `bbox`, `properties`, or `cql_filter`.",
          collection
        ), call. = FALSE)
      }

      out_crs <- crs %||% private$.crs

      params <- build_ogc_query(
        bbox       = bbox,
        bbox_crs   = bbox_crs,
        crs        = out_crs,
        properties = properties,
        cql_filter = cql_filter,
        limit      = limit
      )

      cache_path <- NULL
      if (private$.use_cache && is.infinite(max_features)) {
        private$ensure_dirs()
        cache_path <- file.path(
          private$processed_dir(),
          ogc_cache_key(collection, params, out_crs)
        )
        if (file.exists(cache_path)) {
          message(sprintf("Using cached OGC: %s", basename(cache_path)))
          return(readRDS(cache_path))
        }
      }

      url <- build_ogc_items_url(collection)
      message(sprintf("Fetching OGC features: %s ...", collection))
      sf_obj <- ogc_fetch_features(url, params, max_features = max_features)

      if (is.null(sf_obj)) {
        message("Query returned 0 features.")
        return(NULL)
      }

      # Server already projected to out_crs via the `crs` query param,
      # but sanity-check and fix if the server ignored it.
      current_epsg <- sf::st_crs(sf_obj)$epsg
      if (!is.na(current_epsg) && current_epsg != out_crs) {
        sf_obj <- sf::st_transform(sf_obj, out_crs)
      }

      if (!is.null(cache_path)) saveRDS(sf_obj, cache_path)

      sf_obj
    },

    #' @description List collections reported live by the DGT OGC API.
    #'
    #' Hits `/collections?f=json`. Used for discovery; the package itself
    #' validates against the hardcoded `OGC_COLLECTIONS` registry.
    #'
    #' @return A data.frame with columns `id`, `title`, `item_type`,
    #'   `description`.
    list_ogc_collections = function() {
      req <- httr2::request(sprintf("%s/collections", OGC_BASE_URL))
      req <- httr2::req_url_query(req, f = "json")
      req <- httr2::req_user_agent(req, "geopt R package")
      req <- httr2::req_timeout(req, 60)
      resp <- perform_request(req)
      body <- tryCatch(
        httr2::resp_body_json(resp, simplifyVector = FALSE),
        error = function(e) {
          stop_download(sprintf(
            "Could not read the collection list from %s: %s. The service may have changed.",
            OGC_BASE_URL, conditionMessage(e)
          ))
        }
      )
      cols <- body$collections %||% list()

      do.call(rbind, lapply(cols, function(c) {
        data.frame(
          id          = c$id %||% NA_character_,
          title       = c$title %||% NA_character_,
          item_type   = c$itemType %||% NA_character_,
          description = c$description %||% NA_character_,
          stringsAsFactors = FALSE
        )
      }))
    },

    #' @description Download boundaries to cache without loading into memory.
    #' @param region One of "continente", "raa", "ram".
    #' @param year CAOP year. If NULL, resolves to the latest available.
    #' @return The paths to the downloaded GeoPackage files (invisibly).
    download_caop = function(region, year = NULL) {
      region <- validate_region(region)
      if (is.null(year) && private$.use_cache) {
        year <- private$find_cached_year(region)
      }
      year <- resolve_year(region, year)
      gpkg_paths <- private$download_and_extract(region, year)
      message(sprintf("Data available at:\n  %s", paste(gpkg_paths, collapse = "\n  ")))
      invisible(gpkg_paths)
    },

    #' @description Simplify boundary geometries.
    #' @param sf_obj An sf object.
    #' @param detail One of "full", "high", "medium", "low" or "very_low".
    #' @return A simplified sf object.
    simplify_boundaries = function(sf_obj, detail = "medium") {
      check_suggested_pkg("rmapshaper", "for boundary simplification")
      detail <- validate_detail(detail)
      if (detail == "full") return(sf_obj)
      keep <- SIMPLIFY_PRESETS[[detail]]
      rmapshaper::ms_simplify(sf_obj, keep = keep, keep_shapes = TRUE)
    },

    #' @description Export boundaries to a file format suitable for dashboards.
    #' @param sf_obj An sf object.
    #' @param path Output file path.
    #' @param format Output format: "geojson" or "gpkg".
    #' @param detail Optional simplification level before export.
    #' @param crs Output EPSG code. Defaults to 4326 (WGS84) for web
    #'   compatibility.
    #' @return The output path (invisibly).
    export_boundaries = function(sf_obj, path, format = "geojson", detail = NULL, crs = 4326L) {
      if (!is.null(detail)) {
        sf_obj <- self$simplify_boundaries(sf_obj, detail)
      }

      current_epsg <- sf::st_crs(sf_obj)$epsg
      if (!is.na(current_epsg) && current_epsg != crs) {
        sf_obj <- sf::st_transform(sf_obj, crs)
      }

      driver <- switch(format,
        geojson = "GeoJSON",
        gpkg    = "GPKG",
        stop(sprintf("Unsupported format '%s'. Use 'geojson' or 'gpkg'.", format), call. = FALSE)
      )

      if (file.exists(path)) file.remove(path)
      sf::st_write(sf_obj, path, driver = driver, quiet = TRUE)

      size_kb <- file.size(path) / 1024
      unit <- if (size_kb > 1024) "MB" else "KB"
      size_display <- if (size_kb > 1024) size_kb / 1024 else size_kb
      message(sprintf("Exported to: %s (%.1f %s)", path, size_display, unit))
      invisible(path)
    },

    #' @description List cached data files.
    #' @return A list with `processed` and `raw` character vectors.
    list_cached = function() {
      processed <- list.files(private$processed_dir(), pattern = "\\.rds$")
      raw <- list.files(private$raw_dir(), pattern = "\\.gpkg$", recursive = TRUE)
      list(
        processed = gsub("\\.rds$", "", processed),
        raw = raw
      )
    },

    #' @description Clear cached data.
    #' @param type One of "all", "processed", or "raw".
    clear_cache = function(type = c("all", "processed", "raw")) {
      type <- match.arg(type)

      if (type %in% c("all", "processed")) {
        files <- list.files(private$processed_dir(), full.names = TRUE)
        if (length(files) > 0L) file.remove(files)
        message(sprintf("Cleared %d processed files.", length(files)))
      }

      if (type %in% c("all", "raw")) {
        files <- list.files(private$raw_dir(), full.names = TRUE, recursive = TRUE)
        if (length(files) > 0L) file.remove(files)
        message(sprintf("Cleared %d raw files.", length(files)))
      }

      invisible(self)
    },

    #' @description Print method.
    #' @param ... Ignored.
    print = function(...) {
      cat("<GeoClient>\n")
      cat(sprintf("  Cache: %s\n", private$.cache_dir))
      cat(sprintf("  CRS:   EPSG:%d\n", private$.crs))
      cat(sprintf("  Cache: %s\n", if (private$.use_cache) "enabled" else "disabled"))
      cached <- self$list_cached()
      cat(sprintf("  Files: %d processed, %d raw\n", length(cached$processed), length(cached$raw)))
      invisible(self)
    }
  )
)
