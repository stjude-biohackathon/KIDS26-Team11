# HARTWELL metadata standardization rules developed 2026-09-17
#
# Purpose:
#   1. Preserve protected source fields.
#   2. Treat the ORIGINAL `Sample Name` as immutable source-of-truth.
#      All normalization is written ONLY to `Standard Name`.
#   3. Encode SME-informed rules directly so no external terms/template
#      workbook is required at runtime.
#   4. Standardize Danielle Little mouse sample names.
#   5. Standardize the MAST naming conventions discussed on 2026-09-17.
#   6. SME v4: Natalie Geiger CSTN shorthand (e.g. 725_1 / 686A_1.1) gets MAST prefix, Tissue=PDX, Project=CSTN.
#   7. Apply SME Project classification rules (v6), always using ORIGINAL Sample Name.
#   8. Generalize the SME MAST/CCLF examples into family parsers and extract
#      condition, media, timepoint, and treatment into separate columns.
#   9. Standardize mountain-coded mouse samples and derive Species/Target.
#  10. Flag names that cannot be standardized confidently.
#
# CRITICAL SOURCE-FIELD RULE (v6):
#   `Sample Name` must NEVER be normalized, corrected, or overwritten.
#   Pattern matching always reads from the original Sample Name.
#   The temporary `Sample Name_mistake` audit column from v5 is no longer
#   carried forward. Only original `Sample Name` and derived `Standard Name` remain.
#
# Packages: readxl, openxlsx, dplyr, stringr

library(readxl)
library(openxlsx)
library(dplyr)
library(stringr)
library(stringi)

# Repository defaults. Run this script from the repository root.
master_file <- file.path("dataset", "HARTWELL_database_Master_2025.xlsx")
output_dir  <- "output"
out_file    <- file.path(
  output_dir,
  "HARTWELL_database_Master_2025_standardized_SME_updated_v14.xlsx"
)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(master_file)) {
  stop(
    "Input workbook not found: ", master_file,
    "\nRun the script from the KIDS26-Team11 repository root, or update `master_file`."
  )
}

master <- read_excel(master_file)

# Standalone exact names learned from the SME reference files. These are
# embedded here so the earlier reference workbooks are not runtime inputs.
# All pattern-based MAST/CCLF rules are implemented in functions below.
known_exact_names <- c(
  "TO", "H9", "GIMEN", "Kelly", "SKNAS", "U2OS", "HeLa", "CHLA90",
  "SKNMM", "ATF5", "WT", "1-11 C3128 L570S_F", "1-11 C3128 L570S_R"
)

# -----------------------------------------------------------------------------
# INPUT SCHEMA INITIALIZATION
# Accept a raw database containing the original 13 headings. If this script is
# rerun on an enriched output, previously derived columns are deliberately
# dropped and rebuilt so stale values cannot leak into the new result.
# -----------------------------------------------------------------------------
original_headings <- c(
  "Lab ID #", "Date Ordered", "Sample Name", "Ordered by",
  "Notebook Page #", "SRM Order #", "SRM Sample #", "Assay", "Tissue",
  "Tumor Type", "Species", "Failed", "Notes"
)

missing_original_headings <- setdiff(original_headings, names(master))
if (length(missing_original_headings) > 0) {
  stop(
    "Input database is missing required original heading(s): ",
    paste(missing_original_headings, collapse = ", ")
  )
}

# Restore the canonical raw schema order before applying any transformations.
# Derived fields (Standard Name, Project, Target, condition, media, treatment,
# and timepoint) are created later by this script.
master <- master[, original_headings]

# Define the record boundary by the last populated Lab ID #. This prevents
# free-text footer notes below the database (for example, comments entered in
# the Sample Name column after the final record) from being imported as data.
# Rows inside the record block are retained even if a field is temporarily
# blank; only content below the final Lab ID # is excluded.
lab_id_present <- !is.na(master$`Lab ID #`) &
  str_trim(as.character(master$`Lab ID #`)) != ""

if (!any(lab_id_present)) {
  stop("No populated values were found in `Lab ID #`; record boundary cannot be determined.")
}

last_record_row <- max(which(lab_id_present))

if (last_record_row < nrow(master)) {
  trailing_rows <- master[(last_record_row + 1):nrow(master), , drop = FALSE]
  trailing_has_content <- apply(
    trailing_rows,
    1,
    function(row) any(!is.na(row) & str_trim(as.character(row)) != "")
  )

  if (any(trailing_has_content)) {
    warning(
      sum(trailing_has_content),
      " nonblank trailing row(s) below the final `Lab ID #` were excluded from the output."
    )
  }

  master <- master[seq_len(last_record_row), , drop = FALSE]
}

# Date Ordered contains calendar dates only. Remove any time component while
# retaining a true Date value that remains sortable in Excel.
date_ordered_original <- master$`Date Ordered`
if (inherits(date_ordered_original, "POSIXt")) {
  master$`Date Ordered` <- as.Date(date_ordered_original)
} else if (inherits(date_ordered_original, "Date")) {
  master$`Date Ordered` <- date_ordered_original
} else if (is.numeric(date_ordered_original)) {
  master$`Date Ordered` <- as.Date(date_ordered_original, origin = "1899-12-30")
} else {
  date_text <- str_trim(as.character(date_ordered_original))
  date_text[date_text == ""] <- NA_character_
  master$`Date Ordered` <- as.Date(
    date_text,
    tryFormats = c("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%Y/%m/%d")
  )
  failed_dates <- !is.na(date_text) & is.na(master$`Date Ordered`)
  if (any(failed_dates)) {
    stop(
      "Could not parse ", sum(failed_dates),
      " nonblank `Date Ordered` value(s). Review the source date format."
    )
  }
}

# -----------------------------------------------------------------------------
# Preserve fields that must never be altered. Sample Name is retained here for
# auditing, but v13 permits one narrow SME-authorized edit: removal of terminal
# LUC+/YFP reporter annotations after they are moved to condition.
# -----------------------------------------------------------------------------
protected_fields <- c("Lab ID #", "Sample Name", "SRM Order #", "SRM Sample #")
protected_before <- master[, protected_fields]

# Immutable copy used by every naming rule below. Never transform this vector.
source_sample_name <- master$`Sample Name`

# -----------------------------------------------------------------------------
# Danielle Little mouse naming
# Examples:
#   Lepr97-56   <- Lepr97-56 / LepR84-13 / LEPR 97-56 variants
#   CbaWT       <- Cba_WT / CBAWT
#   Rrd45-23    <- RRd 45-23
# Only the first letter of the family portion is capitalized and spaces are
# removed. WT is retained as uppercase.
# -----------------------------------------------------------------------------
standardize_danielle <- function(x) {
  if (is.na(x)) return(NA_character_)
  z <- str_squish(x)

  # WT forms: remove spaces/underscores before WT; normalize family case.
  if (str_detect(z, regex("^[A-Za-z]+[ _]?WT$", ignore_case = TRUE))) {
    family <- str_remove(z, regex("[ _]?WT$", ignore_case = TRUE))
    family <- str_to_lower(family)
    family <- str_c(str_to_upper(str_sub(family, 1, 1)), str_sub(family, 2))
    return(str_c(family, "WT"))
  }

  # Family + animal numbers, e.g. LepR84-13, RRd 45-23, Cba95-93.
  if (str_detect(z, regex("^[A-Za-z]+\\s*\\d+\\s*-\\s*\\d+$"))) {
    family <- str_extract(z, "^[A-Za-z]+")
    nums   <- str_extract(z, "\\d+\\s*-\\s*\\d+$") |> str_replace_all("\\s+", "")
    family <- str_to_lower(family)
    family <- str_c(str_to_upper(str_sub(family, 1, 1)), str_sub(family, 2))
    return(str_c(family, nums))
  }

  NA_character_
}

# -----------------------------------------------------------------------------
# MAST standardization -- SME rules updated 2026-09-17
#
# The SME clarified that MAST naming also determines Tissue and Project.
# These rules supersede earlier assumptions about S7/P1 and TAZEMETOSTAT.
#
# 1) CSTN / PDX:
#      MAST 1143_1       -> MAST 1143_1       | PDX | CSTN
#      MAST 808_1.2      -> MAST 808_1.2      | PDX | CSTN
#    This rule is applied to Natalie Geiger MAST records with a numeric
#    PDXmouse[.passage] component. Optional treatment follows with underscore.
#
# 2) 3D2D:
#      MAST 191B T       -> MAST 191B_T       | PDX_tumor    | 3D2D
#      MAST 191B S7      -> MAST 191B_3D      | PDX_spheroid | 3D2D
#      MAST 191B p1      -> MAST 191B_2D      | PDX_cells    | 3D2D
#
# 3) Pre-clinical treatment studies:
#      MAST 3 U21 TAZEMETOSTAT -> MAST 3_U21_TAZ | PDX | pre-clinical
#      MAST 3 U23 IRN + TMZ + TAZ -> MAST 3_U23_IRN_TMZ_TAZ
#    TAZEMETOSTAT is standardized to TAZ (NOT TMZ).
#
# Regex below is implementation logic derived from the SME examples.
# -----------------------------------------------------------------------------
standardize_mast_sme <- function(x, ordered_by = NA_character_) {
  if (is.na(x)) return(list(name=NA_character_, tissue=NA_character_, project=NA_character_))
  z <- str_squish(x)

  # 3D2D: T=tumor, S7=3D spheroid, p1=2D cells.
  m <- str_match(z, regex("^MAST\\s+(\\d+[A-Za-z]?)\\s+(T|S7|p1)$", ignore_case=TRUE))
  if (!is.na(m[1,1])) {
    tp <- str_to_upper(m[1,2]); token <- str_to_upper(m[1,3])
    if (token == "T")  return(list(name=str_c("MAST ",tp,"_T"),  tissue="PDX_tumor",    project="3D2D"))
    if (token == "S7") return(list(name=str_c("MAST ",tp,"_3D"), tissue="PDX_spheroid", project="3D2D"))
    if (token == "P1") return(list(name=str_c("MAST ",tp,"_2D"), tissue="PDX_cells",    project="3D2D"))
  }

  # Pre-clinical: alpha-prefixed PDX mouse ID followed by one or more treatments.
  m <- str_match(z, regex("^MAST\\s+(\\d+[A-Za-z]?)\\s+([A-Za-z]{1,2}\\s*\\d+)\\s+(.+)$", ignore_case=TRUE))
  if (!is.na(m[1,1])) {
    tp <- str_to_upper(m[1,2])
    mouse <- str_to_upper(str_remove_all(m[1,3], "\\s+"))
    treatment <- m[1,4] |>
      str_replace_all("\\s+\\+\\s+", "_") |>
      str_replace_all("\\s+", "_") |>
      str_replace_all(regex("TAZEMETOSTAT", ignore_case=TRUE), "TAZ") |>
      str_to_upper()
    return(list(name=str_c("MAST ",tp,"_",mouse,"_",treatment), tissue="PDX", project="pre-clinical"))
  }

  # CSTN: numeric PDX mouse[.passage], optionally followed by treatment.
  # Per SME examples/context, classify these as CSTN when ordered by Natalie Geiger.
  m <- str_match(z, regex("^MAST\\s+(\\d+[A-Za-z]?)\\s*[_ ]\\s*(\\d+(?:\\.\\d+)?)(?:\\s+(.+))?$", ignore_case=TRUE))
  if (!is.na(m[1,1]) && !is.na(ordered_by) && ordered_by == "Natalie Geiger") {
    nm <- str_c("MAST ", str_to_upper(m[1,2]), "_", m[1,3])
    if (!is.na(m[1,4]) && str_trim(m[1,4]) != "") {
      treatment <- m[1,4] |>
        str_replace_all("\\s+\\+\\s+", "_") |>
        str_replace_all("\\s+", "_") |>
        str_replace_all(regex("TAZEMETOSTAT", ignore_case=TRUE), "TAZ") |>
        str_to_upper()
      nm <- str_c(nm, "_", treatment)
    }
    return(list(name=nm, tissue="PDX", project="CSTN"))
  }

  list(name=NA_character_, tissue=NA_character_, project=NA_character_)
}



# -----------------------------------------------------------------------------
# Source-name cleanup for rule matching -- v11
# Do NOT write this cleaned value back to Sample Name. It exists only so
# invisible Unicode/control characters and non-breaking spaces cannot prevent
# otherwise-valid naming rules from matching.
# -----------------------------------------------------------------------------
clean_sample_for_matching <- function(x) {
  if (is.na(x)) return(NA_character_)
  x |>
    stringi::stri_trans_nfkc() |>
    stringi::stri_replace_all_regex("[\\p{Cf}\\p{Cc}]", "") |>
    str_replace_all("\u00A0", " ") |>
    str_squish()
}

# -----------------------------------------------------------------------------
# Mountain-coded mouse samples -- SME update 2026-09-18
#
# Examples:
#   O18_4-11        -> O18_4-11       | mouse_BL6   | R635W
#   EC1 3-57        -> EC1_3-57       | mouse_129S6 | M627I
#   EC1 4-40 (MtK)  -> EC1_4-40_MtK   | mouse_129S6 | M627I
#
# Prefix legend embedded from MT_TABLE.xlsx so no external legend file is
# required when this script is run. EC is treated as a two-letter prefix and
# takes precedence over the single-letter mapping.
# -----------------------------------------------------------------------------
standardize_mountain_mouse <- function(x) {
  if (is.na(x)) {
    return(list(name = NA_character_, species = NA_character_, target = NA_character_))
  }

  y <- clean_sample_for_matching(x)
  m <- str_match(
    y,
    regex(
      "^(EC|F|K|M|W|O|D|B|A|C|T|N)([0-9]+)[ _]([0-9]+)-([0-9]+)(?:\\s*\\(([^()]*)\\))?$",
      ignore_case = TRUE
    )
  )

  if (is.na(m[1, 1])) {
    return(list(name = NA_character_, species = NA_character_, target = NA_character_))
  }

  prefix <- str_to_upper(m[1, 2])
  standard_name <- paste0(prefix, m[1, 3], "_", m[1, 4], "-", m[1, 5])

  annotation <- m[1, 6]
  if (!is.na(annotation) && str_trim(annotation) != "") {
    annotation <- str_squish(annotation)
    if (str_to_lower(annotation) == "mtk") annotation <- "MtK"
    standard_name <- paste0(standard_name, "_", annotation)
  }

  species <- if (prefix %in% c("F", "K", "M", "W", "O", "D")) {
    "mouse_BL6"
  } else {
    "mouse_129S6"
  }

  target <- case_when(
    prefix %in% c("F", "B")  ~ "e18del",
    prefix %in% c("K", "A")  ~ "K672N",
    prefix %in% c("M", "C")  ~ "K625M",
    prefix %in% c("W", "EC") ~ "M627I",
    prefix %in% c("O", "T")  ~ "R635W",
    prefix %in% c("D", "N")  ~ "L570S",
    TRUE ~ NA_character_
  )

  list(name = standard_name, species = species, target = target)
}

# -----------------------------------------------------------------------------
# Retinal Degeneration rules -- SME updates 2026-09-17 (v8-v10)
# v10: broadened Prd handling after review of prd.xlsx. Numeric Prd IDs
# anywhere in the database and WT/WT2-style controls follow the same rule.
# Source Sample Name is immutable.
# Standard Name families: Lepr, Cba, Rrd, Prd.
# Normalize prefix capitalization; insert "_" before numeric/WT identifier;
# remove internal spacing; normalize WT to uppercase.
# Tissue = retina; Project = Retinal Degeneration.
# -----------------------------------------------------------------------------
standardize_retinal_degeneration <- function(x) {
  if (is.na(x)) return(NA_character_)

  y <- clean_sample_for_matching(x) |>
    str_replace_all("\\s*-\\s*", "-") |>
    str_replace_all("[\\s_]+", "")

  m <- str_match(
    y,
    regex("^(Lepr|Cba|Rrd|Prd)(WT[0-9]*|[0-9]+-[0-9]+)$", ignore_case = TRUE)
  )
  if (is.na(m[1, 1])) return(NA_character_)

  prefix <- case_when(
    str_to_lower(m[1, 2]) == "lepr" ~ "Lepr",
    str_to_lower(m[1, 2]) == "cba"  ~ "Cba",
    str_to_lower(m[1, 2]) == "rrd"  ~ "Rrd",
    str_to_lower(m[1, 2]) == "prd"  ~ "Prd"
  )
  ident <- if_else(
    str_detect(m[1, 3], regex("^WT[0-9]*$", ignore_case = TRUE)),
    str_to_upper(m[1, 3]),
    m[1, 3]
  )
  paste0(prefix, "_", ident)
}


# -----------------------------------------------------------------------------
# Target annotation rules -- SME update 2026-09-17 (v9)
# Derived from immutable Sample Name:
#   Cba/CBA -> Ins2-Akita; Prd -> Pde6b-rd10; Rrd/RRD -> Rpe65-rd12.
# -----------------------------------------------------------------------------
derive_target <- function(x) {
  if (is.na(x)) return(NA_character_)
  y <- clean_sample_for_matching(x) |> str_replace_all("[\\s_]+", "")
  case_when(
    str_detect(y, regex("^Cba", ignore_case=TRUE)) ~ "Ins2-Akita",
    str_detect(y, regex("^Prd", ignore_case=TRUE)) ~ "Pde6b-rd10",
    str_detect(y, regex("^Rrd", ignore_case=TRUE)) ~ "Rpe65-rd12",
    TRUE ~ NA_character_
  )
}


# -----------------------------------------------------------------------------
# RB1 standardization -- SME update 2026-09-17 (v12)
# Sample Name remains immutable.
#
# General:
# RB1KO_<clone>_<time> (n) -> RB1_KO_<clone>_<time>_repn
#
# Explicit "Cells" mappings supplied by SME:
# RB1 KO 3A1 Cells (n)  -> RB1_KO_3A1_3m_repn
# RB1 KO 2F12 Cells (n) -> RB1_KO_2F12_Cells_repn
#
# All matching records: Target = RB1.
# -----------------------------------------------------------------------------
standardize_rb1 <- function(x) {
  if (is.na(x)) return(NA_character_)
  y <- clean_sample_for_matching(x)

  m <- str_match(y, regex("^RB1\\s*KO\\s+3A1\\s+Cells\\s*\\((\\d+)\\)$",
                          ignore_case = TRUE))
  if (!is.na(m[1,1])) return(paste0("RB1_KO_3A1_3m_rep", m[1,2]))

  m <- str_match(y, regex("^RB1\\s*KO\\s+2F12\\s+Cells\\s*\\((\\d+)\\)$",
                          ignore_case = TRUE))
  if (!is.na(m[1,1])) return(paste0("RB1_KO_2F12_Cells_rep", m[1,2]))

  m <- str_match(y, regex("^RB1\\s*KO[_\\s]+([A-Za-z0-9]+)[_\\s]+([A-Za-z0-9]+)\\s*\\((\\d+)\\)$",
                          ignore_case = TRUE))
  if (!is.na(m[1,1])) {
    return(paste0("RB1_KO_", str_to_upper(m[1,2]), "_", m[1,3], "_rep", m[1,4]))
  }

  NA_character_
}

# -----------------------------------------------------------------------------
# MERTK Standard Name rules -- SME update 2026-09-17 (v7)
#
# These transformations are applied ONLY to Standard Name. The original
# Sample Name remains immutable and is used as the source/reference field.
#
# Examples:
#   MERTK R629W Clone 1C8 (2) -> MERTK R629W 1C8_rep2
#   MERTK K619M Clone 1C12    -> MERTK K619M 1C12
#   MERTK del 2F9             -> MERTK del2F9
#   MERTK K619M 1C12 (2)      -> MERTK K619M 1C12_rep2
#   MERTK del 3E2 (2)         -> MERTK del3E2_rep2
#
# Rules:
#   1. Remove the literal word "Clone " (case-insensitive).
#   2. Remove whitespace immediately after "del".
#   3. Convert a terminal parenthetical replicate, e.g. (2), to _rep2.
#   4. Do not insert a space before _rep.
# -----------------------------------------------------------------------------
standardize_mertk <- function(x) {
  if (is.na(x) || !str_detect(x, regex("\\bMERTK\\b", ignore_case = TRUE))) {
    return(NA_character_)
  }

  x |>
    str_squish() |>
    str_replace_all(regex("\\bClone\\s+", ignore_case = TRUE), "") |>
    str_replace_all(regex("\\bdel\\s+", ignore_case = TRUE), "del") |>
    str_replace(regex("\\s*\\(([^()]*)\\)\\s*$"), "_rep\\1")
}

# -----------------------------------------------------------------------------
# CCLF family parser -- SME template update 2026-09-18 (v13)
# The template rows are pattern examples, not an exact-match lookup table.
# Examples covered include:
#   RA-SJ1005 VT CCLF 01.24.012 (...) -> SJ1005_CCLF_VT
#   RPMI-SJ1044 VT CCLF 01.24.001     -> SJ1044_CCLF_VT
#   SJ1041-CCLF H3K27ac               -> SJ1041_CCLF_H3K27ac
#   CCLF 01.25.018 SJ1041 2.10.25     -> SJ1041_CCLF
# -----------------------------------------------------------------------------
standardize_cclf <- function(x) {
  empty <- list(name=NA_character_, condition=NA_character_, media=NA_character_,
                timepoint=NA_character_, treatment=NA_character_,
                tissue=NA_character_, project=NA_character_)
  if (is.na(x)) return(empty)
  y <- clean_sample_for_matching(x)
  if (!str_detect(y, regex("CCLF", ignore_case=TRUE)) ||
      !str_detect(y, regex("SJ\\s*\\d+", ignore_case=TRUE))) return(empty)

  sj <- str_extract(y, regex("SJ\\s*\\d+", ignore_case=TRUE)) |>
    str_remove_all("\\s+") |> str_to_upper()
  is_vt <- str_detect(y, regex("(?:^|[ -])VT(?:$|[ # -])", ignore_case=TRUE))

  assay <- str_match(y, regex("CCLF[ -]*(H3K27ac|H3K27me3|H3K4me3|input)\\s*$",
                              ignore_case=TRUE))[,2]
  if (!is.na(assay) && str_to_lower(assay) == "input") assay <- "input"

  nm <- paste0(sj, "_CCLF")
  if (is_vt) nm <- paste0(nm, "_VT")
  if (!is.na(assay)) nm <- paste0(nm, "_", assay)

  order_code <- str_extract(y, "\\b\\d{2}\\.\\d{2}\\.\\d{3}\\b")
  extras <- character(0)

  vt_number <- str_match(y, regex("\\bVT\\s*#(\\d+)", ignore_case=TRUE))[,2]
  if (!is.na(vt_number)) extras <- c(extras, paste0("#", vt_number))

  parenthetical <- str_match(y, "\\(([^()]*)\\)\\s*$")[,2]
  if (!is.na(parenthetical)) extras <- c(extras, parenthetical)

  # Reverse-order form: CCLF <order> SJ#### m.d.yy. Normalize its date.
  trailing_date <- str_match(y, "(\\d{1,2})\\.(\\d{1,2})\\.(\\d{2}|\\d{4})\\s*$")
  if (!is.na(trailing_date[1,1]) && (is.na(order_code) || trailing_date[1,1] != order_code)) {
    yr <- trailing_date[1,4]
    if (nchar(yr) == 2) yr <- paste0("20", yr)
    extras <- c(extras, sprintf("%02d.%02d.%s",
                                as.integer(trailing_date[1,2]),
                                as.integer(trailing_date[1,3]), yr))
  }

  condition <- order_code
  if (length(extras) > 0) {
    suffix <- paste0("(", paste(unique(extras), collapse="; "), ")")
    condition <- ifelse(is.na(condition), suffix, paste(condition, suffix))
  }

  list(
    name=nm,
    condition=condition,
    media=ifelse(str_detect(y, regex("^RPMI-", ignore_case=TRUE)), "RPMI", NA_character_),
    timepoint=NA_character_,
    treatment=ifelse(str_detect(y, regex("^RA(?:-|\\s)", ignore_case=TRUE)), "RA", NA_character_),
    tissue=ifelse(is_vt, "PDX_validated", NA_character_),
    project=ifelse(is_vt, "3D2D", NA_character_)
  )
}

# -----------------------------------------------------------------------------
# Additional MAST family parser -- SME template update 2026-09-18 (v13)
# Separates replicate/date, media, timepoint, condition and treatment tokens
# from the standardized biological sample name.
# -----------------------------------------------------------------------------
standardize_mast_special <- function(x) {
  empty <- list(name=NA_character_, condition=NA_character_, media=NA_character_,
                timepoint=NA_character_, treatment=NA_character_,
                tissue=NA_character_, project=NA_character_)
  if (is.na(x)) return(empty)
  y <- clean_sample_for_matching(x)
  if (!str_detect(y, regex("^MAST", ignore_case=TRUE))) return(empty)

  # MAST1037_1 / MAST 1143_2: retain the valid CSTN name with normalized spacing.
  m <- str_match(y, regex("^MAST\\s*(\\d+[A-Za-z]?_\\d+(?:\\.\\d+)?)$", ignore_case=TRUE))
  if (!is.na(m[1,1])) return(modifyList(empty, list(name=paste("MAST", str_to_upper(m[1,2])))))

  # MAST 621A Rep 2_12.4.25 / RepA_1.13.2026.
  m <- str_match(y, regex("^MAST\\s+(\\d+[A-Za-z]?)\\s+Rep\\s*([A-Za-z0-9]+)(?:_(\\d{1,2}\\.\\d{1,2}\\.\\d{2,4}))?$", ignore_case=TRUE))
  if (!is.na(m[1,1])) {
    return(modifyList(empty, list(name=paste0("MAST ",str_to_upper(m[1,2]),"_rep",m[1,3]),
                                  condition=m[1,4])))
  }

  # MAST 97 [noRA] 48hr p0.
  m <- str_match(y, regex("^MAST\\s+(\\d+[A-Za-z]?)(?:\\s+(noRA))?\\s+(\\d+hr)\\s+(p\\d+)$", ignore_case=TRUE))
  if (!is.na(m[1,1])) {
    return(modifyList(empty, list(name=paste0("MAST ",str_to_upper(m[1,2]),"_",str_to_lower(m[1,5])),
                                  media=ifelse(is.na(m[1,3]),NA_character_,"noRA"),
                                  timepoint=str_to_lower(m[1,4]))))
  }

  m <- str_match(y, regex("^MAST\\s+(\\d+[A-Za-z]?)\\s+tumor\\s+([A-Za-z0-9]+)$", ignore_case=TRUE))
  if (!is.na(m[1,1])) return(modifyList(empty, list(name=paste("MAST",str_to_upper(m[1,2])),
                                                     condition=paste0("tumor_",str_to_upper(m[1,3])))))

  m <- str_match(y, regex("^MAST\\s+(\\d+[A-Za-z]?)\\s+RFP\\s+unsorted$", ignore_case=TRUE))
  if (!is.na(m[1,1])) return(modifyList(empty, list(name=paste("MAST",str_to_upper(m[1,2])),
                                                     condition="RFP_unsorted")))

  # MAST394C_ET 155_ITT -> MAST 394C_E155 + decoded treatment.
  m <- str_match(y, regex("^MAST\\s*(\\d+[A-Za-z]?)_ET\\s*(\\d+)_(IT|ITT)$", ignore_case=TRUE))
  if (!is.na(m[1,1])) {
    trt <- ifelse(str_to_upper(m[1,4]) == "ITT", "IRN+TMZ+TAZ", "IRN+TMZ")
    return(modifyList(empty, list(name=paste0("MAST ",str_to_upper(m[1,2]),"_E",m[1,3]),
                                  treatment=trt, project="pre-clinical")))
  }

  # MAST 97_N94_IT and analogous IT/ITT/Taz families.
  m <- str_match(y, regex("^MAST\\s*(\\d+[A-Za-z]?)_([A-Za-z]?\\d+)_(IT|ITT|Taz)(?:_(LT))?$", ignore_case=TRUE))
  if (!is.na(m[1,1])) {
    token <- str_to_upper(m[1,4])
    trt <- case_when(token == "IT" ~ "IRN+TMZ", token == "ITT" ~ "IRN+TMZ+TAZ", TRUE ~ "TAZ")
    return(modifyList(empty, list(name=paste0("MAST ",str_to_upper(m[1,2]),"_",str_to_upper(m[1,3])),
                                  condition=ifelse(is.na(m[1,5]),NA_character_,"LT"),
                                  treatment=trt, project="pre-clinical")))
  }

  empty
}

# -----------------------------------------------------------------------------
# Main standardization pass.
# -----------------------------------------------------------------------------
# Treat physically present but substantively empty spreadsheet rows as empty.
# This is important because stray comments/text can extend Excel's used range
# far below the actual database (for example, text accidentally entered in
# Sample Name on an otherwise empty row). Such rows should NOT be flagged.
#
# A row is ignored when:
#   1. Sample Name is blank/NA; OR
#   2. Sample Name contains text, but every other source metadata field is
#      blank/NA (a likely stray note/comment rather than a sample record).
# `Standard Name` is excluded from this test so the script can also be rerun on
# a workbook that already contains that derived column.

is_blank_value <- function(x) {
  is.na(x) || (is.character(x) && str_trim(x) == "")
}

row_has_other_metadata <- function(df, i) {
  cols <- setdiff(names(df), c("Sample Name", "Standard Name"))
  vals <- df[i, cols, drop = FALSE]
  any(!vapply(vals, is_blank_value, logical(1)))
}

standard_name <- rep(NA_character_, nrow(master))
updated_tissue <- master$Tissue
project <- if ("Project" %in% names(master)) master$Project else rep(NA_character_, nrow(master))
target <- rep(NA_character_, nrow(master))
condition <- rep(NA_character_, nrow(master))
media <- rep(NA_character_, nrow(master))
timepoint <- rep(NA_character_, nrow(master))
treatment <- rep(NA_character_, nrow(master))

for (i in seq_len(nrow(master))) {
  sample <- source_sample_name[i]
  target[i] <- derive_target(sample)
  ordered_by <- master$`Ordered by`[i]
  notebook <- master$`Notebook Page #`[i]

  # Do not create a review flag for empty rows or stray text/comments on an
  # otherwise empty row. Leave Standard Name blank and move to the next row.
  if (is_blank_value(sample) || !row_has_other_metadata(master, i)) {
    standard_name[i] <- NA_character_
    next
  }

  candidate <- NA_character_

  # Danielle Little rules have priority for her samples.
  if (!is.na(ordered_by) && ordered_by == "Danielle Little") {
    candidate <- standardize_danielle(sample)
  }

  # Retinal Degeneration rules update Standard Name, Tissue, and Project.
  retinal_candidate <- standardize_retinal_degeneration(sample)
  if (!is.na(retinal_candidate)) {
    candidate <- retinal_candidate
    updated_tissue[i] <- "retina"
    project[i] <- "Retinal Degeneration"
  }

  # RB1 rules update Standard Name and Target.
  rb1_candidate <- standardize_rb1(sample)
  if (!is.na(rb1_candidate)) {
    candidate <- rb1_candidate
    target[i] <- "RB1"
  }

  # MERTK rules update Standard Name only.
  if (is.na(candidate) && !is.na(sample) &&
      str_detect(sample, regex("\\bMERTK\\b", ignore_case = TRUE))) {
    candidate <- standardize_mertk(sample)
  }

  # CCLF examples define a family parser, not an exact-name lookup.
  # Apply it to every CCLF name containing an SJ identifier.
  if (is.na(candidate)) {
    cclf <- standardize_cclf(sample)
    if (!is.na(cclf$name)) {
      candidate <- cclf$name
      condition[i] <- cclf$condition
      media[i] <- cclf$media
      timepoint[i] <- cclf$timepoint
      treatment[i] <- cclf$treatment
      if (!is.na(cclf$tissue)) updated_tissue[i] <- cclf$tissue
      if (!is.na(cclf$project)) project[i] <- cclf$project
    }
  }

  # Generalized special MAST patterns from the template.
  if (is.na(candidate)) {
    mast_special <- standardize_mast_special(sample)
    if (!is.na(mast_special$name)) {
      candidate <- mast_special$name
      condition[i] <- mast_special$condition
      media[i] <- mast_special$media
      timepoint[i] <- mast_special$timepoint
      treatment[i] <- mast_special$treatment
      if (!is.na(mast_special$tissue)) updated_tissue[i] <- mast_special$tissue
      if (!is.na(mast_special$project)) project[i] <- mast_special$project
    }
  }

  # MAST SME rules update Standard Name, Tissue, and Project together.
  if (is.na(candidate) && !is.na(sample) && str_detect(sample, regex("^MAST", ignore_case = TRUE))) {
    mast <- standardize_mast_sme(sample, ordered_by)
    if (!is.na(mast$name)) {
      candidate <- mast$name
      updated_tissue[i] <- mast$tissue
      project[i] <- mast$project
    }
  }

  # CSTN shorthand -- SME update 2026-09-17 (v4):
  # Natalie Geiger samples entered without the MAST prefix, e.g.
  # 725_1, 747B_1, 786C_1, 808_1, 686A_1.1, 715A_1, are CSTN MAST PDXs.
  # Add only the missing "MAST " prefix; preserve the tumorpiece/mouse/passage token.
  if (is.na(candidate) && !is.na(ordered_by) && ordered_by == "Natalie Geiger" &&
      !is.na(sample) && str_detect(str_squish(sample), "^\\d+[A-Za-z]?_\\d+(\\.\\d+)?$")) {
    candidate <- str_c("MAST ", str_squish(sample))
    updated_tissue[i] <- "PDX"
    project[i] <- "CSTN"
  }

  # Retain the prior CSTN-notebook fallback for equivalent shorthand records
  # when Ordered By is missing or inconsistent.
  if (is.na(candidate) && !is.na(notebook) && str_detect(notebook, fixed("CSTN")) &&
      !is.na(sample) && str_detect(str_squish(sample), "^\\d+[A-Za-z]?_\\d+(\\.\\d+)?$")) {
    candidate <- str_c("MAST ", str_squish(sample))
    updated_tissue[i] <- "PDX"
    project[i] <- "CSTN"
  }

  # Retain the small embedded set of known standalone names as written.
  if (is.na(candidate) && !is.na(sample) && sample %in% known_exact_names) {
    candidate <- sample
  }

  standard_name[i] <- ifelse(is.na(candidate), "FLAG FOR REVIEW", candidate)
}

# Insert derived Standard Name immediately after the ORIGINAL Sample Name.
# `Sample Name_mistake` was an audit-only column used in v5 and is dropped in v6.
# IMPORTANT: never assign normalized values back to master$`Sample Name`.
if ("Standard Name" %in% names(master)) master$`Standard Name` <- NULL
if ("Sample Name_mistake" %in% names(master)) master$`Sample Name_mistake` <- NULL
for (nm in c("condition", "media", "timepoint", "treatment")) {
  if (nm %in% names(master)) master[[nm]] <- NULL
}
insert_after <- match("Sample Name", names(master))
master <- bind_cols(
  master[, seq_len(insert_after)],
  tibble(
    `Standard Name` = standard_name,
    condition = condition,
    media = media,
    timepoint = timepoint,
    treatment = treatment
  ),
  master[, (insert_after + 1):ncol(master)]
)

# -----------------------------------------------------------------------------
# SME Project classification rules -- v6, 2026-09-17
# All rules inspect ORIGINAL Sample Name (source_sample_name), never Standard Name.
# Existing CSTN assignments from the Natalie Geiger shorthand rule are retained.
#
# Precedence implemented below:
#   base MAST 3D2D/CSTN -> pre-clinical -> Ordered-by overrides -> H9/MERTK ->
#   Diana Acevedo override (unless already 3D2D).
# -----------------------------------------------------------------------------
has_3d2d_token <- function(x) {
  !is.na(x) && str_detect(x, regex("(?:^|[ _])(S6|S7|S8|S14|P1|P2|P3|P3T|2D|3D|T|T0)(?:$|[ _()])", ignore_case=TRUE))
}

has_cstn_mast_pattern <- function(x) {
  if (is.na(x) || !str_detect(x, regex("MAST", ignore_case=TRUE))) return(FALSE)
  str_detect(x, "_\\d+\\.\\d+(?:$|[ _])") ||
    str_detect(x, "\\d+[A-Za-z]?_\\d+(?:\\.\\d+)?(?:$|[ _])")
}

is_preclinical_mast <- function(x) {
  if (is.na(x) || !str_detect(x, regex("MAST", ignore_case=TRUE))) return(FALSE)
  has_mouse <- str_detect(x, regex("(?:^|[ _])[A-Za-z]\\d{2}(?:$|[ _])", ignore_case=TRUE))
  has_treatment <- str_detect(x, regex("(?:^|[ _+])(TAZ|TAZEMETOSTAT|IRN|TMZ)(?:$|[ _+])", ignore_case=TRUE))
  has_mouse && has_treatment
}

for (i in seq_len(nrow(master))) {
  sample <- source_sample_name[i]
  ordered_by <- master$`Ordered by`[i]

  if (is_blank_value(sample) || !row_has_other_metadata(master, i)) next

  # 1. MAST + S6/S7/S8/S14/P1/P2/P3/P3T/2D/3D/T/T0 -> 3D2D.
  if (str_detect(sample, regex("MAST", ignore_case=TRUE)) && has_3d2d_token(sample)) {
    project[i] <- "3D2D"
  }

  # 2. MAST + _number.number or number_number -> CSTN.
  if (has_cstn_mast_pattern(sample)) {
    project[i] <- "CSTN"
  }

  # 8. MAST + letter/two-number mouse ID (e.g. U81) + treatment -> pre-clinical.
  if (is_preclinical_mast(sample)) {
    project[i] <- "pre-clinical"
  }

  # 3. Victoria Honnell or Mellisa Clemmons -> SuperEnhancers.
  # The database currently contains the spelling "Mellisa Clemons"; accept both.
  if (!is.na(ordered_by) && ordered_by %in% c("Victoria Honnell", "Mellisa Clemmons", "Mellisa Clemons")) {
    project[i] <- "SuperEnhancers"
  }

  # 4. Shannon Sweeney: non-MAST -> Retinal Organoid Factory; MAST -> 3D2D.
  if (!is.na(ordered_by) && ordered_by == "Shannon Sweeney") {
    project[i] <- ifelse(str_detect(sample, regex("MAST", ignore_case=TRUE)),
                         "3D2D", "Retinal Organoid Factory")
  }

  # 5. H9 or H9_ -> Retinal Organoid Factory.
  if (str_detect(sample, regex("H9_|\\bH9\\b", ignore_case=TRUE))) {
    project[i] <- "Retinal Organoid Factory"
  }

  # 6. MERTK -> MERTK.
  if (str_detect(sample, regex("MERTK", ignore_case=TRUE))) {
    project[i] <- "MERTK"
  }

  # 7. Diana Acevedo -> NBL_Diana unless the sample is already 3D2D.
  if (!is.na(ordered_by) && ordered_by == "Diana Acevedo" && (is.na(project[i]) || project[i] != "3D2D")) {
    project[i] <- "NBL_Diana"
  }
}

# Apply SME-derived Tissue values and add Project immediately after Tissue.
master$Tissue <- updated_tissue
if ("Project" %in% names(master)) master$Project <- NULL
tissue_pos <- match("Tissue", names(master))
master <- bind_cols(
  master[, seq_len(tissue_pos)],
  tibble(Project = project, Target = target),
  master[, (tissue_pos + 1):ncol(master)]
)

# -----------------------------------------------------------------------------
# Additional SME rules -- 2026-09-18
# -----------------------------------------------------------------------------

# 1. Rrd family: use Rrd_number-number. The space becomes an underscore;
#    the hyphen separating the two numeric components is retained.
rrd_match <- str_match(
  source_sample_name,
  regex("^Rrd\\s+(\\d+)\\s*-\\s*(\\d+)$", ignore_case = TRUE)
)
rrd_rows <- !is.na(rrd_match[,1])
master$`Standard Name`[rrd_rows] <- paste0(
  "Rrd_", rrd_match[rrd_rows,2], "-", rrd_match[rrd_rows,3]
)

# 2. Target annotations are derived from the original Sample Name.
lepr_rows <- str_detect(source_sample_name, regex("Lepr", ignore_case = TRUE))
mertk_rows <- str_detect(source_sample_name, regex("MERTK", ignore_case = TRUE))
master$Target[lepr_rows & !is.na(lepr_rows)] <- "LEPR"
master$Target[mertk_rows & !is.na(mertk_rows)] <- "MERTK"

# Remove tumor-type labels that were mistakenly entered as molecular targets.
invalid_target_values <- c("EWS", "OST", "neuroblastoma", "mouse", "NBL", "MEL")
invalid_target_rows <- !is.na(master$Target) &
  str_to_lower(str_trim(master$Target)) %in% str_to_lower(invalid_target_values)
master$Target[invalid_target_rows] <- NA_character_

# Mountain-coded mouse samples. Apply the family rule to every supported
# prefix, not only to the examples in MOUNTAIN.xlsx. Original Sample Name is
# never changed. The MT_TABLE legend is embedded in standardize_mountain_mouse().
mountain_parsed <- lapply(source_sample_name, standardize_mountain_mouse)
mountain_rows <- !vapply(mountain_parsed, function(x) is.na(x$name), logical(1))

master$`Standard Name`[mountain_rows] <- vapply(
  mountain_parsed[mountain_rows], function(x) x$name, character(1)
)
master$Species[mountain_rows] <- vapply(
  mountain_parsed[mountain_rows], function(x) x$species, character(1)
)
master$Target[mountain_rows] <- vapply(
  mountain_parsed[mountain_rows], function(x) x$target, character(1)
)

# Guard the El Capitan exception explicitly: EC always maps to mouse_129S6.
ec_mountain_rows <- mountain_rows &
  str_detect(source_sample_name, regex("^EC[0-9]+[ _]", ignore_case = TRUE))
stopifnot(all(master$Species[ec_mountain_rows] == "mouse_129S6"))

# 3. Normalize every populated Tissue value to lowercase.
master$Tissue <- if_else(
  is.na(master$Tissue),
  NA_character_,
  str_to_lower(as.character(master$Tissue))
)

# 4. Move terminal reporter annotations from Sample Name into condition.
#    Also remove the corresponding terminal token from Standard Name so the
#    reporter exists in one queryable field only.
reporter_match <- str_match(
  source_sample_name,
  regex("\\s+(LUC\\+|YFP)\\s*$", ignore_case = TRUE)
)
reporter_rows <- !is.na(reporter_match[,1])
reporter_value <- str_to_upper(reporter_match[,2])

master$`Sample Name`[reporter_rows] <- str_remove(
  source_sample_name[reporter_rows],
  regex("\\s+(LUC\\+|YFP)\\s*$", ignore_case = TRUE)
)
master$`Standard Name`[reporter_rows] <- str_remove(
  master$`Standard Name`[reporter_rows],
  regex("(?:_|\\s)(LUC\\+|YFP)\\s*$", ignore_case = TRUE)
)
for (i in which(reporter_rows)) {
  current <- master$condition[i]
  reporter <- reporter_value[i]
  if (is.na(current) || str_trim(current) == "") {
    master$condition[i] <- reporter
  } else if (!str_detect(current, fixed(reporter))) {
    master$condition[i] <- paste(current, reporter, sep = "; ")
  }
}

# Final presentation/schema order supplied by SME on 2026-09-18.
column_order <- c(
  "Project", "Lab ID #", "Date Ordered", "Sample Name", "Standard Name",
  "Species", "Tumor Type", "Tissue", "Target", "condition", "media",
  "treatment", "timepoint", "Ordered by", "Notebook Page #", "SRM Order #",
  "SRM Sample #", "Assay", "Failed", "Notes"
)
stopifnot(setequal(names(master), column_order))
master <- master[, column_order]

# -----------------------------------------------------------------------------
# Safety checks: only the explicitly authorized terminal reporter annotation
# may differ in Sample Name. All other protected fields remain immutable.
# -----------------------------------------------------------------------------
expected_sample_name <- str_remove(
  source_sample_name,
  regex("\\s+(LUC\\+|YFP)\\s*$", ignore_case = TRUE)
)
stopifnot(identical(master$`Sample Name`, expected_sample_name))

# Every CCLF record with an SJ identifier must be handled by the family parser.
cclf_rows <- str_detect(source_sample_name, regex("CCLF", ignore_case=TRUE)) &
  str_detect(source_sample_name, regex("SJ\\s*\\d+", ignore_case=TRUE))
stopifnot(!any(master$`Standard Name`[cclf_rows] == "FLAG FOR REVIEW", na.rm=TRUE))

# Every recognized mountain-coded sample must be standardized and annotated.
stopifnot(!any(master$`Standard Name`[mountain_rows] == "FLAG FOR REVIEW", na.rm = TRUE))
stopifnot(all(master$Species[mountain_rows] %in% c("mouse_BL6", "mouse_129S6")))
stopifnot(all(!is.na(master$Target[mountain_rows])))


strict_protected <- c("Lab ID #", "SRM Order #", "SRM Sample #")
stopifnot(identical(
  as.data.frame(protected_before[, strict_protected]),
  as.data.frame(master[, strict_protected])
))

# -----------------------------------------------------------------------------
# Export. Highlight review flags for manual QC.
# -----------------------------------------------------------------------------
wb <- createWorkbook()
addWorksheet(wb, "Sheet1")
writeData(wb, "Sheet1", master, keepNA = FALSE)

header_style <- createStyle(fontName = "Aptos", fontSize = 11,
                            textDecoration = "bold", fgFill = "#D9EAF7",
                            border = "Bottom", halign = "left", valign = "center")
addStyle(wb, "Sheet1", header_style, rows = 1, cols = seq_len(ncol(master)), gridExpand = TRUE)

body_style <- createStyle(fontName = "Aptos", fontSize = 11,
                          halign = "left", valign = "center")
addStyle(wb, "Sheet1", body_style, rows = 2:(nrow(master) + 1),
         cols = seq_len(ncol(master)), gridExpand = TRUE, stack = TRUE)

date_col <- match("Date Ordered", names(master))
date_style <- createStyle(fontName = "Aptos", fontSize = 11,
                          numFmt = "mm/dd/yyyy", halign = "left", valign = "center")
addStyle(wb, "Sheet1", date_style, rows = 2:(nrow(master) + 1),
         cols = date_col, gridExpand = TRUE, stack = TRUE)

std_col <- match("Standard Name", names(master))
flag_rows <- which(master$`Standard Name` == "FLAG FOR REVIEW") + 1
if (length(flag_rows) > 0) {
  flag_style <- createStyle(fgFill = "#FFF2CC")
  addStyle(wb, "Sheet1", flag_style, rows = flag_rows, cols = std_col, gridExpand = TRUE, stack = TRUE)
}

freezePane(wb, "Sheet1", firstRow = TRUE)
setColWidths(wb, "Sheet1", cols = seq_len(ncol(master)), widths = "auto")
saveWorkbook(wb, out_file, overwrite = TRUE)

message("Wrote: ", out_file)
message("Rows flagged for review: ", sum(master$`Standard Name` == "FLAG FOR REVIEW", na.rm = TRUE))
