#' feed.list
#'
#' This function showed a feed list at feedipedia.org.
#' @param category A category that you want to find(all; forage; plantProduct; animalOrigin; other)
#' @keywords feed, feedipedia
#' @import rvest
#' @import dplyr
#' @export
#' @examples
#' feed.list(all)
#' feed.list(forage)
#' feed.list(plantProduct)
#' feed.list(animalOrigin)
#' feed.list(other)

feed.list <- function(category="https://www.feedipedia.org/content/feeds?category=All") {
  # subsetting
  assign("all","https://www.feedipedia.org/content/feeds?category=All",envir = globalenv())
  assign("forage","https://www.feedipedia.org/content/feeds?category=15965",envir = globalenv())
  assign("other","https://www.feedipedia.org/content/feeds?category=15969",envir = globalenv())
  assign("plantProduct","https://www.feedipedia.org/content/feeds?category=15967",envir = globalenv())
  assign("animalOrigin","https://www.feedipedia.org/content/feeds?category=15968",envir = globalenv())

  url <- category
  # url <- paste0("https://www.feedipedia.org/content/feeds?category=All")
  result <- read_html(url, encoding="UTF-8") %>%
    html_nodes("table") %>%
    html_table() # search results

  # return
  return(result)
}
