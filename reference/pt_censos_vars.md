# Census variables available from get_censos()

Dictionary of the census variables embedded in the INE geographies
returned by
[`get_censos()`](https://c-matos.github.io/geopt/reference/get_censos.md),
with INE's Portuguese descriptions. One row per variable per census year
and level, derived from the actual GeoPackage columns (INE's description
CSVs use spelling variants of the column names, which are matched to
them).

## Usage

``` r
pt_censos_vars
```

## Format

A data.frame with columns:

- year:

  Census year (1991, 2001, 2011, 2021).

- level:

  `"subseccao"`, `"seccao"`, or `"grid"`.

- variable:

  Column name as it appears in the returned object.

- description:

  INE's description (Portuguese).

## Source

INE, Censos — importação de dados alfanuméricos e geográficos (BGRI,
GRID e Lugares): <https://mapas.ine.pt/download/index2021.phtml>

## Details

The variable sets differ widely by year: 2021 subsecções carry 32
variables, 2011 subsecções 122, 1991/2001 subsecções seven basic counts,
2021 secções ~180 variables, and the 2021 grid ten.

## See also

[`get_censos()`](https://c-matos.github.io/geopt/reference/get_censos.md)

## Examples

``` r
# What is available for the 2011 census?
vars <- pt_censos_vars[pt_censos_vars$year == 2011, ]
head(vars[, c("variable", "description")])
#>                         variable                          description
#> 15  F_N_EDIFICIOS_5OU_MAIS_PISOS        Edifícios com 5 ou mais pisos
#> 16                 N_ALOJAMENTOS                 Total de Alojamentos
#> 17      N_ALOJAMENTOS_COLECTIVOS               Alojamentos colectivos
#> 18   N_ALOJAMENTOS_FAM_CLASSICOS     Alojamentos familiares clássicos
#> 19 N_ALOJAMENTOS_FAM_N_CLASSICOS Alojamentos familiares não clássicos
#> 20      N_ALOJAMENTOS_FAMILIARES               Alojamentos familiares
```
