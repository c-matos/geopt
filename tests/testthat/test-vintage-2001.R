# The 2001 administrative vintage: the freguesia map the 2001 census used.
# Offline. See data-raw/fetch_2001_registry.R and
# data-raw/freguesia_changes_2001_2011.csv.

x01 <- pt_crosswalk("2001", "2011")

test_that("the 2001 vintage has the 2001 census's 4241 freguesias", {
  reg <- as.data.frame(get_dataset("pt_registry"))
  r01 <- reg[reg$admin_vintage == "2001", ]
  expect_equal(nrow(r01), 4241L)
  expect_equal(anyDuplicated(r01$dtmnfr), 0L)
  expect_false(anyNA(r01$freguesia))
  expect_equal(nrow(pt_lookup(admin_vintage = "2001")), 4241L)

  # the three freguesias dissolved before the 2011 census exist only here
  expect_setequal(setdiff(r01$dtmnfr, reg$dtmnfr[reg$admin_vintage == "2011"]),
                  c("111101", "420205", "420302"))
  expect_equal(r01$freguesia[r01$dtmnfr == "111101"], "Agualva-Cacém")
})

test_that("2001 and 2011 differ by exactly the listed changes", {
  # 4241 - 3 dissolved + 22 created = 4260; every other code is shared
  expect_equal(length(unique(x01$from)), 4241L)
  expect_equal(length(unique(x01$to)), 4260L)
  created <- setdiff(x01$to, x01$from)
  expect_length(created, 22L)

  # the created ones are all splits of a 2001 unit
  expect_true(all(x01$relation[x01$to %in% created] == "split"))

  # Agualva-Cacém became four freguesias (Lei 18-C/2001)
  expect_setequal(x01$to[x01$from == "111101"],
                  c("111118", "111119", "111120", "111121"))
})

test_that("two 2011 freguesias were carved out of two 2001 ones each", {
  # Boavista dos Pinheiros (Lei 18-F/2001) and Santa Cruz/Trindade: confirmed
  # by overlaying the 2011 census areas on the 2001 ones
  two <- names(which(table(x01$to) > 1L))
  expect_setequal(two, c("021116", "170352"))
  expect_setequal(x01$from[x01$to == "021116"], c("021105", "021108"))
  expect_setequal(x01$from[x01$to == "170352"], c("170321", "170350"))
})

test_that("a parent that lost territory keeps its code but splits", {
  # Ponte (Guimaraes) gave up Corvite in 2004: same code, smaller territory
  expect_setequal(x01$to[x01$from == "030838"], c("030838", "030874"))
  expect_true(all(x01$relation[x01$from == "030838"] == "split"))
})

test_that("pt_recode converts 2001 data both ways", {
  # 2001 -> 2011 splits: opt in
  df <- data.frame(dtmnfr = "111101", rate = 12.5)
  expect_error(pt_recode(df, from = "2001", to = "2011", values = "rate"), "split")
  out <- pt_recode(df, from = "2001", to = "2011", values = "rate",
                   split = "replicate", quiet = TRUE)
  expect_setequal(out$dtmnfr, c("111118", "111119", "111120", "111121"))
  expect_true(all(out$rate == 12.5))

  # 2011 -> 2001 merges them back
  back <- pt_recode(data.frame(dtmnfr = c("111118", "111119", "111120", "111121"),
                               pop = c(1, 2, 3, 4)),
                    from = "2011", to = "2001", values = "pop",
                    aggregate = sum, quiet = TRUE)
  expect_equal(back$dtmnfr, "111101")
  expect_equal(back$pop, 10)
})

test_that("the census-area codes of two transferred freguesias are accepted", {
  # INE's 2001 list files Vale de Amoreira and Moita under their new
  # municipality; the 2001 census areas still use the old codes
  expect_equal(pt_match(c("090756", "100117"), level = "freguesia",
                        admin_vintage = "2001", quiet = TRUE),
               c("090804", "101003"), ignore_attr = TRUE)
  a <- pt_recode(data.frame(dtmnfr = "090756", n = 5), from = "2001", quiet = TRUE)
  b <- pt_recode(data.frame(dtmnfr = "090804", n = 5), from = "2001", quiet = TRUE)
  expect_equal(a, b)

  # but only for the 2001 vintage: codes are vintage-local
  expect_true(is.na(pt_match("090756", level = "freguesia", quiet = TRUE)))
})

test_that("2001 names resolve at 2001, and don't make later names ambiguous", {
  expect_equal(pt_match(c("Agualva-Cacém", "Cavês"), level = "freguesia",
                        context = c("Sintra", "Cabeceiras de Basto"),
                        admin_vintage = "2001", quiet = TRUE),
               c("111101", "030407"), ignore_attr = TRUE)

  # Today, Agualva-Cacém covers two uniões, so the name is ambiguous
  expect_true(is.na(pt_match("Agualva-Cacém", level = "freguesia",
                             context = "Sintra", quiet = TRUE)))

  # A parent's name is also a 2011 name, and the 2011 sense wins, so the 2001
  # name does not make these ambiguous
  cur <- pt_crosswalk("2011", "2025")
  r11 <- pt_lookup(admin_vintage = "2011")
  for (code in c("021108", "170321", "420313")) {
    nm <- cur$name_from[cur$from == code][1]
    mun <- r11$municipio[r11$dtmnfr == code]
    expect_equal(pt_match(nm, level = "freguesia", context = mun, quiet = TRUE),
                 cur$to[cur$from == code][1], ignore_attr = TRUE,
                 info = nm)
  }
})

test_that("health columns reach every 2001 freguesia", {
  # a 2001 unit that later split reaches several current freguesias; all of
  # the affected ones lie in municipalities with a single health unit
  h <- pt_lookup(admin_vintage = "2001", health_vintage = "2024")
  expect_equal(nrow(h), 4241L)
  expect_false(anyNA(h$unit))
})

test_that("auto-detection tells 2001 from 2011 only when the data can", {
  expect_message(
    got <- pt_match(c("Agualva-Cacém", "Nordestinho"), level = "freguesia",
                    admin_vintage = "auto"),
    "2001 freguesia vintage")
  expect_equal(got, c("111101", "420205"), ignore_attr = TRUE)

  # Codes both maps share, and today's map does not: the tie goes to the newer
  # vintage (not to the current one, which accounts for none of them), and the
  # message says the other fits too
  expect_message(
    got <- pt_match(c("030352", "030324"), level = "freguesia",
                    admin_vintage = "auto"),
    "2011 freguesia vintage.*2001 fits equally well")
  expect_equal(got, c("030352", "030324"), ignore_attr = TRUE)
})
