#' Groq Developer Provider Class
#'
#' S7 class that extends ProviderOpenAICompatible to provide Groq-specific functionality.
#' Inherits all capabilities from ProviderOpenAICompatible (which uses the Chat Completions
#' API format) while ensuring proper schema formatting for Groq's strict JSON validation.
#'
#' This class also implements batch processing support via Groq's Batch API,
#' which offers a 50% cost discount compared to synchronous API calls.
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

# Helper functions --------------------------------------------------------

#' Recursively add additionalProperties: false to all objects
#'
#' Groq requires additionalProperties: false on all objects for strict mode.
#' This helper ensures all nested objects have this property set.
#'
#' @param node A list representing a JSON schema node
#' @return The modified node with additionalProperties: false on all objects
#' @noRd
add_additional_properties_false <- function(node) {

  if (is.list(node) && !is.null(node$type) && identical(node$type, "object")) {
    node$additionalProperties <- FALSE
    if (!is.null(node$properties) && is.list(node$properties)) {
      node$properties <- lapply(node$properties, add_additional_properties_false)
    }
  }
  if (is.list(node) && !is.null(node$items)) {
    node$items <- add_additional_properties_false(node$items)
  }
  node
}

#' Upload a file to Groq's batch API
#'
#' @param provider A ProviderGroqDeveloper instance
#' @param path Path to the file to upload
#' @param purpose Purpose of the file (default: "batch" for batch processing)
#' @return The JSON response containing file metadata
#' @noRd
groq_upload_file <- function(provider, path, purpose = "batch") {
  ellmer_ns <- asNamespace("ellmer")
  req <- ellmer_ns$base_request(provider)
  req <- httr2::req_url_path_append(req, "/files")

  # Use curl::form_file with explicit filename and type
  req <- httr2::req_body_multipart(
    req,
    purpose = purpose,
    file = curl::form_file(path, type = "application/jsonl", name = "batch.jsonl")
  )

  resp <- httr2::req_perform(req)
  httr2::resp_body_json(resp)
}

#' Download a file from Groq's batch API
#'
#' @param provider A ProviderGroqDeveloper instance
#' @param id The file ID to download
#' @param path Local path to save the file
#' @return The path invisibly
#' @noRd
groq_download_file <- function(provider, id, path) {
  ellmer_ns <- asNamespace("ellmer")
  req <- ellmer_ns$base_request(provider)
  req <- httr2::req_url_path_append(req, "/files/", id, "/content")
  httr2::req_perform(req, path = path)

  invisible(path)
}

#' Convert an object to JSON string
#'
#' @param x Object to convert
#' @return JSON string
#' @noRd
to_json <- function(x) {
  jsonlite::toJSON(x, auto_unbox = TRUE)
}

#' Default fallback for Groq NDJSON parsing errors
#'
#' Extracts custom_id from failed line and returns a 500 error response.
#' @param line The failed JSON line
#' @return A list with custom_id and error response
#' @noRd
groq_json_fallback <- function(line) {
  # Try to extract custom_id from the line
  custom_id <- tryCatch({
    m <- regmatches(line, regexpr('"custom_id"\\s*:\\s*"([^"]+)"', line, perl = TRUE))
    if (length(m) > 0) {
      gsub('^"custom_id"\\s*:\\s*"([^"]+)".*', "\\1", m, perl = TRUE)
    } else {
      "unknown"
    }
  }, error = function(e) "unknown")

  list(
    custom_id = custom_id,
    response = list(status_code = 500, body = NULL)
  )
}

# Method registration -----------------------------------------------------

register_groq_methods <- function() {
  ellmer_ns <- asNamespace("ellmer")

  # Get the as_json generic from ellmer
  as_json <- S7::new_external_generic("ellmer", "as_json", "provider")

  # Get type classes
  TypeObject <- ellmer_ns$TypeObject
  TypeArray <- ellmer_ns$TypeArray

  # Get batch-related generics from ellmer
  has_batch_support <- ellmer_ns$has_batch_support
  batch_submit <- ellmer_ns$batch_submit
  batch_poll <- ellmer_ns$batch_poll
  batch_status <- ellmer_ns$batch_status
  batch_retrieve <- ellmer_ns$batch_retrieve
  batch_result_turn <- ellmer_ns$batch_result_turn
  chat_body <- ellmer_ns$chat_body
  value_turn <- ellmer_ns$value_turn

  # Register has_batch_support method
  S7::method(has_batch_support, ProviderGroqDeveloper) <- function(provider) {
    TRUE
  }

  # Register batch_submit method
  S7::method(batch_submit, ProviderGroqDeveloper) <- function(
    provider,
    conversations,
    type = NULL
  ) {
    # Create temporary file for batch requests
    path <- withr::local_tempfile()

    # Build request body for each conversation
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

    # Write requests as JSONL
    json_lines <- purrr::map_chr(requests, to_json)
    writeLines(json_lines, path)

    # Upload the file
    uploaded <- groq_upload_file(provider, path)

    # Create batch job
    req <- ellmer_ns$base_request(provider)
    req <- httr2::req_url_path_append(req, "/batches")
    req <- httr2::req_body_json(req, list(
      input_file_id = uploaded$id,
      endpoint = "/v1/chat/completions",
      completion_window = "24h"
    ))

    resp <- httr2::req_perform(req)
    httr2::resp_body_json(resp)
  }

  # Register batch_poll method
  S7::method(batch_poll, ProviderGroqDeveloper) <- function(provider, batch) {
    req <- ellmer_ns$base_request(provider)
    req <- httr2::req_url_path_append(req, "/batches/", batch$id)

    resp <- httr2::req_perform(req)
    httr2::resp_body_json(resp)
  }

  # Register batch_status method
  # Groq batch status values: validating, in_progress, finalizing, completed,
  # failed, expired, cancelling, cancelled
  # We consider anything other than these terminal states as "working"
  S7::method(batch_status, ProviderGroqDeveloper) <- function(provider, batch) {
    # Terminal states where we're no longer working
    terminal_states <- c("completed", "failed", "expired", "cancelled")
    is_working <- !(batch$status %in% terminal_states)

    # Safely extract request counts with defaults
    request_counts <- batch$request_counts
    total <- request_counts$total %||% 0
    completed <- request_counts$completed %||% 0
    failed <- request_counts$failed %||% 0

    list(
      working = is_working,
      n_processing = total - completed - failed,
      n_succeeded = completed,
      n_failed = failed
    )
  }

  # Register batch_retrieve method
  # Matches ellmer's ProviderOpenAI implementation for consistency
  S7::method(batch_retrieve, ProviderGroqDeveloper) <- function(provider, batch) {
    # Download output file
    path_output <- tempfile(fileext = ".jsonl")
    on.exit(unlink(path_output), add = TRUE)
    groq_download_file(provider, batch$output_file_id, path_output)

    # Read file and filter empty lines
    lines <- readLines(path_output, warn = FALSE)
    lines <- lines[nzchar(trimws(lines))]

    # Parse each line
    json <- lapply(lines, function(line) {
      tryCatch(
        jsonlite::fromJSON(line, simplifyVector = FALSE),
        error = function(e) groq_json_fallback(line)
      )
    })

    # Also get error file if it exists
    if (length(batch$error_file_id) == 1 && !is.null(batch$error_file_id) &&
          !identical(batch$error_file_id, list())) {
      path_error <- tempfile(fileext = ".jsonl")
      on.exit(unlink(path_error), add = TRUE)
      groq_download_file(provider, batch$error_file_id, path_error)

      error_lines <- readLines(path_error, warn = FALSE)
      error_lines <- error_lines[nzchar(trimws(error_lines))]
      error_json <- lapply(error_lines, function(line) {
        tryCatch(
          jsonlite::fromJSON(line, simplifyVector = FALSE),
          error = function(e) groq_json_fallback(line)
        )
      })
      json <- c(json, error_json)
    }

    # Filter out NULL entries
    json <- purrr::compact(json)

    if (length(json) == 0) {
      cli::cli_abort("No results found in batch output file")
    }

    # Extract and sort results by custom_id to restore original order
    # Use vapply for safer extraction (purrr::map_chr with "[["" can have issues)
    custom_ids <- vapply(json, function(x) x$custom_id, character(1))
    ids <- as.numeric(gsub("chat-", "", custom_ids))
    results <- lapply(json, function(x) x$response)
    results[order(ids)]
  }

  # Register batch_result_turn method
  S7::method(batch_result_turn, ProviderGroqDeveloper) <- function(
    provider,
    result,
    has_type = FALSE
  ) {
    if (!is.null(result) && result$status_code == 200) {
      value_turn(provider, result$body, has_type = has_type)
    } else {
      NULL
    }
  }

  # Note: No need to override chat_body since ProviderOpenAICompatible
  # already uses the Chat Completions API format that Groq supports.
  # We only need to override as_json methods for TypeObject and TypeArray
  # to add additionalProperties: false for Groq's strict JSON validation.

  # Register TypeObject method
  S7::method(as_json, list(ProviderGroqDeveloper, TypeObject)) <- function(provider, x, ...) {
    # Validate that additional_properties is not set (Groq doesn't support it)
    if (S7::prop(x, "additional_properties")) {
      cli::cli_abort("{.arg additional_properties} not supported for Groq structured outputs.")
    }

    # Get required properties
    props <- S7::prop(x, "properties")
    required <- purrr::map_lgl(props, function(prop) S7::prop(prop, "required"))

    # Build schema
    schema <- purrr::compact(list(
      type = "object",
      description = S7::prop(x, "description"),
      properties = ellmer_ns$as_json(provider, props, ...),
      required = as.list(names(props)[required]),
      additionalProperties = FALSE
    ))

    # Recursively ensure all nested objects have additionalProperties: false
    add_additional_properties_false(schema)
  }

  # Register TypeArray method
  S7::method(as_json, list(ProviderGroqDeveloper, TypeArray)) <- function(provider, x, ...) {
    items <- ellmer_ns$as_json(provider, S7::prop(x, "items"), ...)
    schema <- purrr::compact(list(
      type = "array",
      description = S7::prop(x, "description"),
      items = items
    ))

    add_additional_properties_false(schema)
  }
}

# Class initialization ----------------------------------------------------

# Initialize the class after ellmer is loaded
.onLoad <- function(libname, pkgname) {
  tryCatch({
    # Get parent provider classes from ellmer
    # ProviderOpenAI uses the Responses API format which Groq doesn't support
    # ProviderOpenAICompatible uses the Chat Completions API format
    ellmer_ns <- asNamespace("ellmer")
    ProviderOpenAICompatible <- ellmer_ns$ProviderOpenAICompatible
    ProviderGoogleGemini <- ellmer_ns$ProviderGoogleGemini

    # Create ProviderGroqDeveloper class extending ProviderOpenAICompatible
    ProviderGroqDeveloper <<- S7::new_class(
      name = "ProviderGroqDeveloper",
      package = "ellmer.extensions",
      parent = ProviderOpenAICompatible
    )

    # Create ProviderGeminiExtended class extending ProviderGoogleGemini
    ProviderGeminiExtended <<- S7::new_class(
      name = "ProviderGeminiExtended",
      package = "ellmer.extensions",
      parent = ProviderGoogleGemini
    )

    # Register method overrides
    register_groq_methods()
    register_gemini_methods()

    # Register all S7 methods with ellmer
    S7::methods_register()
  }, error = function(e) {
    # Silently deferred during documentation builds; interactive users will
    # see an informative error when they try to use the provider functions.
    NULL
  })
}

# Batch support is implemented via Groq's Batch API --------------------------
# See https://console.groq.com/docs/batch for documentation
# Batch processing offers 50% cost discount compared to synchronous API calls
