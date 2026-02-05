#' Chat with Groq AI Models (Developer Version)
#'
#' @description
#' Creates a chat interface for Groq's API with support for structured outputs,
#' batch processing, and parallel execution. This developer version extends
#' ellmer's ProviderOpenAICompatible to inherit full batch support while adding
#' Groq-specific schema formatting (additionalProperties: false).
#'
#' Sign up at <https://groq.com>.
#'
#' Built on top of ellmer's ProviderOpenAICompatible class.
#'
#' @param system_prompt A system prompt to set the behavior of the assistant.
#' @param base_url Base URL for Groq API.
#' @param api_key `r lifecycle::badge("deprecated")` Use `credentials` instead.
#' @param credentials Override the default credentials. You generally should not
#'   need this argument; instead set the `GROQ_API_KEY` environment variable.
#'   The best place to set this is in `.Renviron`, which you can easily edit by
#'   calling `usethis::edit_r_environ()`.
#'
#'   If you do need additional control, this argument takes a zero-argument
#'   function that returns either a string (the API key), or a named list
#'   (added as additional headers to every request).
#' @param model The model to use for the chat (defaults to "openai/gpt-oss-20b").
#'   We regularly update the default, so we strongly recommend explicitly
#'   specifying a model for anything other than casual use.
#'   Use [models_groq()] to see all options.
#' @param params Common model parameters, usually created by [ellmer::params()].
#' @param api_args Additional arguments passed to the API.
#' @param echo Whether to echo the conversation to the console. One of:
#'   - `"none"`: No output
#'   - `"output"`: Echo assistant responses only
#'   - `"all"`: Echo all messages
#'   Defaults to `"output"` in interactive sessions, `"none"` otherwise.
#' @param api_headers Additional HTTP headers.
#'
#' @return A [ellmer::Chat] object with methods for:
#'   - `$chat()`: Send messages and receive responses
#'   - `$chat_structured()`: Extract structured data with type validation
#'   - Batch processing via [batch_chat()] and [batch_chat_structured()]
#'   - Parallel processing via [parallel_chat()] and [parallel_chat_structured()]
#'
#' @section Structured Outputs:
#' Groq supports strict JSON schema validation with guaranteed compliance when using
#' compatible models. See <https://console.groq.com/docs/structured-outputs> for details.
#'
#' @section Batch Processing:
#' Groq's batch API offers 50% cost discount and no rate limit impact. Batch jobs
#' are processed asynchronously with completion windows from 24 hours to 7 days.
#' Use [batch_chat()] or [batch_chat_structured()] to submit batches. See 
#' <https://console.groq.com/docs/batch> for details.
#'
#' @section Models:
#' For strict structured output support, use:
#' - `"openai/gpt-oss-20b"` (default)
#' - `"openai/gpt-oss-120b"`
#'
#' Other models support best-effort JSON output but may not guarantee schema compliance.
#'
#' @examples
#' \dontrun{
#' # Basic chat
#' chat <- chat_groq_developer()
#' chat$chat("What is the capital of France?")
#'
#' # Structured output
#' type_person <- ellmer::type_object(
#'   name = ellmer::type_string(),
#'   age = ellmer::type_integer(),
#'   city = ellmer::type_string()
#' )
#' result <- chat$chat_structured(
#'   "John is 30 years old and lives in NYC",
#'   type = type_person
#' )
#'
#' # Batch processing
#' results <- batch_chat(
#'   chat,
#'   prompts = c("Question 1?", "Question 2?", "Question 3?")
#' )
#'
#' # Parallel processing
#' results <- parallel_chat(
#'   chat,
#'   prompts = c("Question 1?", "Question 2?", "Question 3?")
#' )
#' }
#'
#' @seealso
#' - [batch_chat()] for batch processing
#' - [parallel_chat()] for parallel processing
#' - [ellmer::type_object()], [ellmer::type_array()] for defining types
#'
#' @family chatbots
#' @export
chat_groq_developer <- function(
  system_prompt = NULL,
  base_url = "https://api.groq.com/openai/v1",
  api_key = NULL,
  credentials = NULL,
  model = NULL,

  params = NULL,
  api_args = list(),
  echo = NULL,
  api_headers = character()
) {
  ellmer_ns <- asNamespace("ellmer")

  model <- set_default(model, "openai/gpt-oss-20b")
  echo <- ellmer_ns$check_echo(echo)

  credentials <- ellmer_ns$as_credentials(
    "chat_groq_developer",
    function() groq_key(),
    credentials = credentials,
    api_key = api_key
  )

  params <- params %||% ellmer_ns$params()

  provider <- ProviderGroqDeveloper(
    name = "Groq",
    base_url = base_url,
    model = model,
    params = params,
    extra_args = api_args,
    credentials = credentials,
    extra_headers = api_headers
  )

  ellmer_ns$Chat$new(
    provider = provider,
    system_prompt = system_prompt,
    echo = echo
  )
}

#' List Available Groq Models
#'
#' Retrieves a list of available models from the Groq API. Returns model
#' metadata including context window size and active status.
#'
#' @param base_url Base URL for the Groq API.
#' @param api_key `r lifecycle::badge("deprecated")` Use `credentials` instead.
#' @param credentials Override the default credentials. You generally should not
#'   need this argument; instead set the `GROQ_API_KEY` environment variable.
#'
#' @return A data frame with columns:
#'   \describe{
#'     \item{id}{Model identifier (e.g., "llama-3.3-70b-versatile")}
#'     \item{created_at}{Date the model was created}
#'     \item{owned_by}{Organization that owns/provides the model}
#'     \item{context_window}{Maximum context window size in tokens}
#'     \item{active}{Whether the model is currently active/available}
#'   }
#'
#' @examples
#' \dontrun{
#' # List all available models
#' models <- models_groq()
#' print(models)
#'
#' # Filter for active models with large context windows
#' large_context <- models[models$context_window >= 32768 & models$active, ]
#' }
#'
#' @seealso [chat_groq_developer()] for creating chat sessions
#'
#' @export
models_groq <- function(
  base_url = "https://api.groq.com/openai/v1",
  api_key = NULL,
  credentials = NULL
) {
  ellmer_ns <- asNamespace("ellmer")

  credentials <- ellmer_ns$as_credentials(
    "models_groq",
    function() groq_key(),
    credentials = credentials,
    api_key = api_key
  )

  provider <- ellmer_ns$ProviderOpenAICompatible(
    name = "Groq",
    model = "",
    base_url = base_url,
    credentials = credentials
  )

  req <- ellmer_ns$base_request(provider)
  req <- httr2::req_url_path_append(req, "/models")
  resp <- httr2::req_perform(req)
  json <- httr2::resp_body_json(resp)

  # Groq returns: id, object, created, owned_by, active, context_window
  id <- vapply(json$data, function(x) x$id %||% "", character(1))
  created <- as.Date(.POSIXct(vapply(json$data, function(x) x$created %||% 0L, integer(1))))
  owned_by <- vapply(json$data, function(x) x$owned_by %||% "", character(1))
  context_window <- vapply(json$data, function(x) x$context_window %||% NA_integer_, integer(1))
  active <- vapply(json$data, function(x) x$active %||% TRUE, logical(1))

  df <- data.frame(
    id = id,
    created_at = created,
    owned_by = owned_by,
    context_window = context_window,
    active = active,
    stringsAsFactors = FALSE
  )

  df[order(-xtfrm(df$created_at)), ]
}

# Utility functions -------------------------------------------------------

#' @keywords internal
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Get Groq API key
#' @keywords internal
groq_key <- function() {
  key_get("GROQ_API_KEY")
}

#' Get API key from environment variable
#' @keywords internal
key_get <- function(name, error_call = rlang::caller_env()) {

  val <- Sys.getenv(name)
  if (!identical(val, "")) {
    val
  } else {
    if (is_testing()) {
      testthat::skip(sprintf("%s env var is not configured", name))
    } else {
      cli::cli_abort("Can't find env var {.code {name}}.", call = error_call)
    }
  }
}

#' Check if running in test mode
#' @keywords internal
is_testing <- function() {
  identical(Sys.getenv("TESTTHAT"), "true")
}

#' Set default value with informative message
#' @keywords internal
set_default <- function(value, default, arg = rlang::caller_arg(value)) {
  if (is.null(value)) {
    if (!is_testing() || is_snapshot()) {
      cli::cli_inform("Using {.field {arg}} = {.val {default}}.")
    }
    default
  } else {
    value
  }
}

#' Check if running in snapshot mode
#' @keywords internal
is_snapshot <- function() {
  identical(Sys.getenv("TESTTHAT_IS_SNAPSHOT"), "true")
}
