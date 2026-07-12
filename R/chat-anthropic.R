#' Chat with Anthropic Models (Extended Thinking + Structured Output)
#'
#' @description
#' Creates a chat interface for Anthropic's Claude API with support for
#' extended and adaptive thinking combined with structured output. On recent
#' versions of ellmer this is a backward-compatible wrapper around
#' [ellmer::chat_anthropic()]. Older versions use the bundled compatibility
#' provider when ellmer does not yet provide the requested feature.
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
#'   - `"adaptive"`: adaptive thinking. If `reasoning_effort` is not supplied,
#'     it defaults to `"high"`. Model compatibility is determined by Anthropic,
#'     rather than by a hard-coded model allowlist.
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

  params <- params %||% ellmer_ns$params()
  param_list <- as.list(params)

  if (!is.null(thinking)) {
    thinking <- match.arg(thinking, c("enabled", "adaptive"))

    if (identical(thinking, "enabled")) {
      if (!"reasoning_tokens" %in% names(param_list)) {
        cli::cli_abort(
          c(
            '{.arg thinking} = "enabled" requires {.arg reasoning_tokens} in {.arg params}.',
            "i" = "Use {.code params = ellmer::params(reasoning_tokens = 8192)}."
          )
        )
      }
      params$reasoning_effort <- NULL
      if (is.null(params$max_tokens)) {
        params$max_tokens <- params$reasoning_tokens + 16384L
      }
    } else {
      # Explicit adaptive thinking takes precedence over a token budget.
      params$reasoning_tokens <- NULL
      params$reasoning_effort <- params$reasoning_effort %||% "high"
      params$max_tokens <- params$max_tokens %||% 32768L
    }
  } else {
    # Auto-detect: if reasoning_tokens is present, enable thinking
    if ("reasoning_tokens" %in% names(param_list)) {
      thinking <- "enabled"
      params$reasoning_effort <- NULL
      if (is.null(params$max_tokens)) {
        params$max_tokens <- params$reasoning_tokens + 16384L
      }
    }
  }

  use_native <- is.null(thinking) ||
    anthropic_has_native_structured_output() &&
      (!identical(thinking, "adaptive") || anthropic_has_native_adaptive())

  if (use_native) {
    return(ellmer_ns$chat_anthropic(
      system_prompt = system_prompt,
      params = params,
      model = model,
      cache = cache,
      api_args = api_args,
      base_url = base_url,
      beta_headers = beta_headers,
      api_key = api_key,
      credentials = credentials,
      api_headers = api_headers,
      echo = echo
    ))
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

  provider <- ProviderAnthropicExtended(
    name = "Anthropic",
    model = model,
    params = params,
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

#' Does ellmer natively support Claude structured output?
#' @noRd
anthropic_has_native_structured_output <- function() {
  exists(
    "has_claude_structured_output",
    envir = asNamespace("ellmer"),
    inherits = FALSE
  )
}

#' Does ellmer natively translate reasoning effort for Claude?
#' @noRd
anthropic_has_native_adaptive <- function() {
  ellmer_ns <- asNamespace("ellmer")
  method <- tryCatch(
    S7::method(
      ellmer_ns[["chat_params"]],
      ellmer_ns[["ProviderAnthropic"]]
    ),
    error = function(cnd) NULL
  )

  !is.null(method) && any(grepl(
    "reasoning_effort",
    deparse(body(method)),
    fixed = TRUE
  ))
}
