# Metadata Ingestion
This script combines metadata from multiple Excel/TXT files into one CSV file.
It:
- Reads all Excel/TXT files from the input folder
- Combines them into one table
- Adds a `source_file` column
- Renames any unnamed columns as *extra_unnamed_col1*, *extra_unnamed_col2*, etc.
- Writes the combined data to a CSV file
- Update the input and output paths in the script before running.
