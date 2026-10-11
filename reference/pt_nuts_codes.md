# NUTS classification of Portuguese municípios, every revision

One row per município per NUTS revision. NUTS revisions are set at
European level and are **independent of the administrative vintage**:
INE publishes the same 3092-freguesia set under both the 2013 and the
2024 revision.

## Usage

``` r
pt_nuts_codes
```

## Format

A data.frame with 924 rows and columns:

- nuts_vintage:

  `"2002"`, `"2013"` or `"2024"`.

- dtmn:

  4-digit município code.

- nuts1_cod, nuts1:

  NUTS I code and name.

- nuts2_cod, nuts2:

  NUTS II code and name.

- nuts3_cod, nuts3:

  NUTS III code and name.

## Source

INE / Eurostat NUTS nomenclature. NUTS II 2002 names come from INE's own
indicator dimension labels.

## Details

Keyed on `dtmn` because every NUTS revision Portugal has had is a
regrouping of the same 308 municípios — stable since the 1998 creation
of Trofa, Vizela and Odivelas. NUTS is therefore a function of
`(dtmn, nuts_vintage)` and not a freguesia-level attribute at all, which
is why 308 rows per revision is the whole fact.

## Revisions

- `"2024"`:

  9 NUTS II, 26 NUTS III. Splits the former Lisboa region into Grande
  Lisboa, Península de Setúbal and Oeste e Vale do Tejo.

- `"2013"`:

  7 NUTS II, 25 NUTS III, the CIM/AM-based sub-regions.

- `"2002"`:

  7 NUTS II, 30 NUTS III. `PT17` is `"Lisboa"` here and
  `"Área Metropolitana de Lisboa"` from 2013.

## See also

[`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md),
[pt_registry](https://c-matos.github.io/geopt/reference/pt_registry.md)

## Examples

``` r
# how a municipio's NUTS III changed across revisions
pt_nuts_codes[pt_nuts_codes$dtmn == "1106", c("nuts_vintage", "nuts3")]
#>     nuts_vintage                        nuts3
#> 153         2002                Grande Lisboa
#> 461         2013 Área Metropolitana de Lisboa
#> 769         2024                Grande Lisboa
```
