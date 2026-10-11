# Convert freguesia-level data between code vintages

Portugal's freguesias were aggregated into "uniões de freguesias" in
2013 and partially de-aggregated in 2025; the maps before 2013 are finer
still. This function converts freguesia-level data between four
vintages: `"2001"` (the map the 2001 census used, 4241 freguesias),
`"2011"` (the map the 2011 census used, 4260), `"2013"` (the uniões,
3092) and `"2025"` (the current map, 3259). The correspondence is
derived from shared territory rather than stored, so any pair of
vintages works; it handles the value semantics explicitly:

## Usage

``` r
pt_recode(
  data,
  by = "dtmnfr",
  from,
  to = NULL,
  values = NULL,
  aggregate = NULL,
  split = c("error", "replicate", "weight"),
  weights = NULL,
  quiet = FALSE
)
```

## Arguments

- data:

  A data.frame with freguesia-level rows.

- by:

  Name of the column in `data` holding the freguesia codes (DTMNFR,
  zero-padding is repaired). Default `"dtmnfr"`.

- from:

  Which vintage the codes in `data` belong to (required): `"2025"` (the
  current map), `"2013"` (the uniões, in force 2013–2025), `"2011"` (the
  map the 2011 census used, in force 2004–2013) or `"2001"` (the map the
  2001 census used). The 1991 census used an earlier map again, which
  geopt does not have.

- to:

  Target vintage, one of the same four. Leave it out for the newest
  (`"2025"`); when `from` is already the newest, `to` must be given.

- values:

  Character vector naming the numeric value columns to convert. Other
  columns are carried along: replicated on splits, kept on merges when
  constant within the group (otherwise set to `NA`). Columns called
  `dtmnfr` or `freguesia` are not carried: the result's own are the
  target vintage's.

- aggregate:

  Function (or named list of functions, one per value column) used to
  combine values on merges, e.g. `sum`. Required when any merge occurs
  and `values` is non-empty.

- split:

  How to distribute values on splits: `"error"` (default),
  `"replicate"`, or `"weight"`.

- weights:

  For `split = "weight"`: `"area"` (proportional to the area of the
  newest vintage's freguesias) or a named numeric vector keyed by the
  target `dtmnfr` (e.g. population).

- quiet:

  Logical. Suppress informational warnings? Default `FALSE`.

## Value

A data.frame with the target vintage's freguesia code (`dtmnfr`) and
name (`freguesia`), followed by the carried and converted columns. The
column names are the same whichever vintage you convert to, as in
[`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md).

## Details

- **finer → coarser (merges),** e.g. `2025` → `2013`, `2011` → `2025`:
  freguesias collapse into a shared unit. Value columns must be
  aggregated, and only values for which aggregation is meaningful may be
  converted (raw counts can be summed; rates and medians cannot) — so
  `aggregate` is required whenever a merge occurs. If only some
  constituents of a target are present in `data`, the aggregate covers
  the present ones and a warning reports the partial groups.

- **coarser → finer (splits),** e.g. `2013` → `2025`, `2025` → `2011`,
  `2001` → `2011` (22 freguesias created between the two censuses): a
  unit's value cannot be exactly disaggregated. You must opt in to a
  strategy: `split = "replicate"` copies the value to every constituent;
  `split = "weight"` distributes it proportionally to `weights`
  (`"area"`, only when splitting towards the newest vintage, or a named
  vector keyed by the target `dtmnfr`, e.g. population). The default
  (`"error"`) refuses.

Codes not present in the relevant crosswalk (including current
freguesias created after 2011, which have no pre-2013 predecessor)
convert to `NA` with a warning. For `"2001"`, the codes the 2001 census
areas use for Vale de Amoreira (`090756`) and Moita (`100117`) are
accepted alongside INE's (`090804`, `101003`).

## See also

[`pt_crosswalk()`](https://c-matos.github.io/geopt/reference/pt_crosswalk.md),
[pt_registry](https://c-matos.github.io/geopt/reference/pt_registry.md),
[`pt_join()`](https://c-matos.github.io/geopt/reference/pt_join.md)

## Examples

``` r
# 2013-era data onto the current map: sum-able counts, split by area
old <- data.frame(dtmnfr = c("010121", "010109"), cases = c(30, 10))
new <- pt_recode(old, from = "2013", values = "cases",
                 split = "weight", weights = "area")
get_map("freguesia", data = new, by = "dtmnfr")
#> get_map: 3256 boundaries have no data row (NA fill).
#> Simple feature collection with 3265 features and 19 fields
#> Geometry type: GEOMETRY
#> Dimension:     XY
#> Bounding box:  xmin: -11.38491 ymin: 36.96188 xmax: -6.189159 ymax: 42.1482
#> Geodetic CRS:  WGS 84
#> First 10 features:
#>    dtmnfr                                                freguesia
#> 1  010103                                           Aguada de Cima
#> 2  010109                                              Fermentelos
#> 3  010112                                       Macinhata do Vouga
#> 4  010119                                         Valongo do Vouga
#> 5  010124             União das freguesias de Recardães e Espinhel
#> 6  010125        União das freguesias de Travassô e Óis da Ribeira
#> 7  010126 União das freguesias de Trofa, Segadães e Lamas do Vouga
#> 8  010127    União das freguesias do Préstimo e Macieira de Alcoba
#> 9  010128                                                   Agadão
#> 10 010129                                          Aguada de Baixo
#>             designacao_simplificada dtmn municipio dt distrito_ilha nuts1_cod
#> 1                    Aguada de Cima 0101    Águeda 01        Aveiro       PT1
#> 2                       Fermentelos 0101    Águeda 01        Aveiro       PT1
#> 3                Macinhata do Vouga 0101    Águeda 01        Aveiro       PT1
#> 4                  Valongo do Vouga 0101    Águeda 01        Aveiro       PT1
#> 5              Recardães e Espinhel 0101    Águeda 01        Aveiro       PT1
#> 6         Travassô e Óis da Ribeira 0101    Águeda 01        Aveiro       PT1
#> 7  Trofa, Segadães e Lamas do Vouga 0101    Águeda 01        Aveiro       PT1
#> 8     Préstimo e Macieira de Alcoba 0101    Águeda 01        Aveiro       PT1
#> 9                            Agadão 0101    Águeda 01        Aveiro       PT1
#> 10                  Aguada de Baixo 0101    Águeda 01        Aveiro       PT1
#>         nuts1 nuts2_cod  nuts2 nuts3_cod            nuts3 area_ha perimetro_km
#> 1  Continente      PT19 Centro     PT191 Região de Aveiro 2839.31           24
#> 2  Continente      PT19 Centro     PT191 Região de Aveiro  858.20           13
#> 3  Continente      PT19 Centro     PT191 Região de Aveiro 3195.44           29
#> 4  Continente      PT19 Centro     PT191 Região de Aveiro 4340.48           36
#> 5  Continente      PT19 Centro     PT191 Região de Aveiro 1991.78           22
#> 6  Continente      PT19 Centro     PT191 Região de Aveiro 1112.19           21
#> 7  Continente      PT19 Centro     PT191 Região de Aveiro 1586.43           23
#> 8  Continente      PT19 Centro     PT191 Região de Aveiro 4172.64           42
#> 9  Continente      PT19 Centro     PT191 Região de Aveiro 3939.87           29
#> 10 Continente      PT19 Centro     PT191 Região de Aveiro  367.33            9
#>    cases geopt_type geopt_label geopt_frame_level
#> 1     NA   boundary        <NA>                NA
#> 2     10   boundary        <NA>                NA
#> 3     NA   boundary        <NA>                NA
#> 4     NA   boundary        <NA>                NA
#> 5     NA   boundary        <NA>                NA
#> 6     NA   boundary        <NA>                NA
#> 7     NA   boundary        <NA>                NA
#> 8     NA   boundary        <NA>                NA
#> 9     NA   boundary        <NA>                NA
#> 10    NA   boundary        <NA>                NA
#>                          geometry
#> 1  POLYGON ((-8.44382 40.51963...
#> 2  POLYGON ((-8.558152 40.5625...
#> 3  POLYGON ((-8.374529 40.6785...
#> 4  POLYGON ((-8.352534 40.6471...
#> 5  POLYGON ((-8.463656 40.5853...
#> 6  POLYGON ((-8.462521 40.5942...
#> 7  POLYGON ((-8.520504 40.6094...
#> 8  POLYGON ((-8.249194 40.6184...
#> 9  POLYGON ((-8.302963 40.4988...
#> 10 POLYGON ((-8.44382 40.51963...

# Current data backwards to 2013 units (counts: aggregate = sum). Conde and
# Gandarela (Guimarães) were one união from 2013 until 2025.
now <- data.frame(dtmnfr = c("030895", "030897"), n = c(12, 7))
pt_recode(now, from = "2025", to = "2013", values = "n", aggregate = sum)
#>   dtmnfr                                 freguesia  n
#> 1 030882 União das freguesias de Conde e Gandarela 19

# 2011-census freguesia counts onto the current map: many old freguesias
# merged into today's uniões, so aggregate = sum
old <- data.frame(dtmnfr = c("010101", "010102"), pop = c(500, 800))
pt_recode(old, from = "2011", to = "2025", values = "pop",
          aggregate = sum)
#>   dtmnfr       freguesia pop
#> 1 010128          Agadão 500
#> 2 010129 Aguada de Baixo 800

# a 2001-census rate onto the 2011 map: Agualva-Cacém became four
# freguesias, and a rate is copied to each
pt_recode(data.frame(dtmnfr = "111101", rate = 12.5), from = "2001",
          to = "2011", values = "rate", split = "replicate")
#>   dtmnfr   freguesia rate
#> 1 111118     Agualva 12.5
#> 2 111119       Cacém 12.5
#> 3 111120 Mira-Sintra 12.5
#> 4 111121  São Marcos 12.5
```
