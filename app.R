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

presentation_table <- function(data) {
  tags$table(
    class = "table table-striped",
    tags$thead(tags$tr(lapply(names(data), tags$th))),
    tags$tbody(lapply(seq_len(nrow(data)), function(index) {
      tags$tr(lapply(data[index, , drop = TRUE], function(value) tags$td(as.character(value))))
    }))
  )
}

presentation_tables <- function(snapshot, language) {
  t <- function(key, ...) tr(key, language, ...)
  euro <- function(value) format_euro(value, language)
  results <- calculate_scores(snapshot$agreements, game_config$rounds)
  audit <- snapshot$audit
  audit_rows <- lapply(game_config$tutors, function(tutor) {
    lapply(seq_along(game_config$rounds), function(round_number) {
      rows <- audit[audit$tutor == tutor & audit$round == round_number, , drop = FALSE]
      groups_with <- function(status) {
        groups <- rows$group[rows$status == status]
        if (length(groups)) paste(groups, collapse = ", ") else "—"
      }
      data.frame(
        tutor = tutor, round = round_number,
        scored = sum(rows$status %in% c("accepted", "marker_unverified")),
        missing = groups_with("missing"),
        outside = groups_with("outside_window"),
        unmarked = groups_with("marker_unverified"),
        cutoff = format(rows$cutoff_at[[1]], "%H:%M:%S", tz = "UTC")
      )
    })
  })
  audit_summary <- do.call(rbind, unlist(audit_rows, recursive = FALSE))
  names(audit_summary) <- c(t("tutor"), t("round"), t("scored"), t("missing_groups"),
                            t("outside_window_groups"), t("unmarked_groups"), t("cutoff_utc"))
  if (nrow(results) == 0L) {
    no_results <- stats::setNames(data.frame(t("no_agreements")), "")
    return(list(results = results, audit = audit_summary, overspent = no_results,
                crowding = no_results, untreated = no_results, average = no_results,
                scores = no_results))
  }
  overspent <- results[results$government_balance < 0, , drop = FALSE]
  if (nrow(overspent)) {
    overspent <- stats::aggregate(round ~ tutor + group, data = overspent, FUN = length)
    names(overspent) <- c(t("tutor"), t("group"), t("rounds_over_budget"))
  } else overspent <- stats::setNames(data.frame(t("no_overspend")), "")
  crowding <- results[results$crowd_out < 0, c("tutor", "group", "round", "crowd_out"), drop = FALSE]
  if (nrow(crowding)) {
    crowding$crowd_out <- round(crowding$crowd_out, 1)
    names(crowding) <- c(t("tutor"), t("group"), t("round"), t("qalys_lost"))
  } else crowding <- stats::setNames(data.frame(t("no_crowding")), "")
  untreated <- results[results$patients_untreated > 0, c("tutor", "group", "round", "patients_untreated"), drop = FALSE]
  if (nrow(untreated)) names(untreated) <- c(t("tutor"), t("group"), t("round"), t("untreated"))
  else untreated <- stats::setNames(data.frame(t("all_treated")), "")
  usable <- results[results$patients_treated > 0, , drop = FALSE]
  if (nrow(usable)) {
    usable$average_price <- usable$budget_impact / usable$patients_treated
    split_prices <- split(usable$average_price, usable$round)
    average <- data.frame(
      round = as.integer(names(split_prices)),
      mean = vapply(split_prices, mean, numeric(1)),
      minimum = vapply(split_prices, min, numeric(1)),
      maximum = vapply(split_prices, max, numeric(1))
    )
    for (column in c("mean", "minimum", "maximum")) average[[column]] <- vapply(average[[column]], euro, character(1))
    names(average) <- c(t("round"), t("mean"), t("minimum"), t("maximum"))
  } else average <- stats::setNames(data.frame(t("no_treated")), "")
  scores <- results[order(results$tutor, results$group, results$round),
                    c("tutor", "group", "round", "hcp_score", "htd_score"), drop = FALSE]
  names(scores) <- c(t("tutor"), t("group"), t("round"), t("hcp_points"), t("htd_points"))
  list(results = results, audit = audit_summary, overspent = overspent, crowding = crowding,
       untreated = untreated, average = average, scores = scores)
}

results_presentation_ui <- function(language = "en", theme = "light", snapshot = NULL) {
  language <- safe_language(language)
  theme <- safe_theme(theme)
  tables <- if (!is.null(snapshot)) presentation_tables(snapshot, language) else NULL

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
    if (is.null(snapshot)) {
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
                p(class = "presentation-lead", tr("submitted_of", language, nrow(tables$results), nrow(snapshot$audit))),
                p(class = "presentation-timestamp", tr("snapshot_as_of", language, format_live_time(snapshot$generated_at, language)))
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
          tags$section(class = "result-slide", div(class = "slide-content wide-slide", tags$span(class = "eyebrow", tr("submission_timing", language)), h1(tr("submission_timing", language)), p(tr("timing_explanation", language)), div(class = "result-table-frame rainbow-frame", presentation_table(tables$audit)))),
          tags$section(class = "result-slide", div(class = "slide-content", tags$span(class = "eyebrow", tr("results_n", language, 1)), h1(tr("overspent_budget", language)), div(class = "result-table-frame rainbow-frame", presentation_table(tables$overspent)))),
          tags$section(class = "result-slide", div(class = "slide-content", tags$span(class = "eyebrow", tr("results_n", language, 2)), h1(tr("crowding_out", language)), div(class = "result-table-frame rainbow-frame", presentation_table(tables$crowding)))),
          tags$section(class = "result-slide", div(class = "slide-content", tags$span(class = "eyebrow", tr("results_n", language, 3)), h1(tr("untreated_patients", language)), div(class = "result-table-frame rainbow-frame", presentation_table(tables$untreated)))),
          tags$section(class = "result-slide", div(class = "slide-content", tags$span(class = "eyebrow", tr("results_n", language, 4)), h1(tr("average_price", language)), div(class = "result-table-frame rainbow-frame", presentation_table(tables$average)))),
          tags$section(class = "result-slide", div(class = "slide-content wide-slide", tags$span(class = "eyebrow", tr("results_n", language, 5)), h1(tr("points_group_round", language)), div(class = "result-table-frame rainbow-frame", presentation_table(tables$scores)))),
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
          tags$span(id = "slide-counter", "1 / 9"),
          actionButton("next_slide", tr("next", language), class = "presentation-button")
        )
      )
    }
  )
}

ui <- function(request) {
  query <- shiny::parseQueryString(request$QUERY_STRING %||% "")
  if (identical(query$view, "results")) {
    snapshot <- tryCatch(store$get_presentation(query$token %||% ""), error = function(error) {
      warning("Could not load presentation snapshot: ", conditionMessage(error))
      NULL
    })
    results_presentation_ui(query$lang %||% "en", query$theme %||% "light", snapshot)
  } else {
    main_ui
  }
}

server <- function(input, output, session) {
  player <- reactiveValues(joined = FALSE, tutor = NULL, group = NULL, role = NULL, round = 0L)
  staff_authenticated <- reactiveVal(FALSE)
  active_view <- reactiveVal("play")
  language <- reactiveVal("en")
  theme <- reactiveVal("light")
  pending_agreement <- reactiveVal(NULL)
  local_agreements <- reactiveVal(list())
  last_round_event <- reactiveVal(NULL)

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
    player$tutor <- input$player_tutor
    player$group <- input$player_group
    player$role <- input$player_role
    player$round <- 0L
    local_agreements(list())
  })

  observeEvent(input$leave_game, {
    player$joined <- FALSE
    player$round <- 0L
    local_agreements(list())
  })

  observeEvent(input$student_next_round, {
    req(player$joined)
    player$round <- min(length(game_config$rounds) + 1L, player$round + 1L)
  })

  output$round_panel <- renderUI({
    req(player$joined)
    round_number <- player$round

    if (round_number == 0L) {
      return(div(
        class = "game-card waiting-card rainbow-frame",
        tags$span(class = "status-pill", t("lobby")),
        h2(t("waiting_title")),
        p(t("waiting_text")),
        actionButton("student_next_round", t("continue_round", 1L), class = "btn-primary btn-lg")
      ))
    }

    if (round_number > length(game_config$rounds)) {
      return(div(
        class = "game-card rainbow-frame",
        tags$span(class = "status-pill finished", t("finished")),
        h2(t("negotiations_complete")),
        p(t("results_below"))
      ))
    }

    round_config <- game_config$rounds[[round_number]]
    confidential <- round_confidential(round_config, player$role)
    existing <- local_agreements()[[as.character(round_number)]]
    field_value <- function(name, fallback = 0) if (!is.null(existing)) existing[[name]][[1]] else fallback
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
        if (can_submit) tagList(
          hr(),
          h4(t("current_submission")),
          tableOutput("current_agreement")
        )
      ),
      div(class = "student-round-next", actionButton(
        "student_next_round",
        if (round_number < length(game_config$rounds)) t("continue_round", round_number + 1L) else t("complete_game"),
        class = "btn-primary btn-lg"
      ))
    )
  })

  agreement_from_inputs <- function() {
    round_number <- player$round
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
      submission_id = new_player_id(),
      tutor = player$tutor, group = player$group, round = as.integer(round_number),
      role = player$role,
      n1 = patient_numbers[[1]], p1 = prices[[1]], n2 = patient_numbers[[2]], p2 = prices[[2]], n3 = patient_numbers[[3]], p3 = prices[[3]],
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
    receipt <- tryCatch(store$save_agreement(agreement), error = function(error) {
      showNotification(t("save_failed"), type = "error", duration = 8)
      NULL
    })
    if (is.null(receipt)) return()
    agreement$submitted_at <- receipt$submitted_at[[1]]
    saved <- local_agreements()
    saved[[as.character(agreement$round[[1]])]] <- agreement
    local_agreements(saved)
    pending_agreement(NULL)
    removeModal()
    showNotification(t("agreement_saved", utc_label(receipt$submitted_at[[1]])), type = "message")
  })

  output$current_agreement <- renderTable({
    req(player$joined)
    round_number <- player$round
    agreement <- local_agreements()[[as.character(round_number)]]
    if (is.null(agreement)) return(stats::setNames(data.frame(t("no_local_submission")), t("status")))
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
          p(t("round_controls_intro")),
          selectInput("staff_tutor", t("tutor"), choices = game_config$tutors),
          div(class = "button-row", actionButton("advance_all", t("next_everyone"), class = "btn-primary")),
          textOutput("last_round_recorded"),
          div(class = "round-reset-row", actionButton("reset_game", t("reset_prototype"), class = "btn-danger"))
        ),
        div(
          class = "game-card timer-card rainbow-frame",
          div(
            class = "timer-copy",
            tags$span(class = "feature-icon", "◷"),
            h3(t("round_timer")),
            p(t("round_timer_intro")),
            p(class = "timer-local-note", t("timer_local_note"))
          ),
          div(
            id = "staff-round-timer",
            class = "timer-panel",
            div(
              class = "timer-readout",
              tags$span(id = "timer-elapsed", class = "timer-value", `aria-label` = t("elapsed_time"), "00:00"),
              tags$span(class = "timer-label", t("elapsed_time"))
            ),
            div(
              class = "button-row timer-buttons",
              tags$button(
                id = "timer-start-stop", type = "button", class = "btn btn-primary",
                `data-label-start` = t("timer_start"), `data-label-stop` = t("timer_stop"),
                t("timer_start")
              ),
              tags$button(id = "timer-reset", type = "button", class = "btn btn-default", t("timer_reset"))
            ),
            div(
              class = "timer-beep-row",
              tags$label(
                class = "timer-beep-toggle",
                tags$input(id = "timer-beep-enabled", type = "checkbox"),
                tags$span(t("timer_beep_at"))
              ),
              tags$input(
                id = "timer-beep-minutes", class = "form-control timer-minute-input",
                type = "number", min = "1", max = "180", step = "1", value = "10",
                `aria-label` = t("timer_beep_minutes_label")
              ),
              tags$span(class = "timer-minute-label", t("minutes"))
            )
          )
        )
      )
    )
  })

  output$last_round_recorded <- renderText({
    event <- last_round_event()
    if (is.null(event)) return(t("round_record_note"))
    stage <- if (event$round[[1]] > length(game_config$rounds)) t("game_end") else paste(t("round"), event$round[[1]])
    t("round_recorded", event$tutor[[1]], stage, utc_label(event$recorded_at[[1]]))
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
    record <- tryCatch(store$create_presentation(), error = function(error) {
      showNotification(t("save_failed"), type = "error", duration = 8)
      NULL
    })
    if (is.null(record)) return()
    showModal(modalDialog(
      title = t("presentation_created"),
      p(t("presentation_created_text")),
      footer = tagList(
        modalButton(t("close")),
        tags$a(class = "btn btn-success", href = paste0(
          "?view=results&token=", record$token[[1]], "&lang=", language(), "&theme=", theme()
        ), target = "_blank", t("open_results"))
      )
    ))
  })

  observeEvent(input$advance_all, {
    req(staff_authenticated())
    req(input$staff_tutor)
    showModal(modalDialog(
      title = t("confirm_round_title"),
      p(t("confirm_round_text", input$staff_tutor)),
      footer = tagList(modalButton(t("cancel")), actionButton("confirm_next_round", t("confirm_round"), class = "btn-primary"))
    ))
  })
  observeEvent(input$confirm_next_round, {
    req(staff_authenticated(), input$staff_tutor)
    event <- tryCatch(store$record_next_round(input$staff_tutor), error = function(error) {
      showNotification(t("save_failed"), type = "error", duration = 8)
      structure(list(), class = "round_save_error")
    })
    removeModal()
    if (inherits(event, "round_save_error")) return()
    if (is.null(event)) {
      showNotification(t("no_more_rounds"), type = "warning")
      return()
    }
    last_round_event(event)
  })
  observeEvent(input$reset_game, {
    req(staff_authenticated())
    showModal(modalDialog(title = t("reset_title"), t("reset_text"), footer = tagList(modalButton(t("cancel")), actionButton("confirm_reset", t("reset_data"), class = "btn-danger"))))
  })
  observeEvent(input$confirm_reset, {
    req(staff_authenticated())
    tryCatch({
      store$reset()
      last_round_event(NULL)
      removeModal()
      showNotification(t("reset_done"), type = "warning")
    }, error = function(error) showNotification(t("save_failed"), type = "error", duration = 8))
  })
}

shinyApp(ui, server)
