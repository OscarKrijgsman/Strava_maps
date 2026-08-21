library(shiny)
library(bslib)
library(leaflet)
library(leaflet.extras)
library(sf)
library(dplyr)
library(lubridate)
library(plotly)

source("R/helpers.R")

runs_sf <- readRDS("../cache/runs_sf.rds")
heatmap_points <- readRDS("../cache/heatmap_points.rds")

data_min_date <- as.Date(min(runs_sf$date))
data_max_date <- as.Date(max(runs_sf$date))
bbox <- st_bbox(runs_sf)

ui <- page_sidebar(
  title = "My Runs",
  sidebar = sidebar(
    width = 300,
    dateRangeInput(
      "date_range", "Date range",
      start = data_min_date, end = data_max_date,
      min = data_min_date, max = data_max_date
    ),
    actionButton("preset_all", "All time", class = "btn-sm w-100 mb-1"),
    actionButton("preset_year", "This year", class = "btn-sm w-100 mb-1"),
    actionButton("preset_12mo", "Last 12 months", class = "btn-sm w-100 mb-3"),
    radioButtons(
      "map_layer", "Map layer",
      choices = c("Heatmap" = "heatmap", "Routes" = "routes", "Both" = "both"),
      selected = "heatmap"
    )
  ),
  layout_columns(
    col_widths = 3,
    value_box(title = "Runs", value = textOutput("stat_count"), showcase = bsicons::bs_icon("flag")),
    value_box(title = "Distance", value = textOutput("stat_distance"), showcase = bsicons::bs_icon("rulers")),
    value_box(title = "Moving time", value = textOutput("stat_time"), showcase = bsicons::bs_icon("clock")),
    value_box(title = "Avg pace", value = textOutput("stat_pace"), showcase = bsicons::bs_icon("speedometer2"))
  ),
  layout_columns(
    col_widths = c(8, 4),
    card(full_screen = TRUE, card_header("Map"), leafletOutput("map", height = "600px")),
    card(card_header("Monthly distance"), plotlyOutput("mileage_chart", height = "600px"))
  )
)

server <- function(input, output, session) {

  observeEvent(input$preset_all, {
    updateDateRangeInput(session, "date_range", start = data_min_date, end = data_max_date)
  })
  observeEvent(input$preset_year, {
    updateDateRangeInput(session, "date_range", start = floor_date(data_max_date, "year"), end = data_max_date)
  })
  observeEvent(input$preset_12mo, {
    updateDateRangeInput(session, "date_range", start = data_max_date - 365, end = data_max_date)
  })

  filtered_runs <- reactive({
    req(input$date_range)
    runs_sf %>%
      filter(as.Date(date) >= input$date_range[1], as.Date(date) <= input$date_range[2])
  })

  filtered_points <- reactive({
    ids <- filtered_runs()$activity_id
    heatmap_points %>% filter(activity_id %in% ids)
  })

  output$stat_count <- renderText({ nrow(filtered_runs()) })
  output$stat_distance <- renderText({ sprintf("%.0f km", sum(filtered_runs()$distance_km, na.rm = TRUE)) })
  output$stat_time <- renderText({ format_duration(sum(filtered_runs()$moving_time_min, na.rm = TRUE)) })
  output$stat_pace <- renderText({
    fr <- filtered_runs()
    total_km <- sum(fr$distance_km, na.rm = TRUE)
    total_min <- sum(fr$moving_time_min, na.rm = TRUE)
    format_pace(if (total_km > 0) total_min / total_km else NA_real_)
  })

  output$map <- renderLeaflet({
    leaflet() %>%
      addProviderTiles(providers$CartoDB.Positron) %>%
      fitBounds(bbox[["xmin"]], bbox[["ymin"]], bbox[["xmax"]], bbox[["ymax"]])
  })

  observe({
    proxy <- leafletProxy("map") %>% clearGroup("heatmap") %>% clearGroup("routes")

    if (input$map_layer %in% c("heatmap", "both")) {
      pts <- filtered_points()
      if (nrow(pts) > 0) {
        proxy <- proxy %>%
          addHeatmap(
            data = pts, lng = ~lon, lat = ~lat,
            group = "heatmap", radius = 10, blur = 15, max = 0.05
          )
      }
    }

    if (input$map_layer %in% c("routes", "both")) {
      fr <- filtered_runs()
      if (nrow(fr) > 0) {
        proxy <- proxy %>%
          addPolylines(data = fr, color = "#fc4c02", weight = 2, opacity = 0.5, group = "routes")
      }
    }
  })

  output$mileage_chart <- renderPlotly({
    monthly <- filtered_runs() %>%
      st_drop_geometry() %>%
      group_by(month) %>%
      summarise(distance_km = sum(distance_km, na.rm = TRUE), .groups = "drop")

    plot_ly(monthly, x = ~month, y = ~distance_km, type = "bar", marker = list(color = "#fc4c02")) %>%
      layout(xaxis = list(title = ""), yaxis = list(title = "km"))
  })
}

shinyApp(ui, server)
