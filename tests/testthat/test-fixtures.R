content_items <- function(turn, class) {
  Filter(function(x) S7::S7_inherits(x, class), turn@contents)
}

content_json_data <- function(content) {
  if (!is.null(content@data)) content@data else content@parsed
}

test_that("real Gemini batch fixture preserves thinking and structured data", {
  ellmer_ns <- asNamespace("ellmer")
  chat <- chat_gemini_extended(
    model = "gemini-3.1-pro-preview",
    credentials = function() "offline-test-key"
  )
  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "gemini-batch-result.json"),
    simplifyVector = FALSE
  )

  turn <- ellmer_ns$batch_result_turn(
    chat$get_provider(),
    fixture,
    has_type = TRUE
  )

  thinking <- content_items(turn, ellmer_ns$ContentThinking)
  json <- content_items(turn, ellmer_ns$ContentJson)
  expect_length(thinking, 1L)
  expect_length(json, 1L)
  expect_true(nzchar(thinking[[1]]@thinking))
  expect_equal(content_json_data(json[[1]])$score, 0.1)
})

test_that("real Groq batch fixture parses structured data", {
  ellmer_ns <- asNamespace("ellmer")
  chat <- chat_groq_developer(
    model = "openai/gpt-oss-120b",
    credentials = function() "offline-test-key"
  )
  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "groq-batch-result.json"),
    simplifyVector = FALSE
  )

  turn <- ellmer_ns$batch_result_turn(
    chat$get_provider(),
    fixture,
    has_type = TRUE
  )

  json <- content_items(turn, ellmer_ns$ContentJson)
  expect_length(json, 1L)
  expect_equal(content_json_data(json[[1]])$score, 1.4)
})

test_that("real Anthropic thinking fixture parses structured data", {
  ellmer_ns <- asNamespace("ellmer")
  chat <- chat_anthropic_extended(
    model = "claude-sonnet-4-6",
    thinking = "adaptive",
    credentials = function() "offline-test-key"
  )
  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "anthropic-batch-result-thinking-simple.json"),
    simplifyVector = FALSE
  )

  turn <- ellmer_ns$value_turn(
    chat$get_provider(),
    fixture,
    has_type = TRUE
  )

  thinking <- content_items(turn, ellmer_ns$ContentThinking)
  json <- content_items(turn, ellmer_ns$ContentJson)
  expect_length(thinking, 1L)
  expect_length(json, 1L)
  expect_equal(content_json_data(json[[1]])$score, 0.3)
})
