# CLAUDE.md - ellmer.extensions

## Package Overview

- **Package name:** `ellmer.extensions`
- **Purpose:** Extend [ellmer](https://github.com/tidyverse/ellmer) with:
  - Groq provider support (`chat_groq_developer`, `ProviderGroqDeveloper`)
  - Gemini file-based batch support (`chat_gemini_extended`, `ProviderGeminiExtended`)
- **Origin:** Cloned from `groqDeveloper` and adapted with Gemini batch functionality.

## Architecture

### Provider Classes (S7)

Both provider classes are created dynamically in `.onLoad` (in `R/provider-groq.R`) because they extend ellmer classes that aren't available at package build time:

- `ProviderGroqDeveloper` extends `ellmer::ProviderOpenAICompatible` (Chat Completions API format)
- `ProviderGeminiExtended` extends `ellmer::ProviderGoogleGemini`

Method registration uses `S7::method()` calls inside `register_groq_methods()` and `register_gemini_methods()`, followed by `S7::methods_register()`.

### Key Files

| File | Purpose |
|------|---------|
| `R/chat-groq.R` | Groq chat constructor, `models_groq()`, utility functions (`key_get`, `set_default`) |
| `R/provider-groq.R` | `ProviderGroqDeveloper` class, Groq batch methods, schema methods, `.onLoad` |
| `R/chat-gemini.R` | Gemini chat constructor (`chat_gemini_extended`) |
| `R/provider-gemini.R` | `ProviderGeminiExtended` class, Gemini batch upload/submit/poll/status/retrieve methods |
| `R/reexports.R` | Re-exports ellmer generics (`batch_chat`, `parallel_chat`, etc.) |
| `R/ellmer.extensions-package.R` | Package-level documentation, `@import S7`, `@importFrom rlang %\|\|%` |

### Groq Design Notes

- Uses OpenAI Chat Completions API format (via `ProviderOpenAICompatible`)
- Schema override adds `additionalProperties: false` recursively for Groq's strict JSON validation
- Batch API: upload JSONL -> create batch job -> poll -> download results
- Batch processing at 50% cost discount, completion window 24h (usually seconds)

### Gemini Batch Design Notes

- Uses Gemini Batch API file mode:
  - Upload JSONL input file via `google_upload_init` / `google_upload_send` / `google_upload_wait`
  - Submit `models/{model}:batchGenerateContent`
  - Poll batch operation
  - Download output file via `files/*:download`
- Batch line format is normalized defensively to handle both:
  - Plain `GenerateContentResponse` lines
  - Wrapped `response/error/status` variants
- Batch method registration is done in `.onLoad`, with a defensive re-registration in `chat_gemini_extended()` to support `devtools::load_all()` workflows
- 50% cost discount, target 24-hour turnaround, 2 GB max file size, 48-hour expiry
- Structured output via `batch_chat_structured()` may not be supported on all Gemini models (HTTP 400); integration tests handle this gracefully

## Environment Variables

- Groq: `GROQ_API_KEY`
- Gemini: `GEMINI_API_KEY` (or `GOOGLE_API_KEY`)
- Keep `.Renviron` local only; **never commit it**
- `.Renviron.example` contains placeholder values only

## Standard Workflow

Run from package root:

1. `Rscript -e "devtools::document()"`
2. `Rscript -e "devtools::test()"`
3. `Rscript -e "devtools::lint()"` (run at end)
4. `Rscript -e "devtools::check()"`

## Testing Notes

- **Groq unit tests** (`test-provider-groq.R`): Run offline with dummy credentials; test class structure, schema generation, batch support flags.
- **Groq integration tests** (`test-api-integration.R`): Require `GROQ_API_KEY`; test live chat, structured output, and batch processing.
- **Gemini unit tests** (`test-provider-gemini.R`): Run offline; test class structure, batch support, and helper functions (`gemini_extract_index`, `gemini_json_fallback`, `gemini_normalize_result`).
- **Gemini integration tests** (`test-gemini-batch-integration.R`): Require `GEMINI_API_KEY` or `GOOGLE_API_KEY`; poll with bounded timeout (120s) and skip if batch does not finish. A skip is expected behavior under queue pressure.
- **Linting** configured via `.lintr` with `line_length_linter(120)`, `object_name_linter = NULL` (S7 PascalCase), `object_length_linter = NULL`.

## Repo Hygiene

- `.Renviron` is gitignored and purged from git history.
- If `.Renviron` is accidentally committed, remove from tracking immediately and follow the purge procedure in AGENTS.md.
- If a secret is ever pushed or shared, **rotate keys immediately**.

## Known Issues and Limitations

- `ProviderGeminiExtended` is not exported (by design; users should use `chat_gemini_extended()`).
- Groq structured outputs do not support streaming or tool use.
- Gemini batch jobs can remain queued for extended periods; integration tests handle this gracefully.
- The `.onLoad` error handler silently defers initialization failures (needed for documentation builds); users see informative errors when they try to use provider functions.
- Heavy reliance on `asNamespace("ellmer")` for internal functions -- fragile if ellmer renames internals.

## Dependencies

Core: `ellmer`, `S7`, `purrr`, `cli`, `httr2`, `curl`, `withr`, `jsonlite`, `rlang`
Suggests: `testthat`, `lifecycle`

## CI / Publishing

- GitHub repo: https://github.com/xmarquez/ellmer.extensions
- pkgdown site: https://xmarquez.github.io/ellmer.extensions/
- R-CMD-check: `.github/workflows/R-CMD-check.yaml` (push to main/master, PRs)
- pkgdown: `.github/workflows/pkgdown.yaml`
