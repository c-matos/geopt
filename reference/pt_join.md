# Add official codes and administrative context to a data frame

Matches a column of `data` against the
[pt_registry](https://c-matos.github.io/geopt/reference/pt_registry.md)
(via
[`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md))
and appends the administrative columns that are well-defined at that
level: codes, names of parent units, the NUTS regions of one revision,
and health mappings of both vintages. A column is only appended when its
value is constant within each matched unit. If you have data by
municipio, for example, pt_join will add `uls_municipio` and not `uls`.

## Usage

``` r
pt_join(
  data,
  by,
  fuzzy = FALSE,
  aliases = NULL,
  admin_vintage = NULL,
  nuts_vintage = NULL,
  quiet = FALSE
)
```

## Arguments

- data:

  A data.frame.

- by:

  Which column of `data` identifies the unit, and what it contains.
  Forms:

  - `"municipio"` – the column `municipio` in `data` holds municipality
    names or DTMN codes. Any keyword from the `by` registry works:
    `freguesia`/`dtmnfr`, `municipio`/`concelho`/`dtmn`,
    `distrito`/`dt`, `nuts1`-`nuts3` (`*_cod`), `uls`, `reg_saude`,
    `aces`, `uls_municipio`, `aces_municipio`.

  - `c(municipio = "muni_name")` – similar to tidyverse join logic. This
    example assumes the municipio column in your data is called
    `muni_name`.

  - `c(freguesia = "freg", municipio = "mun")` – first entry is the unit
    to match; further entries give context columns used to disambiguate.
    In this example, freguesia names scoped by municipio

- fuzzy, aliases, quiet:

  Passed to
  [`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md).

- admin_vintage:

  Which administrative vintage `data` is on: `"2025"`, `"2013"`,
  `"2011"`, `"2001"`, or `"auto"` to infer it from the `by` column.
  Leave it out for the newest (`"2025"`). Ignored at the health levels,
  which exist on the current map only. See *Vintages*.

- nuts_vintage:

  Which NUTS revision the NUTS columns are: `"2024"`, `"2013"` or
  `"2002"`. Leave it out for the newest (`"2024"`). See *Vintages*.

## Value

`data` with the matched code column and administrative columns appended.
Columns already present in `data` are not overwritten. The match report
is attached and retrievable with
[`pt_match_report()`](https://c-matos.github.io/geopt/reference/pt_match_report.md).

## Vintages

`admin_vintage` says which freguesia map `data` is on, and the codes and
names appended are that map's. INE publishes freguesias on the 2013 map,
so its data joins with `admin_vintage = "2013"` (or `"auto"`) and keeps
its 2013 codes; on the default, the current map, the uniões split in
2025 would not match. Health mappings are recorded on the current map,
so on an earlier one they are reached through shared territory, as in
[`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md):
a unit whose territory now lies in more than one ULS gets `NA`.

`nuts_vintage` says which NUTS revision the NUTS columns are, and at a
NUTS level which revision `by` is matched against.

## See also

[`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md),
[`get_map()`](https://c-matos.github.io/geopt/reference/get_map.md)
(which joins directly onto geometry)

## Examples

``` r
df <- data.frame(concelho = c("Porto", "Lagoa (Acores)"), value = 1:2)
pt_join(df, by = c(municipio = "concelho"))
#> pt_join: 2/2 row(s) matched at municipio level.
#>         concelho value dtmn municipio dt      distrito_ilha nuts1_cod
#> 1          Porto     1 1312     Porto 13              Porto       PT1
#> 2 Lagoa (Acores)     2 4201     Lagoa 42 Ilha de São Miguel       PT2
#>                        nuts1 nuts2_cod                      nuts2 nuts3_cod
#> 1                 Continente      PT11                      Norte     PT11A
#> 2 Região Autónoma dos Açores      PT20 Região Autónoma dos Açores     PT200
#>                         nuts3 reg_saude                uls_municipio
#> 1 Área Metropolitana do Porto     Norte ULS Santo António + São João
#> 2  Região Autónoma dos Açores    Açores               USI São Miguel
#>   reg_saude_2022                        aces_municipio
#> 1          Norte ACES Porto Ocidental + Porto Oriental
#> 2         Açores                        USI São Miguel

# Data on the 2013 map, as INE publishes it: the uniao of Conde and
# Gandarela (Guimaraes) was split in 2025, so its code only exists there
ine <- data.frame(dtmnfr = "030882", value = 3)
pt_join(ine, by = "dtmnfr", admin_vintage = "2013")
#> pt_join: 1/1 row(s) matched at freguesia level.
#>   dtmnfr value                                 freguesia
#> 1 030882     3 União das freguesias de Conde e Gandarela
#>   designacao_simplificada dtmn municipio dt distrito_ilha nuts1_cod      nuts1
#> 1       Conde e Gandarela 0308 Guimarães 03         Braga       PT1 Continente
#>   nuts2_cod nuts2 nuts3_cod nuts3 reg_saude          uls uls_municipio
#> 1      PT11 Norte     PT119   Ave     Norte ULS Alto Ave  ULS Alto Ave
#>   reg_saude_2022                                  aces
#> 1          Norte ACES Guimarães/Vizela/Terras de Basto
#>                          aces_municipio
#> 1 ACES Guimarães/Vizela/Terras de Basto

# The NUTS regions of the 2013 revision, under which Lisboa was PT17
pt_join(data.frame(concelho = "Lisboa"), by = c(municipio = "concelho"),
        nuts_vintage = "2013")
#> pt_join: 1/1 row(s) matched at municipio level.
#>   concelho dtmn municipio dt distrito_ilha nuts1_cod      nuts1 nuts2_cod
#> 1   Lisboa 1106    Lisboa 11        Lisboa       PT1 Continente      PT17
#>                          nuts2 nuts3_cod                        nuts3 reg_saude
#> 1 Área Metropolitana de Lisboa     PT170 Área Metropolitana de Lisboa       LVT
#>                                                     uls_municipio
#> 1 ULS Lisboa Ocidental + Loures-Odivelas + Santa Maria + São José
#>   reg_saude_2022                                               aces_municipio
#> 1            LVT ACES Lisboa Central + Lisboa Norte + Lisboa Ocidental/Oeiras
```
