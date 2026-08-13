empty_players <- function() {
  data.frame(
    player_id = character(),
    tutor = character(),
    group = character(),
    role = character(),
    joined_at = character(),
    stringsAsFactors = FALSE
  )
}

empty_agreements <- function() {
  data.frame(
    tutor = character(),
    group = character(),
    round = integer(),
    n1 = numeric(),
    p1 = numeric(),
    n2 = numeric(),
    p2 = numeric(),
    n3 = numeric(),
    p3 = numeric(),
    updated_at = character(),
    stringsAsFactors = FALSE
  )
}

create_memory_store <- function(config) {
  state <- expand.grid(
    tutor = config$tutors,
    group = config$groups,
    stringsAsFactors = FALSE
  )
  state$current_round <- 0L
  state$status <- "Lobby"
  state$updated_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)

  players <- empty_players()
  agreements <- empty_agreements()
  results_published <- FALSE
  state_revision <- shiny::reactiveVal(0L)
  data_revision <- shiny::reactiveVal(0L)

  touch_state <- function() {
    state_revision(shiny::isolate(state_revision()) + 1L)
  }

  touch_data <- function() {
    data_revision(shiny::isolate(data_revision()) + 1L)
  }

  list(
    mode = "memory",
    state_revision = state_revision,
    data_revision = data_revision,
    get_state = function() state,
    get_players = function() players,
    get_agreements = function() agreements,
    is_results_published = function() results_published,
    register_player = function(player) {
      existing <- which(players$player_id == player$player_id)
      if (length(existing) > 0) {
        players[existing[[1]], ] <<- player
      } else {
        players <<- rbind(players, player)
      }
      touch_data()
      invisible(player)
    },
    save_agreement = function(agreement) {
      existing <- which(
        agreements$tutor == agreement$tutor &
          agreements$group == agreement$group &
          agreements$round == agreement$round
      )
      if (length(existing) > 0) {
        agreements[existing[[1]], ] <<- agreement
      } else {
        agreements <<- rbind(agreements, agreement)
      }
      touch_data()
      invisible(agreement)
    },
    advance = function(tutors, groups, direction = 1L) {
      selected <- state$tutor %in% tutors & state$group %in% groups
      maximum_round <- length(config$rounds)
      state$current_round[selected] <<- pmax(
        0L,
        pmin(maximum_round + 1L, state$current_round[selected] + direction)
      )
      state$status[selected] <<- ifelse(
        state$current_round[selected] == 0L,
        "Lobby",
        ifelse(state$current_round[selected] > maximum_round, "Finished", "Open")
      )
      state$updated_at[selected] <<- format(Sys.time(), tz = "UTC", usetz = TRUE)
      touch_state()
      invisible(state[selected, , drop = FALSE])
    },
    publish_results = function() {
      results_published <<- TRUE
      touch_data()
      invisible(TRUE)
    },
    reset = function() {
      state$current_round <<- 0L
      state$status <<- "Lobby"
      state$updated_at <<- format(Sys.time(), tz = "UTC", usetz = TRUE)
      players <<- empty_players()
      agreements <<- empty_agreements()
      results_published <<- FALSE
      touch_state()
      touch_data()
      invisible(TRUE)
    }
  )
}

create_game_store <- function(config) {
  mode <- tolower(config$storage$mode)

  if (mode != "memory") {
    stop(
      "Only GAME_STORAGE_MODE=memory is enabled in the first prototype. ",
      "The app-facing storage functions are isolated in R/storage.R so a ",
      "Google Sheets adapter can be added next."
    )
  }

  create_memory_store(config)
}
