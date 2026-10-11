#' Simplified Portuguese administrative boundaries
#'
#' Pre-simplified sf objects derived from CAOP (Carta Administrativa Oficial de
#' Portugal). All levels are topologically consistent: higher-level boundaries
#' are dissolved from simplified freguesias, guaranteeing aligned edges. Each
#' level carries its own identity columns (official codes and names) plus
#' aggregated `area_ha`, so every dataset joins directly against user data or
#' against [pt_registry].
#'
#' Common columns (present where applicable to the level):
#' \describe{
#'   \item{dtmnfr}{6-digit freguesia code (distrito + municipio + freguesia),
#'     zero-padded character. Freguesias only.}
#'   \item{dtmn}{4-digit municipality code (first 4 digits of `dtmnfr`).}
#'   \item{dt}{2-digit distrito/ilha code.}
#'   \item{nuts1_cod, nuts2_cod, nuts3_cod}{NUTS 2024 codes in full Eurostat
#'     form (`PT1`, `PT19`, `PT191`, ...).}
#'   \item{freguesia, municipio, distrito_ilha, nuts1, nuts2, nuts3}{Official
#'     names.}
#'   \item{designacao_simplificada}{The freguesia's name without the
#'     `"União das freguesias de"` prefix. Freguesias only.}
#'   \item{perimetro_km}{Perimeter in kilometres, as CAOP gives it. Freguesias
#'     only.}
#'   \item{area_ha}{Area in hectares, summed from the constituent freguesias.}
#'   \item{n_freguesias, n_municipios}{Number of constituent units.}
#' }
#'
#' Geometries use WGS84 (EPSG:4326) and cover all of Portugal (Continente,
#' Açores, and Madeira).
#'
#' A multi-layer GeoPackage containing the same data is also bundled at
#' `inst/extdata/caop_simplified.gpkg`, with one layer per level:
#'
#' ```r
#' gpkg <- system.file("extdata", "caop_simplified.gpkg", package = "geopt")
#' sf::st_layers(gpkg)
#' sf::st_read(gpkg, layer = "municipio")
#' ```
#'
#' @format An sf data frame with `MULTIPOLYGON` geometry.
#' @source Direção-Geral do Território (DGT), CAOP.
#'   <https://www.dgterritorio.gov.pt/cartografia/cartografia-tematica/caop>
#' @seealso [pt_lookup()] for the geometry-free lookup table, [get_map()] for
#'   composed maps with island insets.
#' @name boundaries
NULL

#' @rdname boundaries
"pt_freguesias"

#' @rdname boundaries
"pt_municipios"

#' @rdname boundaries
"pt_distritos"

#' @rdname boundaries
"pt_nuts1"

#' @rdname boundaries
"pt_nuts2"

#' @rdname boundaries
"pt_nuts3"

#' @rdname boundaries
#' @details
#' The health maps are dissolved from the same simplified freguesias using the
#' [pt_health_codes] mappings, so their edges align with every administrative
#' level. Each reflects a single health vintage and exists on the current
#' freguesia map only. `pt_uls`, `pt_reg_saude`, and `pt_aces` are
#' freguesia-accurate: units that split municipalities are drawn correctly.
#'
#' `pt_uls` has 55 units: 39 mainland ULS plus the island health units, which
#' are not ULS — the Açores have nine Unidades de Saúde de Ilha
#' (`"USI São Miguel"`, ...) and Madeira seven centros de saúde
#' (`"CS Funchal Zona I"`, ...). `pt_reg_saude` carries the seven regiões de
#' saúde. Both are the 2024 reform.
#'
#' `pt_aces` has 71 Agrupamentos de Centros de Saúde — the organization the
#' 2024 reform superseded. Its `reg_saude` is the region of that time (the
#' former ARS), not the 2024 região de saúde.
#'
#' `pt_uls_municipio` (50 units) and `pt_aces_municipio` (66) are for data by
#' municipality, which can't be divided between the units that share a
#' municipality. Those units are merged into one, named after its members
#' (`"ULS Santo António + São João"`), so every unit is a set of whole
#' municipalities. Lomba, the one freguesia of Gondomar in ULS Vila Nova de
#' Gaia/Espinho and ACES Espinho/Gaia, is drawn with the rest of Gondomar,
#' where data by municipality counts it. They hold the units of the
#' `uls_municipio` and `aces_municipio` columns that [pt_join()] adds.
#'
#' All datasets carry `nuts1_cod` and `nuts1`, so a health map can be
#' filtered to the mainland, the Açores (`"PT2"`) or Madeira (`"PT3"`),
#' and `pt_aces` and `pt_aces_municipio` carry their `reg_saude`.
#' They carry no other region column, because no other is the same throughout
#' every unit: ULS Médio Tejo, for example, is split between two regiões de saúde.
"pt_uls"

#' @rdname boundaries
"pt_reg_saude"

#' @rdname boundaries
"pt_aces"

#' @rdname boundaries
"pt_uls_municipio"

#' @rdname boundaries
"pt_aces_municipio"

# --- the three vintage axes -----------------------------------------------------

#' Portuguese administrative units, every vintage
#'
#' One row per freguesia per administrative vintage. "Administrative vintage"
#' means *which units exist*, which changes by Portuguese law and is unrelated
#' to the NUTS revision (see [pt_nuts_codes]) or the health geography (see
#' [pt_health_codes]).
#'
#' `dtmn` is denormalised onto each row, so a vintage's set of municípios is the
#' distinct `dtmn` values within it.
#'
#' @section Vintages:
#' \describe{
#'   \item{`"2025"`}{3259 freguesias. Lei 25-A/2025, in force from the 2025
#'     autárquicas, which restored units aggregated in 2013.}
#'   \item{`"2013"`}{3092 freguesias. Lei 11-A/2013. **This is the set INE still
#'     publishes**, including on indicators labelled "NUTS - 2024" — the label
#'     refers to the NUTS revision, not to the freguesia set. Each freguesia has
#'     the last name it had on that map, as in CAOP 2024 and INE's tables. 25
#'     were renamed by law while the map was in force (`"Buarcos"` became
#'     `"Buarcos e São Julião"` in 2015), and [pt_match()] recognizes the
#'     earlier names too.}
#'   \item{`"2011"`}{4260 freguesias, the map the 2011 census used, in force
#'     from 2004 until the 2013 reform.}
#'   \item{`"2001"`}{4241 freguesias, the map the 2001 census used. Between the
#'     two censuses 22 freguesias were created and 3 dissolved.}
#' }
#'
#' The pre-2013 maps are named after the census that recorded them, because
#' neither was made by a single law; the later ones after their reform.
#'
#' @section Codes are vintage-local:
#' A DTMNFR identifies a unit *within its own vintage only*. None of the 302
#' freguesias restored in 2025 reused its pre-2013 code, so comparing codes
#' across vintages, or joining data of one vintage onto codes of another,
#' silently mismatches. Convert with [pt_crosswalk()]; carry values across with
#' [pt_recode()].
#'
#' @format A data.frame with 14852 rows and columns:
#' \describe{
#'   \item{admin_vintage}{`"2001"`, `"2011"`, `"2013"` or `"2025"`.}
#'   \item{dtmnfr}{6-digit freguesia code, unique within the vintage.}
#'   \item{freguesia}{Official designation. For 2013, the last one the
#'     freguesia had on that map.}
#'   \item{designacao_simplificada}{Without the `"União das freguesias de"`
#'     prefix. Official for 2025; derived by the same rule for 2013, because
#'     DGT's list for that map leaves 32 uniões unsimplified. Equal to
#'     `freguesia` for 2001 and 2011, which predate uniões.}
#'   \item{dtmn}{4-digit município code (the first four of `dtmnfr`).}
#'   \item{municipio}{Município name.}
#'   \item{dt, distrito_ilha}{District or island.}
#' }
#'
#' @examples
#' table(pt_registry$admin_vintage)
#'
#' # the set INE publishes today
#' head(pt_registry[pt_registry$admin_vintage == "2013", ])
#'
#' @source Carta Administrativa Oficial de Portugal (DGT): CAOP 2025, and CAOP
#'   2024 for the 2013 names, which INE's code list for that map matches name
#'   for name; Lei 11-A/2013 and Lei 25-A/2025; INE's freguesia code lists for
#'   the 2001 and 2011 censuses.
#' @seealso [pt_lookup()], [pt_nuts_codes], [pt_health_codes], [pt_crosswalk()]
"pt_registry"

#' NUTS classification of Portuguese municípios, every revision
#'
#' One row per município per NUTS revision. NUTS revisions are set at European
#' level and are **independent of the administrative vintage**: INE publishes the
#' same 3092-freguesia set under both the 2013 and the 2024 revision.
#'
#' Keyed on `dtmn` because every NUTS revision Portugal has had is a regrouping
#' of the same 308 municípios — stable since the 1998 creation of Trofa, Vizela
#' and Odivelas. NUTS is therefore a function of `(dtmn, nuts_vintage)` and not a
#' freguesia-level attribute at all, which is why 308 rows per revision is the
#' whole fact.
#'
#' @section Revisions:
#' \describe{
#'   \item{`"2024"`}{9 NUTS II, 26 NUTS III. Splits the former Lisboa region
#'     into Grande Lisboa, Península de Setúbal and Oeste e Vale do Tejo.}
#'   \item{`"2013"`}{7 NUTS II, 25 NUTS III, the CIM/AM-based sub-regions.}
#'   \item{`"2002"`}{7 NUTS II, 30 NUTS III. `PT17` is `"Lisboa"` here and
#'     `"Área Metropolitana de Lisboa"` from 2013.}
#' }
#'
#' @format A data.frame with 924 rows and columns:
#' \describe{
#'   \item{nuts_vintage}{`"2002"`, `"2013"` or `"2024"`.}
#'   \item{dtmn}{4-digit município code.}
#'   \item{nuts1_cod, nuts1}{NUTS I code and name.}
#'   \item{nuts2_cod, nuts2}{NUTS II code and name.}
#'   \item{nuts3_cod, nuts3}{NUTS III code and name.}
#' }
#'
#' @examples
#' # how a municipio's NUTS III changed across revisions
#' pt_nuts_codes[pt_nuts_codes$dtmn == "1106", c("nuts_vintage", "nuts3")]
#'
#' @source INE / Eurostat NUTS nomenclature. NUTS II 2002 names come from INE's
#'   own indicator dimension labels.
#' @seealso [pt_lookup()], [pt_registry]
"pt_nuts_codes"

#' Health geography of Portuguese freguesias, both vintages
#'
#' One row per freguesia per health vintage. Keyed on the freguesia rather than
#' the município because `unit` varies *within* a município in five of them —
#' the reason this cannot live alongside [pt_nuts_codes], which is município
#' grained.
#'
#' Mappings are recorded against the current (2025) freguesia set;
#' [pt_lookup()] reaches them from an earlier `admin_vintage`.
#'
#' @section Vintages:
#' \describe{
#'   \item{`"2024"`}{The reform: 5 regiões de saúde on the mainland plus the
#'     island services, and ULS (Unidades Locais de Saúde) as the local unit.}
#'   \item{`"2022"`}{What it superseded: the former ARS, and ACES (Agrupamentos
#'     de Centros de Saúde) as the local unit.}
#' }
#'
#' `unit_municipio` is the unit to use for data by município. Units that share
#' a município are merged into one pseudo-unit, and merging follows chains, so
#' it can differ from `unit` even in a município that lies whole in one unit.
#' For example, ULS São José also covers part of Loures, which merges ULS
#' Loures-Odivelas with Lisboa's three ULS, and Odivelas gets the merged unit
#' too. Everywhere else it equals `unit`.
#'
#' @format A data.frame with 6518 rows and columns:
#' \describe{
#'   \item{health_vintage}{`"2022"` or `"2024"`.}
#'   \item{dtmnfr}{6-digit freguesia code, current vintage.}
#'   \item{reg_saude}{Região de saúde (2024) or the former ARS (2022).}
#'   \item{scheme}{`"uls"` for 2024, `"aces"` for 2022 — different concepts, not
#'     two names for one thing.}
#'   \item{unit}{The local unit: a ULS or an ACES.}
#'   \item{unit_municipio}{Município-grained approximation of `unit`.}
#' }
#'
#' @examples
#' table(pt_health_codes$health_vintage, pt_health_codes$scheme)
#'
#' @source Decreto-Lei 102/2023 (ULS); prior ARS/ACES organization.
#' @seealso [pt_lookup()], [pt_registry]
"pt_health_codes"

#' Census variables available from get_censos()
#'
#' Dictionary of the census variables embedded in the INE geographies
#' returned by [get_censos()], with INE's Portuguese descriptions. One row
#' per variable per census year and level, derived from the actual
#' GeoPackage columns (INE's description CSVs use spelling variants of the
#' column names, which are matched to them).
#'
#' The variable sets differ widely by year: 2021 subsecções carry 32
#' variables, 2011 subsecções 122, 1991/2001 subsecções seven basic counts,
#' 2021 secções ~180 variables, and the 2021 grid ten.
#'
#' @format A data.frame with columns:
#' \describe{
#'   \item{year}{Census year (1991, 2001, 2011, 2021).}
#'   \item{level}{`"subseccao"`, `"seccao"`, or `"grid"`.}
#'   \item{variable}{Column name as it appears in the returned object.}
#'   \item{description}{INE's description (Portuguese).}
#' }
#'
#' @examples
#' # What is available for the 2011 census?
#' vars <- pt_censos_vars[pt_censos_vars$year == 2011, ]
#' head(vars[, c("variable", "description")])
#'
#' @source INE, Censos — importação de dados alfanuméricos e geográficos
#'   (BGRI, GRID e Lugares): <https://mapas.ine.pt/download/index2021.phtml>
#' @seealso [get_censos()]
"pt_censos_vars"
