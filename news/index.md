# Changelog

## ellmer.extensions 0.2.0

### New features

- Added
  [`chat_anthropic_extended()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_anthropic_extended.md)
  and `ProviderAnthropicExtended` for Anthropic extended thinking
  combined with structured output. Standard
  [`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html)
  cannot combine thinking (`reasoning_tokens`) with structured output
  because Anthropic’s API forbids `tool_choice` when

  thinking is enabled. The new provider uses `output_config.format`
  (JSON schema) instead of `tool_choice` when thinking is active.

- Supported thinking modes: `"enabled"` (all 4.5+ models, requires
  explicit `reasoning_tokens` budget) and `"adaptive"` (Opus 4.6 /
  Sonnet 4.6 only, model decides thinking budget).

- Thinking is auto-detected from `reasoning_tokens` in `params` — no
  additional configuration needed when using the pipeline.

### Bug fixes

- Truncated Anthropic responses (`stop_reason: "max_tokens"`) from
  adaptive thinking self-correction loops now emit a warning instead of
  silently returning recovered JSON from an earlier text block.

- `max_tokens` is now automatically increased when thinking is enabled
  and the default (4096) is too small. Enabled thinking gets
  `budget_tokens + 16384`; adaptive thinking gets 32768.

## ellmer.extensions 0.1.0

- Initial release with
  [`chat_groq_developer()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_groq_developer.md)
  (Groq structured output and batch support) and
  [`chat_gemini_extended()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_gemini_extended.md)
  (Gemini file-based batch support with context caching).
