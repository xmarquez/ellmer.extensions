# Chat with Gemini Models (Extended Batch Support)

Creates a chat interface for Google's Gemini API with support for
asynchronous file-based batch processing through
[`batch_chat()`](https://ellmer.tidyverse.org/reference/batch_chat.html)
and
[`batch_chat_structured()`](https://ellmer.tidyverse.org/reference/batch_chat.html).

This constructor mirrors
[`ellmer::chat_google_gemini()`](https://ellmer.tidyverse.org/reference/chat_google_gemini.html)
while using a provider subclass that implements batch methods required
by ellmer.

## Usage

``` r
chat_gemini_extended(
  system_prompt = NULL,
  base_url = "https://generativelanguage.googleapis.com/v1beta/",
  api_key = NULL,
  credentials = NULL,
  model = NULL,
  params = NULL,
  api_args = list(),
  api_headers = character(),
  echo = NULL
)
```

## Arguments

- system_prompt:

  A system prompt to set the behavior of the assistant.

- base_url:

  Base URL for the Gemini API.

- api_key:

  **\[deprecated\]** Use `credentials` instead.

- credentials:

  Override the default credentials. You generally should not need this
  argument; instead set `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) in
  `.Renviron`.

- model:

  The model to use for the chat (defaults to "gemini-2.5-flash").

- params:

  Common model parameters, usually created by
  [`ellmer::params()`](https://ellmer.tidyverse.org/reference/params.html).

- api_args:

  Additional arguments passed to the API.

- api_headers:

  Additional HTTP headers.

- echo:

  Whether to echo the conversation to the console.

## Value

A [ellmer::Chat](https://ellmer.tidyverse.org/reference/Chat.html)
object with Gemini support for:

- `$chat()`

- `$chat_structured()`

- [`batch_chat()`](https://ellmer.tidyverse.org/reference/batch_chat.html)
  and
  [`batch_chat_structured()`](https://ellmer.tidyverse.org/reference/batch_chat.html)

## See also

[`ellmer::chat_google_gemini()`](https://ellmer.tidyverse.org/reference/chat_google_gemini.html),
[`batch_chat()`](https://ellmer.tidyverse.org/reference/batch_chat.html),
[`batch_chat_structured()`](https://ellmer.tidyverse.org/reference/batch_chat.html)

Other chatbots:
[`chat_groq_developer()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_groq_developer.md)
