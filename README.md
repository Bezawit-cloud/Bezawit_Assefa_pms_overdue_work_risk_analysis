# PMS Intelligence and Overdue Work Risk Analysis

## Overview
[1-2 paragraphs: what this repo does, the two business questions it answers]

## Repo structure
- `sql/` — data quality checks, analytical dataset build, performance metrics
- `notebooks/` — main EDA + modeling notebook
- `src/` — reusable Python (feature engineering, training, evaluation)
- `tests/` — automated validation tests on the analytical dataset
- `reports/` — technical report, management summary, ER diagram
- `answers/` — the 8 reasoning questions

## How to reproduce
1. `pip install -r requirements.txt`
2. Run SQL scripts in order: `data_quality_checks.sql` → `analytical_dataset.sql` → `performance_metrics.sql`
3. Open `notebooks/pms_analysis_and_modeling.ipynb` and run top to bottom
4. `pytest tests/`

## Key assumptions
[Document every assumption here as you make it — schema conflicts, department
selection logic, how multiple positions/history records were resolved, etc.
The grading rubric explicitly checks "clarity of documented assumptions."]

## AI tool usage disclosure
| Tool | Purpose | What it supported | How output was validated | Modifications made | Errors/limitations found |
|---|---|---|---|---|---|
| e.g. Claude | SQL drafting | dedup logic in analytical_dataset.sql | ran row counts before/after, manually checked 10 sample tasks | rewrote join order | initial version double-counted cross-dept tasks |

## Progress checklist
- [ ] ER diagram + 6 schema questions answered
- [ ] Table profiling (rows, cols, PK, FKs, date range, missing %, orphans)
- [ ] 6+ data quality findings (with impact + recommended action)
- [ ] Analytical dataset: exactly one row per task, dedup documented
- [ ] Independent overdue label calculated + compared to stored `is_overdue`
- [ ] Org / department / employee KPIs
- [ ] 4+ visualizations with title, axes, units, interpretation, business implication
- [ ] 6+ engineered features, each with leakage risk assessed
- [ ] Prediction point chosen and justified
- [ ] One classical ML model, justified
- [ ] Time-based train/test split (not random) — explain why
- [ ] Precision, recall, F1, confusion matrix, ROC/PR-AUC reported
- [ ] 2+ thresholds compared, one recommended
- [ ] 3 false positives + 3 false negatives reviewed, 2+ improvements suggested
- [ ] 8 reasoning questions answered
- [ ] One-page management summary (includes the "not for HR decisions" statement)
- [ ] 2+ automated validation tests passing
- [ ] AI usage disclosed above
