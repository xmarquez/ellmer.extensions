new_test_gemini_provider <- function(model = "gemini-2.5-flash") {
  ellmer_ns <- asNamespace("ellmer")
  ellmer.extensions:::ProviderGeminiExtended(
    name = "Google/Gemini",
    base_url = "https://generativelanguage.googleapis.com/v1beta/",
    model = model,
    params = ellmer_ns$params(),
    extra_args = list(),
    credentials = ellmer_ns$as_credentials("test", function() "test-key"),
    extra_headers = character()
  )
}

test_that("chat_gemini_extended preserves its public constructor", {
  chat <- chat_gemini_extended(
    model = "gemini-2.0-flash",
    credentials = function() "test-key"
  )

  expect_s3_class(chat, "Chat")
  expect_equal(chat$get_model(), "gemini-2.0-flash")
  expect_true(S7::S7_inherits(
    chat$get_provider(),
    ellmer.extensions:::ProviderGeminiExtended
  ))
})

test_that("Gemini extension reports batch support", {
  expect_true(asNamespace("ellmer")$has_batch_support(new_test_gemini_provider()))
})

test_that("gemini_prepare_batch_body prepares structured requests", {
  body <- list(
    systemInstruction = list(parts = list(text = "")),
    generationConfig = list(
      responseMimeType = "application/json",
      responseSchema = list(
        type = "object",
        properties = list(firstName = list(type = "string"))
      )
    )
  )

  result <- ellmer.extensions:::gemini_prepare_batch_body(body)

  expect_null(result$system_instruction)
  expect_equal(result$generation_config$response_mime_type, "application/json")
  expect_true("firstName" %in%
                names(result$generation_config$response_json_schema$properties))
  expect_null(result$generation_config$response_schema)
})

test_that("batch normalization orders wrapped responses by key", {
  lines <- list(
    list(key = "chat-2", response = list(responseId = "second")),
    list(key = "chat-1", response = list(responseId = "first")),
    list(key = "chat-3", error = list(code = 429L))
  )

  normalized <- purrr::imap(lines, function(x, i) {
    ellmer.extensions:::gemini_normalize_result(x, as.integer(i))
  })
  normalized <- normalized[order(vapply(normalized, `[[`, integer(1), "index"))]

  expect_equal(normalized[[1]]$result$body$responseId, "first")
  expect_equal(normalized[[2]]$result$body$responseId, "second")
  expect_equal(normalized[[3]]$result$status_code, 429L)
})

test_that("Gemini fixture preserves thinking, JSON, and finish reason", {
  fixture <- jsonlite::read_json(
    testthat::test_path("fixtures", "gemini-batch-result.json"),
    simplifyVector = FALSE
  )
  turn <- asNamespace("ellmer")$value_turn(
    new_test_gemini_provider("gemini-3.1-pro-preview"),
    fixture$body,
    has_type = TRUE
  )

  expect_true(S7::S7_inherits(
    turn@contents[[1]],
    asNamespace("ellmer")$ContentThinking
  ))
  expect_equal(turn@contents[[1]]@thinking, "Analyzing the speech for populist elements...")
  expect_true(S7::S7_inherits(
    turn@contents[[2]],
    asNamespace("ellmer")$ContentJson
  ))
  expect_equal(turn@contents[[2]]@parsed$score, 0.1)
  expect_equal(turn@json$candidates[[1]]$finishReason, "STOP")
})

test_that("Gemini tool-call thought signatures survive replay", {
  ellmer_ns <- asNamespace("ellmer")
  provider <- new_test_gemini_provider()
  result <- list(
    candidates = list(list(
      content = list(parts = list(list(
        functionCall = list(name = "lookup", args = list(id = 1L)),
        thoughtSignature = "signature-123"
      ))),
      finishReason = "STOP"
    )),
    usageMetadata = list()
  )

  turn <- ellmer_ns$value_turn(provider, result)
  request <- turn@contents[[1]]
  replay <- ellmer_ns$as_json(provider, request)

  expect_equal(replay$thoughtSignature, "signature-123")
  expect_equal(turn@json$candidates[[1]]$finishReason, "STOP")
})

test_that("batch status waits for the response file", {
  ellmer_ns <- asNamespace("ellmer")
  provider <- new_test_gemini_provider()
  batch <- list(metadata = list(
    state = "BATCH_STATE_SUCCEEDED",
    batchStats = list(requestCount = 2L, successfulRequestCount = 2L)
  ))

  expect_true(ellmer_ns$batch_status(provider, batch)$working)
  batch$response <- list(responsesFile = "files/output")
  expect_false(ellmer_ns$batch_status(provider, batch)$working)
})

test_that("cached batch metadata survives serialization", {
  batch <- list(
    name = "batches/test-123",
    .gemini_cache_name = "cachedContents/abc123"
  )
  restored <- jsonlite::fromJSON(
    jsonlite::toJSON(batch, auto_unbox = TRUE),
    simplifyVector = FALSE
  )

  expect_equal(restored$.gemini_cache_name, "cachedContents/abc123")
})

test_that("gemini_prepare_cached_body replaces the system instruction", {
  body <- list(
    systemInstruction = list(parts = list(text = "System")),
    contents = list(list(parts = list(list(text = "Hello"))))
  )
  result <- ellmer.extensions:::gemini_prepare_cached_body(
    body,
    "cachedContents/abc123"
  )

  expect_null(result$system_instruction)
  expect_equal(result$cached_content, "cachedContents/abc123")
  expect_false(is.null(result$contents))
})

test_that("chat_gemini_extended validates and stores cache_ttl", {
  chat <- chat_gemini_extended(
    credentials = function() "test-key",
    cache_ttl = 86400
  )
  expect_equal(attr(chat$get_provider(), ".gemini_cache_ttl"), 86400L)

  expect_error(
    chat_gemini_extended(credentials = function() "test-key", cache_ttl = 30),
    "at least 60"
  )
  expect_error(
    chat_gemini_extended(credentials = function() "test-key", cache_ttl = "1h"),
    "numeric"
  )
})

test_that("native Gemini methods are detected as one capability", {
  native <- ellmer.extensions:::gemini_native_batch_methods()
  expected <- exists(
    "gemini_prepare_batch_body",
    asNamespace("ellmer"),
    inherits = FALSE
  )
  expect_identical(!is.null(native), expected)
})
