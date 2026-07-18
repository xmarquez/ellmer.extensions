# CLAUDE.md - ellmer.extensions

## Package Overview

- **Package name:** `ellmer.extensions`
- **Purpose:** Preserve backward-compatible provider entry points while using
  native [ellmer](https://github.com/tidyverse/ellmer) functionality when it is
  available. The remaining extension-specific feature is opt-in Gemini batch
  context caching. The package also provides OpenAI organization cost reports.
- **Origin:** Cloned from `groqDeveloper` and adapted with Gemini batch functionality.

## Architecture

### Provider Classes (S7)

All provider classes are created dynamically in `.onLoad` (in `R/provider-groq.R`) because they extend ellmer classes that aren't available at package build time:

- `ProviderGroqDeveloper` extends native `ellmer::ProviderGroq` when available,
  otherwise `ellmer::ProviderOpenAICompatible`
- `ProviderGeminiExtended` extends `ellmer::ProviderGoogleGemini`
- `ProviderAnthropicExtended` extends `ellmer::ProviderAnthropic`

Method registration uses `S7::method()` calls inside `register_groq_methods()`,
`register_gemini_methods()`, and `register_anthropic_methods()`, followed by
`S7::methods_register()`. Initialization errors are not swallowed: a package
load must fail rather than leave exported constructors backed by `NULL` classes.

### Key Files

| File | Purpose |
|------|---------|
| `R/chat-groq.R` | Groq chat constructor, `models_groq()`, utility functions (`key_get`, `set_default`) |
| `R/provider-groq.R` | Groq reasoning parameter forwarding, legacy batch compatibility, `.onLoad` |
| `R/chat-gemini.R` | Gemini chat constructor (`chat_gemini_extended`) |
| `R/provider-gemini.R` | Native Gemini batch delegation, legacy compatibility, context caching |
| `R/chat-anthropic.R` | Anthropic chat constructor (`chat_anthropic_extended`) |
| `R/provider-anthropic.R` | `ProviderAnthropicExtended` class, chat_body and value_turn overrides |
| `R/openai-costs.R` | OpenAI organization cost reporting and pagination |
| `R/reexports.R` | Re-exports ellmer generics (`batch_chat`, `parallel_chat`, etc.) |
| `R/ellmer.extensions-package.R` | Package-level documentation, `@import S7`, `@importFrom rlang %\|\|%` |

### Groq Design Notes

- Native Groq provider and batch methods are inherited when ellmer supplies them.
- Older ellmer releases use the compatibility batch methods, which reuse
  ellmer's OpenAI upload, download, NDJSON, and parsing helpers.
- `reasoning_effort` is forwarded through `chat_params()` and `chat_body()` so
  it reaches synchronous and batch requests. `api_args` takes precedence.

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
- Current ellmer owns ordinary batch submission, polling, retrieval, and response
  parsing. This package wraps submit/poll/retrieve only when `cache_ttl` is used.
- ellmer 0.4.0 retains the local file-mode compatibility implementation.
- Legacy output handling follows the observed wrapped `response/error/status`
  fixture shape and preserves thinking blocks and thought signatures.

### Gemini Context Caching

Opt-in via `cache_ttl` parameter in `chat_gemini_extended()`. When set, batch operations create a Gemini `cachedContents` resource for the system prompt before submission, then reference it in each JSONL request via `cached_content` instead of `system_instruction`. This reduces input token costs (cached tokens billed at a reduced model-specific rate).

**Cache lifecycle:**
1. `batch_submit`: Creates cache via `POST cachedContents`, embeds `cache_name` in the returned batch object as `.gemini_cache_name`
2. `batch_poll`: Carries `.gemini_cache_name` forward when the batch object is refreshed from the API
3. `batch_retrieve`: Deletes cache via `on.exit()` (runs on both success and failure paths)

**Design decisions:**
- Cache name is embedded in the batch object (not a package-level env) so it survives `wait=FALSE` → resume cycles (BatchJob serializes `self$batch` to JSON)
- `jsonlite` preserves dot-prefixed field names through `toJSON`/`fromJSON` round-trip
- System prompt validation: caching only activates when all conversations share an identical system prompt text
- Cache creation failure falls back to a non-cached batch with a warning
- All cache API calls use `base_request(provider)` to respect custom `base_url`
- S7 value semantics: `attr(provider, ".gemini_cache_ttl")` is set in `chat_gemini_extended()` before `Chat$new()` — readable inside batch methods but mutations inside methods don't propagate out (which is why the batch object, not the provider, carries the cache name)

**TTL recommendation:** `86400` (24 hours) for batch jobs. Gemini batches can run up to 24 hours; shorter TTLs risk expiring mid-batch. `cache_ttl < 60` is rejected.

### Anthropic Extended Thinking + Structured Output

`chat_anthropic_extended()` solves the conflict between Anthropic's extended thinking and structured output. The issue: `ellmer::chat_anthropic()` uses `tool_choice: {type: "tool", name: "_structured_tool_call"}` for structured output, but Anthropic forbids `tool_choice` with thinking enabled (*"Thinking may not be enabled when tool_choice forces tool use."*).

**Solution:** When thinking is active AND structured output is requested, the provider overrides `chat_body()` to use `output_config.format` with a JSON schema instead of `tool_choice`. The model returns JSON in a `text` content block (not `tool_use`), which `value_turn()` parses into `ContentJson`.

**Key design decisions:**
- `thinking` parameter: `NULL` (auto-detect from `reasoning_tokens`), `"enabled"` (explicit budget), or `"adaptive"`
- No `{data: ...}` wrapper — schema matches the user's type directly, `ContentJson(data = parsed)` from the raw JSON text
- Real user tools are preserved in the thinking+type path; only the synthetic `_structured_tool_call` tool is omitted
- Multiple text blocks are joined before JSON parsing (defensive against split responses)
- When thinking is NOT active, behavior is identical to `ellmer::chat_anthropic()` (forced tool_choice)
- Model capability decisions are delegated to ellmer/Anthropic rather than a
  hard-coded model allowlist.
- Adaptive effort is sent as `output_config$effort`, not as a top-level field.

## Environment Variables

- Groq: `GROQ_API_KEY`
- Gemini: `GEMINI_API_KEY` (or `GOOGLE_API_KEY`)
- Anthropic: `ANTHROPIC_API_KEY`
- OpenAI cost reporting: `OPENAI_ADMIN_KEY` (Organization Admin key; read-only
  scope is sufficient)
- Keep `.Renviron` local only; **never commit it**
- `.Renviron.example` contains placeholder values only

## Standard Workflow

Run from package root:

1. `Rscript -e "devtools::document()"`
2. `Rscript -e "devtools::test()"`
3. `Rscript -e "devtools::lint()"` (run at end)
4. `Rscript -e "devtools::check()"`

## Testing Notes

- Offline tests focus on observable request construction and real provider
  fixtures rather than duplicated class-structure assertions.
- Live Groq and Gemini smoke tests require
  `ELLMER_EXTENSIONS_RUN_LIVE_TESTS=true` plus the relevant API key and use a
  bounded 120-second polling window.
- CI checks both ellmer 0.4.0 and ellmer development.
- **Linting** configured via `.lintr` with `line_length_linter(120)`, `object_name_linter = NULL` (S7 PascalCase), `object_length_linter = NULL`.

## Repo Hygiene

- `.Renviron` is gitignored and purged from git history.
- If `.Renviron` is accidentally committed, remove from tracking immediately and follow the purge procedure in AGENTS.md.
- If a secret is ever pushed or shared, **rotate keys immediately**.

## Known Issues and Limitations

- `ProviderGeminiExtended` is not exported (by design; users should use `chat_gemini_extended()`).
- Groq structured outputs do not support streaming or tool use.
- Gemini batch jobs can remain queued for extended periods; integration tests handle this gracefully.
- Heavy reliance on `asNamespace("ellmer")` for internal functions -- fragile if ellmer renames internals.
- **S7 segfault on Windows R 4.5.1:** Keep subclass creation and method
  registration in `.onLoad`; constructors must not defensively re-register.
- **`S7::method<-` prints "Overwriting method" messages** that R CMD check treats as unsuppressable startup messages. All registration calls must be wrapped in `suppressMessages()`.
- `lifecycle` is in Suggests, not Imports (only used at roxygen doc-gen time for badge macros).

## Dependencies

Core: `ellmer`, `S7`, `purrr`, `cli`, `httr2`, `withr`, `jsonlite`, `rlang`
Suggests: `testthat`, `lifecycle`

## CI / Publishing

- GitHub repo: https://github.com/xmarquez/ellmer.extensions
- pkgdown site: https://xmarquez.github.io/ellmer.extensions/
- R-CMD-check: `.github/workflows/R-CMD-check.yaml` (push to main/master, PRs)
- pkgdown: `.github/workflows/pkgdown.yaml`
