# Provider class structure ------------------------------------------------

test_that("ProviderGeminiExtended class is properly defined", {
  skip_if_not_installed("ellmer")

  provider_class <- ellmer.extensions:::ProviderGeminiExtended
  expect_true(inherits(provider_class, "S7_class"))

  parent_class <- attr(provider_class, "parent")
  expect_equal(attr(parent_class, "name"), "ProviderGoogleGemini")
})

test_that("ProviderGeminiExtended has batch support", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  provider <- ellmer.extensions:::ProviderGeminiExtended(
    name = "Google/Gemini",
    base_url = "https://generativelanguage.googleapis.com/v1beta/",
    model = "gemini-2.5-flash",
    params = ellmer_ns$params(),
    extra_args = list(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    extra_headers = character()
  )

  expect_true(ellmer_ns$has_batch_support(provider))
})

test_that("chat_gemini_extended creates a valid Chat object", {
  skip_if_not_installed("ellmer")

  chat <- chat_gemini_extended(
    credentials = function() "dummy_key_for_testing"
  )

  expect_s3_class(chat, "Chat")
  provider <- chat$get_provider()
  expect_true(S7::S7_inherits(provider, ellmer.extensions:::ProviderGeminiExtended))
})

test_that("chat_gemini_extended allows model selection", {
  skip_if_not_installed("ellmer")

  chat <- chat_gemini_extended(
    model = "gemini-2.0-flash",
    credentials = function() "dummy_key_for_testing"
  )

  expect_s3_class(chat, "Chat")
  expect_equal(chat$get_model(), "gemini-2.0-flash")
})

# Gemini batch helper functions -------------------------------------------

test_that("gemini_extract_index extracts from metadata.request_index", {
  x <- list(metadata = list(request_index = 5L))
  expect_equal(ellmer.extensions:::gemini_extract_index(x), 5L)
})

test_that("gemini_extract_index extracts from custom_id key", {
  x <- list(custom_id = "chat-3")
  expect_equal(ellmer.extensions:::gemini_extract_index(x), 3L)
})

test_that("gemini_extract_index extracts from key field", {
  x <- list(key = "chat-7")
  expect_equal(ellmer.extensions:::gemini_extract_index(x), 7L)
})

test_that("gemini_extract_index returns default when no index found", {
  x <- list(foo = "bar")
  expect_equal(ellmer.extensions:::gemini_extract_index(x, default = 99L), 99L)
})

test_that("gemini_json_fallback parses request_index from malformed line", {
  line <- '{"metadata": {"request_index": 42}, broken json...'
  result <- ellmer.extensions:::gemini_json_fallback(line)

  expect_equal(result$metadata$request_index, 42L)
  expect_equal(result$status$code, 500L)
})

test_that("gemini_json_fallback parses custom_id from malformed line", {
  line <- '{"custom_id": "chat-5", broken...'
  result <- ellmer.extensions:::gemini_json_fallback(line)

  expect_equal(result$metadata$request_index, 5L)
  expect_equal(result$status$code, 500L)
})

test_that("gemini_json_fallback returns empty metadata for unparseable line", {
  line <- "completely broken"
  result <- ellmer.extensions:::gemini_json_fallback(line)

  expect_equal(result$metadata, list())
  expect_equal(result$status$code, 500L)
})

test_that("gemini_normalize_result handles plain GenerateContentResponse", {
  x <- list(
    candidates = list(list(content = list(parts = list(list(text = "hello"))))),
    usageMetadata = list(totalTokenCount = 10L)
  )
  result <- ellmer.extensions:::gemini_normalize_result(x, index_default = 1L)

  expect_equal(result$index, 1L)
  expect_equal(result$result$status_code, 200L)
  expect_equal(result$result$body, x)
})

test_that("gemini_normalize_result handles wrapped response", {
  x <- list(
    metadata = list(request_index = 2L),
    response = list(candidates = list())
  )
  result <- ellmer.extensions:::gemini_normalize_result(x, index_default = 99L)

  expect_equal(result$index, 2L)
  expect_equal(result$result$status_code, 200L)
  expect_equal(result$result$body, list(candidates = list()))
})

test_that("gemini_normalize_result handles error response", {
  x <- list(
    metadata = list(request_index = 3L),
    error = list(code = 400L, message = "bad request")
  )
  result <- ellmer.extensions:::gemini_normalize_result(x, index_default = 99L)

  expect_equal(result$index, 3L)
  expect_equal(result$result$status_code, 400L)
  expect_null(result$result$body)
})

test_that("gemini_normalize_result handles unknown format", {
  x <- list(unknown_field = "value")
  result <- ellmer.extensions:::gemini_normalize_result(x, index_default = 5L)

  expect_equal(result$index, 5L)
  expect_equal(result$result$status_code, 500L)
  expect_null(result$result$body)
})
