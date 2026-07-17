# PMS Intelligence and Overdue Work Risk Analysis — Reasoning Questions

## Question 1
**The database already contains `is_overdue`. Why should a separate overdue label be calculated?**

Because the stored field is unreliable. Comparing it against an independently calculated label showed 35.3% of tasks disagree — the stored field says 17.4% of tasks are overdue org-wide, while the calculated label puts it at 51.6%, a 3x understatement. The mismatch persists even after separating out cases where a fallback date had to be used, so it isn't just a side effect of missing `actual_end_date`. Reporting or modeling on the stored field alone would badly understate the organization's real overdue risk.

## Question 2
**Why should `actual_end_date` not be used to predict whether an active task will become overdue?**

`actual_end_date` is only populated once a task is finished — it's an outcome, not a predictor. Using it as a model input would mean the model only "knows" a task is late because the task has already ended late, which is circular and impossible to replicate at actual prediction time (when a task is still active, `actual_end_date` is null by definition for the very tasks we're trying to predict). This is a textbook data-leakage feature.

## Question 3
**A task is marked completed, but some of its sub-tasks remain incomplete. How should this inconsistency be handled?**

This pattern was found in 138 tasks. It should be flagged, not silently corrected — there are multiple plausible explanations (subtasks abandoned as out-of-scope, a status update that didn't cascade, or genuinely incomplete work marked done in error), and each implies a different fix. The record should be retained in the analytical dataset with a flag column (e.g. `has_incomplete_subtasks_at_completion`) rather than excluded, since excluding it would hide a real process issue, and rather than auto-correcting it, since we can't know from the data alone which interpretation is right.

## Question 4
**A task has `is_overdue = false`, but its deadline has passed and it is still active. How should the task be classified?**

It should be classified as overdue using the calculated label. This is exactly the case the independent overdue calculation was built for: for any non-completed task, `calculated_overdue = end_date < CURRENT_DATE`. The stored flag likely wasn't updated after the deadline passed — this is one of the concrete cases contributing to the 4,829 `stored_false / calculated_true` mismatches found in the overdue consistency check.

## Question 5
**A task's department differs from the department connected through its position. Which department should be used for reporting?**

The position's department should be used. `task.department_id` is null on 89.3% of tasks (12,402 of 13,895), while the position-derived department is far more complete. Where both fields are populated, they agree in all but 31 cases — so the position's department isn't just more complete, it's also consistent with the task's own field in the vast majority of cases where a comparison is even possible. Those 31 disagreements are flagged separately as a data-quality issue rather than silently overridden.

## Question 6
**A KSI is linked to multiple goals. How can this create duplicate task records after joining tables?**

If a KSI has more than one associated goal (via the `tasks_ksi_goals` bridge table) and the join isn't deduplicated, each task under that KSI gets one output row per linked goal — a single task can appear 2, 3, or more times purely because of how many goals its KSI happens to touch, not because of anything about the task itself. This is the same fan-out mechanism confirmed elsewhere in the schema (e.g. the task-to-position join inflating 13,895 rows to 27,126 without dedup). The fix applied in the analytical dataset was to pick one goal per KSI (`DISTINCT ON (ksi_id)` on the bridge table) rather than let every linked goal multiply the task row.

## Question 7
**A model has high accuracy but identifies only a small percentage of overdue tasks. Is the model useful? Explain.**

Not necessarily — accuracy alone can be a misleading metric when the target is imbalanced. In this project's own modeling population, 68.7% of eligible tasks were overdue, so a model that always predicted "overdue" would already score ~69% accuracy while identifying 100% of overdue tasks trivially — while a model that predicts "overdue" for only a few cases could still post a high accuracy score by correctly calling the (smaller) on-time class, all while missing most of the overdue tasks that actually matter to catch. High accuracy paired with low recall on the overdue class means the model is failing at its actual job. Recall, precision, and ROC-AUC are needed to judge whether a model is genuinely useful, not accuracy in isolation.

The reverse failure mode showed up directly in this project too: the trained model achieved recall = 1.0 and looked excellent on paper, but its ROC-AUC was only 0.676 — a sign it had collapsed into one dominant, near-hard rule (`started_late_cat = unknown`, 95.7% of feature importance) rather than learning nuanced risk patterns. A model can look "useful" by one metric and be narrow or fragile by another; all the required metrics need to be read together.

## Question 8
**Why should overdue-risk predictions not be used as the sole basis for ranking or penalizing employees?**

Because the model captures whether a task is likely to run late, not whether an employee is underperforming — and several factors driving overdue risk are structural, not individual: task volume and weight vary enormously by role (position-level total assigned weight ranged from 0 to 15,910 in this data), department context isn't controlled for (overdue rates ranged from 11% to 83% by department), and cross-department dependencies can delay a task for reasons outside the assigned employee's control. The model's own dominant signal — whether a task had started by a fixed checkpoint — says nothing about employee effort or skill; a task might not have started because of upstream blockers, resourcing, or approval delays. Per the assignment's stated principle, this analysis is meant to support early intervention, planning, and resource allocation — not disciplinary action, promotion, termination, or compensation decisions.