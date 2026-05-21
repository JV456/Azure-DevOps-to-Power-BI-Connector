
# Metrices — Power Query (M) Metrics Data Extraction

## Purpose

This folder contains Power Query M code used to extract and transform metrics for use in Power BI. 

> These metrics data extraction codes can be considered for use in production-level team data analysis and reporting for managers and stakeholders. They provide valuable insights into team performance, productivity, and whether organizational expectations and objectives are being achieved.

> All of these metric examples can also be utilized to demonstrate Business Intelligence dashboards in a real-world organizational environment, supporting data-driven decision-making and performance evaluation.

## Files

- `TestCoverage.m` — Extracts test-coverage metrics and reshapes them for analysis.
- `UnitTestCodeCoverage.m` — Detailed unit test coverage metrics (by project/module).
- `TestAutomationCoverage.m` — Metrics about test automation coverage and automation rate.
- `DefectAcceptance.m` — Defect acceptance (Bug severity analyzer)
- `SayDoRatio.m` — Say/Do ratio (planned vs completed work) measurements.

## Usage

1. Open Power BI Desktop (Get Data -> From Other Sources -> Blank Query).
2. In Power BI: `Home` → `Get Data` → `Blank Query` → `Advanced Editor`.
3. Open the `TestCoverage.m` file or other file in a text editor and copy its contents (or drag/rename to `TestCoverage`).
4. Paste the M code into the Advanced Editor and click `Done` to run the query and load the resulting table.

## Contact

If you need changes or discover issues with the extraction logic, reach out to me.
