# AGENTS.md

## Package Overview

- Package name: `ellmer.extensions`
- Purpose: Preserve backward-compatible Groq, Gemini, and Anthropic entry points,
  delegate to native [ellmer](https://github.com/tidyverse/ellmer) features when
  available, and retain opt-in Gemini batch context caching.
- Origin: Cloned from `groqDeveloper` and adapted with Gemini batch functionality.
- See `CLAUDE.md` for full architecture and design details.

## Key Files

| File | Purpose |
|------|---------|
| `R/chat-groq.R` | Groq chat constructor, `models_groq()`, utility functions |
| `R/provider-groq.R` | Groq reasoning forwarding, legacy batch compatibility, `.onLoad` |
| `R/chat-gemini.R` | Gemini chat constructor (`chat_gemini_extended`) |
| `R/provider-gemini.R` | Native Gemini delegation, legacy batches, context caching |
| `R/chat-anthropic.R` | Anthropic compatibility constructor |
| `R/provider-anthropic.R` | Legacy Anthropic thinking/structured output methods |
| `R/reexports.R` | Re-exports ellmer generics (`batch_chat`, `parallel_chat`, etc.) |
| `R/ellmer.extensions-package.R` | Package-level docs, `@import S7`, `@importFrom rlang %||%` |
| `tests/testthat/test-provider-groq.R` | Groq offline unit tests |
| `tests/testthat/test-provider-gemini.R` | Gemini offline unit tests |
| `tests/testthat/test-api-integration.R` | Groq live integration tests |
| `tests/testthat/test-gemini-batch-integration.R` | Gemini live integration tests |

## Architecture

- S7 provider classes created dynamically in `.onLoad` (extend ellmer parent classes)
- `ProviderGroqDeveloper` extends native `ProviderGroq` when available, otherwise `ProviderOpenAICompatible`
- `ProviderGeminiExtended` extends `ProviderGoogleGemini`
- `ProviderAnthropicExtended` extends `ProviderAnthropic`
- All use `register_*_methods()` + `S7::methods_register()`
- ellmer internals accessed via `asNamespace("ellmer")` throughout
- `%||%` imported from `rlang`

## Environment Variables

- Groq: `GROQ_API_KEY`
- Gemini: `GEMINI_API_KEY` (or `GOOGLE_API_KEY`)
- Keep `.Renviron` local only; do not commit it.
- `.Renviron.example` contains placeholder values only.

## Standard Workflow

Run from package root:

1. `Rscript -e "devtools::document()"`
2. `Rscript -e "devtools::test()"`
3. `Rscript -e "devtools::lint()"` (run at end)
4. `Rscript -e "devtools::check()"`

## Testing Notes

- Groq unit tests run offline with dummy credentials.
- Offline tests emphasize request bodies and real provider fixtures.
- Live Groq/Gemini smoke tests require `ELLMER_EXTENSIONS_RUN_LIVE_TESTS=true`
  plus the provider key and poll for at most 120 seconds.
- Linting via `.lintr`: `line_length_linter(120)`, S7 PascalCase names suppressed.

## CI

- R-CMD-check: `.github/workflows/R-CMD-check.yaml` (push to main/master, PRs)
- Compatibility CI checks ellmer 0.4.0 and ellmer development.
- pkgdown: `.github/workflows/pkgdown.yaml`

## Repo Hygiene

- `.Renviron` is gitignored and purged from git history.
- `data-raw/` is gitignored (development scripts only).
- `docs/` is gitignored (built by CI via pkgdown).
- If a secret is ever pushed or shared, rotate keys immediately.

## Known Issues

- `ProviderGeminiExtended` not exported by design (use `chat_gemini_extended()`).
- Groq structured outputs: no streaming or tool use support.
- Gemini batch jobs can remain queued for extended periods.
- `.onLoad` fails loudly if any provider cannot initialize; do not restore silent error handlers.
- Heavy reliance on `asNamespace("ellmer")` internals -- fragile if ellmer changes.
- S7 subclassing can segfault on Windows R 4.5.1 outside `.onLoad`; do not defensively re-register in constructors.
- `S7::method<-` prints "Overwriting method" messages; all registration wrapped in `suppressMessages()`.
- Native ellmer owns ordinary Gemini batches when available; the local path is for ellmer 0.4.0 and cached batches.
- `lifecycle` in Suggests; used only for roxygen badge macros at doc-gen time.
