source(file.path("..", "..", "config.R"), local = TRUE)
source(file.path("..", "..", "R", "storage.R"), local = TRUE)

test_submission <- function(tutor = game_config$tutors[[1]], group = game_config$groups[[1]],
                            round = 1L, id = "submission-one", n1 = 100, role = "HCP") {
  data.frame(
    submission_id = id, tutor = tutor, group = group, role = role,
    round = round, n1 = n1, p1 = 50000, n2 = 0, p2 = 0, n3 = 0, p3 = 0,
    stringsAsFactors = FALSE
  )
}

test_that("PostgreSQL URLs are parsed without logging credentials", {
  args <- parse_postgres_url(
    "postgresql://game%40user:p%40ss@example.test:5433/classroom%20game?sslmode=require"
  )
  expect_equal(args$user, "game@user")
  expect_equal(args$password, "p@ss")
  expect_equal(args$host, "example.test")
  expect_equal(args$port, 5433L)
  expect_equal(args$dbname, "classroom game")
  expect_equal(args$sslmode, "require")
})

test_that("tutor round markers are forward-only and scoped to one tutor", {
  store <- create_memory_store(game_config)
  first <- game_config$tutors[[1]]
  second <- game_config$tutors[[2]]
  for (round in 1:4) {
    event <- store$record_next_round(first)
    expect_equal(event$round, round)
    expect_equal(event$tutor, first)
  }
  expect_null(store$record_next_round(first))
  expect_equal(store$record_next_round(second)$round, 1L)
})

test_that("rapid tutor clicks can record separate rounds at the same instant", {
  instant <- as.POSIXct("2026-09-21 09:00:00", tz = "UTC")
  store <- create_memory_store(game_config, clock = function() instant)
  tutor <- game_config$tutors[[1]]
  events <- lapply(seq_len(length(game_config$rounds) + 1L), function(index) {
    store$record_next_round(tutor)
  })
  expect_equal(vapply(events, function(event) event$round[[1]], integer(1)), 1:4)
  expect_true(all(vapply(events, function(event) event$recorded_at[[1]] == instant, logical(1))))
  expect_null(store$record_next_round(tutor))
})

test_that("submissions are append-only and a retried ID is idempotent", {
  store <- create_memory_store(game_config)
  first <- test_submission()
  corrected <- test_submission(id = "submission-two", n1 = 200)
  first_receipt <- store$save_agreement(first)
  expect_equal(store$save_agreement(first), first_receipt)
  store$save_agreement(corrected)
  link <- store$create_presentation()
  snapshot <- store$get_presentation(link$token)
  expect_equal(nrow(snapshot$agreements), 1L)
  expect_equal(snapshot$agreements$n1, 200)
  expect_equal(snapshot$audit$status[[1]], "marker_unverified")
})

test_that("the latest submission inside tutor timestamps wins", {
  tutor <- game_config$tutors[[1]]
  group <- game_config$groups[[1]]
  at <- as.POSIXct("2026-09-21 09:00:00", tz = "UTC")
  events <- data.frame(
    tutor = rep(tutor, 4), round = 1:4,
    recorded_at = at + c(0, 600, 1200, 1800)
  )
  submissions <- do.call(rbind, lapply(seq_along(c(300, 720, 900, 1500)), function(index) {
    row <- test_submission(
      tutor, group,
      round = c(1L, 1L, 2L, 3L)[[index]],
      id = paste0("submission-", index),
      n1 = c(100, 200, 300, 400)[[index]]
    )
    row$submitted_at <- at + c(300, 720, 900, 1500)[[index]]
    row
  }))
  snapshot <- evaluate_presentation(submissions, events, at + 2400, game_config)
  chosen <- snapshot$agreements[snapshot$agreements$tutor == tutor &
                                  snapshot$agreements$group == group, , drop = FALSE]
  expect_equal(chosen$n1, c(100, 300, 400))
  expect_equal(snapshot$audit$status[[1]], "accepted")
  expect_true(any(snapshot$audit$status == "missing"))
})

test_that("outside-window submissions are flagged, not scored", {
  tutor <- game_config$tutors[[1]]
  group <- game_config$groups[[1]]
  at <- as.POSIXct("2026-09-21 09:00:00", tz = "UTC")
  events <- data.frame(tutor = c(tutor, tutor), round = c(1L, 2L),
                       recorded_at = at + c(0, 600))
  submissions <- test_submission(tutor, group)
  submissions$submitted_at <- at + 601
  snapshot <- evaluate_presentation(submissions, events, at + 1200, game_config)
  expect_equal(nrow(snapshot$agreements), 0L)
  expect_equal(snapshot$audit$status[[1]], "outside_window")
})

test_that("a presentation link is a fixed cutoff and reset revokes it", {
  tick <- local({
    now <- as.POSIXct("2026-09-21 09:00:00", tz = "UTC")
    function() { now <<- now + 60; now }
  })
  store <- create_memory_store(game_config, clock = tick)
  store$record_next_round(game_config$tutors[[1]])
  store$save_agreement(test_submission())
  link <- store$create_presentation()
  store$save_agreement(test_submission(id = "later", n1 = 200))
  expect_equal(store$get_presentation(link$token)$agreements$n1, 100)
  expect_null(store$get_presentation("not-a-token"))
  store$reset()
  expect_null(store$get_presentation(link$token))
})

test_that("round 3 submissions are HCP-only", {
  store <- create_memory_store(game_config)
  expect_error(store$save_agreement(test_submission(round = 3L, role = "HTD")))
  expect_no_error(store$save_agreement(test_submission(round = 3L, role = "HCP")))
})
