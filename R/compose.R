#' Offset an sf geometry
#'
#' Centers the geometry at its bounding-box centroid, optionally scales it,
#' then translates it to a new position. Used to move island groups into
#' their insets. Internal: to move the islands, edit the layout from
#' island_layout() instead.
#'
#' @param sf_obj An sf object.
#' @param x_offset Target x coordinate (in CRS units).
#' @param y_offset Target y coordinate (in CRS units).
#' @param scale Scale factor applied after centering. Default `1` (no scaling).
#'
#' @return An sf object with transformed geometry (same CRS, same attributes).
#' @noRd
offset_geometry <- function(sf_obj, x_offset, y_offset, scale = 1) {
  bbox <- sf::st_bbox(sf_obj)
  center_x <- (bbox["xmin"] + bbox["xmax"]) / 2
  center_y <- (bbox["ymin"] + bbox["ymax"]) / 2

  original_crs <- sf::st_crs(sf_obj)

  new_geom <- sf_obj |>
    sf::st_geometry() |>
    {\(g) g - c(center_x, center_y)}() |>
    {\(g) g * scale}() |>
    {\(g) g + c(x_offset, y_offset)}()

  sf::st_crs(new_geom) <- original_crs
  sf::st_geometry(sf_obj) <- new_geom
  sf_obj
}

#' Offset a group of sf objects around a shared anchor
#'
#' Each element in `groups` is a list with `$sf`, `$offset` (length-2 numeric),
#' and optionally `$scale`. The final position of each sub-group is
#' `anchor + offset`.
#'
#' @param groups A named list of lists, each containing:
#'   \describe{
#'     \item{sf}{An sf object.}
#'     \item{offset}{Numeric vector of length 2 (x, y) relative to anchor.}
#'     \item{scale}{Optional scale factor (default 1).}
#'   }
#' @param anchor Numeric vector of length 2 (x, y) — the shared origin for
#'   the group.
#'
#' @return A named list of sf objects with transformed geometries.
#' @noRd
offset_group <- function(groups, anchor) {
  lapply(groups, function(g) {
    offset_geometry(
      g$sf,
      x_offset = anchor[1] + g$offset[1],
      y_offset = anchor[2] + g$offset[2],
      scale = g$scale %||% 1
    )
  })
}

#' Create a bounding box polygon around one or more sf objects
#'
#' Combines the geometries, computes the overall bounding box, adds a buffer,
#' and returns it as an `sfc` polygon.
#'
#' @param ... One or more sf objects.
#' @param buffer Buffer distance in CRS units added to each side of the
#'   bounding box.
#'
#' @return An `sfc` polygon (single rectangle).
#' @noRd
bbox_around <- function(..., buffer = 0.1) {
  combined <- do.call(rbind, lapply(list(...), function(x) {
    if (inherits(x, "sf")) x else sf::st_sf(geometry = x)
  }))

  bbox <- sf::st_bbox(combined)
  bbox["xmin"] <- bbox["xmin"] - buffer
  bbox["xmax"] <- bbox["xmax"] + buffer
  bbox["ymin"] <- bbox["ymin"] - buffer
  bbox["ymax"] <- bbox["ymax"] + buffer

  box <- sf::st_as_sfc(bbox)
  sf::st_crs(box) <- sf::st_crs(combined)
  box
}
