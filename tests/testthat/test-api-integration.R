test_that("Groq structured batch works end to end", {
  skip_if_live_tests_disabled("GROQ_API_KEY")

  chat <- chat_groq_developer(
    model = "openai/gpt-oss-20b",
    params = ellmer::params(reasoning_effort = "low")
  )
  prompts <- list("What is 2+2?", "What is 3+3?")
  type <- ellmer::type_object(answer = ellmer::type_string())
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)

  result <- tryCatch(
    ellmer::batch_chat_structured(
      chat,
      prompts = prompts,
      type = type,
      path = path,
      wait = FALSE
    ),
    error = function(cnd) {
      if (grepl("unexpected number of responses", conditionMessage(cnd), fixed = TRUE)) {
        NULL
      } else {
        stop(cnd)
      }
    }
  )

  if (is.null(result)) {
    if (!wait_for_batch(chat, prompts, path)) {
      skip("Groq batch did not complete within 120 seconds")
    }
    result <- ellmer::batch_chat_structured(
      chat,
      prompts = prompts,
      type = type,
      path = path,
      wait = TRUE
    )
  }

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 2L)
  expect_named(result, "answer")
})
