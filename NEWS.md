# ellmer.extensions 0.3.0

## Compatibility

* Groq, Gemini, and Anthropic constructors now use native `ellmer`
  functionality when available while retaining legacy implementations for
  `ellmer` 0.4.0.

* `chat_groq_developer()` now sends `reasoning_effort` supplied through either
  `ellmer::params()` or `api_args`, including in durable batch request bodies.

* Gemini batch context caching remains available through `cache_ttl`; native
  `ellmer` parsing is retained so thinking blocks, thought signatures, and
  finish reasons are not lost.

* Anthropic adaptive thinking now places effort under `output_config`, and
  delegates model capability handling to current `ellmer` where possible.

## Testing

* Live provider tests require `ELLMER_EXTENSIONS_RUN_LIVE_TESTS=true` and use a
  bounded two-minute polling window.

* CI checks both the minimum supported and development versions of `ellmer`.

# ellmer.extensions 0.2.0

## New features

* Added `chat_anthropic_extended()` and `ProviderAnthropicExtended` for
  Anthropic extended thinking combined with structured output. Standard
  `ellmer::chat_anthropic()` cannot combine thinking (`reasoning_tokens`)
  with structured output because Anthropic's API forbids `tool_choice` when

  thinking is enabled. The new provider uses `output_config.format` (JSON
  schema) instead of `tool_choice` when thinking is active.

* Supported thinking modes: `"enabled"` (all 4.5+ models, requires explicit
  `reasoning_tokens` budget) and `"adaptive"` (Opus 4.6 / Sonnet 4.6 only,
  model decides thinking budget).

* Thinking is auto-detected from `reasoning_tokens` in `params` — no
  additional configuration needed when using the pipeline.

## Bug fixes

* Truncated Anthropic responses (`stop_reason: "max_tokens"`) from adaptive
  thinking self-correction loops now emit a warning instead of silently
  returning recovered JSON from an earlier text block.

* `max_tokens` is now automatically increased when thinking is enabled and
  the default (4096) is too small. Enabled thinking gets
  `budget_tokens + 16384`; adaptive thinking gets 32768.

# ellmer.extensions 0.1.0

* Initial release with `chat_groq_developer()` (Groq structured output and
  batch support) and `chat_gemini_extended()` (Gemini file-based batch
  support with context caching).
