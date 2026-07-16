"""
Evaluate the trained overdue-risk model.

Report precision, recall, F1, confusion matrix, ROC-AUC or PR-AUC.
Accuracy alone is NOT sufficient (dataset is likely imbalanced --
most tasks are probably on-time, so a model that predicts "on time"
for everything can have high accuracy but zero recall for overdue tasks).
"""
from sklearn.metrics import (
    precision_score, recall_score, f1_score, confusion_matrix,
    roc_auc_score, average_precision_score, classification_report,
)


def evaluate_at_threshold(y_true, y_proba, threshold: float) -> dict:
    y_pred = (y_proba >= threshold).astype(int)
    tn, fp, fn, tp = confusion_matrix(y_true, y_pred).ravel()
    return {
        "threshold": threshold,
        "precision": precision_score(y_true, y_pred, zero_division=0),
        "recall": recall_score(y_true, y_pred, zero_division=0),
        "f1": f1_score(y_true, y_pred, zero_division=0),
        "true_positives": int(tp),
        "false_positives": int(fp),
        "false_negatives": int(fn),
        "true_negatives": int(tn),
        # false positives = on-time tasks flagged -> review workload cost
        # false negatives = missed overdue tasks -> the thing you most want to avoid
    }


def compare_thresholds(y_true, y_proba, thresholds=(0.40, 0.60)):
    return [evaluate_at_threshold(y_true, y_proba, t) for t in thresholds]


if __name__ == "__main__":
    # y_true, y_proba = ...
    # print(roc_auc_score(y_true, y_proba))
    # print(average_precision_score(y_true, y_proba))
    # for row in compare_thresholds(y_true, y_proba):
    #     print(row)
    pass
