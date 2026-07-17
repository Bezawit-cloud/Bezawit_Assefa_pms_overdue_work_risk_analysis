"""
Feature engineering for PMS overdue-risk prediction.
Prediction point: 7 days after planned_start_date.
All features are validated leak-safe as of that prediction point (see Part 6 documentation).
"""

import pandas as pd
from sqlalchemy import create_engine


def get_engine(connection_string):
    return create_engine(connection_string)


def build_eligible_population(engine):
    """
    Pull tasks and compute the prediction_date (7 days after planned start).
    Eligible population = tasks whose planned_end_date is after their own prediction_date
    (i.e. still had runway left at the checkpoint).
    """
    query = """
    WITH t AS (SELECT DISTINCT ON (id) * FROM tasks_task)
    SELECT
        id AS task_id,
        start_date AS planned_start_date,
        end_date AS planned_end_date,
        (start_date + INTERVAL '7 days') AS prediction_date,
        actual_start_date,
        actual_end_date,
        status,
        is_overdue AS stored_overdue,
        weight AS task_weight,
        is_planned,
        (derived_from_cross_department_assignment_id IS NOT NULL) AS is_cross_department,
        position_id,
        department_id,
        (end_date - start_date) AS planned_duration_days,
        created_date
    FROM t
    WHERE start_date IS NOT NULL AND end_date IS NOT NULL
    """
    df = pd.read_sql(query, engine)
    df['prediction_date'] = pd.to_datetime(df['prediction_date'])
    df['planned_start_date'] = pd.to_datetime(df['planned_start_date'])
    df['planned_end_date'] = pd.to_datetime(df['planned_end_date'])
    df['actual_start_date'] = pd.to_datetime(df['actual_start_date'], utc=True).dt.tz_localize(None)

    df = df[df['planned_end_date'] > df['prediction_date'].dt.date].copy()
    return df


def add_days_remaining(df):
    df['days_remaining_at_pred'] = (df['planned_end_date'] - df['prediction_date']).dt.days
    return df


def add_revision_count(df, engine):
    """Count task_history rows strictly before each task's prediction_date (leak-safe)."""
    query = "SELECT history_relation_id AS task_id, history_date FROM tasks_task_history"
    hist = pd.read_sql(query, engine)
    hist['history_date'] = pd.to_datetime(hist['history_date'], utc=True).dt.tz_localize(None)

    merged = hist.merge(df[['task_id', 'prediction_date']], on='task_id', how='inner')
    merged = merged[merged['history_date'] <= merged['prediction_date']]
    rev_counts = merged.groupby('task_id').size().rename('num_revisions_before_pred').reset_index()

    df = df.merge(rev_counts, on='task_id', how='left')
    df['num_revisions_before_pred'] = df['num_revisions_before_pred'].fillna(0)
    return df


def add_started_late_flag(df):
    """
    3 outcomes, not 2: late / on_time / unknown.
    unknown = task hadn't started (or start wasn't recorded) as of prediction_date —
    this must NOT be silently treated as "on time".
    """
    def flag(row):
        if pd.isna(row['actual_start_date']):
            return None
        if row['actual_start_date'] > row['prediction_date']:
            return None
        return row['actual_start_date'] > row['planned_start_date']

    df['started_late'] = df.apply(flag, axis=1)
    df['started_late_cat'] = df['started_late'].map({True: 'late', False: 'on_time'}).fillna('unknown')
    return df


def add_employee_workload(df, engine):
    """Count each employee's other active tasks as of the task's own prediction_date."""
    query = """
    WITH t AS (SELECT DISTINCT ON (id) * FROM tasks_task),
    p AS (SELECT DISTINCT ON (id) * FROM basedata_position)
    SELECT t.id AS task_id, t.position_id, p.user_id AS employee_id,
           t.start_date, t.end_date, t.status
    FROM t LEFT JOIN p ON t.position_id = p.id
    """
    all_tasks = pd.read_sql(query, engine)
    all_tasks['start_date'] = pd.to_datetime(all_tasks['start_date'])
    all_tasks['end_date'] = pd.to_datetime(all_tasks['end_date'])

    task_to_employee = all_tasks.set_index('task_id')['employee_id'].to_dict()

    workload = []
    for _, row in df.iterrows():
        emp_id = task_to_employee.get(row['task_id'])
        if pd.isna(emp_id):
            workload.append(None)
            continue
        pd_ = row['prediction_date']
        active_count = all_tasks[
            (all_tasks['employee_id'] == emp_id) &
            (all_tasks['task_id'] != row['task_id']) &
            (all_tasks['start_date'] <= pd_) &
            (all_tasks['end_date'] >= pd_) &
            (all_tasks['status'] != 'completed')
        ].shape[0]
        workload.append(active_count)

    df['employee_active_workload'] = workload
    return df


def add_calculated_overdue_target(df, analytical_df):
    """Merge the independently-calculated overdue label (built in Part 3) onto the feature set."""
    return df.merge(analytical_df[['task_id', 'calculated_overdue']], on='task_id', how='left')


def add_dept_historical_overdue_rate(train_df, test_df):
    """
    IMPORTANT: computed from TRAINING data only, then applied to both train and test.
    Must be called AFTER the train/test split — never on the full dataset first,
    or department overdue rates from the test period leak into training features.
    """
    dept_rate = (
        train_df.groupby('department_id')['calculated_overdue']
        .mean()
        .rename('dept_historical_overdue_rate')
        .reset_index()
    )
    global_rate = train_df['calculated_overdue'].mean()

    train_df = train_df.merge(dept_rate, on='department_id', how='left')
    test_df = test_df.merge(dept_rate, on='department_id', how='left')

    train_df['dept_historical_overdue_rate'] = train_df['dept_historical_overdue_rate'].fillna(global_rate)
    test_df['dept_historical_overdue_rate'] = test_df['dept_historical_overdue_rate'].fillna(global_rate)

    return train_df, test_df, global_rate


def build_features(engine, analytical_df):
    """Full pipeline: eligible population -> all features -> target attached. Returns one clean df."""
    df = build_eligible_population(engine)
    df = add_days_remaining(df)
    df = add_revision_count(df, engine)
    df = add_started_late_flag(df)
    df = add_employee_workload(df, engine)
    df = add_calculated_overdue_target(df, analytical_df)
    return df


FEATURE_COLUMNS_BASE = [
    'planned_duration_days',
    'days_remaining_at_pred',
    'task_weight',
    'is_planned',
    'is_cross_department',
    'num_revisions_before_pred',
    'dept_historical_overdue_rate',
    'employee_active_workload',
]
