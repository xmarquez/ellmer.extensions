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

Method registration uses `S7::method()` calls inside `register_groq_methods()` and `register_gemini_methods()`, followed by `S7::methods_register()`. Each provider's class creation and method registration is wrapped in its own `tryCatch(suppressMessages(...))` block so that a failure in one provider does not prevent the other from initializing.

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

### URL Path Construction

Use **bare segment names** in `httr2::req_url_path_append()` — no leading slashes. Leading slashes produce double-slash paths (e.g. `//files//id//content`) that may break on strict routers.

```r
# GOOD
req_url_path_append(req, "files", id, "content")

# BAD — produces double slashes
req_url_path_append(req, "/files/", id, "/content")
```

### Gemini Batch Design Notes

- Uses Gemini Batch API file mode:
  - Upload JSONL input file via `google_upload_init` / `google_upload_send` / `google_upload_wait`
  - Submit `models/{model}:batchGenerateContent`
  - Poll batch operation
  - Download output file via `files/*:download` (requires `?alt=media` query parameter)
- **JSONL format is stricter than the REST API.** The batch JSONL parser does NOT auto-convert like the REST endpoint:
  - Each line must be `{"key": "string", "request": {GenerateContentRequest}}`
  - All field names must be **snake_case** (protobuf field names), not camelCase. `ellmer::chat_body()` returns camelCase (`generationConfig`, `systemInstruction`, etc.) so `gemini_prepare_batch_body()` converts them. **Exception:** user-defined schema property names are preserved as-is (the schema subtree is saved before conversion and restored after).
  - Structured output field is `response_json_schema`, NOT `response_schema` (REST API accepts either; batch parser only accepts the newer name).
  - Empty `system_instruction` blocks (e.g. `{"parts": {"text": ""}}`) are rejected; `gemini_prepare_batch_body()` strips these.
- Batch output line format is normalized defensively to handle both:
  - Plain `GenerateContentResponse` lines
  - Wrapped `response/error/status` variants
- Batch method registration is done in `.onLoad`, with a defensive re-registration in `chat_gemini_extended()` to support `devtools::load_all()` workflows.
- `batch_retrieve` checks multiple paths for `responsesFile` (`response$output$responsesFile`, `response$responsesFile`, `metadata$output$responsesFile`) because the Gemini API response structure varies between API versions.
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
- The `.onLoad` error handlers silently defer initialization failures (needed for documentation builds); users see informative errors when they try to use provider functions.
- Heavy reliance on `asNamespace("ellmer")` for internal functions -- fragile if ellmer renames internals.
- **S7 segfault on Windows R 4.5.1:** Creating S7 subclasses of ellmer providers (`S7::new_class(parent = ProviderGoogleGemini)`) segfaults when called outside `.onLoad` context. This also affects `S7::method<-` and `register_gemini_methods()` post-load. The classes work correctly when created during `.onLoad`. This is why `chat_gemini_extended()` has a defensive `register_gemini_methods()` call, and why the `has_batch_support` test also re-registers defensively.
- **`S7::method<-` prints "Overwriting method" messages** that R CMD check treats as unsuppressable startup messages. All registration calls must be wrapped in `suppressMessages()`.
- `lifecycle` is in Suggests, not Imports (only used at roxygen doc-gen time for badge macros).

## Dependencies

Core: `ellmer`, `S7`, `purrr`, `cli`, `httr2`, `curl`, `withr`, `jsonlite`, `rlang`
Suggests: `testthat`, `lifecycle`

## CI / Publishing

- GitHub repo: https://github.com/xmarquez/ellmer.extensions
- pkgdown site: https://xmarquez.github.io/ellmer.extensions/
- R-CMD-check: `.github/workflows/R-CMD-check.yaml` (push to main/master, PRs)
- pkgdown: `.github/workflows/pkgdown.yaml`
