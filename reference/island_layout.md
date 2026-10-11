# Lay out the islands

The Açores are about 1,500 km west of the mainland and Madeira about
1,000 km to the south-west, so a map of Portugal drawn to scale is
mostly ocean.
[`get_map()`](https://c-matos.github.io/geopt/reference/get_map.md) and
[`plot_pt()`](https://c-matos.github.io/geopt/reference/plot_pt.md) move
the islands next to the mainland, as insets. `island_layout()` says how:
which archipelagos to show, how to split them into insets, and whether
to draw frames around them.

## Usage

``` r
island_layout(
  both = "compact",
  raa = both,
  ram = both,
  frames = TRUE,
  box_position = "bottom_left"
)
```

## Arguments

- both:

  How to show both archipelagos: `"compact"`, `"groups"`, `"box"`,
  `"in_place"` or `"none"`. See Choices.

- raa, ram:

  How to show the Açores (`raa`) or Madeira (`ram`), when it should
  differ from `both`: one of the choices, or a layout list (see Moving
  and resizing the islands section below).

- frames:

  Draw frames around the insets? Only applies to archipelagos drawn as
  insets.

- box_position:

  Where to put the rectangles, for `"box"`: `"bottom_left"` or
  `"top_left"` of the mainland, or `c(x, y)`, the longitude and latitude
  of the bottom-left corner of the stack.

## Value

An island layout, to pass as `islands` to
[`get_map()`](https://c-matos.github.io/geopt/reference/get_map.md) or
[`plot_pt()`](https://c-matos.github.io/geopt/reference/plot_pt.md).

## Details

Pass the result as `islands` to
[`get_map()`](https://c-matos.github.io/geopt/reference/get_map.md) or
[`plot_pt()`](https://c-matos.github.io/geopt/reference/plot_pt.md). For
the common cases a string is enough: `islands = "none"` is the same as
`islands = island_layout("none")`.

## Choices

Each archipelago takes one of:

- `"compact"`:

  (The default.) Insets arranged to take the least room: the Açores in
  four insets (the western group, the central group, São Miguel, and
  Santa Maria on its own), and Porto Santo in its own small inset, moved
  next to Madeira.

- `"groups"`:

  The Açores in their three official groups (Ocidental, Central and
  Oriental). Madeira has no groups, so for Madeira this is the same as
  `"compact"`.

- `"whole"`:

  Madeira and Porto Santo in one inset, at their true distance apart.
  Not available for the Açores: at a size that fits next to the
  mainland, the smaller islands would be too small to read.

- `"box"`:

  A labelled rectangle instead of the islands, stacked to the left of
  the mainland. Only works at levels where each archipelago is a single
  region: `"nuts1"`, `"nuts2"`, `"nuts3"` and `"reg_saude"`. Can't be
  combined with insets.

- `"in_place"`:

  The islands where they really are, without frames. The starting point
  for a map of one archipelago (see Examples).

- `"none"`:

  Leave the archipelago out.

## Frames

With `frames = TRUE`,
[`get_map()`](https://c-matos.github.io/geopt/reference/get_map.md) adds
the frames drawn around the insets, which show that the islands have
been moved. They are extra rows with `geopt_type = "frame"`, their name
in `geopt_label`, and `geopt_frame_level` saying what they surround: 1
for a whole archipelago, 2 for a group of islands and 3 for a single
island.

## Moving and resizing the islands

`island_layout()` returns a list, which you can change before passing it
on. Each archipelago drawn as insets has:

- `anchor`:

  Longitude and latitude its insets are placed around.

- `label`:

  The name on its frame (and on its rectangle, for `"box"`).

- `frame_buffer`:

  Space between the islands and the frame around the whole archipelago,
  in degrees.

- `groups`:

  One entry per inset, each with:

  `crop`

  :   The part of the archipelago this inset shows, as
      `c(xmin =, ymin =, xmax =, ymax =)` in longitude and latitude.
      `NULL` shows the whole archipelago.

  `offset`

  :   Where the inset goes, as `c(x, y)` in degrees from `anchor`.

  `scale`

  :   How much to enlarge it. Default 1.

  `label`

  :   Optional. Draws a frame around this inset alone, with this name.

  `frame_level`, `frame_buffer`

  :   Optional. That frame's `geopt_frame_level` (default 3) and its
      space around the islands.

- `sub_frames`:

  Optional. Frames around several insets at once, each with `groups`
  (the inset names), `label`, and optionally `frame_buffer` and
  `frame_level` (default 2).

Print `island_layout()$raa` to see a complete example. To lay out an
archipelago from scratch, pass a list with the same structure as `raa`
or `ram`.

## See also

[`get_map()`](https://c-matos.github.io/geopt/reference/get_map.md),
[`plot_pt()`](https://c-matos.github.io/geopt/reference/plot_pt.md)

## Examples

``` r
island_layout()
#> <island layout>
#>   raa (Açores):  compact   4 insets: ocidental, central, s_miguel, s_maria
#>   ram (Madeira):  compact   2 insets: madeira, porto_santo
#>   frames:         yes
island_layout(raa = "groups", ram = "whole")
#> <island layout>
#>   raa (Açores):  groups    3 insets: ocidental, central, oriental
#>   ram (Madeira):  whole     1 inset: madeira
#>   frames:         yes

get_map("municipio", islands = "none")    # mainland only
#> Simple feature collection with 278 features and 15 fields
#> Geometry type: MULTIPOLYGON
#> Dimension:     XY
#> Bounding box:  xmin: -9.500527 ymin: 36.96188 xmax: -6.189159 ymax: 42.1482
#> Geodetic CRS:  WGS 84
#> First 10 features:
#>    dtmn            municipio dt distrito_ilha nuts1_cod      nuts1 nuts2_cod
#> 1  0101               Águeda 01        Aveiro       PT1 Continente      PT19
#> 2  0102   Albergaria-a-Velha 01        Aveiro       PT1 Continente      PT19
#> 3  0103               Anadia 01        Aveiro       PT1 Continente      PT19
#> 4  0104               Arouca 01        Aveiro       PT1 Continente      PT11
#> 5  0105               Aveiro 01        Aveiro       PT1 Continente      PT19
#> 6  0106     Castelo de Paiva 01        Aveiro       PT1 Continente      PT11
#> 7  0107              Espinho 01        Aveiro       PT1 Continente      PT11
#> 8  0108            Estarreja 01        Aveiro       PT1 Continente      PT19
#> 9  0109 Santa Maria da Feira 01        Aveiro       PT1 Continente      PT11
#> 10 0110               Ílhavo 01        Aveiro       PT1 Continente      PT19
#>     nuts2 nuts3_cod                       nuts3  area_ha n_freguesias
#> 1  Centro     PT191            Região de Aveiro 33527.44           15
#> 2  Centro     PT191            Região de Aveiro 15882.49            6
#> 3  Centro     PT191            Região de Aveiro 21663.49           10
#> 4   Norte     PT11A Área Metropolitana do Porto 32910.51           16
#> 5  Centro     PT191            Região de Aveiro 19757.58           10
#> 6   Norte     PT11C              Tâmega e Sousa 11500.52            9
#> 7   Norte     PT11A Área Metropolitana do Porto  2105.67            5
#> 8  Centro     PT191            Região de Aveiro 10817.34            6
#> 9   Norte     PT11A Área Metropolitana do Porto 21587.64           28
#> 10 Centro     PT191            Região de Aveiro  7347.56            4
#>    geopt_type geopt_label geopt_frame_level                       geometry
#> 1    boundary        <NA>                NA MULTIPOLYGON (((-8.249194 4...
#> 2    boundary        <NA>                NA MULTIPOLYGON (((-8.606468 4...
#> 3    boundary        <NA>                NA MULTIPOLYGON (((-8.311495 4...
#> 4    boundary        <NA>                NA MULTIPOLYGON (((-8.32016 40...
#> 5    boundary        <NA>                NA MULTIPOLYGON (((-8.632433 4...
#> 6    boundary        <NA>                NA MULTIPOLYGON (((-8.23713 41...
#> 7    boundary        <NA>                NA MULTIPOLYGON (((-8.611502 4...
#> 8    boundary        <NA>                NA MULTIPOLYGON (((-8.599495 4...
#> 9    boundary        <NA>                NA MULTIPOLYGON (((-8.477484 4...
#> 10   boundary        <NA>                NA MULTIPOLYGON (((-8.746029 4...
get_map("nuts3", islands = "box")
#> Simple feature collection with 26 features and 11 fields
#> Geometry type: MULTIPOLYGON
#> Dimension:     XY
#> Bounding box:  xmin: -10.25053 ymin: 36.96188 xmax: -6.189159 ymax: 42.1482
#> Geodetic CRS:  WGS 84
#> First 10 features:
#>    nuts3_cod                       nuts3 nuts2_cod   nuts2 nuts1_cod      nuts1
#> 1      PT111                  Alto Minho      PT11   Norte       PT1 Continente
#> 2      PT112                      Cávado      PT11   Norte       PT1 Continente
#> 3      PT119                         Ave      PT11   Norte       PT1 Continente
#> 4      PT11A Área Metropolitana do Porto      PT11   Norte       PT1 Continente
#> 5      PT11B       Alto Tâmega e Barroso      PT11   Norte       PT1 Continente
#> 6      PT11C              Tâmega e Sousa      PT11   Norte       PT1 Continente
#> 7      PT11D                       Douro      PT11   Norte       PT1 Continente
#> 8      PT11E    Terras de Trás-os-Montes      PT11   Norte       PT1 Continente
#> 9      PT150                     Algarve      PT15 Algarve       PT1 Continente
#> 10     PT191            Região de Aveiro      PT19  Centro       PT1 Continente
#>     area_ha n_municipios geopt_type geopt_label geopt_frame_level
#> 1  221884.2           10   boundary        <NA>                NA
#> 2  124579.1            6   boundary        <NA>                NA
#> 3  145136.5            8   boundary        <NA>                NA
#> 4  204126.9           17   boundary        <NA>                NA
#> 5  292190.8            6   boundary        <NA>                NA
#> 6  183151.5           11   boundary        <NA>                NA
#> 7  403157.7           19   boundary        <NA>                NA
#> 8  554359.6            9   boundary        <NA>                NA
#> 9  499679.5           16   boundary        <NA>                NA
#> 10 169286.0           11   boundary        <NA>                NA
#>                          geometry
#> 1  MULTIPOLYGON (((-8.519346 4...
#> 2  MULTIPOLYGON (((-8.792077 4...
#> 3  MULTIPOLYGON (((-8.440636 4...
#> 4  MULTIPOLYGON (((-8.789006 4...
#> 5  MULTIPOLYGON (((-7.325235 4...
#> 6  MULTIPOLYGON (((-8.379446 4...
#> 7  MULTIPOLYGON (((-7.8885 41....
#> 8  MULTIPOLYGON (((-6.326651 4...
#> 9  MULTIPOLYGON (((-7.569614 3...
#> 10 MULTIPOLYGON (((-8.746029 4...
get_map("nuts3", islands = island_layout("box", box_position = "top_left"))
#> Simple feature collection with 26 features and 11 fields
#> Geometry type: MULTIPOLYGON
#> Dimension:     XY
#> Bounding box:  xmin: -10.25053 ymin: 36.96188 xmax: -6.189159 ymax: 42.1482
#> Geodetic CRS:  WGS 84
#> First 10 features:
#>    nuts3_cod                       nuts3 nuts2_cod   nuts2 nuts1_cod      nuts1
#> 1      PT111                  Alto Minho      PT11   Norte       PT1 Continente
#> 2      PT112                      Cávado      PT11   Norte       PT1 Continente
#> 3      PT119                         Ave      PT11   Norte       PT1 Continente
#> 4      PT11A Área Metropolitana do Porto      PT11   Norte       PT1 Continente
#> 5      PT11B       Alto Tâmega e Barroso      PT11   Norte       PT1 Continente
#> 6      PT11C              Tâmega e Sousa      PT11   Norte       PT1 Continente
#> 7      PT11D                       Douro      PT11   Norte       PT1 Continente
#> 8      PT11E    Terras de Trás-os-Montes      PT11   Norte       PT1 Continente
#> 9      PT150                     Algarve      PT15 Algarve       PT1 Continente
#> 10     PT191            Região de Aveiro      PT19  Centro       PT1 Continente
#>     area_ha n_municipios geopt_type geopt_label geopt_frame_level
#> 1  221884.2           10   boundary        <NA>                NA
#> 2  124579.1            6   boundary        <NA>                NA
#> 3  145136.5            8   boundary        <NA>                NA
#> 4  204126.9           17   boundary        <NA>                NA
#> 5  292190.8            6   boundary        <NA>                NA
#> 6  183151.5           11   boundary        <NA>                NA
#> 7  403157.7           19   boundary        <NA>                NA
#> 8  554359.6            9   boundary        <NA>                NA
#> 9  499679.5           16   boundary        <NA>                NA
#> 10 169286.0           11   boundary        <NA>                NA
#>                          geometry
#> 1  MULTIPOLYGON (((-8.519346 4...
#> 2  MULTIPOLYGON (((-8.792077 4...
#> 3  MULTIPOLYGON (((-8.440636 4...
#> 4  MULTIPOLYGON (((-8.789006 4...
#> 5  MULTIPOLYGON (((-7.325235 4...
#> 6  MULTIPOLYGON (((-8.379446 4...
#> 7  MULTIPOLYGON (((-7.8885 41....
#> 8  MULTIPOLYGON (((-6.326651 4...
#> 9  MULTIPOLYGON (((-7.569614 3...
#> 10 MULTIPOLYGON (((-8.746029 4...
get_map("municipio", islands = island_layout(frames = FALSE))
#> Simple feature collection with 308 features and 15 fields
#> Geometry type: GEOMETRY
#> Dimension:     XY
#> Bounding box:  xmin: -11.28491 ymin: 36.96188 xmax: -6.189159 ymax: 42.1482
#> Geodetic CRS:  WGS 84
#> First 10 features:
#>    dtmn            municipio dt distrito_ilha nuts1_cod      nuts1 nuts2_cod
#> 1  0101               Águeda 01        Aveiro       PT1 Continente      PT19
#> 2  0102   Albergaria-a-Velha 01        Aveiro       PT1 Continente      PT19
#> 3  0103               Anadia 01        Aveiro       PT1 Continente      PT19
#> 4  0104               Arouca 01        Aveiro       PT1 Continente      PT11
#> 5  0105               Aveiro 01        Aveiro       PT1 Continente      PT19
#> 6  0106     Castelo de Paiva 01        Aveiro       PT1 Continente      PT11
#> 7  0107              Espinho 01        Aveiro       PT1 Continente      PT11
#> 8  0108            Estarreja 01        Aveiro       PT1 Continente      PT19
#> 9  0109 Santa Maria da Feira 01        Aveiro       PT1 Continente      PT11
#> 10 0110               Ílhavo 01        Aveiro       PT1 Continente      PT19
#>     nuts2 nuts3_cod                       nuts3  area_ha n_freguesias
#> 1  Centro     PT191            Região de Aveiro 33527.44           15
#> 2  Centro     PT191            Região de Aveiro 15882.49            6
#> 3  Centro     PT191            Região de Aveiro 21663.49           10
#> 4   Norte     PT11A Área Metropolitana do Porto 32910.51           16
#> 5  Centro     PT191            Região de Aveiro 19757.58           10
#> 6   Norte     PT11C              Tâmega e Sousa 11500.52            9
#> 7   Norte     PT11A Área Metropolitana do Porto  2105.67            5
#> 8  Centro     PT191            Região de Aveiro 10817.34            6
#> 9   Norte     PT11A Área Metropolitana do Porto 21587.64           28
#> 10 Centro     PT191            Região de Aveiro  7347.56            4
#>    geopt_type geopt_label geopt_frame_level                       geometry
#> 1    boundary        <NA>                NA MULTIPOLYGON (((-8.249194 4...
#> 2    boundary        <NA>                NA MULTIPOLYGON (((-8.606468 4...
#> 3    boundary        <NA>                NA MULTIPOLYGON (((-8.311495 4...
#> 4    boundary        <NA>                NA MULTIPOLYGON (((-8.32016 40...
#> 5    boundary        <NA>                NA MULTIPOLYGON (((-8.632433 4...
#> 6    boundary        <NA>                NA MULTIPOLYGON (((-8.23713 41...
#> 7    boundary        <NA>                NA MULTIPOLYGON (((-8.611502 4...
#> 8    boundary        <NA>                NA MULTIPOLYGON (((-8.599495 4...
#> 9    boundary        <NA>                NA MULTIPOLYGON (((-8.477484 4...
#> 10   boundary        <NA>                NA MULTIPOLYGON (((-8.746029 4...

# The Açores alone, in their true position
m <- get_map("municipio", islands = "in_place")
acores <- m[m$nuts2_cod %in% "PT20", ]

# Move the Açores half a degree west, with an English label
lay <- island_layout()
lay$raa$anchor <- lay$raa$anchor + c(-0.5, 0)
lay$raa$label <- "Azores"
get_map("nuts3", islands = lay)
#> Simple feature collection with 36 features and 11 fields
#> Geometry type: GEOMETRY
#> Dimension:     XY
#> Bounding box:  xmin: -11.88491 ymin: 36.96188 xmax: -6.189159 ymax: 42.1482
#> Geodetic CRS:  WGS 84
#> First 10 features:
#>    nuts3_cod                       nuts3 nuts2_cod   nuts2 nuts1_cod      nuts1
#> 1      PT111                  Alto Minho      PT11   Norte       PT1 Continente
#> 2      PT112                      Cávado      PT11   Norte       PT1 Continente
#> 3      PT119                         Ave      PT11   Norte       PT1 Continente
#> 4      PT11A Área Metropolitana do Porto      PT11   Norte       PT1 Continente
#> 5      PT11B       Alto Tâmega e Barroso      PT11   Norte       PT1 Continente
#> 6      PT11C              Tâmega e Sousa      PT11   Norte       PT1 Continente
#> 7      PT11D                       Douro      PT11   Norte       PT1 Continente
#> 8      PT11E    Terras de Trás-os-Montes      PT11   Norte       PT1 Continente
#> 9      PT150                     Algarve      PT15 Algarve       PT1 Continente
#> 10     PT191            Região de Aveiro      PT19  Centro       PT1 Continente
#>     area_ha n_municipios geopt_type geopt_label geopt_frame_level
#> 1  221884.2           10   boundary        <NA>                NA
#> 2  124579.1            6   boundary        <NA>                NA
#> 3  145136.5            8   boundary        <NA>                NA
#> 4  204126.9           17   boundary        <NA>                NA
#> 5  292190.8            6   boundary        <NA>                NA
#> 6  183151.5           11   boundary        <NA>                NA
#> 7  403157.7           19   boundary        <NA>                NA
#> 8  554359.6            9   boundary        <NA>                NA
#> 9  499679.5           16   boundary        <NA>                NA
#> 10 169286.0           11   boundary        <NA>                NA
#>                          geometry
#> 1  MULTIPOLYGON (((-8.519346 4...
#> 2  MULTIPOLYGON (((-8.792077 4...
#> 3  MULTIPOLYGON (((-8.440636 4...
#> 4  MULTIPOLYGON (((-8.789006 4...
#> 5  MULTIPOLYGON (((-7.325235 4...
#> 6  MULTIPOLYGON (((-8.379446 4...
#> 7  MULTIPOLYGON (((-7.8885 41....
#> 8  MULTIPOLYGON (((-6.326651 4...
#> 9  MULTIPOLYGON (((-7.569614 3...
#> 10 MULTIPOLYGON (((-8.746029 4...
```
