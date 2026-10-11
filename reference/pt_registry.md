# Portuguese administrative units, every vintage

One row per freguesia per administrative vintage. "Administrative
vintage" means *which units exist*, which changes by Portuguese law and
is unrelated to the NUTS revision (see
[pt_nuts_codes](https://c-matos.github.io/geopt/reference/pt_nuts_codes.md))
or the health geography (see
[pt_health_codes](https://c-matos.github.io/geopt/reference/pt_health_codes.md)).

## Usage

``` r
pt_registry
```

## Format

A data.frame with 14852 rows and columns:

- admin_vintage:

  `"2001"`, `"2011"`, `"2013"` or `"2025"`.

- dtmnfr:

  6-digit freguesia code, unique within the vintage.

- freguesia:

  Official designation. For 2013, the last one the freguesia had on that
  map.

- designacao_simplificada:

  Without the `"União das freguesias de"` prefix. Official for 2025;
  derived by the same rule for 2013, because DGT's list for that map
  leaves 32 uniões unsimplified. Equal to `freguesia` for 2001 and 2011,
  which predate uniões.

- dtmn:

  4-digit município code (the first four of `dtmnfr`).

- municipio:

  Município name.

- dt, distrito_ilha:

  District or island.

## Source

Carta Administrativa Oficial de Portugal (DGT): CAOP 2025, and CAOP 2024
for the 2013 names, which INE's code list for that map matches name for
name; Lei 11-A/2013 and Lei 25-A/2025; INE's freguesia code lists for
the 2001 and 2011 censuses.

## Details

`dtmn` is denormalised onto each row, so a vintage's set of municípios
is the distinct `dtmn` values within it.

## Vintages

- `"2025"`:

  3259 freguesias. Lei 25-A/2025, in force from the 2025 autárquicas,
  which restored units aggregated in 2013.

- `"2013"`:

  3092 freguesias. Lei 11-A/2013. **This is the set INE still
  publishes**, including on indicators labelled "NUTS - 2024" — the
  label refers to the NUTS revision, not to the freguesia set. Each
  freguesia has the last name it had on that map, as in CAOP 2024 and
  INE's tables. 25 were renamed by law while the map was in force
  (`"Buarcos"` became `"Buarcos e São Julião"` in 2015), and
  [`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md)
  recognizes the earlier names too.

- `"2011"`:

  4260 freguesias, the map the 2011 census used, in force from 2004
  until the 2013 reform.

- `"2001"`:

  4241 freguesias, the map the 2001 census used. Between the two
  censuses 22 freguesias were created and 3 dissolved.

The pre-2013 maps are named after the census that recorded them, because
neither was made by a single law; the later ones after their reform.

## Codes are vintage-local

A DTMNFR identifies a unit *within its own vintage only*. None of the
302 freguesias restored in 2025 reused its pre-2013 code, so comparing
codes across vintages, or joining data of one vintage onto codes of
another, silently mismatches. Convert with
[`pt_crosswalk()`](https://c-matos.github.io/geopt/reference/pt_crosswalk.md);
carry values across with
[`pt_recode()`](https://c-matos.github.io/geopt/reference/pt_recode.md).

## See also

[`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md),
[pt_nuts_codes](https://c-matos.github.io/geopt/reference/pt_nuts_codes.md),
[pt_health_codes](https://c-matos.github.io/geopt/reference/pt_health_codes.md),
[`pt_crosswalk()`](https://c-matos.github.io/geopt/reference/pt_crosswalk.md)

## Examples

``` r
table(pt_registry$admin_vintage)
#> 
#> 2001 2011 2013 2025 
#> 4241 4260 3092 3259 

# the set INE publishes today
head(pt_registry[pt_registry$admin_vintage == "2013", ])
#>      admin_vintage dtmnfr                                       freguesia
#> 8502          2013 010103                                  Aguada de Cima
#> 8503          2013 010109                                     Fermentelos
#> 8504          2013 010112                              Macinhata do Vouga
#> 8505          2013 010119                                Valongo do Vouga
#> 8506          2013 010121       União das freguesias de Águeda e Borralha
#> 8507          2013 010122 União das freguesias de Barrô e Aguada de Baixo
#>      designacao_simplificada dtmn municipio dt distrito_ilha
#> 8502          Aguada de Cima 0101    Águeda 01        Aveiro
#> 8503             Fermentelos 0101    Águeda 01        Aveiro
#> 8504      Macinhata do Vouga 0101    Águeda 01        Aveiro
#> 8505        Valongo do Vouga 0101    Águeda 01        Aveiro
#> 8506       Águeda e Borralha 0101    Águeda 01        Aveiro
#> 8507 Barrô e Aguada de Baixo 0101    Águeda 01        Aveiro
```
