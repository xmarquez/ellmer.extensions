skip_if_live_tests_disabled <- function(..., flag = "ELLMER_EXTENSIONS_RUN_LIVE_TESTS") {
  enabled <- tolower(Sys.getenv(flag, unset = "")) %in% c("1", "true", "yes")
  testthat::skip_if(!enabled, paste0("Set ", flag, "=true to run live API tests"))

  keys <- c(...)
  configured <- vapply(keys, function(key) nzchar(Sys.getenv(key, unset = "")), logical(1))
  testthat::skip_if(!any(configured), paste0("No API credential found in: ", paste(keys, collapse = ", ")))
}

wait_for_batch <- function(chat, prompts, path, timeout = 120, poll_interval = 10) {
  deadline <- Sys.time() + timeout
  while (Sys.time() < deadline) {
    if (isTRUE(ellmer::batch_chat_completed(chat, prompts, path))) {
      return(TRUE)
    }
    Sys.sleep(poll_interval)
  }
  FALSE
}
