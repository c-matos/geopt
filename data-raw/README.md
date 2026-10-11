# data-raw

Sources and build scripts for the bundled datasets. Not shipped (`.Rbuildignore`).

## Source of truth

Three registry CSVs, and the earlier names of the 2013 map's freguesias.
**They already hold the correct values** — nothing is inferred at build time.
The underlying authority is legislation (and CAOP for boundaries), not any
upstream file: when a mistake is found, it is fixed in the CSV.

| file                            | grain                               | rows | holds                                                                                   |
| ------------------------------- | ----------------------------------- | ---- | --------------------------------------------------------------------------------------- |
| `freguesia_registry_2025.csv` | freguesia of the current (2025) map | 3259 | `dtmnfr_2013` and its name, health units (both vintages), NUTS 2013, NUTS 2002        |
| `freguesia_registry_2011.csv` | freguesia of the 2011 census map    | 4260 | 2011 code → current code,`relation`                                                  |
| `freguesia_registry_2001.csv` | (2001, 2011) pair sharing territory | 4262 | 2001 code and name → 2011 code                                                         |
| `freguesia_names_2013.csv`    | earlier name of a 2013 freguesia    | 43   | the name, the CAOP releases that carried it, and the law or correction that replaced it |

Separate files because the vintages are different grains: 751 current
freguesias have more than one 2011 predecessor (up to 12), so those rows cannot
live in a 3259-row table. Everything else about the 2011 layer (`dtmn`,
`municipio`, `dtmnfr_2013`) is recomputed at build time from the current-grain
registry, so the layers stay consistent.

Each file is named after the map its rows are freguesias of. The two pre-2013
maps are named after the census that recorded them, because neither was made
by a single law; the current one after its reform.

### `freguesia_registry_2025.csv`

`dtmnfr` is the key. `freguesia` and `municipio` are editing aids only —
`derive_datasets.R` checks them against CAOP and stops if they drift, so they
cannot silently go stale.

Identity columns and NUTS 2024 are **not** here: they come from CAOP via
`pt_freguesias`.

`freguesia_2013` is written by `fetch_2013_names.R`, **not** hand-maintained:
it is the last name each 2013 freguesia carried, from CAOP 2024 (DGT's last
release of the 2013 map), which INE's code list for that map matches name for
name. The script stops if the two ever disagree. The build checks that each
2013 freguesia has exactly one name.

Vintage pairs that must not be mixed:

* `reg_saude` + `uls` — the 2024 health reform (current).
* `reg_saude_2022` + `aces` — the former ARS/ACES organization.
* NUTS: unsuffixed (2024, from CAOP) / `*_2013` / `nuts3_*_2002`.

The build asserts: every column non-empty; `nuts2_cod_2013` is the prefix of
`nuts3_cod_2013`; each code ↔ name pair is 1:1 both ways; and no statistical
geography (`nuts3_cod_2013`, `nuts3_cod_2002`) splits a municipality.
A hand-edit that breaks any of these fails the build rather than shipping.

### `freguesia_registry_2011.csv`

The map the 2011 census used, in force from 2004-01-01 (when the last
freguesias created before the reform came into being) until the 2013 reform.
The 2001 census used an earlier map (see below), and the 1991 one an earlier
one again, with 305 municípios, which has no vintage.

`relation` is stored, not derived: 10 rows genuinely contradict the naive rule
(e.g. Pombalinho, a real Santarém → Golegã transfer, and the Ílhavo and
Figueira da Foz restorations).

`freguesia_2011` holds the name the unit carried **then**, which is frequently
not the current unit's name — `030352` is `"Braga (Sé)"`, today part of
`"União das freguesias de Braga (Maximinos, Sé e Cividade)"`. `pt_match()`
matches these, so a name read off an older census file resolves.

Written by `fetch_2011_names.R` from INE, **not** hand-maintained — rerun that
script rather than editing the column.

### `freguesia_registry_2001.csv`

The map the 2001 census used: 4241 freguesias, from INE indicator 0000535.
Written by `fetch_2001_registry.R`, **not** hand-maintained: to correct it,
fix `freguesia_changes_2001_2011.csv` and rerun that script. It stops unless the
2001 and 2011 code lists differ by exactly the changes listed there.

One row per pair of a 2001 and a 2011 freguesia sharing territory. The 2011 map
is finer everywhere except two freguesias carved out of two 2001 ones each,
Boavista dos Pinheiros (021116) and Santa Cruz/Trindade (170352); the atom model
gives each of them one atom per part.

Names are INE's 2001 labels without the region qualifier INE appends to
Azorean and Madeiran ones. A few are abbreviated to fit INE's 40-character field
and are kept as published.

### `freguesia_changes_2001_2011.csv`

The 25 differences between the two census maps: 22 freguesias created and 3
dissolved, with the law, its publication date, the date it took effect where
the law sets one, and whether that was checked against the Diário da República
text (`checked`). For each created freguesia, `from_2001` names the 2001
freguesia(s) its territory came from. All 22 were confirmed by overlaying the
2011 census areas on the 2001 ones and counting 2001 residents in each part
(`from_2001_checked`); that is how Santa Cruz/Trindade's second parent, Santa
Maria Maior, was found — Lei 18-E/2001 gives only its boundaries.

In the 2001 census areas (BGRI), Vale de Amoreira and Moita carry the code of
the municipality they were in before a transfer (`090756`, `100117`), not
INE's (`090804`, `101003`). The package accepts both: see
`FREGUESIA_CODE_ALIASES` in `R/vintage.R`.

### `freguesia_names_2013.csv`

The names the 2013 map's freguesias carried before their last one, which
`freguesia_registry_2025.csv` holds. One row per earlier name: 43 names of 40
freguesias. The build adds them to the 2013 vintage's names, so `pt_match()`
finds `"Buarcos"` as 060520's name on that map even with `historic = FALSE`.

`change` says how each name was replaced:

* `renamed` — by the law in `law`, published on `published`. 25 rows, one per
  freguesia renamed while the map was in force (2014–2020).
* `corrected` — DGT corrected its own record. That covers five 2013 spellings
  fixed in CAOP 2014, six spellings of CAOP 2017 that CAOP 2018 reverted citing
  Declaração de Retificação 19/2013, three accent fixes in Madeira and the
  Azores, and four errors corrected in CAOP 2021: three renames first recorded
  with a slip ("das freguesias" for "de freguesias", "Faíl" for "Fail") and
  one 2013 spelling ("da Riba-Ul").

`caop_first` and `caop_last` are the CAOP releases that carry the name.
`freguesia_2013` is an editing aid, the last name; the build checks it against
the registry.

Built 2026-10 by comparing the freguesia names of every DGT release of the 2013
map (CAOP 2013–2024) with CAOP 2024's, and taking each change's law from DGT's
yearly change logs (`alteracoes_CAOP<year>.pdf`). For the islands only the 2013
and 2024 releases were compared; their 2013 files are in capitals, which are
not listed as names. The map is closed, so the list will not grow; correct it by
hand.

## Scripts

* `derive_datasets.R` — builds every bundled dataset. Run this after editing a
  registry CSV.
* `fetch_2013_names.R` — fills `freguesia_2013` in `freguesia_registry_2025.csv`
  from CAOP 2024, checked against INE indicator 0012396 (needs `ineptr2` +
  network). Run before `derive_datasets.R`.
* `fetch_2011_names.R` — fills `freguesia_2011` from INE indicator 0006393
  (needs `ineptr2` + network). Run before `derive_datasets.R`.
* `fetch_2001_registry.R` — writes `freguesia_registry_2001.csv` from INE
  indicator 0000535 and `freguesia_changes_2001_2011.csv` (needs `ineptr2` +
  network). Run before `derive_datasets.R`.
* `prepare_boundaries.R` — downloads and simplifies CAOP into
  `freg_simplified.rds` (optional; the build falls back to the bundled
  `pt_freguesias`), then runs `derive_datasets.R`.
* `build_atoms.R` — the atom model in `R/sysdata.rda`, which every vintage
  conversion is derived from. Sourced by `derive_datasets.R`, not run alone.
* `save_internal.R` — writes objects into `R/sysdata.rda` without dropping the
  ones another script wrote there. Used by `derive_datasets.R` and
  `censos_manifest.R`.
* `censos_manifest.R` — unrelated to the registries; builds the census
  download manifest (internal) and the variable dictionary
  (`pt_censos_vars`).
