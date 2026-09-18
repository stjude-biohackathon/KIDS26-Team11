# HARTWELL metadata standardization

## Purpose

This workflow converts the Developmental and Solid Tumor legacy metadata workbook into a standardized, queryable table while retaining source identifiers and flagging unresolved names for human review.

## Input and output

Run the script from the repository root.

- Input: `dataset/HARTWELL_database_Master_2025.xlsx`
- Output: `output/HARTWELL_database_Master_2025_standardized_SME_updated_v14.xlsx`

The input workbook must contain these original headings:

`Lab ID #`, `Date Ordered`, `Sample Name`, `Ordered by`, `Notebook Page #`, `SRM Order #`, `SRM Sample #`, `Assay`, `Tissue`, `Tumor Type`, `Species`, `Failed`, and `Notes`.

## Requirements

Use R 4.x with these packages:

```r
install.packages(c("readxl", "openxlsx", "dplyr", "stringr", "stringi"))
```

## Run

From the repository root:

```bash
Rscript scripts/HARTWELL_standardization_2026-09-18_v14.R
```

## What the workflow does

- Validates the original input schema.
- Removes footer material below the final populated `Lab ID #` record.
- Derives a standardized `Standard Name` without generally rewriting `Sample Name`.
- Derives queryable fields including `Project`, `Target`, `condition`, `media`, `treatment`, and `timepoint`.
- Standardizes `Tissue` and `Species` for SME-supported naming patterns.
- Moves authorized terminal `LUC+` and `YFP` reporter suffixes from `Sample Name` into `condition`.
- Checks protected identifiers with assertions before writing the result.
- Writes an Excel workbook with Aptos 11-point font, a frozen header, left-aligned populated cells, and date-only values in `Date Ordered`.
- Highlights unresolved `Standard Name` values as `FLAG FOR REVIEW`.

## Source-field policy

`Lab ID #`, `SRM Order #`, and `SRM Sample #` remain unchanged. `Sample Name` is retained as the parsing source, with one explicitly authorized exception: a terminal ` LUC+` or ` YFP` annotation is removed only after it is migrated to `condition`. All other normalization is written to derived fields, especially `Standard Name`.

## Human review

`FLAG FOR REVIEW` means that no confident, SME-supported rule matched the record. It does not necessarily mean that the source value is invalid. Review flagged records before downstream integration or enforcement.

The script does not require `terms.xlsx`, `MAST_CCLF(1).xlsx`, `MOUNTAIN.xlsx`, or `MT_TABLE.xlsx`; the reviewed rules and mappings needed by version 14 are embedded in the script.

## Limitations

- This is a program-specific prototype, not a universal metadata validator.
- The mappings reflect the naming families and SME examples reviewed for version 14.
- New or changed naming families should be reviewed with a subject-matter expert before new enforcement rules are added.
- Use only approved, de-identified metadata in the shared repository workflow.
