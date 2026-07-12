# Groq Developer Provider Class

S7 compatibility class that extends ellmer's native Groq provider when
available and otherwise extends ProviderOpenAICompatible.

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

It forwards Groq reasoning-effort parameters and retains a legacy batch
implementation for ellmer releases without native Groq batch support.

Users should typically use
[`chat_groq_developer()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_groq_developer.md)
instead of calling this constructor directly. This class is exported for
advanced use cases.

## See also

[`chat_groq_developer()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_groq_developer.md)
for creating chat objects
