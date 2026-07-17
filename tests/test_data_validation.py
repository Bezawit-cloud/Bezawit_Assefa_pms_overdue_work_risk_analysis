"""
Automated validation tests for the PMS analytical dataset and overdue-risk model.
Run with: pytest tests/test_data_validation.py -v
"""

import pandas as pd
import pytest
from sqlalchemy import create_engine

CONNECTION_STRING = "postgresql://postgres:newpassword123@localhost:5432/tasktracker"


@pytest.fixture(scope="module")
def engine():
    return create_engine(CONNECTION_STRING)


@pytest.fixture(scope="module")
def analytical_df():
    """Loads the exported analytical dataset (from notebooks/analytical_dataset.csv)."""
    return pd.read_csv("notebooks/analytical_dataset.csv")


# ------------------------------------------------------------
# Test 1: One row per task — no duplication from many-to-many joins
# ------------------------------------------------------------
def test_analytical_dataset_has_one_row_per_task(analytical_df):
    total_rows = len(analytical_df)
    distinct_tasks = analytical_df['task_id'].nunique()
    assert total_rows == distinct_tasks, (
        f"Expected one row per task, but got {total_rows} rows for "
        f"{distinct_tasks} distinct task_ids. Likely cause: an undeduped join "
        f"(e.g. KSI-to-goal fan-out, or a joined table missing DISTINCT ON (id))."
    )


# ------------------------------------------------------------
# Test 2: calculated_overdue must never be null where it's computable
# (status = 'completed' with actual_end_date present, or status != 'completed')
# ------------------------------------------------------------
def test_calculated_overdue_not_null_where_computable(analytical_df):
    computable = analytical_df[
        (analytical_df['status'] != 'completed') |
        ((analytical_df['status'] == 'completed') & (analytical_df['actual_end_date'].notna())) |
        ((analytical_df['status'] == 'completed') & (analytical_df['updated_date'].notna()))
    ]
    nulls = computable['calculated_overdue'].isna().sum()
    assert nulls == 0, (
        f"{nulls} tasks have a computable overdue status but calculated_overdue is null. "
        f"Check the CASE logic for uncovered status/date combinations."
    )


# ------------------------------------------------------------
# Test 3: No task department_id conflicts silently overridden without a flag
# (every task with both task.department_id and position.department_id populated
#  should either match, or be explicitly identifiable as a known conflict)
# ------------------------------------------------------------
def test_department_source_is_consistent(engine):
    query = """
    WITH clean_task AS (SELECT DISTINCT ON (id) * FROM tasks_task),
         clean_position AS (SELECT DISTINCT ON (id) * FROM basedata_position)
    SELECT COUNT(*) AS conflicting_dept
    FROM clean_task t
    LEFT JOIN clean_position p ON t.position_id = p.id
    WHERE t.department_id IS NOT NULL
      AND p.department_id IS NOT NULL
      AND t.department_id != p.department_id
    """
    result = pd.read_sql(query, engine)
    conflicts = result['conflicting_dept'].iloc[0]
    # Known baseline from Part 2 profiling: 31 conflicts. This test guards against
    # that number silently growing (e.g. new bad data entering the source system)
    # without anyone noticing.
    assert conflicts <= 31, (
        f"Expected at most 31 known task/position department conflicts, found {conflicts}. "
        f"New conflicting records may have entered the system since the original profiling."
    )


# ------------------------------------------------------------
# Test 4: No orphaned sub-tasks (sub-task referencing a non-existent task)
# ------------------------------------------------------------
def test_no_orphaned_subtasks(engine):
    query = """
    WITH t AS (SELECT DISTINCT ON (id) * FROM tasks_task),
         st AS (SELECT DISTINCT ON (id) * FROM tasks_sub_task)
    SELECT COUNT(*) AS orphaned
    FROM st
    WHERE st.task_id IS NOT NULL
      AND st.task_id NOT IN (SELECT id FROM t)
    """
    result = pd.read_sql(query, engine)
    orphaned = result['orphaned'].iloc[0]
    assert orphaned == 0, f"Found {orphaned} sub-tasks referencing non-existent tasks."


# ------------------------------------------------------------
# Test 5: Feature engineering leak check — no feature uses actual_end_date directly
# (guards against a future edit accidentally reintroducing a leakage feature)
# ------------------------------------------------------------
def test_feature_columns_exclude_leakage_fields():
    from src.feature_engineering import FEATURE_COLUMNS_BASE

    leakage_fields = {'actual_end_date', 'is_overdue', 'stored_overdue', 'subtask_completion_pct'}
    overlap = leakage_fields.intersection(set(FEATURE_COLUMNS_BASE))
    assert not overlap, (
        f"Leakage field(s) found in FEATURE_COLUMNS_BASE: {overlap}. "
        f"These fields are only known after task completion or are the label being predicted."
    )


# ------------------------------------------------------------
# Test 6: Eligible population for ML matches expected filter logic
# (planned_end_date must be strictly after each task's own prediction_date)
# ------------------------------------------------------------
def test_eligible_population_has_runway_at_prediction_point(engine):
    from src.feature_engineering import build_eligible_population

    df = build_eligible_population(engine)
    violations = (df['planned_end_date'] <= df['prediction_date'].dt.date).sum()
    assert violations == 0, (
        f"{violations} tasks in the eligible population have no runway left at "
        f"their own prediction_date — filter logic is not being applied correctly."
    )
