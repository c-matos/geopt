# GeoClient

R6 class for downloading, processing, and caching Portuguese geographic
boundaries from CAOP (Carta Administrativa Oficial de Portugal), and for
filtered queries to DGT's OGC API.
[`get_censos()`](https://c-matos.github.io/geopt/reference/get_censos.md)
and [`get_map()`](https://c-matos.github.io/geopt/reference/get_map.md)
use one for their downloads too.

## Failed downloads

When a download fails, because a server can't be reached or a file has
moved or changed, the method stops with an error saying which and why.
The error has class `geopt_download_error`, so a script can catch
download failures alone with
`tryCatch(..., geopt_download_error = ...)`.

## Usage

    client <- GeoClient$new()
    sf <- client$get_caop("continente", "municipio")

## Active bindings

- `cache_dir`:

  Character. Path to the cache directory. Defaults to
  `tools::R_user_dir("geopt", "cache")`.

- `use_cache`:

  Logical. Whether to read and write cached results (default `TRUE`).
  With `FALSE`, cached results are neither read nor written: each call
  builds its result again, and the latest CAOP year is looked up online
  instead of taken from the cache. Downloaded files (CAOP and census
  GeoPackages) are kept and reused either way; `$clear_cache("raw")`
  removes them.

- `crs`:

  Integer EPSG code for the default coordinate reference system.
  Defaults to 4326 (WGS84). Output can be transformed to any CRS via the
  `crs` argument of `$get_caop()`.

## Methods

### Public methods

- [`GeoClient$new()`](#method-GeoClient-initialize)

- [`GeoClient$get_caop()`](#method-GeoClient-get_caop)

- [`GeoClient$get_ogc()`](#method-GeoClient-get_ogc)

- [`GeoClient$list_ogc_collections()`](#method-GeoClient-list_ogc_collections)

- [`GeoClient$download_caop()`](#method-GeoClient-download_caop)

- [`GeoClient$simplify_boundaries()`](#method-GeoClient-simplify_boundaries)

- [`GeoClient$export_boundaries()`](#method-GeoClient-export_boundaries)

- [`GeoClient$list_cached()`](#method-GeoClient-list_cached)

- [`GeoClient$clear_cache()`](#method-GeoClient-clear_cache)

- [`GeoClient$print()`](#method-GeoClient-print)

- [`GeoClient$clone()`](#method-GeoClient-clone)

------------------------------------------------------------------------

### `GeoClient$new()`

Create a new GeoClient.

#### Usage

    GeoClient$new(cache_dir = NULL, use_cache = TRUE, crs = DEFAULT_CRS)

#### Arguments

- `cache_dir`:

  Path to cache directory. Defaults to user cache dir.

- `use_cache`:

  Whether to read and write cached results. Downloaded files are kept
  either way; see the `use_cache` field.

- `crs`:

  Default EPSG code. Defaults to 4326 (WGS84).

------------------------------------------------------------------------

### `GeoClient$get_caop()`

Get geographic boundaries as an sf object.

#### Usage

    GeoClient$get_caop(region, level, year = NULL, crs = NULL, detail = "full")

#### Arguments

- `region`:

  One of "continente", "raa", "ram".

- `level`:

  One of "freguesia", "municipio", "distrito", "nuts1", "nuts2",
  "nuts3".

- `year`:

  CAOP year. If NULL, resolves to the latest available.

- `crs`:

  Output EPSG code. If NULL, uses the client default.

- `detail`:

  Simplification level: "full", "high", "medium", "low" or "very_low".

#### Returns

An sf object.

------------------------------------------------------------------------

### `GeoClient$get_ogc()`

Get features from a DGT OGC API collection.

Queries `https://ogcapi.dgterritorio.gov.pt/` and returns the response
as an sf object. Use this for filtered or bounded subsets (single
municipio, bbox around a city, COS land-cover by area). For bulk
country-wide downloads of CAOP, `$get_caop()` is faster.

#### Usage

    GeoClient$get_ogc(
      collection,
      bbox = NULL,
      bbox_crs = 4326L,
      properties = NULL,
      cql_filter = NULL,
      crs = NULL,
      limit = OGC_DEFAULT_LIMIT,
      max_features = Inf
    )

#### Arguments

- `collection`:

  Collection id, e.g. "freguesias", "municipios", "nuts3", "cos2023v1".
  See `$list_ogc_collections()`; an id geopt doesn't know is an error
  that lists the ones it does. The large collections (`"cos2018v3"`,
  `"cos2023v1"`, `"cadastro"`) need a `bbox`, `properties` or
  `cql_filter`.

- `bbox`:

  Numeric length-4 vector `c(xmin, ymin, xmax, ymax)` or an sf `bbox`
  object. If NULL, no spatial filter is applied.

- `bbox_crs`:

  Integer EPSG code that `bbox` is expressed in. Defaults to 4326. Only
  sent to the server when not 4326.

- `properties`:

  Named list of equality filters on attribute columns, e.g.
  `list(distrito = "Lisboa")`. Use `cql_filter` for more complex
  predicates.

- `cql_filter`:

  Optional CQL-Text filter string, passed through verbatim. Example:
  `"distrito_ilha = 'Lisboa'"`. DGT's server accepts CQL1 syntax
  (`cql-text`), not CQL2.

- `crs`:

  Output EPSG code. If NULL, uses the client default. Requested
  server-side to avoid client-side reprojection.

- `limit`:

  Page size sent to the server. Default 1000.

- `max_features`:

  Stop pagination after this many features. Defaults to `Inf` (fetch
  everything).

#### Returns

An sf object, or NULL if the query returned zero features.

------------------------------------------------------------------------

### `GeoClient$list_ogc_collections()`

List collections reported live by the DGT OGC API.

Hits `/collections?f=json`. Used for discovery; the package itself
validates against the hardcoded `OGC_COLLECTIONS` registry.

#### Usage

    GeoClient$list_ogc_collections()

#### Returns

A data.frame with columns `id`, `title`, `item_type`, `description`.

------------------------------------------------------------------------

### `GeoClient$download_caop()`

Download boundaries to cache without loading into memory.

#### Usage

    GeoClient$download_caop(region, year = NULL)

#### Arguments

- `region`:

  One of "continente", "raa", "ram".

- `year`:

  CAOP year. If NULL, resolves to the latest available.

#### Returns

The paths to the downloaded GeoPackage files (invisibly).

------------------------------------------------------------------------

### `GeoClient$simplify_boundaries()`

Simplify boundary geometries.

#### Usage

    GeoClient$simplify_boundaries(sf_obj, detail = "medium")

#### Arguments

- `sf_obj`:

  An sf object.

- `detail`:

  One of "full", "high", "medium", "low" or "very_low".

#### Returns

A simplified sf object.

------------------------------------------------------------------------

### `GeoClient$export_boundaries()`

Export boundaries to a file format suitable for dashboards.

#### Usage

    GeoClient$export_boundaries(
      sf_obj,
      path,
      format = "geojson",
      detail = NULL,
      crs = 4326L
    )

#### Arguments

- `sf_obj`:

  An sf object.

- `path`:

  Output file path.

- `format`:

  Output format: "geojson" or "gpkg".

- `detail`:

  Optional simplification level before export.

- `crs`:

  Output EPSG code. Defaults to 4326 (WGS84) for web compatibility.

#### Returns

The output path (invisibly).

------------------------------------------------------------------------

### `GeoClient$list_cached()`

List cached data files.

#### Usage

    GeoClient$list_cached()

#### Returns

A list with `processed` and `raw` character vectors.

------------------------------------------------------------------------

### `GeoClient$clear_cache()`

Clear cached data.

#### Usage

    GeoClient$clear_cache(type = c("all", "processed", "raw"))

#### Arguments

- `type`:

  One of "all", "processed", or "raw".

------------------------------------------------------------------------

### `GeoClient$print()`

Print method.

#### Usage

    GeoClient$print(...)

#### Arguments

- `...`:

  Ignored.

------------------------------------------------------------------------

### `GeoClient$clone()`

The objects of this class are cloneable with this method.

#### Usage

    GeoClient$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
