#' feed.info
#'
#' This function show the result of tables of URL.
#' @param url A URL that you want to scraping.
#' @keywords feed, feedipedia
#' @export
#' @import rvest
#' @import dplyr
#' @examples
#' feed.info("https://www.feedipedia.org/node/556")

feed.info <- function(url){
  html <- read_html(url, encoding="UTF-8")

  #names
  h1 <- html %>% html_nodes("h1") %>% html_text()
  h2 <- html %>% html_nodes("h2") %>% html_text()
  h3 <- html %>% html_nodes("h3") %>% html_text()

  #nutrients
  list <- html %>% html_nodes("table") %>% html_table()

  print(h1)
  print(h2)
  print(h3)
  print(list[1:ifelse(length(list)-1==0,1,length(list)-1)])
}
