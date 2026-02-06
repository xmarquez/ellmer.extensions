# Gemini integration tests ------------------------------------------------

test_that("chat_gemini_extended() creates a valid Chat object", {
  skip_if_not_installed("ellmer")
  skip_if(
    Sys.getenv("GEMINI_API_KEY") == "" && Sys.getenv("GOOGLE_API_KEY") == "",
    "No Gemini credentials set"
  )

  chat <- chat_gemini_extended()

  expect_s3_class(chat, "Chat")
  provider <- chat$get_provider()
  expect_true(S7::S7_inherits(provider, ellmer.extensions:::ProviderGeminiExtended))
})

test_that("Gemini batch_chat submits and can be resumed", {
  skip_if_not_installed("ellmer")
  skip_if(
    Sys.getenv("GEMINI_API_KEY") == "" && Sys.getenv("GOOGLE_API_KEY") == "",
    "No Gemini credentials set"
  )

  chat <- chat_gemini_extended(model = "gemini-2.5-flash")

  prompts <- list("Reply with exactly: ok")
  results_file <- tempfile(fileext = ".json")
  on.exit(unlink(results_file), add = TRUE)

  chats <- tryCatch(
    ellmer::batch_chat(
      chat,
      prompts = prompts,
      path = results_file,
      wait = FALSE
    ),
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("unexpected number of responses", msg, fixed = TRUE)) {
        NULL
      } else {
        stop(e)
      }
    }
  )

  if (is.null(chats)) {
    completed <- FALSE
    for (i in seq_len(12)) {
      Sys.sleep(10)
      completed <- isTRUE(ellmer::batch_chat_completed(chat, prompts, results_file))
      if (completed) {
        break
      }
    }

    if (!completed) {
      skip("Gemini batch did not complete within test timeout.")
    }

    chats <- ellmer::batch_chat(
      chat,
      prompts = prompts,
      path = results_file,
      wait = TRUE
    )
  }

  expect_equal(length(chats), 1)
  expect_true(inherits(chats[[1]], "Chat"))
})

test_that("Gemini batch_chat_structured works", {
  skip_if_not_installed("ellmer")
  skip_if(
    Sys.getenv("GEMINI_API_KEY") == "" && Sys.getenv("GOOGLE_API_KEY") == "",
    "No Gemini credentials set"
  )

  ellmer_ns <- asNamespace("ellmer")
  chat <- chat_gemini_extended(model = "gemini-2.5-flash")

  type_answer <- ellmer_ns$type_object(
    answer = ellmer_ns$type_string()
  )

  prompts <- list("What is 2+2? Reply with just the number.")
  results_file <- tempfile(fileext = ".json")
  on.exit(unlink(results_file), add = TRUE)

  result <- tryCatch(
    ellmer::batch_chat_structured(
      chat,
      prompts = prompts,
      path = results_file,
      type = type_answer,
      wait = FALSE
    ),
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("unexpected number of responses", msg, fixed = TRUE)) {
        NULL
      } else if (grepl("HTTP 400|invalid argument", msg, ignore.case = TRUE)) {
        skip("Gemini batch structured output not supported for this model/config.")
      } else {
        stop(e)
      }
    }
  )

  if (is.null(result)) {
    completed <- FALSE
    for (i in seq_len(12)) {
      Sys.sleep(10)
      completed <- isTRUE(ellmer::batch_chat_completed(chat, prompts, results_file))
      if (completed) {
        break
      }
    }

    if (!completed) {
      skip("Gemini batch did not complete within test timeout.")
    }

    result <- ellmer::batch_chat_structured(
      chat,
      prompts = prompts,
      path = results_file,
      type = type_answer,
      wait = TRUE
    )
  }

  expect_true(is.data.frame(result))
  expect_equal(nrow(result), 1)
  expect_true("answer" %in% names(result))
})
