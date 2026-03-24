#' Gemini Provider with Batch API Support
#'
#' Internal S7 class that extends `ellmer::ProviderGoogleGemini` with
#' file-based batch support for `batch_chat()` and `batch_chat_structured()`.
#'
#' @keywords internal
ProviderGeminiExtended <- NULL

# Gemini batch helpers ----------------------------------------------------

#' Convert camelCase list names to snake_case recursively
#'
#' The Gemini REST API auto-converts camelCase to snake_case, but the
#' batch JSONL file parser requires protobuf field names (snake_case).
#' @noRd
gemini_to_snake_case <- function(x) {
  if (is.list(x)) {
    if (!is.null(names(x))) {
      names(x) <- gsub("([a-z])([A-Z])", "\\1_\\2", names(x), perl = TRUE) |>
        tolower()
    }
    lapply(x, gemini_to_snake_case)
  } else {
    x
  }
}

#' Clean a chat_body for Gemini batch JSONL serialization
#'
#' Removes empty system instructions and converts camelCase keys to snake_case.
#' @noRd
gemini_prepare_batch_body <- function(body) {
  # Remove empty system instructions (batch parser rejects them)
  si <- body$systemInstruction %||% body$system_instruction
  if (!is.null(si)) {
    parts <- si$parts
    is_empty <- if (is.list(parts) && !is.null(names(parts))) {
      # Single part auto-unboxed to object: {"text": ""}
      identical(parts$text, "") || is.null(parts$text)
    } else if (is.list(parts) && length(parts) > 0) {
      # Array of parts
      all(vapply(parts, function(p) identical(p$text, "") || is.null(p$text), logical(1)))
    } else {
      TRUE
    }
    if (is_empty) {
      body$systemInstruction <- NULL
      body$system_instruction <- NULL
    }
  }

  # Save user-defined schema before snake_case conversion so property names

  # like "firstName" are not mangled to "first_name" (gemini_to_snake_case
  # only converts list *names*, but schema property keys are list names too).
  gc_pre <- body$generationConfig %||% body$generation_config
  saved_schema <- if (!is.null(gc_pre)) {
    gc_pre$responseSchema %||% gc_pre$response_schema
  }

  body <- gemini_to_snake_case(body)

  # Rename response_schema -> response_json_schema and restore original schema
  gc <- body$generation_config
  if (!is.null(gc) && (!is.null(gc$response_schema) || !is.null(saved_schema))) {
    gc$response_json_schema <- saved_schema %||% gc$response_schema
    gc$response_schema <- NULL
    body$generation_config <- gc
  }

  body
}

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
  req <- httr2::req_url_query(req, alt = "media")
  httr2::req_perform(req, path = path)
  invisible(path)
}

# Context caching helpers --------------------------------------------------

#' Create a Gemini context cache for a system prompt
#'
#' Creates a `cachedContents` resource via the Gemini REST API. The returned
#' cache name can be passed in batch request bodies as `cached_content` instead
#' of `system_instruction`, reducing input token costs.
#'
#' @param provider A ProviderGeminiExtended object (provides base_url and credentials)
#' @param system_prompt_text Character string of the system prompt to cache
#' @param ttl_seconds Integer TTL in seconds (default 86400 = 24 hours)
#' @return Character cache name (e.g. `"cachedContents/abc123"`)
#' @noRd
gemini_create_cache <- function(provider, system_prompt_text, ttl_seconds = 86400L) {
  ellmer_ns <- asNamespace("ellmer")
  req <- ellmer_ns$base_request(provider)
  req <- httr2::req_url_path_append(req, "cachedContents")
  req <- httr2::req_body_json(req, list(
    model = paste0("models/", provider@model),
    systemInstruction = list(parts = list(list(text = system_prompt_text))),
    contents = list(),
    ttl = paste0(as.integer(ttl_seconds), "s")
  ))
  resp <- httr2::req_perform(req)
  body <- httr2::resp_body_json(resp)
  body$name
}

#' Delete a Gemini context cache
#'
#' Fire-and-forget deletion; errors produce a warning only.
#'
#' @param provider A ProviderGeminiExtended object
#' @param cache_name Character cache name (e.g. `"cachedContents/abc123"`)
#' @noRd
gemini_delete_cache <- function(provider, cache_name) {
  ellmer_ns <- asNamespace("ellmer")
  req <- ellmer_ns$base_request(provider)
  req <- httr2::req_url_path_append(req, cache_name)
  req <- httr2::req_method(req, "DELETE")
  tryCatch(
    httr2::req_perform(req),
    error = function(e) cli::cli_warn("Failed to delete Gemini cache {.val {cache_name}}: {e$message}")
  )
  invisible(NULL)
}

#' Prepare a batch body with cached content reference
#'
#' Calls `gemini_prepare_batch_body()` then replaces `system_instruction`
#' with a `cached_content` reference.
#'
#' @param body List from `chat_body()`
#' @param cache_name Character cache name (e.g. `"cachedContents/abc123"`)
#' @return Modified body ready for batch JSONL
#' @noRd
gemini_prepare_cached_body <- function(body, cache_name) {
  body <- gemini_prepare_batch_body(body)
  body$system_instruction <- NULL
  body$cached_content <- cache_name
  body
}

# Batch metadata helpers ---------------------------------------------------

#' Extract request index from known batch metadata fields
#' @noRd
gemini_extract_index <- function(x, default = NA_integer_) {
  metadata <- x$metadata %||% list()
  idx <- metadata$request_index %||% metadata$index

  if (!is.null(idx) && !is.na(idx)) {
    return(as.integer(idx))
  }

  key <- x$key %||% x$custom_id %||% metadata$key %||% metadata$custom_id %||% ""
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

    # Check if context caching is requested (attr set by chat_gemini_extended)
    cache_ttl <- attr(provider, ".gemini_cache_ttl")
    cache_name <- NULL

    if (!is.null(cache_ttl) && length(conversations) > 0) {
      # Extract system prompt from first conversation to validate uniformity
      si_texts <- vapply(conversations, function(conv) {
        body <- chat_body(provider, stream = FALSE, turns = conv, type = type)
        si <- body$systemInstruction
        if (is.null(si) || is.null(si$parts)) return("")
        if (!is.null(names(si$parts))) return(si$parts$text %||% "")
        if (length(si$parts) > 0) return(si$parts[[1]]$text %||% "")
        ""
      }, character(1))

      unique_prompts <- unique(si_texts[nzchar(si_texts)])
      if (length(unique_prompts) == 1L && all(nzchar(si_texts))) {
        cache_name <- tryCatch(
          gemini_create_cache(provider, unique_prompts, as.integer(cache_ttl)),
          error = function(e) {
            cli::cli_warn(
              "Gemini cache creation failed, proceeding without caching: {e$message}"
            )
            NULL
          }
        )
      } else if (length(unique_prompts) == 1L && !all(nzchar(si_texts))) {
        cli::cli_warn(
          "Some conversations have no system prompt; skipping Gemini context caching."
        )
      } else if (length(unique_prompts) > 1L) {
        cli::cli_warn(
          "Conversations have different system prompts; skipping Gemini context caching."
        )
      }
    }

    # Build JSONL request lines
    requests <- purrr::map(seq_along(conversations), function(i) {
      body <- chat_body(
        provider,
        stream = FALSE,
        turns = conversations[[i]],
        type = type
      )

      prepared <- if (!is.null(cache_name)) {
        gemini_prepare_cached_body(body, cache_name)
      } else {
        gemini_prepare_batch_body(body)
      }

      list(key = paste0("chat-", i), request = prepared)
    })

    json_lines <- purrr::map_chr(requests, function(x) {
      jsonlite::toJSON(x, auto_unbox = TRUE)
    })
    writeLines(json_lines, path)

    # Upload and submit; clean up cache on failure
    batch_result <- tryCatch({
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
    }, error = function(e) {
      if (!is.null(cache_name)) gemini_delete_cache(provider, cache_name)
      stop(e)
    })

    # Embed cache name in batch object so it survives wait=FALSE serialization
    if (!is.null(cache_name)) {
      batch_result$.gemini_cache_name <- cache_name
    }

    batch_result
  }

  S7::method(batch_poll, ProviderGeminiExtended) <- function(provider, batch) {
    cache_name <- batch$.gemini_cache_name
    req <- ellmer_ns$base_request(provider)
    req <- httr2::req_url_path_append(req, batch$name)
    resp <- httr2::req_perform(req)
    result <- httr2::resp_body_json(resp)
    # Carry cache name forward (API response won't include it)
    if (!is.null(cache_name)) result$.gemini_cache_name <- cache_name
    result
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

    is_done <- state %in% terminal_states

    # Keep polling if succeeded but output file isn't available yet.
    # The API can report BATCH_STATE_SUCCEEDED before the responsesFile
    # metadata is populated.
    if (state == "BATCH_STATE_SUCCEEDED") {
      responses_file <- response$output$responsesFile %||%
        response$responsesFile %||%
        metadata$output$responsesFile %||%
        metadata$responsesFile %||%
        ""
      if (!nzchar(responses_file)) {
        is_done <- FALSE
      }
    }

    n_processing <- max(pending, total - succeeded - failed, 0L)

    list(
      working = !is_done,
      n_processing = n_processing,
      n_succeeded = max(succeeded, 0L),
      n_failed = max(failed, 0L)
    )
  }

  S7::method(batch_retrieve, ProviderGeminiExtended) <- function(provider, batch) {
    # Schedule cache cleanup (runs on both success and failure paths)
    cache_name <- batch$.gemini_cache_name
    if (!is.null(cache_name)) {
      on.exit(gemini_delete_cache(provider, cache_name), add = TRUE)
    }

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
