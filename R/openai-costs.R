#' Report OpenAI API Costs
#'
#' Retrieves actual costs from OpenAI's organization Costs API. Results can be
#' filtered to API key or project IDs and grouped by API key, project, or line
#' item. All pages are retrieved automatically.
#'
#' This endpoint requires an OpenAI Organization Admin API key. It does not
#' accept the ordinary project API key used for model requests. Organization
#' owners can create an Admin API key at
#' <https://platform.openai.com/settings/organization/admin-keys>.
#'
#' @param start_time Start of the reporting period, inclusive. A [Date],
#'   [POSIXt], or Unix timestamp in seconds.
#' @param end_time End of the reporting period, exclusive. A [Date], [POSIXt],
#'   Unix timestamp in seconds, or `NULL` to use the API default.
#' @param api_key_ids Optional character vector of OpenAI API key IDs. These are
#'   identifiers such as `"key_..."`, not secret `"sk-..."` key values.
#' @param project_ids Optional character vector of OpenAI project IDs.
#' @param group_by Optional character vector containing any of
#'   `"api_key_id"`, `"project_id"`, and `"line_item"`.
#' @param admin_key An OpenAI Organization Admin API key. Defaults to
#'   `OPENAI_ADMIN_KEY`.
#' @param limit Number of daily buckets requested per page, from 1 to 180.
#'   Pagination is automatic.
#' @param base_url Base URL for the OpenAI API.
#'
#' @return A data frame with one row per cost result and columns:
#'   `start_time`, `end_time`, `amount`, `currency`, `quantity`, `line_item`,
#'   `api_key_id`, `project_id`, and `project_name`. Grouping columns that were
#'   not requested may contain `NA`.
#'
#' @details
#' `amount` is the amount charged in `currency`; it is not estimated from token
#' counts. Sum `amount` only within a single currency.
#'
#' OpenAI does not currently document an API endpoint for remaining prepaid
#' credit. That balance remains available in the organization Billing page.
#'
#' @examples
#' \dontrun{
#' # Daily organization costs for the current month
#' costs <- openai_costs(
#'   start_time = as.Date(format(Sys.Date(), "%Y-%m-01")),
#'   group_by = "line_item"
#' )
#' sum(costs$amount)
#'
#' # Costs incurred by one API key
#' openai_costs(
#'   start_time = Sys.Date() - 30,
#'   api_key_ids = "key_abc123",
#'   group_by = c("api_key_id", "line_item")
#' )
#' }
#'
#' @seealso
#' [OpenAI Costs API](https://platform.openai.com/docs/api-reference/usage/costs)
#'
#' @export
openai_costs <- function(
  start_time,
  end_time = NULL,
  api_key_ids = NULL,
  project_ids = NULL,
  group_by = NULL,
  admin_key = Sys.getenv("OPENAI_ADMIN_KEY"),
  limit = 180L,
  base_url = "https://api.openai.com/v1"
) {
  start_time <- openai_cost_time(start_time, "start_time")
  if (!is.null(end_time)) {
    end_time <- openai_cost_time(end_time, "end_time")
    if (end_time <= start_time) {
      cli::cli_abort("{.arg end_time} must be later than {.arg start_time}.")
    }
  }

  group_by <- openai_cost_group_by(group_by)
  limit <- openai_cost_limit(limit)
  admin_key <- openai_admin_key(admin_key)

  req <- openai_cost_request(
    start_time = start_time,
    end_time = end_time,
    api_key_ids = api_key_ids,
    project_ids = project_ids,
    group_by = group_by,
    admin_key = admin_key,
    limit = limit,
    base_url = base_url
  )

  pages <- openai_cost_pages(req)
  openai_cost_data_frame(pages)
}

openai_cost_time <- function(x, arg) {
  if (inherits(x, "Date")) {
    x <- as.POSIXct(x, tz = "UTC")
  }
  if (inherits(x, "POSIXt")) {
    x <- as.numeric(x)
  }
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x)) {
    cli::cli_abort(
      "{.arg {arg}} must be a Date, date-time, or Unix timestamp."
    )
  }
  x
}

openai_cost_group_by <- function(group_by) {
  if (is.null(group_by)) {
    return(NULL)
  }
  match.arg(
    group_by,
    c("api_key_id", "project_id", "line_item"),
    several.ok = TRUE
  )
}

openai_cost_limit <- function(limit) {
  if (!is.numeric(limit) || length(limit) != 1L || is.na(limit) ||
        limit < 1 || limit > 180 || limit != as.integer(limit)) {
    cli::cli_abort("{.arg limit} must be a whole number from 1 to 180.")
  }
  as.integer(limit)
}

openai_admin_key <- function(admin_key) {
  if (!is.character(admin_key) || length(admin_key) != 1L || !nzchar(admin_key)) {
    cli::cli_abort(
      c(
        "Can't find an OpenAI Organization Admin API key.",
        "i" = "Set {.envvar OPENAI_ADMIN_KEY} or supply {.arg admin_key}."
      )
    )
  }
  admin_key
}

openai_cost_request <- function(
  start_time,
  end_time,
  api_key_ids,
  project_ids,
  group_by,
  admin_key,
  limit,
  base_url
) {
  req <- httr2::request(base_url)
  req <- httr2::req_url_path_append(req, "organization", "costs")
  req <- httr2::req_auth_bearer_token(req, admin_key)

  query <- list(
    start_time = start_time,
    bucket_width = "1d",
    limit = limit
  )
  if (!is.null(end_time)) query$end_time <- end_time
  if (length(api_key_ids)) query$api_key_ids <- api_key_ids
  if (length(project_ids)) query$project_ids <- project_ids
  if (length(group_by)) query$group_by <- group_by

  do.call(
    httr2::req_url_query,
    c(list(.req = req), query, list(.multi = "explode"))
  )
}

openai_cost_pages <- function(req, fetch = openai_cost_fetch_page) {
  pages <- list()
  page <- NULL

  repeat {
    page_req <- req
    if (!is.null(page)) {
      page_req <- httr2::req_url_query(page_req, page = page)
    }

    body <- fetch(page_req)
    pages[[length(pages) + 1L]] <- body

    if (!isTRUE(body$has_more) || is.null(body$next_page)) {
      break
    }
    page <- body$next_page
  }

  pages
}

openai_cost_fetch_page <- function(req) {
  req |>
    httr2::req_perform() |>
    httr2::resp_body_json(simplifyVector = FALSE)
}

openai_cost_data_frame <- function(pages) {
  rows <- list()

  for (page in pages) {
    for (bucket in page$data %||% list()) {
      for (result in bucket$results %||% list()) {
        rows[[length(rows) + 1L]] <- openai_cost_row(bucket, result)
      }
    }
  }

  if (length(rows) == 0L) {
    return(openai_cost_empty())
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

openai_cost_row <- function(bucket, result) {
  amount <- result$amount %||% list()

  data.frame(
    start_time = as.POSIXct(
      bucket$start_time,
      origin = "1970-01-01",
      tz = "UTC"
    ),
    end_time = as.POSIXct(
      bucket$end_time,
      origin = "1970-01-01",
      tz = "UTC"
    ),
    amount = as.numeric(amount$value %||% NA_real_),
    currency = as.character(amount$currency %||% NA_character_),
    quantity = as.numeric(result$quantity %||% NA_real_),
    line_item = as.character(result$line_item %||% NA_character_),
    api_key_id = as.character(result$api_key_id %||% NA_character_),
    project_id = as.character(result$project_id %||% NA_character_),
    project_name = as.character(result$project_name %||% NA_character_),
    stringsAsFactors = FALSE
  )
}

openai_cost_empty <- function() {
  data.frame(
    start_time = as.POSIXct(character(), tz = "UTC"),
    end_time = as.POSIXct(character(), tz = "UTC"),
    amount = numeric(),
    currency = character(),
    quantity = numeric(),
    line_item = character(),
    api_key_id = character(),
    project_id = character(),
    project_name = character(),
    stringsAsFactors = FALSE
  )
}
