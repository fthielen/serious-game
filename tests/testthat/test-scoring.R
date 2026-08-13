source(file.path("..", "..", "config.R"), local = TRUE)
source(file.path("..", "..", "R", "scoring.R"), local = TRUE)

agreement <- function(round, n1, p1, n2 = 0, p2 = 0, n3 = 0, p3 = 0) {
  data.frame(
    tutor = "Tutor 1",
    group = "A",
    round = round,
    n1 = n1,
    p1 = p1,
    n2 = n2,
    p2 = p2,
    n3 = n3,
    p3 = p3,
    updated_at = "2026-01-01 UTC",
    stringsAsFactors = FALSE
  )
}

test_that("scores stay inside the documented range", {
  result <- calculate_scores(
    agreement(round = 1, n1 = 500, p1 = 90000),
    game_config$rounds
  )

  expect_gte(result$hcp_score, 0)
  expect_lte(result$hcp_score, 10)
  expect_gte(result$htd_score, 0)
  expect_lte(result$htd_score, 10)
})

test_that("round three excludes hospital production from manufacturer sales", {
  result <- calculate_scores(
    agreement(round = 3, n1 = 150, p1 = 40000, n2 = 350, p2 = 50000),
    game_config$rounds
  )

  expect_equal(result$budget_impact, 23500000)
  expect_equal(result$manufacturer_sales, 17500000)
})

test_that("an empty agreement table produces an empty result", {
  expect_equal(nrow(calculate_scores(data.frame(), game_config$rounds)), 0)
})
