test_that("chat_groq_developer remains a compatible entry point", {
  chat <- chat_groq_developer(
    model = "openai/gpt-oss-120b",
    credentials = function() "offline-test-key"
  )

  expect_s3_class(chat, "Chat")
  expect_true(S7::S7_inherits(chat$get_provider(), ProviderGroqDeveloper))
  expect_equal(chat$get_model(), "openai/gpt-oss-120b")
})

test_that("Groq request bodies preserve reasoning effort and API arguments", {
  ellmer_ns <- asNamespace("ellmer")
  chat <- chat_groq_developer(
    model = "openai/gpt-oss-120b",
    params = ellmer::params(reasoning_effort = "low"),
    api_args = list(include_reasoning = FALSE),
    credentials = function() "offline-test-key"
  )

  body <- ellmer_ns$chat_body(chat$get_provider(), stream = FALSE)

  expect_identical(body$reasoning_effort, "low")
  expect_identical(body$include_reasoning, FALSE)
})

test_that("Groq API arguments override common parameters", {
  ellmer_ns <- asNamespace("ellmer")
  chat <- chat_groq_developer(
    model = "openai/gpt-oss-20b",
    params = ellmer::params(reasoning_effort = "low"),
    api_args = list(reasoning_effort = "high"),
    credentials = function() "offline-test-key"
  )

  body <- ellmer_ns$chat_body(chat$get_provider(), stream = FALSE)

  expect_identical(body$reasoning_effort, "high")
})

test_that("Groq retrieves an error-only batch", {
  ellmer_ns <- asNamespace("ellmer")
  chat <- chat_groq_developer(credentials = function() "offline-test-key")
  downloaded <- character()

  local_mocked_bindings(
    openai_download_file = function(provider, id, path) {
      downloaded <<- c(downloaded, id)
      writeLines(
        paste0(
          '{"custom_id":"chat-1","response":',
          '{"status_code":400,"body":{"error":{"message":"bad request"}}}}'
        ),
        path
      )
      invisible(path)
    },
    .package = "ellmer"
  )

  results <- ellmer_ns$batch_retrieve(
    chat$get_provider(),
    list(output_file_id = list(), error_file_id = "file-error")
  )

  expect_identical(downloaded, "file-error")
  expect_length(results, 1)
  expect_identical(results[[1]]$status_code, 400L)
  expect_identical(results[[1]]$body$error$message, "bad request")
})

test_that("Groq batch status treats all terminal states as finished", {
  ellmer_ns <- asNamespace("ellmer")
  chat <- chat_groq_developer(credentials = function() "offline-test-key")
  provider <- chat$get_provider()
  counts <- list(total = 5L, completed = 3L, failed = 2L)

  statuses <- lapply(
    c("completed", "failed", "expired", "cancelled"),
    function(status) {
      ellmer_ns$batch_status(
        provider,
        list(status = status, request_counts = counts)
      )
    }
  )

  expect_true(all(!vapply(statuses, "[[", logical(1), "working")))
  expect_true(all(vapply(statuses, "[[", integer(1), "n_processing") == 0L))
})
