library(shiny)
#devtools::install_github("tidyverse/googlesheets4", force = TRUE)
library(googlesheets4)

gs4_auth(email = "eshpm.serious.game@gmail.com")

table <- "responses"
g_sheet <- "1VgbqTeaP0L8h0WL-PMcGU9l7kWs2e1BVVYyeJmaEPlE"
#options(gargle_oauth_cache = "eshpm.serious.game@gmail.com")


saveData <- function(data) {
  # The data must be a dataframe rather than a named vector
  #data <- data %>% as.list() %>% data.frame()
  # Add the data as a new row
  sheet_append(g_sheet, data)
}

loadData <- function() {
  # Read the data
  read_sheet(ss = g_sheet, sheet = "responses")
}



# Define the fields we want to save from the form
fields <- c("name", "used_shiny", "r_num_years")

# Shiny app with 3 fields that the user can submit data for
shinyApp(
  ui = fluidPage(
    DT::dataTableOutput("responses", width = 300), tags$hr(),
    radioButtons("wg", "Work group number", choices = list("Group 1" = "1",
                                                           "Group 2" = "2")),
    radioButtons("gr", "Group number", choices = list("Group A" = "A",
                                                           "Group B" = "B")),
    radioButtons("round", "Round number", choices = list("Round 1" = 1,
                                                      "Round 2" = 2)),
    numericInput("n1", "Number of patients in tier 1", 0),
    numericInput("p1", "Price per patient in tier 1", 0),
    numericInput("n2", "Number of patients in tier 2", 0),
    numericInput("p2", "Price per patient in tier 2", 0),
    numericInput("n3", "Number of patients in tier 3", 0),
    numericInput("p3", "Price per patient in tier 3", 0),
    actionButton("submit", "Submit")
  ),
  server = function(input, output, session) {
    
    # Whenever a field is filled, aggregate all form data
    formData <- reactive({
      data <- data.frame(wg = input$wg,
                         gr = input$gr,
                         round = input$round,
                         n1 = input$n1,
                         p1 = input$p1,
                         n2 = input$n2,
                         p2 = input$p2,
                         n3 = input$n3,
                         p3 = input$p3,
                         time = Sys.time())
      data
    })
    
    # When the Submit button is clicked, save the form data
    observeEvent(input$submit, {
      saveData(formData())
    })
    
    # Show the previous responses
    # (update with current response when Submit is clicked)
    output$responses <- DT::renderDataTable({
      input$submit
      loadData()
    })     
  }
)