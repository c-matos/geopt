# Joining data

``` r

library(geopt)
```

Portuguese data usually identifies places in one of three ways: by
official code (the 4-digit DTMN for a municipality, the 6-digit DTMNFR
for a freguesia), by name, in whatever spelling the source uses, or by
NUTS code. This guide shows how to get each of them onto a map, and how
to deal with the usual problems: repeated names, lost leading zeros and
spelling variants.

## Join by code when available

Codes are unambiguous, so use them whenever possible:

``` r

df <- data.frame(dtmn = c("1106", "1312"), value = c(20, 10))
m <- get_map("municipio", data = df, by = "dtmn")
#> get_map: 306 boundaries have no data row (NA fill).
```

Excel often turns `"0115"` into `115`. geopt restores the leading zeros
when it joins. To fix a column directly:

``` r

pt_pad_code(c(115, 1106), "municipio")
#> [1] "0115" "1106"
```

## Join by name

Names are matched by
[`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md),
which ignores accents, case and punctuation, and reads the abbreviations
`S.`, `Sta.` and `Sto.` as São, Santa and Santo:

``` r

df <- data.frame(concelho = c("porto", "CÂMARA DE LOBOS", "S. João da Madeira"),
                 value = c(1, 2, 3))
pt_match(df$concelho)
#> [1] "1312" "3102" "0116"
#> attr(,"report")
#>                input        matched_name code method dist
#> 1              porto               Porto 1312  exact   NA
#> 2    CÂMARA DE LOBOS     Câmara de Lobos 3102  exact   NA
#> 3 S. João da Madeira São João da Madeira 0116  exact   NA
```

### Repeated names

Some names are shared: two municipalities are called **Lagoa** (one in
Faro district, one on São Miguel), and 196 freguesia names are used by
more than one freguesia. A name that fits more than one unit returns
`NA` with a warning. geopt never guesses:

``` r

pt_match("Lagoa")
#> Warning: pt_match: 1 ambiguous name(s) returned NA. Pass `context` or use codes.
#>   'Lagoa' (2 candidates: Faro, Ilha de São Miguel)
#> [1] NA
#> attr(,"report")
#>   input matched_name code    method dist
#> 1 Lagoa         <NA> <NA> ambiguous   NA
```

There are two ways to say which one is meant. Add the region in brackets
after the name, as INE’s files often do, or pass a `context`, the unit
it belongs to:

``` r

pt_match(c("Lagoa (Faro)", "Lagoa (Açores)", "Lagoa (R.A.A.)"), quiet = TRUE)
#> [1] "0806" "4201" "4201"
#> attr(,"report")
#>            input matched_name code method dist
#> 1   Lagoa (Faro)        Lagoa 0806  exact   NA
#> 2 Lagoa (Açores)        Lagoa 4201  exact   NA
#> 3 Lagoa (R.A.A.)        Lagoa 4201  exact   NA

pt_match("Lagoa", context = "Faro", quiet = TRUE)
#> [1] "0806"
#> attr(,"report")
#>   input matched_name code method dist
#> 1 Lagoa        Lagoa 0806  exact   NA
```

At freguesia level, repeated names are common, so always give the
municipality as context. No municipality has two freguesias with the
same name, so this always settles it:

``` r

df <- data.frame(freg = c("Pinheiro", "Pinheiro"),
                 mun  = c("Guimarães", "Castro Daire"))
pt_match(df$freg, level = "freguesia", context = df$mun, quiet = TRUE)
#> [1] "030836" "180319"
#> attr(,"report")
#>      input matched_name   code method dist
#> 1 Pinheiro     Pinheiro 030836  exact   NA
#> 2 Pinheiro     Pinheiro 180319  exact   NA
```

### Names from older data

In 2013, about half of all freguesias were merged into *uniões de
freguesias*, and in 2025 some of them were split again. Names from
before 2013 match the freguesia that covers the same place today, so a
file from an older census joins without being converted first:

``` r

pt_match(c("Sé", "Maximinos"), level = "freguesia",
         context = "Braga", quiet = TRUE)
#> [1] "030364" "030364"
#> attr(,"report")
#>       input      matched_name   code   method dist
#> 1        Sé        Braga (Sé) 030364 historic   NA
#> 2 Maximinos Braga (Maximinos) 030364 historic   NA
```

Both are now part of
`União das freguesias de Braga (Maximinos, Sé e Cividade)`. The report
marks these matches as `"historic"`, which shows how much of a join
relied on old names. A name that is still in use always takes priority
over an old one, so this never changes what a current name matches. Pass
`historic = FALSE` to accept only current names.

To get the code each freguesia had before 2013 instead, pass
`admin_vintage = "2011"` (the map the 2011 census used). Each old
freguesia then keeps its own code, rather than sharing the code of the
união it joined:

``` r

pt_match(c("Sé", "Maximinos"), level = "freguesia", context = "Braga",
         admin_vintage = "2011", quiet = TRUE)
#> [1] "030352" "030324"
#> attr(,"report")
#>       input      matched_name   code method dist
#> 1        Sé        Braga (Sé) 030352  exact   NA
#> 2 Maximinos Braga (Maximinos) 030324  exact   NA
```

To convert the *values* in a dataset between these versions of the map,
see
[`pt_recode()`](https://c-matos.github.io/geopt/reference/pt_recode.md)
and
[`vignette("vintages")`](https://c-matos.github.io/geopt/articles/vintages.md).

### Spelling variants and typos

If a source consistently spells a name its own way, pass `aliases`:

``` r

pt_match("VN Gaia", aliases = c("VN Gaia" = "Vila Nova de Gaia"), quiet = TRUE)
#> [1] "1317"
#> attr(,"report")
#>     input      matched_name code method dist
#> 1 VN Gaia Vila Nova de Gaia 1317  alias   NA
```

For typos, turn on fuzzy matching (this needs the stringdist package).
It only runs on names that didn’t match exactly, only accepts a
candidate that is clearly the closest, and reports every match it makes:

``` r

pt_match("Guimaraess", fuzzy = TRUE)
#> pt_match: 1 fuzzy match(es):
#>   'Guimaraess' -> 'Guimarães' (dist 1)
#> [1] "0308"
#> attr(,"report")
#>        input matched_name code method dist
#> 1 Guimaraess    Guimarães 0308  fuzzy    1
```

### Checking what matched

Every result from
[`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md)
and [`pt_join()`](https://c-matos.github.io/geopt/reference/pt_join.md)
carries a report. Check it before trusting a join:

``` r

res <- pt_match(c("Porto", "Lagoa", "Atlantis"), quiet = TRUE)
pt_match_report(res)
#>      input matched_name code    method dist
#> 1    Porto        Porto 1312     exact   NA
#> 2    Lagoa         <NA> <NA> ambiguous   NA
#> 3 Atlantis         <NA> <NA> unmatched   NA
```

The `method` column says how each input was matched, or why it wasn’t:

| `method` | Meaning |
|----|----|
| `code` | the input was an official code |
| `exact` | the name matched, once accents, case and punctuation were ignored |
| `loose` | the name matched once small words like “da” or “dos” were ignored |
| `historic` | the name is from an older map, such as one from before 2013 |
| `alias` | the name matched through `aliases` |
| `fuzzy` | a close spelling matched (only with `fuzzy = TRUE`) |
| `ambiguous` | more than one unit has this name: add a context |
| `context_unrecognized` | the given context isn’t a unit geopt knows |
| `unmatched` | no unit has this name |
| `empty` | the input was empty or `NA` |

## Three ways to join

**`get_map(data =, by =)`** joins straight onto the boundaries, for
maps:

``` r

m <- get_map("municipio", data = df, by = c(municipio = "concelho"))
```

**[`pt_join()`](https://c-matos.github.io/geopt/reference/pt_join.md)**
adds to the data frame the codes and the regions each unit belongs to,
for work that doesn’t need a map. It only adds columns that have a
single value for each unit at the level joined on. Some municipalities
are split between several ULS, for example, so a join by municipality
gets `uls_municipio` rather than `uls` (see
[`vignette("health-geographies")`](https://c-matos.github.io/geopt/articles/health-geographies.md)):

``` r

df <- data.frame(concelho = c("Porto", "Águeda"), value = c(1, 2))
out <- pt_join(df, by = c(municipio = "concelho"))
#> pt_join: 2/2 row(s) matched at municipio level.
names(out)
#>  [1] "concelho"       "value"          "dtmn"           "municipio"     
#>  [5] "dt"             "distrito_ilha"  "nuts1_cod"      "nuts1"         
#>  [9] "nuts2_cod"      "nuts2"          "nuts3_cod"      "nuts3"         
#> [13] "reg_saude"      "uls_municipio"  "reg_saude_2022" "aces_municipio"
```

Like
[`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md),
[`pt_join()`](https://c-matos.github.io/geopt/reference/pt_join.md)
takes `admin_vintage` and `nuts_vintage`. INE publishes freguesias on
the 2013 map, so for its data `admin_vintage = "2013"` (or `"auto"`)
keeps the 2013 codes and adds that map’s names, and `nuts_vintage` picks
the NUTS revision of the regions added:

``` r

ine <- data.frame(dtmnfr = "030882", value = 3)  # a união split in 2025
pt_join(ine, by = "dtmnfr", admin_vintage = "2013")[, c("dtmnfr", "freguesia", "municipio")]
#> pt_join: 1/1 row(s) matched at freguesia level.
#>   dtmnfr                                 freguesia municipio
#> 1 030882 União das freguesias de Conde e Gandarela Guimarães
```

**[`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md)**
returns the table of codes and regions itself, as a plain data frame,
ready for any other kind of join. Health columns are only added when
`health_vintage` says which version of the health map to use:

``` r

codes <- pt_lookup(health_vintage = "2024")
head(codes[, c("dtmnfr", "freguesia", "dtmn", "municipio", "nuts3_cod", "unit")])
#>   dtmnfr                                         freguesia dtmn municipio
#> 1 010103                                    Aguada de Cima 0101    Águeda
#> 2 010109                                       Fermentelos 0101    Águeda
#> 3 010112                                Macinhata do Vouga 0101    Águeda
#> 4 010119                                  Valongo do Vouga 0101    Águeda
#> 5 010124      União das freguesias de Recardães e Espinhel 0101    Águeda
#> 6 010125 União das freguesias de Travassô e Óis da Ribeira 0101    Águeda
#>   nuts3_cod                 unit
#> 1     PT191 ULS Região de Aveiro
#> 2     PT191 ULS Região de Aveiro
#> 3     PT191 ULS Região de Aveiro
#> 4     PT191 ULS Região de Aveiro
#> 5     PT191 ULS Região de Aveiro
#> 6     PT191 ULS Região de Aveiro
```

## Cleaning names directly

The name cleaning that
[`pt_match()`](https://c-matos.github.io/geopt/reference/pt_match.md)
uses is available as
[`pt_normalize()`](https://c-matos.github.io/geopt/reference/pt_normalize.md),
so the same rules can be applied to any column before a manual join:

``` r

pt_normalize(c("S. Jorge", "SÃO JORGE", "Sao-Jorge"))
#> [1] "sao jorge" "sao jorge" "sao jorge"
```
