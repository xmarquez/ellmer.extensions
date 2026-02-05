# AGENTS.md

## Package Overview

- Package name: `ellmer.extensions`
- Purpose: Extend `ellmer` with:
  - Groq provider support (`chat_groq_developer`, `ProviderGroqDeveloper`)
  - Gemini file-based batch support (`chat_gemini_extended`, `ProviderGeminiExtended`)
- This repository was cloned from `groqDeveloper` and then adapted with package identity updates plus Gemini batch functionality.

## Key Files

- `R/chat-groq.R`: Groq chat constructor and Groq utilities.
- `R/provider-groq.R`: Groq provider methods, S7 registrations, `.onLoad`.
- `R/chat-gemini.R`: Gemini chat constructor (`chat_gemini_extended`).
- `R/provider-gemini.R`: Gemini batch upload/submit/poll/status/retrieve/result methods.
- `tests/testthat/test-api-integration.R`: Groq live integration tests.
- `tests/testthat/test-gemini-batch-integration.R`: Gemini live integration tests.

## Gemini Batch Design Notes

- Uses Gemini Batch API file mode:
  - Upload JSONL input file
  - Submit `models/{model}:batchGenerateContent`
  - Poll batch operation (`batches/...`)
  - Download output file via `files/*:download`
- Batch line format is normalized defensively to handle both:
  - Plain `GenerateContentResponse` lines
  - Wrapped `response/error/status` variants
- Batch method registration is done in `.onLoad`, with a defensive re-registration in `chat_gemini_extended()` to support `devtools::load_all()` workflows.

## Environment Variables

- Groq: `GROQ_API_KEY`
- Gemini: `GEMINI_API_KEY` (or `GOOGLE_API_KEY`)
- `.Renviron` is intentionally present in this repo by request.

## Standard Workflow

Run from package root:

1. `Rscript -e "devtools::document()"`
2. `Rscript -e "devtools::test()"`
3. `Rscript -e "devtools::lint()"` (run at end)
4. `Rscript -e "devtools::check()"`

## Testing Notes

- Gemini batch integration can remain queued for extended periods.
- `test-gemini-batch-integration.R` polls with a bounded timeout and skips if the batch does not finish in time.
- A skip in that test is expected behavior under queue pressure; build/check should still pass.
