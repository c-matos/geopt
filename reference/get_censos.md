# Get INE census geographies (BGRI, secções, GRID)

Downloads and reads the census geographies that INE distributes at
<https://mapas.ine.pt/download/index2021.phtml>: BGRI subsecções
(city-block/place-part polygons) for the 1991, 2001, 2011, and 2021
censuses, statistical secções, and the 1 km grid — each with the census
variables INE embeds in the files. Files are fetched at the smallest
scope that covers the request (per-municipality files are typically 1–3
MB) and cached.

## Usage

``` r
get_censos(
  municipio = NULL,
  year = 2021,
  level = "subseccao",
  region = NULL,
  freguesia = NULL,
  variables = NULL,
  geometry = TRUE,
  crs = NULL,
  client = NULL
)
```

## Arguments

- municipio:

  Municipality name(s) or DTMN code(s). See *Scope*.

- year:

  Census year: 1991, 2001, 2011, or 2021 (default).

- level:

  `"subseccao"` (default), `"seccao"`, or `"grid"`.

- region:

  Region keyword, NUTS2/NUTS3 name, or NUTS 2013 code. See *Scope*.

- freguesia:

  Freguesia name(s) or DTMNFR code(s). See *Scope*.

- variables:

  Optional character vector of census variables to keep
  (case-insensitive; identifier columns are always kept). See
  [pt_censos_vars](https://c-matos.github.io/geopt/reference/pt_censos_vars.md).

- geometry:

  Logical. `FALSE` drops the geometry and returns a plain data.frame.
  Default `TRUE`.

- crs:

  Output EPSG code. If `NULL`, uses the client default (4326).

- client:

  Optional
  [GeoClient](https://c-matos.github.io/geopt/reference/GeoClient.md) to
  use (for a custom cache directory or CRS). Defaults to
  `GeoClient$new()`.

## Value

An sf object (or a data.frame when `geometry = FALSE`) with one row per
subsecção, secção, or grid cell. A failed download stops with an error
of class `geopt_download_error` saying why (see
[GeoClient](https://c-matos.github.io/geopt/reference/GeoClient.md)).

## Scope

Exactly one scope must be given (there is no default: a whole-country
request is ~250 MB and must be explicit):

- `municipio`: one or more municipality names or 4-digit DTMN codes,
  resolved via
  [`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md)
  (qualifiers like `"Lagoa (Açores)"` work). Downloads the
  per-municipality file(s).

- `freguesia`: one or more freguesia names or 6-digit DTMNFR codes.
  Downloads the enclosing municipality file(s) and filters. May be
  combined with `municipio` to disambiguate names.

- `region`: `"portugal"`, `"continente"`, `"raa"`/`"açores"`,
  `"ram"`/`"madeira"`, a NUTS2 or NUTS3 name, or a NUTS 2013 code
  (`"PT16D"`/`"16D"`). Census files follow the NUTS 2013 geography; NUTS
  2024 names are accepted when they map unambiguously to it.

## Levels and years

- `"subseccao"` (default): BGRI subsecções, available for all four
  censuses. 2021 files embed 32 census variables, 2011 files 122,
  1991/2001 files seven basic counts.

- `"seccao"`: statistical secções. For 2021 these are INE's native files
  with ~180 variables (more detail than the subsecção set). For earlier
  censuses no secção product exists: subsecções are downloaded and
  dissolved, summing that year's variables (adds `n_subseccoes`).

- `"grid"`: the 2021-only 1 km grid (EPSG:3035 cells crossing
  administrative boundaries), `region` scope only.

See
[pt_censos_vars](https://c-matos.github.io/geopt/reference/pt_censos_vars.md)
for every variable with its INE description.

## Identifiers

INE's identifier columns are year-suffixed and inconsistent (`DTCC91`,
`DTMN21`, `FR11`, ...). Year-stable tidy columns are added alongside the
originals: `censos_year`, `bgri` (full subsecção code), `dtmn`,
`dtmnfr`, `seccao`, `subseccao`, and — where the file carries them
(1991–2011) — `lugar`/`lugar_nome`. GIS artifacts (`OBJECTID`,
`SHAPE_*`) and INE join metadata are dropped.

Freguesia codes are vintage-specific: each census uses the freguesia map
in force at the time. The `dtmnfr` codes of the 2021 census are the
`"2013"` vintage, those of 2011 the `"2011"` vintage and those of 2001
the `"2001"` vintage, so
[`pt_recode()`](https://c-matos.github.io/geopt/reference/pt_recode.md)
converts them to today's map. The 1991 census used an earlier map (4208
freguesias in 305 municípios, before Odivelas, Trofa and Vizela were
created in 1998), which geopt has no vintage for.

Name-based `freguesia` scoping resolves against the current registry
and, for 2021, also matches through
[`pt_crosswalk()`](https://c-matos.github.io/geopt/reference/pt_crosswalk.md);
for older censuses pass that era's codes if a name does not resolve. In
the 2001 files, two freguesias still carry the code of the municipality
they belonged to before a transfer: Vale de Amoreira is `090756`
(Guarda, now Manteigas) and Moita `100117` (Alcobaça, now Marinha
Grande).
[`pt_recode()`](https://c-matos.github.io/geopt/reference/pt_recode.md)
and
[`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md)
accept those codes for the `"2001"` vintage, and a `freguesia` filter
finds either form.

## See also

[pt_censos_vars](https://c-matos.github.io/geopt/reference/pt_censos_vars.md),
[GeoClient](https://c-matos.github.io/geopt/reference/GeoClient.md) (for
`client`),
[`get_map()`](https://c-matos.github.io/geopt/reference/get_map.md) for
administrative boundaries.

## Examples

``` r
# City blocks of Braga with the 2021 census variables (~2 MB download)
bgri <- get_censos("Braga")
#> Downloading Censos 2021 0303 (BGRI2021_0303.zip)...
#> Error: Could not reach mapas.ine.pt: Timeout was reached [mapas.ine.pt]: Failed to connect to mapas.ine.pt port 443 after 134217 ms: Couldn't connect to server. Check your internet connection, or try again later.

# Population density by subsecção
bgri$dens <- bgri$N_INDIVIDUOS / sf::st_area(bgri)
#> Error: object 'bgri' not found

# 2011 vintage, only the resident population variables
get_censos("Braga", year = 2011,
           variables = c("N_INDIVIDUOS_RESIDENT", "N_INDIVIDUOS_RESIDENT_H"))
#> Downloading Censos 2011 0303 (BGRI2011_0303.zip)...
#> Error: Could not reach mapas.ine.pt: Timeout was reached [mapas.ine.pt]: Failed to connect to mapas.ine.pt port 443 after 135145 ms: Couldn't connect to server. Check your internet connection, or try again later.

# Secção-level detail (native 2021 product, ~180 variables)
get_censos("Braga", level = "seccao")
#> Downloading Censos 2021 0303 (C2021_SECCOES_0303.zip)...
#> Error: Could not reach mapas.ine.pt: Timeout was reached [mapas.ine.pt]: Failed to connect to mapas.ine.pt port 443 after 135150 ms: Couldn't connect to server. Check your internet connection, or try again later.

# A whole NUTS3, and the 1 km grid for the mainland
get_censos(region = "Cávado")
#> Downloading Censos 2021 112 (BGRI21_112.zip)...
#> Error: Could not reach mapas.ine.pt: Timeout was reached [mapas.ine.pt]: Failed to connect to mapas.ine.pt port 443 after 135030 ms: Couldn't connect to server. Check your internet connection, or try again later.
get_censos(region = "continente", level = "grid")
#> Downloading Censos 2021 CONT (GRID1K21_CONT.zip)...
#> Error: Could not reach mapas.ine.pt: Timeout was reached [mapas.ine.pt]: Failed to connect to mapas.ine.pt port 443 after 135146 ms: Couldn't connect to server. Check your internet connection, or try again later.

# Just the data, no geometry
get_censos("Braga", geometry = FALSE)
#> Downloading Censos 2021 0303 (BGRI2021_0303.zip)...
#> Error: Could not reach mapas.ine.pt: Timeout was reached [mapas.ine.pt]: Failed to connect to mapas.ine.pt port 443 after 135151 ms: Couldn't connect to server. Check your internet connection, or try again later.
```
