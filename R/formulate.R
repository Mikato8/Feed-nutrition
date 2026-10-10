# Conversion helpers -------------------------------------------------------

# Nutrients stored on a dry-matter basis ("%DM" or "% DM") are converted to an
# as-fed basis using the ingredient's dry matter. Everything else (already
# as-fed: $/Tonne, Mcal/kg, mg/kg, IU, and ratios like "%CP" or "%NDF") is
# left unchanged. "Forage" is a classification flag and is never converted.

#' @title Convert dry-matter nutrient values to an as-fed basis
#' @param df A data frame of ingredients with a `DM` column and nutrient columns.
#' @return The data frame with dry-matter-basis nutrients converted to as-fed.
#' @export
to_as_fed <- function(df) {
  u <- nutrient_units()
  dm <- if ("DM" %in% names(df)) df$DM else NA_real_
  skip <- c("Feed", "IFN", "Cost", "Forage", "DM")
  for (nm in intersect(names(df), names(u))) {
    if (nm %in% skip) next
    if (is.na(u[[nm]]) || length(u[[nm]]) == 0) next
    if (u[[nm]] %in% c("%DM", "% DM")) {
      df[[nm]] <- df[[nm]] * dm / 100
    }
  }
  df
}

# Nutrition calculator -----------------------------------------------------

#' @title Nutrition calculator
#' @description Given a set of ingredients and their amounts (kg as-fed),
#'   compute total weight, total cost and the weighted average of every
#'   nutrient. Nutrient values are reported on an as-fed basis.
#' @param ingredients A data frame with a `Feed` column, a `Cost` column
#'   (currency per tonne) and nutrient columns.
#' @param amounts Numeric vector of amounts (kg) matching `ingredients` rows.
#' @param as_fed Logical; convert dry-matter nutrient values to as-fed first.
#' @return A list with `weight`, `cost`, `cost_per_kg` and `nutrients`
#'   (a named numeric vector of weighted averages).
#' @export
feed_calc <- function(ingredients, amounts, as_fed = TRUE) {
  ing <- ingredients
  if (isTRUE(as_fed)) ing <- to_as_fed(ing)
  w <- as.numeric(amounts)
  if (length(w) != nrow(ing)) stop("length(amounts) must equal nrow(ingredients)")
  total_w <- sum(w, na.rm = TRUE)
  n <- setdiff(intersect(nutrient_cols(), names(ing)), c("Cost", "Forage"))
  weighted <- vapply(n, function(nm) {
    v <- as.numeric(ing[[nm]])
    if (all(is.na(v))) return(NA_real_)
    sum(w * v, na.rm = TRUE) / total_w
  }, numeric(1))
  cost_total <- if ("Cost" %in% names(ing)) {
    sum(w * as.numeric(ing$Cost) / 1000, na.rm = TRUE)
  } else {
    NA_real_
  }
  list(
    weight = total_w,
    cost = cost_total,
    cost_per_kg = if (is.na(cost_total)) NA_real_ else cost_total / total_w,
    nutrients = weighted
  )
}

# Least-cost formulation ---------------------------------------------------

#' @title Least-cost feed formulation
#' @description Solve the least-cost mix of ingredients (kg as-fed) that meets
#'   nutrient targets, using linear programming (`lpSolve`).
#' @param ingredients A data frame with `Feed`, `Cost` (currency per tonne) and
#'   nutrient columns. Optional numeric columns `min_inc` / `max_inc` bound each
#'   ingredient's inclusion (kg).
#' @param constraints A data frame with columns `nutrient`, `min` and `max`
#'   (use `NA` to leave a side unconstrained).
#' @param total Total batch weight (kg as-fed).
#' @param as_fed Logical; convert dry-matter nutrient values to as-fed first.
#' @return A list with `solution` (a data frame of ingredient amounts),
#'   `status` (LP status), `cost`, `nutrients` (achieved values) and
#'   `objective` (cost per batch).
#' @export
feed_formulate <- function(ingredients, constraints, total = 100, as_fed = TRUE) {
  if (!requireNamespace("lpSolve", quietly = TRUE)) {
    stop("Package 'lpSolve' is required. Install it with install.packages(\"lpSolve\").")
  }
  ing <- ingredients
  if (isTRUE(as_fed)) ing <- to_as_fed(ing)

  n <- nrow(ing)
  cost_kg <- ifelse(is.na(ing$Cost), 0, ing$Cost) / 1000

  const_mat <- matrix(0, nrow = 0, ncol = n)
  const_dir <- character(0)
  const_rhs <- numeric(0)

  add_row <- function(row, dir, rhs) {
    const_mat <<- rbind(const_mat, row)
    const_dir <<- c(const_dir, dir)
    const_rhs <<- c(const_rhs, rhs)
  }

  add_row(rep(1, n), "=", total)

  nutrient_rows <- intersect(constraints$nutrient, names(ing))
  for (nm in nutrient_rows) {
    cc <- constraints[constraints$nutrient == nm, , drop = FALSE]
    vals <- as.numeric(ing[[nm]])
    vals[is.na(vals)] <- 0
    if (!is.na(cc$min[1])) add_row(vals, ">=", cc$min[1] * total)
    if (!is.na(cc$max[1])) add_row(vals, "<=", cc$max[1] * total)
  }

  if ("min_inc" %in% names(ing)) {
    for (i in seq_len(n)) {
      if (!is.na(ing$min_inc[i])) {
        row <- rep(0, n); row[i] <- 1
        add_row(row, ">=", ing$min_inc[i])
      }
    }
  }
  if ("max_inc" %in% names(ing)) {
    for (i in seq_len(n)) {
      if (!is.na(ing$max_inc[i])) {
        row <- rep(0, n); row[i] <- 1
        add_row(row, "<=", ing$max_inc[i])
      }
    }
  }

  sol <- lpSolve::lp(
    direction = "min",
    objective.in = cost_kg,
    const.mat = const_mat,
    const.dir = const_dir,
    const.rhs = const_rhs
  )

  x <- sol$solution
  names(x) <- ing$Feed
  achieved <- feed_calc(ing, x, as_fed = FALSE)

  list(
    solution = data.frame(Feed = ing$Feed, kg = x, stringsAsFactors = FALSE),
    status = sol$status,
    objective = sol$objval,
    cost = achieved$cost,
    weight = achieved$weight,
    nutrients = achieved$nutrients
  )
}
