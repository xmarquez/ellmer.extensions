# Chat with Anthropic Models (Extended Thinking + Structured Output)

Creates a chat interface for Anthropic's Claude API with support for
extended thinking combined with structured output. Standard
[`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html)
cannot combine thinking (`reasoning_tokens`) with structured output
because Anthropic's API forbids `tool_choice` with thinking enabled.
This provider uses Anthropic's `output_config.format` (JSON schema)
instead of `tool_choice` when thinking is active, avoiding the API
conflict.

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

  - `"adaptive"`: adaptive thinking. Only available on Claude Opus 4.6
    and Sonnet 4.6; errors for 4.5 model IDs.

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

### Model compatibility

- `thinking = "enabled"`: All Claude 4.5 models (Haiku, Sonnet, Opus)
  and later. Requires `reasoning_tokens` in `params` to set the thinking
  budget.

- `thinking = "adaptive"`: Claude Opus 4.6 and Sonnet 4.6 only.

## See also

[`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html),
[`batch_chat_structured()`](https://ellmer.tidyverse.org/reference/batch_chat.html)

Other chatbots:
[`chat_gemini_extended()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_gemini_extended.md),
[`chat_groq_developer()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_groq_developer.md)
