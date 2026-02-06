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
  skip_if(
    is.null(ellmer.extensions:::ProviderGeminiExtended),
    "ProviderGeminiExtended not initialized"
  )

  ellmer_ns <- asNamespace("ellmer")

  # Defensive re-registration (mirrors chat_gemini_extended behaviour)
  tryCatch(suppressMessages(ellmer.extensions:::register_gemini_methods()), error = function(e) NULL)

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

# gemini_prepare_batch_body -----------------------------------------------

test_that("gemini_prepare_batch_body converts API keys to snake_case", {
  body <- list(
    generationConfig = list(responseMimeType = "text/plain"),
    contents = list(list(role = "user", parts = list(list(text = "hi"))))
  )

  result <- ellmer.extensions:::gemini_prepare_batch_body(body)

  expect_true("generation_config" %in% names(result))
  expect_null(result$generationConfig)
  expect_true("response_mime_type" %in% names(result$generation_config))
})

test_that("gemini_prepare_batch_body preserves schema property names", {
  body <- list(
    generationConfig = list(
      responseMimeType = "application/json",
      responseSchema = list(
        type = "object",
        properties = list(
          firstName = list(type = "string"),
          lastName = list(type = "string")
        ),
        required = list("firstName", "lastName")
      )
    ),
    contents = list(list(role = "user", parts = list(list(text = "hi"))))
  )
  result <- ellmer.extensions:::gemini_prepare_batch_body(body)

  schema <- result$generation_config$response_json_schema
  expect_false(is.null(schema))
  # Property names must be preserved as-is, not converted to snake_case

  expect_true("firstName" %in% names(schema$properties))
  expect_true("lastName" %in% names(schema$properties))
  expect_equal(schema$required, list("firstName", "lastName"))
  # The old field name must be removed
  expect_null(result$generation_config$response_schema)
})

test_that("gemini_prepare_batch_body strips empty system instruction", {
  body <- list(
    systemInstruction = list(parts = list(text = "")),
    contents = list(list(role = "user", parts = list(list(text = "hi"))))
  )
  result <- ellmer.extensions:::gemini_prepare_batch_body(body)

  expect_null(result$system_instruction)
  expect_null(result$systemInstruction)
})

test_that("gemini_prepare_batch_body keeps non-empty system instruction", {
  body <- list(
    systemInstruction = list(parts = list(text = "You are helpful.")),
    contents = list(list(role = "user", parts = list(list(text = "hi"))))
  )
  result <- ellmer.extensions:::gemini_prepare_batch_body(body)

  expect_false(is.null(result$system_instruction))
  expect_equal(result$system_instruction$parts$text, "You are helpful.")
})

# Credential fallback -----------------------------------------------------

test_that("chat_gemini_extended fallback checks GOOGLE_API_KEY", {
  skip_if_not_installed("ellmer")

  # When ellmer does NOT export default_google_credentials (old versions),
  # the fallback function should try GEMINI_API_KEY first, then GOOGLE_API_KEY.
  ellmer_ns <- asNamespace("ellmer")

  # Only test the fallback path (when default_google_credentials doesn't exist)
  skip_if(
    exists("default_google_credentials", envir = ellmer_ns, inherits = FALSE),
    "ellmer has default_google_credentials; fallback path not used"
  )

  withr::local_envvar(GEMINI_API_KEY = "", GOOGLE_API_KEY = "test-google-key")
  chat <- chat_gemini_extended(model = "gemini-2.5-flash")
  expect_s3_class(chat, "Chat")
})
