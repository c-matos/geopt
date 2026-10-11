# How the bundled data is built

This article explains where geopt’s bundled datasets come from, and why
the build works the way it does. The scripts that do it are in
`data-raw/`: `prepare_boundaries.R` downloads and simplifies the
boundaries, and `derive_datasets.R` builds everything else.

## Simplify once, then merge upwards

The source is CAOP (Carta Administrativa Oficial de Portugal, from DGT)
at freguesia level, the finest official detail. The build:

1.  Downloads the full-resolution freguesias for the mainland, the
    Açores and Madeira.
2.  Simplifies them **once**, at freguesia level
    ([`rmapshaper::ms_simplify()`](http://andyteucher.ca/rmapshaper/reference/ms_simplify.md),
    keeping 1% of the points, with shapes preserved).
3.  Builds every other level (municipalities, districts, NUTS 1 to 3,
    ULS, health regions, ACES) by **merging** the simplified freguesias.

Merging, rather than simplifying each level separately, is what makes
the borders line up: a municipality’s border is exactly the outer edge
of its freguesias, so drawing any two levels on top of each other never
leaves gaps or slivers. It also means the freguesias of a unit always
fill exactly that unit’s shape.

Each merged level keeps only its own columns (codes and names, which are
the same for every freguesia in it), plus `area_ha`, the sum of its
freguesias’ areas, and counts of the units it contains.

## The code columns

CAOP stores the 6-digit freguesia code (2 digits for the district, 2 for
the municipality, 2 for the freguesia) in a column called `dtmnfr`, and
geopt keeps that name. It takes `dtmn` (the first 4 digits) and `dt`
(the first 2) from it, the names CAOP uses for the municipality and
district codes. (CAOP releases before 2024, and many older datasets,
call these codes DICOFRE and DICO.) NUTS codes are stored in full
Eurostat form (`PT11A`), and the NUTS 2 and NUTS 1 codes are its first
characters. Before saving, the build checks that the codes nest as they
should: every freguesia code is unique, every municipality sits in
exactly one district and one NUTS 3 region, and so on.

## The freguesia tables, and the checks on them

Everything that isn’t geometry or NUTS 2024 comes from
`data-raw/freguesia_registry_2025.csv`. It has one row per **current**
freguesia (3,259), with its 2013 code, its units in both versions of the
health map, and its NUTS 2013 and NUTS 2002 regions. Because it’s
already one row per freguesia, the build only has to join it on
`dtmnfr`: nothing is inferred.

The registry’s 2013 names aren’t edited by hand.
`data-raw/fetch_2013_names.R` writes them from CAOP 2024, DGT’s last
release of the 2013 map, and stops unless INE’s code list for that map
gives the same name for every freguesia (it does, for all 3,092). So
each 2013 freguesia has the last name it carried, which is the one INE
publishes. 25 of them were renamed by law while the map was in force.
`data-raw/freguesia_names_2013.csv` lists their earlier names, and the
spellings DGT later corrected, with the law and the CAOP releases that
carried each; they match as names of the 2013 map too.

The freguesias of the 2011 census map, in force until 2013, are in a
second file, `data-raw/freguesia_registry_2011.csv`, because there are
more of them: about 750 current freguesias have more than one
predecessor there (up to 12), so those 4,260 rows can’t fit in a
3,259-row table.

A third file, `data-raw/freguesia_registry_2001.csv`, holds the map of
the 2001 census. It is written by `data-raw/fetch_2001_registry.R` from
INE’s code list for that census and
`data-raw/freguesia_changes_2001_2011.csv`, which lists the 22
freguesias created and 3 dissolved between the two censuses, with their
laws. It has one row per pair of a 2001 and a 2011 freguesia that share
territory, and the build checks that the pairs describe exactly those
changes.

The first two files are edited by hand, so the build checks them rather
than trusting them:

- the registry lists exactly the freguesias that CAOP has;
- its `freguesia` and `municipio` columns, which are only there to make
  editing easier, still agree with CAOP, so an out-of-date row can’t
  slip through;
- no column is empty;
- each NUTS 2013 region code starts with its NUTS 2 code;
- every code has exactly one name, and every name exactly one code;
- no NUTS 3 region (of either revision) splits a municipality;
- each 2013 freguesia has exactly one name, and each earlier name
  belongs to a 2013 freguesia and differs from its last one.

A hand edit that breaks any of these stops the build.

## How vintages are related: shared territory

To relate the units of two vintages, geopt breaks the territory into
building blocks that never change. Those blocks are the freguesias of
the 2011 census map: every freguesia since has been either one of them,
several of them merged, or one of them restored, and every 2001
freguesia is one or more of them. There are three exceptions. Parque das
Nações in Lisboa was created in 2012 from parts of older freguesias, so
it gets a block of its own. And two 2011 freguesias were carved out of
two 2001 freguesias each, Boavista dos Pinheiros (Odemira) and Santa
Cruz/Trindade (Chaves), so each is two blocks.

Every unit in every vintage (freguesias, NUTS regions and health units)
is recorded as the set of blocks it covers. Two units from different
vintages correspond when they share blocks, and how they share them
gives the `relation` in
[`pt_crosswalk()`](https://c-matos.github.io/geopt/reference/pt_crosswalk.md):

- the same blocks, code and name: `unchanged`;
- the same blocks and code, with a different name: `renamed`;
- the same blocks with a different code: `renumbered`;
- several old units sharing one new one: `merged`;
- one old unit spread over several new ones: `split`.

Because the correspondence is worked out from the blocks rather than
stored, any pair of vintages works, and a new vintage only needs its own
block sets.

NUTS regions are recorded against municipalities rather than freguesias,
because every NUTS revision Portugal has had groups the same 308
municipalities. Health units are recorded against freguesias, because
some of them split municipalities.

## `uls_municipio` and `aces_municipio`

Some health units split municipalities: Lisboa is divided between three
ULS, and Loures, Porto and Funchal are split too (Gondomar as well, by
one freguesia: see below). Data by municipality can’t be assigned to
those units, so `pt_health_codes` also has `unit_municipio`: units that
share a municipality are combined into one. (Formally, these are the
connected groups in the network that links each municipality to its
health units.) For example, ULS São José also covers part of Loures, so
ULS Loures-Odivelas ends up combined with Lisboa’s three ULS.

``` r

h <- pt_lookup(health_vintage = "2024")
unique(h$unit_municipio[h$unit != h$unit_municipio])
#> [1] "ULS Lisboa Ocidental + Loures-Odivelas + Santa Maria + São José"
#> [2] "ULS Santo António + São João"                                   
#> [3] "CS Funchal Zona I + Funchal Zona II"
```

Everywhere else, `unit_municipio` is the same as `unit`.
[`pt_join()`](https://c-matos.github.io/geopt/reference/pt_join.md) uses
this to add only the columns that have one value per unit at the level
joined on. The `pt_uls_municipio` and `pt_aces_municipio` maps merge the
freguesias by these columns, so each of their units is a set of whole
municipalities.

One exception keeps the combining in check. **Lomba** is the only
freguesia of Gondomar outside both ULS Santo António and ACES Gondomar,
and a single freguesia like that is enough to link two otherwise
separate units into one. Since the established practice is to report
Lomba with the rest of its municipality, the build does the same, for
the `*_municipio` columns only, never for the freguesia-level `uls` and
`aces`. Without it, neither ULS Vila Nova de Gaia/Espinho nor ACES
Gondomar could be reported on their own. The rule is written once, as
“count this freguesia under whatever the rest of its municipality uses”,
and the build fails if the rest of the municipality doesn’t agree.

## Maps of another vintage use the same steps

`get_map(admin_vintage = "2013")` runs the same simplify-then-merge
steps on request, from CAOP 2024, DGT’s last release of the 2013 map.
The download goes through `GeoClient`. From that file, geopt takes only
the freguesia codes, geometry and areas. The names come from
`pt_registry`, so the map and
[`pt_lookup()`](https://c-matos.github.io/geopt/reference/pt_lookup.md)
name every unit alike, and the municipality, district and NUTS columns
are joined on the municipality code, which hasn’t changed. The merging
uses the same code as the bundled data, and results are cached per level
and vintage.

A different `nuts_vintage` needs no download: on the current map, geopt
swaps the NUTS columns, or, for a NUTS level, merges the bundled
freguesias again.

## Rebuilding or extending the data

``` r

# Full rebuild from scratch (needs network access and rmapshaper):
source("data-raw/prepare_boundaries.R")

# Rebuild everything from the already-simplified freguesias (offline):
source("data-raw/derive_datasets.R")
```

The build prints what it did as it goes: the unit counts in the
registry, the combined health units, the crosswalk relation counts, and
the final size of the data.
