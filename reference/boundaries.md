# Simplified Portuguese administrative boundaries

Pre-simplified sf objects derived from CAOP (Carta Administrativa
Oficial de Portugal). All levels are topologically consistent:
higher-level boundaries are dissolved from simplified freguesias,
guaranteeing aligned edges. Each level carries its own identity columns
(official codes and names) plus aggregated `area_ha`, so every dataset
joins directly against user data or against
[pt_registry](https://c-matos.github.io/geopt/reference/pt_registry.md).

## Usage

``` r
pt_freguesias

pt_municipios

pt_distritos

pt_nuts1

pt_nuts2

pt_nuts3

pt_uls

pt_reg_saude

pt_aces

pt_uls_municipio

pt_aces_municipio
```

## Format

An sf data frame with `MULTIPOLYGON` geometry.

An object of class `sf` (inherits from `data.frame`) with 3259 rows and
16 columns.

An object of class `sf` (inherits from `data.frame`) with 308 rows and
13 columns.

An object of class `sf` (inherits from `data.frame`) with 29 rows and 8
columns.

An object of class `sf` (inherits from `data.frame`) with 3 rows and 4
columns.

An object of class `sf` (inherits from `data.frame`) with 9 rows and 6
columns.

An object of class `sf` (inherits from `data.frame`) with 26 rows and 9
columns.

An object of class `sf` (inherits from `data.frame`) with 55 rows and 7
columns.

An object of class `sf` (inherits from `data.frame`) with 7 rows and 6
columns.

An object of class `sf` (inherits from `data.frame`) with 71 rows and 8
columns.

An object of class `sf` (inherits from `data.frame`) with 50 rows and 7
columns.

An object of class `sf` (inherits from `data.frame`) with 66 rows and 8
columns.

## Source

Direção-Geral do Território (DGT), CAOP.
<https://www.dgterritorio.gov.pt/cartografia/cartografia-tematica/caop>

## Details

Common columns (present where applicable to the level):

- dtmnfr:

  6-digit freguesia code (distrito + municipio + freguesia), zero-padded
  character. Freguesias only.

- dtmn:

  4-digit municipality code (first 4 digits of `dtmnfr`).

- dt:

  2-digit distrito/ilha code.

- nuts1_cod, nuts2_cod, nuts3_cod:

  NUTS 2024 codes in full Eurostat form (`PT1`, `PT19`, `PT191`, ...).

- freguesia, municipio, distrito_ilha, nuts1, nuts2, nuts3:

  Official names.

- designacao_simplificada:

  The freguesia's name without the `"União das freguesias de"` prefix.
  Freguesias only.

- perimetro_km:

  Perimeter in kilometres, as CAOP gives it. Freguesias only.

- area_ha:

  Area in hectares, summed from the constituent freguesias.

- n_freguesias, n_municipios:

  Number of constituent units.

Geometries use WGS84 (EPSG:4326) and cover all of Portugal (Continente,
Açores, and Madeira).

A multi-layer GeoPackage containing the same data is also bundled at
`inst/extdata/caop_simplified.gpkg`, with one layer per level:

    gpkg <- system.file("extdata", "caop_simplified.gpkg", package = "geopt")
    sf::st_layers(gpkg)
    sf::st_read(gpkg, layer = "municipio")

The health maps are dissolved from the same simplified freguesias using
the
[pt_health_codes](https://c-matos.github.io/geopt/reference/pt_health_codes.md)
mappings, so their edges align with every administrative level. Each
reflects a single health vintage and exists on the current freguesia map
only. `pt_uls`, `pt_reg_saude`, and `pt_aces` are freguesia-accurate:
units that split municipalities are drawn correctly.

`pt_uls` has 55 units: 39 mainland ULS plus the island health units,
which are not ULS — the Açores have nine Unidades de Saúde de Ilha
(`"USI São Miguel"`, ...) and Madeira seven centros de saúde
(`"CS Funchal Zona I"`, ...). `pt_reg_saude` carries the seven regiões
de saúde. Both are the 2024 reform.

`pt_aces` has 71 Agrupamentos de Centros de Saúde — the organization the
2024 reform superseded. Its `reg_saude` is the region of that time (the
former ARS), not the 2024 região de saúde.

`pt_uls_municipio` (50 units) and `pt_aces_municipio` (66) are for data
by municipality, which can't be divided between the units that share a
municipality. Those units are merged into one, named after its members
(`"ULS Santo António + São João"`), so every unit is a set of whole
municipalities. Lomba, the one freguesia of Gondomar in ULS Vila Nova de
Gaia/Espinho and ACES Espinho/Gaia, is drawn with the rest of Gondomar,
where data by municipality counts it. They hold the units of the
`uls_municipio` and `aces_municipio` columns that
[`pt_join()`](https://c-matos.github.io/geopt/reference/pt_join.md)
adds.

All datasets carry `nuts1_cod` and `nuts1`, so a health map can be
filtered to the mainland, the Açores (`"PT2"`) or Madeira (`"PT3"`), and
`pt_aces` and `pt_aces_municipio` carry their `reg_saude`. They carry no
other region column, because no other is the same throughout every unit:
ULS Médio Tejo, for example, is split between two regiões de saúde.

## See also

[`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md)
for the geometry-free lookup table,
[`get_map()`](https://c-matos.github.io/geopt/reference/get_map.md) for
composed maps with island insets.
