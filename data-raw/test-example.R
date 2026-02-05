library(tidyverse)
library(ellmer)
devtools::load_all()
test_data <- read_csv(here::here("data-raw/politics_simple_prompts_sample.csv"))
test_data <- test_data |> 
  filter(ellmer_function == "chat_groq_developer")
structured_response_format_politics_simple <- ellmer::type_object(
        about_politics = ellmer::type_boolean(), 
        justification = ellmer::type_string(), 
        confidence_score = ellmer::type_number()
    )

chat_obj_groq_dev <- chat_groq_developer(model = test_data$model[[1]])
chat_obj_openai <- chat_openai(model = "gpt-5-nano")
simple_chat_structured <- chat_obj_groq_dev$chat_structured(
  test_data$prompt[[1]],
  type =  structured_response_format_politics_simple,
  convert = TRUE
)

# This works fine
simple_chat_structured

batch_chat_wait_false_groq <- batch_chat_structured(
  chat_obj_groq_dev,
  as.list(test_data$prompt[1:5]),
  type =  structured_response_format_politics_simple,
  path = here::here("data-raw/batch_results.json"),
  convert = TRUE,
  ignore_hash = TRUE,
  wait = FALSE
)

# This errors!
batch_chat_wait_false_groq
fs::file_delete(here::here("data-raw/batch_results.json"))

batch_chat_wait_false_openai <- batch_chat_structured(
  chat_obj_openai,
  as.list(test_data$prompt[1:5]),
  type =  structured_response_format_politics_simple,
  path = here::here("data-raw/batch_results.json"),
  convert = TRUE,
  wait = FALSE
)

batch_chat_structured(
  chat_obj_openai,
  as.list(test_data$prompt[1:5]),
  type =  structured_response_format_politics_simple,
  path = here::here("data-raw/batch_results.json"),
  convert = TRUE)
res3 <- parallel_chat_structured(
  chat_obj_groq_dev,
  as.list(test_data$prompt[1:5]),
  type =  structured_response_format_politics_simple,
  convert = TRUE
)

res3

