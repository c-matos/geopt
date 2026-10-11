# --- Island layout ------------------------------------------------------------------

#' Lay out the islands
#'
#' The Açores are about 1,500 km west of the mainland and Madeira about
#' 1,000 km to the south-west, so a map of Portugal drawn to scale is mostly
#' ocean. [get_map()] and [plot_pt()] move the islands next to the mainland,
#' as insets. `island_layout()` says how: which archipelagos to show, how to
#' split them into insets, and whether to draw frames around them.
#'
#' Pass the result as `islands` to [get_map()] or [plot_pt()]. For the common
#' cases a string is enough: `islands = "none"` is the same as
#' `islands = island_layout("none")`.
#'
#' @section Choices:
#' Each archipelago takes one of:
#' \describe{
#'   \item{`"compact"`}{(The default.) Insets arranged to take the least room:
#'     the Açores in four insets (the western group, the central group, São
#'     Miguel, and Santa Maria on its own), and Porto Santo in its own small
#'     inset, moved next to Madeira.}
#'   \item{`"groups"`}{The Açores in their three official groups (Ocidental,
#'     Central and Oriental). Madeira has no groups, so for Madeira this is the
#'     same as `"compact"`.}
#'   \item{`"whole"`}{Madeira and Porto Santo in one inset, at their true
#'     distance apart. Not available for
#'     the Açores: at a size that fits next to the mainland, the smaller
#'     islands would be too small to read.}
#'   \item{`"box"`}{A labelled rectangle instead of the islands, stacked to
#'     the left of the mainland. Only works at levels where each archipelago
#'     is a single region: `"nuts1"`, `"nuts2"`, `"nuts3"` and `"reg_saude"`.
#'     Can't be combined with insets.}
#'   \item{`"in_place"`}{The islands where they really are, without frames.
#'     The starting point for a map of one archipelago (see Examples).}
#'   \item{`"none"`}{Leave the archipelago out.}
#' }
#'
#' @section Frames:
#' With `frames = TRUE`, [get_map()] adds the frames drawn around the insets,
#' which show that the islands have been moved. They are extra rows with
#' `geopt_type = "frame"`, their name in `geopt_label`, and
#' `geopt_frame_level` saying what they surround: 1 for a whole archipelago,
#' 2 for a group of islands and 3 for a single island.
#'
#' @section Moving and resizing the islands:
#' `island_layout()` returns a list, which you can change before passing it
#' on. Each archipelago drawn as insets has:
#' \describe{
#'   \item{`anchor`}{Longitude and latitude its insets are placed around.}
#'   \item{`label`}{The name on its frame (and on its rectangle, for `"box"`).}
#'   \item{`frame_buffer`}{Space between the islands and the frame around the
#'     whole archipelago, in degrees.}
#'   \item{`groups`}{One entry per inset, each with:
#'     \describe{
#'       \item{`crop`}{The part of the archipelago this inset shows, as
#'         `c(xmin =, ymin =, xmax =, ymax =)` in longitude and latitude.
#'         `NULL` shows the whole archipelago.}
#'       \item{`offset`}{Where the inset goes, as `c(x, y)` in degrees from
#'         `anchor`.}
#'       \item{`scale`}{How much to enlarge it. Default 1.}
#'       \item{`label`}{Optional. Draws a frame around this inset alone, with
#'         this name.}
#'       \item{`frame_level`, `frame_buffer`}{Optional. That frame's
#'         `geopt_frame_level` (default 3) and its space around the islands.}
#'     }
#'   }
#'   \item{`sub_frames`}{Optional. Frames around several insets at once, each
#'     with `groups` (the inset names), `label`, and optionally
#'     `frame_buffer` and `frame_level` (default 2).}
#' }
#' Print `island_layout()$raa` to see a complete example. To lay out an
#' archipelago from scratch, pass a list with the same structure as `raa` or
#' `ram`.
#'
#' @param both How to show both archipelagos: `"compact"`, `"groups"`,
#'   `"box"`, `"in_place"` or `"none"`. See Choices.
#' @param raa,ram How to show the Açores (`raa`) or Madeira (`ram`), when it
#'   should differ from `both`: one of the choices, or a layout list (see
#'   Moving and resizing the islands section below).
#' @param frames Draw frames around the insets? Only applies to archipelagos
#'   drawn as insets.
#' @param box_position Where to put the rectangles, for `"box"`:
#'   `"bottom_left"` or `"top_left"` of the mainland, or `c(x, y)`, the
#'   longitude and latitude of the bottom-left corner of the stack.
#'
#' @return An island layout, to pass as `islands` to [get_map()] or
#'   [plot_pt()].
#'
#' @examples
#' island_layout()
#' island_layout(raa = "groups", ram = "whole")
#'
#' @examplesIf identical(Sys.getenv("NOT_CRAN"), "true")
#' get_map("municipio", islands = "none")    # mainland only
#' get_map("nuts3", islands = "box")
#' get_map("nuts3", islands = island_layout("box", box_position = "top_left"))
#' get_map("municipio", islands = island_layout(frames = FALSE))
#'
#' # The Açores alone, in their true position
#' m <- get_map("municipio", islands = "in_place")
#' acores <- m[m$nuts2_cod %in% "PT20", ]
#'
#' # Move the Açores half a degree west, with an English label
#' lay <- island_layout()
#' lay$raa$anchor <- lay$raa$anchor + c(-0.5, 0)
#' lay$raa$label <- "Azores"
#' get_map("nuts3", islands = lay)
#'
#' @seealso [get_map()], [plot_pt()]
#' @export
island_layout <- function(both = "compact",
                          raa = both,
                          ram = both,
                          frames = TRUE,
                          box_position = "bottom_left") {
  check_island_both(both, "both")

  out <- structure(
    list(
      raa = resolve_island_region("raa", raa),
      ram = resolve_island_region("ram", ram),
      frames = frames,
      box_position = box_position
    ),
    class = "geopt_island_layout"
  )
  validate_island_layout(out)

  shows <- c(out$raa$show, out$ram$show)
  if (!missing(frames) && !"inset" %in% shows) {
    warning("`frames` has no effect: no archipelago is drawn as insets.",
            call. = FALSE)
  }
  if (!missing(box_position) && !"box" %in% shows) {
    warning("`box_position` has no effect: no archipelago is drawn as a box.",
            call. = FALSE)
  }
  out
}

#' @export
print.geopt_island_layout <- function(x, ...) {
  cat("<island layout>\n")
  titles <- c(raa = "raa (A\u00e7ores):", ram = "ram (Madeira):")
  for (r in c("raa", "ram")) {
    cfg <- x[[r]]
    what <- switch(
      cfg$show,
      inset = sprintf("%d inset%s: %s", length(cfg$groups),
                      if (length(cfg$groups) == 1L) "" else "s",
                      paste(names(cfg$groups), collapse = ", ")),
      box = sprintf("a rectangle labelled \"%s\"", cfg$label),
      in_place = "in its true position",
      none = "left out"
    )
    cat(sprintf("  %-15s %-9s %s\n", titles[[r]], cfg$preset, what))
  }
  shows <- c(x$raa$show, x$ram$show)
  if ("inset" %in% shows) {
    cat(sprintf("  %-15s %s\n", "frames:", if (isTRUE(x$frames)) "yes" else "no"))
  }
  if ("box" %in% shows) {
    pos <- x$box_position
    if (is.numeric(pos)) pos <- sprintf("c(%s, %s)", pos[1L], pos[2L])
    cat(sprintf("  %-15s %s\n", "box position:", pos))
  }
  invisible(x)
}


# --- Values and presets -------------------------------------------------------------

ISLAND_REGION_VALUES <- list(
  raa = c("compact", "groups", "box", "in_place", "none"),
  ram = c("compact", "groups", "whole", "box", "in_place", "none")
)

# The values `both` (and a bare `islands` string) take: the ones both
# archipelagos support.
ISLAND_BOTH_VALUES <- c("compact", "groups", "box", "in_place", "none")

ISLAND_LABELS <- c(raa = "A\u00e7ores", ram = "Madeira")

# Inset presets per archipelago. The numbers are hand-tuned: each crop is the
# bounding box of an island group, each offset/scale places it next to the
# mainland. Madeira has no "groups" preset: it means "compact" there.
ISLAND_PRESETS <- list(
  raa = list(
    compact = list(
      anchor = c(-10.2, 40.75),
      label = ISLAND_LABELS[["raa"]],
      frame_buffer = 0.1,
      groups = list(
        ocidental = list(
          crop   = c(xmin = -31.30, ymin = 39.35, xmax = -31.05, ymax = 39.75),
          offset = c(-0.7, 0.95),
          scale  = 1.5,
          label  = "Grupo Ocidental",
          frame_level  = 2L,
          frame_buffer = 0.05
        ),
        central = list(
          crop   = c(xmin = -28.86, ymin = 38.33, xmax = -27.00, ymax = 39.11),
          offset = c(-0.1, 0.27),
          scale  = 1.1
        ),
        s_miguel = list(
          crop   = c(xmin = -25.89, ymin = 37.67, xmax = -25.10, ymax = 37.94),
          offset = c(-0.23, -0.54),
          scale  = 1.5
        ),
        s_maria = list(
          crop   = c(xmin = -25.19, ymin = 36.92, xmax = -25.01, ymax = 37.03),
          offset = c(0.7, -0.63),
          scale  = 1.5,
          label  = "Santa Maria",
          frame_buffer = 0.03
        )
      ),
      sub_frames = list(
        oriental = list(
          groups = c("s_miguel", "s_maria"),
          label  = "Grupo Oriental",
          frame_buffer = 0.05
        )
      )
    ),
    groups = list(
      anchor = c(-10.9, 40.75),
      label = ISLAND_LABELS[["raa"]],
      frame_buffer = 0.1,
      groups = list(
        ocidental = list(
          crop   = c(xmin = -31.30, ymin = 39.35, xmax = -31.05, ymax = 39.75),
          offset = c(-0.9, 0.95),
          scale  = 1.5,
          label  = "Grupo Ocidental",
          frame_level  = 2L,
          frame_buffer = 0.05
        ),
        central = list(
          crop   = c(xmin = -28.86, ymin = 38.33, xmax = -27.00, ymax = 39.11),
          offset = c(-0.1, 0.27),
          scale  = 1.1
        ),
        oriental = list(
          crop   = c(xmin = -25.89, ymin = 36.92, xmax = -25.01, ymax = 37.94),
          offset = c(0.6, -1),
          scale  = 1.2,
          label  = "Grupo Oriental",
          frame_level  = 2L,
          frame_buffer = 0.05
        )
      )
    )
  ),
  ram = list(
    compact = list(
      anchor = c(-9.9, 37.78),
      label = ISLAND_LABELS[["ram"]],
      frame_buffer = 0.15,
      groups = list(
        madeira = list(
          crop   = c(xmin = -17.28, ymin = 32.61, xmax = -16.65, ymax = 32.89),
          offset = c(-0.4, -0.23),
          scale  = 3
        ),
        porto_santo = list(
          crop   = c(xmin = -16.42, ymin = 32.98, xmax = -16.27, ymax = 33.14),
          offset = c(0.35, 0.23),
          scale  = 3,
          label  = "Porto Santo",
          frame_buffer = 0.03
        )
      )
    ),
    whole = list(
      anchor = c(-10.9, 37.78),
      label = ISLAND_LABELS[["ram"]],
      frame_buffer = 0.15,
      groups = list(
        madeira = list(
          crop   = c(xmin = -17.28, ymin = 32.61, xmax = -16.24, ymax = 33.14),
          offset = c(0, 0),
          scale  = 2.2
        )
      )
    )
  )
)


# --- Resolution and validation ------------------------------------------------------

#' Check the value of `both` (or of a bare `islands` string)
#' @noRd
check_island_both <- function(value, arg) {
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    stop(sprintf(
      "`%s` must be one of %s, or made with island_layout().",
      arg, quote_values(ISLAND_BOTH_VALUES)
    ), call. = FALSE)
  }
  if (identical(value, "whole")) {
    stop(sprintf(
      paste0(
        "`%s = \"whole\"` isn't available: the A\u00e7ores can't be drawn as one ",
        "inset. For Madeira alone, use island_layout(ram = \"whole\")."
      ),
      arg
    ), call. = FALSE)
  }
  if (!value %in% ISLAND_BOTH_VALUES) {
    stop(sprintf("`%s` must be one of %s, not \"%s\".",
                 arg, quote_values(ISLAND_BOTH_VALUES), value), call. = FALSE)
  }
  invisible(value)
}

#' Expand one archipelago's value into its region config
#' @noRd
resolve_island_region <- function(region, value) {
  if (is.list(value)) {
    value$show <- value$show %||% "inset"
    value$preset <- value$preset %||% "custom"
    value$label <- value$label %||% ISLAND_LABELS[[region]]
    return(value)
  }
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    stop(sprintf("`%s` must be a single value, such as \"compact\", or a layout list.",
                 region), call. = FALSE)
  }
  if (region == "raa" && identical(value, "whole")) {
    stop(paste0(
      "The A\u00e7ores can't be drawn as one inset: at a size that fits next to ",
      "the mainland, the smaller islands would be too small to read. For a ",
      "map of the A\u00e7ores alone, use \"in_place\" and filter the result ",
      "(see ?island_layout)."
    ), call. = FALSE)
  }
  valid <- ISLAND_REGION_VALUES[[region]]
  if (!value %in% valid) {
    stop(sprintf("`%s` must be one of %s, not \"%s\".",
                 region, quote_values(valid), value), call. = FALSE)
  }

  if (value %in% c("box", "in_place", "none")) {
    return(list(show = value, preset = value, label = ISLAND_LABELS[[region]]))
  }
  preset <- if (region == "ram" && value == "groups") "compact" else value
  c(list(show = "inset", preset = value), ISLAND_PRESETS[[region]][[preset]])
}

#' Turn get_map()'s `islands` argument into a validated island layout
#' @noRd
as_island_layout <- function(islands) {
  if (inherits(islands, "geopt_island_layout")) {
    return(validate_island_layout(islands))
  }
  if (is.character(islands)) {
    check_island_both(islands, "islands")
    return(island_layout(islands))
  }
  stop(sprintf(
    "`islands` must be one of %s, or made with island_layout().",
    quote_values(ISLAND_BOTH_VALUES)
  ), call. = FALSE)
}

#' Check an island layout, including one edited by hand
#' @noRd
validate_island_layout <- function(x) {
  for (r in c("raa", "ram")) validate_island_region(x[[r]], r)

  shows <- c(x$raa$show, x$ram$show)
  if ("box" %in% shows && "inset" %in% shows) {
    stop(paste0(
      "\"box\" can't be combined with insets: the rectangles would overlap ",
      "the inset. Use \"box\" for both archipelagos, or leave one out with ",
      "\"none\"."
    ), call. = FALSE)
  }
  if (!is.logical(x$frames) || length(x$frames) != 1L || is.na(x$frames)) {
    stop("`frames` must be TRUE or FALSE.", call. = FALSE)
  }
  pos <- x$box_position
  pos_ok <- (is.numeric(pos) && length(pos) == 2L && all(is.finite(pos))) ||
    (is.character(pos) && length(pos) == 1L && pos %in% c("bottom_left", "top_left"))
  if (!pos_ok) {
    stop("`box_position` must be \"bottom_left\", \"top_left\", or c(x, y).",
         call. = FALSE)
  }
  invisible(x)
}

#' Check one archipelago's region config
#' @noRd
validate_island_region <- function(cfg, region) {
  bad <- function(what) {
    stop(sprintf("The `%s` layout is not valid: %s.", region, what),
         call. = FALSE)
  }
  is_xy <- function(v) is.numeric(v) && length(v) == 2L && all(is.finite(v))
  is_num <- function(v) is.numeric(v) && length(v) == 1L && is.finite(v)

  if (!is.list(cfg)) bad("expected a list")
  shows <- c("inset", "box", "in_place", "none")
  if (!is.character(cfg$show) || length(cfg$show) != 1L || !cfg$show %in% shows) {
    bad(sprintf("`show` must be one of %s", quote_values(shows)))
  }
  if (!is.character(cfg$label) || length(cfg$label) != 1L || is.na(cfg$label)) {
    bad("`label` must be a single string")
  }
  if (cfg$show != "inset") return(invisible(cfg))

  if (!is_xy(cfg$anchor)) bad("`anchor` must be two numbers, c(x, y)")
  if (!is.null(cfg$frame_buffer) && !is_num(cfg$frame_buffer)) {
    bad("`frame_buffer` must be a number")
  }
  groups <- cfg$groups
  if (!is.list(groups) || length(groups) == 0L || is.null(names(groups)) ||
      any(names(groups) == "")) {
    bad("`groups` must be a named list with one entry per inset")
  }
  for (nm in names(groups)) {
    g <- groups[[nm]]
    where <- sprintf("groups$%s", nm)
    if (!is.list(g)) bad(sprintf("`%s` must be a list", where))
    if (!is_xy(g$offset)) bad(sprintf("`%s$offset` must be two numbers, c(x, y)", where))
    if (!is.null(g$scale) && !(is_num(g$scale) && g$scale > 0)) {
      bad(sprintf("`%s$scale` must be a positive number", where))
    }
    crop_names <- c("xmin", "ymin", "xmax", "ymax")
    if (!is.null(g$crop) &&
        !(is.numeric(g$crop) && all(crop_names %in% names(g$crop)))) {
      bad(sprintf("`%s$crop` must be c(xmin =, ymin =, xmax =, ymax =)", where))
    }
  }
  for (sb in names(cfg$sub_frames %||% list())) {
    members <- cfg$sub_frames[[sb]]$groups
    if (!is.character(members) || !all(members %in% names(groups))) {
      bad(sprintf("`sub_frames$%s$groups` must name entries of `groups`", sb))
    }
  }
  invisible(cfg)
}

#' Format values for an error message: "a", "b" or "c"
#' @noRd
quote_values <- function(x) {
  x <- paste0("\"", x, "\"")
  if (length(x) == 1L) return(x)
  paste0(paste(x[-length(x)], collapse = ", "), " or ", x[length(x)])
}
