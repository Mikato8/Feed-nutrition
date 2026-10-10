# Internal helpers ---------------------------------------------------------

utils::globalVariables("feed.nrc.beef")

# Nutrient columns of the reference dataset (everything except identifiers).
# These are the columns a user can create/edit for their own ingredients.

#' @title Nutrient columns available in the reference dataset
#' @return A character vector of nutrient column names.
#' @export
nutrient_cols <- function() {
  setdiff(names(feed.nrc.beef), c("Feed", "IFN"))
}

# Named vector of units for every column of feed.nrc.beef, e.g.
# c(Cost = "$/Tonne AF", CP = "%DM", Ca = "% DM", ...).

#' @title Units of the reference dataset columns
#' @return A named character vector mapping column names to their units.
#' @export
nutrient_units <- function() {
  u <- attr(feed.nrc.beef, "unit")
  if (is.null(u)) return(character(0))
  u <- unlist(u)
  stats::setNames(as.character(u), names(u))
}

# Build an empty ingredients data frame with the same nutrient schema as the
# reference data plus editable metadata columns.
ingredient_skeleton <- function() {
  n <- nutrient_cols()
  cols <- c(
    list(
      id = character(),
      Feed = character(),
      IFN = character(),
      source = character(),
      created = character(),
      updated = character(),
      notes = character()
    ),
    stats::setNames(rep(list(numeric()), length(n)), n)
  )
  as.data.frame(cols, stringsAsFactors = FALSE, check.names = FALSE)
}

.new_id <- function() {
  paste0("u", as.integer(Sys.time()), sample.int(1e6, 1))
}

.now <- function() {
  format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")
}

# Location of the user ingredients CSV. Overridable via
# options(feed.db = "...") or the FEED_DB environment variable.
ingredient_path <- function() {
  p <- getOption("feed.db", NULL)
  if (is.null(p) || !nzchar(p)) p <- Sys.getenv("FEED_DB", unset = "")
  if (!nzchar(p)) p <- file.path(path.expand("~"), ".feed", "ingredients.csv")
  p
}

# User-facing database API ------------------------------------------------

#' @title Create an empty ingredients database
#' @description Initialise the CSV that stores the user's own (editable)
#'   ingredients. Reference data (`feed.nrc.beef`) is never touched.
#' @param path Path to the ingredients CSV. Defaults to `ingredient_path()`.
#' @param overwrite Logical; recreate the file even if it already exists.
#' @return The path (invisibly).
#' @export
ingredient_init <- function(path = ingredient_path(), overwrite = FALSE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (overwrite || !file.exists(path)) {
    utils::write.csv(ingredient_skeleton(), path, row.names = FALSE, na = "")
  }
  invisible(path)
}

#' @title Load the user ingredients database
#' @param path Path to the ingredients CSV.
#' @return A data frame of user ingredients (0 rows if empty).
#' @export
ingredient_load <- function(path = ingredient_path()) {
  ingredient_init(path)
  df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  for (cc in intersect(nutrient_cols(), names(df))) df[[cc]] <- as.numeric(df[[cc]])
  df
}

.ingredient_save <- function(df, path = ingredient_path()) {
  ingredient_init(path)
  utils::write.csv(df, path, row.names = FALSE, na = "")
  invisible(df)
}

#' @title Add a new ingredient
#' @param feed Ingredient name.
#' @param ... Named nutrient values (e.g. `CP = 12`, `Cost = 300`).
#' @param path Path to the ingredients CSV.
#' @return The updated database (invisibly).
#' @export
ingredient_add <- function(feed, ..., path = ingredient_path()) {
  values <- list(...)
  df <- ingredient_load(path)
  row <- ingredient_skeleton()[1, , drop = FALSE]
  row$id <- .new_id()
  row$Feed <- as.character(feed)
  row$source <- "user"
  row$created <- .now()
  row$updated <- .now()
  for (nm in names(values)) {
    if (nm %in% names(row)) row[[nm]] <- values[[nm]]
  }
  df <- rbind(df, row)
  .ingredient_save(df, path)
}

#' @title Edit an ingredient's values
#' @param id Ingredient id (from `ingredient_load`).
#' @param ... Named nutrient values to change.
#' @param path Path to the ingredients CSV.
#' @return The updated database (invisibly).
#' @export
ingredient_update <- function(id, ..., path = ingredient_path()) {
  values <- list(...)
  df <- ingredient_load(path)
  i <- which(df$id == id)
  if (length(i) == 0) stop("Ingredient id not found: ", id)
  for (nm in names(values)) {
    if (nm %in% names(df)) df[[nm]][i] <- values[[nm]]
  }
  df$updated[i] <- .now()
  .ingredient_save(df, path)
}

#' @title Remove an ingredient
#' @param id Ingredient id to delete.
#' @param path Path to the ingredients CSV.
#' @return The updated database (invisibly).
#' @export
ingredient_remove <- function(id, path = ingredient_path()) {
  df <- ingredient_load(path)
  df <- df[df$id != id, , drop = FALSE]
  .ingredient_save(df, path)
}

#' @title Copy a reference feed into the editable database
#' @description Copy a row of `feed.nrc.beef` into the user database so it can
#'   be edited (price, values, ...) without changing the reference data.
#' @param name Feed name (exact or partial match) from `feed.nrc.beef`.
#' @param path Path to the ingredients CSV.
#' @return The updated database (invisibly).
#' @export
ingredient_from_reference <- function(name, path = ingredient_path()) {
  i <- which(tolower(feed.nrc.beef$Feed) == tolower(name))
  if (length(i) == 0) i <- grep(name, feed.nrc.beef$Feed, ignore.case = TRUE)
  if (length(i) == 0) stop("Feed not found in reference data: ", name)
  ref <- feed.nrc.beef[i[1], , drop = FALSE]
  df <- ingredient_load(path)
  row <- ingredient_skeleton()[1, , drop = FALSE]
  row$id <- .new_id()
  row$Feed <- as.character(ref$Feed)
  row$IFN <- as.character(ref$IFN)
  row$source <- "reference"
  row$created <- .now()
  row$updated <- .now()
  row$notes <- paste("Copied from NRC beef reference:", as.character(ref$Feed))
  for (nm in intersect(names(row), names(ref))) row[[nm]] <- ref[[nm]]
  df <- rbind(df, row)
  .ingredient_save(df, path)
}

#' @title Export the user ingredients database
#' @param path Path to the ingredients CSV.
#' @param file Destination CSV file.
#' @return The destination file path (invisibly).
#' @export
ingredient_export <- function(path = ingredient_path(), file = "feed-ingredients.csv") {
  df <- ingredient_load(path)
  utils::write.csv(df, file, row.names = FALSE, na = "")
  invisible(file)
}

#' @title Import ingredients from a CSV
#' @description Merge ingredients exported with `ingredient_export` into the
#'   database. Rows whose id already exists are skipped unless `replace = TRUE`.
#' @param file Source CSV file.
#' @param path Path to the ingredients CSV.
#' @param replace Logical; replace the whole database with the file contents.
#' @return The updated database (invisibly).
#' @export
ingredient_import <- function(file, path = ingredient_path(), replace = FALSE) {
  new <- utils::read.csv(file, stringsAsFactors = FALSE, check.names = FALSE)
  for (cc in intersect(nutrient_cols(), names(new))) new[[cc]] <- as.numeric(new[[cc]])
  if (replace) {
    df <- new
  } else {
    df <- ingredient_load(path)
    keep <- !(new$id %in% df$id)
    df <- rbind(df, new[keep, , drop = FALSE])
  }
  .ingredient_save(df, path)
}

#' @title Combined catalogue of reference and user ingredients
#' @description Returns a single data frame with both the read-only reference
#'   feeds (`source = "reference"`) and the editable user feeds
#'   (`source = "user"` / `source = "reference"` copied rows are still editable
#'   because they live in the user database).
#' @param path Path to the ingredients CSV.
#' @return A data frame.
#' @export
ingredient_catalog <- function(path = ingredient_path()) {
  ref <- feed.nrc.beef
  ref <- data.frame(
    id = paste0("ref-", seq_len(nrow(ref))),
    Feed = ref$Feed,
    IFN = as.character(ref$IFN),
    source = "reference",
    created = "",
    updated = "",
    notes = "",
    ref[, nutrient_cols(), drop = FALSE],
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  user <- ingredient_load(path)
  # User copies take precedence over reference feeds with the same name.
  ref <- ref[!tolower(ref$Feed) %in% tolower(user$Feed), , drop = FALSE]
  cols <- intersect(names(ref), names(user))
  ref <- ref[, cols, drop = FALSE]
  user <- user[, cols, drop = FALSE]
  rbind(ref, user)
}
