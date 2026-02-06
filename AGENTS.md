# AGENTS.md

## Package Overview

- Package name: `ellmer.extensions`
- Purpose: Extend [ellmer](https://github.com/tidyverse/ellmer) with:
  - Groq provider support (`chat_groq_developer`,
    `ProviderGroqDeveloper`)
  - Gemini file-based batch support (`chat_gemini_extended`,
    `ProviderGeminiExtended`)
- Origin: Cloned from `groqDeveloper` and adapted with Gemini batch
  functionality.
- See `CLAUDE.md` for full architecture and design details.

## Key Files

| File                                             | Purpose                                                                                                                            |
|--------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------|
| `R/chat-groq.R`                                  | Groq chat constructor, [`models_groq()`](https://xmarquez.github.io/ellmer.extensions/reference/models_groq.md), utility functions |
| `R/provider-groq.R`                              | `ProviderGroqDeveloper` class, Groq batch/schema methods, `.onLoad`                                                                |
| `R/chat-gemini.R`                                | Gemini chat constructor (`chat_gemini_extended`)                                                                                   |
| `R/provider-gemini.R`                            | `ProviderGeminiExtended` class, Gemini batch methods                                                                               |
| `R/reexports.R`                                  | Re-exports ellmer generics (`batch_chat`, `parallel_chat`, etc.)                                                                   |
| `R/ellmer.extensions-package.R`                  | Package-level docs, `@import S7`, `@importFrom rlang %||%`                                                                         |
| `tests/testthat/test-provider-groq.R`            | Groq offline unit tests                                                                                                            |
| `tests/testthat/test-provider-gemini.R`          | Gemini offline unit tests                                                                                                          |
| `tests/testthat/test-api-integration.R`          | Groq live integration tests                                                                                                        |
| `tests/testthat/test-gemini-batch-integration.R` | Gemini live integration tests                                                                                                      |

## Architecture

- S7 provider classes created dynamically in `.onLoad` (extend ellmer
  parent classes)
- `ProviderGroqDeveloper` extends `ProviderOpenAICompatible` (Chat
  Completions format)
- `ProviderGeminiExtended` extends `ProviderGoogleGemini`
- Both use `register_*_methods()` +
  [`S7::methods_register()`](https://rconsortium.github.io/S7/reference/methods_register.html)
- ellmer internals accessed via `asNamespace("ellmer")` throughout
- `%||%` imported from `rlang`

## Environment Variables

- Groq: `GROQ_API_KEY`
- Gemini: `GEMINI_API_KEY` (or `GOOGLE_API_KEY`)
- Keep `.Renviron` local only; do not commit it.
- `.Renviron.example` contains placeholder values only.

## Standard Workflow

Run from package root:

1.  `Rscript -e "devtools::document()"`
2.  `Rscript -e "devtools::test()"`
3.  `Rscript -e "devtools::lint()"` (run at end)
4.  `Rscript -e "devtools::check()"`

## Testing Notes

- Groq unit tests run offline with dummy credentials.
- Groq integration tests require `GROQ_API_KEY`.
- Gemini unit tests run offline; cover helper functions
  (`gemini_extract_index`, `gemini_json_fallback`,
  `gemini_normalize_result`).
- Gemini integration tests require `GEMINI_API_KEY` or `GOOGLE_API_KEY`;
  poll with bounded timeout and skip if batch does not finish.
- Gemini `batch_chat_structured` may return HTTP 400 for some models;
  test skips gracefully.
- Linting via `.lintr`: `line_length_linter(120)`, S7 PascalCase names
  suppressed.

## CI

- R-CMD-check: `.github/workflows/R-CMD-check.yaml` (push to
  main/master, PRs)
- pkgdown: `.github/workflows/pkgdown.yaml`

## Repo Hygiene

- `.Renviron` is gitignored and purged from git history.
- `data-raw/` is gitignored (development scripts only).
- `docs/` is gitignored (built by CI via pkgdown).
- If a secret is ever pushed or shared, rotate keys immediately.

## Known Issues

- `ProviderGeminiExtended` not exported by design (use
  [`chat_gemini_extended()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_gemini_extended.md)).
- Groq structured outputs: no streaming or tool use support.
- Gemini batch jobs can remain queued for extended periods.
- `.onLoad` uses separate `tryCatch(suppressMessages(...))` blocks per
  provider; one failing doesn’t block the other.
- Heavy reliance on `asNamespace("ellmer")` internals – fragile if
  ellmer changes.
- S7 subclassing segfaults on Windows R 4.5.1 outside `.onLoad`;
  defensive re-registration needed.
- `S7::method<-` prints “Overwriting method” messages; all registration
  wrapped in
  [`suppressMessages()`](https://rdrr.io/r/base/message.html).
- Gemini `batch_retrieve` checks multiple paths for `responsesFile` (API
  structure varies).
- `lifecycle` in Suggests; used only for roxygen badge macros at doc-gen
  time.
