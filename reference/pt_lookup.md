# Administrative, NUTS and health codes for one choice of each vintage

Assembles a wide lookup table from
[pt_registry](https://c-matos.github.io/geopt/reference/pt_registry.md),
[pt_nuts_codes](https://c-matos.github.io/geopt/reference/pt_nuts_codes.md)
and
[pt_health_codes](https://c-matos.github.io/geopt/reference/pt_health_codes.md).
Each axis is chosen independently, because they are independent: the
same freguesia set is published by INE under more than one NUTS
revision, and a NUTS revision says nothing about which freguesias exist.

## Usage

``` r
pt_lookup(
  level = "freguesia",
  admin_vintage = NULL,
  nuts_vintage = NULL,
  health_vintage = NULL
)
```

## Arguments

- level:

  Grain of the result: `"freguesia"` (default), `"municipio"`,
  `"distrito"`, `"nuts1"`, `"nuts2"`, `"nuts3"`, or the health levels
  `"reg_saude"`, `"uls"`, `"aces"`, `"uls_municipio"`,
  `"aces_municipio"`. Coarser levels return one row per unit with only
  the columns that are constant within it. A health level reads its own
  health geography unless `health_vintage` says otherwise (see
  *Vintages*).

- admin_vintage:

  Which administrative unit set: `"2025"`, `"2013"`, `"2011"` or
  `"2001"`. Leave it out for the newest (`"2025"`).

- nuts_vintage:

  Which NUTS revision: `"2024"`, `"2013"` or `"2002"`. Leave it out for
  the newest (`"2024"`); `NA` drops the NUTS columns.

- health_vintage:

  Which health geography: `"2024"` or `"2022"`. Unlike the other two,
  leaving it out omits the health columns, except at a health `level`.
  ULS exist only in `"2024"` and ACES only in `"2022"`, so
  `level = "uls"` with `"2022"` returns that geography's ACES, and
  `level = "aces"` with `"2024"` its ULS (likewise for the `*_municipio`
  levels), with a warning.

## Value

A data.frame, one row per unit of `level`.

## Vintages

`admin_vintage` selects which administrative units exist:

- `"2025"` — 3259 freguesias, the current set (Lei 25-A/2025, in force
  from the 2025 autárquicas, which restored units aggregated in 2013).

- `"2013"` — 3092 freguesias (Lei 11-A/2013). **This is what INE still
  publishes**, including on indicators labelled "NUTS - 2024".

- `"2011"` — 4260 freguesias, the map the 2011 census used, in force
  from 2004 until the 2013 reform.

- `"2001"` — 4241 freguesias, the map the 2001 census used. 22
  freguesias were created and 3 dissolved between the two censuses.

The pre-2013 maps are named after the census that recorded them, because
neither was made by a single law. The 1991 census used an earlier map
again (4208 freguesias in 305 municípios, before Odivelas, Trofa and
Vizela were created in 1998), which geopt does not have.

`nuts_vintage` selects the NUTS revision: `"2024"` (9 NUTS II, 26 NUTS
III), `"2013"` (7 / 25) or `"2002"` (7 / 30).

`health_vintage` selects the health geography: `"2024"` (regiões de
saúde + ULS) or `"2022"` (the former ARS + ACES). Health columns are
omitted unless asked for, or unless `level` is a health level: those
read the geography their units belong to, `"2024"` for `"reg_saude"`,
`"uls"` and `"uls_municipio"`, and `"2022"` for `"aces"` and
`"aces_municipio"`.

## Codes are vintage-local

A DTMNFR identifies a unit *within its own vintage only*. None of the
302 freguesias restored in 2025 reused its pre-2013 code, so comparing a
code across vintages — or joining data of one vintage onto codes of
another — silently mismatches. Use
[`pt_crosswalk()`](https://c-matos.github.io/geopt/reference/pt_crosswalk.md)
to convert, and
[`pt_recode()`](https://c-matos.github.io/geopt/reference/pt_recode.md)
to carry values across.

## See also

[pt_registry](https://c-matos.github.io/geopt/reference/pt_registry.md),
[pt_nuts_codes](https://c-matos.github.io/geopt/reference/pt_nuts_codes.md),
[pt_health_codes](https://c-matos.github.io/geopt/reference/pt_health_codes.md),
[`pt_crosswalk()`](https://c-matos.github.io/geopt/reference/pt_crosswalk.md),
[`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md)

## Examples

``` r
head(pt_lookup())
#>   dtmnfr                                         freguesia
#> 1 010103                                    Aguada de Cima
#> 2 010109                                       Fermentelos
#> 3 010112                                Macinhata do Vouga
#> 4 010119                                  Valongo do Vouga
#> 5 010124      União das freguesias de Recardães e Espinhel
#> 6 010125 União das freguesias de Travassô e Óis da Ribeira
#>     designacao_simplificada dtmn municipio dt distrito_ilha nuts1_cod
#> 1            Aguada de Cima 0101    Águeda 01        Aveiro       PT1
#> 2               Fermentelos 0101    Águeda 01        Aveiro       PT1
#> 3        Macinhata do Vouga 0101    Águeda 01        Aveiro       PT1
#> 4          Valongo do Vouga 0101    Águeda 01        Aveiro       PT1
#> 5      Recardães e Espinhel 0101    Águeda 01        Aveiro       PT1
#> 6 Travassô e Óis da Ribeira 0101    Águeda 01        Aveiro       PT1
#>        nuts1 nuts2_cod  nuts2 nuts3_cod            nuts3
#> 1 Continente      PT19 Centro     PT191 Região de Aveiro
#> 2 Continente      PT19 Centro     PT191 Região de Aveiro
#> 3 Continente      PT19 Centro     PT191 Região de Aveiro
#> 4 Continente      PT19 Centro     PT191 Região de Aveiro
#> 5 Continente      PT19 Centro     PT191 Região de Aveiro
#> 6 Continente      PT19 Centro     PT191 Região de Aveiro

# the combination INE actually publishes: 2013 freguesias, 2024 NUTS
head(pt_lookup(admin_vintage = "2013", nuts_vintage = "2024"))
#>   dtmnfr                                       freguesia
#> 1 010103                                  Aguada de Cima
#> 2 010109                                     Fermentelos
#> 3 010112                              Macinhata do Vouga
#> 4 010119                                Valongo do Vouga
#> 5 010121       União das freguesias de Águeda e Borralha
#> 6 010122 União das freguesias de Barrô e Aguada de Baixo
#>   designacao_simplificada dtmn municipio dt distrito_ilha nuts1_cod      nuts1
#> 1          Aguada de Cima 0101    Águeda 01        Aveiro       PT1 Continente
#> 2             Fermentelos 0101    Águeda 01        Aveiro       PT1 Continente
#> 3      Macinhata do Vouga 0101    Águeda 01        Aveiro       PT1 Continente
#> 4        Valongo do Vouga 0101    Águeda 01        Aveiro       PT1 Continente
#> 5       Águeda e Borralha 0101    Águeda 01        Aveiro       PT1 Continente
#> 6 Barrô e Aguada de Baixo 0101    Águeda 01        Aveiro       PT1 Continente
#>   nuts2_cod  nuts2 nuts3_cod            nuts3
#> 1      PT19 Centro     PT191 Região de Aveiro
#> 2      PT19 Centro     PT191 Região de Aveiro
#> 3      PT19 Centro     PT191 Região de Aveiro
#> 4      PT19 Centro     PT191 Região de Aveiro
#> 5      PT19 Centro     PT191 Região de Aveiro
#> 6      PT19 Centro     PT191 Região de Aveiro

# one row per municipio, with its 2002 NUTS grouping
head(pt_lookup("municipio", nuts_vintage = "2002"))
#>   dtmn          municipio dt distrito_ilha nuts1_cod      nuts1 nuts2_cod
#> 1 0101             Águeda 01        Aveiro       PT1 Continente      PT16
#> 2 0102 Albergaria-a-Velha 01        Aveiro       PT1 Continente      PT16
#> 3 0103             Anadia 01        Aveiro       PT1 Continente      PT16
#> 4 0104             Arouca 01        Aveiro       PT1 Continente      PT11
#> 5 0105             Aveiro 01        Aveiro       PT1 Continente      PT16
#> 6 0106   Castelo de Paiva 01        Aveiro       PT1 Continente      PT11
#>    nuts2 nuts3_cod               nuts3
#> 1 Centro     PT161         Baixo Vouga
#> 2 Centro     PT161         Baixo Vouga
#> 3 Centro     PT161         Baixo Vouga
#> 4  Norte     PT116 Entre Douro e Vouga
#> 5 Centro     PT161         Baixo Vouga
#> 6  Norte     PT115              Tâmega

# one row per ULS (the 2024 health geography, without asking)
head(pt_lookup("uls"))
#>                                unit nuts1_cod                      nuts1
#> 1                CS Câmara de Lobos       PT3 Região Autónoma da Madeira
#> 2 CS Dr. Francisco Rodrigues Jardim       PT3 Região Autónoma da Madeira
#> 3                 CS Funchal Zona I       PT3 Região Autónoma da Madeira
#> 4                CS Funchal Zona II       PT3 Região Autónoma da Madeira
#> 5                     CS Santa Cruz       PT3 Região Autónoma da Madeira
#> 6                     CS Zona Leste       PT3 Região Autónoma da Madeira
```
