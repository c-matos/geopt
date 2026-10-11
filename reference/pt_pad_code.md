# Restore leading zeros in administrative codes

Spreadsheet round-trips commonly convert codes like `"0115"` to the
number `115`. This pads digit codes back to their official width: 6 for
DTMNFR (freguesia), 4 for DTMN (municipio), 2 for DT (distrito/ilha).

## Usage

``` r
pt_pad_code(x, level = "municipio")
```

## Arguments

- x:

  Vector of codes (character or numeric).

- level:

  One of `"freguesia"`/`"dtmnfr"`, `"municipio"`/`"dtmn"`,
  `"distrito"`/`"dt"`.

## Value

Character vector of zero-padded codes. Non-digit entries are returned
unchanged.

## Examples

``` r
pt_pad_code(c(115, 1106), "municipio")
#> [1] "0115" "1106"
```
