empty_players <- function() {
  data.frame(
    player_id = character(), tutor = character(), group = character(),
    role = character(), joined_at = character(), stringsAsFactors = FALSE
  )
}

empty_agreements <- function() {
  data.frame(
    tutor = character(), group = character(), round = integer(),
    n1 = numeric(), p1 = numeric(), n2 = numeric(), p2 = numeric(),
    n3 = numeric(), p3 = numeric(), updated_at = character(),
    stringsAsFactors = FALSE
  )
}

utc_string <- function(value = Sys.time()) format(value, tz = "UTC", usetz = TRUE)

normalise_time_columns <- function(data) {
  for (column in intersect(c("joined_at", "updated_at"), names(data))) {
    if (inherits(data[[column]], "POSIXt")) data[[column]] <- utc_string(data[[column]])
  }
  data
}

create_memory_store <- function(config) {
  state <- expand.grid(tutor = config$tutors, group = config$groups, stringsAsFactors = FALSE)
  state$current_round <- 0L
  state$status <- "Lobby"
  state$updated_at <- utc_string()
  players <- empty_players()
  agreements <- empty_agreements()
  results_published <- FALSE
  state_revision <- shiny::reactiveVal(0L)
  data_revision <- shiny::reactiveVal(0L)
  touch_state <- function() state_revision(shiny::isolate(state_revision()) + 1L)
  touch_data <- function() data_revision(shiny::isolate(data_revision()) + 1L)

  list(
    mode = "memory",
    state_revision = state_revision,
    data_revision = data_revision,
    refresh = function() invisible(FALSE),
    get_state = function() state,
    get_players = function() players,
    get_agreements = function() agreements,
    is_results_published = function() results_published,
    register_player = function(player) {
      existing <- which(players$player_id == player$player_id)
      if (length(existing) > 0) players[existing[[1]], ] <<- player else players <<- rbind(players, player)
      touch_data()
      invisible(player)
    },
    save_agreement = function(agreement) {
      existing <- which(
        agreements$tutor == agreement$tutor & agreements$group == agreement$group &
          agreements$round == agreement$round
      )
      if (length(existing) > 0) agreements[existing[[1]], ] <<- agreement else agreements <<- rbind(agreements, agreement)
      touch_data()
      invisible(agreement)
    },
    advance = function(tutors, groups, direction = 1L, from_rounds = NULL) {
      selected <- state$tutor %in% tutors & state$group %in% groups
      if (!is.null(from_rounds)) selected <- selected & state$current_round %in% from_rounds
      maximum_round <- length(config$rounds)
      state$current_round[selected] <<- pmax(0L, pmin(maximum_round + 1L, state$current_round[selected] + direction))
      state$status[selected] <<- ifelse(
        state$current_round[selected] == 0L, "Lobby",
        ifelse(state$current_round[selected] > maximum_round, "Finished", "Open")
      )
      state$updated_at[selected] <<- utc_string()
      if (any(selected)) touch_state()
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
      state$updated_at <<- utc_string()
      players <<- empty_players()
      agreements <<- empty_agreements()
      results_published <<- FALSE
      touch_state()
      touch_data()
      invisible(TRUE)
    }
  )
}

parse_postgres_url <- function(url) {
  pattern <- "^postgres(?:ql)?://([^:]+):([^@]*)@([^:/?#]+)(?::([0-9]+))?/([^?]+)(?:\\?(.*))?$"
  parts <- regmatches(url, regexec(pattern, url, perl = TRUE))[[1]]
  if (length(parts) == 0) {
    stop("DATABASE_URL must look like postgresql://user:password@host:5432/database?sslmode=require.")
  }
  args <- list(
    user = utils::URLdecode(parts[[2]]), password = utils::URLdecode(parts[[3]]),
    host = parts[[4]], port = if (nzchar(parts[[5]])) as.integer(parts[[5]]) else 5432L,
    dbname = utils::URLdecode(parts[[6]])
  )
  query <- parts[[7]]
  if (nzchar(query)) {
    split_pairs <- strsplit(query, "&", fixed = TRUE)[[1]]
    pairs <- strsplit(split_pairs, "=", fixed = TRUE)
    values <- lapply(pairs, function(pair) utils::URLdecode(pair[[min(2L, length(pair))]]))
    names(values) <- vapply(pairs, `[[`, character(1), 1L)
    if (!is.null(values$sslmode)) args$sslmode <- values$sslmode
  }
  args
}

postgres_connection_args <- function(url_env = "DATABASE_URL", allow_pg_fallback = TRUE) {
  url <- Sys.getenv(url_env, unset = "")
  if (nzchar(url)) return(parse_postgres_url(url))
  if (!allow_pg_fallback) stop(url_env, " is not configured.")
  required <- c(PGHOST = "host", PGDATABASE = "dbname", PGUSER = "user", PGPASSWORD = "password")
  values <- Sys.getenv(names(required), unset = "")
  if (any(!nzchar(values))) {
    stop("PostgreSQL storage requires DATABASE_URL or PGHOST, PGDATABASE, PGUSER, and PGPASSWORD.")
  }
  args <- as.list(stats::setNames(unname(values), unname(required)))
  args$port <- as.integer(Sys.getenv("PGPORT", unset = "5432"))
  sslmode <- Sys.getenv("PGSSLMODE", unset = "require")
  if (nzchar(sslmode)) args$sslmode <- sslmode
  args
}

create_postgres_store <- function(config) {
  if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("RPostgres", quietly = TRUE)) {
    stop("PostgreSQL storage requires the DBI and RPostgres packages.")
  }
  connection_args <- postgres_connection_args("DATABASE_URL")
  schema_connection_args <- if (nzchar(Sys.getenv("DATABASE_URL_UNPOOLED", unset = ""))) {
    postgres_connection_args("DATABASE_URL_UNPOOLED", allow_pg_fallback = FALSE)
  } else {
    connection_args
  }
  session_id <- config$session_id
  state_revision <- shiny::reactiveVal(0L)
  data_revision <- shiny::reactiveVal(0L)
  last_refresh_at <- as.POSIXct(NA)
  connect <- function(args = connection_args) {
    do.call(DBI::dbConnect, c(list(drv = RPostgres::Postgres()), args))
  }
  with_connection_args <- function(args, code) {
    connection <- connect(args)
    on.exit(DBI::dbDisconnect(connection), add = TRUE)
    force(code)(connection)
  }
  with_connection <- function(code) with_connection_args(connection_args, code)
  with_schema_connection <- function(code) with_connection_args(schema_connection_args, code)
  read_revisions <- function(connection) {
    DBI::dbGetQuery(
      connection,
      "SELECT state_revision, data_revision FROM hta_game_sessions WHERE session_id = $1",
      params = list(session_id)
    )
  }
  bump_revisions <- function(connection, state = FALSE, data = FALSE) {
    revisions <- DBI::dbGetQuery(
      connection,
      paste(
        "UPDATE hta_game_sessions",
        "SET state_revision = state_revision + $1, data_revision = data_revision + $2, updated_at = NOW()",
        "WHERE session_id = $3 RETURNING state_revision, data_revision"
      ),
      params = list(as.integer(state), as.integer(data), session_id)
    )
    state_revision(as.integer(revisions$state_revision[[1]]))
    data_revision(as.integer(revisions$data_revision[[1]]))
  }

  with_schema_connection(function(connection) {
    DBI::dbWithTransaction(connection, {
      DBI::dbExecute(connection, paste(
        "CREATE TABLE IF NOT EXISTS hta_game_sessions (",
        "session_id TEXT PRIMARY KEY, results_published BOOLEAN NOT NULL DEFAULT FALSE,",
        "state_revision BIGINT NOT NULL DEFAULT 0, data_revision BIGINT NOT NULL DEFAULT 0,",
        "updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW())"
      ))
      DBI::dbExecute(connection, paste(
        "CREATE TABLE IF NOT EXISTS hta_game_state (",
        "session_id TEXT NOT NULL REFERENCES hta_game_sessions(session_id) ON DELETE CASCADE,",
        "tutor TEXT NOT NULL, group_name TEXT NOT NULL, current_round INTEGER NOT NULL DEFAULT 0,",
        "status TEXT NOT NULL DEFAULT 'Lobby', updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),",
        "PRIMARY KEY (session_id, tutor, group_name))"
      ))
      DBI::dbExecute(connection, paste(
        "CREATE TABLE IF NOT EXISTS hta_game_players (",
        "session_id TEXT NOT NULL REFERENCES hta_game_sessions(session_id) ON DELETE CASCADE,",
        "player_id TEXT NOT NULL, tutor TEXT NOT NULL, group_name TEXT NOT NULL, role TEXT NOT NULL,",
        "joined_at TIMESTAMPTZ NOT NULL, PRIMARY KEY (session_id, player_id))"
      ))
      DBI::dbExecute(connection, paste(
        "CREATE TABLE IF NOT EXISTS hta_game_agreements (",
        "session_id TEXT NOT NULL REFERENCES hta_game_sessions(session_id) ON DELETE CASCADE,",
        "tutor TEXT NOT NULL, group_name TEXT NOT NULL, round_number INTEGER NOT NULL,",
        "n1 DOUBLE PRECISION NOT NULL, p1 DOUBLE PRECISION NOT NULL,",
        "n2 DOUBLE PRECISION NOT NULL, p2 DOUBLE PRECISION NOT NULL,",
        "n3 DOUBLE PRECISION NOT NULL, p3 DOUBLE PRECISION NOT NULL,",
        "updated_at TIMESTAMPTZ NOT NULL, PRIMARY KEY (session_id, tutor, group_name, round_number))"
      ))
    })
  })

  with_connection(function(connection) {
    DBI::dbWithTransaction(connection, {
      DBI::dbExecute(
        connection,
        "INSERT INTO hta_game_sessions (session_id) VALUES ($1) ON CONFLICT (session_id) DO NOTHING",
        params = list(session_id)
      )
      for (tutor in config$tutors) for (group in config$groups) {
        DBI::dbExecute(
          connection,
          paste(
            "INSERT INTO hta_game_state (session_id, tutor, group_name)",
            "VALUES ($1, $2, $3) ON CONFLICT (session_id, tutor, group_name) DO NOTHING"
          ),
          params = list(session_id, tutor, group)
        )
      }
    })
    revisions <- read_revisions(connection)
    state_revision(as.integer(revisions$state_revision[[1]]))
    data_revision(as.integer(revisions$data_revision[[1]]))
  })

  list(
    mode = "postgres",
    state_revision = state_revision,
    data_revision = data_revision,
    refresh = function() {
      now <- Sys.time()
      minimum_gap <- max(0.25, config$poll_interval_ms / 1000 * 0.75)
      if (!is.na(last_refresh_at) && as.numeric(difftime(now, last_refresh_at, units = "secs")) < minimum_gap) {
        return(invisible(FALSE))
      }
      revisions <- with_connection(read_revisions)
      last_refresh_at <<- now
      changed <- revisions$state_revision[[1]] != shiny::isolate(state_revision()) ||
        revisions$data_revision[[1]] != shiny::isolate(data_revision())
      state_revision(as.integer(revisions$state_revision[[1]]))
      data_revision(as.integer(revisions$data_revision[[1]]))
      invisible(changed)
    },
    get_state = function() with_connection(function(connection) {
      result <- DBI::dbGetQuery(
        connection,
        paste(
          "SELECT tutor, group_name AS \"group\", current_round, status, updated_at",
          "FROM hta_game_state WHERE session_id = $1 ORDER BY tutor, group_name"
        ),
        params = list(session_id)
      )
      result$current_round <- as.integer(result$current_round)
      normalise_time_columns(result)
    }),
    get_players = function() with_connection(function(connection) {
      result <- DBI::dbGetQuery(
        connection,
        paste(
          "SELECT player_id, tutor, group_name AS \"group\", role, joined_at",
          "FROM hta_game_players WHERE session_id = $1 ORDER BY joined_at"
        ),
        params = list(session_id)
      )
      normalise_time_columns(result)
    }),
    get_agreements = function() with_connection(function(connection) {
      result <- DBI::dbGetQuery(
        connection,
        paste(
          "SELECT tutor, group_name AS \"group\", round_number AS \"round\", n1, p1, n2, p2, n3, p3, updated_at",
          "FROM hta_game_agreements WHERE session_id = $1 ORDER BY tutor, group_name, round_number"
        ),
        params = list(session_id)
      )
      result$round <- as.integer(result$round)
      normalise_time_columns(result)
    }),
    is_results_published = function() with_connection(function(connection) {
      result <- DBI::dbGetQuery(
        connection,
        "SELECT results_published FROM hta_game_sessions WHERE session_id = $1",
        params = list(session_id)
      )
      isTRUE(result$results_published[[1]])
    }),
    register_player = function(player) with_connection(function(connection) {
      DBI::dbWithTransaction(connection, {
        DBI::dbExecute(
          connection,
          paste(
            "INSERT INTO hta_game_players (session_id, player_id, tutor, group_name, role, joined_at)",
            "VALUES ($1, $2, $3, $4, $5, $6)",
            "ON CONFLICT (session_id, player_id) DO UPDATE SET",
            "tutor = EXCLUDED.tutor, group_name = EXCLUDED.group_name, role = EXCLUDED.role, joined_at = EXCLUDED.joined_at"
          ),
          params = list(session_id, player$player_id[[1]], player$tutor[[1]], player$group[[1]], player$role[[1]], player$joined_at[[1]])
        )
        bump_revisions(connection, data = TRUE)
      })
      invisible(player)
    }),
    save_agreement = function(agreement) with_connection(function(connection) {
      DBI::dbWithTransaction(connection, {
        DBI::dbExecute(
          connection,
          paste(
            "INSERT INTO hta_game_agreements",
            "(session_id, tutor, group_name, round_number, n1, p1, n2, p2, n3, p3, updated_at)",
            "VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
            "ON CONFLICT (session_id, tutor, group_name, round_number) DO UPDATE SET",
            "n1 = EXCLUDED.n1, p1 = EXCLUDED.p1, n2 = EXCLUDED.n2, p2 = EXCLUDED.p2,",
            "n3 = EXCLUDED.n3, p3 = EXCLUDED.p3, updated_at = EXCLUDED.updated_at"
          ),
          params = list(
            session_id, agreement$tutor[[1]], agreement$group[[1]], as.integer(agreement$round[[1]]),
            agreement$n1[[1]], agreement$p1[[1]], agreement$n2[[1]], agreement$p2[[1]],
            agreement$n3[[1]], agreement$p3[[1]], agreement$updated_at[[1]]
          )
        )
        bump_revisions(connection, data = TRUE)
      })
      invisible(agreement)
    }),
    advance = function(tutors, groups, direction = 1L, from_rounds = NULL) with_connection(function(connection) {
      changed <- DBI::dbWithTransaction(connection, {
        current <- DBI::dbGetQuery(
          connection,
          "SELECT tutor, group_name, current_round FROM hta_game_state WHERE session_id = $1",
          params = list(session_id)
        )
        selected <- current$tutor %in% tutors & current$group_name %in% groups
        if (!is.null(from_rounds)) selected <- selected & current$current_round %in% from_rounds
        current <- current[selected, , drop = FALSE]
        maximum_round <- length(config$rounds)
        if (nrow(current) > 0) {
          for (index in seq_len(nrow(current))) {
            next_round <- max(0L, min(maximum_round + 1L, as.integer(current$current_round[[index]]) + direction))
            next_status <- if (next_round == 0L) "Lobby" else if (next_round > maximum_round) "Finished" else "Open"
            DBI::dbExecute(
              connection,
              paste(
                "UPDATE hta_game_state SET current_round = $1, status = $2, updated_at = NOW()",
                "WHERE session_id = $3 AND tutor = $4 AND group_name = $5"
              ),
              params = list(next_round, next_status, session_id, current$tutor[[index]], current$group_name[[index]])
            )
          }
          bump_revisions(connection, state = TRUE)
        }
        current
      })
      invisible(changed)
    }),
    publish_results = function() with_connection(function(connection) {
      DBI::dbWithTransaction(connection, {
        DBI::dbExecute(
          connection,
          "UPDATE hta_game_sessions SET results_published = TRUE WHERE session_id = $1",
          params = list(session_id)
        )
        bump_revisions(connection, data = TRUE)
      })
      invisible(TRUE)
    }),
    reset = function() with_connection(function(connection) {
      DBI::dbWithTransaction(connection, {
        DBI::dbExecute(connection, "DELETE FROM hta_game_players WHERE session_id = $1", params = list(session_id))
        DBI::dbExecute(connection, "DELETE FROM hta_game_agreements WHERE session_id = $1", params = list(session_id))
        DBI::dbExecute(
          connection,
          "UPDATE hta_game_state SET current_round = 0, status = 'Lobby', updated_at = NOW() WHERE session_id = $1",
          params = list(session_id)
        )
        DBI::dbExecute(
          connection,
          "UPDATE hta_game_sessions SET results_published = FALSE WHERE session_id = $1",
          params = list(session_id)
        )
        bump_revisions(connection, state = TRUE, data = TRUE)
      })
      invisible(TRUE)
    })
  )
}

create_game_store <- function(config) {
  mode <- tolower(config$storage$mode)
  if (identical(mode, "memory")) return(create_memory_store(config))
  if (mode %in% c("postgres", "postgresql")) return(create_postgres_store(config))
  stop("Unknown GAME_STORAGE_MODE. Use 'memory' or 'postgres'.")
}
