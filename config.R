# Stable classroom configuration for the Shiny game.
#
# Edit this file before deployment when tutors, groups, or scenario values
# change. Live state (joined players, current rounds, and agreements) is kept by
# the storage backend and does not belong here.

game_config <- list(
  session_id = "hta-demo",
  session_title = list(en = "HTA negotiation game", nl = "HTA-onderhandelingsspel"),
  tutors = c("Tutor 1", "Tutor 2"),
  groups = c("A", "B", "C", "D"),
  roles = list(
    en = c(HCP = "Healthcare Payer (HCP)", HTD = "Health Technology Developer (HTD)"),
    nl = c(HCP = "Zorgbetaler (HCP)", HTD = "Ontwikkelaar gezondheidstechnologie (HTD)")
  ),
  poll_interval_ms = 2000,
  max_patients = 500,
  storage = list(
    # "memory" is intended for local testing. Data is lost when the app stops.
    # The storage interface is deliberately separate so Google Sheets can be
    # connected without changing the UI or scoring code.
    mode = Sys.getenv("GAME_STORAGE_MODE", unset = "memory")
  ),
  rounds = list(
    list(
      number = 1L,
      title = list(en = "Baseline negotiation", nl = "Eerste onderhandeling"),
      public_summary = list(
        en = c("500 patients may benefit from the treatment.", "The treatment produces 0.6 QALYs per treated patient per year.", "The list price is EUR 150,000 per patient per year.", "The HCP budget for this treatment is EUR 45 million."),
        nl = c("500 patiënten kunnen baat hebben bij de behandeling.", "De behandeling levert per behandelde patiënt 0,6 QALY per jaar op.", "De lijstprijs bedraagt EUR 150.000 per patiënt per jaar.", "Het HCP-budget voor deze behandeling bedraagt EUR 45 miljoen.")
      ),
      confidential = list(en = list(HCP = character(), HTD = character()), nl = list(HCP = character(), HTD = character())),
      settings = list(
        n_pats = 500,
        qaly_yr = 0.6,
        gov_max_budget = 45000000,
        wtp = 50000,
        list_price = 150000,
        sales_expect = 0.8,
        hospital_capacity = 0,
        hospital_price = 0
      )
    ),
    list(
      number = 2L,
      title = list(en = "Revised evidence", nl = "Herzien bewijs"),
      public_summary = list(
        en = c("A new negotiation round has started.", "The maximum eligible population remains 500 patients."),
        nl = c("Een nieuwe onderhandelingsronde is gestart.", "De maximale patiëntpopulatie blijft 500.")
      ),
      confidential = list(
        en = list(HCP = character(), HTD = c("A new cost-utility analysis revises the health gain from 0.6 to 0.3 QALYs per patient per year.", "The reduction is caused by more frequent adverse events, including auto-immune responses, observed in daily practice.", "This information is under embargo and must not be shared with the HCP.")),
        nl = list(HCP = character(), HTD = c("Een nieuwe kosteneffectiviteitsanalyse herziet de gezondheidswinst van 0,6 naar 0,3 QALY per patiënt per jaar.", "De afname komt door vaker optredende bijwerkingen, waaronder auto-immuunreacties, die in de dagelijkse praktijk zijn waargenomen.", "Deze informatie valt onder embargo en mag niet met de HCP worden gedeeld."))
      ),
      settings = list(
        n_pats = 500,
        qaly_yr = 0.3,
        gov_max_budget = 45000000,
        wtp = 50000,
        list_price = 150000,
        sales_expect = 0.8,
        hospital_capacity = 0,
        hospital_price = 0
      )
    ),
    list(
      number = 3L,
      title = list(en = "Budget and hospital production", nl = "Budget en ziekenhuisproductie"),
      public_summary = list(
        en = c("The final negotiation round has started.", "The maximum eligible population remains 500 patients."),
        nl = c("De laatste onderhandelingsronde is gestart.", "De maximale patiëntpopulatie blijft 500.")
      ),
      confidential = list(
        en = list(HCP = c("The health gain is now estimated at 0.3 QALYs per patient per year.", "The available treatment budget has been reduced to EUR 25 million.", "Academic hospitals can produce treatment for EUR 40,000 per patient for at most 150 patients.", "Hospital production must be paid from the same HCP budget."), HTD = character()),
        nl = list(HCP = c("De gezondheidswinst wordt nu geschat op 0,3 QALY per patiënt per jaar.", "Het beschikbare behandelbudget is verlaagd naar EUR 25 miljoen.", "Academische ziekenhuizen kunnen voor maximaal 150 patiënten produceren tegen EUR 40.000 per patiënt.", "Ziekenhuisproductie moet uit hetzelfde HCP-budget worden betaald."), HTD = character())
      ),
      settings = list(
        n_pats = 500,
        qaly_yr = 0.3,
        gov_max_budget = 25000000,
        wtp = 50000,
        list_price = 150000,
        sales_expect = 0.8,
        hospital_capacity = 150,
        hospital_price = 40000
      )
    )
  )
)
