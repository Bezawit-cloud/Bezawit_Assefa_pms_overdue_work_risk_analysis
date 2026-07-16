"""
Automated validation tests on the analytical dataset.
Rubric requires at least 2 -- these five give you margin and double as
handy checks to run live during the technical defense.

Run with: pytest tests/
"""
import pandas as pd
import pytest

DATASET_PATH = "analytical_dataset.csv"  # export analytical_dataset.sql output here


@pytest.fixture(scope="module")
def df():
    return pd.read_csv(DATASET_PATH, parse_dates=[
        "planned_start_date", "planned_end_date",
        "actual_start_date", "actual_end_date",
    ])


def test_one_row_per_task(df):
    assert df["task_id"].is_unique, "Analytical dataset must have exactly one row per task"


def test_no_negative_planned_duration(df):
    bad = df[df["planned_end_date"] < df["planned_start_date"]]
    assert bad.empty, f"{len(bad)} tasks have planned_end_date before planned_start_date"


def test_completed_tasks_have_completion_date(df):
    completed = df[df["status"] == "completed"]
    missing = completed[completed["actual_end_date"].isna()]
    assert missing.empty, f"{len(missing)} completed tasks are missing actual_end_date"


def test_calculated_overdue_is_boolean(df):
    assert df["calculated_overdue"].dropna().isin([True, False]).all()


def test_subtask_completion_pct_in_range(df):
    pct = df["subtask_completion_pct"].dropna()
    assert ((pct >= 0) & (pct <= 1)).all(), "subtask_completion_pct must be between 0 and 1"
