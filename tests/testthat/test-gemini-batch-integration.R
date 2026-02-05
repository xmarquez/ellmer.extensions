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
