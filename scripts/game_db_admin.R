#!/usr/bin/env Rscript

# Read or reset only this application's three PostgreSQL tables. Never source
# app.R here: that would start the Shiny application.
args <- commandArgs(trailingOnly = TRUE)
usage <- paste(
  "Usage:",
  "  Rscript scripts/game_db_admin.R status",
  "  Rscript scripts/game_db_admin.R export SESSION_ID BACKUP_DIR",
  "  Rscript scripts/game_db_admin.R reset-session SESSION_ID BACKUP_DIR CONFIRM:SESSION_ID",
  "  Rscript scripts/game_db_admin.R reset-all BACKUP_DIR CONFIRM:ALL-GAME-DATA",
  sep = "\n"
)
if (!length(args) || args[[1]] %in% c("-h", "--help")) {
  cat(usage, "\n")
  quit(status = if (length(args)) 0L else 1L)
}

command <- args[[1]]
valid <- switch(command,
  status = length(args) == 1L,
  export = length(args) == 3L,
  `reset-session` = length(args) == 4L,
  `reset-all` = length(args) == 3L,
  FALSE
)
if (!valid) stop(usage, call. = FALSE)

script_flag <- grep("^--file=", commandArgs(), value = TRUE)
if (length(script_flag) != 1L) stop("Run this script with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", script_flag), mustWork = TRUE)
repo_dir <- dirname(dirname(script_path))
source(file.path(repo_dir, "R", "storage.R"), local = TRUE)

if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("RPostgres", quietly = TRUE)) {
  stop("Install DBI and RPostgres first.", call. = FALSE)
}
connection_args <- postgres_app_connection_args()
connection <- do.call(DBI::dbConnect, c(list(drv = RPostgres::Postgres()), connection_args))

tables <- c("hta_game_submission_log", "hta_game_round_events", "hta_game_presentations")
present <- vapply(tables, function(table) DBI::dbExistsTable(connection, table), logical(1))
if (!all(present)) {
  stop("Game tables are missing: ", paste(tables[!present], collapse = ", "),
       ". The app creates them on its first write.", call. = FALSE)
}

target <- paste0(connection_args$host, "/", connection_args$dbname)
cat("Database: ", target, "\n", sep = "")

read_table <- function(table, session_id = NULL) {
  query <- paste0("SELECT * FROM ", table)
  if (!is.null(session_id)) {
    query <- paste(query, "WHERE session_id = $1")
    return(DBI::dbGetQuery(connection, query, params = list(session_id)))
  }
  DBI::dbGetQuery(connection, query)
}

backup <- function(directory, session_id = NULL) {
  if (!nzchar(directory) || directory %in% c("/", ".", "..")) {
    stop("Choose a dedicated backup directory.", call. = FALSE)
  }
  if (file.exists(directory)) stop("Backup directory already exists; choose a new empty path.", call. = FALSE)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(directory)) stop("Could not create backup directory.", call. = FALSE)
  for (table in tables) {
    data <- read_table(table, session_id)
    utils::write.csv(data, file.path(directory, paste0(table, ".csv")), row.names = FALSE, na = "")
    cat(table, ": ", nrow(data), " rows backed up\n", sep = "")
  }
  cat("Backup: ", normalizePath(directory), "\n", sep = "")
}

if (command == "status") {
  for (table in tables) {
    cat("\n", table, "\n", sep = "")
    columns <- if (table == "hta_game_presentations") "session_id" else "session_id, tutor"
    counts <- DBI::dbGetQuery(connection, paste0(
      "SELECT ", columns, ", COUNT(*) AS rows FROM ", table,
      " GROUP BY ", columns, " ORDER BY ", columns
    ))
    if (nrow(counts)) print(counts, row.names = FALSE) else cat("(empty)\n")
  }
} else if (command == "export") {
  invisible(DBI::dbWithTransaction(connection, backup(args[[3]], args[[2]])))
} else if (command == "reset-session") {
  session_id <- args[[2]]
  if (!nzchar(session_id) || !identical(args[[4]], paste0("CONFIRM:", session_id))) {
    stop("Reset confirmation must exactly match CONFIRM:SESSION_ID.", call. = FALSE)
  }
  invisible(DBI::dbWithTransaction(connection, {
    backup(args[[3]], session_id)
    for (table in tables) {
      rows <- DBI::dbExecute(connection, paste0("DELETE FROM ", table, " WHERE session_id = $1"), params = list(session_id))
      cat(table, ": ", rows, " rows deleted\n", sep = "")
    }
  }))
} else if (command == "reset-all") {
  if (!identical(args[[3]], "CONFIRM:ALL-GAME-DATA")) {
    stop("Reset confirmation must exactly match CONFIRM:ALL-GAME-DATA.", call. = FALSE)
  }
  invisible(DBI::dbWithTransaction(connection, {
    backup(args[[2]])
    for (table in tables) {
      rows <- DBI::dbExecute(connection, paste0("DELETE FROM ", table))
      cat(table, ": ", rows, " rows deleted\n", sep = "")
    }
  }))
}
DBI::dbDisconnect(connection)
