# Match place names to official codes

Resolves a character vector of Portuguese administrative unit names to
their official codes using the
[pt_registry](https://c-matos.github.io/geopt/reference/pt_registry.md)
table. Matching is exact on normalized names (see
[`pt_normalize()`](https://c-matos.github.io/geopt/reference/pt_normalize.md)),
optionally preceded by a user-supplied alias lookup and followed by an
opt-in fuzzy pass.

## Usage

``` r
pt_match(
  x,
  level = "municipio",
  to = NULL,
  context = NULL,
  admin_vintage = NULL,
  nuts_vintage = NULL,
  health_vintage = NULL,
  fuzzy = FALSE,
  max_dist = 2,
  aliases = NULL,
  historic = TRUE,
  quiet = FALSE
)
```

## Arguments

- x:

  Character vector of names to match. Codes are automatically padded to
  the correct length, if needed.

- level:

  Which units `x` refers to: `"freguesia"`, `"municipio"` (default),
  `"distrito"`, `"nuts1"`, `"nuts2"`, `"nuts3"`, `"uls"`, `"reg_saude"`,
  `"aces"`, `"uls_municipio"`, `"aces_municipio"`. `"uls"`/`"reg_saude"`
  are the 2024 health reform; `"aces"` is the organization it
  superseded. The `*_municipio` levels merge the units that share a
  municipality, and are matched by the merged name
  (`"ULS Santo António + São João"`).

- to:

  Column of
  [`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md)
  to return, at the vintages requested below. Defaults to the level's
  own code column (`dtmnfr`, `dtmn`, `dt`, `nuts*_cod`, ...). A column
  defined only at a finer level — `"dtmnfr"` for a municipio — yields
  `NA`.

- context:

  Optional character vector (length 1 or `length(x)`) naming a parent
  unit to scope the match. Any vintage of any parent scheme is accepted,
  so INE's own parent column works whichever nomenclature that indicator
  was published under.

- admin_vintage:

  Which administrative vintage to match against and return codes for:
  `"2025"`, `"2013"`, `"2011"`, `"2001"`, or `"auto"` to infer it from
  `x`. Leave it out for the newest (`"2025"`). See *Vintages*.

- nuts_vintage:

  Which NUTS revision `to` is expressed in: `"2024"`, `"2013"` or
  `"2002"`. Also the vintage matched at
  `level = "nuts1"`/`"nuts2"`/`"nuts3"`. Leave it out for the newest
  (`"2024"`).

- health_vintage:

  Which health geography `to` is expressed in: `"2024"` or `"2022"`.
  Leave it out for the newest (`"2024"`). Ignored at `level = "uls"` and
  `"aces"` (and their `*_municipio` forms), which each exist in one
  health geography only; a value that isn't a health vintage at all is
  still an error.

- fuzzy:

  Logical. Enable the fuzzy fallback pass? Default `FALSE`.

- max_dist:

  Maximum string distance for a fuzzy match. Default `2`.

- aliases:

  Optional named character vector mapping variant spellings to either
  canonical names or codes, e.g. `c("VN Gaia" = "Vila Nova de Gaia")`.
  Checked before exact matching; names are compared in normalized form.

- historic:

  Logical. Also match names from the level's other vintages? Default
  `TRUE`. Set `FALSE` to accept only names in use at `admin_vintage` —
  useful when validating that a file really is that vintage.

- quiet:

  Logical. Suppress warnings/messages about ambiguous, unmatched, and
  fuzzy-matched entries? Default `FALSE`.

## Value

Character vector of codes (same length as `x`), with a `"report"`
attribute retrievable via
[`pt_match_report()`](https://c-matos.github.io/geopt/reference/pt_match_report.md).

## Ambiguity and context

Many names are not unique (~200 freguesia names are reused; the
municipality "Lagoa" exists in Faro and in Sao Miguel). Ambiguous names
return `NA` with a warning listing the candidates. To resolve them,
either:

- pass `context`: a parent unit name per element (municipio for
  freguesias; distrito/ilha, NUTS region, or `"Acores"`/`"Madeira"` for
  municipios), or

- embed a qualifier in the name itself: `"Lagoa (Acores)"`,
  `"Lagoa (Faro)"`, INE-style `"Calheta (R.A.M.)"`,
  `"Lagoa [R.A. Acores]"` and dash-separated forms like
  `"Calheta - RAA"` or `"Calheta-R.A.A"` are all parsed automatically. A
  dash is only read as a separator when what follows it is a recognized
  region — ordinary names containing dashes (`"Albergaria-a-Velha"`) are
  never split.

A qualifier is only read as one when it is not already part of an
official name. Many freguesias end in a parenthetical of their own —
`"Bouro (Santa Maria)"`,
`"Uniao das freguesias de Braga (Maximinos, Se e Cividade)"` — and those
are matched whole, before any split is attempted.

## Spelling tolerance

Matching ignores case, accents, and punctuation, and expands
`S.`/`Sta.`/ `Sto.`. If that still does not match, a second pass ignores
Portuguese particles, so official designations and their working short
forms both resolve: `"ULS da Guarda"` → `"ULS Guarda"`,
`"ULS Trás-os-Montes Alto Douro"` → `"ULS Trás-os-Montes e Alto Douro"`.
Exact spellings always win; the report's `method` column shows `"loose"`
when this pass was needed.

A few units accept a second official spelling, so that data labelled
either way resolves: `"Vila da Praia da Vitoria"` for Praia da Vitória,
and `"Calheta"` for the Azorean Calheta (which `pt_registry` stores as
`"Calheta de Sao Jorge"`). Because Madeira also has a Calheta, a bare
`"Calheta"` is therefore *ambiguous* and returns `NA` with a warning —
qualify it as `"Calheta (R.A.A.)"` or `"Calheta (Madeira)"`.

## Historic names

Administrative reforms rename and dissolve units, so names in older
census and administrative files often have no current counterpart. With
`historic = TRUE` (the default) names from *every* vintage of the level
are matched, returning the code of the unit covering that territory in
the requested vintage; the report's `method` column shows `"historic"`.
A name found in the 2001 map is only used when no later vintage has it:
most 2001 names were still in use in 2011, and for the few freguesias
that lost territory in between, the 2011 sense is the one that matches a
single unit today. This is one mechanism, not a freguesia special case —
it is also what makes `"Minho-Lima"` resolve at `level = "nuts3"`, where
the current name is `"Alto Minho"`.

Live names win outright. A name still in use resolves to the unit
bearing it now, whatever it also meant in the past. Where a predecessor
was later split between several current units the name is genuinely
ambiguous and returns `NA` — pass a `context` or use codes. Historic
names are matched exactly and particle-loosely, never fuzzily.

A freguesia renamed while its map was in force keeps its earlier names
as names of that vintage, not as historic ones. The 2013 freguesias are
named as they were last, in CAOP 2024 and in INE's tables, and 25 of
them were renamed by law before that. `"Buarcos"`, the name of `060520`
until 2015, therefore matches it with `admin_vintage = "2013"` even when
`historic = FALSE`.

## Vintages

The three axes are independent and each has its own argument.
`admin_vintage` chooses which units exist *and which vintage's codes
come back*; `nuts_vintage` and `health_vintage` choose the nomenclature
that NUTS and health columns are expressed in. See
[`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md).

`admin_vintage` defaults to the current set, which is what you want for
joining old data onto today's map. To keep the data on its own vintage
instead — to map it against boundaries of the era — name that vintage:

    pt_match(c("Sé", "Maximinos"), level = "freguesia", context = "Braga")
    #> [1] "030364" "030364"   # the union covering both today

    pt_match(c("Sé", "Maximinos"), level = "freguesia", context = "Braga",
             admin_vintage = "2011")
    #> [1] "030352" "030324"   # the units they were

**Codes are vintage-local.** None of the 302 freguesias restored in 2025
reused its pre-2013 code, even if it has the same name and same
boundaries, so a code is only accepted against the vintage it belongs
to. `pt_match("030882", level = "freguesia")` is `NA`, because that is a
2013 code; with `admin_vintage = "2013"` it resolves.

`admin_vintage = "auto"` infers the vintage from the input and says
which it chose. This is the setting for INE data, which is published on
the 2013 freguesia set even under the 2024 NUTS revision — so 134 units
that were disaggregated in 2025 are ambiguous against the current
registry and exact against their own.

INE prefixes a city's pre-2013 parishes with the city (`"Braga (Sé)"`)
but names the same kind of unit plainly elsewhere (`"Sé"` in Lisboa).
All the spellings resolve — `"Braga (Sé)"`, `"Sé (Braga)"`, and `"Sé"`
with `context = "Braga"` — because a bare name plus a context is
recombined into the parenthesised forms and retried, once the name as
given has failed. A trailing parenthetical never *displaces* a `context`
you passed: where it is part of the official name rather than a
qualifier, the context still applies.

## Fuzzy matching

With `fuzzy = TRUE` (requires the `stringdist` package), elements that
fail exact matching are compared against candidate names by optimal
string alignment distance. A fuzzy match is accepted only when the best
candidate is within `max_dist` and strictly better than the second-best
candidate; every accepted fuzzy match is reported via message. Fuzzy
matching is most reliable with a `context`, which shrinks the candidate
pool.

## See also

[`pt_match_report()`](https://c-matos.github.io/geopt/reference/pt_match_report.md),
[`pt_normalize()`](https://c-matos.github.io/geopt/reference/pt_normalize.md),
[pt_registry](https://c-matos.github.io/geopt/reference/pt_registry.md)

## Examples

``` r
pt_match(c("Porto", "lisboa", "S. Joao da Madeira"))
#> [1] "1312" "1106" "0116"
#> attr(,"report")
#>                input        matched_name code method dist
#> 1              Porto               Porto 1312  exact   NA
#> 2             lisboa              Lisboa 1106  exact   NA
#> 3 S. Joao da Madeira São João da Madeira 0116  exact   NA
pt_match(c("Lagoa (Faro)", "Lagoa (Acores)"))
#> [1] "0806" "4201"
#> attr(,"report")
#>            input matched_name code method dist
#> 1   Lagoa (Faro)        Lagoa 0806  exact   NA
#> 2 Lagoa (Acores)        Lagoa 4201  exact   NA
pt_match("Pinheiro", level = "freguesia", context = "Guimarães")
#> [1] "030836"
#> attr(,"report")
#>      input matched_name   code method dist
#> 1 Pinheiro     Pinheiro 030836  exact   NA
```
