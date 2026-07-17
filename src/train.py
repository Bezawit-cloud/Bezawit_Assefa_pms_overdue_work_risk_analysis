"""
Train and evaluate the overdue-risk classifier.
Time-based split (no random split — see Part 7 justification).
"""

import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.metrics import (
    precision_score, recall_score, f1_score, confusion_matrix, roc_auc_score, accuracy_score
)

from feature_engineering import (
    build_features, add_dept_historical_overdue_rate, FEATURE_COLUMNS_BASE, get_engine
)


def time_based_split(df, train_frac=0.8):
    """
    Sort by planned_start_date and split chronologically.
    A random split would let later tasks (with department/process patterns that hadn't
    happened yet) leak information into predictions for earlier tasks — unrealistic for
    how the model would actually be deployed.
    """
    df = df.sort_values('planned_start_date').reset_index(drop=True)
    split_idx = int(len(df) * train_frac)
    cutoff_date = df.iloc[split_idx]['planned_start_date']

    train = df[df['planned_start_date'] < cutoff_date].copy()
    test = df[df['planned_start_date'] >= cutoff_date].copy()
    return train, test, cutoff_date


def encode_started_late(train, test):
    """One-hot encode started_late_cat with a collision-safe prefix (NOT 'started' —
    that clashes with the pre-existing 'started_late' column name)."""
    train_dummies = pd.get_dummies(train['started_late_cat'], prefix='startcat')
    test_dummies = pd.get_dummies(test['started_late_cat'], prefix='startcat')
    test_dummies = test_dummies.reindex(columns=train_dummies.columns, fill_value=0)

    train = pd.concat([train.reset_index(drop=True), train_dummies.reset_index(drop=True)], axis=1)
    test = pd.concat([test.reset_index(drop=True), test_dummies.reset_index(drop=True)], axis=1)
    return train, test, list(train_dummies.columns)


def prep_features(train, test, feature_cols):
    for df in (train, test):
        df['is_planned'] = df['is_planned'].astype(int)
        df['is_cross_department'] = df['is_cross_department'].astype(int)
        df['employee_active_workload'] = df['employee_active_workload'].fillna(0)
        df['task_weight'] = df['task_weight'].fillna(df['task_weight'].median())

    X_train = train[feature_cols]
    y_train = train['calculated_overdue'].astype(int)
    X_test = test[feature_cols]
    y_test = test['calculated_overdue'].astype(int)
    return X_train, y_train, X_test, y_test


def train_model(X_train, y_train):
    """
    GradientBoostingClassifier chosen over logistic regression: department overdue rate,
    duration, and workload likely interact non-linearly. Sample-weighted for class
    imbalance (train population runs ~69%% overdue).
    """
    weight_ratio = (y_train == 0).sum() / (y_train == 1).sum()
    sample_weights = y_train.map({1: weight_ratio, 0: 1.0})

    model = GradientBoostingClassifier(random_state=42)
    model.fit(X_train, y_train, sample_weight=sample_weights)
    return model


def evaluate_at_threshold(y_test, proba, threshold):
    preds = (proba >= threshold).astype(int)
    cm = confusion_matrix(y_test, preds)
    tn, fp, fn, tp = cm.ravel()
    return {
        'threshold': threshold,
        'precision': round(precision_score(y_test, preds), 3),
        'recall': round(recall_score(y_test, preds), 3),
        'f1': round(f1_score(y_test, preds), 3),
        'accuracy': round(accuracy_score(y_test, preds), 3),
        'correctly_flagged_overdue': int(tp),
        'missed_overdue': int(fn),
        'on_time_flagged_incorrectly': int(fp),
        'review_workload': int(tp + fp),
    }


def run_pipeline(connection_string, analytical_df):
    engine = get_engine(connection_string)

    feat_df = build_features(engine, analytical_df)
    print(f"Eligible tasks: {len(feat_df)}")

    train, test, cutoff_date = time_based_split(feat_df)
    print(f"Train: {len(train)} (before {cutoff_date.date()}), Test: {len(test)}")

    train, test, started_late_cols = encode_started_late(train, test)
    train, test, global_rate = add_dept_historical_overdue_rate(train, test)

    feature_cols = FEATURE_COLUMNS_BASE + started_late_cols
    X_train, y_train, X_test, y_test = prep_features(train, test, feature_cols)

    model = train_model(X_train, y_train)
    proba = model.predict_proba(X_test)[:, 1]

    auc = roc_auc_score(y_test, proba)
    print(f"ROC-AUC: {round(auc, 3)}")

    thresholds = [0.10, 0.40, 0.60, 0.90]
    results = [evaluate_at_threshold(y_test, proba, t) for t in thresholds]
    threshold_df = pd.DataFrame(results)
    print(threshold_df.to_string(index=False))

    importances = pd.Series(model.feature_importances_, index=feature_cols).sort_values(ascending=False)
    print("\nFeature importances:")
    print(importances)

    return model, X_train, y_train, X_test, y_test, proba, test, threshold_df


if __name__ == "__main__":
    CONNECTION_STRING = "postgresql://postgres:YOUR_PASSWORD@localhost:5432/tasktracker"
    # analytical_df should be loaded/rebuilt here — e.g. from notebooks/analytical_dataset.csv
    analytical_df = pd.read_csv("../notebooks/analytical_dataset.csv")

    model, X_train, y_train, X_test, y_test, proba, test, threshold_df = run_pipeline(
        CONNECTION_STRING, analytical_df
    )