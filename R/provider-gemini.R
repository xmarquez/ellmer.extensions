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

# Batch compatibility helpers --------------------------------------------

#' Find native Gemini batch methods, if this version of ellmer has them
#' @noRd
gemini_native_batch_methods <- function(ellmer_ns = asNamespace("ellmer")) {
  get_method <- function(generic) {
    tryCatch(
      S7::method(generic, ellmer_ns$ProviderGoogleGemini),
      error = function(e) NULL
    )
  }

  methods <- list(
    submit = get_method(ellmer_ns$batch_submit),
    poll = get_method(ellmer_ns$batch_poll),
    retrieve = get_method(ellmer_ns$batch_retrieve)
  )

  if (any(vapply(methods, is.null, logical(1)))) NULL else methods
}

#' Extract the request index assigned by Gemini batch submission
#' @noRd
gemini_extract_index <- function(x, default = NA_integer_) {
  key <- x$key %||% ""
  if (grepl("^chat-[0-9]+$", key)) {
    return(as.integer(sub("^chat-([0-9]+)$", "\\1", key)))
  }
  as.integer(default)
}

#' Normalize a Gemini batch output line
#' @noRd
gemini_normalize_result <- function(x, index_default) {
  index <- gemini_extract_index(x, default = index_default)

  if (!is.null(x$response) && is.null(x$error) && is.null(x$status)) {
    return(list(
      index = index,
      result = list(status_code = 200L, body = x$response)
    ))
  }

  if (!is.null(x$error) || !is.null(x$status)) {
    code <- x$error$code %||% x$status$code %||% 500L
    return(list(
      index = index,
      result = list(status_code = as.integer(code), body = NULL)
    ))
  }

  list(index = index, result = list(status_code = 500L, body = NULL))
}

#' Create a cache when every conversation has the same system prompt
#' @noRd
gemini_batch_cache <- function(provider, conversations, type, cache_ttl) {
  if (is.null(cache_ttl) || length(conversations) == 0L) {
    return(NULL)
  }

  chat_body <- asNamespace("ellmer")$chat_body
  prompts <- vapply(conversations, function(conversation) {
    body <- chat_body(provider, stream = FALSE, turns = conversation, type = type)
    body$systemInstruction$parts$text %||% ""
  }, character(1))

  if (any(!nzchar(prompts))) {
    cli::cli_warn(
      "At least one conversation has no system prompt; skipping Gemini context caching."
    )
    return(NULL)
  }
  if (length(unique(prompts)) != 1L) {
    cli::cli_warn(
      "Conversations have different system prompts; skipping Gemini context caching."
    )
    return(NULL)
  }

  tryCatch(
    gemini_create_cache(provider, prompts[[1]], cache_ttl),
    error = function(e) {
      cli::cli_warn(
        "Gemini cache creation failed; submitting without caching: {e$message}"
      )
      NULL
    }
  )
}

#' Submit a Gemini batch, optionally replacing its system prompt with a cache
#' @noRd
gemini_batch_submit_legacy <- function(
  provider,
  conversations,
  type = NULL,
  cache_name = NULL
) {
  ellmer_ns <- asNamespace("ellmer")
  path <- withr::local_tempfile(fileext = ".jsonl")

  requests <- purrr::map(seq_along(conversations), function(i) {
    body <- ellmer_ns$chat_body(
      provider,
      stream = FALSE,
      turns = conversations[[i]],
      type = type
    )
    body <- if (is.null(cache_name)) {
      gemini_prepare_batch_body(body)
    } else {
      gemini_prepare_cached_body(body, cache_name)
    }
    list(key = paste0("chat-", i), request = body)
  })

  writeLines(
    purrr::map_chr(requests, jsonlite::toJSON, auto_unbox = TRUE),
    path
  )

  upload <- if (exists("gemini_upload_file", ellmer_ns, inherits = FALSE)) {
    ellmer_ns$gemini_upload_file
  } else {
    gemini_upload_file
  }
  uploaded <- upload(provider, path)
  if (is.null(uploaded$name) || !nzchar(uploaded$name)) {
    cli::cli_abort("Gemini upload did not return a file resource name.")
  }

  req <- ellmer_ns$base_request(provider)
  req <- httr2::req_url_path_append(
    req,
    "models",
    paste0(provider@model, ":batchGenerateContent")
  )
  req <- httr2::req_body_json(req, list(
    batch = list(
      displayName = paste0("ellmer-extensions-", as.integer(Sys.time())),
      model = paste0("models/", provider@model),
      inputConfig = list(fileName = uploaded$name)
    )
  ))

  result <- httr2::req_perform(req) |>
    httr2::resp_body_json()
  if (!is.null(cache_name)) {
    result$.gemini_cache_name <- cache_name
  }
  result
}

# Method registration -----------------------------------------------------

register_gemini_methods <- function() {
  ellmer_ns <- asNamespace("ellmer")
  native <- gemini_native_batch_methods(ellmer_ns)

  has_batch_support <- ellmer_ns$has_batch_support
  batch_submit <- ellmer_ns$batch_submit
  batch_poll <- ellmer_ns$batch_poll
  batch_status <- ellmer_ns$batch_status
  batch_retrieve <- ellmer_ns$batch_retrieve
  batch_result_turn <- ellmer_ns$batch_result_turn
  value_turn <- ellmer_ns$value_turn
  as_json <- ellmer_ns$as_json

  # Native ellmer owns Gemini batching and response parsing. The extension
  # wraps only the three methods needed to carry optional cache metadata.
  if (!is.null(native)) {
    S7::method(batch_submit, ProviderGeminiExtended) <- function(
      provider,
      conversations,
      type = NULL
    ) {
      cache_ttl <- attr(provider, ".gemini_cache_ttl")
      if (is.null(cache_ttl)) {
        return(native$submit(provider, conversations, type))
      }

      cache_name <- gemini_batch_cache(
        provider,
        conversations,
        type,
        cache_ttl
      )
      if (is.null(cache_name)) {
        return(native$submit(provider, conversations, type))
      }

      tryCatch(
        gemini_batch_submit_legacy(
          provider,
          conversations,
          type,
          cache_name
        ),
        error = function(e) {
          gemini_delete_cache(provider, cache_name)
          stop(e)
        }
      )
    }

    S7::method(batch_poll, ProviderGeminiExtended) <- function(provider, batch) {
      cache_name <- batch$.gemini_cache_name
      result <- native$poll(provider, batch)
      if (!is.null(cache_name)) {
        result$.gemini_cache_name <- cache_name
      }
      result
    }

    S7::method(batch_retrieve, ProviderGeminiExtended) <- function(provider, batch) {
      cache_name <- batch$.gemini_cache_name
      if (!is.null(cache_name)) {
        on.exit(gemini_delete_cache(provider, cache_name), add = TRUE)
      }
      native$retrieve(provider, batch)
    }

    return(invisible())
  }

  # ellmer <= 0.4.0: retain the original batch implementation for projects
  # that still use the extension as their Gemini batch provider.
  S7::method(has_batch_support, ProviderGeminiExtended) <- function(provider) {
    TRUE
  }

  S7::method(batch_submit, ProviderGeminiExtended) <- function(
    provider,
    conversations,
    type = NULL
  ) {
    cache_name <- gemini_batch_cache(
      provider,
      conversations,
      type,
      attr(provider, ".gemini_cache_ttl")
    )

    tryCatch(
      gemini_batch_submit_legacy(provider, conversations, type, cache_name),
      error = function(e) {
        if (!is.null(cache_name)) {
          gemini_delete_cache(provider, cache_name)
        }
        stop(e)
      }
    )
  }

  S7::method(batch_poll, ProviderGeminiExtended) <- function(provider, batch) {
    cache_name <- batch$.gemini_cache_name
    req <- ellmer_ns$base_request(provider)
    req <- httr2::req_url_path_append(req, batch$name)
    result <- httr2::req_perform(req) |>
      httr2::resp_body_json()
    if (!is.null(cache_name)) {
      result$.gemini_cache_name <- cache_name
    }
    result
  }

  S7::method(batch_status, ProviderGeminiExtended) <- function(provider, batch) {
    metadata <- batch$metadata %||% list()
    stats <- metadata$batchStats %||% list()
    state <- metadata$state %||% "BATCH_STATE_UNSPECIFIED"

    total <- as.integer(stats$requestCount %||% 0L)
    pending <- as.integer(stats$pendingRequestCount %||% 0L)
    succeeded <- as.integer(stats$successfulRequestCount %||% 0L)
    failed <- as.integer(stats$failedRequestCount %||% 0L)
    if (!is.null(batch$error) && total > 0L && failed == 0L) {
      failed <- total
    }

    is_done <- state %in% c(
      "BATCH_STATE_SUCCEEDED",
      "BATCH_STATE_FAILED",
      "BATCH_STATE_CANCELLED",
      "BATCH_STATE_EXPIRED"
    )
    if (state == "BATCH_STATE_SUCCEEDED" && !nzchar(batch$response$responsesFile %||% "")) {
      is_done <- FALSE
    }

    list(
      working = !is_done,
      n_processing = max(pending, total - succeeded - failed, 0L),
      n_succeeded = max(succeeded, 0L),
      n_failed = max(failed, 0L)
    )
  }

  S7::method(batch_retrieve, ProviderGeminiExtended) <- function(provider, batch) {
    cache_name <- batch$.gemini_cache_name
    if (!is.null(cache_name)) {
      on.exit(gemini_delete_cache(provider, cache_name), add = TRUE)
    }

    metadata <- batch$metadata %||% list()
    request_count <- as.integer(metadata$batchStats$requestCount %||% 0L)
    if (!is.null(batch$error)) {
      code <- as.integer(batch$error$code %||% 500L)
      return(rep(
        list(list(status_code = code, body = NULL)),
        max(0L, request_count)
      ))
    }

    responses_file <- batch$response$responsesFile %||% ""
    if (!nzchar(responses_file)) {
      cli::cli_abort("Gemini batch completed but no output file was returned.")
    }

    path <- withr::local_tempfile(fileext = ".jsonl")
    gemini_download_file(provider, responses_file, path)
    parsed <- ellmer_ns$read_ndjson(path)
    normalized <- purrr::imap(parsed, function(x, i) {
      gemini_normalize_result(x, index_default = as.integer(i))
    })
    ids <- vapply(normalized, function(x) x$index, integer(1))
    results <- lapply(normalized, function(x) x$result)
    results[order(ids)]
  }

  ContentJson <- ellmer_ns$ContentJson
  ContentText <- ellmer_ns$ContentText
  ContentThinking <- ellmer_ns$ContentThinking
  ContentToolRequest <- ellmer_ns$ContentToolRequest
  ContentImageInline <- ellmer_ns$ContentImageInline
  AssistantTurn <- ellmer_ns$AssistantTurn
  value_tokens <- ellmer_ns$value_tokens
  get_token_cost <- ellmer_ns$get_token_cost
  compact <- ellmer_ns$compact
  parent_as_json <- S7::method(
    as_json,
    list(ellmer_ns$ProviderGoogleGemini, ContentToolRequest)
  )

  S7::method(value_turn, ProviderGeminiExtended) <- function(
    provider,
    result,
    has_type = FALSE
  ) {
    message <- result$candidates[[1]]$content
    contents <- lapply(message$parts, function(content) {
      if (isTRUE(content$thought) && rlang::has_name(content, "text")) {
        ContentThinking(content$text)
      } else if (rlang::has_name(content, "text")) {
        if (has_type) ContentJson(string = content$text) else ContentText(content$text)
      } else if (rlang::has_name(content, "functionCall")) {
        request <- ContentToolRequest(
          content$functionCall$name,
          content$functionCall$name,
          content$functionCall$args
        )
        attr(request, ".gemini_thought_signature") <- content$thoughtSignature
        request
      } else if (rlang::has_name(content, "inlineData")) {
        ContentImageInline(
          type = content$inlineData$mimeType,
          data = content$inlineData$data
        )
      } else {
        cli::cli_abort(
          "Unknown content type with names {.str {names(content)}}.",
          .internal = TRUE
        )
      }
    })
    contents <- compact(contents)
    tokens <- value_tokens(provider, result)
    AssistantTurn(
      contents,
      json = result,
      tokens = unlist(tokens),
      cost = get_token_cost(provider, tokens)
    )
  }

  S7::method(
    as_json,
    list(ProviderGeminiExtended, ContentToolRequest)
  ) <- function(provider, x, ...) {
    result <- parent_as_json(provider, x, ...)
    signature <- attr(x, ".gemini_thought_signature")
    if (!is.null(signature)) {
      result$thoughtSignature <- signature
    }
    result
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

  invisible()
}
