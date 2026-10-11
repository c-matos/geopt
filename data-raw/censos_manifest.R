# Build the INE Censos download manifest and the pt_censos_vars dictionary.
#
# INE distributes census geographies (BGRI subsecções, secções, 1 km GRID)
# as static zipped GeoPackages behind JavaScript tree pages at
# https://mapas.ine.pt/download/. This script parses those trees into a
# lookup table (`censos_manifest`, internal) so the package never scrapes at
# runtime, and derives the variable dictionary (`pt_censos_vars`, exported)
# from small sample downloads (Corvo, the smallest municipality) plus INE's
# variable-description CSVs.
#
# Re-run when INE reorganizes the download pages (last verified: 2026-07).
# Requires network access. Run from the package root:
#   source("data-raw/censos_manifest.R")

library(sf)

CENSOS_BASE <- "https://mapas.ine.pt/download"

TREE_PAGES <- c(
  bgri_1991    = "index1991.phtml",
  bgri_2001    = "index2001.phtml",
  bgri_2011    = "index2011.phtml",
  bgri_2021    = "index2021.phtml",
  seccoes_2021 = "index2021Seccoes.phtml",
  grid_2021    = "index2021Grid.phtml"
)

work_dir <- file.path(tempdir(), "geopt_censos_manifest")
dir.create(work_dir, showWarnings = FALSE, recursive = TRUE)

fetch <- function(path, dest = file.path(work_dir, basename(path))) {
  if (!file.exists(dest)) {
    utils::download.file(paste0(CENSOS_BASE, "/", path), dest,
                         mode = "wb", quiet = TRUE)
  }
  dest
}

# INE's server ignores HEAD; check existence with a 1-byte range GET.
url_alive <- function(url) {
  req <- httr2::request(url)
  req <- httr2::req_headers(req, Range = "bytes=0-0")
  req <- httr2::req_timeout(req, 30)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  resp <- httr2::req_perform(req)
  httr2::resp_status(resp) < 400L
}

decode_entities <- function(x) {
  map <- c(
    "&aacute;" = "á", "&agrave;" = "à", "&acirc;" = "â",
    "&atilde;" = "ã", "&eacute;" = "é", "&ecirc;" = "ê",
    "&iacute;" = "í", "&oacute;" = "ó", "&ocirc;" = "ô",
    "&otilde;" = "õ", "&uacute;" = "ú", "&ccedil;" = "ç",
    "&Aacute;" = "Á", "&Eacute;" = "É", "&Iacute;" = "Í",
    "&Oacute;" = "Ó", "&Uacute;" = "Ú", "&Ccedil;" = "Ç",
    "&Acirc;" = "Â", "&Atilde;" = "Ã", "&amp;" = "&"
  )
  for (ent in names(map)) x <- gsub(ent, map[[ent]], x, fixed = TRUE)
  gsub("\\s+", " ", trimws(x))
}

# --- 1. Parse the dtree definitions -----------------------------------------

parse_tree <- function(html_path) {
  html <- readLines(html_path, warn = FALSE, encoding = "UTF-8")
  html <- paste(html, collapse = "\n")

  # d.add(id, parent, 'label', 'url', ...) — labels may contain \' escapes.
  pattern <- "d\\.add\\(\\d+,-?\\d+,'((?:[^'\\\\]|\\\\.)*)','((?:[^'\\\\]|\\\\.)*)'"
  m <- gregexpr(pattern, html, perl = TRUE)
  hits <- regmatches(html, m)[[1]]

  label <- sub(pattern, "\\1", hits, perl = TRUE)
  url <- sub(pattern, "\\2", hits, perl = TRUE)

  keep <- grepl("^filesGPG/", url)
  url <- url[keep]
  # INE's trees omit ".zip" on a few nodes (e.g. Manteigas on every page);
  # the .zip file exists and is canonical, so normalize.
  url <- ifelse(grepl("\\.zip$", url), url, paste0(url, ".zip"))
  data.frame(
    name = decode_entities(gsub("\\\\'", "'", label[keep])),
    url = url,
    stringsAsFactors = FALSE
  )
}

classify <- function(tree, product, year) {
  dir_part <- dirname(tree$url)
  file_part <- basename(tree$url)

  scope_type <- rep(NA_character_, nrow(tree))
  scope_id <- rep(NA_character_, nrow(tree))

  is_mun <- grepl("/municipios$", dir_part)
  scope_type[is_mun] <- "municipio"
  scope_id[is_mun] <- sub(".*?([0-9]{4})\\.zip$", "\\1", file_part[is_mun])

  is_n3 <- grepl("/nuts3$", dir_part)
  scope_type[is_n3] <- "nuts3"
  scope_id[is_n3] <- sub(".*_([0-9A-Z]{3})\\.zip$", "\\1", file_part[is_n3])

  is_n2 <- grepl("/nuts2$", dir_part)
  scope_type[is_n2] <- "nuts2"
  scope_id[is_n2] <- sub(".*_([A-Z]+)\\.zip$", "\\1", file_part[is_n2])

  # Root files: canonical names (BGRI21_CONT, C2021_SECCOES_RAA, ...) plus
  # the alternate deep-branch names some nodes use (raa2021.zip, ram1991.zip).
  is_root <- is.na(scope_type)
  root_id <- toupper(file_part[is_root])
  root_scope <- ifelse(
    grepl("PORTUGAL|_PT\\.ZIP", root_id), "portugal",
    ifelse(grepl("_CONT", root_id), "CONT",
      ifelse(grepl("_RAA|^RAA", root_id), "RAA",
        ifelse(grepl("_MAD|^RAM", root_id), "MAD", NA_character_)
      )
    )
  )
  scope_type[is_root] <- ifelse(root_scope == "portugal", "portugal", "region")
  scope_id[is_root] <- ifelse(root_scope == "portugal", "PT", root_scope)

  out <- data.frame(
    product = product, year = year,
    scope_type = scope_type, scope_id = scope_id,
    name = tree$name, url = tree$url,
    stringsAsFactors = FALSE
  )
  stopifnot(!anyNA(out$scope_type), !anyNA(out$scope_id))
  out
}

manifest <- do.call(rbind, lapply(names(TREE_PAGES), function(key) {
  product <- sub("_[0-9]{4}$", "", key)
  year <- as.integer(sub(".*_", "", key))
  message("Parsing ", TREE_PAGES[[key]], " ...")
  classify(parse_tree(fetch(TREE_PAGES[[key]])), product, year)
}))

# --- 2. Deduplicate and repair ------------------------------------------------
# Trees list islands several times across branches, sometimes with different
# URLs: alternate packagings (raa2021.zip) and outright dead links (the 2011
# page points one RAA node at BGRI21_RAA.zip, which 404s). Where duplicate
# keys disagree, prefer the URL sharing the canonical prefix of that
# product-year's Continente file, verifying it is alive; otherwise fall back
# to whichever candidate is alive.

key <- with(manifest, paste(product, year, scope_type, scope_id))

cont_prefix <- vapply(split(manifest, paste(manifest$product, manifest$year)), function(rows) {
  cont <- unique(basename(rows$url[rows$scope_id == "CONT"]))
  stopifnot(length(cont) == 1L)
  sub("_CONT\\.zip$", "", cont)
}, character(1L))

resolved <- lapply(split(manifest, key), function(rows) {
  urls <- unique(rows$url)
  if (length(urls) == 1L) return(rows[1L, ])

  prefix <- cont_prefix[[paste(rows$product[1L], rows$year[1L])]]
  canonical <- urls[startsWith(basename(urls), paste0(prefix, "_"))]
  candidates <- if (length(canonical) >= 1L) canonical else urls

  alive <- vapply(paste0(CENSOS_BASE, "/", candidates), url_alive, logical(1L))
  if (sum(alive) != 1L) {
    stop("Cannot disambiguate URLs for ", rows$product[1L], " ", rows$year[1L],
         " ", rows$scope_id[1L], ": ", paste(urls, collapse = " | "))
  }
  chosen <- candidates[alive]
  message(sprintf(
    "  %s %d %s: kept %s (dropped %s)",
    rows$product[1L], rows$year[1L], rows$scope_id[1L],
    basename(chosen), paste(basename(setdiff(urls, chosen)), collapse = ", ")
  ))
  rows[rows$url == chosen, ][1L, ]
})
censos_manifest <- do.call(rbind, resolved)
rownames(censos_manifest) <- NULL

# --- 3. Sanity checks ---------------------------------------------------------

counts <- table(censos_manifest$product, censos_manifest$scope_type)
print(counts)

for (yr in c(1991L, 2001L, 2011L, 2021L)) {
  sub <- censos_manifest[censos_manifest$product == "bgri" & censos_manifest$year == yr, ]
  stopifnot(
    sum(sub$scope_type == "municipio") == 308L,
    sum(sub$scope_type == "nuts3") == 23L,
    sum(sub$scope_type == "nuts2") == 5L,
    sum(sub$scope_type == "region") == 3L,
    sum(sub$scope_type == "portugal") == 1L
  )
}
sec <- censos_manifest[censos_manifest$product == "seccoes", ]
stopifnot(sum(sec$scope_type == "municipio") == 308L)
stopifnot(nrow(censos_manifest[censos_manifest$product == "grid", ]) == 4L)

# All 308 dtmns, and the mainland NUTS3 ids, must match pt_nuts_codes. INE's
# census files follow the NUTS 2013 geography.
load("data/pt_nuts_codes.rda")
nuts_2013 <- pt_nuts_codes[pt_nuts_codes$nuts_vintage == "2013", ]
stopifnot(setequal(
  censos_manifest$scope_id[censos_manifest$product == "bgri" &
                             censos_manifest$year == 2021L &
                             censos_manifest$scope_type == "municipio"],
  unique(nuts_2013$dtmn)
))

# Mainland NUTS3 ids must match the NUTS-2013 codes (sans "PT")
n3_2013 <- unique(sub("^PT", "", nuts_2013$nuts3_cod[nuts_2013$nuts1_cod == "PT1"]))
stopifnot(setequal(
  censos_manifest$scope_id[censos_manifest$product == "bgri" &
                             censos_manifest$year == 2021L &
                             censos_manifest$scope_type == "nuts3"],
  n3_2013
))

# --- 4. Spot-check URLs live --------------------------------------------------

message("Spot-checking URLs ...")
spot <- censos_manifest[censos_manifest$scope_type != "municipio", ]
spot <- rbind(spot, do.call(rbind, lapply(
  split(censos_manifest[censos_manifest$scope_type == "municipio", ],
        paste(censos_manifest$product, censos_manifest$year)[
          censos_manifest$scope_type == "municipio"]),
  function(rows) rows[c(1L, nrow(rows) %/% 2L, nrow(rows)), ]
)))
ok <- vapply(paste0(CENSOS_BASE, "/", spot$url), url_alive, logical(1L))
if (!all(ok)) {
  print(spot[!ok, c("product", "year", "scope_id", "url")])
  stop(sum(!ok), " manifest URLs are dead.")
}
message(sprintf("  %d/%d spot-checked URLs alive.", sum(ok), length(ok)))

# --- 5. pt_censos_vars: variable dictionary -----------------------------------
# Stat columns observed in sample GeoPackages (Corvo = smallest municipality;
# RAA for the grid), described via INE's variable CSVs where a match exists.

# Mirror the runtime drop set (see CENSOS_DROP_COLS / CENSOS_DROP_PATTERN in
# R/censos.R) so the dictionary lists exactly the columns get_censos() keeps.
# N_ALOJ is the Açores-only 2011 artifact; OBJECTID_<n> are stray GIS keys.
NON_STAT_NUMERIC <- c(
  "OBJECTID", "ANO", "ORDEM", "NIVEL",
  "SHAPE_LENGTH", "SHAPE_AREA", "SHAPE_LENG", "N_ALOJ"
)
NON_STAT_PATTERN <- "^OBJECTID(_[0-9]+)?$"

read_sample <- function(url) {
  zip_path <- fetch(url, file.path(work_dir, basename(url)))
  members <- utils::unzip(zip_path, list = TRUE)$Name
  gpkg <- members[grepl("\\.gpkg$", members)]
  stopifnot(length(gpkg) == 1L)
  utils::unzip(zip_path, files = gpkg, exdir = work_dir, overwrite = TRUE)
  path <- file.path(work_dir, gpkg)
  layer <- sf::st_layers(path)$name
  stopifnot(length(layer) == 1L)
  sf::st_drop_geometry(sf::st_read(path, layer = layer, quiet = TRUE))
}

stat_cols <- function(df) {
  num <- names(df)[vapply(df, is.numeric, logical(1L))]
  up <- toupper(num)
  num[!(up %in% NON_STAT_NUMERIC | grepl(NON_STAT_PATTERN, up))]
}

SAMPLES <- list(
  list(year = 1991L, level = "subseccao", url = "filesGPG/1991/municipios/BGRE1991_4901.zip"),
  list(year = 2001L, level = "subseccao", url = "filesGPG/2001/municipios/BGRI2001_4901.zip"),
  list(year = 2011L, level = "subseccao", url = "filesGPG/2011/municipios/BGRI2011_4901.zip"),
  list(year = 2021L, level = "subseccao", url = "filesGPG/2021/municipios/BGRI2021_4901.zip"),
  list(year = 2021L, level = "seccao",    url = "filesGPG/2021Seccoes/municipios/C2021_SECCOES_4901.zip"),
  list(year = 2021L, level = "grid",      url = "filesGPG/2021grid/GRID1K21_RAA.zip")
)

vars <- do.call(rbind, lapply(SAMPLES, function(s) {
  message("Sampling ", s$url, " ...")
  data.frame(
    year = s$year, level = s$level,
    variable = stat_cols(read_sample(s$url)),
    stringsAsFactors = FALSE
  )
}))

# Descriptions: INE CSVs, matched on aggressively normalized names — the CSVs
# use spacing, accent, and "1946A1980"-style variants of the GeoPackage
# column names.
read_vars_csv <- function(path) {
  df <- utils::read.csv2(fetch(path), fileEncoding = "UTF-8-BOM",
                         stringsAsFactors = FALSE)
  names(df)[1:2] <- c("variable", "description")
  df$description <- trimws(df$description)
  df[!is.na(df$variable) & trimws(df$variable) != "", 1:2]
}

norm_key <- function(x) {
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
  x <- gsub("[^A-Z0-9]", "", toupper(x))
  # "0A14", "1946A1980" (CSV) vs "0_14", "1946_1980" (gpkg)
  gsub("(?<=[0-9])A(?=[0-9])", "", x, perl = TRUE)
}

desc_map <- local({
  csv_2021 <- read_vars_csv("C2021_FSINTESE_VARIAVEIS.csv")
  csv_2021$year <- 2021L
  csv_2021$level <- "subseccao"
  csv_sec <- read_vars_csv("C2021_FSINTESE_VARIAVEIS_SECCOES.csv")
  csv_sec$year <- 2021L
  csv_sec$level <- "seccao"
  csv_2011 <- read_vars_csv("C2011_FSINTESE_VARIAVEIS.csv")
  csv_2011$year <- 2011L
  csv_2011$level <- "subseccao"
  # Grid variables are a subset of the 2021 subsecção set
  csv_grid <- csv_2021
  csv_grid$level <- "grid"
  # 1991/2001 embed the same seven basic counts; INE ships no CSV for them.
  basic <- data.frame(
    variable = c("EDIFICIOS", "ALOJAMENTOS", "FAMILIAS",
                 "RESIDENTES_T", "RESIDENTES_H", "PRESENTES_T", "PRESENTES_H"),
    description = c(
      "Nº de edifícios clássicos",
      "Nº de alojamentos",
      "Nº de famílias",
      "População residente, total",
      "População residente, homens",
      "População presente, total",
      "População presente, homens"
    ),
    stringsAsFactors = FALSE
  )
  basic <- rbind(
    transform(basic, year = 1991L, level = "subseccao"),
    transform(basic, year = 2001L, level = "subseccao")
  )
  rbind(csv_2021, csv_sec, csv_2011, csv_grid, basic)
})

# Known one-off naming divergences (gpkg column -> CSV variable)
DESC_ALIASES <- c(
  "N_EDIFICIOS_3_OU_MAIS_PISOS" = "N_EDIFICIOS_3 MAIS_PISOS"
)
# Columns INE's CSVs do not document
DESC_EXTRA <- data.frame(
  variable = "N_SS",
  description = "Nº de subsecções estatísticas na secção",
  stringsAsFactors = FALSE
)

match_var <- function(v) {
  aliased <- ifelse(v %in% names(DESC_ALIASES), DESC_ALIASES[v], v)
  norm_key(sub("^F_", "", aliased))
}

desc_map$key <- paste(desc_map$year, desc_map$level, norm_key(desc_map$variable))
vars$key <- paste(vars$year, vars$level, match_var(vars$variable))
vars$description <- desc_map$description[match(vars$key, desc_map$key)]

# Second pass for truncated names: GeoPackage column names are truncated
# versions of the CSV names (e.g. a trailing "ANOS" or final "S" dropped), so
# accept a CSV key that uniquely *extends* the gpkg key within the year/level.
todo <- which(is.na(vars$description))
for (i in todo) {
  grp <- desc_map[paste(desc_map$year, desc_map$level) == paste(vars$year[i], vars$level[i]), ]
  vk <- match_var(vars$variable[i])
  gk <- sub("^[0-9]+ [a-z]+ ", "", grp$key)
  hits <- which(startsWith(gk, vk))
  if (length(hits) == 1L) vars$description[i] <- grp$description[hits]
}

vars$key <- NULL
hand <- match(vars$variable, DESC_EXTRA$variable)
vars$description[!is.na(hand)] <- DESC_EXTRA$description[hand[!is.na(hand)]]

n_desc <- sum(!is.na(vars$description))
message(sprintf("pt_censos_vars: %d variables, %d with descriptions (%d unmatched).",
                nrow(vars), n_desc, nrow(vars) - n_desc))
if (n_desc < nrow(vars)) {
  print(vars[is.na(vars$description), c("year", "level", "variable")])
}
print(table(vars$year, vars$level))

pt_censos_vars <- vars[order(vars$year, vars$level, vars$variable), ]
rownames(pt_censos_vars) <- NULL

# --- 6. Save -------------------------------------------------------------------

# save_internal() rather than use_data(internal = TRUE): R/sysdata.rda also
# holds the atom model written by derive_datasets.R, and use_data() would
# replace the whole file rather than merge into it.
source("data-raw/save_internal.R")
save_internal(censos_manifest = censos_manifest)

usethis::use_data(pt_censos_vars, overwrite = TRUE, compress = "xz")

message("Done.")
