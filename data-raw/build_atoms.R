# data-raw/build_atoms.R
#
# Builds the internal atom model that the vintage axes rest on. Sourced by
# derive_datasets.R after the crosswalks exist (section 3d).
#
#   atoms       one row per invariant territory unit
#   units       (scheme, vintage, code) -> official name
#   unit_names  the matching pool: official + simplified spellings, and the
#               earlier names of the 2013 map's freguesias (kind "former")
#   membership  atom -> unit, per (scheme, vintage), with `share`
#
# Nothing here infers geography. Every fact comes from the three registry CSVs
# (current, 2011 and 2001 freguesias), freguesia_names_2013.csv and the
# CAOP-derived pt_codes; this file only reshapes them and then proves, in
# verify_atom_model(), that the reshape is lossless.
#
# Why the shapes are what they are:
#   - NUTS is keyed on `dtmn`, not on the freguesia: every NUTS revision is a
#     regrouping of the same 308 municipios (asserted in
#     tests/testthat/test-vintage-invariants.R).
#   - health is keyed on the freguesia: uls/aces vary WITHIN a municipio in 5
#     of them, so a dtmn key would lose information.
#   - `share` is 1 everywhere today because every geography modelled is a union
#     of freguesias. It exists for geographies that do not nest.

# --- atoms ---------------------------------------------------------------------

#' The invariant territory units
#'
#' The 2011 freguesia partition, refined where another vintage cuts across it:
#'
#' * A 2011 freguesia carved out of TWO 2001 freguesias becomes one atom per
#'   part, with id "<2011 code>/<2001 code>" -- Boavista dos Pinheiros and Santa
#'   Cruz/Trindade. Everywhere else the 2001 map is coarser than the 2011 one.
#' * A later unit with no 2011 ancestry gets an atom of its own, id "X<code>".
#'   Those are freguesias CREATED after 2011 by subdividing a 2011 one -- Parque
#'   das Nacoes (110662, Lisboa, Lei 56/2012) is the real case.
#'
#' Both exception lists are computed, not hardcoded, so correcting a registry
#' shrinks them automatically and a genuinely new case is picked up.
build_atoms <- function(codes, xw, xw11, reg01) {
  a <- data.frame(
    atom_id   = xw11$dtmnfr_2011,
    atom_name = xw11$freguesia_2011,
    stringsAsFactors = FALSE
  )

  multi <- names(which(table(reg01$dtmnfr_2011) > 1L))
  if (length(multi)) {
    parts <- reg01[reg01$dtmnfr_2011 %in% multi, ]
    message(sprintf("  atoms: %d 2011 freguesia(s) with more than one 2001 predecessor: %s",
                    length(multi), paste(multi, collapse = ", ")))
    a <- rbind(a[!a$atom_id %in% multi, ], data.frame(
      atom_id   = paste0(parts$dtmnfr_2011, "/", parts$dtmnfr_2001),
      atom_name = a$atom_name[match(parts$dtmnfr_2011, a$atom_id)],
      stringsAsFactors = FALSE
    ))
  }

  orphans <- setdiff(codes$dtmnfr, xw11$dtmnfr)
  if (length(orphans)) {
    message(sprintf("  atoms: %d current freguesia(s) with no 2011 ancestry: %s",
                    length(orphans), paste(orphans, collapse = ", ")))
    a <- rbind(a, data.frame(
      atom_id   = paste0("X", orphans),
      atom_name = codes$freguesia[match(orphans, codes$dtmnfr)],
      stringsAsFactors = FALSE
    ))
  }
  a[order(a$atom_id), ]
}

#' Which unit each atom belongs to at each freguesia vintage
#'
#' Returned separately from `atoms` because it is membership, not identity, and
#' because the orphan atoms need their later-vintage codes filled from the
#' current crosswalk rather than the 2011 one. A split atom names its 2001 part
#' in its id; every other atom's 2011 unit has exactly one 2001 predecessor.
atom_freguesias <- function(atoms, codes, xw, xw11, reg01) {
  orphan <- startsWith(atoms$atom_id, "X")
  f2011 <- ifelse(orphan, NA_character_, sub("/.*$", "", atoms$atom_id))
  f2001 <- ifelse(grepl("/", atoms$atom_id, fixed = TRUE),
                  sub("^.*/", "", atoms$atom_id),
                  reg01$dtmnfr_2001[match(f2011, reg01$dtmnfr_2011)])
  i <- match(f2011, xw11$dtmnfr_2011)
  cur <- ifelse(orphan, sub("^X", "", atoms$atom_id), xw11$dtmnfr[i])
  j <- match(cur, xw$dtmnfr)
  data.frame(
    atom_id = atoms$atom_id,
    f2001   = f2001,
    f2011   = f2011,
    f2013   = xw$dtmnfr_2013[j],
    f2025   = cur,
    stringsAsFactors = FALSE
  )
}

# --- names ---------------------------------------------------------------------

# DGT's own simplification rule, recovered by inspection and verified against
# the current registry (3258/3259). NOT anchored: two names carry the phrase
# inside a parenthetical and are simplified in place. Guarded so it only fires
# when what remains begins with a capital -- the one name DGT leaves alone is
# "Uniao de freguesias da cidade de Santarem", where stripping would yield the
# lowercase fragment "cidade de Santarem".
UNIAO_RX <- "União d[aeo]s? freguesias d[eao]s? "

simplify_freguesia <- function(x) {
  out <- sub(UNIAO_RX, "", x)
  keep <- !is.na(out) & out != x & grepl("^[[:lower:]]", out)
  out[keep] <- x[keep]
  out
}

# NUTS II under the 2002 revision. pt_codes carries nuts2_2013 but has no
# equivalent for 2002, and the names cannot be derived: PT17 was "Lisboa" in
# 2002 and became "Area Metropolitana de Lisboa" in 2013. Taken from INE's own
# geo dimension labels on indicators published against "NUTS - 2002" (INE
# gives the codes without the PT prefix).
NUTS2_2002_NAMES <- c(
  PT11 = "Norte",
  PT15 = "Algarve",
  PT16 = "Centro",
  PT17 = "Lisboa",
  PT18 = "Alentejo",
  PT20 = "Região Autónoma dos Açores",
  PT30 = "Região Autónoma da Madeira"
)

# --- units and membership ------------------------------------------------------

# The administrative vintages, oldest first. Each is a column `f<vintage>` of
# atom_freguesias(). The two pre-2013 maps are named after the census that
# recorded them, because neither was made by a single law: freguesias were
# created one law at a time. The later two are named after their reform.
FREGUESIA_VINTAGES <- c("2001", "2011", "2013", "2025")

#' Assemble units + unit_names + membership from the current-grain tables
#'
#' `codes` is pt_codes: one row per current freguesia carrying every scheme at
#' its own vintage. An atom reaches all of them through its current unit, which
#' is why `cur` is the only join needed for the derived schemes. `names13` is
#' freguesia_names_2013.csv, already validated by derive_datasets.R.
build_units_membership <- function(atoms, af, codes, xw, xw11, reg01,
                                   names13 = NULL) {
  cur <- match(af$f2025, codes$dtmnfr)
  stopifnot(!anyNA(cur))

  units <- list(); memb <- list(); nms <- list()

  add <- function(scheme, vintage, code, name, simplified = NULL) {
    keep <- !is.na(code)
    memb[[length(memb) + 1L]] <<- data.frame(
      atom_id = atoms$atom_id[keep], scheme = scheme, vintage = vintage,
      unit_code = code[keep], share = 1, stringsAsFactors = FALSE)

    u <- unique(data.frame(scheme = scheme, vintage = vintage,
                           code = code[keep], name = name[keep],
                           stringsAsFactors = FALSE))
    # a code named in one source and NA in another must not become two units
    u <- u[order(u$code, is.na(u$name)), ]
    u <- u[!duplicated(u$code), ]
    units[[length(units) + 1L]] <<- u

    n <- data.frame(scheme = scheme, vintage = vintage, code = u$code,
                    name = u$name, kind = "official", stringsAsFactors = FALSE)
    if (!is.null(simplified)) {
      s <- unique(data.frame(code = code[keep], name = simplified[keep],
                             stringsAsFactors = FALSE))
      s <- s[match(u$code, s$code), ]
      extra <- !is.na(s$name) & !is.na(u$name) & s$name != u$name
      if (any(extra)) {
        n <- rbind(n, data.frame(scheme = scheme, vintage = vintage,
                                 code = u$code[extra], name = s$name[extra],
                                 kind = "simplified", stringsAsFactors = FALSE))
      }
    }
    nms[[length(nms) + 1L]] <<- n
  }

  # -- freguesia, four vintages.
  # 2001 names come from its registry; 2011 from the atom itself; 2025 from the
  # registry. 2013 names are the registry's freguesia_2013 column: the last name
  # each unit had on that map, from CAOP 2024 (fetch_2013_names.R).
  # derive_datasets.R has checked there is exactly one per 2013 freguesia.
  #
  # Simplified spellings are DERIVED for 2013 and asserted against DGT's for
  # 2025 in verify_atom_model(). DGT's own list for the 2013 map, in CAOP 2024,
  # leaves 32 unioes unsimplified ("Uniao das freguesias do Sabugal e ..."),
  # while INE publishes their short forms. 2001 and 2011 predate the unioes, so
  # they have none.
  f13_name <- xw$freguesia_2013[match(af$f2013, xw$dtmnfr_2013)]
  f01_name <- reg01$freguesia_2001[match(af$f2001, reg01$dtmnfr_2001)]
  add("freguesia", "2001", af$f2001, f01_name)
  add("freguesia", "2011", af$f2011, atoms$atom_name, simplify_freguesia(atoms$atom_name))
  add("freguesia", "2013", af$f2013, f13_name,        simplify_freguesia(f13_name))
  add("freguesia", "2025", af$f2025, codes$freguesia[cur],
      codes$designacao_simplificada[cur])

  # The names the 2013 map's freguesias carried before their last one: 25
  # renames by law, and spellings DGT later corrected. They are names OF the
  # 2013 vintage -- "Buarcos" was 060520's name from 2013 to 2015 -- so they
  # match there as its own names, and from any other vintage as historic ones.
  # Each comes with its simplified form, derived as for the official names; a
  # spelling the unit already has is not repeated.
  if (!is.null(names13) && nrow(names13) > 0L) {
    f <- data.frame(code = rep(names13$dtmnfr_2013, 2L),
                    name = c(names13$former_name,
                             simplify_freguesia(names13$former_name)),
                    stringsAsFactors = FALSE)
    have <- do.call(rbind, nms)
    have <- have[have$scheme == "freguesia" & have$vintage == "2013", ]
    f <- unique(f[!paste(f$code, f$name) %in% paste(have$code, have$name), ])
    nms[[length(nms) + 1L]] <- data.frame(
      scheme = "freguesia", vintage = "2013", code = f$code, name = f$name,
      kind = "former", stringsAsFactors = FALSE)
  }

  # -- municipio and distrito: the code carries them, per vintage. Names come
  # from one stable table because municipio codes have not moved since 1998.
  mn <- unique(codes[, c("dtmn", "municipio")])
  dn <- unique(codes[, c("dt", "distrito_ilha")])
  for (v in FREGUESIA_VINTAGES) {
    fc <- af[[paste0("f", v)]]
    dtmn <- substr(fc, 1L, 4L)
    dist <- substr(fc, 1L, 2L)
    add("municipio", v, dtmn, mn$municipio[match(dtmn, mn$dtmn)])
    add("distrito",  v, dist, dn$distrito_ilha[match(dist, dn$dt)])
  }

  # -- NUTS, keyed on the current unit because that is how pt_codes records it.
  # verify_atom_model() asserts this is indistinguishable from keying on the
  # vintage's own municipio.
  n1n <- unique(data.frame(cod = codes$nuts1_cod, nm = codes$nuts1))
  add("nuts1", "2024", codes$nuts1_cod[cur], codes$nuts1[cur])
  add("nuts2", "2024", codes$nuts2_cod[cur], codes$nuts2[cur])
  add("nuts3", "2024", codes$nuts3_cod[cur], codes$nuts3[cur])

  n1_13 <- substr(codes$nuts3_cod_2013[cur], 1L, 3L)
  add("nuts1", "2013", n1_13, n1n$nm[match(n1_13, n1n$cod)])
  add("nuts2", "2013", codes$nuts2_cod_2013[cur], codes$nuts2_2013[cur])
  add("nuts3", "2013", codes$nuts3_cod_2013[cur], codes$nuts3_2013[cur])

  # NUTS 2002: pt_codes carries NUTS3 only. NUTS1 is stable so its names carry
  # over. NUTS2 2002 codes are the NUTS3 prefix, and the names come from
  # NUTS2_2002_NAMES below -- six of the seven happen to match 2013, but PT17
  # does not, so the 2013 names cannot be borrowed wholesale.
  n1_02 <- substr(codes$nuts3_cod_2002[cur], 1L, 3L)
  n2_02 <- substr(codes$nuts3_cod_2002[cur], 1L, 4L)
  add("nuts1", "2002", n1_02, n1n$nm[match(n1_02, n1n$cod)])
  add("nuts2", "2002", n2_02, unname(NUTS2_2002_NAMES[n2_02]))
  add("nuts3", "2002", codes$nuts3_cod_2002[cur], codes$nuts3_2002[cur])

  # -- health. Freguesia-keyed: uls/aces vary within a municipio.
  add("reg_saude",      "2024", codes$reg_saude[cur],      codes$reg_saude[cur])
  add("uls",            "2024", codes$uls[cur],            codes$uls[cur])
  add("uls_municipio",  "2024", codes$uls_municipio[cur],  codes$uls_municipio[cur])
  add("reg_saude",      "2022", codes$reg_saude_2022[cur], codes$reg_saude_2022[cur])
  add("aces",           "2022", codes$aces[cur],           codes$aces[cur])
  add("aces_municipio", "2022", codes$aces_municipio[cur], codes$aces_municipio[cur])

  list(units = do.call(rbind, units),
       unit_names = unique(do.call(rbind, nms)),
       membership = do.call(rbind, memb))
}

# --- derived views -------------------------------------------------------------

#' The flat per-freguesia view, assembled for one choice of each axis
#'
#' The shape pt_lookup() returns, built from the atoms rather than the exported
#' tables. Used here to prove the reshape is lossless.
atom_lookup <- function(atoms, m, admin_vintage = "2025",
                        nuts_vintage = "2024", health_vintage = "2024") {
  pick <- function(scheme, vintage) {
    s <- m$membership[m$membership$scheme == scheme &
                        m$membership$vintage == vintage, ]
    code <- s$unit_code[match(atoms$atom_id, s$atom_id)]
    nm <- m$units$name[match(paste(scheme, vintage, code),
                             paste(m$units$scheme, m$units$vintage, m$units$code))]
    list(code = code, name = nm)
  }
  nm_of <- function(scheme, vintage, kind) {
    s <- m$unit_names[m$unit_names$scheme == scheme &
                        m$unit_names$vintage == vintage &
                        m$unit_names$kind == kind, ]
    s
  }
  f <- pick("freguesia", admin_vintage)
  simp <- nm_of("freguesia", admin_vintage, "simplified")
  simplified <- simp$name[match(f$code, simp$code)]

  out <- data.frame(
    dtmnfr = f$code, freguesia = f$name,
    designacao_simplificada = ifelse(is.na(simplified), f$name, simplified),
    stringsAsFactors = FALSE
  )
  mu <- pick("municipio", admin_vintage); di <- pick("distrito", admin_vintage)
  out$dtmn <- mu$code; out$municipio <- mu$name
  out$dt <- di$code; out$distrito_ilha <- di$name
  for (lv in c("nuts1", "nuts2", "nuts3")) {
    p <- pick(lv, nuts_vintage)
    out[[paste0(lv, "_cod")]] <- p$code; out[[lv]] <- p$name
  }
  out <- unique(out[!is.na(out$dtmnfr), ])
  out[order(out$dtmnfr), ]
}

#' Crosswalk between two administrative vintages, derived from shared atoms
#'
#' `relation` is computed, never stored. Cardinality separates merged/split;
#' comparing code and name separates unchanged / renumbered / renamed, so a
#' unit whose territory changed is told apart from one that was merely
#' renumbered.
atom_crosswalk <- function(m, from, to) {
  fm <- m$membership[m$membership$scheme == "freguesia" & m$membership$vintage == from, ]
  tm <- m$membership[m$membership$scheme == "freguesia" & m$membership$vintage == to, ]
  j <- merge(fm[, c("atom_id", "unit_code")], tm[, c("atom_id", "unit_code")],
             by = "atom_id", suffixes = c("_from", "_to"))
  p <- unique(j[, c("unit_code_from", "unit_code_to")])

  nm <- function(v, code) m$units$name[match(paste("freguesia", v, code),
                                             paste(m$units$scheme, m$units$vintage,
                                                   m$units$code))]
  p$name_from <- nm(from, p$unit_code_from)
  p$name_to   <- nm(to,   p$unit_code_to)

  n_to   <- table(p$unit_code_from)
  n_from <- table(p$unit_code_to)
  p$relation <- ifelse(
    n_to[p$unit_code_from] > 1, "split",
    ifelse(n_from[p$unit_code_to] > 1, "merged",
           ifelse(p$unit_code_from != p$unit_code_to, "renumbered",
                  ifelse(!is.na(p$name_from) & !is.na(p$name_to) &
                           p$name_from != p$name_to, "renamed", "unchanged"))))
  p[order(p$unit_code_to, p$unit_code_from), ]
}

# --- exported tables -----------------------------------------------------------

#' The three exported long tables
#'
#' Each is long on its own axis, so a vintage is visible on sight rather than
#' documented somewhere else.
build_exported <- function(atoms, af, m, codes) {
  code_of <- function(scheme, vintage) {
    s <- m$membership[m$membership$scheme == scheme & m$membership$vintage == vintage, ]
    s$unit_code[match(atoms$atom_id, s$atom_id)]
  }
  name_of <- function(scheme, vintage, code) {
    m$units$name[match(paste(scheme, vintage, code),
                       paste(m$units$scheme, m$units$vintage, m$units$code))]
  }
  simpl_of <- function(vintage, code) {
    s <- m$unit_names[m$unit_names$scheme == "freguesia" &
                        m$unit_names$vintage == vintage &
                        m$unit_names$kind == "simplified", ]
    s$name[match(code, s$code)]
  }

  # -- pt_registry: one row per (admin_vintage, freguesia).
  # Freguesia rows with dtmn denormalised, as in pt_codes -- a vintage's
  # municipio set is implied by its distinct dtmn values, so a pre-1998 vintage
  # would need no schema change.
  reg <- do.call(rbind, lapply(FREGUESIA_VINTAGES, function(v) {
    fc <- code_of("freguesia", v)
    if (all(is.na(fc))) return(NULL)
    simp <- simpl_of(v, fc)
    fn <- name_of("freguesia", v, fc)
    out <- data.frame(
      admin_vintage = v,
      dtmnfr = fc,
      freguesia = fn,
      designacao_simplificada = ifelse(is.na(simp), fn, simp),
      dtmn = code_of("municipio", v),
      municipio = name_of("municipio", v, code_of("municipio", v)),
      dt = code_of("distrito", v),
      distrito_ilha = name_of("distrito", v, code_of("distrito", v)),
      stringsAsFactors = FALSE
    )
    out <- unique(out[!is.na(out$dtmnfr), ])
    out[order(out$dtmnfr), ]
  }))
  rownames(reg) <- NULL

  # -- pt_nuts_codes: one row per (nuts_vintage, municipio). NUTS is constant
  # within dtmn -- asserted in tests/testthat/test-vintage-invariants.R -- so
  # 308 rows per revision is the whole fact.
  nuts <- do.call(rbind, lapply(c("2002", "2013", "2024"), function(v) {
    out <- data.frame(nuts_vintage = v, dtmn = code_of("municipio", "2025"),
                      stringsAsFactors = FALSE)
    for (lv in c("nuts1", "nuts2", "nuts3")) {
      cd <- code_of(lv, v)
      out[[paste0(lv, "_cod")]] <- cd
      out[[lv]] <- name_of(lv, v, cd)
    }
    out <- unique(out[!is.na(out$dtmn), ])
    out[order(out$dtmn), ]
  }))
  rownames(nuts) <- NULL

  # -- pt_health_codes: one row per (health_vintage, freguesia). Keyed on the
  # freguesia, not the municipio, because uls/aces vary WITHIN a municipio in 5
  # of them. `scheme` names the kind of local unit, which is not the same
  # concept across the reform: ACES were Agrupamentos de Centros de Saude, ULS
  # are Unidades Locais de Saude.
  #
  # Health mappings exist for the current freguesia vintage only.
  hv <- list(
    list(v = "2024", scheme = "uls",  rs = "reg_saude",
         unit = "uls",  mun = "uls_municipio"),
    list(v = "2022", scheme = "aces", rs = "reg_saude_2022",
         unit = "aces", mun = "aces_municipio")
  )
  health <- do.call(rbind, lapply(hv, function(h) {
    out <- data.frame(
      health_vintage = h$v,
      dtmnfr = codes$dtmnfr,
      reg_saude = codes[[h$rs]],
      scheme = h$scheme,
      unit = codes[[h$unit]],
      unit_municipio = codes[[h$mun]],
      stringsAsFactors = FALSE
    )
    out[order(out$dtmnfr), ]
  }))
  rownames(health) <- NULL

  list(pt_registry = reg, pt_nuts_codes = nuts, pt_health_codes = health)
}

#' Gate B: the exported tables say exactly what pt_codes says
#'
#' Note the health columns CANNOT be reproduced in one call: pt_codes carries
#' two health vintages side by side (reg_saude/uls next to reg_saude_2022/aces),
#' which the exported tables keep apart. They are checked one vintage at a time
#' instead.
verify_exported <- function(ex, baseline) {
  fail <- character(0)
  ok <- function(lab, cond, extra = "") {
    good <- isTRUE(cond)
    message(sprintf("  [%s] %-56s %s", if (good) "ok" else "FAIL", lab, extra))
    if (!good) fail <<- c(fail, lab)
  }

  reg <- ex$pt_registry
  cur <- reg[reg$admin_vintage == "2025", ]
  admin <- c("dtmnfr", "freguesia", "designacao_simplificada", "dtmn",
             "municipio", "dt", "distrito_ilha")
  b <- baseline[order(baseline$dtmnfr), admin]
  a <- cur[order(cur$dtmnfr), admin]
  rownames(a) <- NULL; rownames(b) <- NULL
  ok("pt_registry 2025 == pt_codes admin columns", identical(a, b))

  ok("pt_registry row counts per vintage",
     identical(as.integer(table(reg$admin_vintage)), c(4241L, 4260L, 3092L, 3259L)),
     paste(names(table(reg$admin_vintage)), table(reg$admin_vintage),
           sep = "=", collapse = " "))

  nuts <- ex$pt_nuts_codes
  ok("pt_nuts_codes is 308 rows per revision",
     all(table(nuts$nuts_vintage) == 308L),
     paste(names(table(nuts$nuts_vintage)), table(nuts$nuts_vintage),
           sep = "=", collapse = " "))
  ok("pt_nuts_codes has no missing names",
     !anyNA(nuts[, c("nuts1", "nuts2", "nuts3")]))

  # NUTS 2024 and 2013 against the columns pt_codes carries
  n24 <- nuts[nuts$nuts_vintage == "2024", ]
  i <- match(baseline$dtmn, n24$dtmn)
  ok("pt_nuts_codes 2024 == pt_codes NUTS 2024 columns",
     identical(n24$nuts3_cod[i], baseline$nuts3_cod) &&
       identical(n24$nuts3[i], baseline$nuts3) &&
       identical(n24$nuts2_cod[i], baseline$nuts2_cod) &&
       identical(n24$nuts1[i], baseline$nuts1))
  n13 <- nuts[nuts$nuts_vintage == "2013", ]
  j <- match(baseline$dtmn, n13$dtmn)
  ok("pt_nuts_codes 2013 == pt_codes NUTS 2013 columns",
     identical(n13$nuts3_cod[j], baseline$nuts3_cod_2013) &&
       identical(n13$nuts3[j], baseline$nuts3_2013) &&
       identical(n13$nuts2_cod[j], baseline$nuts2_cod_2013) &&
       identical(n13$nuts2[j], baseline$nuts2_2013))
  n02 <- nuts[nuts$nuts_vintage == "2002", ]
  k <- match(baseline$dtmn, n02$dtmn)
  ok("pt_nuts_codes 2002 == pt_codes NUTS 2002 column",
     identical(n02$nuts3_cod[k], baseline$nuts3_cod_2002) &&
       identical(n02$nuts3[k], baseline$nuts3_2002))

  h <- ex$pt_health_codes
  h24 <- h[h$health_vintage == "2024", ]; i24 <- match(baseline$dtmnfr, h24$dtmnfr)
  h22 <- h[h$health_vintage == "2022", ]; i22 <- match(baseline$dtmnfr, h22$dtmnfr)
  ok("pt_health_codes 2024 == pt_codes reg_saude/uls columns",
     identical(h24$reg_saude[i24], baseline$reg_saude) &&
       identical(h24$unit[i24], baseline$uls) &&
       identical(h24$unit_municipio[i24], baseline$uls_municipio))
  ok("pt_health_codes 2022 == pt_codes reg_saude_2022/aces columns",
     identical(h22$reg_saude[i22], baseline$reg_saude_2022) &&
       identical(h22$unit[i22], baseline$aces) &&
       identical(h22$unit_municipio[i22], baseline$aces_municipio))

  if (length(fail)) {
    stop(sprintf("Gate B failed: %s", paste(fail, collapse = "; ")), call. = FALSE)
  }
  invisible(TRUE)
}

# --- Gate A --------------------------------------------------------------------

#' Prove the reshape is lossless, or stop the build
verify_atom_model <- function(atoms, af, m, codes, xw, xw11, reg01) {
  fail <- character(0)
  ok <- function(lab, cond, extra = "") {
    good <- isTRUE(cond)
    message(sprintf("  [%s] %-56s %s", if (good) "ok" else "FAIL", lab, extra))
    if (!good) fail <<- c(fail, lab)
  }

  # structure
  ok("atom_id unique", !anyDuplicated(atoms$atom_id))
  ok("membership single-valued per (atom, scheme, vintage)",
     !any(duplicated(m$membership[, c("atom_id", "scheme", "vintage")])))
  ok("unit codes unique per (scheme, vintage)",
     !any(duplicated(m$units[, c("scheme", "vintage", "code")])))
  ok("every membership unit exists in units",
     all(paste(m$membership$scheme, m$membership$vintage, m$membership$unit_code) %in%
           paste(m$units$scheme, m$units$vintage, m$units$code)))
  ok("shares sum to 1 per (atom, scheme, vintage)",
     all(tapply(m$membership$share,
                paste(m$membership$atom_id, m$membership$scheme,
                      m$membership$vintage), sum) == 1))

  # the simplification rule
  der <- simplify_freguesia(codes$freguesia)
  ok("DGT's simplify rule reproduces designacao_simplificada",
     identical(der, codes$designacao_simplificada),
     sprintf("(%d/%d)", sum(der == codes$designacao_simplificada), nrow(codes)))

  # NUTS keyed on the current unit is indistinguishable from keying on the
  # vintage's own municipio -- true only while no transferred freguesia crosses
  # a NUTS boundary. If this fires, NUTS membership must become vintage-keyed.
  n3 <- unique(codes[, c("dtmn", "nuts3_cod_2002")])
  n_moved <- 0L; cross <- FALSE
  for (old in c("f2001", "f2011")) {
    moved <- which(substr(af[[old]], 1, 4) != substr(af$f2025, 1, 4) & !is.na(af[[old]]))
    n_moved <- n_moved + length(moved)
    cross <- cross ||
      any(n3$nuts3_cod_2002[match(substr(af[[old]][moved], 1, 4), n3$dtmn)] !=
            n3$nuts3_cod_2002[match(substr(af$f2025[moved], 1, 4), n3$dtmn)])
  }
  ok("no transferred freguesia crosses a NUTS 2002 boundary", !cross,
     sprintf("(%d atom(s) transferred)", n_moved))

  # losslessness
  lk <- atom_lookup(atoms, m)
  base <- codes[order(codes$dtmnfr), names(lk)]
  rownames(lk) <- NULL; rownames(base) <- NULL
  ok("lookup reconstructs pt_codes admin+NUTS columns", identical(lk, base),
     sprintf("(%d vs %d rows)", nrow(lk), nrow(base)))
  if (!identical(lk, base)) {
    for (cc in names(lk)) if (!identical(lk[[cc]], base[[cc]]))
      message(sprintf("       differs: %-24s %d value(s)", cc,
                      sum(lk[[cc]] != base[[cc]], na.rm = TRUE)))
  }

  x13 <- atom_crosswalk(m, "2013", "2025")
  ok("derived crosswalk == pt_crosswalk code pairs",
     setequal(paste(x13$unit_code_from, x13$unit_code_to),
              paste(xw$dtmnfr_2013, xw$dtmnfr)))
  x11 <- atom_crosswalk(m, "2011", "2025")
  ok("derived crosswalk == pt_crosswalk_2011 code pairs",
     setequal(paste(x11$unit_code_from, x11$unit_code_to),
              paste(xw11$dtmnfr_2011, xw11$dtmnfr)))
  x01 <- atom_crosswalk(m, "2001", "2011")
  ok("derived 2001 -> 2011 pairs == freguesia_registry_2001",
     setequal(paste(x01$unit_code_from, x01$unit_code_to),
              paste(reg01$dtmnfr_2001, reg01$dtmnfr_2011)),
     sprintf("(%d pairs)", nrow(x01)))
  u01 <- m$units[m$units$scheme == "freguesia" & m$units$vintage == "2001", ]
  ok("every 2001 freguesia is a unit, and named",
     setequal(u01$code, reg01$dtmnfr_2001) && !anyNA(u01$name),
     sprintf("(%d units)", nrow(u01)))

  if (length(fail)) {
    stop(sprintf("Gate A failed: %s", paste(fail, collapse = "; ")), call. = FALSE)
  }
  invisible(TRUE)
}
