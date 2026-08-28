library(shiny)

source("config.R", local = TRUE)
source(file.path("R", "i18n.R"), local = TRUE)
source(file.path("R", "storage.R"), local = TRUE)
source(file.path("R", "scoring.R"), local = TRUE)

store <- create_game_store(game_config)
staff_pin <- Sys.getenv("STAFF_PIN", unset = "demo")
using_demo_pin <- identical(staff_pin, "demo")

`%||%` <- function(value, fallback) if (is.null(value)) fallback else value

safe_language <- function(value) if (value %in% c("en", "nl")) value else "en"
safe_theme <- function(value) if (value %in% c("light", "dark")) value else "light"

format_euro <- function(value, language = "en") {
  mark <- if (language == "nl") "." else ","
  decimal <- if (language == "nl") "," else "."
  paste0("EUR ", format(round(value), big.mark = mark, decimal.mark = decimal, scientific = FALSE))
}

format_live_time <- function(value, language = "en") {
  if (language == "nl") format(value, "%d-%m-%Y, %H:%M") else format(value, "%d %B %Y, %H:%M")
}

bullet_list <- function(items) {
  if (length(items) == 0) return(NULL)
  tags$ul(class = "content-list", lapply(items, tags$li))
}

new_player_id <- function() {
  paste0(
    format(Sys.time(), "%Y%m%d%H%M%OS3"), "-",
    paste(sample(c(letters, 0:9), 8, replace = TRUE), collapse = "")
  )
}

brand_mark <- function(language = "en") {
  div(
    class = "eshpm-brand",
    tags$img(class = "eshpm-logo", src = "eshpm-logo.png", alt = tr("school_name", language)),
    div(class = "brand-divider"),
    div(
      class = "game-wordmark",
      tags$span("ESHPM"),
      tags$strong(tr("app_title", language))
    )
  )
}

main_ui <- fluidPage(
  class = "app-page",
  tags$head(
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    tags$title("ESHPM · HTA negotiation game"),
    tags$link(rel = "stylesheet", type = "text/css", href = "styles.css"),
    tags$script(src = "app.js", defer = NA)
  ),
  uiOutput("app_header"),
  tags$main(class = "app-shell", uiOutput("app_body"))
)

results_presentation_ui <- function(language = "en", theme = "light") {
  language <- safe_language(language)
  theme <- safe_theme(theme)

  fluidPage(
    class = "presentation-page",
    `data-theme` = theme,
    `data-language` = language,
    tags$head(
      tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
      tags$title(paste(tr("app_title", language), tr("results_reflection", language), sep = " · ")),
      tags$link(rel = "stylesheet", type = "text/css", href = "presentation.css"),
      tags$script(src = "presentation.js", defer = NA)
    ),
    if (!store$is_results_published()) {
      div(
        class = "presentation-unavailable rainbow-frame",
        brand_mark(language),
        h1(tr("presentation_unavailable", language)),
        p(tr("presentation_unavailable_text", language)),
        tags$a(class = "presentation-link", href = "./", tr("return_game", language))
      )
    } else {
      tagList(
        tags$img(class = "deck-corner-logo", src = "eshpm-logo.png", alt = tr("school_name", language)),
        tags$main(
          id = "results-deck",
          class = "results-deck",
          tags$section(
            class = "result-slide title-slide",
            div(
              class = "slide-accent rainbow-orbit",
              div(
              class = "slide-content",
                tags$span(class = "eyebrow", tr("course_team", language)),
                h1(tr("app_title", language)),
                h2(tr("results_reflection", language)),
                uiOutput("presentation_summary")
              )
            )
          ),
          tags$section(
            class = "result-slide",
            div(
              class = "slide-content",
              tags$span(class = "eyebrow", tr("debrief", language)),
              h1(tr("share_experience", language)),
              tags$ul(
                class = "reflection-list",
                tags$li(tr("reflection_1", language)),
                tags$li(tr("reflection_2", language)),
                tags$li(tr("reflection_3", language)),
                tags$li(tr("reflection_4", language))
              )
            )
          ),
          tags$section(class = "result-slide", div(class = "slide-content", tags$span(class = "eyebrow", tr("results_n", language, 1)), h1(tr("overspent_budget", language)), div(class = "result-table-frame rainbow-frame", tableOutput("presentation_overspent")))),
          tags$section(class = "result-slide", div(class = "slide-content", tags$span(class = "eyebrow", tr("results_n", language, 2)), h1(tr("crowding_out", language)), div(class = "result-table-frame rainbow-frame", tableOutput("presentation_crowding_out")))),
          tags$section(class = "result-slide", div(class = "slide-content", tags$span(class = "eyebrow", tr("results_n", language, 3)), h1(tr("untreated_patients", language)), div(class = "result-table-frame rainbow-frame", tableOutput("presentation_untreated")))),
          tags$section(class = "result-slide", div(class = "slide-content", tags$span(class = "eyebrow", tr("results_n", language, 4)), h1(tr("average_price", language)), div(class = "result-table-frame rainbow-frame", tableOutput("presentation_average_price")))),
          tags$section(class = "result-slide", div(class = "slide-content wide-slide", tags$span(class = "eyebrow", tr("results_n", language, 5)), h1(tr("points_group_round", language)), div(class = "result-table-frame rainbow-frame", tableOutput("presentation_scores")))),
          tags$section(
            class = "result-slide closing-slide",
            div(
              class = "slide-accent rainbow-orbit",
              div(
                class = "slide-content",
                tags$span(class = "eyebrow", tr("closing_discussion", language)),
                h1(tr("changed_strategy", language)),
                p(tr("compare_rounds", language)),
                h2(tr("real_negotiation", language))
              )
            )
          )
        ),
        div(
          class = "presentation-controls rainbow-frame",
          actionButton("previous_slide", tr("previous", language), class = "presentation-button"),
          tags$span(id = "slide-counter", "1 / 8"),
          actionButton("next_slide", tr("next", language), class = "presentation-button")
        )
      )
    }
  )
}

ui <- function(request) {
  query <- shiny::parseQueryString(request$QUERY_STRING %||% "")
  if (identical(query$view, "results")) {
    results_presentation_ui(query$lang %||% "en", query$theme %||% "light")
  } else {
    main_ui
  }
}

server <- function(input, output, session) {
  player <- reactiveValues(joined = FALSE, id = NULL, tutor = NULL, group = NULL, role = NULL)
  staff_authenticated <- reactiveVal(FALSE)
  active_view <- reactiveVal("play")
  language <- reactiveVal("en")
  theme <- reactiveVal("light")
  pending_agreement <- reactiveVal(NULL)

  observeEvent(session$clientData$url_search, {
    query <- shiny::parseQueryString(session$clientData$url_search %||% "")
    language(safe_language(query$lang %||% language()))
    theme(safe_theme(query$theme %||% theme()))
  }, once = TRUE, ignoreInit = FALSE)

  observe({
    session$sendCustomMessage("set-preferences", list(language = language(), theme = theme()))
  })

  t <- function(key, ...) tr(key, language(), ...)
  role_label <- function(role) unname(game_config$roles[[language()]][[role]])
  round_title <- function(round_config) round_config$title[[language()]]
  round_summary <- function(round_config) round_config$public_summary[[language()]]
  round_confidential <- function(round_config, role) round_config$confidential[[language()]][[role]]
  euro <- function(value) format_euro(value, language())

  observe({
    invalidateLater(game_config$poll_interval_ms, session)
    try(store$refresh(), silent = TRUE)
  })

  observeEvent(input$nav_play, active_view("play"))
  observeEvent(input$nav_staff, active_view("staff"))
  observeEvent(input$language_en, language("en"))
  observeEvent(input$language_nl, language("nl"))
  observeEvent(input$theme_toggle, theme(if (theme() == "light") "dark" else "light"))

  output$app_header <- renderUI({
    tags$header(
      class = "app-header",
      div(
        class = "header-inner",
        brand_mark(language()),
        div(
          class = "preference-controls",
          div(
            class = "segmented-control",
            `aria-label` = t("language"),
            actionButton("language_en", "EN", class = paste("segment-button", if (language() == "en") "active")),
            actionButton("language_nl", "NL", class = paste("segment-button", if (language() == "nl") "active"))
          ),
          actionButton(
            "theme_toggle",
            if (theme() == "light") paste("◐", t("dark_mode")) else paste("☀", t("light_mode")),
            class = "theme-button"
          )
        )
      ),
      tags$nav(
        class = "app-navigation",
        div(
          class = "header-inner nav-inner",
          actionButton("nav_play", t("play"), class = paste("nav-button", if (active_view() == "play") "active")),
          actionButton("nav_staff", t("staff"), class = paste("nav-button", if (active_view() == "staff") "active")),
          tags$span(class = "header-tagline", t("school_tagline"))
        )
      )
    )
  })

  output$app_body <- renderUI({
    if (active_view() == "staff") uiOutput("staff_screen") else uiOutput("player_screen")
  })

  current_group_state <- reactive({
    req(player$joined)
    store$state_revision()
    state <- store$get_state()
    state[state$tutor == player$tutor & state$group == player$group, , drop = FALSE]
  })

  selected_tutors <- reactive({
    req(input$staff_tutor)
    if (input$staff_tutor == "__all__") game_config$tutors else input$staff_tutor
  })

  selected_groups <- reactive({
    req(input$staff_group)
    if (input$staff_group == "__all__") game_config$groups else input$staff_group
  })

  live_results <- reactive({
    store$data_revision()
    calculate_scores(store$get_agreements(), game_config$rounds)
  })

  output$player_screen <- renderUI({
    if (!player$joined) {
      return(div(
        class = "hero-grid",
        div(
          class = "hero-copy",
          tags$span(class = "eyebrow", t("school_name")),
          h1(t("join_title")),
          p(class = "hero-lead", t("join_intro")),
          div(class = "hero-shape shape-one"),
          div(class = "hero-shape shape-two")
        ),
        div(
          class = "game-card join-card rainbow-frame",
          selectInput("player_tutor", t("tutor"), choices = game_config$tutors),
          selectInput("player_group", t("negotiation_group"), choices = game_config$groups),
          radioButtons(
            "player_role",
            t("role"),
            choices = stats::setNames(names(game_config$roles[[language()]]), unname(game_config$roles[[language()]])),
            selected = character()
          ),
          actionButton("join_game", t("join_game"), class = "btn-primary btn-lg btn-block")
        )
      ))
    }

    div(
      div(
        class = "player-header game-card",
        div(
          tags$span(class = "eyebrow", t("negotiation_group")),
          h2(paste(player$tutor, "·", t("group"), player$group)),
          tags$span(class = "role-badge", role_label(player$role))
        ),
        actionButton("leave_game", t("change_assignment"), class = "btn-quiet")
      ),
      uiOutput("round_panel")
    )
  })

  observeEvent(input$join_game, {
    if (is.null(input$player_role) || !input$player_role %in% c("HCP", "HTD")) {
      showNotification(t("select_role"), type = "error")
      return()
    }

    player$joined <- TRUE
    player$id <- new_player_id()
    player$tutor <- input$player_tutor
    player$group <- input$player_group
    player$role <- input$player_role
    store$register_player(data.frame(
      player_id = player$id,
      tutor = player$tutor,
      group = player$group,
      role = player$role,
      joined_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      stringsAsFactors = FALSE
    ))
  })

  observeEvent(input$leave_game, {
    player$joined <- FALSE
    player$id <- NULL
  })

  output$round_panel <- renderUI({
    state <- current_group_state()
    req(nrow(state) == 1)
    round_number <- state$current_round[[1]]

    if (round_number == 0L) {
      return(div(
        class = "game-card waiting-card rainbow-frame",
        tags$span(class = "status-pill", t("lobby")),
        h2(t("waiting_title")),
        p(t("waiting_text")),
        div(class = "waiting-pulse", tags$span(), tags$span(), tags$span())
      ))
    }

    if (round_number > length(game_config$rounds)) {
      return(div(
        class = "game-card rainbow-frame",
        tags$span(class = "status-pill finished", t("finished")),
        h2(t("negotiations_complete")),
        p(t("results_below")),
        tableOutput("player_results")
      ))
    }

    round_config <- game_config$rounds[[round_number]]
    confidential <- round_confidential(round_config, player$role)
    existing <- store$get_agreements()
    existing <- existing[
      existing$tutor == player$tutor & existing$group == player$group & existing$round == round_number,
      , drop = FALSE
    ]
    field_value <- function(name, fallback = 0) if (nrow(existing) == 1) existing[[name]][[1]] else fallback
    can_submit <- round_number < 3L || identical(player$role, "HCP")

    div(
      div(
        class = "round-heading",
        tags$span(class = "round-number", paste(t("round"), round_number)),
        h1(round_title(round_config))
      ),
      div(
        class = "round-layout",
        div(
          class = "game-card round-card",
          bullet_list(round_summary(round_config))
        ),
        if (length(confidential) > 0) {
          div(
            class = "game-card confidential-card rainbow-frame",
            tags$span(class = "confidential-lock", "✦"),
            h3(t("confidential_for", player$role)),
            bullet_list(confidential)
          )
        } else if (round_number > 1L) {
          div(class = "game-card no-news-card", strong(t("no_confidential")))
        }
      ),
      div(
        class = "game-card agreement-card",
        h3(t("agreement_title")),
        if (can_submit) p(t("agreement_intro")) else p(class = "help-block private-submission-note", t("hcp_submits_round3")),
        if (can_submit && round_number == 3L) tagList(
          p(class = "help-block", t("hospital_help")),
          checkboxInput("use_hospital_production", t("use_hospital_production"), value = field_value("n1") > 0),
          conditionalPanel(
            condition = "input.use_hospital_production",
            div(
              class = "hospital-production-panel",
              numericInput("hospital_patients", t("hospital_patients"), field_value("n1"), min = 0, max = round_config$settings$hospital_capacity, step = 1),
              div(class = "fixed-price", strong(t("price_per_patient")), tags$span(euro(round_config$settings$hospital_price)))
            )
          )
        ),
        if (can_submit) fluidRow(
          if (round_number < 3L) column(4, h4(t("tier", 1)), numericInput("n1", t("tier_patients", 1), field_value("n1"), min = 0, step = 1), numericInput("p1", t("tier_price", 1), field_value("p1"), min = 0, step = 1000)),
          column(if (round_number == 3L) 6 else 4, h4(t("tier", 2)), numericInput("n2", t("tier_patients", 2), field_value("n2"), min = 0, step = 1), numericInput("p2", t("tier_price", 2), field_value("p2"), min = 0, step = 1000)),
          column(if (round_number == 3L) 6 else 4, h4(t("tier", 3)), numericInput("n3", t("tier_patients", 3), field_value("n3"), min = 0, step = 1), numericInput("p3", t("tier_price", 3), field_value("p3"), min = 0, step = 1000))
        ),
        if (can_submit) actionButton("submit_agreement", t("submit_agreement"), class = "btn-primary"),
        hr(),
        h4(t("current_submission")),
        if (can_submit) tableOutput("current_agreement") else textOutput("private_submission_status")
      )
    )
  })

  agreement_from_inputs <- function() {
    state <- current_group_state()
    round_number <- state$current_round[[1]]
    req(round_number >= 1L, round_number <= length(game_config$rounds))
    if (round_number == 3L && !identical(player$role, "HCP")) return(NULL)
    n1 <- if (round_number == 3L) {
      if (isTRUE(input$use_hospital_production)) input$hospital_patients %||% 0 else 0
    } else input$n1 %||% 0
    p1 <- if (round_number == 3L) {
      if (isTRUE(input$use_hospital_production)) game_config$rounds[[3]]$settings$hospital_price else 0
    } else input$p1 %||% 0
    patient_numbers <- c(n1, input$n2 %||% 0, input$n3 %||% 0)
    prices <- c(p1, input$p2 %||% 0, input$p3 %||% 0)

    if (any(!is.finite(c(patient_numbers, prices))) || any(c(patient_numbers, prices) < 0)) {
      showNotification(t("nonnegative"), type = "error"); return(NULL)
    }
    if (any(patient_numbers != round(patient_numbers))) {
      showNotification(t("whole_patients"), type = "error"); return(NULL)
    }
    if (sum(patient_numbers) > game_config$max_patients) {
      showNotification(t("exceeds_patients", game_config$max_patients), type = "error"); return(NULL)
    }
    if (round_number == 3L) {
      settings <- game_config$rounds[[3]]$settings
      if (n1 > settings$hospital_capacity) {
        showNotification(t("hospital_limit"), type = "error"); return(NULL)
      }
    }

    data.frame(
      tutor = player$tutor, group = player$group, round = as.integer(round_number),
      n1 = patient_numbers[[1]], p1 = prices[[1]], n2 = patient_numbers[[2]], p2 = prices[[2]], n3 = patient_numbers[[3]], p3 = prices[[3]],
      updated_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      stringsAsFactors = FALSE
    )
  }

  observeEvent(input$submit_agreement, {
    agreement <- agreement_from_inputs()
    if (is.null(agreement)) return()
    pending_agreement(agreement)
    tier_labels <- vapply(1:3, function(index) {
      if (agreement$round[[1]] == 3L && index == 1L) t("tier_hospital") else t("tier", index)
    }, character(1))
    summary <- data.frame(
      tier = tier_labels,
      patients = as.numeric(agreement[1, c("n1", "n2", "n3")]),
      price = vapply(as.numeric(agreement[1, c("p1", "p2", "p3")]), euro, character(1)),
      stringsAsFactors = FALSE
    )
    names(summary) <- c(t("tier_name"), t("patients"), t("price_per_patient"))
    showModal(modalDialog(
      title = t("agreement_confirm_title"),
      p(t("agreement_confirm_text")),
      tags$table(
        class = "table table-condensed modal-agreement-summary",
        tags$thead(tags$tr(lapply(names(summary), tags$th))),
        tags$tbody(lapply(seq_len(nrow(summary)), function(index) tags$tr(lapply(summary[index, ], tags$td))))
      ),
      footer = tagList(modalButton(t("cancel")), actionButton("confirm_agreement", t("confirm_submit"), class = "btn-primary"))
    ))
  })

  observeEvent(input$confirm_agreement, {
    agreement <- pending_agreement()
    req(!is.null(agreement))
    store$save_agreement(agreement)
    pending_agreement(NULL)
    removeModal()
    showNotification(t("agreement_saved"), type = "message")
  })

  output$private_submission_status <- renderText({
    req(player$joined)
    store$data_revision()
    round_number <- current_group_state()$current_round[[1]]
    agreements <- store$get_agreements()
    submitted <- any(agreements$tutor == player$tutor & agreements$group == player$group & agreements$round == round_number)
    if (submitted) t("agreement_received") else t("no_submission")
  })

  output$current_agreement <- renderTable({
    req(player$joined)
    round_number <- current_group_state()$current_round[[1]]
    store$data_revision()
    agreements <- store$get_agreements()
    agreement <- agreements[agreements$tutor == player$tutor & agreements$group == player$group & agreements$round == round_number, , drop = FALSE]
    if (nrow(agreement) == 0) return(stats::setNames(data.frame(t("no_submission")), t("status")))
    result <- data.frame(
      tier = vapply(1:3, function(index) {
        if (round_number == 3L && index == 1L) t("tier_hospital") else t("tier", index)
      }, character(1)),
      patients = as.numeric(unlist(agreement[1, c("n1", "n2", "n3")], use.names = FALSE)),
      price = vapply(as.numeric(unlist(agreement[1, c("p1", "p2", "p3")], use.names = FALSE)), euro, character(1)),
      check.names = FALSE
    )
    names(result) <- c(t("tier_name"), t("patients"), t("price_per_patient"))
    result
  }, striped = TRUE, bordered = FALSE, spacing = "s", digits = 0)

  output$player_results <- renderTable({
    req(player$joined)
    results <- live_results()
    results <- results[results$tutor == player$tutor & results$group == player$group, c("round", "patients_treated", "budget_impact", "hcp_score", "htd_score"), drop = FALSE]
    if (nrow(results) == 0) return(NULL)
    names(results) <- c(t("round"), t("patients_treated"), t("budget_impact"), t("hcp_score"), t("htd_score"))
    results[[t("budget_impact")]] <- vapply(results[[t("budget_impact")]], euro, character(1))
    results
  }, striped = TRUE, bordered = FALSE)

  output$staff_screen <- renderUI({
    if (!staff_authenticated()) {
      return(div(
        class = "staff-login-layout",
        div(class = "hero-copy", tags$span(class = "eyebrow", t("school_name")), h1(t("staff_access")), p(class = "hero-lead", t("staff_access_intro"))),
        div(
          class = "game-card join-card rainbow-frame",
          if (using_demo_pin) div(class = "demo-warning", strong(t("local_prototype")), paste(" ", t("demo_pin_warning"))),
          passwordInput("staff_pin", t("staff_pin")),
          actionButton("staff_login", t("open_staff"), class = "btn-primary btn-lg btn-block")
        )
      ))
    }

    div(
      div(
        class = "staff-heading",
        div(
          tags$span(class = "eyebrow", t("school_name")),
          h1(t("session_control")),
          p(t("storage_notice", store$mode)),
          if (identical(store$mode, "memory")) p(class = "storage-warning", t("memory_storage_warning"))
        ),
        actionButton("staff_logout", t("lock_staff"), class = "btn-quiet")
      ),
      div(
        class = "staff-grid",
        div(
          class = "game-card feature-card rainbow-frame",
          tags$span(class = "feature-icon", "▶"),
          h3(t("facilitator_presentations")),
          p(t("presentations_intro")),
          div(
            class = "button-row",
            tags$a(
              class = "btn btn-default",
              href = paste0("opening-presentation-", language(), ".html?theme=", theme()),
              target = "_blank",
              t("open_intro")
            ),
            actionButton("create_results_presentation", t("create_results"), class = "btn-success")
          )
        ),
        div(
          class = "game-card feature-card",
          tags$span(class = "feature-icon", "↗"),
          h3(t("round_controls")),
          fluidRow(
            column(6, selectInput("staff_tutor", t("tutor"), choices = c(stats::setNames("__all__", t("all_tutors")), game_config$tutors))),
            column(6, selectInput("staff_group", t("negotiation_group"), choices = c(stats::setNames("__all__", t("all_groups")), game_config$groups)))
          ),
          div(
            class = "button-row",
            actionButton("start_round", t("start_selection"), class = "btn-success"),
            actionButton("previous_round", t("previous_round"), class = "btn-default"),
            actionButton("next_round", t("next_selection"), class = "btn-primary"),
            actionButton("advance_all", t("next_everyone"), class = "btn-default"),
            actionButton("reset_game", t("reset_prototype"), class = "btn-danger")
          )
        )
      ),
      div(class = "game-card dashboard-card rainbow-frame", h3(t("live_group_status")), tableOutput("state_table")),
      div(class = "dashboard-grid", div(class = "game-card dashboard-card", h3(t("joined_players")), tableOutput("players_table")), div(class = "game-card dashboard-card agreements-dashboard", h3(t("submitted_agreements")), div(class = "agreements-table-wrap", tableOutput("agreements_table")))),
      div(class = "game-card dashboard-card", h3(t("calculated_results")), tableOutput("results_table"))
    )
  })

  observeEvent(input$staff_login, {
    if (identical(input$staff_pin, staff_pin)) {
      staff_authenticated(TRUE)
    } else {
      showNotification(t("incorrect_pin"), type = "error")
    }
  })
  observeEvent(input$staff_logout, staff_authenticated(FALSE))

  observeEvent(input$create_results_presentation, {
    req(staff_authenticated())
    if (nrow(store$get_agreements()) == 0) {
      showNotification(t("no_agreements_presentation"), type = "error"); return()
    }
    store$publish_results()
    showModal(modalDialog(
      title = t("presentation_created"),
      p(t("presentation_created_text")),
      footer = tagList(
        modalButton(t("close")),
        tags$a(class = "btn btn-success", href = paste0("?view=results&lang=", language(), "&theme=", theme()), target = "_blank", t("open_results"))
      )
    ))
  })

  observeEvent(input$previous_round, { req(staff_authenticated()); store$advance(selected_tutors(), selected_groups(), -1L) })
  observeEvent(input$start_round, { req(staff_authenticated()); store$advance(selected_tutors(), selected_groups(), 1L, from_rounds = 0L) })
  observeEvent(input$next_round, { req(staff_authenticated()); store$advance(selected_tutors(), selected_groups(), 1L, from_rounds = seq_along(game_config$rounds)) })
  observeEvent(input$advance_all, { req(staff_authenticated()); store$advance(game_config$tutors, game_config$groups, 1L, from_rounds = seq_along(game_config$rounds)) })
  observeEvent(input$reset_game, {
    req(staff_authenticated())
    showModal(modalDialog(title = t("reset_title"), t("reset_text"), footer = tagList(modalButton(t("cancel")), actionButton("confirm_reset", t("reset_data"), class = "btn-danger"))))
  })
  observeEvent(input$confirm_reset, { req(staff_authenticated()); store$reset(); removeModal(); showNotification(t("reset_done"), type = "warning") })

  output$state_table <- renderTable({
    req(staff_authenticated())
    store$state_revision(); store$data_revision()
    state <- store$get_state(); players <- store$get_players(); agreements <- store$get_agreements()
    state$players <- vapply(seq_len(nrow(state)), function(i) sum(players$tutor == state$tutor[[i]] & players$group == state$group[[i]]), integer(1))
    state$submitted <- vapply(seq_len(nrow(state)), function(i) {
      if (state$current_round[[i]] < 1L || state$current_round[[i]] > length(game_config$rounds)) return(FALSE)
      any(agreements$tutor == state$tutor[[i]] & agreements$group == state$group[[i]] & agreements$round == state$current_round[[i]])
    }, logical(1))
    state$submitted <- ifelse(state$submitted, t("yes"), t("no"))
    state$shown_round <- ifelse(state$status == "Finished", t("finished"), state$current_round)
    state$status <- ifelse(state$status == "Lobby", t("lobby"), ifelse(state$status == "Finished", t("finished"), t("open")))
    state <- state[, c("tutor", "group", "shown_round", "status", "players", "submitted")]
    names(state) <- c(t("tutor"), t("group"), t("round"), t("status"), t("players"), t("current_round_submitted"))
    state
  }, striped = TRUE, bordered = FALSE, hover = TRUE)

  output$players_table <- renderTable({
    req(staff_authenticated()); store$data_revision()
    players <- store$get_players(); if (nrow(players) == 0) return(NULL)
    players$role <- vapply(players$role, role_label, character(1))
    players <- players[, c("tutor", "group", "role", "joined_at")]
    names(players) <- c(t("tutor"), t("group"), t("role"), t("joined_utc"))
    players
  }, striped = TRUE, bordered = FALSE)

  output$agreements_table <- renderTable({
    req(staff_authenticated()); store$data_revision()
    agreements <- store$get_agreements(); if (nrow(agreements) == 0) return(NULL)
    for (column in c("p1", "p2", "p3")) agreements[[column]] <- vapply(agreements[[column]], euro, character(1))
    agreements <- agreements[, c("tutor", "group", "round", "n1", "p1", "n2", "p2", "n3", "p3", "updated_at")]
    names(agreements) <- c(
      t("tutor"), t("group"), t("round"),
      t("tier_patients", 1), t("tier_price", 1),
      t("tier_patients", 2), t("tier_price", 2),
      t("tier_patients", 3), t("tier_price", 3),
      t("updated_utc")
    )
    agreements
  }, striped = TRUE, bordered = FALSE, digits = 0)

  output$results_table <- renderTable({
    req(staff_authenticated())
    results <- live_results(); if (nrow(results) == 0) return(NULL)
    results$budget_impact <- vapply(results$budget_impact, euro, character(1))
    results$government_balance <- vapply(results$government_balance, euro, character(1))
    results$patients_treated <- as.integer(results$patients_treated)
    results$patients_untreated <- as.integer(results$patients_untreated)
    results$crowd_out <- round(results$crowd_out, 1)
    results <- results[, c("tutor", "group", "round", "patients_treated", "patients_untreated", "budget_impact", "government_balance", "crowd_out", "hcp_score", "htd_score")]
    names(results) <- c(t("tutor"), t("group"), t("round"), t("patients_treated"), t("untreated"), t("budget_impact"), t("hcp_balance"), t("crowding_out"), t("hcp_score"), t("htd_score"))
    results
  }, striped = TRUE, bordered = FALSE, digits = 1)

  output$presentation_summary <- renderUI({
    results <- live_results()
    possible <- length(game_config$tutors) * length(game_config$groups) * length(game_config$rounds)
    tagList(p(class = "presentation-lead", t("submitted_of", nrow(results), possible)), p(class = "presentation-timestamp", t("live_as_of", format_live_time(Sys.time(), language()))))
  })

  output$presentation_overspent <- renderTable({
    results <- live_results(); overspent <- results[results$government_balance < 0, , drop = FALSE]
    if (nrow(overspent) == 0) return(stats::setNames(data.frame(t("no_overspend")), ""))
    summary <- stats::aggregate(round ~ tutor + group, data = overspent, FUN = length)
    names(summary) <- c(t("tutor"), t("group"), t("rounds_over_budget")); summary
  }, striped = TRUE, bordered = FALSE)

  output$presentation_crowding_out <- renderTable({
    results <- live_results()
    if (nrow(results) == 0) return(stats::setNames(data.frame(t("no_crowding")), ""))
    affected <- results[results$crowd_out < 0, c("tutor", "group", "round", "crowd_out"), drop = FALSE]
    if (nrow(affected) == 0) return(stats::setNames(data.frame(t("no_crowding")), ""))
    affected$crowd_out <- round(affected$crowd_out, 1); names(affected) <- c(t("tutor"), t("group"), t("round"), t("qalys_lost")); affected
  }, striped = TRUE, bordered = FALSE)

  output$presentation_untreated <- renderTable({
    results <- live_results()
    if (nrow(results) == 0) return(stats::setNames(data.frame(t("all_treated")), ""))
    untreated <- results[results$patients_untreated > 0, c("tutor", "group", "round", "patients_untreated"), drop = FALSE]
    if (nrow(untreated) == 0) return(stats::setNames(data.frame(t("all_treated")), ""))
    names(untreated) <- c(t("tutor"), t("group"), t("round"), t("untreated")); untreated
  }, striped = TRUE, bordered = FALSE)

  output$presentation_average_price <- renderTable({
    results <- live_results(); usable <- results[results$patients_treated > 0, , drop = FALSE]
    if (nrow(usable) == 0) return(stats::setNames(data.frame(t("no_treated")), ""))
    usable$average_price <- usable$budget_impact / usable$patients_treated
    split_prices <- split(usable$average_price, usable$round)
    summary <- data.frame(round = as.integer(names(split_prices)), mean = vapply(split_prices, mean, numeric(1)), minimum = vapply(split_prices, min, numeric(1)), maximum = vapply(split_prices, max, numeric(1)))
    for (column in c("mean", "minimum", "maximum")) summary[[column]] <- vapply(summary[[column]], euro, character(1))
    names(summary) <- c(t("round"), t("mean"), t("minimum"), t("maximum")); summary
  }, striped = TRUE, bordered = FALSE)

  output$presentation_scores <- renderTable({
    results <- live_results(); if (nrow(results) == 0) return(stats::setNames(data.frame(t("no_agreements")), ""))
    scores <- results[, c("tutor", "group", "round", "hcp_score", "htd_score"), drop = FALSE]
    scores <- scores[order(scores$tutor, scores$group, scores$round), , drop = FALSE]
    names(scores) <- c(t("tutor"), t("group"), t("round"), t("hcp_points"), t("htd_points")); scores
  }, striped = TRUE, bordered = FALSE)

  for (output_id in c("presentation_summary", "presentation_overspent", "presentation_crowding_out", "presentation_untreated", "presentation_average_price", "presentation_scores")) {
    outputOptions(output, output_id, suspendWhenHidden = FALSE)
  }
}

shinyApp(ui, server)
