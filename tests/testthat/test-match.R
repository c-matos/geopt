# The four full-registry sweeps (every freguesia name through pt_match()) take
# about two minutes together, so they run only when asked for. Set
# GEOPT_TEST_REGISTRY=true to run them, and do so after any change to the
# matching code or NAME_VARIANTS.
skip_registry_sweep <- function() {
  if (!identical(Sys.getenv("GEOPT_TEST_REGISTRY"), "true")) {
    testthat::skip("Full-registry sweep skipped. Set GEOPT_TEST_REGISTRY=true to run.")
  }
}

# --- pt_normalize ----------------------------------------------------------------

test_that("pt_normalize unifies case, accents, and punctuation", {
  expect_equal(pt_normalize("SÃO JORGE"), "sao jorge")
  expect_equal(pt_normalize("Sao-Jorge"), "sao jorge")
  expect_equal(pt_normalize("  são  jorge  "), "sao jorge")
  expect_equal(pt_normalize("Câmara de Lobos"), "camara de lobos")
})

test_that("pt_normalize expands abbreviations", {
  expect_equal(pt_normalize("S. Jorge"), "sao jorge")
  expect_equal(pt_normalize("Sta. Maria"), "santa maria")
  expect_equal(pt_normalize("Sto. António"), "santo antonio")
  # Bare 's' without a dot is not expanded
  expect_equal(pt_normalize("s jorge"), "s jorge")
})

test_that("pt_normalize handles vectors and NA", {
  out <- pt_normalize(c("S. Jorge", NA, "PORTO"))
  expect_equal(out[1], "sao jorge")
  expect_true(is.na(out[2]))
  expect_equal(out[3], "porto")
})

# --- pt_pad_code -------------------------------------------------------------------

test_that("pt_pad_code pads digit codes to official widths", {
  expect_equal(pt_pad_code(c(115, 1106), "municipio"), c("0115", "1106"))
  expect_equal(pt_pad_code("10103", "freguesia"), "010103")
  expect_equal(pt_pad_code(1, "distrito"), "01")
  expect_equal(pt_pad_code("115", "dtmn"), "0115")
})

test_that("pt_pad_code leaves non-digit values unchanged and validates level", {
  expect_equal(pt_pad_code(c("115", "Porto"), "municipio"), c("0115", "Porto"))
  expect_error(pt_pad_code("115", "nuts3"), "Invalid level")
})

# --- pt_match: exact ----------------------------------------------------------------

lookup_dtmn <- function(nm) {
  codes <- pt_lookup()
  unique(codes$dtmn[codes$municipio == nm])
}

test_that("pt_match resolves unambiguous municipality names", {
  out <- pt_match(c("Porto", "lisboa", "Câmara de Lobos"))
  expect_equal(out[1], lookup_dtmn("Porto"), ignore_attr = TRUE)
  expect_equal(out[2], lookup_dtmn("Lisboa"), ignore_attr = TRUE)
  expect_equal(out[3], lookup_dtmn("Câmara de Lobos"), ignore_attr = TRUE)
})

test_that("pt_match returns NA with a warning for ambiguous names", {
  expect_warning(out <- pt_match("Lagoa"), "ambiguous")
  expect_true(is.na(out))
  rep <- pt_match_report(out)
  expect_equal(rep$method, "ambiguous")
})

test_that("qualifiers in the name disambiguate", {
  out <- suppressWarnings(pt_match(c(
    "Lagoa (Faro)", "Lagoa (Açores)", "Lagoa (R.A.A.)", "Lagoa [Faro]"
  )))
  expect_false(any(is.na(out)))
  expect_equal(out[2], out[3], ignore_attr = TRUE)
  expect_false(out[1] == out[2])
  expect_equal(out[1], out[4], ignore_attr = TRUE)
})

test_that("the context argument disambiguates", {
  faro <- pt_match("Lagoa", context = "Faro")
  azores <- pt_match("Lagoa", context = "Açores")
  expect_false(is.na(faro))
  expect_false(is.na(azores))
  expect_false(faro == azores)

  # context recycles and can vary per element; there is no Lagoa municipality
  # in Madeira, so the second element is unmatched (not the Faro/Açores one)
  both <- suppressWarnings(pt_match(c("Lagoa", "Lagoa"), context = c("Faro", "Madeira")))
  expect_false(is.na(both[1]))
  expect_true(is.na(both[2]))
})

test_that("freguesia matching requires context for reused names", {
  codes <- pt_lookup()
  reused <- names(which(table(codes$freguesia) > 1))[1]
  mun <- codes$municipio[codes$freguesia == reused][1]

  expect_warning(out <- pt_match(reused, level = "freguesia"), "ambiguous")
  expect_true(is.na(out))

  out <- pt_match(reused, level = "freguesia", context = mun)
  expect_false(is.na(out))
  expect_equal(substr(out, 1, 4), codes$dtmn[codes$municipio == mun][1],
               ignore_attr = TRUE)
})

test_that("unrecognized context warns", {
  expect_warning(out <- pt_match("Porto", context = "Narnia"),
                 "context was not recognized")
  # It still reports method context_unrecognized (no silent unscoped match)
  expect_true(is.na(out))
})

test_that("the context warning names the contexts that failed, with row counts", {
  expect_warning(
    pt_match(c("Porto", "Braga", "Faro"), context = c("Narnia", "Narnia", "Mordor")),
    "3 input(s) returned NA because their context was not recognized: 'Narnia' (2 rows), 'Mordor' (1 row). A context must name the distrito, nuts3, nuts2 or nuts1 an input belongs to.",
    fixed = TRUE
  )
  # a trailing parenthetical tried as the context is named too
  expect_warning(pt_match("Lagoa (Narnia)"), "'Narnia' (1 row)", fixed = TRUE)
})

# --- pt_match: codes and targets ------------------------------------------------------

test_that("codes pass through, padded", {
  out <- pt_match(c("0115", "115"), quiet = TRUE)
  expect_equal(unname(out[1]), unname(out[2]))
  rep <- pt_match_report(out)
  expect_true(all(rep$method == "code"))
})

test_that("NUTS codes pass through at nuts levels", {
  codes <- pt_lookup()
  a_code <- codes$nuts3_cod[1]
  out <- pt_match(tolower(a_code), level = "nuts3", quiet = TRUE)
  expect_equal(out, a_code, ignore_attr = TRUE)
})

test_that("`to` maps to any pt_lookup() column representable at the level", {
  out <- pt_match("Porto", to = "nuts2", quiet = TRUE)
  expect_equal(out, "Norte", ignore_attr = TRUE)

  # dtmnfr is not representable at municipio level -> NA
  out <- pt_match("Porto", to = "dtmnfr", quiet = TRUE)
  expect_true(is.na(out))

  expect_error(pt_match("Porto", to = "nope"), "column of pt_lookup")
})

test_that("`to` follows the requested NUTS revision", {
  # The axes are independent, so `to` names a level and the vintage arguments
  # say which nomenclature that level is expressed in.
  expect_equal(pt_match("Leiria", to = "nuts3", quiet = TRUE),
               "Região de Leiria", ignore_attr = TRUE)
  expect_equal(pt_match("Leiria", to = "nuts3", nuts_vintage = "2013",
                        quiet = TRUE),
               "Região de Leiria", ignore_attr = TRUE)
  expect_equal(pt_match("Leiria", to = "nuts3", nuts_vintage = "2002",
                        quiet = TRUE),
               "Pinhal Litoral", ignore_attr = TRUE)
})

test_that("`to` reaches the health geographies, per vintage", {
  expect_equal(pt_match("Porto", level = "municipio", to = "unit_municipio",
                        health_vintage = "2024", quiet = TRUE),
               pt_match("Porto", level = "municipio", to = "unit_municipio",
                        quiet = TRUE),
               ignore_attr = TRUE)
  aces <- pt_match("Porto", level = "municipio", to = "unit_municipio",
                   health_vintage = "2022", quiet = TRUE)
  uls <- pt_match("Porto", level = "municipio", to = "unit_municipio",
                  health_vintage = "2024", quiet = TRUE)
  expect_false(identical(unname(aces), unname(uls)))
})

test_that("an unknown vintage is an error even where the level ignores it", {
  # ULS exist in the 2024 health geography only, so a real health vintage is
  # ignored at that level; one that isn't a health vintage at all is a mistake
  expect_equal(pt_match("ULS Coimbra", level = "uls", health_vintage = "2022",
                        quiet = TRUE),
               pt_match("ULS Coimbra", level = "uls", quiet = TRUE),
               ignore_attr = TRUE)
  # ... and so is it for `to`, which would otherwise be read off the ACES table
  expect_no_warning(
    to22 <- pt_match("ULS Coimbra", level = "uls", to = "nuts1",
                     health_vintage = "2022", quiet = TRUE)
  )
  expect_equal(to22, "Continente", ignore_attr = TRUE)
  expect_error(pt_match("ULS Coimbra", level = "uls", health_vintage = "banana",
                        quiet = TRUE), "`health_vintage` must be one of")
  expect_error(pt_match("Porto", health_vintage = "2023", quiet = TRUE),
               "`health_vintage` must be one of")
  expect_error(pt_match("Porto", nuts_vintage = "2025", quiet = TRUE),
               "`nuts_vintage` must be one of")
})

test_that("nuts and uls levels match by name", {
  out <- pt_match("Norte", level = "nuts2", quiet = TRUE)
  expect_equal(out, "PT11", ignore_attr = TRUE)

  a_uls <- pt_lookup(health_vintage = "2024")$unit[1]
  out <- pt_match(a_uls, level = "uls", quiet = TRUE)
  expect_equal(out, a_uls, ignore_attr = TRUE)
})

# --- pt_match: aliases ------------------------------------------------------------------

test_that("aliases map variant spellings to canonical names or codes", {
  out <- pt_match("Invicta", aliases = c("Invicta" = "Porto"), quiet = TRUE)
  expect_equal(out, lookup_dtmn("Porto"), ignore_attr = TRUE)
  expect_equal(pt_match_report(out)$method, "alias")

  # Alias directly to a code
  out <- pt_match("A Capital", aliases = c("a capital" = "1106"), quiet = TRUE)
  expect_equal(out, "1106", ignore_attr = TRUE)

  expect_error(pt_match("x", aliases = c("unnamed")), "named character vector")
})

# --- pt_match: fuzzy ---------------------------------------------------------------------

test_that("fuzzy matching catches typos, opt-in only", {
  skip_if_not_installed("stringdist")

  # Without fuzzy: unmatched
  expect_warning(out <- pt_match("Guimaraess"), "unmatched")
  expect_true(is.na(out))

  # With fuzzy: matched and reported via message
  expect_message(
    out <- pt_match("Guimaraess", fuzzy = TRUE),
    "fuzzy match"
  )
  expect_equal(out, lookup_dtmn("Guimarães"), ignore_attr = TRUE)
  rep <- pt_match_report(out)
  expect_equal(rep$method, "fuzzy")
  expect_true(rep$dist > 0)
})

test_that("fuzzy never overrides exact matches or resolves ties", {
  skip_if_not_installed("stringdist")

  out <- pt_match("Porto", fuzzy = TRUE, quiet = TRUE)
  expect_equal(pt_match_report(out)$method, "exact")
})

# --- Report and edge cases -----------------------------------------------------------------

test_that("the report tracks every input", {
  out <- suppressWarnings(pt_match(c("Porto", "Lagoa", "Atlantis", NA, "")))
  rep <- pt_match_report(out)
  expect_equal(nrow(rep), 5L)
  expect_equal(rep$method, c("exact", "ambiguous", "unmatched", "empty", "empty"))
})

test_that("pt_match_report errors on objects without a report", {
  expect_error(pt_match_report("plain vector"), "no match report")
})

test_that("quiet = TRUE suppresses warnings and messages", {
  expect_silent(pt_match(c("Lagoa", "Atlantis"), quiet = TRUE))
})

test_that("pt_match validates inputs", {
  expect_error(pt_match("Porto", level = "planeta"), "Invalid level")
  expect_error(pt_match("Porto", context = c("a", "b")), "length 1 or length")
})

# --- curated name variants -----------------------------------------------------

test_that("alternative official spellings resolve", {
  # "Vila da Praia da Vitoria" is the other official form
  expect_equal(pt_match("Vila da Praia da Vitoria", quiet = TRUE),
               "4302", ignore_attr = TRUE)
  expect_equal(pt_match("Praia da Vitoria", quiet = TRUE),
               "4302", ignore_attr = TRUE)

  # pt_registry stores the Azorean Calheta as "Calheta de Sao Jorge"; the plain
  # name is accepted as a variant, so INE-style qualified forms work.
  expect_equal(pt_match("Calheta (R.A.A.)", quiet = TRUE),
               "4501", ignore_attr = TRUE)
  expect_equal(pt_match("Calheta (Madeira)", quiet = TRUE),
               "3101", ignore_attr = TRUE)

  # distrito level
  expect_equal(pt_match("Ilha Graciosa", level = "distrito", quiet = TRUE),
               "44", ignore_attr = TRUE)
})

test_that("a variant that collides is reported as ambiguous, not guessed", {
  # Madeira and the Azores each have a Calheta, so a bare "Calheta" must fail
  # loudly rather than silently match one of them.
  expect_warning(res <- pt_match("Calheta"), "ambiguous")
  expect_true(is.na(res[1]))
  expect_equal(pt_match_report(res)$method, "ambiguous")
})

test_that("the R.A. abbreviation styles are understood as context", {
  for (x in c("Lagoa (R.A.A.)", "Lagoa [R.A. Acores]", "Lagoa (Acores)")) {
    expect_equal(pt_match(x, quiet = TRUE), "4201", ignore_attr = TRUE,
                 info = x)
  }
  expect_equal(pt_match("Lagoa (Faro)", quiet = TRUE), "0806", ignore_attr = TRUE)
})

test_that("particle-insensitive fallback resolves official designations", {
  # Official ULS names carry an article that pt_health_codes' short style drops.
  expect_equal(pt_match("ULS da Guarda", level = "uls", quiet = TRUE),
               "ULS Guarda", ignore_attr = TRUE)
  expect_equal(pt_match("ULS do Alto Minho", level = "uls", quiet = TRUE),
               "ULS Alto Minho", ignore_attr = TRUE)
  expect_equal(pt_match("ULS Trás-os-Montes Alto Douro", level = "uls", quiet = TRUE),
               "ULS Trás-os-Montes e Alto Douro", ignore_attr = TRUE)
  expect_equal(pt_match("Lisboa e Vale do Tejo", level = "reg_saude", quiet = TRUE),
               "LVT", ignore_attr = TRUE)

  # Reported as "loose" so the fallback is visible; exact spellings stay "exact"
  r <- pt_match(c("ULS da Guarda", "ULS Guarda"), level = "uls", quiet = TRUE)
  expect_equal(pt_match_report(r)$method, c("loose", "exact"))
})

test_that("dash-separated qualifiers are read, but only when the tail is a region", {
  for (x in c("Calheta - RAA", "Calheta-R.A.A", "Calheta - R.A. Açores",
              "Calheta \u2013 RAA")) {
    expect_equal(pt_match(x, quiet = TRUE), "4501", ignore_attr = TRUE, info = x)
  }
  expect_equal(pt_match("Lagoa - Faro", quiet = TRUE), "0806", ignore_attr = TRUE)

  # Names that simply contain a dash must never be split
  expect_equal(pt_match(c("Albergaria-a-Velha", "Montemor-o-Novo"), quiet = TRUE),
               c("0102", "0706"), ignore_attr = TRUE)
  expect_equal(pt_match("ULS Almada-Seixal", level = "uls", quiet = TRUE),
               "ULS Almada-Seixal", ignore_attr = TRUE)
  expect_equal(pt_match("Algueirão-Mem Martins", level = "freguesia", quiet = TRUE),
               "111102", ignore_attr = TRUE)
})

test_that("older freguesia names resolve, and their collisions need a context", {
  # An earlier name of a 2013 freguesia ("Rua" until 2017), and a misspelling
  expect_equal(pt_match("Rua", level = "freguesia", quiet = TRUE),
               "180716", ignore_attr = TRUE)
  expect_equal(pt_match("Paços de Gaiola", level = "freguesia", quiet = TRUE),
               "130742", ignore_attr = TRUE)

  # "Passos" is both the old name of Paços (Fafe) and a live freguesia in
  # Mirandela, so bare it is ambiguous -- and a context settles it either way.
  expect_warning(pt_match("Passos", level = "freguesia"), "ambiguous")
  expect_equal(pt_match("Passos", level = "freguesia", context = "Mirandela",
                        quiet = TRUE), "040724", ignore_attr = TRUE)
  expect_equal(pt_match("Passos", level = "freguesia", context = "Fafe",
                        quiet = TRUE), "030719", ignore_attr = TRUE)
})

test_that("a name that ends in a parenthetical is not mistaken for a qualifier", {
  # INE-style saint qualifiers and post-2013 union names are part of the
  # official name, not a context to be stripped off it.
  expect_equal(pt_match("Bouro (Santa Maria)", level = "freguesia", quiet = TRUE),
               "030119", ignore_attr = TRUE)
  expect_equal(pt_match("Bouro (Santa Marta)", level = "freguesia", quiet = TRUE),
               "030120", ignore_attr = TRUE)
  expect_equal(pt_match("Braga (São Vicente)", level = "freguesia", quiet = TRUE),
               "030349", ignore_attr = TRUE)
  expect_equal(
    pt_match("União das freguesias de Braga (Maximinos, Sé e Cividade)",
             level = "freguesia", quiet = TRUE),
    "030364", ignore_attr = TRUE
  )

  # A real name wins, but a genuine qualifier still parses
  expect_equal(pt_match("Lagoa (Açores)", quiet = TRUE), "4201", ignore_attr = TRUE)
  expect_equal(pt_match("Lagoa (Faro)", quiet = TRUE), "0806", ignore_attr = TRUE)
  expect_equal(pt_match("Calheta (R.A.M.)", quiet = TRUE), "3101", ignore_attr = TRUE)
  expect_equal(pt_match("Pinheiro (Guimarães)", level = "freguesia", quiet = TRUE),
               "030836", ignore_attr = TRUE)

  # The literal pass is exact-only, so it never invents a match of its own
  expect_true(is.na(pt_match("Bourro (Santa Maria)", level = "freguesia",
                             quiet = TRUE)))
})

test_that("pre-2013 freguesia names resolve to the unit covering them today", {
  # Sé, Maximinos and Cividade were dissolved into one união in 2013; each
  # resolves to it.
  for (nm in c("Sé", "Maximinos", "Cividade")) {
    expect_equal(pt_match(nm, level = "freguesia", context = "Braga", quiet = TRUE),
                 "030364", ignore_attr = TRUE, info = nm)
  }
  m <- pt_match("Sé", level = "freguesia", context = "Braga", quiet = TRUE)
  expect_equal(pt_match_report(m)$method, "historic")

  # INE writes the city's parishes as "Braga (Sé)"; a qualifier is the more
  # natural way to type it. Both are the same unit.
  expect_equal(pt_match("Braga (Sé)", level = "freguesia", quiet = TRUE),
               "030364", ignore_attr = TRUE)
  expect_equal(pt_match("Sé (Braga)", level = "freguesia", quiet = TRUE),
               "030364", ignore_attr = TRUE)

  # Pombalinho transferred Santarém -> Golegã, so both parents scope it
  expect_equal(pt_match("Pombalinho", level = "freguesia", context = "Santarém",
                        quiet = TRUE), "141203", ignore_attr = TRUE)
  expect_equal(pt_match("Pombalinho", level = "freguesia", context = "Golegã",
                        quiet = TRUE), "141203", ignore_attr = TRUE)
})

test_that("a bare name plus a context is recombined into INE's spellings", {
  # Only "Braga (Se)" is stored; "Se" + context Braga is rebuilt at match time.
  r11 <- pt_lookup(admin_vintage = "2011")
  succ <- pt_crosswalk("2011", "2025")
  r11$successor <- succ$to[match(r11$dtmnfr, succ$from)]
  expect_true("Braga (Sé)" %in% r11$freguesia)
  expect_false("Sé" %in% r11$freguesia[r11$municipio == "Braga"])

  # every city-prefixed pre-2013 name is reachable from its bare form
  city <- r11[grepl("^(.*) \\(([^()]+)\\)$", r11$freguesia), ]
  city <- city[pt_normalize(sub(" \\(.*$", "", city$freguesia)) ==
                 pt_normalize(city$municipio), ]
  expect_gt(nrow(city), 100L)
  bare <- sub("^.*\\((.*)\\)$", "\\1", city$freguesia)
  got <- pt_match(bare, level = "freguesia", context = city$municipio, quiet = TRUE)
  expect_equal(sum(!is.na(got) & got == city$successor), nrow(city))

  # the construction needs a context; it is not applied blindly
  expect_true(is.na(pt_match("Cividade", level = "freguesia", quiet = TRUE)))
})

test_that("a context with two readings is tried narrowest-first", {
  # Bare "Calheta" is Madeira's municipio in the registry AND the Azorean one via
  # NAME_VARIANTS. The readings are tried in order and the NAME decides: only
  # when it is absent from Madeira does the Azorean reading get used.
  mad <- c("Arco da Calheta", "Prazeres", "Jardim do Mar")
  for (nm in mad) {
    got <- pt_match(nm, level = "freguesia", context = "Calheta", quiet = TRUE)
    expect_equal(substr(got, 1L, 4L), "3101", ignore_attr = TRUE, info = nm)   # Madeira
  }
  # "Calheta" is a freguesia of BOTH, so the first reading must win outright
  expect_equal(pt_match("Calheta", level = "freguesia", context = "Calheta",
                        quiet = TRUE),
               "310102", ignore_attr = TRUE)
  # these exist only in Sao Jorge, so the second reading is reached
  for (nm in c("Norte Pequeno", "Ribeira Seca", "Santo Antão",
               "Topo (Nossa Senhora do Rosário)")) {
    got <- pt_match(nm, level = "freguesia", context = "Calheta", quiet = TRUE)
    expect_equal(substr(got, 1L, 4L), "4501", ignore_attr = TRUE, info = nm)   # Acores
  }
})

test_that("a region qualifier on the context constrains, not just strips", {
  # Discarding "(Madeira)" would let NAME_VARIANTS' bare "Calheta" reach the
  # Azorean unit -- the qualifier has to rule that reading out.
  expect_equal(pt_match("Calheta", level = "freguesia",
                        context = "Calheta (Madeira)", quiet = TRUE),
               "310102", ignore_attr = TRUE)
  expect_equal(pt_match("Calheta", level = "freguesia",
                        context = "Calheta (R.A.A.)", quiet = TRUE),
               "450101", ignore_attr = TRUE)
  expect_equal(pt_match("Calheta", level = "freguesia",
                        context = "Calheta de São Jorge", quiet = TRUE),
               "450101", ignore_attr = TRUE)
})

test_that("a bare name shared by several cities' parishes stays ambiguous", {
  # "Sé" was a freguesia in Braga, Lisboa, Porto, Faro, Guarda, Lamego... A name
  # present TWICE inside a reading is an answer, not a miss, so the next
  # reading must not be tried -- that would invent a match.
  expect_true(is.na(pt_match("Sé", level = "freguesia", quiet = TRUE)))
  expect_warning(pt_match("Sé", level = "freguesia"), "ambiguous")
})

test_that("both Paços and Passos resolve, for every unit INE spells either way", {
  # INE publishes BOTH spellings for the SAME unit across different dimensions,
  # so whichever the registry carries, the other has to be accepted. Each bare
  # form is therefore ambiguous and needs a context -- which INE's data has.
  want <- c(Mirandela = "040724", Sabrosa = "171007", Fafe = "030719")
  for (mun in names(want)) {
    for (nm in c("Paços", "Passos")) {
      expect_equal(
        pt_match(nm, level = "freguesia", context = mun, quiet = TRUE),
        want[[mun]], ignore_attr = TRUE,
        info = paste(nm, mun)
      )
    }
  }
  # 030412 merged, so both spellings land on the unit covering it today
  for (nm in c("Paços", "Passos")) {
    expect_equal(
      pt_match(nm, level = "freguesia", context = "Cabeceiras de Basto",
               quiet = TRUE),
      "030418", ignore_attr = TRUE, info = nm
    )
  }
})

test_that("a NAME_VARIANTS row can be stated at a non-current vintage", {
  # "Paços" is INE's other spelling of Cabeceiras de Basto's 2011 freguesia
  # 030412 ("Passos"). That unit merged in 2013, so the variant cannot be keyed
  # on a current code -- it is stated at 2011.
  expect_equal(
    pt_match("Paços", level = "freguesia", context = "Cabeceiras de Basto",
             admin_vintage = "2011", quiet = TRUE),
    "030412", ignore_attr = TRUE
  )
})

test_that("a 2013 union that split in 2025 is found on its own map only", {
  # "Penha Longa e Paços de Gaiolo" is 130738's name on the 2013 map (it was
  # "Penhalonga e ..." until Lei 20/2017). At the current vintage it is
  # genuinely unresolvable: two units cover it.
  expect_equal(
    pt_match("Penha Longa e Paços de Gaiolo", level = "freguesia",
             context = "Marco de Canaveses", admin_vintage = "2013",
             quiet = TRUE),
    "130738", ignore_attr = TRUE
  )
  expect_true(is.na(
    pt_match("Penha Longa e Paços de Gaiolo", level = "freguesia",
             context = "Marco de Canaveses", quiet = TRUE)))
})

test_that("`admin_vintage` returns codes of that vintage, not the current one", {
  # The same name resolves either to the unit covering it today or, with
  # `admin_vintage`, to the unit it WAS.
  expect_equal(
    pt_match(c("Sé", "Maximinos", "Cividade"), level = "freguesia",
             context = "Braga", admin_vintage = "2011", quiet = TRUE),
    c("030352", "030324", "030307"), ignore_attr = TRUE
  )
  expect_equal(pt_match("Sé", level = "freguesia", context = "Braga",
                        admin_vintage = "2011", to = "freguesia", quiet = TRUE),
               "Braga (Sé)", ignore_attr = TRUE)

  # default stays the current vintage: an old name resolves to the unit covering
  # its territory today
  expect_equal(pt_match("Sé", level = "freguesia", context = "Braga",
                        quiet = TRUE),
               "030364", ignore_attr = TRUE)
})

test_that("`admin_vintage` is validated against the vintages that exist", {
  expect_error(pt_match("Porto", admin_vintage = "1999"),
               "`admin_vintage` must be one of")
  expect_error(pt_match("Sé", level = "freguesia", to = "nope"),
               "column of pt_lookup")
})

test_that("`admin_vintage = auto` detects the vintage from the input", {
  # The ineptr2 case: INE publishes the 2013 freguesia set, whose disaggregated
  # units are ambiguous against the current registry but exact against their own.
  nm <- "União das freguesias de Conde e Gandarela"
  expect_true(is.na(pt_match(nm, level = "freguesia", context = "Guimarães",
                             quiet = TRUE)))
  expect_equal(pt_match(nm, level = "freguesia", context = "Guimarães",
                        admin_vintage = "auto", quiet = TRUE),
               "030882", ignore_attr = TRUE)

  # and it reports the choice rather than making it silently
  expect_message(
    pt_match(nm, level = "freguesia", context = "Guimarães",
             admin_vintage = "auto"),
    "2013 freguesia vintage")

  # current names give no reason to move off the current vintage
  expect_equal(pt_match("Gandarela", level = "freguesia", context = "Guimarães",
                        admin_vintage = "auto", quiet = TRUE),
               "030897", ignore_attr = TRUE)
})

test_that("a code is read in the vintage it was asked for", {
  # Codes are vintage-local: none of the 302 freguesias restored in 2025 reused
  # its pre-2013 code, so a code must not be accepted against the wrong vintage.
  m <- pt_match("030364", level = "freguesia", quiet = TRUE)
  expect_equal(pt_match_report(m)$method, "code")
  expect_equal(pt_match_report(m)$code, "030364")

  # 030882 is a 2013 code, not a current one
  expect_true(is.na(pt_match("030882", level = "freguesia", quiet = TRUE)))
  expect_equal(pt_match("030882", level = "freguesia",
                        admin_vintage = "2013", quiet = TRUE),
               "030882", ignore_attr = TRUE)
})

test_that("every pre-2013 name resolves to its own unit at its own vintage", {
  skip_on_cran()
  skip_registry_sweep()
  reg <- as.data.frame(get_dataset("pt_registry"))
  old <- reg[reg$admin_vintage == "2011", ]
  got <- pt_match(old$freguesia, level = "freguesia", context = old$municipio,
                  admin_vintage = "2011", quiet = TRUE)
  expect_equal(sum(is.na(got)), 0L)
  expect_equal(sum(got != old$dtmnfr), 0L)
})

test_that("the ambiguity warning spells the candidates' parents officially", {
  # the pool holds them normalized ("ilha de sao miguel")
  expect_warning(pt_match("Lagoa"), "(2 candidates: Faro, Ilha de São Miguel)",
                 fixed = TRUE)
})

test_that("a live name always wins over a historic one", {
  # 161 pre-2013 names collide with a live name meaning a different unit; the
  # live unit is what a current name has to resolve to.
  expect_equal(pt_match("Alhadas", level = "freguesia", quiet = TRUE),
               "060525", ignore_attr = TRUE)
  expect_equal(pt_match("Buarcos", level = "freguesia", quiet = TRUE),
               "060527", ignore_attr = TRUE)
})

test_that("historic = FALSE restricts matching to names in use today", {
  expect_true(is.na(pt_match("Maximinos", level = "freguesia", context = "Braga",
                             quiet = TRUE, historic = FALSE)))
  expect_equal(pt_match("Gualtar", level = "freguesia", context = "Braga",
                        quiet = TRUE, historic = FALSE),
               "030319", ignore_attr = TRUE)
})

test_that("earlier names of the 2013 freguesias are names of that map", {
  # Each 2013 freguesia is named as it was last. The names it had before were
  # that map's names too, so they match there without historic matching.
  m13 <- function(x, ctx) {
    pt_match(x, level = "freguesia", context = ctx, admin_vintage = "2013",
             historic = FALSE, quiet = TRUE)
  }
  expect_equal(m13("Buarcos", "Figueira da Foz"), "060520", ignore_attr = TRUE)
  expect_equal(m13("Livração", "Marco de Canaveses"), "130735",
               ignore_attr = TRUE)
  expect_equal(
    m13("União das freguesias de Lagos (São Sebastião e Santa Maria)", "Lagos"),
    "080708", ignore_attr = TRUE)
  # and in their simplified form, as INE publishes uniões
  expect_equal(m13("Gouveia (São Pedro e São Julião)", "Gouveia"), "090625",
               ignore_attr = TRUE)

  # Matched from today's map, they are historic names
  expect_true(is.na(pt_match("Livração", level = "freguesia",
                             context = "Marco de Canaveses", historic = FALSE,
                             quiet = TRUE)))
  rep <- pt_match_report(pt_match("Livração", level = "freguesia",
                                  context = "Marco de Canaveses", quiet = TRUE))
  expect_equal(rep$code, "130735")
  expect_equal(rep$method, "historic")
})

test_that("enabling historic names changes nothing for current ones", {
  skip_on_cran()
  skip_registry_sweep()
  frg <- pt_lookup()

  for (ctx in list(frg$municipio, NULL)) {
    on  <- pt_match(frg$freguesia, level = "freguesia", context = ctx,
                    quiet = TRUE, historic = TRUE)
    off <- pt_match(frg$freguesia, level = "freguesia", context = ctx,
                    quiet = TRUE, historic = FALSE)
    expect_equal(as.character(on), as.character(off))
  }
})

test_that("every pre-2013 freguesia resolves from its own name", {
  skip_on_cran()
  skip_registry_sweep()
  r11 <- pt_lookup(admin_vintage = "2011")
  succ <- pt_crosswalk("2011", "2025")
  r11$successor <- succ$to[match(r11$dtmnfr, succ$from)]
  codes <- pt_lookup()

  got <- pt_match(r11$freguesia, level = "freguesia",
                  context = r11$municipio, quiet = TRUE)
  # NA only where the predecessor was later split between several units
  resolved <- !is.na(got)
  expect_gt(mean(resolved), 0.95)

  # A resolved name lands on the crosswalk's successor, unless a unit alive
  # today carries that same name in that same municipality -- then the live one
  # wins, which is the rule.
  live_key <- paste(pt_normalize(codes$freguesia), pt_normalize(codes$municipio))
  key <- paste(pt_normalize(r11$freguesia), pt_normalize(r11$municipio))
  off <- resolved & got != r11$successor
  expect_true(all(key[off] %in% live_key))
  expect_true(all(got[off] == codes$dtmnfr[match(key[off], live_key)]))
})

test_that("every freguesia in the registry resolves from its own name", {
  skip_on_cran()
  skip_registry_sweep()
  frg <- pt_lookup()

  # With its municipio as context, every official name must round-trip.
  got <- pt_match(frg$freguesia, level = "freguesia",
                  context = frg$municipio, quiet = TRUE)
  expect_equal(as.character(got), frg$dtmnfr)

  # Bare, a reused name is allowed to return NA -- but never the wrong unit.
  bare <- pt_match(frg$freguesia, level = "freguesia", quiet = TRUE)
  expect_equal(sum(!is.na(bare) & bare != frg$dtmnfr), 0L)
})
