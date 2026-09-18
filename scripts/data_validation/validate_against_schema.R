# Validate a TSV/CSV file against validation_rules_schema_HARTWELL_SCOPED.json
# (a Cerberus-style type/required/allowed schema). Writes two outputs: rows
# that pass (ready for LabKey) and rows that fail (with the specific reason).
#
# Usage: Rscript validate_against_schema.R <input.tsv|csv> [schema.json] [output_prefix]

library(tidyverse)
library(jsonlite)
library(tools)

args        <- commandArgs(trailingOnly = TRUE)
stopifnot("Usage: Rscript validate_against_schema.R <input.tsv|csv> [schema.json] [output_prefix]" = length(args) >= 1)

script_dir  <- dirname(normalizePath(sub("--file=", "", grep("--file=", commandArgs(trailingOnly = FALSE), value = TRUE))))
input_path  <- args[1]
schema_path <- if (length(args) >= 2) args[2] else file.path(dirname(script_dir), "analyses", "validation_rules_schema_HARTWELL.json")
out_prefix  <- if (length(args) >= 3) args[3] else file_path_sans_ext(input_path)

read_table <- if (file_ext(input_path) == "csv") read_csv else read_tsv
data <- read_table(input_path, col_types = cols(.default = "c")) %>%
  mutate(row_id = row_number())

rules <- fromJSON(schema_path, simplifyVector = FALSE)$hartwell_sample_rules

# A few schema field names don't match the raw HARTWELL column names
# (kept out of the schema itself so it stays plain type/required/allowed).
raw_column_aliases <- c(
  Lab_ID = "Lab ID #",
  Sample_Name = "Sample Name",
  SRM_Order_ID = "SRM Order #",
  SRM_Sample_ID = "SRM Sample #",
  Order_by = "Ordered by",
  Parental_Model_ID = "parental_model_id"
)

fields <- map(names(rules), function(field_name) {
  r <- rules[[field_name]]
  column <- case_when(
    field_name %in% names(data) ~ field_name,
    field_name %in% names(raw_column_aliases) ~ unname(raw_column_aliases[field_name]),
    TRUE ~ NA_character_
  )
  list(field = field_name, column = column, required = isTRUE(r$required),
       type = r$type, allowed = unlist(r$allowed))
})

# One row per (row_id, field, reason) validation failure.
errors <- map_dfr(fields, function(f) {
  if (is.na(f$column)) {
    if (f$required) return(tibble(row_id = data$row_id, field = f$field, reason = "required column missing from input"))
    return(tibble())
  }

  values <- data[[f$column]]
  blank  <- is.na(values) | str_trim(values) == ""

  bind_rows(
    if (f$required) tibble(row_id = data$row_id[blank], field = f$field, reason = "required but blank"),
    if (!is.null(f$allowed)) {
      bad <- !blank & !(values %in% f$allowed)
      tibble(row_id = data$row_id[bad], field = f$field, reason = str_c("value '", values[bad], "' not allowed"))
    },
    if (identical(f$type, "boolean")) {
      bad <- !blank & !(str_to_lower(str_trim(values)) %in% c("true", "false", "t", "f", "1", "0"))
      tibble(row_id = data$row_id[bad], field = f$field, reason = str_c("'", values[bad], "' is not a valid boolean"))
    }
  )
})

row_errors <- errors %>%
  group_by(row_id) %>%
  summarise(validation_errors = str_c(field, ": ", reason, collapse = "; "), .groups = "drop")

data <- left_join(data, row_errors, by = "row_id")
valid_rows   <- data %>% filter(is.na(validation_errors)) %>% select(-row_id, -validation_errors)
invalid_rows <- data %>% filter(!is.na(validation_errors)) %>% select(-row_id)

write_tsv(valid_rows, str_c(out_prefix, "_valid.tsv"), na = "")
write_tsv(invalid_rows, str_c(out_prefix, "_validation_errors.tsv"), na = "")

cat(nrow(data), "rows:", nrow(valid_rows), "valid,", nrow(invalid_rows), "failing\n")
cat("Wrote", str_c(out_prefix, "_valid.tsv"), "and", str_c(out_prefix, "_validation_errors.tsv"), "\n")
