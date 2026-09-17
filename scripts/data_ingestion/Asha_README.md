# Metadata Ingestion
This script combines metadata from multiple Excel/TXT files into one CSV file.
It:
- Reads all Excel/TXT files from the input folder
- Combines them into one table
- Adds `source_file` and `source_sheet` columns
- Renames any unnamed columns as `extra_unnamed_col1`, `extra_unnamed_col2`, etc.
- Removes rows with no metadata values
- Identifies duplicated metadata rows that occur in two or more input files and writes them to `duplicated_info_rows.csv`
- Collapses valid duplicated rows seperated by **commas* in the final combined dataset while retaining the contributing source file information
- Identifies incomplete rows where only one metadata column contains a value, excluding `source_file` and `source_sheet`, and writes them to `incomplete_info_rows.csv`
- Removes these incomplete rows from the final combined dataset
- Writes the final combined data to a CSV file

Update the input and output paths in the script before running.