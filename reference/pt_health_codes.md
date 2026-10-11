# Health geography of Portuguese freguesias, both vintages

One row per freguesia per health vintage. Keyed on the freguesia rather
than the município because `unit` varies *within* a município in five of
them — the reason this cannot live alongside
[pt_nuts_codes](https://c-matos.github.io/geopt/reference/pt_nuts_codes.md),
which is município grained.

## Usage

``` r
pt_health_codes
```

## Format

A data.frame with 6518 rows and columns:

- health_vintage:

  `"2022"` or `"2024"`.

- dtmnfr:

  6-digit freguesia code, current vintage.

- reg_saude:

  Região de saúde (2024) or the former ARS (2022).

- scheme:

  `"uls"` for 2024, `"aces"` for 2022 — different concepts, not two
  names for one thing.

- unit:

  The local unit: a ULS or an ACES.

- unit_municipio:

  Município-grained approximation of `unit`.

## Source

Decreto-Lei 102/2023 (ULS); prior ARS/ACES organization.

## Details

Mappings are recorded against the current (2025) freguesia set;
[`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md)
reaches them from an earlier `admin_vintage`.

## Vintages

- `"2024"`:

  The reform: 5 regiões de saúde on the mainland plus the island
  services, and ULS (Unidades Locais de Saúde) as the local unit.

- `"2022"`:

  What it superseded: the former ARS, and ACES (Agrupamentos de Centros
  de Saúde) as the local unit.

`unit_municipio` is the unit to use for data by município. Units that
share a município are merged into one pseudo-unit, and merging follows
chains, so it can differ from `unit` even in a município that lies whole
in one unit. For example, ULS São José also covers part of Loures, which
merges ULS Loures-Odivelas with Lisboa's three ULS, and Odivelas gets
the merged unit too. Everywhere else it equals `unit`.

## See also

[`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md),
[pt_registry](https://c-matos.github.io/geopt/reference/pt_registry.md)

## Examples

``` r
table(pt_health_codes$health_vintage, pt_health_codes$scheme)
#>       
#>        aces  uls
#>   2022 3259    0
#>   2024    0 3259
```
