# Package index

## Make a map

Composed maps of Portugal (mainland + island insets) and one-liner
choropleths.

- [`plot_pt()`](https://c-matos.github.io/geopt/reference/plot_pt.md) :
  Quick map of Portugal
- [`get_map()`](https://c-matos.github.io/geopt/reference/get_map.md) :
  Get a composed map of Portugal

## Island layout

How the Açores and Madeira are shown, and helpers for drawing the frames
and island labels with echarts4r.

- [`island_layout()`](https://c-matos.github.io/geopt/reference/island_layout.md)
  : Lay out the islands
- [`frame_data_echarts()`](https://c-matos.github.io/geopt/reference/frame_data_echarts.md)
  : Build echarts frame styling data
- [`box_labels_echarts()`](https://c-matos.github.io/geopt/reference/box_labels_echarts.md)
  : Add labels to an echarts map

## Join and match

Getting custom data onto official units.

- [`pt_join()`](https://c-matos.github.io/geopt/reference/pt_join.md) :
  Add official codes and administrative context to a data frame
- [`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md)
  : Match place names to official codes
- [`pt_match_report()`](https://c-matos.github.io/geopt/reference/pt_match_report.md)
  : Retrieve the match report from a pt_match result
- [`pt_normalize()`](https://c-matos.github.io/geopt/reference/pt_normalize.md)
  : Normalize Portuguese place names for matching
- [`pt_pad_code()`](https://c-matos.github.io/geopt/reference/pt_pad_code.md)
  : Restore leading zeros in administrative codes

## Vintages

Converting freguesia-level data between boundary vintages.

- [`pt_crosswalk()`](https://c-matos.github.io/geopt/reference/pt_crosswalk.md)
  : Correspondence between two administrative vintages
- [`pt_recode()`](https://c-matos.github.io/geopt/reference/pt_recode.md)
  : Convert freguesia-level data between code vintages

## Download client

Full-resolution CAOP downloads, INE census geographies, and the DGT OGC
API.

- [`GeoClient`](https://c-matos.github.io/geopt/reference/GeoClient.md)
  : GeoClient
- [`get_censos()`](https://c-matos.github.io/geopt/reference/get_censos.md)
  : Get INE census geographies (BGRI, secções, GRID)

## Data

Bundled boundaries and lookup tables.

- [`pt_freguesias`](https://c-matos.github.io/geopt/reference/boundaries.md)
  [`pt_municipios`](https://c-matos.github.io/geopt/reference/boundaries.md)
  [`pt_distritos`](https://c-matos.github.io/geopt/reference/boundaries.md)
  [`pt_nuts1`](https://c-matos.github.io/geopt/reference/boundaries.md)
  [`pt_nuts2`](https://c-matos.github.io/geopt/reference/boundaries.md)
  [`pt_nuts3`](https://c-matos.github.io/geopt/reference/boundaries.md)
  [`pt_uls`](https://c-matos.github.io/geopt/reference/boundaries.md)
  [`pt_reg_saude`](https://c-matos.github.io/geopt/reference/boundaries.md)
  [`pt_aces`](https://c-matos.github.io/geopt/reference/boundaries.md)
  [`pt_uls_municipio`](https://c-matos.github.io/geopt/reference/boundaries.md)
  [`pt_aces_municipio`](https://c-matos.github.io/geopt/reference/boundaries.md)
  : Simplified Portuguese administrative boundaries
- [`pt_censos_vars`](https://c-matos.github.io/geopt/reference/pt_censos_vars.md)
  : Census variables available from get_censos()
- [`pt_registry`](https://c-matos.github.io/geopt/reference/pt_registry.md)
  : Portuguese administrative units, every vintage
- [`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md)
  : Administrative, NUTS and health codes for one choice of each vintage
- [`pt_health_codes`](https://c-matos.github.io/geopt/reference/pt_health_codes.md)
  : Health geography of Portuguese freguesias, both vintages
- [`pt_nuts_codes`](https://c-matos.github.io/geopt/reference/pt_nuts_codes.md)
  : NUTS classification of Portuguese municípios, every revision
