# List Available Groq Models

Retrieves a list of available models from the Groq API. Returns model
metadata including context window size and active status.

## Usage

``` r
models_groq(
  base_url = "https://api.groq.com/openai/v1",
  api_key = NULL,
  credentials = NULL
)
```

## Arguments

- base_url:

  Base URL for the Groq API.

- api_key:

  **\[deprecated\]** Use `credentials` instead.

- credentials:

  Override the default credentials. You generally should not need this
  argument; instead set the `GROQ_API_KEY` environment variable.

## Value

A data frame with columns:

- id:

  Model identifier (e.g., "llama-3.3-70b-versatile")

- created_at:

  Date the model was created

- owned_by:

  Organization that owns/provides the model

- context_window:

  Maximum context window size in tokens

- active:

  Whether the model is currently active/available

## See also

[`chat_groq_developer()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_groq_developer.md)
for creating chat sessions

## Examples

``` r
if (FALSE) { # \dontrun{
# List all available models
models <- models_groq()
print(models)

# Filter for active models with large context windows
large_context <- models[models$context_window >= 32768 & models$active, ]
} # }
```
