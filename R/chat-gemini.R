#' Chat with Gemini Models (Extended Batch Support)
#'
#' @description
#' Creates a chat interface for Google's Gemini API with support for
#' asynchronous file-based batch processing through [batch_chat()] and
#' [batch_chat_structured()].
#'
#' This constructor mirrors [ellmer::chat_google_gemini()] while using a
#' provider subclass that implements batch methods required by ellmer.
#'
#' @param system_prompt A system prompt to set the behavior of the assistant.
#' @param base_url Base URL for the Gemini API.
#' @param api_key `r lifecycle::badge("deprecated")` Use `credentials` instead.
#' @param credentials Override the default credentials. You generally should not
#'   need this argument; instead set `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) in
#'   `.Renviron`.
#' @param model The model to use for the chat (defaults to "gemini-2.5-flash").
#' @param params Common model parameters, usually created by [ellmer::params()].
#' @param api_args Additional arguments passed to the API.
#' @param api_headers Additional HTTP headers.
#' @param echo Whether to echo the conversation to the console.
#'
#' @return A [ellmer::Chat] object with Gemini support for:
#'   - `$chat()`
#'   - `$chat_structured()`
#'   - [batch_chat()] and [batch_chat_structured()]
#'
#' @seealso [ellmer::chat_google_gemini()], [batch_chat()], [batch_chat_structured()]
#' @family chatbots
#' @export
chat_gemini_extended <- function(
  system_prompt = NULL,
  base_url = "https://generativelanguage.googleapis.com/v1beta/",
  api_key = NULL,
  credentials = NULL,
  model = NULL,
  params = NULL,
  api_args = list(),
  api_headers = character(),
  echo = NULL
) {
  ellmer_ns <- asNamespace("ellmer")

  model <- set_default(model, "gemini-2.5-flash")
  echo <- ellmer_ns$check_echo(echo)

  default_credentials <- if (exists("default_google_credentials", envir = ellmer_ns, inherits = FALSE)) {
    ellmer_ns$default_google_credentials(variant = "gemini")
  } else {
    function() {
      val <- Sys.getenv("GEMINI_API_KEY")
      if (nzchar(val)) return(val)
      key_get("GOOGLE_API_KEY")
    }
  }

  credentials <- ellmer_ns$as_credentials(
    "chat_gemini_extended",
    default_credentials,
    credentials = credentials,
    api_key = api_key
  )

  if (is.null(ProviderGeminiExtended)) {
    cli::cli_abort(
      "Gemini provider initialization failed. Ensure {.pkg ellmer} is installed."
    )
  }

  # Defensive re-registration for devtools::load_all() sessions where .onLoad
  # may not have attached this subclass method table yet.
  suppressMessages(register_gemini_methods())

  provider <- ProviderGeminiExtended(
    name = "Google/Gemini",
    base_url = base_url,
    model = model,
    params = params %||% ellmer_ns$params(),
    extra_args = api_args,
    extra_headers = api_headers,
    credentials = credentials
  )

  ellmer_ns$Chat$new(
    provider = provider,
    system_prompt = system_prompt,
    echo = echo
  )
}
