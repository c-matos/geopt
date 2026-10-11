# Retrieve the match report from a pt_match result

Retrieve the match report from a pt_match result

## Usage

``` r
pt_match_report(x)
```

## Arguments

- x:

  The return value of
  [`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md).

## Value

A data.frame with one row per input: `input`, `matched_name`, `code`,
`method` (`"exact"`, `"loose"` — matched once Portuguese particles were
ignored, `"alias"`, `"historic"` — matched a name from a vintage other
than the one requested, such as a pre-2013 name, `"fuzzy"`, `"code"`,
`"ambiguous"`, `"context_unrecognized"` — the `context` is not a unit
geopt knows, `"unmatched"`, `"empty"`), and `dist` (fuzzy matches only).

## Examples

``` r
m <- pt_match(c("Porto", "Lagoa"))
#> Warning: pt_match: 1 ambiguous name(s) returned NA. Pass `context` or use codes.
#>   'Lagoa' (2 candidates: Faro, Ilha de São Miguel)
pt_match_report(m)
#>   input matched_name code    method dist
#> 1 Porto        Porto 1312     exact   NA
#> 2 Lagoa         <NA> <NA> ambiguous   NA
```
