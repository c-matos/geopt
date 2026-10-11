# pt_crosswalk() and pt_recode() across the 2011 vintage. Offline.

xw11 <- pt_crosswalk("2011", "2025")
xw13 <- pt_crosswalk("2011", "2013")

# --- 2011 crosswalk integrity -----------------------------------------------------

test_that("every 2011 freguesia maps to one 2013 and one 2025 freguesia", {
  r11 <- pt_lookup(admin_vintage = "2011")
  expect_setequal(xw11$from, r11$dtmnfr)
  expect_false(anyDuplicated(xw11$from) > 0)
  expect_false(anyNA(xw11$to))
  expect_true(all(xw11$to %in% pt_lookup()$dtmnfr))
  expect_setequal(xw13$from, r11$dtmnfr)
  expect_false(anyDuplicated(xw13$from) > 0)
  expect_true(all(xw13$to %in% pt_lookup(admin_vintage = "2013")$dtmnfr))
  expect_false(anyNA(r11$municipio))
  expect_setequal(unique(xw11$relation),
                  c("unchanged", "renamed", "renumbered", "merged"))
  expect_gt(nrow(xw11), 4000)              # 4260 pre-2013 freguesias
})

test_that("codes are internally consistent with grain finest->coarsest", {
  # unchanged and renamed: same code across all three vintages
  u <- xw11[xw11$relation %in% c("unchanged", "renamed"), ]
  expect_true(all(u$from == u$to))
  expect_true(all(u$from == xw13$to[match(u$from, xw13$from)]))

  # merged current units genuinely gather several pre-2013 freguesias
  merged_targets <- unique(xw11$to[xw11$relation == "merged"])
  counts <- table(xw11$to[xw11$to %in% merged_targets])
  expect_true(all(counts >= 2))
})

test_that("every pre-2013 freguesia carries its own name", {
  # Names come from the Censos 2011 geography of INE indicator 0006393 (see
  # data-raw/fetch_2011_names.R), which covers the vintage in full.
  expect_false(anyNA(xw11$name_from))
  expect_true(all(nzchar(xw11$name_from)))

  # the units merged into unions are named too, and are the point of the column
  merged <- xw11[xw11$relation == "merged", ]
  expect_gt(nrow(merged), 0L)
  expect_false(anyNA(merged$name_from))

  # a name may legitimately differ from the current unit's
  expect_equal(xw11$name_from[xw11$from == "030352"], "Braga (Sé)")
  expect_equal(xw11$name_to[xw11$from == "030352"],
               "União das freguesias de Braga (Maximinos, Sé e Cividade)")
})

# --- pt_recode across the 2011 vintage -----------------------------------------

# a current union that gathers >= 2 pre-2013 freguesias
merged_union <- names(which(table(
  xw11$to[xw11$relation == "merged"]) >= 2))[1]
members_2011 <- xw11$from[xw11$to == merged_union]

test_that("2011 -> 2025 merges pre-2013 freguesias (aggregate required)", {
  df <- data.frame(dtmnfr = members_2011, pop = rep(10, length(members_2011)))
  expect_error(
    pt_recode(df, from = "2011", to = "2025", values = "pop"),
    "aggregate"
  )
  out <- pt_recode(df, from = "2011", to = "2025", values = "pop",
                   aggregate = sum, quiet = TRUE)
  expect_equal(nrow(out), 1L)
  expect_equal(out$dtmnfr, merged_union)
  expect_equal(out$pop, 10 * length(members_2011))
})

test_that("2025 -> 2011 splits a unit back to its pre-2013 freguesias", {
  df <- data.frame(dtmnfr = merged_union, v = 100)
  expect_error(
    pt_recode(df, from = "2025", to = "2011", values = "v"),
    "split"
  )
  out <- pt_recode(df, from = "2025", to = "2011", values = "v",
                   split = "replicate", quiet = TRUE)
  expect_setequal(out$dtmnfr, members_2011)
  expect_true(all(out$v == 100))
})

test_that("2011 -> 2013 aggregates onto the união", {
  df <- data.frame(dtmnfr = members_2011, pop = rep(5, length(members_2011)))
  out <- pt_recode(df, from = "2011", to = "2013", values = "pop",
                   aggregate = sum, quiet = TRUE)
  target_2013 <- unique(xw13$to[xw13$from %in% members_2011])
  expect_true(all(out$dtmnfr %in% target_2013))
  expect_equal(sum(out$pop), 5 * length(members_2011))
})

test_that("unchanged pre-2013 codes convert 1:1 to 2025", {
  code <- xw11$from[xw11$relation == "unchanged"][1]
  out <- pt_recode(data.frame(dtmnfr = code, n = 3),
                   from = "2011", to = "2025", quiet = TRUE)
  expect_equal(nrow(out), 1L)
  expect_equal(out$dtmnfr, code)
})

test_that("default target and area weights behave sensibly for 2011", {
  # leaving `to` out means the newest vintage
  out <- pt_recode(data.frame(dtmnfr = members_2011[1], n = 1),
                   from = "2011", quiet = TRUE)
  ref <- pt_recode(data.frame(dtmnfr = members_2011[1], n = 1),
                   from = "2011", to = "2025", quiet = TRUE)
  expect_equal(out, ref)

  # area weights only towards the newest vintage
  df <- data.frame(dtmnfr = merged_union, v = 10)
  expect_error(
    pt_recode(df, from = "2025", to = "2011", values = "v",
              split = "weight", weights = "area"),
    "towards the newest"
  )
})

test_that("vintages are named by their year only", {
  df <- data.frame(dtmnfr = members_2011, pop = rep(10, length(members_2011)))

  # There is no label for the newest vintage: "current" would change meaning
  # when a newer map is added. "pre2013" is ambiguous, as there are two
  # pre-2013 maps. "2002" names a NUTS revision, not a freguesia map.
  for (label in c("current", "pre2013", "2002")) {
    expect_error(pt_recode(df, from = label, values = "pop", aggregate = sum),
                 "`from` must be one of")
    expect_error(pt_recode(df, from = "2011", to = label, values = "pop",
                           aggregate = sum), "`to` must be one of")
    expect_error(pt_crosswalk(label, "2025"), "`from` must be one of")
    expect_error(pt_crosswalk("2013", label), "`to` must be one of")
    expect_error(pt_lookup(admin_vintage = label), "`admin_vintage` must be one of")
    expect_error(pt_match("Porto", admin_vintage = label, quiet = TRUE),
                 "`admin_vintage` must be one of")
  }
  expect_error(pt_lookup(nuts_vintage = "current"), "`nuts_vintage` must be one of")
  expect_error(pt_lookup(health_vintage = "current"), "`health_vintage` must be one of")
})

# --- NUTS 2002 -----------------------------------------------------------------

test_that("the pre-2013 NUTS III nomenclature is complete", {
  n02 <- pt_lookup(nuts_vintage = "2002")
  expect_false(anyNA(n02$nuts3_cod))
  expect_false(anyNA(n02$nuts3))

  # 30 units, the full pre-2013 scheme including the three alphanumeric codes
  expect_equal(length(unique(n02$nuts3_cod)), 30L)
  expect_true(all(c("PT16A", "PT16B", "PT16C") %in% n02$nuts3_cod))

  # code <-> name is 1:1
  expect_equal(length(unique(n02$nuts3_cod)), length(unique(n02$nuts3)))

  # A statistical geography must not split a municipality
  per_dtmn <- tapply(n02$nuts3_cod, n02$dtmn, function(v) length(unique(v)))
  expect_true(all(per_dtmn == 1L))

  # NUTS 2 is unchanged between the 2002 and 2013 nomenclatures
  n13 <- pt_lookup(nuts_vintage = "2013")
  expect_equal(substr(n02$nuts3_cod, 1L, 4L),
               n13$nuts2_cod[match(n02$dtmnfr, n13$dtmnfr)])
})

test_that("the 2002 -> 2013 NUTS III transitions are the documented ones", {
  mu <- pt_lookup("municipio", nuts_vintage = "2002")
  n13 <- pt_lookup("municipio", nuts_vintage = "2013")

  # The three codes absent from the source workbook, reconstructed
  expect_setequal(mu$municipio[mu$nuts3_cod == "PT16A"],
                  c("Belmonte", "Covilhã", "Fundão"))
  expect_equal(sum(mu$nuts3_cod == "PT16B"), 12L)   # Oeste
  expect_equal(sum(mu$nuts3_cod == "PT16C"), 10L)   # Médio Tejo

  # Grande Porto was 9 municipios in 2002: Santo Tirso and Trofa were in Ave
  # and only joined the Área Metropolitana do Porto with the 2013 revision.
  expect_equal(sum(mu$nuts3_cod == "PT114"), 9L)
  expect_equal(mu$nuts3_cod[mu$municipio == "Santo Tirso"], "PT113")
  expect_equal(n13$nuts3[n13$municipio == "Santo Tirso"],
               "Área Metropolitana do Porto")
})
