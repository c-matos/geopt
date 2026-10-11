# Correspondence between two administrative vintages

Which units of one vintage correspond to which of another, and how each
changed. Derived from shared territory rather than stored, so any pair
of vintages works and nothing goes stale when a new one is added.

## Usage

``` r
pt_crosswalk(
  from = "2013",
  to = NULL,
  level = c("freguesia", "municipio", "distrito")
)
```

## Arguments

- from, to:

  Administrative vintages: `"2001"`, `"2011"`, `"2013"` or `"2025"`.
  `from` defaults to `"2013"`; leave `to` out for the newest (`"2025"`).

- level:

  Which units to relate. Only `"freguesia"` changes across these
  vintages; `"municipio"` and `"distrito"` are included for
  completeness.

## Value

A data.frame with one row per corresponding pair: `from`, `to`,
`name_from`, `name_to`, `relation`.

## Codes are vintage-local

A DTMNFR identifies a unit *within its own vintage only*. None of the
302 freguesias restored in 2025 reused its pre-2013 code, so this table
— not string comparison — is the only safe way to relate codes across
vintages.

## Relations

`relation` is computed from the correspondence itself:

- `unchanged`:

  same territory, same code, same name.

- `renamed`:

  same territory and code, different name.

- `renumbered`:

  same territory, different code. Colos kept its territory across the
  2025 reform and changed only its code (`021118` → `021124`).

- `merged`:

  several `from` units became one — the 2013 uniões.

- `split`:

  one `from` unit became several — the 2025 reposição.

## See also

[`pt_recode()`](https://c-matos.github.io/geopt/reference/pt_recode.md)
to carry values across vintages,
[pt_registry](https://c-matos.github.io/geopt/reference/pt_registry.md)
for the units themselves.

## Examples

``` r
x <- pt_crosswalk("2013", "2025")
table(x$relation)
#> 
#> renumbered      split  unchanged 
#>          1        301       2957 

# what became of the 2013 "030882" code
x[x$from == "030882", ]
#>       from     to                                 name_from   name_to relation
#> 490 030882 030895 União das freguesias de Conde e Gandarela     Conde    split
#> 492 030882 030897 União das freguesias de Conde e Gandarela Gandarela    split
```
