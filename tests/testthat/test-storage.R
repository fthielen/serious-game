library(shiny)

source(file.path("..", "..", "config.R"), local = TRUE)
source(file.path("..", "..", "R", "storage.R"), local = TRUE)

test_that("the memory store creates every tutor and group combination", {
  store <- create_memory_store(game_config)

  expect_equal(
    nrow(store$get_state()),
    length(game_config$tutors) * length(game_config$groups)
  )
  expect_true(all(store$get_state()$current_round == 0))
})

test_that("rounds advance and stop after the final round", {
  store <- create_memory_store(game_config)

  for (index in seq_len(length(game_config$rounds) + 3L)) {
    store$advance("Tutor 1", "A")
  }

  selected <- subset(store$get_state(), tutor == "Tutor 1" & group == "A")
  expect_equal(selected$current_round, length(game_config$rounds) + 1L)
  expect_equal(selected$status, "Finished")
})

test_that("a later agreement replaces an earlier group-round submission", {
  store <- create_memory_store(game_config)
  first <- data.frame(
    tutor = "Tutor 1", group = "A", round = 1L,
    n1 = 100, p1 = 50000, n2 = 0, p2 = 0, n3 = 0, p3 = 0,
    updated_at = "first", stringsAsFactors = FALSE
  )
  second <- first
  second$n1 <- 200
  second$updated_at <- "second"

  store$save_agreement(first)
  store$save_agreement(second)

  expect_equal(nrow(store$get_agreements()), 1)
  expect_equal(store$get_agreements()$n1, 200)
})

test_that("results presentation publication is reset with the session", {
  store <- create_memory_store(game_config)

  expect_false(store$is_results_published())
  store$publish_results()
  expect_true(store$is_results_published())
  store$reset()
  expect_false(store$is_results_published())
})
