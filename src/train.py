"""
Train a classical ML model to predict overdue risk for active tasks.

Steps:
1. Load the analytical dataset (from analytical_dataset.sql export).
2. Filter to tasks that were ACTIVE at the chosen prediction point.
3. Build features via feature_engineering.py (leakage-checked).
4. TIME-BASED split: e.g. train on tasks created/predicted before a cutoff
   date, test on tasks after it. Do NOT use train_test_split with
   shuffle=True / random_state -- that lets future tasks leak into training
   and inflates performance in a way that won't hold up in production.
5. Fit one classical model (see justification in the report / notebook --
   e.g. logistic regression for interpretability, or a tree ensemble if
   the relationship is non-linear and you have enough data).
6. Save the fitted model + the feature list used (for evaluate.py).
"""
import pandas as pd
from sklearn.linear_model import LogisticRegression
# from sklearn.ensemble import RandomForestClassifier  # alt option


PREDICTION_POINT = "seven_days_before_deadline"  # document the chosen point and why
TIME_SPLIT_CUTOFF = "2026-01-01"  # replace with an actual, justified cutoff date

FEATURE_COLUMNS = [
    # fill in once features are finalized in feature_engineering.py
]
TARGET_COLUMN = "calculated_overdue_at_prediction"


def time_based_split(df: pd.DataFrame, date_col: str, cutoff: str):
    train = df[df[date_col] < cutoff]
    test = df[df[date_col] >= cutoff]
    return train, test


def train_model(train_df: pd.DataFrame):
    X = train_df[FEATURE_COLUMNS]
    y = train_df[TARGET_COLUMN]
    model = LogisticRegression(max_iter=1000, class_weight="balanced")
    model.fit(X, y)
    return model


if __name__ == "__main__":
    # df = pd.read_csv("analytical_dataset.csv")
    # train_df, test_df = time_based_split(df, "prediction_date", TIME_SPLIT_CUTOFF)
    # model = train_model(train_df)
    # persist model + test_df for evaluate.py
    pass
