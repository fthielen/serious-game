# Instructions for AI agents

This file applies to the entire repository. Read it together with
[`_MAP.md`](_MAP.md) and [`README.md`](README.md) before making changes.

## Project purpose

This repository supports an HTA classroom negotiation game. Students work in
an HCP or HTD role and negotiate access and prices for an expensive treatment
over three rounds. Role-specific information is confidential.

The repository currently contains two distinct workflows:

1. **Legacy production workflow:** Google Form → Google Sheet →
   `calculations.R` → `presentations/after_game.qmd`.
2. **Shiny prototype:** `app.R` with replaceable storage, live round control,
   confidential information, agreement submission, and a live closing deck.

Do not silently merge, delete, or redirect one workflow into the other. The
legacy workflow remains available while the Shiny version is developed.

## Start here

Before editing:

1. Read `_MAP.md` for the current architecture, completed work, and open items.
2. Read the relevant source files instead of relying only on generated HTML.
3. Check `git status --short`. The worktree may contain deliberate user work;
   preserve unrelated changes.
4. Determine whether the task concerns the legacy workflow, the Shiny
   prototype, or both.

## Source-of-truth files

| Concern | Source of truth |
|---|---|
| Shiny application and live results deck | `app.R` |
| Tutors, group labels, roles, scenario values, and confidential news | `config.R` |
| English and Dutch interface copy | `R/i18n.R` |
| Shiny scoring implementation | `R/scoring.R` |
| Shiny state/storage contract | `R/storage.R` |
| App styling | `www/styles.css` |
| Live results-deck styling and controls | `www/presentation.css`, `www/presentation.js` |
| Shared logo served by Shiny | `www/eshpm-logo.png` |
| English static introduction | `presentations/before_game.qmd` |
| Dutch static introduction | `presentations/before_game_nl.qmd` |
| Static presentation styling | `presentations/logo.css` |
| Legacy Google Sheet calculation | `calculations.R` |
| Legacy closing presentation | `presentations/after_game.qmd` |
| Confidential legacy news pages | `news_flashes/htd.qmd`, `news_flashes/hcp.qmd` |

Generated `.html` files are outputs, not primary editing targets. Modify the
corresponding `.qmd`, R, CSS, or JavaScript source and render again.

## Non-negotiable product rules

### Group identity

- Players join with **tutor, negotiation group, and role only**.
- Do not reintroduce names, nicknames, email addresses, or other personal
  identifiers unless the user explicitly changes this requirement.
- The role selection is required because it controls confidential information.

### Confidentiality

- Round 2 confidential information is visible only to HTD.
- Round 3 confidential information is visible only to HCP.
- Never expose confidential copy in shared status tables, URLs, client-side
  data intended for all roles, or the facilitator opening deck.
- When changing round logic, test both roles separately.

### Languages

- The Shiny interface supports English (`en`) and Dutch (`nl`).
- Every new interface key must be added to both dictionaries in `R/i18n.R`.
- Keep the key sets identical.
- Scenario text belongs in bilingual entries in `config.R`, not in `app.R`.
- The active language must apply consistently to player, staff, and live
  presentation views.

### Theme and branding

- The app supports light and dark modes.
- Preserve readable contrast in both modes.
- Use the supplied ESHPM logo from `www/eshpm-logo.png`; do not recreate the
  school name as an improvised text logo.
- The source image added by the user is `eshpm-logo.png` at repository root.
  `www/eshpm-logo.png` is the PNG web asset used by the application and decks.
- The visual system uses ESHPM deep green, purple, warm neutral surfaces, and
  restrained rainbow accents.
- Animated rainbow frames should highlight important elements only. Preserve
  the `prefers-reduced-motion` behavior.
- Opening and closing slides use a brighter purple treatment with white text
  and a light backing behind the logo.

### Presentations

- The opening presentation is static and must work before a game begins.
- Maintain matched English and Dutch opening decks.
- The Shiny closing deck is generated from current in-memory results and is
  implemented inside `app.R`; it does not source `calculations.R`.
- The legacy closing deck is different: rendering
  `presentations/after_game.qmd` sources `calculations.R`, reads the Google
  Sheet, and recalculates results.
- Do not render the legacy closing deck casually: it requires network access,
  valid Google authorization, a checked `game_date`, and valid Sheet data.

## Shiny architecture rules

- Keep classroom configuration in `config.R`; do not scatter tutor, group,
  budget, price, or round constants through the UI.
- Keep scoring pure and testable in `R/scoring.R`.
- Keep persistence behind the interface returned by `create_game_store()`.
- The only implemented backend is currently `memory`; its data disappears when
  the R process stops.
- Do not describe the prototype as production-ready until persistent storage,
  deployment configuration, and a non-demo staff PIN are implemented and
  verified.
- A later submission for the same tutor/group/round replaces the prior one.
- Round 3 tier 1 represents hospital production and is excluded from HTD sales.
- Staff authentication uses `STAFF_PIN`. The `demo` fallback is local-only and
  must never be used for a public deployment.
- The presentation route is `?view=results&lang=<en|nl>&theme=<light|dark>`.

## Scoring-change policy

The current scoring model is inherited from the legacy calculation and has
known incentive problems documented in `_MAP.md`. Do not “clean up” or replace
it as a side effect of unrelated work.

Any scoring change must:

1. be explicitly authorized;
2. define expected behavior for no agreement;
3. include scenario tests for all three rounds;
4. compare old and proposed scores on representative agreements;
5. update both `R/scoring.R` and, if the legacy workflow is still in scope,
   `calculations.R`;
6. update explanatory copy and results presentation content as needed.

## Editing and rendering presentations

From `presentations/`, rebuild the bundled Shiny opening decks with:

```sh
quarto render before_game.qmd \
  --output opening-presentation-en.html \
  --output-dir ../www

quarto render before_game_nl.qmd \
  --output opening-presentation-nl.html \
  --output-dir ../www
```

Refresh the tracked English standalone output with:

```sh
quarto render before_game.qmd
```

After presentation changes, inspect at least the first, a representative
interior, and the final slide in both languages. For broad layout changes,
inspect every slide. Check logo position, clipping, title wrapping, contrast,
and controls at projector dimensions.

## Validation checklist

Run after relevant changes:

```sh
Rscript -e '
  invisible(parse("app.R"))
  invisible(parse("config.R"))
  invisible(parse("R/i18n.R"))
  source("R/i18n.R")
  stopifnot(setequal(names(translations$en), names(translations$nl)))
'

Rscript tests/testthat.R
git diff --check
```

For UI changes, run the app locally and verify proportionately:

```r
Sys.setenv(STAFF_PIN = "a-local-test-pin")
shiny::runApp()
```

Minimum browser checks for material Shiny changes:

- English and Dutch join screens;
- light and dark modes;
- tutor/group/role joining without personal identifiers;
- staff PIN and controls;
- round advancement and return to player view;
- HCP and HTD confidential-information isolation;
- agreement submission and replacement;
- static opening-deck language/theme link;
- live results-deck creation, navigation, tables, logo, and contrast;
- reset test data before handoff.

## Documentation expectations

- Update `README.md` when user-facing setup or operation changes.
- Update `_MAP.md` after significant architectural, workflow, schema, or design
  changes. Add completed work to its history and keep open issues current.
- Update this file only when future-agent operating rules change.
- Never place credentials, OAuth tokens, or private classroom data in the
  repository or documentation.

## Current safe next steps

The most likely future work is:

1. agree on a revised scoring model;
2. add explicit agreement/no-agreement status;
3. implement persistent storage suitable for shinyapps.io;
4. add deployment configuration and production secrets;
5. conduct a multi-browser classroom simulation before live use.

