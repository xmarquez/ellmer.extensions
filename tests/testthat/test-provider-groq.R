# Provider class structure ------------------------------------------------

test_that("ProviderGroqDeveloper class is properly defined", {
  skip_if_not_installed("ellmer")

  # Check that the class exists and is an S7 class
  expect_true(inherits(ProviderGroqDeveloper, "S7_class"))

  # Check that it extends ProviderOpenAICompatible
  parent_class <- attr(ProviderGroqDeveloper, "parent")
  expect_equal(attr(parent_class, "name"), "ProviderOpenAICompatible")
})

test_that("ProviderGroqDeveloper can be created directly", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  provider <- ProviderGroqDeveloper(
    name = "Groq",
    base_url = "https://api.groq.com/openai/v1",
    model = "openai/gpt-oss-20b",
    params = ellmer_ns$params(),
    extra_args = list(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    extra_headers = character()
  )

  expect_true(S7::S7_inherits(provider, ProviderGroqDeveloper))
  expect_true(S7::S7_inherits(provider, ellmer_ns$ProviderOpenAICompatible))
})

test_that("chat_groq_developer creates a valid Chat object", {
  skip_if_not_installed("ellmer")

  chat <- chat_groq_developer(credentials = function() "dummy_key_for_testing")

  expect_s3_class(chat, "Chat")
  provider <- chat$get_provider()
  expect_true(S7::S7_inherits(provider, ProviderGroqDeveloper))
})

test_that("chat_groq_developer allows model selection", {
  skip_if_not_installed("ellmer")

  chat <- chat_groq_developer(
    model = "openai/gpt-oss-120b",
    credentials = function() "dummy_key_for_testing"
  )

  expect_s3_class(chat, "Chat")
  expect_equal(chat$get_model(), "openai/gpt-oss-120b")
})

# Schema generation -------------------------------------------------------

test_that("Schema generation adds additionalProperties: false", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  provider <- ProviderGroqDeveloper(
    name = "Groq",
    base_url = "https://api.groq.com/openai/v1",
    model = "openai/gpt-oss-20b",
    params = ellmer_ns$params(),
    extra_args = list(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    extra_headers = character()
  )

  type_obj <- ellmer_ns$type_object(
    name = ellmer_ns$type_string(),
    age = ellmer_ns$type_integer()
  )

  schema <- ellmer_ns$as_json(provider, type_obj)

  expect_equal(schema$type, "object")
  expect_equal(schema$additionalProperties, FALSE)
  expect_true("name" %in% names(schema$properties))
  expect_true("age" %in% names(schema$properties))
})

test_that("Nested object schema has recursive additionalProperties: false", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  provider <- ProviderGroqDeveloper(
    name = "Groq",
    base_url = "https://api.groq.com/openai/v1",
    model = "openai/gpt-oss-20b",
    params = ellmer_ns$params(),
    extra_args = list(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    extra_headers = character()
  )

  type_nested <- ellmer_ns$type_object(
    person = ellmer_ns$type_object(
      name = ellmer_ns$type_string(),
      age = ellmer_ns$type_integer()
    ),
    address = ellmer_ns$type_object(
      city = ellmer_ns$type_string(),
      country = ellmer_ns$type_string()
    )
  )

  schema_nested <- ellmer_ns$as_json(provider, type_nested)

  expect_equal(schema_nested$additionalProperties, FALSE)
  expect_equal(schema_nested$properties$person$additionalProperties, FALSE)
  expect_equal(schema_nested$properties$address$additionalProperties, FALSE)
})

test_that("Array schema has additionalProperties: false on items", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  provider <- ProviderGroqDeveloper(
    name = "Groq",
    base_url = "https://api.groq.com/openai/v1",
    model = "openai/gpt-oss-20b",
    params = ellmer_ns$params(),
    extra_args = list(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    extra_headers = character()
  )

  type_arr <- ellmer_ns$type_array(
    ellmer_ns$type_object(name = ellmer_ns$type_string())
  )

  schema_arr <- ellmer_ns$as_json(provider, type_arr)

  expect_equal(schema_arr$type, "array")
  expect_equal(schema_arr$items$type, "object")
  expect_equal(schema_arr$items$additionalProperties, FALSE)
})

# Batch support -----------------------------------------------------------

test_that("ProviderGroqDeveloper has batch support", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  provider <- ProviderGroqDeveloper(
    name = "Groq",
    base_url = "https://api.groq.com/openai/v1",
    model = "openai/gpt-oss-20b",
    params = ellmer_ns$params(),
    extra_args = list(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    extra_headers = character()
  )

  expect_true(ellmer_ns$has_batch_support(provider))
})

test_that("batch_retrieve handles malformed JSON gracefully", {
  skip_if_not_installed("ellmer")

  # Test the fallback function directly
  result <- ellmer.extensions:::groq_json_fallback('{"custom_id": "chat-1", ')
  expect_equal(result$custom_id, "chat-1")
  expect_equal(result$response$status_code, 500)
  expect_null(result$response$body)

  # Test with unknown custom_id
  result2 <- ellmer.extensions:::groq_json_fallback("malformed json")
  expect_equal(result2$custom_id, "unknown")
  expect_equal(result2$response$status_code, 500)
})

# URL construction --------------------------------------------------------

test_that("groq_upload_file builds clean URL path without double slashes", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  provider <- ProviderGroqDeveloper(
    name = "Groq",
    base_url = "https://api.groq.com/openai/v1",
    model = "openai/gpt-oss-20b",
    params = ellmer_ns$params(),
    extra_args = list(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    extra_headers = character()
  )

  # Build the same request as groq_upload_file without performing it
  req <- ellmer_ns$base_request(provider)
  req <- httr2::req_url_path_append(req, "files")
  expect_false(grepl("//files", req$url))
})

test_that("groq_download_file builds clean URL path without double slashes", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  provider <- ProviderGroqDeveloper(
    name = "Groq",
    base_url = "https://api.groq.com/openai/v1",
    model = "openai/gpt-oss-20b",
    params = ellmer_ns$params(),
    extra_args = list(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    extra_headers = character()
  )

  req <- ellmer_ns$base_request(provider)
  req <- httr2::req_url_path_append(req, "files", "file-abc123", "content")
  expect_false(grepl("//", sub("^https://", "", req$url)))
})

# batch_status edge cases -------------------------------------------------

test_that("batch_status clamps n_processing to zero", {
  skip_if_not_installed("ellmer")

  ellmer_ns <- asNamespace("ellmer")
  provider <- ProviderGroqDeveloper(
    name = "Groq",
    base_url = "https://api.groq.com/openai/v1",
    model = "openai/gpt-oss-20b",
    params = ellmer_ns$params(),
    extra_args = list(),
    credentials = ellmer_ns$as_credentials("test", function() "test_key"),
    extra_headers = character()
  )

  # Simulate a batch where completed > total (shouldn't happen but test the clamp)
  batch <- list(
    status = "completed",
    request_counts = list(total = 5, completed = 6, failed = 0)
  )
  status <- ellmer_ns$batch_status(provider, batch)
  expect_equal(status$n_processing, 0L)
})
