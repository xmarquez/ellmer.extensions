# Anthropic Provider with Extended Thinking + Structured Output

Internal S7 class that extends `ellmer::ProviderAnthropic` with support
for extended thinking combined with structured output. When thinking is
active, uses `output_config.format` (JSON schema) instead of
`tool_choice` to avoid the Anthropic API conflict: *"Thinking may not be
enabled when tool_choice forces tool use."*

## Usage

``` r
ProviderAnthropicExtended(
  name = stop("Required"),
  model = stop("Required"),
  base_url = stop("Required"),
  params = list(),
  extra_args = list(),
  extra_headers = character(0),
  credentials = function() NULL,
  beta_headers = character(0),
  cache = stop("Required")
)
```
