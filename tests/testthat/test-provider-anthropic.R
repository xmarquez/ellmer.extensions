# Provider class structure ------------------------------------------------

test_that("ProviderAnthropicExtended class is properly defined", {
  skip_if_not_installed("ellmer")

  provider_class <- ellmer.extensions:::ProviderAnthropicExtended
  expect_true(inherits(provider_class, "S7_class"))

  parent_class <- attr(provider_class, "parent")
  expect_equal(attr(parent_class, "name"), "ProviderAnthropic")
})

test_that("chat_anthropic_extended creates a valid Chat object", {
  skip_if_not_installed("ellmer")

  chat <- chat_anthropic_extended(
    model = "claude-sonnet-4-5-20250929",
    credentials = function() "dummy_key_for_testing"
  )

  expect_s3_class(chat, "Chat")
  provider <- chat$get_provider()
  expect_true(S7::S7_inherits(provider, ellmer.extensions:::ProviderAnthropicExtended))
})

test_that("chat_anthropic_extended allows model selection", {
  skip_if_not_installed("ellmer")

  chat <- chat_anthropic_extended(
    model = "claude-haiku-4-5-20251001",
    credentials = function() "dummy_key_for_testing"
  )

  expect_s3_class(chat, "Chat")
  expect_equal(chat$get_model(), "claude-haiku-4-5-20251001")
})

# Thinking parameter validation -------------------------------------------

test_that("thinking = 'enabled' without reasoning_tokens errors", {
  skip_if_not_installed("ellmer")

  expect_error(
    chat_anthropic_extended(
      thinking = "enabled",
      credentials = function() "dummy_key_for_testing"
    ),
    "reasoning_tokens"
  )
})

test_that("thinking = 'enabled' with reasoning_tokens succeeds", {
  skip_if_not_installed("ellmer")

  chat <- chat_anthropic_extended(
    thinking = "enabled",
    params = ellmer::params(reasoning_tokens = 8192),
    credentials = function() "dummy_key_for_testing"
  )

  expect_s3_class(chat, "Chat")
  provider <- chat$get_provider()
  expect_equal(attr(provider, ".anthropic_thinking"), "enabled")
})

test_that("thinking = 'adaptive' errors for 4.5 models", {
  skip_if_not_installed("ellmer")

  expect_error(
    chat_anthropic_extended(
      model = "claude-sonnet-4-5-20250929",
      thinking = "adaptive",
      credentials = function() "dummy_key_for_testing"
    ),
    "not supported"
  )

  expect_error(
    chat_anthropic_extended(
      model = "claude-haiku-4-5-20251001",
      thinking = "adaptive",
      credentials = function() "dummy_key_for_testing"
    ),
    "not supported"
  )
})

test_that("thinking = 'adaptive' warns for unknown models", {
  skip_if_not_installed("ellmer")

  expect_warning(
    chat_anthropic_extended(
      model = "claude-unknown-5-0",
      thinking = "adaptive",
      credentials = function() "dummy_key_for_testing"
    ),
    "Verify"
  )
})

test_that("thinking = 'adaptive' succeeds silently for 4.6 models", {
  skip_if_not_installed("ellmer")

  # Should not warn or error
  chat <- chat_anthropic_extended(
    model = "claude-sonnet-4-6-20260301",
    thinking = "adaptive",
    credentials = function() "dummy_key_for_testing"
  )

  expect_s3_class(chat, "Chat")
  provider <- chat$get_provider()
  expect_equal(attr(provider, ".anthropic_thinking"), "adaptive")
})

test_that("auto-detect: reasoning_tokens in params enables thinking", {
  skip_if_not_installed("ellmer")

  chat <- chat_anthropic_extended(
    params = ellmer::params(reasoning_tokens = 4096),
    credentials = function() "dummy_key_for_testing"
  )

  provider <- chat$get_provider()
  expect_equal(attr(provider, ".anthropic_thinking"), "enabled")
})

test_that("no thinking when no reasoning_tokens and thinking = NULL", {
  skip_if_not_installed("ellmer")

  chat <- chat_anthropic_extended(
    credentials = function() "dummy_key_for_testing"
  )

  provider <- chat$get_provider()
  expect_null(attr(provider, ".anthropic_thinking"))
})

test_that("invalid thinking value errors", {
  skip_if_not_installed("ellmer")

  expect_error(
    chat_anthropic_extended(
      thinking = "invalid",
      credentials = function() "dummy_key_for_testing"
    ),
    "arg"
  )
})

# chat_body construction --------------------------------------------------

# Helper to create a provider for chat_body tests
make_test_provider <- function(thinking = NULL, reasoning_tokens = NULL) {
  ellmer_ns <- asNamespace("ellmer")

  tryCatch(
    suppressMessages(ellmer.extensions:::register_anthropic_methods()),
    error = function(e) NULL
  )

  params <- if (!is.null(reasoning_tokens)) {
    ellmer::params(reasoning_tokens = reasoning_tokens)
  } else {
    ellmer_ns$params()
  }

  provider <- ellmer.extensions:::ProviderAnthropicExtended(
    name = "Anthropic",
    model = "claude-sonnet-4-5-20250929",
    params = params,
    extra_args = list(),
    extra_headers = character(),
    base_url = "https://api.anthropic.com/v1",
    beta_headers = character(),
    credentials = function() "dummy_key_for_testing",
    cache = "none"
  )

  if (!is.null(thinking)) {
    attr(provider, ".anthropic_thinking") <- thinking
  }

  provider
}

test_that("chat_body with thinking + type uses output_config.format", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  chat_body <- ellmer_ns$chat_body

  provider <- make_test_provider(thinking = "enabled", reasoning_tokens = 8192)

  system_turn <- ellmer::Turn("system", list(ellmer::ContentText("You are helpful.")))
  user_turn <- ellmer::Turn("user", list(ellmer::ContentText("Hello")))
  type <- ellmer::type_object(score = ellmer::type_number())

  body <- chat_body(provider, stream = FALSE, turns = list(system_turn, user_turn), type = type)

  # Should have output_config with json_schema
  expect_true("output_config" %in% names(body))
  expect_equal(body$output_config$format$type, "json_schema")

  # Schema should match the type directly (no {data: ...} wrapper)
  schema <- body$output_config$format$schema
  expect_true("score" %in% names(schema$properties))

  # Should have thinking enabled
  expect_equal(body$thinking$type, "enabled")
  expect_equal(body$thinking$budget_tokens, 8192)

  # Should NOT have tool_choice
  expect_null(body$tool_choice)
})

test_that("chat_body with type only (no thinking) uses forced tool_choice", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  chat_body <- ellmer_ns$chat_body

  provider <- make_test_provider()  # no thinking

  user_turn <- ellmer::Turn("user", list(ellmer::ContentText("Hello")))
  type <- ellmer::type_object(score = ellmer::type_number())

  body <- chat_body(provider, stream = FALSE, turns = list(user_turn), type = type)

  # Should have forced tool_choice
  expect_equal(body$tool_choice$type, "tool")
  expect_equal(body$tool_choice$name, "_structured_tool_call")

  # Should NOT have output_config
  expect_null(body$output_config)

  # Should NOT have thinking
  expect_null(body$thinking)
})

test_that("chat_body with thinking but no type works normally", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  chat_body <- ellmer_ns$chat_body

  provider <- make_test_provider(thinking = "enabled", reasoning_tokens = 4096)

  user_turn <- ellmer::Turn("user", list(ellmer::ContentText("Hello")))

  body <- chat_body(provider, stream = TRUE, turns = list(user_turn))

  # Should have thinking
  expect_equal(body$thinking$type, "enabled")
  expect_equal(body$thinking$budget_tokens, 4096)

  # Should NOT have output_config, tools, or tool_choice
  expect_null(body$output_config)
  expect_null(body$tool_choice)
})

test_that("chat_body with adaptive thinking + type uses output_config.format", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  chat_body <- ellmer_ns$chat_body

  provider <- make_test_provider(thinking = "adaptive")

  user_turn <- ellmer::Turn("user", list(ellmer::ContentText("Hello")))
  type <- ellmer::type_object(label = ellmer::type_string())

  body <- chat_body(provider, stream = FALSE, turns = list(user_turn), type = type)

  # Should have output_config
  expect_true("output_config" %in% names(body))

  # Should have adaptive thinking
  expect_equal(body$thinking$type, "adaptive")

  # Should NOT have budget_tokens for adaptive
  expect_null(body$thinking$budget_tokens)

  # No tool_choice
  expect_null(body$tool_choice)
})

test_that("chat_body with adaptive thinking strips budget_tokens from params", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  chat_body <- ellmer_ns$chat_body

  # Adaptive provider but with reasoning_tokens in params (should be stripped)
  provider <- make_test_provider(thinking = "adaptive", reasoning_tokens = 8192)

  user_turn <- ellmer::Turn("user", list(ellmer::ContentText("Hello")))
  type <- ellmer::type_object(label = ellmer::type_string())

  body <- chat_body(provider, stream = FALSE, turns = list(user_turn), type = type)

  # Should have adaptive thinking, NOT enabled
  expect_equal(body$thinking$type, "adaptive")
  # budget_tokens must NOT leak into the body
  expect_null(body$thinking$budget_tokens)
  expect_null(body$budget_tokens)
})

# value_turn parsing ------------------------------------------------------

# Helper: check if any content in a turn matches a class pattern
has_content_class <- function(turn, pattern) {
  any(vapply(turn@contents, function(x) any(grepl(pattern, class(x))), logical(1)))
}

# Helper: extract first content matching a class pattern
get_content <- function(turn, pattern) {
  Filter(function(x) any(grepl(pattern, class(x))), turn@contents)[[1]]
}

test_that("value_turn parses text-as-JSON when thinking + has_type", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  value_turn <- ellmer_ns$value_turn

  provider <- make_test_provider(thinking = "enabled", reasoning_tokens = 8192)

  # Mock an Anthropic response with thinking + text (JSON)
  result <- list(
    role = "assistant",
    content = list(
      list(
        type = "thinking",
        thinking = "Let me analyze this...",
        signature = "sig123"
      ),
      list(
        type = "text",
        text = '{"score": 1.5, "label": "moderate"}'
      )
    ),
    model = "claude-sonnet-4-5-20250929",
    usage = list(
      input_tokens = 100,
      output_tokens = 50,
      cache_creation_input_tokens = 0,
      cache_read_input_tokens = 0
    )
  )

  turn <- value_turn(provider, result, has_type = TRUE)

  expect_equal(turn@role, "assistant")

  # Should have ContentThinking + ContentJson
  expect_true(has_content_class(turn, "ContentThinking"))
  expect_true(has_content_class(turn, "ContentJson"))

  # Check ContentJson data — no {data: ...} wrapper
  json_content <- get_content(turn, "ContentJson")
  expect_equal(json_content@data$score, 1.5)
  expect_equal(json_content@data$label, "moderate")
})

test_that("value_turn joins multiple text blocks before parsing", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  value_turn <- ellmer_ns$value_turn

  provider <- make_test_provider(thinking = "enabled", reasoning_tokens = 8192)

  result <- list(
    role = "assistant",
    content = list(
      list(type = "text", text = '{"score":'),
      list(type = "text", text = ' 2.0}')
    ),
    model = "claude-sonnet-4-5-20250929",
    usage = list(
      input_tokens = 100, output_tokens = 50,
      cache_creation_input_tokens = 0, cache_read_input_tokens = 0
    )
  )

  turn <- value_turn(provider, result, has_type = TRUE)

  json_content <- get_content(turn, "ContentJson")
  expect_equal(json_content@data$score, 2.0)
})

test_that("value_turn falls back to ContentText for non-JSON text", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  value_turn <- ellmer_ns$value_turn

  provider <- make_test_provider(thinking = "enabled", reasoning_tokens = 8192)

  result <- list(
    role = "assistant",
    content = list(
      list(
        type = "text",
        text = "This is just plain text, not JSON."
      )
    ),
    model = "claude-sonnet-4-5-20250929",
    usage = list(
      input_tokens = 100, output_tokens = 50,
      cache_creation_input_tokens = 0, cache_read_input_tokens = 0
    )
  )

  turn <- value_turn(provider, result, has_type = TRUE)

  # Non-JSON text should become ContentText
  expect_true(has_content_class(turn, "ContentText"))
  expect_false(has_content_class(turn, "ContentJson"))
})

test_that("value_turn with has_type = FALSE treats text as ContentText", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  value_turn <- ellmer_ns$value_turn

  provider <- make_test_provider(thinking = "enabled", reasoning_tokens = 8192)

  result <- list(
    role = "assistant",
    content = list(
      list(
        type = "text",
        text = '{"score": 1.5}'
      )
    ),
    model = "claude-sonnet-4-5-20250929",
    usage = list(
      input_tokens = 100, output_tokens = 50,
      cache_creation_input_tokens = 0, cache_read_input_tokens = 0
    )
  )

  # has_type = FALSE means this is a regular chat, not structured output
  turn <- value_turn(provider, result, has_type = FALSE)

  expect_true(has_content_class(turn, "ContentText"))
  expect_false(has_content_class(turn, "ContentJson"))
})

test_that("value_turn without thinking handles tool_use normally", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  value_turn <- ellmer_ns$value_turn

  provider <- make_test_provider()  # no thinking

  result <- list(
    role = "assistant",
    content = list(
      list(
        type = "tool_use",
        id = "toolu_123",
        name = "_structured_tool_call",
        input = list(data = list(score = 2.0))
      )
    ),
    model = "claude-sonnet-4-5-20250929",
    usage = list(
      input_tokens = 100, output_tokens = 50,
      cache_creation_input_tokens = 0, cache_read_input_tokens = 0
    )
  )

  turn <- value_turn(provider, result, has_type = TRUE)

  json_content <- get_content(turn, "ContentJson")
  expect_equal(json_content@data$score, 2.0)
})

test_that("value_turn preserves tool_use alongside thinking", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  value_turn <- ellmer_ns$value_turn

  provider <- make_test_provider(thinking = "enabled", reasoning_tokens = 8192)

  # Response with thinking + tool_use (real tool, not structured output)
  result <- list(
    role = "assistant",
    content = list(
      list(
        type = "thinking",
        thinking = "I need to search...",
        signature = "sig456"
      ),
      list(
        type = "tool_use",
        id = "toolu_789",
        name = "search",
        input = list(query = "test")
      ),
      list(
        type = "text",
        text = '{"score": 1.0}'
      )
    ),
    model = "claude-sonnet-4-5-20250929",
    usage = list(
      input_tokens = 100, output_tokens = 50,
      cache_creation_input_tokens = 0, cache_read_input_tokens = 0
    )
  )

  turn <- value_turn(provider, result, has_type = TRUE)

  expect_true(has_content_class(turn, "ContentThinking"))
  expect_true(has_content_class(turn, "ContentToolRequest"))
  expect_true(has_content_class(turn, "ContentJson"))
})
