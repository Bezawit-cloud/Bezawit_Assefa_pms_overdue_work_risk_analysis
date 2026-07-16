"""
Feature engineering for overdue-risk prediction.

Every feature must be computable using ONLY information available
at PREDICTION_POINT (defined in train.py / the notebook). If a column
is only known after the task closes (actual_end_date, is_overdue,
final status, etc.) it CANNOT be a feature -- that's leakage.

For each feature function below, document (in the docstring or a
companion table in the report):
  1. Business meaning
  2. Calculation method
  3. Source table(s)
  4. Availability at prediction time (yes/no + why)
  5. Data leakage risk (none / low / high + why)
  6. Missing-value handling
"""
import pandas as pd


def add_planned_duration(df: pd.DataFrame) -> pd.DataFrame:
    """Planned task duration in days = planned_end_date - planned_start_date.
    Available at creation time. No leakage risk."""
    df = df.copy()
    df["planned_duration_days"] = (
        pd.to_datetime(df["planned_end_date"]) - pd.to_datetime(df["planned_start_date"])
    ).dt.days
    return df


def add_days_remaining(df: pd.DataFrame, as_of_date: pd.Timestamp) -> pd.DataFrame:
    """Days between as_of_date (the prediction point) and planned_end_date.
    Must use the PREDICTION POINT, not today's date, to avoid leakage
    when building historical training examples."""
    df = df.copy()
    df["days_remaining_at_prediction"] = (
        pd.to_datetime(df["planned_end_date"]) - as_of_date
    ).dt.days
    return df


def add_started_late(df: pd.DataFrame) -> pd.DataFrame:
    """Whether the task's actual_start_date is after planned_start_date.
    CAUTION: only valid as a feature if actual_start_date is known by the
    prediction point (e.g. prediction point is after the task started).
    If predicting at creation time, this feature is NOT available -- drop it."""
    df = df.copy()
    df["started_late"] = (
        pd.to_datetime(df["actual_start_date"]) > pd.to_datetime(df["planned_start_date"])
    )
    return df


def add_revisions_before_prediction(df: pd.DataFrame, history_df: pd.DataFrame, as_of_date: pd.Timestamp) -> pd.DataFrame:
    """Count of history rows for the task with change_date <= as_of_date.
    This is the safe way to use history: filter by prediction point, not
    by total revisions over the task's full life (which would leak future info)."""
    counts = (
        history_df[history_df["change_date"] <= as_of_date]
        .groupby("task_id")
        .size()
        .rename("num_revisions_before_prediction")
    )
    return df.merge(counts, how="left", left_on="task_id", right_index=True).fillna(
        {"num_revisions_before_prediction": 0}
    )


# TODO: add_department_historical_overdue_rate, add_employee_active_workload,
# add_cross_department_flag, add_subtask_progress_at_prediction, etc.
# Aim for 6+ total, each leakage-checked against the chosen prediction point.
