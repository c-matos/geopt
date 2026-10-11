# Downloading official data

``` r

library(geopt)
```

The bundled boundaries are simplified so they plot quickly. geopt can
also download data from the two official sources:

- **DGT** (Direção-Geral do Território): the full-resolution official
  boundaries (CAOP), and other datasets such as land cover, through its
  online service.
- **INE** (Instituto Nacional de Estatística): the census areas, from
  single city blocks upwards, with the census data attached.

Downloads go through `GeoClient`, an `R6` object that holds the
settings, such as where to cache:

``` r

client <- GeoClient$new()
client
```

Everything the client downloads is cached under
`tools::R_user_dir("geopt", "cache")`, so later calls are instant and
work offline. To use another folder, pass
`GeoClient$new(cache_dir = ...)`.

If a download fails, because a server can’t be reached or a file has
moved, the error says which and why:

``` r

# With no internet connection
bgri <- get_censos("Braga")
#> Downloading Censos 2021 0303 (BGRI2021_0303.zip)...
#> Error: Could not reach mapas.ine.pt: Could not resolve hostname
#> [mapas.ine.pt]: Could not resolve host: mapas.ine.pt. Check your internet
#> connection, or try again later.
```

These errors have the class `geopt_download_error`, so a script can
catch failed downloads without hiding other errors. For example, to
carry on with the municipalities that did download:

``` r

bgri <- lapply(c("Braga", "Guimarães"), function(m) {
  tryCatch(get_censos(m), geopt_download_error = function(e) NULL)
})
```

## Full-resolution CAOP boundaries

``` r

# Latest year, full detail, as sf
mun <- client$get_caop("continente", "municipio")

# A specific year and a simplification preset
freg_2022 <- client$get_caop("continente", "freguesia",
                             year = 2022, detail = "medium")
```

The regions are `"continente"`, `"raa"` (Açores) and `"ram"` (Madeira).
The levels run from `"freguesia"` to `"nuts3"`. When a year’s file has
no NUTS layer, geopt builds it by merging municipalities. `detail`
simplifies the boundaries (`"full"`, `"high"`, `"medium"`, `"low"` or
`"very_low"`; this needs the rmapshaper package), and each combination
is cached.

To download the files without loading them, for example to read them
with other tools:

``` r

paths <- client$download_caop("continente", year = 2024)
```

## Filtered queries to DGT’s online service

To get only part of a dataset, `get_ogc()` calls DGT’s online service
(`https://ogcapi.dgterritorio.gov.pt`, which follows the OGC API
standard) to do the filtering, so the whole country isn’t downloaded:

``` r

# One district's municipalities
lisboa <- client$get_ogc("municipios", properties = list(distrito = "Lisboa"))

# Everything inside a rectangle (longitude and latitude)
box <- client$get_ogc("freguesias", bbox = c(-9.3, 38.6, -9.0, 38.85))

# A filter expression, in the service's query language (CQL)
alg <- client$get_ogc("municipios", cql_filter = "distrito_ilha = 'Faro'")
```

The land cover maps (COS) and the land registry (`cadastro`) are large,
so for these a filter is **required**:

``` r

cos <- client$get_ogc("cos2023v1", bbox = c(-8.45, 40.15, -8.35, 40.25))
```

To see what datasets the service offers right now:

``` r

client$list_ogc_collections()
```

Raster datasets, such as aerial photographs, aren’t supported yet. The
error message suggests how to read them with the terra package or GDAL
instead.

## Census areas: subsecções, secções and the 1 km grid

INE publishes the areas the census is counted in, with the census data
attached to each file:

- **subsecções**, the smallest areas: city blocks in towns, villages or
  parts of villages in the countryside. They form the BGRI (Base
  Geográfica de Referenciação de Informação), available for the 1991,
  2001, 2011 and 2021 censuses.
- **secções**, statistical sections made of several subsecções.
- a **1 km grid**, for 2021 only.

[`get_censos()`](https://c-matos.github.io/geopt/reference/get_censos.md)
downloads the smallest file that covers the request: a municipality is a
1–3 MB file, not a 250 MB download for the whole country.

``` r

# City blocks of Braga, 2021 variables included
bgri <- get_censos("Braga")

library(ggplot2)
ggplot(bgri) +
  geom_sf(aes(fill = N_INDIVIDUOS / as.numeric(sf::st_area(geometry)) * 1e6),
          color = NA) +
  scale_fill_viridis_c(name = "hab/km²", trans = "log10")
```

Choose the area with `municipio`, `freguesia` or `region` (a NUTS 2 or
NUTS 3 name, `"continente"`, `"raa"`, `"ram"` or `"portugal"`). There’s
deliberately no default, so the whole country can’t be downloaded by
accident. The same call works for every census year and level:

``` r

# The 2011 census has 122 variables; keep only some
get_censos("Braga", year = 2011,
           variables = c("N_INDIVIDUOS_RESIDENT", "N_EDIFICIOS_CLASSICOS"))

# Secções: INE's 2021 files have about 180 variables.
# For earlier censuses, geopt merges the subsecções and adds up their counts.
get_censos("Braga", level = "seccao")
get_censos("Braga", level = "seccao", year = 2011)

# A NUTS3, and the 2021-only 1 km grid (region scope only)
get_censos(region = "Cávado")
get_censos(region = "continente", level = "grid")

# Data without geometry
get_censos("Braga", geometry = FALSE)
```

`pt_censos_vars` lists the variables for each year and level:

``` r

head(pt_censos_vars[pt_censos_vars$year == 2021 &
                      pt_censos_vars$level == "subseccao",
                    c("variable", "description")])
#>                                              variable
#> 325                              N_ADP_1_OU_2_PESSOAS
#> 326                           N_ADP_3_OU_MAIS_PESSOAS
#> 327                   N_AGREGADOS_DOMESTICOS_PRIVADOS
#> 328                 N_ALOJAMENTOS_FAM_CLASS_RHABITUAL
#> 329 N_ALOJAMENTOS_FAM_CLASS_VAGOS_OU_RESID_SECUNDARIA
#> 330                          N_ALOJAMENTOS_FAMILIARES
#>                                                                  description
#> 325                   Nº de agregados domésticos privados com 1 ou 2 pessoas
#> 326                Nº de agregados domésticos privados com 3 ou mais pessoas
#> 327                                      Nº de agregados domésticos privados
#> 328            Nº de alojamentos familiares clássicos de residência habitual
#> 329 Nº de alojamentos familiares clássicos vagos ou de residência secundária
#> 330                                             Nº de alojamentos familiares
```

INE names its code columns differently in each census (`DTMN11` in 2011,
`DTMN21` in 2021, and so on).
[`get_censos()`](https://c-matos.github.io/geopt/reference/get_censos.md)
adds the same codes under names that stay the same every year (`bgri`,
`dtmn`, `dtmnfr`, `seccao`, `subseccao`, and `lugar` where the file has
it), so results from different censuses line up, and join with
[`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md).
Each census uses the freguesias of its own time, though, so the 2011
freguesia codes aren’t today’s: see
[`vignette("vintages")`](https://c-matos.github.io/geopt/articles/vintages.md).

To use a client’s cache and settings, pass it as
`get_censos("Braga", client = client)`.

## Exporting for dashboards

`export_boundaries()` writes GeoJSON or GeoPackage files, in WGS84 by
default, and can simplify the boundaries on the way out:

``` r

client$export_boundaries(mun, "municipios.geojson", detail = "low")
```

## Cache management

``` r

client$list_cached()
client$clear_cache("processed")  # or "raw", "all"
```

## Relationship to the rest of geopt

[`get_map()`](https://c-matos.github.io/geopt/reference/get_map.md) and
[`plot_pt()`](https://c-matos.github.io/geopt/reference/plot_pt.md)
don’t need the GeoClient for the current map: they use the bundled
boundaries. `get_map(admin_vintage = "2013")`, the one earlier map they
can draw, uses a `GeoClient` (and its cache) to download it the first
time it’s needed.
