# Chat with Anthropic Models (Extended Thinking + Structured Output)

Creates a chat interface for Anthropic's Claude API with support for
extended and adaptive thinking combined with structured output. On
recent versions of ellmer this is a backward-compatible wrapper around
[`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html).
Older versions use the bundled compatibility provider when ellmer does
not yet provide the requested feature.

When `thinking` is `NULL` (the default), thinking is auto-detected from
`params`: if `reasoning_tokens` is present, thinking is enabled
automatically. Otherwise, the function behaves identically to
[`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html).

## Usage

``` r
chat_anthropic_extended(
  system_prompt = NULL,
  params = NULL,
  model = NULL,
  cache = c("5m", "1h", "none"),
  api_args = list(),
  base_url = "https://api.anthropic.com/v1",
  beta_headers = character(),
  api_key = NULL,
  credentials = NULL,
  api_headers = character(),
  echo = NULL,
  thinking = NULL
)
```

## Arguments

- system_prompt:

  A system prompt to set the behavior of the assistant.

- params:

  Common model parameters, usually created by
  [`ellmer::params()`](https://ellmer.tidyverse.org/reference/params.html).
  When `thinking = "enabled"`, must include `reasoning_tokens` to set
  the thinking budget.

- model:

  The model to use for the chat (defaults to
  `"claude-sonnet-4-5-20250929"`).

- cache:

  Anthropic prompt caching strategy. One of `"5m"`, `"1h"`, or `"none"`.

- api_args:

  Additional arguments passed to the API.

- base_url:

  Base URL for the Anthropic API.

- beta_headers:

  Character vector of Anthropic beta feature headers.

- api_key:

  **\[deprecated\]** Use `credentials` instead.

- credentials:

  Override the default credentials. You generally should not need this
  argument; instead set `ANTHROPIC_API_KEY` in `.Renviron`.

- api_headers:

  Additional HTTP headers.

- echo:

  Whether to echo the conversation to the console.

- thinking:

  Thinking mode. One of:

  - `NULL` (default): auto-detect. If `reasoning_tokens` is present in
    `params`, thinking is automatically enabled. Otherwise, no thinking
    (behaves like
    [`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html)).

  - `"enabled"`: extended thinking with explicit budget. Requires
    `reasoning_tokens` in `params`.

  - `"adaptive"`: adaptive thinking. If `reasoning_effort` is not
    supplied, it defaults to `"high"`. Model compatibility is determined
    by Anthropic, rather than by a hard-coded model allowlist.

## Value

A [ellmer::Chat](https://ellmer.tidyverse.org/reference/Chat.html)
object.

## Details

### How it works

When `thinking` is active and structured output is requested (via
`$chat_structured()` or
[`batch_chat_structured()`](https://ellmer.tidyverse.org/reference/batch_chat.html)),
this provider uses Anthropic's `output_config.format` with a JSON schema
instead of the usual `tool_choice` mechanism. The model produces a
`thinking` block (internal reasoning) followed by a `text` block
containing JSON that matches the requested schema. This avoids the API
error: *"Thinking may not be enabled when tool_choice forces tool use."*

When thinking is not active (no `reasoning_tokens` in `params` and
`thinking = NULL`), the provider falls back to standard
`tool_choice`-based structured output (identical to
[`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html)).

## See also

[`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html),
[`batch_chat_structured()`](https://ellmer.tidyverse.org/reference/batch_chat.html)

Other chatbots:
[`chat_gemini_extended()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_gemini_extended.md),
[`chat_groq_developer()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_groq_developer.md)
