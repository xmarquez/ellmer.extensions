#' Gemini Provider with Batch API Support
#'
#' Internal S7 class that extends `ellmer::ProviderGoogleGemini` with
#' file-based batch support for `batch_chat()` and `batch_chat_structured()`.
#'
#' @keywords internal
ProviderGeminiExtended <- NULL

# Gemini batch helpers ----------------------------------------------------

#' Upload a JSONL input file for Gemini batch processing
#' @noRd
gemini_upload_file <- function(provider, path, mime_type = "application/jsonl") {
  ellmer_ns <- asNamespace("ellmer")
  upload_base_url <- sub("/v[^/]+/?$", "/", provider@base_url)

  upload_url <- ellmer_ns$google_upload_init(
    path = path,
    base_url = upload_base_url,
    credentials = provider@credentials,
    mime_type = mime_type
  )

  status <- ellmer_ns$google_upload_send(
    upload_url = upload_url,
    path = path,
    credentials = provider@credentials
  )
  ellmer_ns$google_upload_wait(status, provider@credentials)
  status
}

#' Download a Gemini file resource
#' @noRd
gemini_download_file <- function(provider, name, path) {
  ellmer_ns <- asNamespace("ellmer")
  req <- ellmer_ns$base_request(provider)
  req <- httr2::req_url_path_append(req, paste0(name, ":download"))
  httr2::req_perform(req, path = path)
  invisible(path)
}

#' Extract request index from known batch metadata fields
#' @noRd
gemini_extract_index <- function(x, default = NA_integer_) {
  metadata <- x$metadata %||% list()
  idx <- metadata$request_index %||% metadata$index %||% default

  if (!is.na(idx)) {
    return(as.integer(idx))
  }

  key <- x$key %||% x$custom_id %||% metadata$custom_id %||% ""
  if (grepl("^chat-[0-9]+$", key)) {
    return(as.integer(sub("^chat-([0-9]+)$", "\\1", key)))
  }

  as.integer(default)
}

#' Parse malformed Gemini JSONL lines into a recoverable error object
#' @noRd
gemini_json_fallback <- function(line) {
  index <- suppressWarnings(as.integer(sub('.*"request_index"\\s*:\\s*([0-9]+).*', "\\1", line, perl = TRUE)))

  if (length(index) == 0L || is.na(index)) {
    custom_id <- tryCatch({
      m <- regmatches(line, regexpr('"custom_id"\\s*:\\s*"chat-[0-9]+"', line, perl = TRUE))
      if (length(m) == 0L) NA_character_ else sub('.*"chat-([0-9]+)".*', "\\1", m)
    }, error = function(e) NA_character_)
    index <- suppressWarnings(as.integer(custom_id))
  }

  list(
    metadata = if (length(index) == 0L || is.na(index)) list() else list(request_index = index),
    status = list(code = 500L, message = "Failed to parse Gemini batch output line")
  )
}

#' Normalize a Gemini batch output line
#' @noRd
gemini_normalize_result <- function(x, index_default) {
  index <- gemini_extract_index(x, default = index_default)

  # Formats where response and error/status are wrapped in one object
  if (!is.null(x$response) || !is.null(x$error) || !is.null(x$status)) {
    if (!is.null(x$response) && is.null(x$error) && is.null(x$status)) {
      return(list(index = index, result = list(status_code = 200L, body = x$response)))
    }

    status <- x$error %||% x$status %||% list()
    code <- status$code %||% 500L
    return(list(index = index, result = list(status_code = as.integer(code), body = NULL)))
  }

  # Plain GenerateContentResponse lines (current file-mode output)
  if (!is.null(x$candidates) || !is.null(x$promptFeedback) || !is.null(x$usageMetadata)) {
    return(list(index = index, result = list(status_code = 200L, body = x)))
  }

  list(index = index, result = list(status_code = 500L, body = NULL))
}

# Method registration -----------------------------------------------------

register_gemini_methods <- function() {
  ellmer_ns <- asNamespace("ellmer")

  has_batch_support <- ellmer_ns$has_batch_support
  batch_submit <- ellmer_ns$batch_submit
  batch_poll <- ellmer_ns$batch_poll
  batch_status <- ellmer_ns$batch_status
  batch_retrieve <- ellmer_ns$batch_retrieve
  batch_result_turn <- ellmer_ns$batch_result_turn
  chat_body <- ellmer_ns$chat_body
  value_turn <- ellmer_ns$value_turn

  S7::method(has_batch_support, ProviderGeminiExtended) <- function(provider) {
    TRUE
  }

  S7::method(batch_submit, ProviderGeminiExtended) <- function(
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
        metadata = list(request_index = i, custom_id = paste0("chat-", i)),
        request = body
      )
    })

    json_lines <- purrr::map_chr(requests, function(x) {
      jsonlite::toJSON(x, auto_unbox = TRUE)
    })
    writeLines(json_lines, path)

    uploaded <- gemini_upload_file(provider, path)
    if (is.null(uploaded$name) || !nzchar(uploaded$name)) {
      cli::cli_abort("Gemini upload did not return a file resource name.")
    }

    req <- ellmer_ns$base_request(provider)
    req <- httr2::req_url_path_append(
      req,
      "models",
      paste0(provider@model, ":batchGenerateContent")
    )
    req <- httr2::req_body_json(
      req,
      list(
        batch = list(
          displayName = paste0("ellmer-extensions-", as.integer(Sys.time())),
          model = paste0("models/", provider@model),
          inputConfig = list(fileName = uploaded$name)
        )
      )
    )

    resp <- httr2::req_perform(req)
    httr2::resp_body_json(resp)
  }

  S7::method(batch_poll, ProviderGeminiExtended) <- function(provider, batch) {
    req <- ellmer_ns$base_request(provider)
    req <- httr2::req_url_path_append(req, batch$name)
    resp <- httr2::req_perform(req)
    httr2::resp_body_json(resp)
  }

  S7::method(batch_status, ProviderGeminiExtended) <- function(provider, batch) {
    metadata <- batch$metadata %||% list()
    response <- batch$response %||% list()
    state <- metadata$state %||% response$state %||% "BATCH_STATE_UNSPECIFIED"
    stats <- metadata$batchStats %||% response$batchStats %||% list()

    total <- as.integer(stats$requestCount %||% 0L)
    pending <- as.integer(stats$pendingRequestCount %||% 0L)
    succeeded <- as.integer(stats$successfulRequestCount %||% 0L)
    failed <- as.integer(stats$failedRequestCount %||% 0L)

    if (!is.null(batch$error) && total > 0 && failed == 0L) {
      failed <- total
    }

    terminal_states <- c(
      "BATCH_STATE_SUCCEEDED",
      "BATCH_STATE_FAILED",
      "BATCH_STATE_CANCELLED",
      "BATCH_STATE_EXPIRED"
    )

    n_processing <- max(pending, total - succeeded - failed, 0L)

    list(
      working = !(state %in% terminal_states),
      n_processing = n_processing,
      n_succeeded = max(succeeded, 0L),
      n_failed = max(failed, 0L)
    )
  }

  S7::method(batch_retrieve, ProviderGeminiExtended) <- function(provider, batch) {
    metadata <- batch$metadata %||% list()
    response <- batch$response %||% list()
    stats <- metadata$batchStats %||% response$batchStats %||% list()
    request_count <- as.integer(stats$requestCount %||% 0L)

    if (!is.null(batch$error)) {
      code <- as.integer(batch$error$code %||% 500L)
      if (request_count <= 0L) {
        return(list(list(status_code = code, body = NULL)))
      }
      return(replicate(request_count, list(status_code = code, body = NULL), simplify = FALSE))
    }

    batch_resource <- batch$response %||% batch$metadata
    responses_file <- batch_resource$output$responsesFile %||%
      batch_resource$responsesFile %||%
      metadata$output$responsesFile %||%
      NULL

    if (is.null(responses_file) || !nzchar(responses_file)) {
      cli::cli_abort("Gemini batch completed but no output file was returned.")
    }

    path_output <- tempfile(fileext = ".jsonl")
    on.exit(unlink(path_output), add = TRUE)
    gemini_download_file(provider, responses_file, path_output)

    lines <- readLines(path_output, warn = FALSE)
    lines <- lines[nzchar(trimws(lines))]

    if (length(lines) == 0) {
      cli::cli_abort("No results found in Gemini batch output file.")
    }

    parsed <- lapply(lines, function(line) {
      tryCatch(
        jsonlite::fromJSON(line, simplifyVector = FALSE),
        error = function(e) gemini_json_fallback(line)
      )
    })

    normalized <- purrr::imap(parsed, function(x, i) {
      gemini_normalize_result(x, index_default = as.integer(i))
    })

    ids <- vapply(normalized, function(x) x$index, integer(1))
    results <- lapply(normalized, function(x) x$result)
    results[order(ids)]
  }

  S7::method(batch_result_turn, ProviderGeminiExtended) <- function(
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
}
