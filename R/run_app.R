#' @title Launch the Feed Nutrition Shiny app
#' @description Starts the interactive app for managing ingredients, running the
#'   nutrition calculator, least-cost formulation and product suggestions.
#' @param ... Arguments passed to `shiny::runApp`.
#' @export
run_feed_app <- function(...) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("Package 'shiny' is required. Install it with install.packages(\"shiny\").")
  }
  app_dir <- system.file("shiny", "feed-app", package = "feed")
  if (!nzchar(app_dir)) stop("Shiny app not found; reinstall the package.")
  shiny::runApp(app_dir, ...)
}
