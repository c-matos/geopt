# A GeoClient whose cache is a temporary directory, removed when the calling
# test ends.
local_client <- function(...) {
  GeoClient$new(cache_dir = withr::local_tempdir(.local_envir = parent.frame()), ...)
}

# Fails the calling test if anything tries to download.
local_no_download <- function(env = parent.frame()) {
  httr2::local_mocked_responses(function(req) stop("this test must not download"),
                                env = env)
}
