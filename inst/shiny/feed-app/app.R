# Feed Nutrition - interactive app
#
# Run with: feed::run_feed_app()
# Or standalone: shiny::runApp(system.file("shiny", "feed-app", package = "feed"))

library(shiny)
library(DT)

# Resolve the package functions/data. When launched via feed::run_feed_app()
# the package namespace is available. When sourced directly from the repo we
# fall back to sourcing the R files.
if (requireNamespace("feed", quietly = TRUE)) {
  feed_env <- asNamespace("feed")
} else {
  candidates <- file.path(
    c(".", "..", "../..", "../../.."),
    "R"
  )
  src <- NULL
  for (d in candidates) {
    fl <- list.files(d, pattern = "[.]R$", full.names = TRUE)
    if (length(fl)) { src <- fl; break }
  }
  if (length(src)) for (fl in src) source(fl)
  data("feed.nrc.beef")
  feed_env <- globalenv()
}

f <- function(nm) get(nm, envir = feed_env)

nutrient_cols <- f("nutrient_cols")
nutrient_units <- f("nutrient_units")
to_as_fed     <- f("to_as_fed")
ingredient_load     <- f("ingredient_load")
ingredient_add      <- f("ingredient_add")
ingredient_update   <- f("ingredient_update")
ingredient_remove   <- f("ingredient_remove")
ingredient_from_reference <- f("ingredient_from_reference")
ingredient_export   <- f("ingredient_export")
ingredient_import   <- f("ingredient_import")
ingredient_catalog  <- f("ingredient_catalog")
feed_calc      <- f("feed_calc")
feed_formulate <- f("feed_formulate")
feed_suggest   <- f("feed_suggest")
reference_data <- f("feed.nrc.beef")

# Nutrient groups used across tabs
nutrient_groups <- list(
  "Básicos"  = c("DM", "CP", "TDN", "ME", "NEma", "NEga", "Fat", "Ash",
                 "Starch", "NDF", "Sugars", "Lignin"),
  "Aminoácidos" = c("ARG", "HIS", "ILE", "LEU", "LYS", "MET", "CYS",
                    "PHE", "TYR", "THR", "TRP", "VAL"),
  "Minerales" = c("Ca", "P", "Mg", "Cl", "K", "Na", "S",
                  "Co", "Cu", "I", "Fe", "Mn", "Se", "Zn"),
  "Vitaminas" = c("Vit A", "Vit D", "Vit E")
)
formulation_nutrients <- c("DM", "CP", "TDN", "ME", "Fat", "NDF", "Ca", "P")

units <- nutrient_units()

ui <- navbarPage(
  title = "Feed Nutrition",
  id = "tabs",

  # --- Ingredients --------------------------------------------------------
  tabPanel(
    "Ingredientes",
    fluidRow(
      column(
        6,
        h4("Datos de referencia (solo lectura)"),
        p("Selecciona una fila y pulsa 'Copiar a mi base' para editarla sin tocar los datos de referencia."),
        actionButton("copy_ref", "Copiar a mi base", icon = icon("copy")),
        br(), br(),
        DTOutput("ref_table")
      ),
      column(
        6,
        h4("Mi base de ingredientes (editable)"),
        p("Edita cualquier celda (precio, valores...). Los cambios se guardan automáticamente."),
        fluidRow(
          column(6, actionButton("add_ing", "Añadir nuevo", icon = icon("plus"))),
          column(6, actionButton("del_ing", "Borrar seleccionado", icon = icon("trash")))
        ),
        br(),
        fluidRow(
          column(6, downloadButton("export_csv", "Exportar CSV")),
          column(6, fileInput("import_csv", "Importar CSV", accept = ".csv"))
        ),
        br(),
        DTOutput("user_table")
      )
    )
  ),

  # --- Calculator ---------------------------------------------------------
  tabPanel(
    "Calculadora",
    sidebarLayout(
      sidebarPanel(
        h4("1. Selecciona ingredientes"),
        checkboxGroupInput("calc_ingredients", "Ingredientes",
                           choices = NULL, selected = NULL, width = "100%"),
        hr(),
        h4("2. Cantidades (kg)"),
        uiOutput("calc_amounts"),
        actionButton("calc_run", "Calcular", icon = icon("calculator"), width = "100%")
      ),
      mainPanel(
        h4("Resultado"),
        verbatimTextOutput("calc_result"),
        br(),
        h4("Aporte por nutriente (base tal cual / as-fed)"),
        DTOutput("calc_nutrients")
      )
    )
  ),

  # --- Formulation --------------------------------------------------------
  tabPanel(
    "Formulación (mínimo costo)",
    sidebarLayout(
      sidebarPanel(
        h4("1. Ingredientes disponibles"),
        checkboxGroupInput("form_ingredients", "Ingredientes",
                           choices = NULL, selected = NULL, width = "100%"),
        numericInput("form_total", "Peso total (kg)", value = 100, min = 1),
        hr(),
        h4("2. Requerimientos (deja vacío = sin límite)"),
        uiOutput("form_constraints"),
        actionButton("form_run", "Formular", icon = icon("sliders"), width = "100%")
      ),
      mainPanel(
        h4("Mezcla óptima"),
        DTOutput("form_result"),
        br(),
        verbatimTextOutput("form_summary")
      )
    )
  ),

  # --- Suggestions --------------------------------------------------------
  tabPanel(
    "Sugerencias",
    sidebarLayout(
      sidebarPanel(
        selectizeInput("sugg_ingredient", "Ingrediente de referencia",
                       choices = NULL, width = "100%"),
        checkboxGroupInput("sugg_nutrients", "Nutrientes a comparar",
                           choices = formulation_nutrients,
                           selected = c("CP", "TDN", "ME", "Ca", "P")),
        numericInput("sugg_top", "Número de sugerencias", value = 5, min = 1, max = 50),
        actionButton("sugg_run", "Sugerir", icon = icon("lightbulb"), width = "100%")
      ),
      mainPanel(
        h4("Alternativas similares (y su precio)"),
        DTOutput("sugg_result")
      )
    )
  )
)

server <- function(input, output, session) {
  # --- reactive catalogue -------------------------------------------------
  catalog_version <- reactiveVal(0)

  catalog <- reactive({
    catalog_version()
    ingredient_catalog()
  })

  observe({
    cats <- catalog()
    updateCheckboxGroupInput(session, "calc_ingredients", choices = cats$Feed)
    updateCheckboxGroupInput(session, "form_ingredients", choices = cats$Feed)
    updateSelectizeInput(session, "sugg_ingredient", choices = cats$Feed, server = TRUE)
  })

  # --- Ingredients tab ----------------------------------------------------
  ref_data <- reactive({
    reference_data[, c("Feed", "Cost", "DM", "CP", "TDN", "ME", "NDF", "Ca", "P")]
  })

  output$ref_table <- renderDT({
    datatable(ref_data(), selection = "single",
              options = list(pageLength = 10, scrollX = TRUE))
  })

  user_db <- reactiveVal(NULL)
  reload_user <- function() {
    user_db(ingredient_load())
    catalog_version(catalog_version() + 1)
  }
  reload_user()

  output$user_table <- renderDT({
    df <- user_db()
    datatable(df, selection = "single", editable = TRUE,
              options = list(pageLength = 10, scrollX = TRUE))
  })

  observeEvent(input$copy_ref, {
    req(input$ref_table_rows_selected)
    nm <- ref_data()$Feed[input$ref_table_rows_selected]
    tryCatch({
      ingredient_from_reference(nm)
      reload_user()
      showNotification(paste("Copiado:", nm), type = "message")
    }, error = function(e) showNotification(conditionMessage(e), type = "error"))
  })

  observeEvent(input$add_ing, {
    showModal(modalDialog(
      title = "Nuevo ingrediente",
      textInput("new_name", "Nombre", ""),
      numericInput("new_cost", "Precio ($/tonelada)", value = NA, min = 0),
      numericInput("new_dm", "Materia seca DM (%)", value = NA, min = 0, max = 100),
      footer = tagList(
        modalButton("Cancelar"),
        actionButton("new_save", "Guardar")
      )
    ))
  })

  observeEvent(input$new_save, {
    req(input$new_name)
    ingredient_add(input$new_name, Cost = input$new_cost, DM = input$new_dm)
    reload_user()
    removeModal()
    showNotification("Ingrediente añadido", type = "message")
  })

  observeEvent(input$del_ing, {
    req(input$user_table_rows_selected)
    id <- user_db()$id[input$user_table_rows_selected]
    ingredient_remove(id)
    reload_user()
    showNotification("Ingrediente borrado", type = "warning")
  })

  observeEvent(input$user_table_cell_edit, {
    info <- input$user_table_cell_edit
    col <- names(user_db())[info$col]
    protected <- c("id", "source", "created", "updated")
    if (col %in% protected) return()
    id <- user_db()$id[info$row]
    val <- info$value
    if (col %in% names(user_db())) {
      ingredient_update(id, stats::setNames(list(val), col))
      reload_user()
    }
  })

  output$export_csv <- downloadHandler(
    filename = function() paste0("feed-ingredients-", Sys.Date(), ".csv"),
    content = function(file) {
      df <- ingredient_load()
      write.csv(df, file, row.names = FALSE, na = "")
    }
  )

  observeEvent(input$import_csv, {
    req(input$import_csv)
    tryCatch({
      ingredient_import(input$import_csv$datapath)
      reload_user()
      showNotification("Importación completada", type = "message")
    }, error = function(e) showNotification(conditionMessage(e), type = "error"))
  })

  # --- Calculator tab -----------------------------------------------------
  output$calc_amounts <- renderUI({
    req(input$calc_ingredients)
    lapply(input$calc_ingredients, function(nm) {
      numericInput(paste0("amt_", make.names(nm)), nm, value = 0, min = 0)
    })
  })

  calc_result <- eventReactive(input$calc_run, {
    req(input$calc_ingredients)
    cats <- catalog()
    sel <- cats[cats$Feed %in% input$calc_ingredients, , drop = FALSE]
    amts <- vapply(sel$Feed, function(nm) {
      v <- input[[paste0("amt_", make.names(nm))]]
      if (is.null(v) || is.na(v)) 0 else v
    }, numeric(1))
    feed_calc(sel, amts)
  })

  output$calc_result <- renderText({
    r <- calc_result()
    if (is.null(r)) return("Pulsa 'Calcular'")
    sprintf("Peso total: %.2f kg\nCosto total: $%.2f\nCosto por kg: $%.4f",
            r$weight, r$cost, r$cost_per_kg)
  })

  output$calc_nutrients <- renderDT({
    r <- calc_result()
    if (is.null(r)) return(NULL)
    n <- r$nutrients
    df <- data.frame(Nutriente = names(n), Valor = round(n, 4), stringsAsFactors = FALSE)
    datatable(df, options = list(pageLength = 15))
  })

  # --- Formulation tab ----------------------------------------------------
  output$form_constraints <- renderUI({
    lapply(formulation_nutrients, function(nm) {
      u <- if (!is.null(units[[nm]])) units[[nm]] else ""
      fluidRow(
        column(4, tags$b(paste0(nm, if (nzchar(u)) paste0(" (", u, ")") else ""))),
        column(4, numericInput(paste0("min_", nm), "Mínimo", value = NA)),
        column(4, numericInput(paste0("max_", nm), "Máximo", value = NA))
      )
    })
  })

  form_result <- eventReactive(input$form_run, {
    req(input$form_ingredients)
    cats <- catalog()
    sel <- cats[cats$Feed %in% input$form_ingredients, , drop = FALSE]
    cons <- do.call(rbind, lapply(formulation_nutrients, function(nm) {
      data.frame(nutrient = nm,
                 min = input[[paste0("min_", nm)]],
                 max = input[[paste0("max_", nm)]],
                 stringsAsFactors = FALSE)
    }))
    cons <- cons[!is.na(cons$min) | !is.na(cons$max), , drop = FALSE]
    if (nrow(cons) == 0) stop("Define al menos un requerimiento (mínimo o máximo).")
    feed_formulate(sel, cons, total = input$form_total)
  })

  output$form_result <- renderDT({
    res <- form_result()
    if (is.null(res)) return(NULL)
    formatRound(datatable(res$solution, options = list(pageLength = 10)), "kg", 3)
  })

  output$form_summary <- renderText({
    res <- form_result()
    if (is.null(res)) return("Pulsa 'Formular'")
    if (res$status != 0) return(paste("No factible (estado LP:", res$status, "). Revisa los límites."))
    sprintf("Costo total: $%.2f\nPeso: %.2f kg\n\nNutrientes logrados:\n%s",
            res$cost, res$weight,
            paste(names(res$nutrients), "=", round(res$nutrients, 3), collapse = "\n"))
  })

  # --- Suggestions tab ----------------------------------------------------
  sugg_result <- eventReactive(input$sugg_run, {
    req(input$sugg_ingredient)
    feed_suggest(input$sugg_ingredient, catalog = catalog(),
                 nutrients = input$sugg_nutrients, top_n = input$sugg_top)
  })

  output$sugg_result <- renderDT({
    res <- sugg_result()
    if (is.null(res)) return(NULL)
    datatable(res, options = list(pageLength = 10))
  })
}

shinyApp(ui, server)
