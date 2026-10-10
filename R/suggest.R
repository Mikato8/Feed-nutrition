# Product suggestions ------------------------------------------------------

#' @title Suggest similar or cheaper ingredients
#' @description Rank other ingredients by how similar they are to a target
#'   ingredient on a set of nutrients, and report their price so the user can
#'   spot cheaper alternatives.
#' @param ingredient Name of the target ingredient (must be in `catalog`).
#' @param catalog A combined catalogue from `ingredient_catalog()`.
#' @param nutrients Nutrient columns used for the similarity comparison.
#' @param top_n Number of suggestions to return.
#' @param as_fed Logical; compare nutrients on an as-fed basis.
#' @return A data frame of suggested ingredients ordered by similarity, with
#'   the target's price and each suggestion's price and relative cost.
#' @export
feed_suggest <- function(ingredient, catalog = ingredient_catalog(),
                         nutrients = c("CP", "TDN", "ME", "Fat", "NDF", "Ca", "P"),
                         top_n = 5, as_fed = TRUE) {
  cat <- catalog
  if (isTRUE(as_fed)) cat <- to_as_fed(cat)
  i <- which(tolower(cat$Feed) == tolower(ingredient))
  if (length(i) == 0) i <- grep(ingredient, cat$Feed, ignore.case = TRUE)
  if (length(i) == 0) stop("Ingredient not found in catalog: ", ingredient)

  target <- cat[i[1], , drop = FALSE]
  nutrients <- intersect(nutrients, names(cat))
  if (length(nutrients) == 0) stop("None of the requested nutrients are available.")

  mat <- as.matrix(cat[, nutrients, drop = FALSE])
  mode(mat) <- "numeric"

  sd_vec <- apply(mat, 2, stats::sd, na.rm = TRUE)
  sd_vec[sd_vec == 0 | is.na(sd_vec)] <- 1
  sc <- sweep(mat, 2, sd_vec, "/")

  tvec <- sc[i[1], ]
  d <- sqrt(rowSums((sweep(sc, 2, tvec, "-"))^2, na.rm = TRUE))

  out <- data.frame(
    Feed = cat$Feed,
    source = cat$source,
    Cost = as.numeric(cat$Cost),
    distance = round(d, 3),
    stringsAsFactors = FALSE
  )
  out <- out[-i[1], , drop = FALSE]
  out <- out[order(out$distance), , drop = FALSE]
  out <- utils::head(out, top_n)
  out$cheaper <- !is.na(out$Cost) & out$Cost < as.numeric(target$Cost)
  rownames(out) <- NULL
  out
}
