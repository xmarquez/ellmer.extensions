# ellmer.extensions

`ellmer.extensions` extends
[ellmer](https://github.com/tidyverse/ellmer) with:

- [`chat_groq_developer()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_groq_developer.md)
  for Groq structured outputs and Groq batch support.
- [`chat_gemini_extended()`](https://xmarquez.github.io/ellmer.extensions/reference/chat_gemini_extended.md)
  for Gemini chat plus file-based batch support.

The package is integrated with ellmer generics like
[`batch_chat()`](https://ellmer.tidyverse.org/reference/batch_chat.html),
[`batch_chat_structured()`](https://ellmer.tidyverse.org/reference/batch_chat.html),
and
[`parallel_chat()`](https://ellmer.tidyverse.org/reference/parallel_chat.html).

## Installation

You can install the development version of `ellmer.extensions` from
GitHub:

``` r
# install.packages("devtools")
devtools::install_github("xmarquez/ellmer.extensions")
```

## Setup

Set one or both provider keys in `.Renviron`:

``` r
Sys.setenv(GROQ_API_KEY = "your-groq-key")
Sys.setenv(GEMINI_API_KEY = "your-gemini-key")
```

(`GOOGLE_API_KEY` also works for Gemini.)

## Examples

### Basic Groq chat

``` r
library(ellmer.extensions)

chat_groq <- chat_groq_developer(model = "openai/gpt-oss-20b")
chat_groq$chat("What is the capital of France?")
```

### Basic Gemini chat

``` r
library(ellmer.extensions)

chat_gemini <- chat_gemini_extended(model = "gemini-2.5-flash")
chat_gemini$chat("Reply with exactly one word: hello")
```

### Structured output (Groq)

``` r
type_person <- ellmer::type_object(
  name = ellmer::type_string(),
  age = ellmer::type_integer(),
  city = ellmer::type_string()
)

result <- chat_groq$chat_structured(
  "John is 30 years old and lives in New York City",
  type = type_person
)

str(result)
```

### Batch chat (Groq)

``` r
prompts <- list(
  "What is 2 + 2? Reply with only the number.",
  "What is the capital of New Zealand? Reply with only the city."
)

path <- tempfile(fileext = ".json")

chats <- batch_chat(
  chat_groq,
  prompts = prompts,
  path = path,
  wait = TRUE
)

chats
```

### Batch chat (Gemini)

``` r
prompts <- list(
  "Reply with exactly: ok",
  "Reply with exactly: done"
)

path <- tempfile(fileext = ".json")

# Submit without waiting, then resume later
batch_chat(
  chat_gemini,
  prompts = prompts,
  path = path,
  wait = FALSE
)

batch_chat_completed(chat_gemini, prompts, path)

# Resume and retrieve once completed
chats <- batch_chat(
  chat_gemini,
  prompts = prompts,
  path = path,
  wait = TRUE
)
```

### Parallel chat

``` r
parallel_chat(
  chat_groq,
  prompts = list(
    "Tell me one fact about Paris.",
    "Tell me one fact about Wellington.",
    "Tell me one fact about Tokyo."
  )
)
```

## Model discovery

- Groq models:
  [`models_groq()`](https://xmarquez.github.io/ellmer.extensions/reference/models_groq.md)
- Gemini models:
  [`ellmer::models_google_gemini()`](https://ellmer.tidyverse.org/reference/chat_google_gemini.html)

## License

MIT
