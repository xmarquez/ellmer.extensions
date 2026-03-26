#' Chat with Anthropic Models (Extended Thinking + Structured Output)
#'
#' @description
#' Creates a chat interface for Anthropic's Claude API with support for
#' extended thinking combined with structured output. Standard
#' [ellmer::chat_anthropic()] cannot combine thinking (`reasoning_tokens`)
#' with structured output because Anthropic's API forbids `tool_choice` with
#' thinking enabled. This provider uses Anthropic's `output_config.format`
#' (JSON schema) instead of `tool_choice` when thinking is active, avoiding
#' the API conflict.
#'
#' When `thinking` is `NULL` (the default), thinking is auto-detected from
#' `params`: if `reasoning_tokens` is present, thinking is enabled
#' automatically. Otherwise, the function behaves identically to
#' [ellmer::chat_anthropic()].
#'
#' @param system_prompt A system prompt to set the behavior of the assistant.
#' @param params Common model parameters, usually created by [ellmer::params()].
#'   When `thinking = "enabled"`, must include `reasoning_tokens` to set the
#'   thinking budget.
#' @param model The model to use for the chat (defaults to
#'   `"claude-sonnet-4-5-20250929"`).
#' @param cache Anthropic prompt caching strategy. One of `"5m"`, `"1h"`, or
#'   `"none"`.
#' @param api_args Additional arguments passed to the API.
#' @param base_url Base URL for the Anthropic API.
#' @param beta_headers Character vector of Anthropic beta feature headers.
#' @param api_key `r lifecycle::badge("deprecated")` Use `credentials` instead.
#' @param credentials Override the default credentials. You generally should not
#'   need this argument; instead set `ANTHROPIC_API_KEY` in `.Renviron`.
#' @param api_headers Additional HTTP headers.
#' @param echo Whether to echo the conversation to the console.
#' @param thinking Thinking mode. One of:
#'   - `NULL` (default): auto-detect. If `reasoning_tokens` is present in
#'     `params`, thinking is automatically enabled. Otherwise, no thinking
#'     (behaves like [ellmer::chat_anthropic()]).
#'   - `"enabled"`: extended thinking with explicit budget. Requires
#'     `reasoning_tokens` in `params`.
#'   - `"adaptive"`: adaptive thinking. Only available on Claude Opus 4.6 and
#'     Sonnet 4.6; errors for 4.5 model IDs.
#'
#' @return A [ellmer::Chat] object.
#'
#' @details
#' ## How it works
#'
#' When `thinking` is active and structured output is requested (via
#' `$chat_structured()` or [batch_chat_structured()]),
#' this provider uses Anthropic's `output_config.format` with a JSON schema
#' instead of the usual `tool_choice` mechanism. The model produces a
#' `thinking` block (internal reasoning) followed by a `text` block containing
#' JSON that matches the requested schema. This avoids the API error:
#' *"Thinking may not be enabled when tool_choice forces tool use."*
#'
#' When thinking is not active (no `reasoning_tokens` in `params` and
#' `thinking = NULL`), the provider falls back to standard
#' `tool_choice`-based structured output (identical to `ellmer::chat_anthropic()`).
#'
#' ## Model compatibility
#'
#' - `thinking = "enabled"`: All Claude 4.5 models (Haiku, Sonnet, Opus) and
#'   later. Requires `reasoning_tokens` in `params` to set the thinking budget.
#' - `thinking = "adaptive"`: Claude Opus 4.6 and Sonnet 4.6 only.
#'
#' @seealso [ellmer::chat_anthropic()], [batch_chat_structured()]
#' @family chatbots
#' @export
chat_anthropic_extended <- function(
  system_prompt = NULL,
  params = NULL,
  model = NULL,
  cache = c("5m", "1h", "none"),
  api_args = list(),
  base_url = "https://api.anthropic.com/v1",
  beta_headers = character(),
  api_key = NULL,
  credentials = NULL,
  api_headers = character(),
  echo = NULL,
  thinking = NULL
) {
  ellmer_ns <- asNamespace("ellmer")

  model <- set_default(model, "claude-sonnet-4-5-20250929")
  echo <- ellmer_ns$check_echo(echo)
  cache <- match.arg(cache)

  # Validate thinking parameter
  if (!is.null(thinking)) {
    thinking <- match.arg(thinking, c("enabled", "adaptive"))

    if (identical(thinking, "enabled")) {
      param_list <- if (is.list(params)) params else list()
      if (inherits(params, "ellmer_params")) {
        param_list <- as.list(params)
      }
      if (!"reasoning_tokens" %in% names(param_list)) {
        cli::cli_abort(
          c(
            '{.arg thinking} = "enabled" requires {.arg reasoning_tokens} in {.arg params}.',
            "i" = 'Use {.code params = ellmer::params(reasoning_tokens = 8192)}.'
          )
        )
      }
    }

    if (identical(thinking, "adaptive")) {
      # Error for known incompatible models; warn for unknown models
      is_45_model <- grepl("4-5|4\\.5", model, perl = TRUE)
      if (is_45_model) {
        cli::cli_abort(
          c(
            '{.arg thinking} = "adaptive" is not supported on {.val {model}}.',
            "i" = "Adaptive thinking requires Claude Opus 4.6 or Sonnet 4.6.",
            "i" = 'For this model, use {.code thinking = "enabled"} with {.arg reasoning_tokens}.'
          )
        )
      } else if (!grepl("4-6|4\\.6", model, perl = TRUE)) {
        cli::cli_warn(
          c(
            '{.arg thinking} = "adaptive" is documented for Claude Opus 4.6 and Sonnet 4.6.',
            "i" = "Verify that {.val {model}} supports adaptive thinking."
          )
        )
      }
    }
  } else {
    # Auto-detect: if reasoning_tokens is present, enable thinking
    param_list <- if (is.list(params)) params else list()
    if (inherits(params, "ellmer_params")) {
      param_list <- as.list(params)
    }
    if ("reasoning_tokens" %in% names(param_list)) {
      thinking <- "enabled"
    }
  }

  credentials <- ellmer_ns$as_credentials(
    "chat_anthropic_extended",
    function() ellmer_ns$anthropic_key(),
    credentials = credentials,
    api_key = api_key
  )

  if (is.null(ProviderAnthropicExtended)) {
    cli::cli_abort(
      "Anthropic provider initialization failed. Ensure {.pkg ellmer} is installed."
    )
  }

  # Defensive re-registration for devtools::load_all() sessions
  suppressMessages(register_anthropic_methods())

  provider <- ProviderAnthropicExtended(
    name = "Anthropic",
    model = model,
    params = params %||% ellmer_ns$params(),
    extra_args = api_args,
    extra_headers = api_headers,
    base_url = base_url,
    beta_headers = beta_headers,
    credentials = credentials,
    cache = cache
  )

  if (!is.null(thinking)) {
    attr(provider, ".anthropic_thinking") <- thinking
  }

  ellmer_ns$Chat$new(
    provider = provider,
    system_prompt = system_prompt,
    echo = echo
  )
}
