#' Groq Developer Provider Class
#'
#' S7 compatibility class that extends ellmer's native Groq provider when
#' available and otherwise extends ProviderOpenAICompatible.
#'
#' It forwards Groq reasoning-effort parameters and retains a legacy batch
#' implementation for ellmer releases without native Groq batch support.
#'
#' @param name Provider name
#' @param model Model identifier (e.g., "openai/gpt-oss-20b")
#' @param base_url API base URL
#' @param params Parameters list for generation control
#' @param extra_args Additional API arguments
#' @param extra_headers Additional HTTP headers
#' @param credentials API credentials (function or string)
#'
#' @details
#' Users should typically use [chat_groq_developer()] instead of calling this
#' constructor directly. This class is exported for advanced use cases.
#'
#' @seealso [chat_groq_developer()] for creating chat objects
#'
#' @export
ProviderGroqDeveloper <- NULL

# Method registration -----------------------------------------------------

register_groq_methods <- function() {
  ellmer_ns <- asNamespace("ellmer")

  ProviderOpenAICompatible <- ellmer_ns$ProviderOpenAICompatible
  ProviderGroq <- if (exists("ProviderGroq", ellmer_ns, inherits = FALSE)) {
    ellmer_ns$ProviderGroq
  }
  uses_native_parent <- !is.null(ProviderGroq) &&
    identical(attr(ProviderGroqDeveloper, "parent"), ProviderGroq)
  parent <- if (uses_native_parent) {
    ProviderGroq
  } else {
    ProviderOpenAICompatible
  }

  # Get generics from ellmer
  has_batch_support <- ellmer_ns$has_batch_support
  batch_submit <- ellmer_ns$batch_submit
  batch_poll <- ellmer_ns$batch_poll
  batch_status <- ellmer_ns$batch_status
  batch_retrieve <- ellmer_ns$batch_retrieve
  batch_result_turn <- ellmer_ns$batch_result_turn
  chat_body <- ellmer_ns$chat_body
  chat_params <- ellmer_ns$chat_params
  value_turn <- ellmer_ns$value_turn

  # ProviderOpenAICompatible deliberately supports only parameters common to
  # every compatible API. Groq's GPT-OSS models additionally accept
  # reasoning_effort, so preserve it instead of silently dropping it.
  S7::method(chat_params, ProviderGroqDeveloper) <- function(provider, params) {
    reasoning_effort <- params$reasoning_effort
    params$reasoning_effort <- NULL
    out <- chat_params(S7::super(provider, parent), params)
    if (!is.null(reasoning_effort)) {
      out$reasoning_effort <- reasoning_effort
    }
    out
  }

  # chat_request() merges extra_args for ordinary requests, but batch_submit()
  # calls chat_body() directly. Merge here so api_args are included in both.
  S7::method(chat_body, ProviderGroqDeveloper) <- function(
    provider,
    stream = TRUE,
    turns = list(),
    tools = list(),
    type = NULL
  ) {
    body <- chat_body(
      S7::super(provider, parent),
      stream = stream,
      turns = turns,
      tools = tools,
      type = type
    )
    ellmer_ns$modify_list(body, provider@extra_args)
  }

  # ProviderGroq predates native Groq batching, so probe the capability instead
  # of treating the presence of the class as sufficient.
  has_native_batch <- FALSE
  if (identical(parent, ProviderGroq)) {
    probe <- ProviderGroq(
      name = "Groq",
      model = "",
      base_url = "https://api.groq.com/openai/v1",
      credentials = function() NULL
    )
    has_native_batch <- isTRUE(has_batch_support(probe))
  }

  if (has_native_batch) {
    return(invisible())
  }

  # Legacy ellmer compatibility ---------------------------------------------

  S7::method(has_batch_support, ProviderGroqDeveloper) <- function(provider) {
    TRUE
  }

  S7::method(batch_submit, ProviderGroqDeveloper) <- function(
    provider,
    conversations,
    type = NULL
  ) {
    path <- withr::local_tempfile(fileext = ".jsonl")

    requests <- purrr::map(seq_along(conversations), function(i) {
      body <- chat_body(
        provider,
        stream = FALSE,
        turns = conversations[[i]],
        type = type
      )
      list(
        custom_id = paste0("chat-", i),
        method = "POST",
        url = "/v1/chat/completions",
        body = body
      )
    })

    json_lines <- purrr::map_chr(requests, ellmer_ns$to_json)
    writeLines(json_lines, path)

    uploaded <- ellmer_ns$openai_upload(provider, path)

    req <- ellmer_ns$base_request(provider)
    req <- httr2::req_url_path_append(req, "batches")
    req <- httr2::req_body_json(req, list(
      input_file_id = uploaded$id,
      endpoint = "/v1/chat/completions",
      completion_window = "24h"
    ))

    resp <- httr2::req_perform(req)
    httr2::resp_body_json(resp)
  }

  S7::method(batch_poll, ProviderGroqDeveloper) <- function(provider, batch) {
    req <- ellmer_ns$base_request(provider)
    req <- httr2::req_url_path_append(req, "batches", batch$id)

    resp <- httr2::req_perform(req)
    httr2::resp_body_json(resp)
  }

  S7::method(batch_status, ProviderGroqDeveloper) <- function(provider, batch) {
    terminal_states <- c("completed", "failed", "expired", "cancelled")

    request_counts <- batch$request_counts
    total <- request_counts$total %||% 0L
    completed <- request_counts$completed %||% 0L
    failed <- request_counts$failed %||% 0L

    list(
      working = !(batch$status %in% terminal_states),
      n_processing = max(total - completed - failed, 0L),
      n_succeeded = completed,
      n_failed = failed
    )
  }

  S7::method(batch_retrieve, ProviderGroqDeveloper) <- function(provider, batch) {
    json <- list()

    if (length(batch$output_file_id) == 1 && nzchar(batch$output_file_id)) {
      path_output <- withr::local_tempfile(fileext = ".jsonl")
      ellmer_ns$openai_download_file(provider, batch$output_file_id, path_output)
      json <- ellmer_ns$read_ndjson(
        path_output,
        fallback = ellmer_ns$openai_json_fallback
      )
    }

    if (length(batch$error_file_id) == 1 && nzchar(batch$error_file_id)) {
      path_error <- withr::local_tempfile(fileext = ".jsonl")
      ellmer_ns$openai_download_file(provider, batch$error_file_id, path_error)
      json <- c(
        json,
        ellmer_ns$read_ndjson(
          path_error,
          fallback = ellmer_ns$openai_json_fallback
        )
      )
    }

    custom_ids <- vapply(json, function(x) {
      id <- x$custom_id
      if (is.character(id) && length(id) == 1) id else NA_character_
    }, character(1))
    ids <- as.numeric(gsub("chat-", "", custom_ids))
    results <- lapply(json, "[[", "response")
    results[order(ids)]
  }

  S7::method(batch_result_turn, ProviderGroqDeveloper) <- function(
    provider,
    result,
    has_type = FALSE
  ) {
    if (!is.null(result) && result$status_code == 200L && !is.null(result$body)) {
      value_turn(provider, result$body, has_type = has_type)
    } else {
      NULL
    }
  }

  invisible()
}

# Class initialization ----------------------------------------------------

# Initialize the class after ellmer is loaded
.onLoad <- function(libname, pkgname) {
  ellmer_ns <- asNamespace("ellmer")

  suppressMessages({
    ProviderGroqParent <- if (exists("ProviderGroq", ellmer_ns, inherits = FALSE)) {
      ellmer_ns$ProviderGroq
    } else {
      ellmer_ns$ProviderOpenAICompatible
    }
    ProviderGroqDeveloper <<- S7::new_class(
      name = "ProviderGroqDeveloper",
      package = "ellmer.extensions",
      parent = ProviderGroqParent
    )
    register_groq_methods()

    ProviderGoogleGemini <- ellmer_ns$ProviderGoogleGemini
    ProviderGeminiExtended <<- S7::new_class(
      name = "ProviderGeminiExtended",
      package = "ellmer.extensions",
      parent = ProviderGoogleGemini
    )
    register_gemini_methods()

    ProviderAnthropic <- ellmer_ns$ProviderAnthropic
    ProviderAnthropicExtended <<- S7::new_class(
      name = "ProviderAnthropicExtended",
      package = "ellmer.extensions",
      parent = ProviderAnthropic
    )
    register_anthropic_methods()

    S7::methods_register()
  })
}

# Batch support is implemented via Groq's Batch API --------------------------
# See https://console.groq.com/docs/batch for documentation
# Batch processing offers 50% cost discount compared to synchronous API calls
