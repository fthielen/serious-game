# The classroom app writes an append-only submission log. The only bulk read
# happens when a tutor opens a results-presentation URL.

empty_submissions <- function() {
  data.frame(
    submission_id = character(), tutor = character(), group = character(),
    role = character(), round = integer(), n1 = numeric(), p1 = numeric(),
    n2 = numeric(), p2 = numeric(), n3 = numeric(), p3 = numeric(),
    submitted_at = as.POSIXct(character(), tz = "UTC"),
    stringsAsFactors = FALSE
  )
}

empty_round_events <- function() {
  data.frame(
    tutor = character(), round = integer(),
    recorded_at = as.POSIXct(character(), tz = "UTC"),
    stringsAsFactors = FALSE
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

new_record_token <- function() {
  paste(sample(c(letters, LETTERS, 0:9), 32L, replace = TRUE), collapse = "")
}

utc_time <- function(value) as.POSIXct(value, tz = "UTC")
utc_label <- function(value) format(utc_time(value), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC")

validate_submission <- function(agreement, config) {
  stopifnot(
    nrow(agreement) == 1L,
    agreement$tutor[[1]] %in% config$tutors,
    agreement$group[[1]] %in% config$groups,
    agreement$role[[1]] %in% c("HCP", "HTD"),
    agreement$round[[1]] %in% seq_along(config$rounds),
    agreement$round[[1]] != 3L || agreement$role[[1]] == "HCP",
    nzchar(agreement$submission_id[[1]])
  )
  invisible(TRUE)
}

evaluate_presentation <- function(submissions, events, generated_at, config) {
  generated_at <- utc_time(generated_at)
  submissions$submitted_at <- utc_time(submissions$submitted_at)
  events$recorded_at <- utc_time(events$recorded_at)
  agreements <- empty_agreements()
  audit <- expand.grid(
    tutor = config$tutors, group = config$groups,
    round = seq_along(config$rounds), stringsAsFactors = FALSE
  )
  audit$status <- "missing"
  audit$start_recorded <- FALSE
  audit$cutoff_recorded <- FALSE
  audit$cutoff_at <- as.POSIXct(rep(NA_real_, nrow(audit)), origin = "1970-01-01", tz = "UTC")

  for (index in seq_len(nrow(audit))) {
    tutor <- audit$tutor[[index]]
    group <- audit$group[[index]]
    round_number <- audit$round[[index]]
    start <- events$recorded_at[events$tutor == tutor & events$round == round_number]
    end <- events$recorded_at[events$tutor == tutor & events$round == round_number + 1L]
    cutoff <- if (length(end)) min(generated_at, end[[1]]) else generated_at
    audit$start_recorded[[index]] <- length(start) > 0L
    audit$cutoff_recorded[[index]] <- length(end) > 0L || round_number == length(config$rounds)
    audit$cutoff_at[[index]] <- cutoff

    candidates <- submissions[
      submissions$tutor == tutor & submissions$group == group &
        submissions$round == round_number, , drop = FALSE
    ]
    if (nrow(candidates) == 0L) next
    on_time <- candidates$submitted_at <= cutoff
    if (length(start)) on_time <- on_time & candidates$submitted_at >= start[[1]]
    if (!any(on_time)) {
      audit$status[[index]] <- "outside_window"
      next
    }
    candidates <- candidates[on_time, , drop = FALSE]
    chosen <- candidates[order(candidates$submitted_at, candidates$submission_id, decreasing = TRUE)[[1]], , drop = FALSE]
    audit$status[[index]] <- if (audit$start_recorded[[index]] && audit$cutoff_recorded[[index]]) {
      "accepted"
    } else "marker_unverified"
    agreements <- rbind(
      agreements,
      data.frame(
        tutor = chosen$tutor, group = chosen$group, round = as.integer(chosen$round),
        n1 = chosen$n1, p1 = chosen$p1, n2 = chosen$n2, p2 = chosen$p2,
        n3 = chosen$n3, p3 = chosen$p3,
        updated_at = utc_label(chosen$submitted_at),
        stringsAsFactors = FALSE
      )
    )
  }
  list(agreements = agreements, audit = audit, generated_at = generated_at)
}

create_memory_store <- function(config, clock = Sys.time) {
  submissions <- empty_submissions()
  events <- empty_round_events()
  presentations <- data.frame(
    token = character(), created_at = as.POSIXct(character(), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  list(
    mode = "memory",
    save_agreement = function(agreement) {
      validate_submission(agreement, config)
      existing <- submissions[submissions$submission_id == agreement$submission_id[[1]], , drop = FALSE]
      if (nrow(existing)) return(existing[1, c("submission_id", "submitted_at"), drop = FALSE])
      agreement$submitted_at <- utc_time(clock())
      submissions <<- rbind(submissions, agreement[, names(submissions), drop = FALSE])
      agreement[, c("submission_id", "submitted_at"), drop = FALSE]
    },
    record_next_round = function(tutor) {
      stopifnot(tutor %in% config$tutors)
      next_round <- 1L + sum(events$tutor == tutor)
      if (next_round > length(config$rounds) + 1L) return(NULL)
      event <- data.frame(tutor = tutor, round = next_round, recorded_at = utc_time(clock()))
      events <<- rbind(events, event)
      event
    },
    create_presentation = function() {
      record <- data.frame(token = new_record_token(), created_at = utc_time(clock()))
      presentations <<- rbind(presentations, record)
      record
    },
    get_presentation = function(token) {
      record <- presentations[presentations$token == token, , drop = FALSE]
      if (nrow(record) != 1L) return(NULL)
      at <- record$created_at[[1]]
      evaluate_presentation(
        submissions[submissions$submitted_at <= at, , drop = FALSE],
        events[events$recorded_at <= at, , drop = FALSE],
        at, config
      )
    },
    reset = function() {
      submissions <<- empty_submissions()
      events <<- empty_round_events()
      presentations <<- presentations[0, , drop = FALSE]
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
    pairs <- strsplit(strsplit(query, "&", fixed = TRUE)[[1]], "=", fixed = TRUE)
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

postgres_app_connection_args <- function(
  pooled_url = Sys.getenv("DATABASE_URL", unset = ""),
  direct_url = Sys.getenv("DATABASE_URL_UNPOOLED", unset = "")
) {
  # RPostgres parameter binding intermittently fails through Neon's transaction
  # pooler, so this low-traffic app uses a short-lived direct connection.
  if (nzchar(direct_url)) return(parse_postgres_url(direct_url))
  if (nzchar(pooled_url)) {
    args <- parse_postgres_url(pooled_url)
    if (grepl("-pooler", args$host, fixed = TRUE)) {
      stop("RPostgres requires DATABASE_URL_UNPOOLED for this app; a pooled-only URL can fail parameterized queries.")
    }
    return(args)
  }
  postgres_connection_args("DATABASE_URL")
}

create_postgres_store <- function(config) {
  if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("RPostgres", quietly = TRUE)) {
    stop("PostgreSQL storage requires the DBI and RPostgres packages.")
  }
  connection_args <- postgres_app_connection_args()
  schema_args <- connection_args
  session_id <- config$session_id
  schema_ready <- FALSE
  connect <- function(args) do.call(DBI::dbConnect, c(list(drv = RPostgres::Postgres()), args))
  with_connection <- function(code, args = connection_args) {
    connection <- connect(args)
    on.exit(DBI::dbDisconnect(connection), add = TRUE)
    code(connection)
  }
  ensure_schema <- function() {
    if (schema_ready) return(invisible(TRUE))
    with_connection(function(connection) {
      DBI::dbWithTransaction(connection, {
        DBI::dbGetQuery(connection, "SELECT pg_advisory_xact_lock(721044)")
        DBI::dbExecute(connection, paste(
          "CREATE TABLE IF NOT EXISTS hta_game_submission_log (",
          "session_id TEXT NOT NULL, submission_id TEXT NOT NULL, tutor TEXT NOT NULL,",
          "group_name TEXT NOT NULL, role TEXT NOT NULL, round_number INTEGER NOT NULL,",
          "n1 DOUBLE PRECISION NOT NULL, p1 DOUBLE PRECISION NOT NULL,",
          "n2 DOUBLE PRECISION NOT NULL, p2 DOUBLE PRECISION NOT NULL,",
          "n3 DOUBLE PRECISION NOT NULL, p3 DOUBLE PRECISION NOT NULL,",
          "submitted_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),",
          "PRIMARY KEY (session_id, submission_id))"
        ))
        DBI::dbExecute(connection, paste(
          "CREATE INDEX IF NOT EXISTS hta_game_submission_lookup",
          "ON hta_game_submission_log (session_id, tutor, group_name, round_number, submitted_at)"
        ))
        DBI::dbExecute(connection, paste(
          "CREATE TABLE IF NOT EXISTS hta_game_round_events (",
          "session_id TEXT NOT NULL, tutor TEXT NOT NULL, round_number INTEGER NOT NULL,",
          "recorded_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),",
          "PRIMARY KEY (session_id, tutor, round_number))"
        ))
        DBI::dbExecute(connection, paste(
          "CREATE TABLE IF NOT EXISTS hta_game_presentations (",
          "session_id TEXT NOT NULL, token TEXT NOT NULL,",
          "created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),",
          "PRIMARY KEY (session_id, token))"
        ))
      })
    }, args = schema_args)
    schema_ready <<- TRUE
    invisible(TRUE)
  }
  list(
    mode = "postgres",
    save_agreement = function(agreement) {
      validate_submission(agreement, config)
      ensure_schema()
      with_connection(function(connection) {
        DBI::dbGetQuery(
          connection,
          paste(
            "INSERT INTO hta_game_submission_log",
            "(session_id, submission_id, tutor, group_name, role, round_number,",
            "n1, p1, n2, p2, n3, p3)",
            "VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)",
            "ON CONFLICT (session_id, submission_id) DO UPDATE",
            "SET submission_id = EXCLUDED.submission_id",
            "RETURNING submission_id, submitted_at"
          ),
          params = list(
            session_id, agreement$submission_id[[1]], agreement$tutor[[1]],
            agreement$group[[1]], agreement$role[[1]], as.integer(agreement$round[[1]]),
            agreement$n1[[1]], agreement$p1[[1]], agreement$n2[[1]], agreement$p2[[1]],
            agreement$n3[[1]], agreement$p3[[1]]
          )
        )
      })
    },
    record_next_round = function(tutor) {
      stopifnot(tutor %in% config$tutors)
      ensure_schema()
      with_connection(function(connection) {
        result <- DBI::dbGetQuery(
          connection,
          paste(
            "INSERT INTO hta_game_round_events (session_id, tutor, round_number)",
            "SELECT $1, $2, COALESCE(MAX(round_number), 0) + 1",
            "FROM hta_game_round_events WHERE session_id = $1 AND tutor = $2",
            "HAVING COALESCE(MAX(round_number), 0) < $3",
            "ON CONFLICT DO NOTHING RETURNING tutor, round_number AS round, recorded_at"
          ),
          params = list(session_id, tutor, length(config$rounds) + 1L)
        )
        if (!nrow(result)) return(NULL)
        result$round <- as.integer(result$round)
        result
      })
    },
    create_presentation = function() {
      ensure_schema()
      with_connection(function(connection) {
        DBI::dbGetQuery(
          connection,
          paste(
            "INSERT INTO hta_game_presentations (session_id, token)",
            "VALUES ($1, $2) RETURNING token, created_at"
          ),
          params = list(session_id, new_record_token())
        )
      })
    },
    get_presentation = function(token) {
      if (!is.character(token) || length(token) != 1L || !grepl("^[A-Za-z0-9]{32}$", token)) return(NULL)
      with_connection(function(connection) {
        DBI::dbWithTransaction(connection, {
          record <- DBI::dbGetQuery(
            connection,
            "SELECT created_at FROM hta_game_presentations WHERE session_id = $1 AND token = $2",
            params = list(session_id, token)
          )
          if (nrow(record) != 1L) return(NULL)
          at <- record$created_at[[1]]
          submissions <- DBI::dbGetQuery(
            connection,
            paste(
              "SELECT submission_id, tutor, group_name AS \"group\", role,",
              "round_number AS \"round\", n1, p1, n2, p2, n3, p3, submitted_at",
              "FROM hta_game_submission_log",
              "WHERE session_id = $1 AND submitted_at <= $2"
            ),
            params = list(session_id, at)
          )
          events <- DBI::dbGetQuery(
            connection,
            paste(
              "SELECT tutor, round_number AS \"round\", recorded_at",
              "FROM hta_game_round_events WHERE session_id = $1 AND recorded_at <= $2"
            ),
            params = list(session_id, at)
          )
          evaluate_presentation(submissions, events, at, config)
        })
      })
    },
    reset = function() {
      ensure_schema()
      with_connection(function(connection) {
        DBI::dbWithTransaction(connection, {
          DBI::dbExecute(connection, "DELETE FROM hta_game_submission_log WHERE session_id = $1", params = list(session_id))
          DBI::dbExecute(connection, "DELETE FROM hta_game_round_events WHERE session_id = $1", params = list(session_id))
          DBI::dbExecute(connection, "DELETE FROM hta_game_presentations WHERE session_id = $1", params = list(session_id))
        })
      })
      invisible(TRUE)
    }
  )
}

create_game_store <- function(config) {
  mode <- tolower(config$storage$mode)
  if (identical(mode, "memory")) return(create_memory_store(config))
  if (mode %in% c("postgres", "postgresql")) return(create_postgres_store(config))
  stop("Unknown GAME_STORAGE_MODE. Use 'memory' or 'postgres'.")
}
