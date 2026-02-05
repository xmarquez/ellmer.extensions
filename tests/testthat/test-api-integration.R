# Getting started --------------------------------------------------------

test_that("chat_groq_developer() creates a valid Chat object", {
  skip_if_not_installed("ellmer")
  skip_if(Sys.getenv("GROQ_API_KEY") == "", "GROQ_API_KEY not set")

  chat <- chat_groq_developer()

  expect_s3_class(chat, "Chat")
  provider <- chat$get_provider()
  expect_true(S7::S7_inherits(provider, ProviderGroqDeveloper))
})

test_that("chat_groq_developer() supports system prompts", {
  skip_if_not_installed("ellmer")
  skip_if(Sys.getenv("GROQ_API_KEY") == "", "GROQ_API_KEY not set")

  chat <- chat_groq_developer(
    system_prompt = "You are a helpful assistant that responds concisely."
  )

  expect_s3_class(chat, "Chat")
  provider <- chat$get_provider()
  expect_true(S7::S7_inherits(provider, ProviderGroqDeveloper))
})

test_that("can list models", {
  skip_if_not_installed("ellmer")
  skip_if(Sys.getenv("GROQ_API_KEY") == "", "GROQ_API_KEY not set")

  models <- models_groq()

  expect_gt(nrow(models), 0)
  expect_s3_class(models, "data.frame")
  expect_contains(names(models), "id")
  expect_contains(names(models), "context_window")
  expect_contains(names(models), "active")
})

# Structured outputs -----------------------------------------------------

test_that("structured output extraction works with simple types", {
  skip_if_not_installed("ellmer")
  skip_if(Sys.getenv("GROQ_API_KEY") == "", "GROQ_API_KEY not set")

  ellmer_ns <- asNamespace("ellmer")
  chat <- chat_groq_developer()

  type_person <- ellmer_ns$type_object(
    name = ellmer_ns$type_string(),
    age = ellmer_ns$type_integer(),
    city = ellmer_ns$type_string()
  )

  result <- chat$chat_structured(
    "John is 30 years old and lives in New York City",
    type = type_person
  )

  expect_true(is.list(result))
  expect_true("name" %in% names(result))
  expect_true("age" %in% names(result))
  expect_true("city" %in% names(result))
})

test_that("structured output extraction works with arrays of objects", {
  skip_if_not_installed("ellmer")
  skip_if(Sys.getenv("GROQ_API_KEY") == "", "GROQ_API_KEY not set")

  ellmer_ns <- asNamespace("ellmer")
  chat <- chat_groq_developer()

  type_people <- ellmer_ns$type_array(
    ellmer_ns$type_object(
      name = ellmer_ns$type_string(),
      age = ellmer_ns$type_integer(),
      height = ellmer_ns$type_number("in m"),
      weight = ellmer_ns$type_number("in kg")
    )
  )

  prompt <- r"(
 * John Smith. Age: 30. Height: 180 cm. Weight: 80 kg.
 * Jane Doe. Age: 25. Height: 5'5". Weight: 110 lb.
 * Jose Rodriguez. Age: 40. Height: 190 cm. Weight: 90 kg.
 * June Lee | Age: 35 | Height 175 cm | Weight: 70 kg
)"

  result <- chat$chat_structured(prompt, type = type_people)

  expect_true(is.list(result))
  expect_true(length(result) > 0)

  if (length(result) > 0) {
    expect_true("name" %in% names(result))
    expect_true("age" %in% names(result))
    expect_true("height" %in% names(result))
    expect_true("weight" %in% names(result))
  }
})

# Batch processing -------------------------------------------------------

test_that("batch_chat works with wait = TRUE", {
  skip_if_not_installed("ellmer")
  skip_if(Sys.getenv("GROQ_API_KEY") == "", "GROQ_API_KEY not set")

  chat <- chat_groq_developer()

  prompts <- list(
    "What is 2+2? Answer with just the number.",
    "What is the capital of France? Answer with just the city name."
  )

  results_file <- tempfile(fileext = ".json")
  on.exit(unlink(results_file), add = TRUE)

  chats <- ellmer::batch_chat(
    chat,
    prompts = prompts,
    path = results_file,
    wait = TRUE
  )

  expect_equal(length(chats), 2)
  expect_true(all(vapply(chats, function(x) inherits(x, "Chat"), logical(1))))
})

test_that("batch_chat_structured works with wait = TRUE", {
  skip_if_not_installed("ellmer")
  skip_if(Sys.getenv("GROQ_API_KEY") == "", "GROQ_API_KEY not set")

  ellmer_ns <- asNamespace("ellmer")
  chat <- chat_groq_developer()

  type_answer <- ellmer_ns$type_object(
    answer = ellmer_ns$type_string()
  )

  prompts <- list(
    "What is 2+2?",
    "What is 3+3?"
  )

  results_file <- tempfile(fileext = ".json")
  on.exit(unlink(results_file), add = TRUE)

  result <- ellmer::batch_chat_structured(
    chat,
    prompts = prompts,
    path = results_file,
    type = type_answer,
    wait = TRUE
  )

  expect_true(is.data.frame(result))
  expect_equal(nrow(result), 2)
  expect_true("answer" %in% names(result))
})

test_that("batch_chat works with wait = FALSE and resume", {
  skip_if_not_installed("ellmer")
  skip_if(Sys.getenv("GROQ_API_KEY") == "", "GROQ_API_KEY not set")

  chat <- chat_groq_developer()

  prompts <- list(
    "What is 2+2? Answer with just the number.",
    "What is 3+3? Answer with just the number."
  )

  results_file <- tempfile(fileext = ".json")
  on.exit(unlink(results_file), add = TRUE)

  # First call with wait = FALSE
  # If batch is still processing, batch_chat throws an error
  # If batch completes before the first poll, we get results
  chats1 <- tryCatch(
    ellmer::batch_chat(
      chat,
      prompts = prompts,
      path = results_file,
      wait = FALSE
    ),
    error = function(e) {
      # Expected if batch is still processing
      if (grepl("unexpected number of responses", conditionMessage(e))) {
        NULL
      } else {
        stop(e)
      }
    }
  )

  if (is.null(chats1)) {
    # Batch was still processing - wait for completion
    chats <- ellmer::batch_chat(
      chat,
      prompts = prompts,
      path = results_file,
      wait = TRUE
    )
    expect_equal(length(chats), 2)
    expect_true(all(vapply(chats, function(x) inherits(x, "Chat"), logical(1))))
  } else {
    # Batch completed immediately (can happen with Groq's fast processing)
    expect_equal(length(chats1), 2)
    expect_true(all(vapply(chats1, function(x) inherits(x, "Chat"), logical(1))))
  }
})
