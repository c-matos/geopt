# Matching Portuguese administrative unit names to official codes.
#
# The matching pipeline is: user aliases -> exact match on normalized names
# -> optional fuzzy match (stringdist). Matching can be scoped to a parent
# unit ("context") because plain names are ambiguous: ~200 freguesia names are
# shared by more than one freguesia, and the municipality "Lagoa" exists in
# both Faro and Sao Miguel. Freguesia + municipio pairs are unique, so a
# context always resolves.

# --- Level registry ------------------------------------------------------------

# For each matchable level: the atom-model scheme it corresponds to, and the
# schemes a context value may refer to, most specific first. Every VINTAGE of
# each context scheme is accepted -- see build_match_pool().
#
# `code` names the column pt_lookup() exposes the level's code as, used to
# resolve `to`.
MATCH_LEVELS <- list(
  freguesia = list(
    scheme  = "freguesia",
    code    = "dtmnfr",
    name    = "freguesia",
    context = c("municipio", "distrito", "nuts3", "nuts2", "nuts1")
  ),
  municipio = list(
    scheme  = "municipio",
    code    = "dtmn",
    name    = "municipio",
    context = c("distrito", "nuts3", "nuts2", "nuts1")
  ),
  distrito = list(
    scheme  = "distrito",
    code    = "dt",
    name    = "distrito_ilha",
    context = "nuts1"
  ),
  nuts1 = list(scheme = "nuts1", code = "nuts1_cod", name = "nuts1",
               context = character(0)),
  nuts2 = list(scheme = "nuts2", code = "nuts2_cod", name = "nuts2",
               context = "nuts1"),
  nuts3 = list(scheme = "nuts3", code = "nuts3_cod", name = "nuts3",
               context = c("nuts2", "nuts1")),
  # Health levels. ULS exist only from 2024 and ACES only before it, so each
  # resolves to a single vintage whatever `health_vintage` says.
  #
  # `lookup_code` is the column pt_lookup() exposes the code as, where that
  # differs from `code`. pt_health_codes is long over both vintages, so its local
  # unit column has to be generic (`unit`), while `code` stays the name the
  # boundary datasets and plot_pt() key on.
  uls   = list(scheme = "uls", code = "uls", name = "uls", lookup_code = "unit",
               context = c("reg_saude", "nuts2", "nuts1")),
  reg_saude = list(scheme = "reg_saude", code = "reg_saude", name = "reg_saude",
                   context = character(0)),
  aces  = list(scheme = "aces", code = "aces", name = "aces", lookup_code = "unit",
               context = c("reg_saude", "nuts2", "nuts1")),
  # The units that share a municipio merged into one, for data by municipio.
  # Names only: a merged unit is named after its members ("ULS Santo Antonio +
  # Sao Joao"); an unmerged one keeps its own name.
  uls_municipio  = list(scheme = "uls_municipio", code = "uls_municipio",
                        name = "uls_municipio", lookup_code = "unit_municipio",
                        context = c("reg_saude", "nuts2", "nuts1")),
  aces_municipio = list(scheme = "aces_municipio", code = "aces_municipio",
                        name = "aces_municipio", lookup_code = "unit_municipio",
                        context = c("reg_saude", "nuts2", "nuts1"))
)

# Shorthand context values for the autonomous regions, mapped to the nuts1
# name they stand for (normalized forms). Covers the abbreviation styles seen
# in the wild: "(R.A.A.)" (INE/PORDATA) and "[R.A. Acores]" both normalize
# into this table.
REGION_CONTEXT_SYNONYMS <- c(
  "raa"    = "regiao autonoma dos acores",
  "r a a"  = "regiao autonoma dos acores",
  "r a acores" = "regiao autonoma dos acores",
  "acores" = "regiao autonoma dos acores",
  "ram"     = "regiao autonoma da madeira",
  "r a m"   = "regiao autonoma da madeira",
  "r a madeira" = "regiao autonoma da madeira",
  "madeira" = "regiao autonoma da madeira"
)

# Curated alternative names, per level: code -> an extra spelling accepted for
# that unit. These are the cases normalization cannot bridge -- a unit renamed,
# or one that the registry disambiguates by appending a qualifier so its plain
# name no longer appears at all. A freguesia's earlier official names are not
# listed here: they are data, names of the vintage they belong to (the 2013
# map's are in data-raw/freguesia_names_2013.csv).
#
# An optional `vintage` column says which vintage `code` is expressed in; the
# default is the current one. It is needed for names of units that did not
# survive to today: "Pacos" as a spelling of Cabeceiras de Basto's 030412 has to
# be stated at 2011, because that unit merged and its current code covers other
# territory too. build_match_pool() maps the code from `vintage` to whichever
# vintage is being matched.
#
# Adding a variant can make a bare name AMBIGUOUS. That is the point: an
# ambiguous name returns NA with a warning naming the candidates, which is far
# safer than silently resolving to the wrong twin. The Azorean Calheta is
# stored as "Calheta de Sao Jorge", so without its variant a bare "Calheta"
# would match Madeira's with no collision to detect, and INE's own "Calheta
# (R.A.A.)" would not match at all.
#
# Exactly two entries collide with a live unit of the same name, both
# deliberately, and both resolve as soon as a `context` is passed:
#   "Calheta" -> Acores 4501 vs Madeira 3101
#   "Passos"  -> the 2013-era name of Pacos, Fafe (030719), vs the freguesia
#                actually called Passos today (040724, Mirandela)
# Everything else here is collision-free.
#
# To add one: append a row. The unit must exist at that level in pt_registry.
NAME_VARIANTS <- list(
  municipio = data.frame(
    code = c("4501", "4302"),
    name = c(
      "Calheta",                  # Acores; pt_registry: "Calheta de Sao Jorge"
      "Vila da Praia da Vit\u00f3ria"  # other official form of "Praia da Vitoria"
    ),
    stringsAsFactors = FALSE
  ),
  distrito = data.frame(
    code = c("44", "32"),
    name = c(
      "Ilha Graciosa",            # pt_registry: "Ilha da Graciosa"
      "Porto Santo"               # pt_registry: "Ilha de Porto Santo"
    ),
    stringsAsFactors = FALSE
  ),
  # Paços/Passos: INE publishes BOTH spellings for the SAME unit across different
  # dimensions -- 030412, 030719, 040724 and 171007 each appear under both -- so
  # whichever spelling the registry carries, the other one has to be accepted.
  # This deliberately makes both bare forms ambiguous; a context resolves them,
  # and INE's own data always carries a parent. (030719 was also officially
  # "Passos" until Lei 22/2020; the 2013 vintage keeps that as a former name.)
  freguesia = data.frame(
    code = c("030719", "130742",
             "040724", "171007", "030412"),
    name = c(
      "Passos",                        # Fafe; registry: "Pa\u00e7os"
      "Pa\u00e7os de Gaiola",               # registry: "Pa\u00e7os de Gaiolo"
      "Pa\u00e7os",                         # Mirandela; registry: "Passos"
      "Passos",                        # Sabrosa; registry: "Pa\u00e7os"
      "Pa\u00e7os"                          # Cabeceiras de Basto; 2011: "Passos"
    ),
    vintage = c(NA, NA, NA, NA, "2011"),
    stringsAsFactors = FALSE
  ),
  # Renames and short forms the particle-insensitive pass cannot bridge.
  uls = data.frame(
    code = c("ULS Vila Nova de Gaia/Espinho", "ULS D\u00e3o-Laf\u00f5es",
             "ULS Alto Alentejo"),
    name = c(
      "ULS de Gaia/Espinho",       # official 2024 short form
      "ULS de Viseu D\u00e3o-Laf\u00f5es",   # official 2024 form
      "ULS do Norte Alentejano"    # the pre-2024 name of this ULS
    ),
    stringsAsFactors = FALSE
  ),
  reg_saude = data.frame(
    code = "LVT",
    name = "Lisboa e Vale do Tejo",  # pt_registry carries the acronym
    stringsAsFactors = FALSE
  )
)

# --- pt_normalize ---------------------------------------------------------------

# Accented letters (both cases) and the ordinal and superscript signs, each
# paired with the plain character it reads as, for chartr(). iconv()'s
# "ASCII//TRANSLIT" is not used: its output differs by platform (macOS turns
# an accented "a" into "'a", some Linux locales into "?").
ACCENTED_CHARS <- paste0(
  "\u00e0\u00e1\u00e2\u00e3\u00e4\u00e7\u00e8\u00e9\u00ea\u00eb",
  "\u00ec\u00ed\u00ee\u00ef\u00f1\u00f2\u00f3\u00f4\u00f5\u00f6",
  "\u00f9\u00fa\u00fb\u00fc\u00fd\u00ff",
  "\u00c0\u00c1\u00c2\u00c3\u00c4\u00c7\u00c8\u00c9\u00ca\u00cb",
  "\u00cc\u00cd\u00ce\u00cf\u00d1\u00d2\u00d3\u00d4\u00d5\u00d6",
  "\u00d9\u00da\u00db\u00dc\u00dd",
  "\u00aa\u00ba\u00b9\u00b2\u00b3"
)
PLAIN_CHARS <- paste0(
  "aaaaaceeee",
  "iiiinooooo",
  "uuuuyy",
  "aaaaaceeee",
  "iiiinooooo",
  "uuuuy",
  "ao123"
)

#' Normalize Portuguese place names for matching
#'
#' Lowercases, expands common abbreviations (`S.` -> `Sao`, `Sta.` -> `Santa`,
#' `Sto.` -> `Santo`), strips accents, and collapses punctuation and
#' whitespace, so that variant spellings of the same unit produce identical
#' keys: `"S. Jorge"`, `"são jorge"`, and `"Sao-Jorge"` all normalize to
#' `"sao jorge"`.
#'
#' This is the normalization used internally by [pt_match()]; it is exported
#' so the same rules can be applied to arbitrary user columns.
#'
#' @param x Character vector of names.
#'
#' @return Character vector of normalized names.
#'
#' @examples
#' pt_normalize(c("S. Jorge", "SÃO JORGE", "Sao-Jorge"))
#'
#' @export
pt_normalize <- function(x) {
  out <- tolower(trimws(as.character(x)))

  # Expand abbreviations before accent stripping (order matters: sta./sto.
  # before the bare s.)
  out <- gsub("\\bsta\\.\\s*", "santa ", out)
  out <- gsub("\\bsto\\.\\s*", "santo ", out)
  out <- gsub("\\bs\\.\\s*", "s\u00e3o ", out)

  # Strip accents
  out <- chartr(ACCENTED_CHARS, PLAIN_CHARS, enc2utf8(out))

  # Punctuation and runs of whitespace become single spaces
  out <- gsub("[^a-z0-9]+", " ", out)
  trimws(out)
}

# Portuguese particles/articles, dropped by the loose matching key below.
NORMALIZE_PARTICLES <- c("de", "do", "da", "dos", "das", "e",
                         "a", "o", "as", "os")

#' Particle-insensitive matching key
#'
#' [pt_normalize()] with standalone articles and conjunctions removed, so that
#' "ULS da Guarda" and "ULS Guarda", or "ULS Tras-os-Montes Alto Douro" and
#' "ULS Tras-os-Montes e Alto Douro", collapse to the same key. Official unit
#' designations carry these particles and shorter working forms drop them,
#' which no amount of accent stripping bridges.
#'
#' Used only as a FALLBACK, after exact matching on the full normalized name
#' has failed: dropping particles is lossy in principle, so exact spellings
#' always win. Verified to introduce no new collisions at any level of
#' pt_registry.
#' @noRd
pt_normalize_loose <- function(x) {
  n <- pt_normalize(x)
  vapply(strsplit(n, " ", fixed = TRUE), function(w) {
    w <- w[w != "" & !(w %in% NORMALIZE_PARTICLES)]
    paste(w, collapse = " ")
  }, character(1L), USE.NAMES = FALSE)
}

# --- pt_pad_code ------------------------------------------------------------------

#' Restore leading zeros in administrative codes
#'
#' Spreadsheet round-trips commonly convert codes like `"0115"` to the number
#' `115`. This pads digit codes back to their official width: 6 for DTMNFR
#' (freguesia), 4 for DTMN (municipio), 2 for DT (distrito/ilha).
#'
#' @param x Vector of codes (character or numeric).
#' @param level One of `"freguesia"`/`"dtmnfr"`, `"municipio"`/`"dtmn"`,
#'   `"distrito"`/`"dt"`.
#'
#' @return Character vector of zero-padded codes. Non-digit entries are
#'   returned unchanged.
#'
#' @examples
#' pt_pad_code(c(115, 1106), "municipio")
#'
#' @export
pt_pad_code <- function(x, level = "municipio") {
  widths <- c(
    freguesia = 6L, dtmnfr = 6L,
    municipio = 4L, dtmn = 4L,
    distrito = 2L, dt = 2L
  )
  level <- tolower(level)
  if (!level %in% names(widths)) {
    stop(
      sprintf("Invalid level '%s'. Must be one of: %s",
              level, paste(unique(names(widths)), collapse = ", ")),
      call. = FALSE
    )
  }

  out <- trimws(as.character(x))
  is_digits <- grepl("^[0-9]+$", out) & !is.na(out)
  # formatC() pads character input with spaces even with flag = "0"
  pad <- pmax(0L, widths[[level]] - nchar(out[is_digits]))
  out[is_digits] <- paste0(strrep("0", pad), out[is_digits])
  out
}

# --- pt_match ----------------------------------------------------------------------

#' Match place names to official codes
#'
#' Resolves a character vector of Portuguese administrative unit names to
#' their official codes using the [pt_registry] table. Matching is exact on
#' normalized names (see [pt_normalize()]), optionally preceded by a
#' user-supplied alias lookup and followed by an opt-in fuzzy pass.
#'
#' @section Ambiguity and context:
#' Many names are not unique (~200 freguesia names are reused; the municipality
#' "Lagoa" exists in Faro and in Sao Miguel). Ambiguous names return `NA` with
#' a warning listing the candidates. To resolve them, either:
#'
#' * pass `context`: a parent unit name per element (municipio for
#'   freguesias; distrito/ilha, NUTS region, or `"Acores"`/`"Madeira"` for
#'   municipios), or
#' * embed a qualifier in the name itself: `"Lagoa (Acores)"`,
#'   `"Lagoa (Faro)"`, INE-style `"Calheta (R.A.M.)"`, `"Lagoa [R.A. Acores]"`
#'   and dash-separated forms like `"Calheta - RAA"` or `"Calheta-R.A.A"` are
#'   all parsed automatically. A dash is only read as a separator when what
#'   follows it is a recognized region — ordinary names containing dashes
#'   (`"Albergaria-a-Velha"`) are never split.
#'
#' A qualifier is only read as one when it is not already part of an official
#' name. Many freguesias end in a parenthetical of their own —
#' `"Bouro (Santa Maria)"`, `"Uniao das freguesias de Braga (Maximinos, Se e
#' Cividade)"` — and those are matched whole, before any split is attempted.
#'
#' @section Spelling tolerance:
#' Matching ignores case, accents, and punctuation, and expands `S.`/`Sta.`/
#' `Sto.`. If that still does not match, a second pass ignores Portuguese
#' particles, so official designations and their working short forms both
#' resolve: `"ULS da Guarda"` → `"ULS Guarda"`,
#' `"ULS Trás-os-Montes Alto Douro"` → `"ULS Trás-os-Montes e Alto Douro"`.
#' Exact spellings always win; the report's `method` column shows `"loose"`
#' when this pass was needed.
#'
#' A few units accept a second official spelling, so that data labelled either
#' way resolves: `"Vila da Praia da Vitoria"` for Praia da Vitória, and
#' `"Calheta"` for the Azorean Calheta (which `pt_registry` stores as
#' `"Calheta de Sao Jorge"`). Because Madeira also has a Calheta, a bare
#' `"Calheta"` is therefore *ambiguous* and returns `NA` with a warning —
#' qualify it as `"Calheta (R.A.A.)"` or `"Calheta (Madeira)"`.
#'
#' @section Historic names:
#' Administrative reforms rename and dissolve units, so names in older census and
#' administrative files often have no current counterpart. With
#' `historic = TRUE` (the default) names from *every* vintage of the level are
#' matched, returning the code of the unit covering that territory in the
#' requested vintage; the report's `method` column shows `"historic"`. A name
#' found in the 2001 map is only used when no later vintage has it: most 2001
#' names were still in use in 2011, and for the few freguesias that lost
#' territory in between, the 2011 sense is the one that matches a single unit
#' today. This is
#' one mechanism, not a freguesia special case — it is also what makes
#' `"Minho-Lima"` resolve at `level = "nuts3"`, where the current name is
#' `"Alto Minho"`.
#'
#' Live names win outright. A name still in use resolves to the unit bearing it
#' now, whatever it also meant in the past. Where a predecessor was later split
#' between several current units the name is genuinely ambiguous and returns
#' `NA` — pass a `context` or use codes. Historic names are matched exactly and
#' particle-loosely, never fuzzily.
#'
#' A freguesia renamed while its map was in force keeps its earlier names as
#' names of that vintage, not as historic ones. The 2013 freguesias are named as
#' they were last, in CAOP 2024 and in INE's tables, and 25 of them were renamed
#' by law before that. `"Buarcos"`, the name of `060520` until 2015, therefore
#' matches it with `admin_vintage = "2013"` even when `historic = FALSE`.
#'
#' @section Vintages:
#' The three axes are independent and each has its own argument. `admin_vintage`
#' chooses which units exist *and which vintage's codes come back*;
#' `nuts_vintage` and `health_vintage` choose the nomenclature that NUTS and
#' health columns are expressed in. See [pt_lookup()].
#'
#' `admin_vintage` defaults to the current set, which is what you want for
#' joining old data onto today's map. To keep the data on its own vintage
#' instead — to map it against boundaries of the era — name that vintage:
#'
#' ```r
#' pt_match(c("Sé", "Maximinos"), level = "freguesia", context = "Braga")
#' #> [1] "030364" "030364"   # the union covering both today
#'
#' pt_match(c("Sé", "Maximinos"), level = "freguesia", context = "Braga",
#'          admin_vintage = "2011")
#' #> [1] "030352" "030324"   # the units they were
#' ```
#'
#' **Codes are vintage-local.** None of the 302 freguesias restored in 2025
#' reused its pre-2013 code, even if it has the same name and same boundaries,
#' so a code is only accepted against the vintage it belongs to.
#' `pt_match("030882", level = "freguesia")` is `NA`, because that is
#' a 2013 code; with `admin_vintage = "2013"` it resolves.
#'
#' `admin_vintage = "auto"` infers the vintage from the input and says which it
#' chose. This is the setting for INE data, which is published on the 2013
#' freguesia set even under the 2024 NUTS revision — so 134 units that were
#' disaggregated in 2025 are ambiguous against the current registry and exact
#' against their own.
#'
#' INE prefixes a city's pre-2013 parishes with the city (`"Braga (Sé)"`) but
#' names the same kind of unit plainly elsewhere (`"Sé"` in Lisboa). All the
#' spellings resolve — `"Braga (Sé)"`, `"Sé (Braga)"`, and `"Sé"` with
#' `context = "Braga"` — because a bare name plus a context is recombined into
#' the parenthesised forms and retried, once the name as given has failed. A
#' trailing parenthetical never *displaces* a `context` you passed: where it is
#' part of the official name rather than a qualifier, the context still applies.
#'
#' @section Fuzzy matching:
#' With `fuzzy = TRUE` (requires the `stringdist` package), elements that
#' fail exact matching are compared against candidate names by optimal string
#' alignment distance. A fuzzy match is accepted only when the best candidate
#' is within `max_dist` and strictly better than the second-best candidate;
#' every accepted fuzzy match is reported via message. Fuzzy matching is
#' most reliable with a `context`, which shrinks the candidate pool.
#'
#' @param x Character vector of names to match. Codes are automatically padded
#'   to the correct length, if needed.
#' @param level Which units `x` refers to: `"freguesia"`, `"municipio"`
#'   (default), `"distrito"`, `"nuts1"`, `"nuts2"`, `"nuts3"`, `"uls"`,
#'   `"reg_saude"`, `"aces"`, `"uls_municipio"`, `"aces_municipio"`.
#'   `"uls"`/`"reg_saude"` are the 2024 health reform; `"aces"` is the
#'   organization it superseded. The `*_municipio` levels merge the units that
#'   share a municipality, and are matched by the merged name
#'   (`"ULS Santo António + São João"`).
#' @param to Column of [pt_lookup()] to return, at the vintages requested below.
#'   Defaults to the level's own code column (`dtmnfr`, `dtmn`, `dt`,
#'   `nuts*_cod`, ...). A column defined only at a finer level — `"dtmnfr"` for
#'   a municipio — yields `NA`.
#' @param context Optional character vector (length 1 or `length(x)`) naming
#'   a parent unit to scope the match. Any vintage of any parent scheme is
#'   accepted, so INE's own parent column works whichever nomenclature that
#'   indicator was published under.
#' @param admin_vintage Which administrative vintage to match against and return
#'   codes for: `"2025"`, `"2013"`, `"2011"`, `"2001"`, or `"auto"` to infer it
#'   from `x`. Leave it out for the newest (`"2025"`). See *Vintages*.
#' @param nuts_vintage Which NUTS revision `to` is expressed in: `"2024"`,
#'   `"2013"` or `"2002"`. Also the vintage matched at
#'   `level = "nuts1"`/`"nuts2"`/`"nuts3"`. Leave it out for the newest
#'   (`"2024"`).
#' @param health_vintage Which health geography `to` is expressed in: `"2024"`
#'   or `"2022"`. Leave it out for the newest (`"2024"`). Ignored at
#'   `level = "uls"` and `"aces"` (and their `*_municipio` forms), which each
#'   exist in one health geography only; a value that isn't a health vintage
#'   at all is still an error.
#' @param fuzzy Logical. Enable the fuzzy fallback pass? Default `FALSE`.
#' @param max_dist Maximum string distance for a fuzzy match. Default `2`.
#' @param aliases Optional named character vector mapping variant spellings
#'   to either canonical names or codes, e.g.
#'   `c("VN Gaia" = "Vila Nova de Gaia")`. Checked before exact matching;
#'   names are compared in normalized form.
#' @param historic Logical. Also match names from the level's other vintages?
#'   Default `TRUE`. Set `FALSE` to accept only names in use at
#'   `admin_vintage` — useful when validating that a file really is that vintage.
#' @param quiet Logical. Suppress warnings/messages about ambiguous,
#'   unmatched, and fuzzy-matched entries? Default `FALSE`.
#'
#' @return Character vector of codes (same length as `x`), with a `"report"`
#'   attribute retrievable via [pt_match_report()].
#'
#' @examples
#' pt_match(c("Porto", "lisboa", "S. Joao da Madeira"))
#' pt_match(c("Lagoa (Faro)", "Lagoa (Acores)"))
#' pt_match("Pinheiro", level = "freguesia", context = "Guimarães")
#'
#' @seealso [pt_match_report()], [pt_normalize()], [pt_registry]
#'
#' @export
pt_match <- function(x,
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
                     quiet = FALSE) {
  level <- tolower(level)
  if (!level %in% names(MATCH_LEVELS)) {
    stop(
      sprintf("Invalid level '%s'. Must be one of: %s",
              level, paste(names(MATCH_LEVELS), collapse = ", ")),
      call. = FALSE
    )
  }
  spec <- MATCH_LEVELS[[level]]
  to <- to %||% spec$code

  if (!is.null(aliases)) {
    if (is.null(names(aliases)) || any(names(aliases) == "")) {
      stop("`aliases` must be a named character vector.", call. = FALSE)
    }
    names(aliases) <- pt_normalize(names(aliases))
  }

  if (!is.null(context)) {
    if (!length(context) %in% c(1L, length(x))) {
      stop("`context` must have length 1 or length(x).", call. = FALSE)
    }
    context <- rep_len(as.character(context), length(x))
  }

  x_chr <- as.character(x)

  # Checked here, whatever the level: a vintage that doesn't apply to this level
  # is ignored further down (see level_vintage()), but one that doesn't exist at
  # all is a mistake, and ignoring it would hide it.
  admin_vintage  <- check_vintage(admin_vintage, "admin", extra = "auto")
  nuts_vintage   <- check_vintage(nuts_vintage, "nuts")
  health_vintage <- check_vintage(health_vintage, "health")

  # `admin_vintage` selects which vintage's CODES come back, so the default is
  # the current one, where historic names resolve to the unit covering them
  # today; detecting it would make the codes returned depend on the input.
  # "auto" is opt-in, for data whose own vintage is what you want back -- the
  # ineptr2 case, where INE publishes the 2013 set.
  if (identical(admin_vintage, "auto")) {
    admin_vintage <- detect_admin_vintage(x_chr, level, quiet = quiet)
  }

  lookup <- build_match_pool(level, admin_vintage = admin_vintage,
                             nuts_vintage = nuts_vintage,
                             health_vintage = health_vintage,
                             historic = historic)
  vintage <- attr(lookup, "vintage")
  pool_codes <- unique(lookup$code)

  # `to` names a column of the assembled lookup for these vintages, so it can
  # reach any level: dtmn and nuts3 from a freguesia, reg_saude from a municipio.
  target <- lookup_target(level, to, admin_vintage = admin_vintage,
                          nuts_vintage = nuts_vintage,
                          health_vintage = health_vintage)
  resolve_to <- function(code) {
    if (identical(to, spec$code)) code else unname(target[code])
  }

  result <- rep(NA_character_, length(x))
  bad_context <- rep(NA_character_, length(x))
  report <- data.frame(
    input = x_chr,
    matched_name = NA_character_,
    code = NA_character_,
    method = "unmatched",
    dist = NA_real_,
    stringsAsFactors = FALSE
  )

  # Identified, whether or not the requested `to` has a value for it: a code
  # that resolved is not retried as a name just because its target column is
  # undefined for that unit.
  done <- rep(FALSE, length(x))

  # Pass codes straight through (padded) for levels with digit codes. Validated
  # against the REQUESTED vintage: a code is only meaningful within its own
  # vintage, and none of the 302 freguesias restored in 2025 reused its pre-2013
  # code, so accepting a code from another vintage here would silently return
  # the wrong unit.
  digit_like <- grepl("^[0-9]+$", trimws(x_chr)) & !is.na(x_chr)
  if (any(digit_like) && level %in% c("freguesia", "municipio", "distrito")) {
    padded <- pt_pad_code(x_chr[digit_like], level)
    if (identical(level, "freguesia")) padded <- resolve_code_aliases(padded, vintage)
    valid <- padded %in% pool_codes
    idx <- which(digit_like)[valid]
    result[idx] <- vapply(padded[valid], resolve_to, character(1L))
    report$method[idx] <- "code"
    report$code[idx] <- padded[valid]
    done[idx] <- TRUE
  }

  # Pass through values that already are codes (e.g. "PT191" at nuts3 level)
  up <- toupper(trimws(x_chr))
  direct <- which(!done & !is.na(x_chr) & up %in% pool_codes)
  if (length(direct) > 0L) {
    result[direct] <- vapply(up[direct], resolve_to, character(1L))
    report$method[direct] <- "code"
    report$code[direct] <- up[direct]
    done[direct] <- TRUE
  }

  todo <- which(!done & !is.na(x_chr) & trimws(x_chr) != "")

  for (i in todo) {
    parsed <- parse_qualifier(x_chr[i])
    ctx <- context[i] %||% NULL
    ctx <- if (!is.null(ctx) && !is.na(ctx) && trimws(ctx) != "") ctx else NULL

    # An official name may itself end in a parenthetical -- "Bouro (Santa
    # Maria)", "Uniao das freguesias de Beja (Salvador e Santa Maria da
    # Feira)" -- so a trailing parenthetical is only a qualifier when it is
    # not part of a real name. Try the name as given first, exact-only: a
    # registry spelling always beats a speculative split, and restricting this
    # pass to exact hits keeps it from inventing matches of its own. The
    # loose/dash/fuzzy fallbacks stay on the parsed path below. This mirrors
    # split_dash_qualifier(), where a split likewise has to earn its way.
    m <- NULL
    if (!is.null(parsed$qualifier)) {
      literal <- match_one(
        trimws(x_chr[i]), ctx, lookup, spec,
        aliases = aliases, exact_only = TRUE
      )
      if (!is.na(literal$code)) m <- literal
    }

    # A trailing parenthetical is preferred as the scope, but it must not
    # DISPLACE a context the caller supplied. INE writes a city's parishes as
    # "Evora (Se)", which parses backwards -- name "Evora", qualifier "Se" -- so
    # taking only the qualifier as the scope would turn an explicit
    # context = "Evora" into a hard failure. Try the qualifier first, and fall
    # back to the caller's context whenever the qualifier did not resolve; then,
    # still holding the caller's context, try the parenthetical as the NAME,
    # which is the form INE actually publishes.
    if (is.null(m)) {
      m <- match_one(
        parsed$name, parsed$qualifier %||% ctx, lookup, spec,
        fuzzy = fuzzy, max_dist = max_dist, aliases = aliases
      )
      if (is.na(m$code) && !is.null(parsed$qualifier) && !is.null(ctx)) {
        retry <- match_one(
          parsed$name, ctx, lookup, spec,
          fuzzy = fuzzy, max_dist = max_dist, aliases = aliases
        )
        if (is.na(retry$code)) {
          retry <- match_one(
            parsed$qualifier, ctx, lookup, spec,
            fuzzy = fuzzy, max_dist = max_dist, aliases = aliases
          )
        }
        if (!is.na(retry$code) || identical(m$method, "context_unrecognized")) {
          m <- retry
        }
      }
    }

    if (!is.na(m$code)) result[i] <- resolve_to(m$code)
    if (identical(m$method, "context_unrecognized")) bad_context[i] <- m$context
    report$matched_name[i] <- m$matched_name
    report$code[i] <- m$code
    report$method[i] <- m$method
    report$dist[i] <- m$dist
  }

  # Blank/NA inputs
  blank <- is.na(x_chr) | trimws(x_chr) == ""
  report$method[blank] <- "empty"

  attr(result, "report") <- report
  if (!quiet) summarize_match_report(report, lookup, spec, bad_context)
  result
}

#' Retrieve the match report from a pt_match result
#'
#' @param x The return value of [pt_match()].
#'
#' @return A data.frame with one row per input: `input`, `matched_name`,
#'   `code`, `method` (`"exact"`, `"loose"` — matched once Portuguese
#'   particles were ignored, `"alias"`, `"historic"` — matched a name from a
#'   vintage other than the one requested, such as a pre-2013 name,
#'   `"fuzzy"`, `"code"`, `"ambiguous"`, `"context_unrecognized"` — the
#'   `context` is not a unit geopt knows, `"unmatched"`, `"empty"`), and `dist`
#'   (fuzzy matches only).
#'
#' @examplesIf identical(Sys.getenv("NOT_CRAN"), "true")
#' m <- pt_match(c("Porto", "Lagoa"))
#' pt_match_report(m)
#'
#' @export
pt_match_report <- function(x) {
  rep <- attr(x, "report")
  if (is.null(rep)) {
    stop("`x` has no match report. Was it returned by pt_match()?", call. = FALSE)
  }
  rep
}

# --- Internal helpers ----------------------------------------------------------

#' Parse a trailing parenthetical/bracketed qualifier out of a name
#' @noRd
parse_qualifier <- function(x) {
  m <- regmatches(
    x,
    regexec("^(.*?)\\s*[(\\[]([^)\\]]+)[)\\]]\\s*$", x, perl = TRUE)
  )[[1]]
  if (length(m) == 3L && trimws(m[2]) != "") {
    list(name = trimws(m[2]), qualifier = trimws(m[3]))
  } else {
    list(name = trimws(x), qualifier = NULL)
  }
}

#' Candidate (name, qualifier) splits of a dash-separated string
#'
#' `"Calheta - RAA"` and `"Calheta-R.A.A"` both mean Calheta scoped to the
#' Açores, but a dash is also an ordinary part of many official names
#' ("Albergaria-a-Velha", "ULS Almada-Seixal", "Algueirão-Mem Martins"), so a
#' split can never be assumed. This returns every plausible split, rightmost
#' dash first, for the caller to validate: only a split whose qualifier is a
#' recognized context is ever accepted.
#'
#' Splits on a dash that is surrounded by whitespace are tried first, since
#' `" - "` is the deliberate separator; a bare dash is tried after.
#' @noRd
split_dash_qualifier <- function(x) {
  x <- as.character(x)
  spaced <- gregexpr("\\s+[-\u2013\u2014]\\s+", x, perl = TRUE)[[1]]
  bare   <- gregexpr("[-\u2013\u2014]", x, perl = TRUE)[[1]]

  mk <- function(pos, len) {
    if (pos[1L] == -1L) return(list())
    lapply(rev(seq_along(pos)), function(i) {
      head <- trimws(substr(x, 1L, pos[i] - 1L))
      tail <- trimws(substring(x, pos[i] + len[i]))
      if (!nzchar(head) || !nzchar(tail)) return(NULL)
      list(name = head, qualifier = tail)
    })
  }
  out <- c(mk(spaced, attr(spaced, "match.length")),
           mk(bare, attr(bare, "match.length")))
  out <- out[!vapply(out, is.null, logical(1L))]
  # Drop duplicate splits (a spaced dash also shows up in the bare scan)
  key <- vapply(out, function(p) paste(p$name, p$qualifier, sep = "\r"), character(1L))
  out[!duplicated(key)]
}

#' The normalized forms a context value is recognized under, most specific first
#'
#' Three readings, tried in order rather than unioned -- for the same reason
#' exact spellings beat loose ones when matching a name. A single pool would make
#' `context = "Calheta"` match Madeira's Calheta *and* the Azorean one that
#' NAME_VARIANTS deliberately gives that spelling, turning an unambiguous scope
#' into an ambiguous one.
#'
#' \describe{
#'   \item{`literal`}{the value as given, plus the region-abbreviation synonyms.}
#'   \item{`variant`}{what the curated NAME_VARIANTS tables say that value names,
#'     spelled as the registry spells it. Ranked above `stripped` because it USED
#'     the qualifier: `"Calheta (R.A.A.)"` reaches `"Calheta de Sao Jorge"` here,
#'     whereas discarding the qualifier would reach Madeira's Calheta.}
#'   \item{`stripped`}{the value with a trailing qualifier removed -- the last
#'     resort, since it throws information away.}
#' }
#' @noRd
context_candidates <- function(ctx) {
  expand <- function(v) {
    n <- pt_normalize(v)
    syn <- REGION_CONTEXT_SYNONYMS[n]
    unique(c(n, if (!is.na(syn)) unname(syn)))
  }
  literal <- expand(ctx)

  parsed <- parse_qualifier(ctx)
  stripped <- if (!is.null(parsed$qualifier)) expand(parsed$name) else character(0)
  # A trailing qualifier naming a region CONSTRAINS which curated spelling is
  # meant. Without this, "Calheta (Madeira)" would reach the Azorean Calheta,
  # because NAME_VARIANTS gives that unit the bare spelling and the qualifier was
  # simply discarded.
  qual_region <- if (!is.null(parsed$qualifier)) expand(parsed$qualifier) else NULL

  # A context may name a unit at any level, so consult every variant table.
  variant <- character(0)
  for (lv in names(NAME_VARIANTS)) {
    v <- NAME_VARIANTS[[lv]]
    hit <- pt_normalize(v$name) %in% c(literal, stripped)
    if (!any(hit)) next
    scheme <- MATCH_LEVELS[[lv]]$scheme
    codes <- v$code[hit]
    if (!is.null(qual_region)) {
      codes <- codes[vapply(codes, function(cd) {
        any(unit_region(scheme, cd) %in% qual_region)
      }, logical(1L))]
    }
    if (length(codes) == 0L) next
    for (vint in atom_vintages(scheme)) {
      nm <- atom_unit_name(scheme, vint, codes)
      variant <- c(variant, pt_normalize(nm[!is.na(nm)]))
    }
  }
  clean <- function(x, seen) setdiff(unique(x[!is.na(x) & nzchar(x)]), seen)
  variant  <- clean(variant, literal)
  stripped <- clean(stripped, c(literal, variant))
  list(literal = literal, variant = variant, stripped = stripped)
}

#' Candidate scopes for a context value, best reading first
#'
#' A list, not one frame, because a context can have more than one defensible
#' reading and only the NAME can tell them apart. Bare `"Calheta"` is Madeira's
#' município in the registry, so that is the first reading; it is also the
#' Azorean one via NAME_VARIANTS, which is the second. `match_one()` tries them
#' in order and stops at the first where the name actually resolves, so
#' `"Calheta"` (a freguesia of both) still lands in Madeira while
#' `"Norte Pequeno"` (only Azorean) reaches São Jorge.
#'
#' Within one reading, context columns cover every VINTAGE of every context
#' scheme, and the vintages of one scheme are UNIONED before moving on to the
#' next. That union is the point: INE labels an indicator's parent with the
#' nomenclature of that indicator, so "Minho-Lima" (NUTS 2002) and "Alto Minho"
#' (NUTS 2024) must both scope a municipio. It also means a freguesia that
#' changed municipality is reachable from either parent -- Pombalinho was
#' Santarem's before 2013 and is Golega's now, and taking only the current
#' column would lose the former. Schemes are still tried in order, most
#' specific first, so a value naming both a municipio and a NUTS region
#' resolves as the narrower one.
#'
#' Returns `list()` when the context is recognized under no reading at all.
#' @noRd
scope_lookup <- function(lookup, spec, ctx) {
  cands <- context_candidates(ctx)
  idx <- attr(lookup, "ctx_index")

  out <- list()
  for (pass in cands) {
    if (length(pass) == 0L) next
    for (scheme in names(idx)) {
      rows <- unlist(idx[[scheme]][pass], use.names = FALSE)
      if (length(rows) > 0L) {
        out[[length(out) + 1L]] <- lookup[sort(unique(rows)), , drop = FALSE]
        break   # one scope per pass: the most specific scheme that matched
      }
    }
  }
  out
}

#' Match a single (already qualifier-parsed) name
#'
#' `allow_dash` guards the dash-qualifier fallback against recursing.
#' `exact_only` restricts matching to registry spellings -- no loose, dash or
#' fuzzy fallback -- for the literal-name pass in [pt_match()], which must be
#' able to confirm a name exists without ever guessing at one.
#' @noRd
match_one <- function(name, ctx, lookup, spec,
                      fuzzy = FALSE, max_dist = 2, aliases = NULL,
                      allow_dash = TRUE, exact_only = FALSE) {
  no_match <- list(code = NA_character_, matched_name = NA_character_,
                   method = "unmatched", dist = NA_real_)

  norm <- pt_normalize(name)
  if (is.na(norm) || norm == "") return(no_match)

  method_prefix <- ""

  # Alias substitution: value may be a canonical name (re-normalized and
  # matched) or a code (returned directly if it exists).
  if (!is.null(aliases) && norm %in% names(aliases)) {
    target <- unname(aliases[[norm]])
    if (target %in% lookup$code) {
      row <- lookup[lookup$code == target, , drop = FALSE][1L, ]
      return(list(code = target, matched_name = row$display_name,
                  method = "alias", dist = NA_real_))
    }
    norm <- pt_normalize(target)
    method_prefix <- "alias"
  }

  # An unrecognized context is a hard failure: silently ignoring it could
  # match the wrong twin of an ambiguous name. `context` carries the value for
  # the warning, which may be a trailing parenthetical rather than the caller's.
  scopes <- list(lookup)
  if (!is.null(ctx)) {
    scopes <- scope_lookup(lookup, spec, ctx)
    if (length(scopes) == 0L) {
      return(list(code = NA_character_, matched_name = NA_character_,
                  method = "context_unrecognized", dist = NA_real_,
                  context = ctx))
    }
  }

  # One attempt against one reading of the context. Factored out so the readings
  # can be tried in turn -- see scope_lookup().
  attempt <- function(scoped) {

  # Rows whose `col` is one of `keys`, resolved by vintage: a name still in use
  # beats one that fell out of use, which beats a fallback (see
  # FALLBACK_NAME_VINTAGES). 161 pre-2013 names spell the same as a live
  # freguesia meaning a different unit, so the live one has to win outright: a
  # current name resolves the same with or without historic matching.
  pick <- function(col, keys) {
    h <- scoped[scoped[[col]] %in% keys, , drop = FALSE]
    if (nrow(h) == 0L) return(NULL)
    h[h$tier == min(h$tier), , drop = FALSE]
  }

  hits <- pick("norm_name", norm)
  how <- "exact"

  # INE prefixes a city's pre-2013 parishes with the city -- "Braga (Se)",
  # "Beja (Salvador)" -- but names the same kind of unit plainly elsewhere
  # ("Se" in Lisboa, Porto, Portalegre). A context makes both spellings
  # reachable from the bare name, so build them here rather than storing every
  # combination in the lookup. Only after the name as given has failed, so an
  # official spelling is never displaced by a constructed one.
  if (is.null(hits) && !is.null(ctx) && !isTRUE(exact_only)) {
    hits <- pick("norm_name",
                 c(pt_normalize(paste0(name, " (", ctx, ")")),
                   pt_normalize(paste0(ctx, " (", name, ")"))))
  }

  # Fallback 1: ignore particles ("ULS da Guarda" -> "ULS Guarda"). Exact
  # spellings always win; this only runs when none matched.
  if (is.null(hits) && !isTRUE(exact_only)) {
    loose <- pt_normalize_loose(name)
    if (nzchar(loose)) {
      hits <- pick("loose_name", loose)
      how <- "loose"
    }
  }

  if (!is.null(hits)) {
    if (length(unique(hits$code)) > 1L) {
      return(list(code = NA_character_, matched_name = NA_character_,
                  method = "ambiguous", dist = NA_real_))
    }
    return(list(
      code = hits$code[1L],
      matched_name = hits$display_name[1L],
      method = if (hits$tier[1L] > 0L) "historic" else
               if (method_prefix == "alias") "alias" else how,
      dist = NA_real_
    ))
  }

  if (isTRUE(exact_only)) return(no_match)

  # Fallback 2: a dash-separated qualifier ("Calheta - RAA", "Calheta-R.A.A").
  # Only tried when nothing above matched and no qualifier was given, and only
  # accepted when the tail is a RECOGNIZED context -- many official names
  # contain dashes ("Albergaria-a-Velha", "ULS Almada-Seixal"), so a split is
  # never assumed, it has to earn its way.
  if (isTRUE(allow_dash) && is.null(ctx) && grepl("[-\u2013\u2014]", name)) {
    parts <- split_dash_qualifier(name)
    for (p in parts) {
      if (is.null(scope_lookup(lookup, spec, p$qualifier))) next
      m <- match_one(p$name, p$qualifier, lookup, spec,
                     fuzzy = FALSE, aliases = NULL, allow_dash = FALSE)
      if (!is.na(m$code)) return(m)
    }
  }

  # Fuzzy considers live names only. A historic name already carries an
  # assumption about which vintage the caller meant; letting a typo choose one
  # too would stack two guesses into a match nobody can audit.
  if (isTRUE(fuzzy)) {
    check_suggested_pkg("stringdist", "for fuzzy matching (fuzzy = TRUE)")
    live <- scoped[scoped$tier == 0L, , drop = FALSE]
    cand_names <- unique(live$norm_name)
    if (length(cand_names) > 0L) {
      d <- stringdist::stringdist(norm, cand_names, method = "osa")
      ord <- order(d)
      best <- ord[1L]
      second <- if (length(ord) > 1L) d[ord[2L]] else Inf
      if (d[best] <= max_dist && d[best] < second) {
        hits <- live[live$norm_name == cand_names[best], , drop = FALSE]
        if (length(unique(hits$code)) == 1L) {
          return(list(
            code = hits$code[1L],
            matched_name = hits$display_name[1L],
            method = "fuzzy",
            dist = d[best]
          ))
        }
      }
    }
  }

  no_match
  }   # end attempt()

  # Try each reading of the context, stopping at the first that resolves. An
  # AMBIGUITY inside a reading is itself an answer -- the name is there, twice --
  # so widening past it would invent a match. Only a name that is absent from a
  # reading justifies trying the next one. The first reading's outcome is what
  # gets reported when none resolves, since that is the primary interpretation.
  first <- NULL
  for (scoped in scopes) {
    r <- attempt(scoped)
    if (!is.na(r$code)) return(r)
    if (is.null(first)) first <- r
    if (identical(r$method, "ambiguous")) return(r)
  }
  first %||% no_match
}

summarize_match_report <- function(report, lookup, spec, bad_context = NULL) {
  fuzzy_rows <- report[report$method == "fuzzy", , drop = FALSE]
  if (nrow(fuzzy_rows) > 0L) {
    lines <- sprintf("'%s' -> '%s' (dist %g)",
                     fuzzy_rows$input, fuzzy_rows$matched_name, fuzzy_rows$dist)
    message(sprintf("pt_match: %d fuzzy match(es):\n  %s",
                    nrow(fuzzy_rows), paste(unique(lines), collapse = "\n  ")))
  }

  ambiguous <- unique(report$input[report$method == "ambiguous"])
  if (length(ambiguous) > 0L) {
    examples <- vapply(utils::head(ambiguous, 5L), function(nm) {
      norm <- pt_normalize(parse_qualifier(nm)$name)
      cand <- lookup[lookup$norm_name == norm, , drop = FALSE]
      # Name the candidates by their most specific parent, so the warning says
      # something actionable: which context would separate them. The pool holds
      # parent names normalized; show their official spelling.
      ctx_cols <- pool_ctx_cols(lookup, spec)
      where <- ""
      if (length(ctx_cols) > 0L) {
        vals <- unique(cand[[ctx_cols[1L]]])
        vals <- vals[!is.na(vals)]
        shown <- unname(attr(lookup, "ctx_display")[vals])
        where <- paste(ifelse(is.na(shown), vals, shown), collapse = ", ")
      }
      sprintf("'%s' (%d candidates: %s)", nm,
              length(unique(cand$code)), where)
    }, character(1L))
    warning(sprintf(
      "pt_match: %d ambiguous name(s) returned NA. Pass `context` or use codes.\n  %s",
      length(ambiguous), paste(examples, collapse = "\n  ")
    ), call. = FALSE)
  }

  # Name the context values that failed, not the inputs: a typo or the wrong
  # column is then obvious.
  bad <- report$method == "context_unrecognized"
  if (any(bad)) {
    vals <- bad_context[bad]
    vals[is.na(vals)] <- "?"
    counts <- table(factor(vals, levels = unique(vals)))
    shown <- utils::head(counts, 5L)
    listed <- paste(sprintf("'%s' (%d %s)", names(shown), as.integer(shown),
                            ifelse(shown == 1L, "row", "rows")),
                    collapse = ", ")
    if (length(counts) > 5L) listed <- paste0(listed, ", ...")
    parents <- spec$context
    expected <- if (length(parents) == 0L) {
      " This level takes no context."
    } else if (length(parents) == 1L) {
      sprintf(" A context must name the %s an input belongs to.", parents)
    } else {
      sprintf(" A context must name the %s or %s an input belongs to.",
              paste(parents[-length(parents)], collapse = ", "),
              parents[length(parents)])
    }
    warning(sprintf(
      "pt_match: %d input(s) returned NA because their context was not recognized: %s.%s",
      sum(bad), listed, expected
    ), call. = FALSE)
  }

  unmatched <- unique(report$input[report$method == "unmatched"])
  if (length(unmatched) > 0L) {
    warning(sprintf(
      "pt_match: %d unmatched name(s): %s%s",
      length(unmatched),
      paste(utils::head(unmatched, 5L), collapse = ", "),
      if (length(unmatched) > 5L) ", ..." else ""
    ), call. = FALSE)
  }
}
