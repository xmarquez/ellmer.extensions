read_openai_cost_fixture <- function() {
  jsonlite::fromJSON(
    test_path("fixtures", "openai-costs.json"),
    simplifyVector = FALSE
  )
}

test_that("OpenAI cost fixture becomes a focused data frame", {
  costs <- ellmer.extensions:::openai_cost_data_frame(
    list(read_openai_cost_fixture())
  )

  expect_s3_class(costs, "data.frame")
  expect_named(
    costs,
    c(
      "start_time", "end_time", "amount", "currency", "quantity",
      "line_item", "api_key_id", "project_id", "project_name"
    )
  )
  expect_equal(nrow(costs), 2L)
  expect_equal(sum(costs$amount), 0.625)
  expect_equal(unique(costs$api_key_id), "key_fixture")
  expect_equal(unique(costs$project_id), "proj_fixture")
  expect_s3_class(costs$start_time, "POSIXct")
  expect_equal(attr(costs$start_time, "tzone"), "UTC")
  expect_false("organization_name" %in% names(costs))
  expect_false("user_email" %in% names(costs))
})

test_that("OpenAI cost requests encode filters and grouping", {
  req <- ellmer.extensions:::openai_cost_request(
    start_time = 1783728000,
    end_time = 1783900800,
    api_key_ids = c("key_one", "key_two"),
    project_ids = "proj_fixture",
    group_by = c("api_key_id", "line_item"),
    admin_key = "offline-test-key",
    limit = 30L,
    base_url = "https://api.openai.com/v1"
  )
  url <- httr2::url_parse(req$url)

  expect_equal(url$path, "/v1/organization/costs")
  expect_equal(url$query$start_time, "1783728000")
  expect_equal(url$query$end_time, "1783900800")
  expect_equal(url$query$project_ids, "proj_fixture")
  expect_equal(url$query$limit, "30")
  expect_match(req$url, "api_key_ids=key_one", fixed = TRUE)
  expect_match(req$url, "api_key_ids=key_two", fixed = TRUE)
  expect_match(req$url, "group_by=api_key_id", fixed = TRUE)
  expect_match(req$url, "group_by=line_item", fixed = TRUE)
})

test_that("OpenAI cost pagination follows the returned cursor", {
  page_one <- read_openai_cost_fixture()
  page_one$has_more <- TRUE
  page_one$next_page <- "page_fixture_2"

  page_two <- read_openai_cost_fixture()
  page_two$data <- page_two$data[1]

  requests <- character()
  fetch <- function(req) {
    requests <<- c(requests, req$url)
    if (length(requests) == 1L) page_one else page_two
  }

  req <- httr2::request("https://api.openai.com/v1/organization/costs")
  pages <- ellmer.extensions:::openai_cost_pages(req, fetch = fetch)

  expect_length(pages, 2L)
  expect_null(httr2::url_parse(requests[[1]])$query$page)
  expect_equal(
    httr2::url_parse(requests[[2]])$query$page,
    "page_fixture_2"
  )
})

test_that("OpenAI cost argument checks are clear", {
  expect_error(
    openai_costs(Sys.Date(), admin_key = ""),
    "Organization Admin API key"
  )
  expect_error(
    openai_costs(Sys.Date(), end_time = Sys.Date(), admin_key = "fixture"),
    "later than"
  )
  expect_error(
    openai_costs(Sys.Date(), group_by = "model", admin_key = "fixture"),
    "one of"
  )
  expect_error(
    openai_costs(Sys.Date(), limit = 181, admin_key = "fixture"),
    "1 to 180"
  )
})

test_that("OpenAI Costs API works end to end", {
  skip_if_live_tests_disabled("OPENAI_ADMIN_KEY")

  costs <- openai_costs(
    start_time = Sys.Date() - 7,
    end_time = Sys.time(),
    group_by = "line_item",
    limit = 7L
  )

  expect_s3_class(costs, "data.frame")
  expect_true(all(costs$amount >= 0))
  expect_true(all(costs$currency == "usd"))
})
