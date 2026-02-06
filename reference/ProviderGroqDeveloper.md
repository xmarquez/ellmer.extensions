# Groq Developer Provider Class

S7 class that extends ProviderOpenAICompatible to provide Groq-specific
functionality. Inherits all capabilities from ProviderOpenAICompatible
(which uses the Chat Completions API format) while ensuring proper
schema formatting for Groq's strict JSON validation.

## Usage

``` r
ProviderGroqDeveloper(
  name = stop("Required"),
  model = stop("Required"),
  base_url = stop("Required"),
  params = list(),
  extra_args = list(),
  extra_headers = character(0),
  credentials = function() NULL
)
```

## Arguments

- name:

  Provider name

- model:

  Model identifier (e.g., "openai/gpt-oss-20b")

- base_url:

  API base URL

- params:

  Parameters list for generation control

- extra_args:

  Additional API arguments

- extra_headers:

  Additional HTTP headers

- credentials:

  API credentials (function or string)

## Details

This class also implements batch processing support via Groq's Batch
API, which offers a 50% cost discount compared to synchronous API calls.

Users should typically use
[`chat_groq_developer()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_groq_developer.md)
instead of calling this constructor directly. This class is exported for
advanced use cases.

## See also

[`chat_groq_developer()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_groq_developer.md)
for creating chat objects
