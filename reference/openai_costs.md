# Report OpenAI API Costs

Retrieves actual costs from OpenAI's organization Costs API. Results can
be filtered to API key or project IDs and grouped by API key, project,
or line item. All pages are retrieved automatically.

## Usage

``` r
openai_costs(
  start_time,
  end_time = NULL,
  api_key_ids = NULL,
  project_ids = NULL,
  group_by = NULL,
  admin_key = Sys.getenv("OPENAI_ADMIN_KEY"),
  limit = 180L,
  base_url = "https://api.openai.com/v1"
)
```

## Arguments

- start_time:

  Start of the reporting period, inclusive. A
  [Date](https://rdrr.io/r/base/Dates.html),
  [POSIXt](https://rdrr.io/r/base/DateTimeClasses.html), or Unix
  timestamp in seconds.

- end_time:

  End of the reporting period, exclusive. A
  [Date](https://rdrr.io/r/base/Dates.html),
  [POSIXt](https://rdrr.io/r/base/DateTimeClasses.html), Unix timestamp
  in seconds, or `NULL` to use the API default.

- api_key_ids:

  Optional character vector of OpenAI API key IDs. These are identifiers
  such as `"key_..."`, not secret `"sk-..."` key values.

- project_ids:

  Optional character vector of OpenAI project IDs.

- group_by:

  Optional character vector containing any of `"api_key_id"`,
  `"project_id"`, and `"line_item"`.

- admin_key:

  An OpenAI Organization Admin API key. Defaults to `OPENAI_ADMIN_KEY`.

- limit:

  Number of daily buckets requested per page, from 1 to 180. Pagination
  is automatic.

- base_url:

  Base URL for the OpenAI API.

## Value

A data frame with one row per cost result and columns: `start_time`,
`end_time`, `amount`, `currency`, `quantity`, `line_item`, `api_key_id`,
`project_id`, and `project_name`. Grouping columns that were not
requested may contain `NA`.

## Details

This endpoint requires an OpenAI Organization Admin API key. It does not
accept the ordinary project API key used for model requests.
Organization owners can create an Admin API key at
<https://platform.openai.com/settings/organization/admin-keys>.

`amount` is the amount charged in `currency`; it is not estimated from
token counts. Sum `amount` only within a single currency.

OpenAI does not currently document an API endpoint for remaining prepaid
credit. That balance remains available in the organization Billing page.

## See also

[OpenAI Costs
API](https://platform.openai.com/docs/api-reference/usage/costs)

## Examples

``` r
if (FALSE) { # \dontrun{
# Daily organization costs for the current month
costs <- openai_costs(
  start_time = as.Date(format(Sys.Date(), "%Y-%m-01")),
  group_by = "line_item"
)
sum(costs$amount)

# Costs incurred by one API key
openai_costs(
  start_time = Sys.Date() - 30,
  api_key_ids = "key_abc123",
  group_by = c("api_key_id", "line_item")
)
} # }
```
