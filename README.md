# PMS Intelligence and Overdue Work Risk Analysis

AI Residency Grouping Challenge — July 2026
Individual assessment: SQL, data quality, analytical dataset design, KPI reporting, feature engineering, and a classical ML model predicting overdue task risk in a Performance Management System (PMS).

## Business Questions

1. Can PMS data be used to identify active tasks likely to become overdue before their deadlines pass?
2. Can the existing PMS database support fair and reliable performance reporting at organizational, departmental, position, and employee levels?

## Repository Structure

```
pms-residency-assessment/
├── README.md
├── requirements.txt
├── sql/
│   ├── data_quality_checks.sql       # Profiling + all 6 required quality checks
│   ├── analytical_dataset.sql        # One-row-per-task dataset, all joins documented
│   └── performance_metrics.sql       # Org / department / position KPIs
├── notebooks/
│   └── pms_analysis_and_modeling.ipynb   # Full walkthrough, Parts 1-8
├── src/
│   ├── feature_engineering.py        # Leak-safe feature pipeline
│   ├── train.py                      # Time-based split, model training, evaluation
│   └── evaluate.py                   # Error analysis helpers
├── tests/
│   └── test_data_validation.py       # 6 automated validation tests
├── reports/
│   ├── technical_report.pdf
│   ├── management_summary.pdf
│   └── er_diagram.png
└── answers/
    └── reasoning_questions.md        # 8 required reasoning questions
```

## Setup

```bash
python -m venv venv
venv\Scripts\activate        # Windows
# source venv/bin/activate   # macOS/Linux

pip install -r requirements.txt
```

Update the database connection string in `notebooks/pms_analysis_and_modeling.ipynb` (Cell 1) and in `src/train.py` / `tests/test_data_validation.py` to match your local Postgres instance:

```python
engine = create_engine('postgresql://postgres:YOUR_PASSWORD@localhost:5432/tasktracker')
```

## Running the Analysis

1. **Notebook (recommended for full walkthrough):**
   Open `notebooks/pms_analysis_and_modeling.ipynb` and run all cells top to bottom. Covers schema exploration, data quality checks, analytical dataset construction, KPIs, EDA, feature engineering, model training, and error analysis.

2. **SQL only:**
   Run the three files in `sql/` directly against the PMS Postgres database in order: `data_quality_checks.sql` → `analytical_dataset.sql` → `performance_metrics.sql`.

3. **Model training as a script:**
   ```bash
   cd src
   python train.py
   ```

4. **Tests:**
   ```bash
   pytest tests/test_data_validation.py -v
   ```

## Key Findings (Summary)

- **PMS hierarchy:** Goal → KSI → Milestone → KPI → Major Activity → Task → Sub-task, with Department/Position/User on the organizational side. `tasks_task` is the correct central table for task-level analysis (13,895 distinct tasks, zero native duplicates).
- **Data quality:** 8 core tables contain exact duplicate rows at a 2:1 ratio — every join in this project dedupes with `DISTINCT ON (id)` first. The stored `is_overdue` field disagrees with an independently calculated label on 35.3% of tasks (stored: 17.4% overdue; calculated: 51.6% overdue) and should not be used as a reporting or modeling target on its own.
- **Analytical dataset:** One row per task (13,895 rows = 13,895 distinct `task_id`), with department sourced from the task's position (not the sparsely populated `task.department_id`) and an independently calculated overdue label.
- **KPIs:** Organizational completion rate is 94.3%, but on-time completion is only 50.6% — a large gap the raw completion rate conceals. Departmental overdue rates range from 11% to 83%.
- **Model:** GradientBoostingClassifier, time-based split (1,213 train / 315 test), ROC-AUC 0.676. The model's practical value is closer to a single early-warning rule ("has this task started by 7 days after its planned start?") than a nuanced multi-factor risk score — documented honestly in the technical report and error analysis rather than overstated.
- **Governance:** Per the assignment's stated principle, all analytics and predictions in this project are intended to support early intervention, planning, and resource allocation — not employee ranking, discipline, promotion, or compensation decisions.

Full detail on every finding, join decision, and modeling choice is in `reports/technical_report.pdf`, `reports/management_summary.pdf`, and `answers/reasoning_questions.md`.

