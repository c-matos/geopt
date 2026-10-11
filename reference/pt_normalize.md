# Normalize Portuguese place names for matching

Lowercases, expands common abbreviations (`S.` -\> `Sao`, `Sta.` -\>
`Santa`, `Sto.` -\> `Santo`), strips accents, and collapses punctuation
and whitespace, so that variant spellings of the same unit produce
identical keys: `"S. Jorge"`, `"são jorge"`, and `"Sao-Jorge"` all
normalize to `"sao jorge"`.

## Usage

``` r
pt_normalize(x)
```

## Arguments

- x:

  Character vector of names.

## Value

Character vector of normalized names.

## Details

This is the normalization used internally by
[`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md);
it is exported so the same rules can be applied to arbitrary user
columns.

## Examples

``` r
pt_normalize(c("S. Jorge", "SÃO JORGE", "Sao-Jorge"))
#> [1] "sao jorge" "sao jorge" "sao jorge"
```
