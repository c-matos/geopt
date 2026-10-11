#' @keywords internal
"_PACKAGE"

# The .data pronoun used in ggplot2::aes() calls is resolved by the data
# mask at plot time; declare it so R CMD check does not flag it.
utils::globalVariables(".data")
