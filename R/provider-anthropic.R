#' Anthropic Provider with Extended Thinking + Structured Output
#'
#' Internal S7 class that extends `ellmer::ProviderAnthropic` with support for
#' extended thinking combined with structured output. When thinking is active,
#' uses `output_config.format` (JSON schema) instead of `tool_choice` to avoid
#' the Anthropic API conflict: *"Thinking may not be enabled when tool_choice
#' forces tool use."*
#'
#' @keywords internal
ProviderAnthropicExtended <- NULL

# Anthropic extended helpers -----------------------------------------------

#' Get the thinking configuration for the provider
#'
#' Returns the thinking mode stored on the provider by
#' `chat_anthropic_extended()`, or NULL if not set.
#' @noRd
anthropic_thinking_mode <- function(provider) {
  attr(provider, ".anthropic_thinking")
}

# Method registration ------------------------------------------------------

#' Register S7 methods for ProviderAnthropicExtended
#'
#' Called from `.onLoad()` and defensively from `chat_anthropic_extended()`.
#' @noRd
register_anthropic_methods <- function() {
  ellmer_ns <- asNamespace("ellmer")

  # Internals we need from ellmer
  chat_body <- ellmer_ns$chat_body
  chat_params <- ellmer_ns$chat_params
  value_turn <- ellmer_ns$value_turn
  value_tokens <- ellmer_ns$value_tokens
  get_token_cost <- ellmer_ns$get_token_cost
  is_system_turn <- ellmer_ns$is_system_turn
  cache_control <- ellmer_ns$cache_control
  as_json <- ellmer_ns$as_json
  compact <- ellmer_ns$compact
  map2 <- ellmer_ns$map2
  ToolDef <- ellmer_ns$ToolDef
  type_object <- ellmer_ns$type_object
  ContentText <- ellmer_ns$ContentText
  ContentJson <- ellmer_ns$ContentJson
  ContentThinking <- ellmer_ns$ContentThinking
  ContentToolRequest <- ellmer_ns$ContentToolRequest
  ContentToolRequestSearch <- ellmer_ns$ContentToolRequestSearch
  ContentToolRequestFetch <- ellmer_ns$ContentToolRequestFetch
  ContentToolResponseSearch <- ellmer_ns$ContentToolResponseSearch
  ContentToolResponseFetch <- ellmer_ns$ContentToolResponseFetch
  AssistantTurn <- ellmer_ns$AssistantTurn
  map_chr <- ellmer_ns$map_chr

  # chat_body: route to parent or extended depending on thinking mode --------
  S7::method(chat_body, ProviderAnthropicExtended) <- function(
    provider, stream = TRUE, turns = list(), tools = list(), type = NULL
  ) {
    thinking_mode <- anthropic_thinking_mode(provider)
    has_thinking <- !is.null(thinking_mode)

    # --- System prompt (shared by both paths) ---
    if (length(turns) >= 1 && is_system_turn(turns[[1]])) {
      system <- list(list(type = "text", text = turns[[1]]@text))
      system[[1]]$cache_control <- cache_control(provider)
    } else {
      system <- NULL
    }

    # --- Messages (shared) ---
    is_last <- seq_along(turns) == length(turns)
    messages <- compact(map2(turns, is_last, function(turn, is_last) {
      as_json(provider, turn, is_last = is_last)
    }))

    # --- Params (shared) ---
    params <- chat_params(provider, provider@params)

    # Ensure max_tokens is large enough when thinking is enabled.
    # ellmer defaults max_tokens to 4096, which is insufficient for thinking.
    if (has_thinking && !is.null(params$max_tokens) && params$max_tokens <= 4096L) {
      if (rlang::has_name(params, "budget_tokens") && params$max_tokens <= params$budget_tokens) {
        # Enabled thinking: max_tokens must exceed budget_tokens
        params$max_tokens <- params$budget_tokens + 16384L
      } else if (!rlang::has_name(params, "budget_tokens")) {
        # Adaptive thinking: no budget_tokens, but 4096 is still too small.
        # max_tokens covers both thinking and output tokens combined.
        params$max_tokens <- 32768L
      }
    }

    # When thinking is active AND structured output is requested:
    # use output_config.format (JSON schema) instead of tool_choice
    if (has_thinking && !is.null(type)) {
      # Build JSON schema from the type directly (no {data: ...} wrapper).
      # ContentJson will be constructed from the raw parsed text.
      schema <- as_json(provider, type)

      output_config <- list(
        format = list(type = "json_schema", schema = schema)
      )

      # Build thinking block
      if (identical(thinking_mode, "adaptive")) {
        thinking <- list(type = "adaptive")
        params$budget_tokens <- NULL  # strip if present; adaptive doesn't use budget
      } else if (rlang::has_name(params, "budget_tokens")) {
        thinking <- list(type = "enabled", budget_tokens = params$budget_tokens)
        params$budget_tokens <- NULL
      } else {
        # Fallback: thinking = "enabled" was set but no budget_tokens;
        # this should have been caught by chat_anthropic_extended(), but
        # handle gracefully by not enabling thinking
        thinking <- NULL
        output_config <- NULL
      }

      # Preserve real user tools (non-structured-output tools) but do NOT
      # add the synthetic _structured_tool_call or force tool_choice.
      # output_config handles structured output; real tools can coexist.
      tools_json <- if (length(tools) > 0) {
        as_json(provider, unname(tools))
      } else {
        NULL
      }

      stream <- FALSE
      compact(rlang::list2(
        model = provider@model,
        system = system,
        messages = messages,
        stream = stream,
        tools = tools_json,
        output_config = output_config,
        thinking = thinking,
        !!!params
      ))

    } else {
      # --- Default path: delegate to parent ProviderAnthropic logic ---
      # Replicate ellmer's chat_body for ProviderAnthropic exactly
      if (!is.null(type)) {
        tool_def <- ToolDef(
          function(...) {},
          name = "_structured_tool_call",
          description = "Extract structured data",
          arguments = type_object(data = type)
        )
        tools[[tool_def@name]] <- tool_def
        tool_choice <- list(type = "tool", name = tool_def@name)
        stream <- FALSE
      } else {
        tool_choice <- NULL
      }

      tools <- as_json(provider, unname(tools))

      if (rlang::has_name(params, "budget_tokens")) {
        thinking <- list(type = "enabled", budget_tokens = params$budget_tokens)
        params$budget_tokens <- NULL
      } else if (has_thinking && identical(thinking_mode, "adaptive")) {
        thinking <- list(type = "adaptive")
        params$budget_tokens <- NULL  # strip if present; adaptive doesn't use budget
      } else {
        thinking <- NULL
      }

      compact(rlang::list2(
        model = provider@model,
        system = system,
        messages = messages,
        stream = stream,
        tools = tools,
        tool_choice = tool_choice,
        thinking = thinking,
        !!!params
      ))
    }
  }

  # value_turn: handle text-as-JSON when using output_config.format ----------
  S7::method(value_turn, ProviderAnthropicExtended) <- function(
    provider, result, has_type = FALSE
  ) {
    thinking_mode <- anthropic_thinking_mode(provider)
    has_thinking <- !is.null(thinking_mode)

    # When thinking + structured output: the model returns JSON in text
    # blocks (via output_config.format). We join all text blocks, parse as
    # JSON once, and emit a single ContentJson. Thinking blocks and genuine
    # tool_use blocks are preserved as-is.
    if (has_type && has_thinking) {
      text_parts <- character()
      non_text_contents <- list()

      for (content in result$content) {
        if (content$type == "thinking") {
          non_text_contents <- c(
            non_text_contents,
            list(ContentThinking(content$thinking, extra = list(signature = content$signature)))
          )
        } else if (content$type == "text") {
          text_parts <- c(text_parts, content$text)
        } else if (content$type == "tool_use") {
          # Genuine tool_use (not structured output tool — we didn't add one)
          if (rlang::is_string(content$input)) {
            content$input <- jsonlite::parse_json(content$input)
          }
          non_text_contents <- c(
            non_text_contents,
            list(ContentToolRequest(content$id, content$name, content$input))
          )
        } else if (content$type == "server_tool_use") {
          if (content$name == "web_search") {
            non_text_contents <- c(
              non_text_contents,
              list(ContentToolRequestSearch(query = content$input$query, json = content))
            )
          } else if (content$name == "web_fetch") {
            non_text_contents <- c(
              non_text_contents,
              list(ContentToolRequestFetch(url = content$input$url, json = content))
            )
          }
        } else if (content$type == "web_search_tool_result") {
          urls <- map_chr(content$content, function(x) x$url)
          non_text_contents <- c(
            non_text_contents,
            list(ContentToolResponseSearch(url = urls, json = content))
          )
        } else if (content$type == "web_fetch_tool_result") {
          non_text_contents <- c(
            non_text_contents,
            list(ContentToolResponseFetch(url = content$url %||% "failed", json = content))
          )
        }
        # Other unknown content types are skipped gracefully
      }

      # Detect truncated responses: stop_reason == "max_tokens" means the
      # model ran out of token budget (often from an adaptive thinking loop).
      is_truncated <- identical(result$stop_reason, "max_tokens")

      # Parse text as JSON → ContentJson.
      # Two scenarios: (1) API splits a single JSON response across multiple
      # text blocks (join then parse), or (2) adaptive thinking produces
      # multiple complete JSON blocks in a self-correction loop (use last).
      # Try individual blocks first (last-wins), then fall back to joining.
      if (length(text_parts) > 0) {
        parsed <- NULL
        # Try each text block individually (last valid one wins)
        for (tp in rev(text_parts)) {
          parsed <- tryCatch(
            jsonlite::parse_json(tp, simplifyVector = FALSE),
            error = function(e) NULL
          )
          if (!is.null(parsed) && is.list(parsed)) break
          parsed <- NULL
        }
        # If no individual block parsed, try joining all blocks
        if (is.null(parsed)) {
          joined <- paste(text_parts, collapse = "")
          parsed <- tryCatch(
            jsonlite::parse_json(joined, simplifyVector = FALSE),
            error = function(e) NULL
          )
        }

        if (is_truncated) {
          cli::cli_warn(c(
            "Anthropic response truncated ({.val max_tokens}).",
            "i" = "{length(text_parts)} text block{?s} found; last block is incomplete.",
            "i" = "Model {result$model %||% 'unknown'} used {result$usage$output_tokens %||% '?'} output tokens.",
            if (!is.null(parsed)) "i" = "Recovered JSON from an earlier complete text block, but the result may reflect a self-correction loop rather than the model's final answer."
          ))
        }

        if (!is.null(parsed) && is.list(parsed)) {
          non_text_contents <- c(non_text_contents, list(ContentJson(data = parsed)))
        } else {
          # Could not parse as JSON; fall back to ContentText
          non_text_contents <- c(non_text_contents, list(ContentText(
            paste(text_parts, collapse = "")
          )))
        }
      }

      contents <- non_text_contents
    } else {
      # Standard path: same as parent ProviderAnthropic
      contents <- lapply(result$content, function(content) {
        if (content$type == "thinking") {
          ContentThinking(content$thinking, extra = list(signature = content$signature))
        } else if (content$type == "text") {
          ContentText(content$text)
        } else if (content$type == "tool_use") {
          if (has_type) {
            ContentJson(data = content$input$data)
          } else {
            if (rlang::is_string(content$input)) {
              content$input <- jsonlite::parse_json(content$input)
            }
            ContentToolRequest(content$id, content$name, content$input)
          }
        } else if (content$type == "server_tool_use") {
          if (content$name == "web_search") {
            ContentToolRequestSearch(query = content$input$query, json = content)
          } else if (content$name == "web_fetch") {
            ContentToolRequestFetch(url = content$input$url, json = content)
          } else {
            cli::cli_abort("Unknown server tool {.str {content$name}}.")
          }
        } else if (content$type == "web_search_tool_result") {
          urls <- map_chr(content$content, function(x) x$url)
          ContentToolResponseSearch(url = urls, json = content)
        } else if (content$type == "web_fetch_tool_result") {
          ContentToolResponseFetch(url = content$url %||% "failed", json = content)
        } else {
          cli::cli_abort(
            "Unknown content type {.str {content$type}}.",
            .internal = TRUE
          )
        }
      })
    }

    tokens <- value_tokens(provider, result)
    cost <- get_token_cost(provider, tokens)
    AssistantTurn(contents, json = result, tokens = unlist(tokens), cost = cost)
  }
}
