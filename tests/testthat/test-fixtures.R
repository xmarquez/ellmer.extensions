# Fixture-based tests -----------------------------------------------------
# These tests use real (trimmed) API batch response structures to verify that
# value_turn and batch_result_turn correctly parse production outputs from
# Gemini, Groq, and Anthropic providers.

# Helper: check if any content in a turn matches a class pattern
has_content_class <- function(turn, pattern) {
  any(vapply(turn@contents, function(x) any(grepl(pattern, class(x))), logical(1)))
}

# Helper: extract first content matching a class pattern
get_content <- function(turn, pattern) {
  Filter(function(x) any(grepl(pattern, class(x))), turn@contents)[[1]]
}

# Helper: extract ALL contents matching a class pattern
get_all_content <- function(turn, pattern) {
  Filter(function(x) any(grepl(pattern, class(x))), turn@contents)
}

# Helper: get parsed data from ContentJson (handles both string and data modes)
get_json_data <- function(content_json) {
  if (!is.null(content_json@data)) content_json@data
  else content_json@parsed
}

# Gemini fixture tests ---------------------------------------------------

test_that("batch_result_turn parses real Gemini batch result with thinking", {
  skip_if_not_installed("ellmer")
  skip_if(
    is.null(ellmer.extensions:::ProviderGeminiExtended),
    "ProviderGeminiExtended not initialized"
  )

  ellmer_ns <- asNamespace("ellmer")
  tryCatch(suppressMessages(ellmer.extensions:::register_gemini_methods()), error = function(e) NULL)

  provider <- ellmer.extensions:::ProviderGeminiExtended(
    name = "Google/Gemini",
    base_url = "https://generativelanguage.googleapis.com/v1beta/",
    model = "gemini-3.1-pro-preview",
    params = ellmer_ns$params(),
    extra_args = list(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    extra_headers = character()
  )

  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "gemini-batch-result.json"),
    simplifyVector = FALSE
  )

  # batch_result_turn wraps value_turn for batch results
  turn <- ellmer_ns$batch_result_turn(provider, fixture, has_type = TRUE)

  expect_equal(turn@role, "assistant")

  # Gemini value_turn with has_type = TRUE creates ContentJson(string = ...) for

  # each text part. The thinking part and the output part both become ContentJson.
  # The last one contains the actual structured output.
  json_items <- get_all_content(turn, "ContentJson")
  expect_gte(length(json_items), 1)

  # The last ContentJson should be the structured output
  output_json <- json_items[[length(json_items)]]
  parsed <- get_json_data(output_json)
  expect_equal(parsed$score, 0.1)
  expect_true(nzchar(parsed$explanation))
  expect_true(is.list(parsed$populist))
  expect_true(is.list(parsed$non_populist))
})

# Groq fixture tests -----------------------------------------------------

test_that("batch_result_turn parses real Groq batch result", {
  skip_if_not_installed("ellmer")
  skip_if(
    is.null(ellmer.extensions:::ProviderGroqDeveloper),
    "ProviderGroqDeveloper not initialized"
  )

  ellmer_ns <- asNamespace("ellmer")
  tryCatch(suppressMessages(ellmer.extensions:::register_groq_methods()), error = function(e) NULL)

  provider <- ellmer.extensions:::ProviderGroqDeveloper(
    name = "Groq",
    base_url = "https://api.groq.com/openai/v1",
    model = "openai/gpt-oss-120b",
    params = ellmer_ns$params(),
    extra_args = list(),
    extra_headers = character(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key")
  )

  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "groq-batch-result.json"),
    simplifyVector = FALSE
  )

  turn <- ellmer_ns$batch_result_turn(provider, fixture, has_type = TRUE)

  expect_equal(turn@role, "assistant")

  # Groq (OpenAICompatible) with has_type = TRUE: ContentJson(string = content)
  expect_true(has_content_class(turn, "ContentJson"))
  json_content <- get_content(turn, "ContentJson")
  parsed <- get_json_data(json_content)
  expect_equal(parsed$score, 1.4)
  expect_true(nzchar(parsed$explanation))
  expect_true(is.list(parsed$populist))
})

# Anthropic fixture tests (tool_use path, no thinking) -------------------

test_that("value_turn parses real Anthropic batch result with tool_use", {
  skip_if_not_installed("ellmer")
  skip_if(
    is.null(ellmer.extensions:::ProviderAnthropicExtended),
    "ProviderAnthropicExtended not initialized"
  )

  ellmer_ns <- asNamespace("ellmer")
  tryCatch(suppressMessages(ellmer.extensions:::register_anthropic_methods()), error = function(e) NULL)

  # Provider without thinking (standard tool_choice path)
  provider <- ellmer.extensions:::ProviderAnthropicExtended(
    name = "Anthropic",
    model = "claude-sonnet-4-5-20250929",
    params = ellmer_ns$params(),
    extra_args = list(),
    extra_headers = character(),
    base_url = "https://api.anthropic.com/v1",
    beta_headers = character(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    cache = "none"
  )
  # No thinking attribute set — this is the standard path

  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "anthropic-batch-result-tool-use.json"),
    simplifyVector = FALSE
  )

  turn <- ellmer_ns$value_turn(provider, fixture$message, has_type = TRUE)

  expect_equal(turn@role, "assistant")

  # Standard path: tool_use with data wrapper → ContentJson(data = ...)
  expect_true(has_content_class(turn, "ContentJson"))
  json_content <- get_content(turn, "ContentJson")
  expect_equal(json_content@data$score, 0.4)
  expect_true(nzchar(json_content@data$explanation))
  expect_true(is.list(json_content@data$populist))
})

# Anthropic fixture tests (thinking + text path) -------------------------

test_that("value_turn parses Anthropic thinking result with JSON text", {
  skip_if_not_installed("ellmer")
  skip_if(
    is.null(ellmer.extensions:::ProviderAnthropicExtended),
    "ProviderAnthropicExtended not initialized"
  )

  ellmer_ns <- asNamespace("ellmer")
  tryCatch(suppressMessages(ellmer.extensions:::register_anthropic_methods()), error = function(e) NULL)

  # Provider WITH thinking (output_config.format path) — real Sonnet 4.6
  # adaptive thinking result from batch API
  provider <- ellmer.extensions:::ProviderAnthropicExtended(
    name = "Anthropic",
    model = "claude-sonnet-4-6",
    params = ellmer_ns$params(),
    extra_args = list(),
    extra_headers = character(),
    base_url = "https://api.anthropic.com/v1",
    beta_headers = character(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    cache = "none"
  )
  attr(provider, ".anthropic_thinking") <- "adaptive"

  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "anthropic-batch-result-thinking.json"),
    simplifyVector = FALSE
  )

  turn <- ellmer_ns$value_turn(provider, fixture, has_type = TRUE)

  expect_equal(turn@role, "assistant")

  # Thinking path: thinking block + text-as-JSON → ContentJson(data = ...)
  expect_true(has_content_class(turn, "ContentThinking"))
  expect_true(has_content_class(turn, "ContentJson"))

  json_content <- get_content(turn, "ContentJson")
  expect_equal(json_content@data$score, 0.0)
  expect_true(nzchar(json_content@data$explanation))
  expect_true(is.list(json_content@data$populist))
  expect_true(is.list(json_content@data$non_populist))

  # Verify thinking content is preserved (fixture has 2 thinking blocks from

  # adaptive thinking self-correction loop)
  thinking_items <- get_all_content(turn, "ContentThinking")
  expect_equal(length(thinking_items), 2)
  expect_true(nzchar(thinking_items[[1]]@thinking))
})

test_that("Anthropic batch result with thinking (simple, single block) parses correctly", {
  skip_if_not_installed("ellmer")
  skip_if(
    is.null(ellmer.extensions:::ProviderAnthropicExtended),
    "ProviderAnthropicExtended not initialized"
  )

  ellmer_ns <- asNamespace("ellmer")
  tryCatch(suppressMessages(ellmer.extensions:::register_anthropic_methods()), error = function(e) NULL)

  provider <- ellmer.extensions:::ProviderAnthropicExtended(
    name = "Anthropic",
    model = "claude-sonnet-4-6",
    params = ellmer_ns$params(),
    extra_args = list(),
    extra_headers = character(),
    base_url = "https://api.anthropic.com/v1",
    beta_headers = character(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    cache = "none"
  )
  attr(provider, ".anthropic_thinking") <- "adaptive"

  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "anthropic-batch-result-thinking-simple.json"),
    simplifyVector = FALSE
  )

  turn <- ellmer_ns$value_turn(provider, fixture, has_type = TRUE)

  expect_equal(turn@role, "assistant")

  # Single thinking block + single text block → ContentJson
  expect_true(has_content_class(turn, "ContentThinking"))
  expect_true(has_content_class(turn, "ContentJson"))

  json_content <- get_content(turn, "ContentJson")
  expect_equal(json_content@data$score, 0.3)
  expect_true(nzchar(json_content@data$explanation))
  expect_true(is.list(json_content@data$populist))
  expect_true(is.list(json_content@data$non_populist))

  # Only 1 thinking block (no self-correction loop)
  thinking_items <- get_all_content(turn, "ContentThinking")
  expect_equal(length(thinking_items), 1)
  expect_true(nzchar(thinking_items[[1]]@thinking))
})

# Anthropic fixture tests (truncated / max_tokens) --------------------------

test_that("Anthropic truncated response (max_tokens) warns and recovers JSON", {
  skip_if_not_installed("ellmer")
  skip_if(
    is.null(ellmer.extensions:::ProviderAnthropicExtended),
    "ProviderAnthropicExtended not initialized"
  )

  ellmer_ns <- asNamespace("ellmer")
  tryCatch(suppressMessages(ellmer.extensions:::register_anthropic_methods()), error = function(e) NULL)

  provider <- ellmer.extensions:::ProviderAnthropicExtended(
    name = "Anthropic",
    model = "claude-sonnet-4-6",
    params = ellmer_ns$params(),
    extra_args = list(),
    extra_headers = character(),
    base_url = "https://api.anthropic.com/v1",
    beta_headers = character(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    cache = "none"
  )
  attr(provider, ".anthropic_thinking") <- "adaptive"

  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "anthropic-batch-result-thinking-truncated.json"),
    simplifyVector = FALSE
  )

  # Should warn about truncation
  expect_warning(
    turn <- ellmer_ns$value_turn(provider, fixture, has_type = TRUE),
    "truncated"
  )

  expect_equal(turn@role, "assistant")

  # Despite truncation, JSON was recovered from an earlier complete text block
  expect_true(has_content_class(turn, "ContentJson"))
  json_content <- get_content(turn, "ContentJson")
  expect_equal(json_content@data$score, 0.2)
  expect_true(nzchar(json_content@data$explanation))

  # All 3 thinking blocks preserved
  thinking_items <- get_all_content(turn, "ContentThinking")
  expect_equal(length(thinking_items), 3)
})
