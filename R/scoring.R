linear_points <- function(value_low, value_high, points_low, points_high, value) {
  if (!is.finite(value) || value_high == value_low) {
    return(NA_real_)
  }

  points_low + (value - value_low) *
    (points_high - points_low) / (value_high - value_low)
}

expected_sales_points <- function(manufacturer_sales, settings) {
  if (!is.finite(manufacturer_sales) || manufacturer_sales <= 0) {
    return(0)
  }

  values <- c(
    settings$n_pats * settings$wtp,
    settings$n_pats * settings$list_price * settings$sales_expect,
    settings$n_pats * settings$list_price
  )
  points <- c(0, 10, 12)

  stats::predict(
    stats::lm(points ~ log(values)),
    newdata = data.frame(values = manufacturer_sales)
  )[[1]]
}

clamp_score <- function(value) {
  max(0, min(10, value))
}

calculate_scores <- function(agreements, rounds) {
  if (nrow(agreements) == 0) {
    return(data.frame())
  }

  scored <- lapply(seq_len(nrow(agreements)), function(index) {
    agreement <- agreements[index, , drop = FALSE]
    round_number <- as.integer(agreement$round[[1]])
    settings <- rounds[[round_number]]$settings

    patient_numbers <- as.numeric(unlist(
      agreement[1, c("n1", "n2", "n3")], use.names = FALSE
    ))
    prices <- as.numeric(unlist(
      agreement[1, c("p1", "p2", "p3")], use.names = FALSE
    ))
    patients_treated <- sum(patient_numbers)
    budget_impact <- sum(patient_numbers * prices)
    manufacturer_sales <- if (round_number == 3L) {
      sum(patient_numbers[2:3] * prices[2:3])
    } else {
      budget_impact
    }

    government_balance <- settings$gov_max_budget - budget_impact
    qalys_gained <- patients_treated * settings$qaly_yr
    crowd_out <- min(0, government_balance / settings$wtp)
    qaly_balance <- qalys_gained + crowd_out
    qaly_max_loss <- -(
      settings$list_price * settings$n_pats - settings$gov_max_budget
    ) / settings$wtp
    qaly_max_gain <- settings$n_pats * settings$qaly_yr

    qaly_points <- linear_points(
      qaly_max_loss, qaly_max_gain, -10, 10, qaly_balance
    )
    population_points <- linear_points(
      0, settings$n_pats, 0, 10, patients_treated
    )

    manufacturer_low <- if (round_number == 3L) {
      (settings$n_pats - settings$hospital_capacity) * settings$wtp -
        settings$hospital_capacity * settings$hospital_price
    } else {
      settings$n_pats * settings$wtp
    }
    manufacturer_high <- if (round_number == 3L) {
      (settings$n_pats - settings$hospital_capacity) * settings$list_price
    } else {
      settings$n_pats * settings$list_price
    }
    sales_points <- linear_points(
      manufacturer_low, manufacturer_high, 0, 10, manufacturer_sales
    )
    expectation_points <- expected_sales_points(manufacturer_sales, settings)

    data.frame(
      tutor = agreement$tutor,
      group = agreement$group,
      round = round_number,
      patients_treated = patients_treated,
      patients_untreated = settings$n_pats - patients_treated,
      budget_impact = budget_impact,
      government_balance = government_balance,
      crowd_out = crowd_out,
      manufacturer_sales = manufacturer_sales,
      hcp_score = round(clamp_score(qaly_points * 0.6 + population_points * 0.4), 1),
      htd_score = round(clamp_score(sales_points * 0.6 + expectation_points * 0.4), 1),
      updated_at = agreement$updated_at,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, scored)
}
