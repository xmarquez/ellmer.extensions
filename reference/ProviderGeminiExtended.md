# Gemini Provider with Batch API Support

Internal S7 class that extends `ellmer::ProviderGoogleGemini` with
file-based batch support for
[`batch_chat()`](https://ellmer.tidyverse.org/reference/batch_chat.html)
and
[`batch_chat_structured()`](https://ellmer.tidyverse.org/reference/batch_chat.html).

## Usage

``` r
ProviderGeminiExtended(
  name = stop("Required"),
  model = stop("Required"),
  base_url = stop("Required"),
  params = list(),
  extra_args = list(),
  extra_headers = character(0),
  credentials = function() NULL
)
```
