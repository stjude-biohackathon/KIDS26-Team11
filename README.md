# Biohackathon Project Template

This repository is a starting point for a three-day team project. This repository is populated with a starting template for team organization and planning. Use it to plan, build, and document work. Please adjust this repository to suit the needs of your team.

> **Team leads:** Start with the [team lead checklist](project-management/CHECKLIST.md) before the event or during your first team meeting.

## Project Profile

- **Communication:** [Add the agreed channel or contact]

# **Project name:**: FAIR Harmonization and Automated LabKey Integration of Legacy Sequencing Metadata

> **St. Jude BioHackathon 2026 | Team 11**

## Overview

Research institutions often maintain years to decades of sequencing data generated across evolving technologies, computational pipelines, metadata standards, and storage systems. Over time, these datasets accumulate inconsistent sample naming conventions, incomplete metadata, duplicated records, incompatible formatting, and fragmented documentation.

These challenges create significant barriers to:

* Data discovery and reuse
* Cross-study integration
* Reproducible research
* Long-term data stewardship
* Migration into centralized data management platforms

This project aims to prototype a reproducible and extensible framework for harmonizing heterogeneous legacy sequencing metadata and preparing standardized outputs for integration into LabKey.

Rather than reanalyzing sequencing data, our focus is on improving the quality, consistency, and interoperability of the metadata that describes sequencing experiments.

---

# The Challenge

Legacy sequencing projects often contain metadata distributed across multiple sources, including:

* Excel spreadsheets
* CSV and TSV files
* Sample sheets
* Sequencing manifests
* Pipeline output files
* Project tracking documents
* Inconsistent file and directory naming conventions

Manual metadata cleanup is time-consuming, difficult to reproduce, and challenging to scale across large collections of historical datasets.

Current approaches frequently rely on project-specific spreadsheets and manual curation. This can result in inconsistent metadata structures, duplicated effort, and loss of institutional knowledge over time.

Our challenge is to develop a prototype workflow capable of transforming heterogeneous metadata sources into a validated and standardized representation suitable for downstream data management and integration.

---

# Project Goals

During the BioHackathon, we aim to prototype an end-to-end metadata harmonization workflow that can:

1. **Ingest heterogeneous metadata**

   * Excel spreadsheets
   * CSV/TSV files
   * Sample manifests
   * Other structured sequencing metadata

2. **Standardize metadata structure**

   * Normalize column names
   * Standardize data formats
   * Apply consistent naming conventions

3. **Validate metadata quality**

   * Identify missing values
   * Detect duplicate records
   * Flag conflicting metadata
   * Identify invalid or inconsistent values

4. **Harmonize selected metadata fields**

   * Map values to controlled vocabularies
   * Standardize biological and experimental annotations
   * Document transformations

5. **Generate standardized outputs**

   * Produce harmonized metadata tables
   * Generate validation/QC reports
   * Prepare outputs suitable for downstream LabKey integration

---

# Proposed Workflow

```text
                  Legacy Metadata Sources
                           │
          ┌────────────────┼────────────────┐
          │                │                │
      Excel Files       CSV/TSV       Sample Manifests
          │                │                │
          └────────────────┼────────────────┘
                           │
                           ▼
                    Data Ingestion
                           │
                           ▼
                  Schema Normalization
                           │
                           ▼
                   Metadata Validation
                           │
                           ▼
                 Metadata Harmonization
                           │
                           ▼
                    Quality Control
                           │
                           ▼
               Standardized Metadata Output
                           │
                           ▼
                LabKey-Compatible Export
```

---

# Expected Outputs

Potential deliverables from the BioHackathon include:

* Metadata ingestion and parsing utilities
* Metadata schema definitions
* Validation and quality-control workflows
* Harmonization and transformation utilities
* Standardized metadata outputs
* LabKey-compatible import templates
* Automated validation reports
* Documentation and reproducible examples

The goal is not to create a production-ready platform within 72 hours. Instead, we aim to demonstrate a functional and extensible prototype that can serve as the foundation for continued development.

---

# Example Questions the Workflow Should Help Answer

The prototype should help identify and address questions such as:

* Are required metadata fields missing?
* Do multiple records refer to the same biological sample?
* Are sample identifiers formatted consistently?
* Are experimental conditions represented using inconsistent terminology?
* Are there conflicting values across metadata sources?
* Can heterogeneous metadata files be transformed into a common schema?
* Can metadata issues be automatically identified before ingestion into a centralized data management system?

---

# Technology Stack

The final technology stack will be collaboratively determined during the BioHackathon. Naming the tools and stack early helps the team lead create useful roles and divide work realistically. It is fine to revise this section as the project develops.

Potential tools include:

### Programming Languages

* Python
* R

### Data Processing

* pandas
* tidyverse
* openpyxl
* readxl

### Validation

* Pydantic
* pytest
* Custom schema validation workflows

### Reproducibility

* Conda
* Git/GitHub
* Containerization (if appropriate)

### Data Management

* LabKey-compatible metadata structures
* Controlled vocabularies and ontologies

---

# Data

The project will use approved, de-identified legacy sequencing metadata provided by collaborating St. Jude research groups.

These datasets were selected because they represent real-world metadata challenges, including:


## Example R harmonization workflow

The repository includes a documented [HARTWELL metadata-standardization script](scripts/HARTWELL_standardization_2026-09-18_v14.R) for the example workbook [dataset/HARTWELL_database_Master_2025.xlsx](dataset/HARTWELL_database_Master_2025.xlsx). See [the usage guide](docs/hartwell-standardization.md) for dependencies, execution, safeguards, and limitations.

* Inconsistent formatting
* Variable naming conventions
* Missing values
* Human data entry errors
* Heterogeneous metadata structures

Potentially confidential or identifying information will be removed prior to use by the broader hackathon team.

---

# What Success Looks Like

By the end of the BioHackathon, success would mean demonstrating an end-to-end workflow capable of:

```text
Messy Legacy Metadata
        ↓
Automated Ingestion
        ↓
Validation & Error Detection
        ↓
Metadata Harmonization
        ↓
Standardized Output
        ↓
Ready for Downstream Integration
```

Even partial automation of this process could substantially reduce manual metadata curation while improving consistency, reproducibility, and long-term data usability.

---

# Why This Matters

High-quality metadata is essential for making scientific data discoverable, interpretable, reusable, and reproducible.

As sequencing datasets continue to accumulate, institutions face increasing challenges in managing historical data generated across changing technologies and standards. Developing reusable workflows for metadata harmonization can help preserve the long-term value of these datasets and reduce the burden of manual data curation.

While this project is motivated by an institutional need to organize legacy sequencing metadata, the underlying challenge is broadly applicable to laboratories and research institutions managing historical omics datasets.

---

# Team

**Team 11 — St. Jude BioHackathon 2026**

**Team lead:** Dr. Cody Alexander Ramirez
**GitHub handle:** CodyRamirez 

Team members and roles will be added here.
- **Team members and roles:** [Link to `project-management/team.md`]

---

# Getting Started

Instructions for setting up the development environment will be added prior to the BioHackathon.

The project will aim to provide a reproducible environment that allows contributors to work locally or within the shared BioHackathon development environment.

Expected setup:

```bash
git clone https://github.com/stjude-biohackathon/KIDS26-Team11.git
cd KIDS26-Team11
```

---

# Project Status

🚧 **Prototype under active development during St. Jude BioHackathon 2026**

This repository represents an experimental prototype developed during a collaborative hackathon. The project architecture, technology stack, and implementation details may evolve rapidly as the team explores potential solutions.





## Vision and Mission

- **Vision:** [Describe the change, insight, or capability you hope this project supports.]
- **Mission:** [Describe what the team will do during the biohackathon to move toward that vision.]


## Roadmap and Milestones

| When | Focus | Expected outcome |
| --- | --- | --- |
| Day 1 | Agree on the question, inputs, stack, roles, and first tasks | A shared plan and a first small change in the repository |
| Day 2 | Build, test, and compare approaches | A working result or clear evidence about what does not work |
| Day 3 | Stabilize, document, and present | A demo or handoff with methods, limitations, and next steps |

The goal is not a perfect production system. The goal is a clear, honest, useful result that the team can explain and others can build on.


