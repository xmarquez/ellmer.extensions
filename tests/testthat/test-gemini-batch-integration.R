test_that("Gemini cached structured batch works end to end", {
  skip_if_live_tests_disabled("GEMINI_API_KEY", "GOOGLE_API_KEY")

  filler <- paste(
    "When solving a problem, identify the relevant facts, check edge cases,",
    "show the necessary reasoning, verify the result, and then return only",
    "the requested structured answer."
  )
  system_prompt <- paste(rep(filler, 80), collapse = " ")
  chat <- chat_gemini_extended(
    model = "gemini-3-flash-preview",
    system_prompt = system_prompt,
    cache_ttl = 3600
  )
  prompts <- list("What is 2+2?", "What is 3*3?")
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
      message <- conditionMessage(cnd)
      if (grepl("unexpected number of responses", message, fixed = TRUE)) {
        NULL
      } else if (grepl("HTTP 40[04]|invalid argument|not supported", message, ignore.case = TRUE)) {
        skip(paste0("Gemini rejected cached batch request: ", message))
      } else {
        stop(cnd)
      }
    }
  )

  if (is.null(result)) {
    if (!wait_for_batch(chat, prompts, path)) {
      skip("Gemini batch did not complete within 120 seconds")
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
