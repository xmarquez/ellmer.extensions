# Chat with Groq AI Models (Developer Version)

Creates a chat interface for Groq's API with support for structured
outputs, batch processing, and parallel execution. This developer
version extends ellmer's ProviderOpenAICompatible to inherit full batch
support while adding Groq-specific schema formatting
(additionalProperties: false).

Sign up at <https://groq.com>.

Built on top of ellmer's ProviderOpenAICompatible class.

## Usage

``` r
chat_groq_developer(
  system_prompt = NULL,
  base_url = "https://api.groq.com/openai/v1",
  api_key = NULL,
  credentials = NULL,
  model = NULL,
  params = NULL,
  api_args = list(),
  echo = NULL,
  api_headers = character()
)
```

## Arguments

- system_prompt:

  A system prompt to set the behavior of the assistant.

- base_url:

  Base URL for Groq API.

- api_key:

  **\[deprecated\]** Use `credentials` instead.

- credentials:

  Override the default credentials. You generally should not need this
  argument; instead set the `GROQ_API_KEY` environment variable. The
  best place to set this is in `.Renviron`, which you can easily edit by
  calling `usethis::edit_r_environ()`.

  If you do need additional control, this argument takes a zero-argument
  function that returns either a string (the API key), or a named list
  (added as additional headers to every request).

- model:

  The model to use for the chat (defaults to "openai/gpt-oss-20b"). We
  regularly update the default, so we strongly recommend explicitly
  specifying a model for anything other than casual use. Use
  [`models_groq()`](https://xmarquez.github.io/ellmer.extensions/reference/models_groq.md)
  to see all options.

- params:

  Common model parameters, usually created by
  [`ellmer::params()`](https://ellmer.tidyverse.org/reference/params.html).

- api_args:

  Additional arguments passed to the API.

- echo:

  Whether to echo the conversation to the console. One of:

  - `"none"`: No output

  - `"output"`: Echo assistant responses only

  - `"all"`: Echo all messages Defaults to `"output"` in interactive
    sessions, `"none"` otherwise.

- api_headers:

  Additional HTTP headers.

## Value

A [ellmer::Chat](https://ellmer.tidyverse.org/reference/Chat.html)
object with methods for:

- `$chat()`: Send messages and receive responses

- `$chat_structured()`: Extract structured data with type validation

- Batch processing via
  [`batch_chat()`](https://ellmer.tidyverse.org/reference/batch_chat.html)
  and
  [`batch_chat_structured()`](https://ellmer.tidyverse.org/reference/batch_chat.html)

- Parallel processing via
  [`parallel_chat()`](https://ellmer.tidyverse.org/reference/parallel_chat.html)
  and
  [`parallel_chat_structured()`](https://ellmer.tidyverse.org/reference/parallel_chat.html)

## Structured Outputs

Groq supports strict JSON schema validation with guaranteed compliance
when using compatible models. See
<https://console.groq.com/docs/structured-outputs> for details.

## Batch Processing

Groq's batch API offers 50% cost discount and no rate limit impact.
Batch jobs are processed asynchronously with completion windows from 24
hours to 7 days. Use
[`batch_chat()`](https://ellmer.tidyverse.org/reference/batch_chat.html)
or
[`batch_chat_structured()`](https://ellmer.tidyverse.org/reference/batch_chat.html)
to submit batches. See <https://console.groq.com/docs/batch> for
details.

## Models

For strict structured output support, use:

- `"openai/gpt-oss-20b"` (default)

- `"openai/gpt-oss-120b"`

Other models support best-effort JSON output but may not guarantee
schema compliance.

## See also

- [`batch_chat()`](https://ellmer.tidyverse.org/reference/batch_chat.html)
  for batch processing

- [`parallel_chat()`](https://ellmer.tidyverse.org/reference/parallel_chat.html)
  for parallel processing

- [`ellmer::type_object()`](https://ellmer.tidyverse.org/reference/type_boolean.html),
  [`ellmer::type_array()`](https://ellmer.tidyverse.org/reference/type_boolean.html)
  for defining types

Other chatbots:
[`chat_gemini_extended()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_gemini_extended.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Basic chat
chat <- chat_groq_developer()
chat$chat("What is the capital of France?")

# Structured output
type_person <- ellmer::type_object(
  name = ellmer::type_string(),
  age = ellmer::type_integer(),
  city = ellmer::type_string()
)
result <- chat$chat_structured(
  "John is 30 years old and lives in NYC",
  type = type_person
)

# Batch processing
results <- batch_chat(
  chat,
  prompts = c("Question 1?", "Question 2?", "Question 3?")
)

# Parallel processing
results <- parallel_chat(
  chat,
  prompts = c("Question 1?", "Question 2?", "Question 3?")
)
} # }
```
