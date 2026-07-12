anthropic_test_credentials <- function() "dummy_key_for_testing"

anthropic_test_body <- function(chat, type = NULL) {
  provider <- chat$get_provider()
  user_turn <- ellmer::Turn("user", list(ellmer::ContentText("Hello")))

  asNamespace("ellmer")$chat_body(
    provider,
    stream = FALSE,
    turns = list(user_turn),
    type = type
  )
}

test_that("ordinary chats delegate to ellmer", {
  chat <- chat_anthropic_extended(credentials = anthropic_test_credentials)
  provider <- chat$get_provider()

  expect_s3_class(chat, "Chat")
  expect_true(S7::S7_inherits(provider, asNamespace("ellmer")$ProviderAnthropic))
  expect_false(S7::S7_inherits(
    provider,
    ellmer.extensions:::ProviderAnthropicExtended
  ))
})

test_that("enabled thinking requires and sends a token budget", {
  expect_error(
    chat_anthropic_extended(
      thinking = "enabled",
      credentials = anthropic_test_credentials
    ),
    "reasoning_tokens"
  )

  chat <- chat_anthropic_extended(
    thinking = "enabled",
    params = ellmer::params(reasoning_tokens = 8192),
    credentials = anthropic_test_credentials
  )
  type <- ellmer::type_object(score = ellmer::type_number())
  body <- anthropic_test_body(chat, type = type)

  expect_equal(body$thinking, list(type = "enabled", budget_tokens = 8192))
  expect_equal(body$output_config$format$type, "json_schema")
  expect_null(body$tool_choice)
  expect_gt(body$max_tokens, body$thinking$budget_tokens)
})

test_that("adaptive thinking puts effort under output_config", {
  expect_no_warning(
    chat <- chat_anthropic_extended(
      model = "claude-opus-4-8",
      thinking = "adaptive",
      params = ellmer::params(reasoning_effort = "low"),
      credentials = anthropic_test_credentials
    )
  )
  type <- ellmer::type_object(score = ellmer::type_number())
  body <- anthropic_test_body(chat, type = type)

  expect_equal(body$thinking, list(type = "adaptive"))
  expect_equal(body$output_config$effort, "low")
  expect_equal(body$output_config$format$type, "json_schema")
  expect_null(body$reasoning_effort)
  expect_null(body$budget_tokens)
  expect_null(body$tool_choice)
})

test_that("adaptive thinking defaults effort and overrides a token budget", {
  chat <- chat_anthropic_extended(
    model = "claude-sonnet-4-6",
    thinking = "adaptive",
    params = ellmer::params(reasoning_tokens = 8192),
    credentials = anthropic_test_credentials
  )
  body <- anthropic_test_body(chat)

  expect_equal(body$thinking, list(type = "adaptive"))
  expect_equal(body$output_config, list(effort = "high"))
  expect_null(body$reasoning_effort)
  expect_null(body$budget_tokens)
  expect_equal(body$max_tokens, 32768)
})

test_that("Anthropic response parsing comes from ellmer when available", {
  chat <- chat_anthropic_extended(
    model = "claude-sonnet-4-6",
    thinking = "adaptive",
    credentials = anthropic_test_credentials
  )
  provider <- chat$get_provider()
  result <- list(
    role = "assistant",
    content = list(
      list(type = "thinking", thinking = "Analysis", signature = "sig"),
      list(type = "text", text = '{"score": 1.5}')
    ),
    stop_reason = "end_turn",
    model = "claude-sonnet-4-6",
    usage = list(
      input_tokens = 10,
      output_tokens = 5,
      cache_creation_input_tokens = 0,
      cache_read_input_tokens = 0
    )
  )

  turn <- asNamespace("ellmer")$value_turn(provider, result, has_type = TRUE)
  classes <- vapply(turn@contents, function(x) class(x)[[1]], character(1))

  expect_true(any(grepl("ContentThinking", classes)))
  expect_true(any(grepl("ContentJson", classes)))

  if (exists("value_finish_reason", envir = asNamespace("ellmer"))) {
    expect_equal(turn@finish_reason, "success")
  }
})
