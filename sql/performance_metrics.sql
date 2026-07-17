-- ============================================================
-- PMS Performance Indicators
-- Built on top of the analytical dataset (analytical_dataset.sql).
-- Run analytical_dataset.sql as a CTE/view first, or materialize it, then use below.
-- ============================================================

-- ------------------------------------------------------------
-- 9.1 Organizational Indicators
-- ------------------------------------------------------------
WITH analytical AS (
    -- paste analytical_dataset.sql query here, or reference a materialized view/table
    SELECT * FROM analytical_dataset  -- placeholder table/view name
)
SELECT
    COUNT(*) AS total_tasks,
    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_tasks,
    SUM(CASE WHEN status != 'completed' THEN 1 ELSE 0 END) AS active_tasks,
    SUM(CASE WHEN calculated_overdue THEN 1 ELSE 0 END) AS overdue_tasks,
    SUM(CASE WHEN is_planned THEN 1 ELSE 0 END) AS planned_tasks,
    SUM(CASE WHEN NOT is_planned THEN 1 ELSE 0 END) AS unplanned_tasks,
    ROUND(100.0 * SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) / COUNT(*), 1) AS completion_rate,
    ROUND(100.0 * SUM(CASE WHEN status = 'completed' AND NOT calculated_overdue THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END), 0), 1) AS on_time_completion_rate,
    ROUND(100.0 * SUM(CASE WHEN stored_overdue IS DISTINCT FROM calculated_overdue THEN 1 ELSE 0 END)
        / COUNT(*), 1) AS pct_incorrect_stored_overdue
FROM analytical;

-- Average delay in days (completed + late only)
WITH analytical AS (SELECT * FROM analytical_dataset)
SELECT ROUND(AVG(actual_end_date - planned_end_date), 1) AS avg_delay_days
FROM analytical
WHERE status = 'completed'
  AND actual_end_date IS NOT NULL
  AND calculated_overdue = TRUE;


-- ------------------------------------------------------------
-- 9.2 Department Indicators
-- ------------------------------------------------------------
WITH analytical AS (SELECT * FROM analytical_dataset)
SELECT
    department_name,
    COUNT(*) AS total_tasks,
    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_tasks,
    SUM(CASE WHEN status != 'completed' THEN 1 ELSE 0 END) AS active_tasks,
    SUM(CASE WHEN calculated_overdue THEN 1 ELSE 0 END) AS overdue_tasks,
    ROUND(100.0 * SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) / COUNT(*), 1) AS completion_rate,
    ROUND(100.0 * SUM(CASE WHEN calculated_overdue THEN 1 ELSE 0 END) / COUNT(*), 1) AS overdue_rate,
    ROUND(100.0 * SUM(CASE WHEN status = 'completed' AND NOT calculated_overdue THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END), 0), 1) AS on_time_completion_rate,
    ROUND(100.0 * SUM(CASE WHEN NOT is_planned THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_unplanned
FROM analytical
WHERE department_name IS NOT NULL
GROUP BY department_name
ORDER BY overdue_rate DESC;

-- Average delay by department
WITH analytical AS (SELECT * FROM analytical_dataset)
SELECT
    department_name,
    ROUND(AVG(actual_end_date - planned_end_date), 1) AS avg_delay_days
FROM analytical
WHERE status = 'completed' AND actual_end_date IS NOT NULL AND calculated_overdue = TRUE
GROUP BY department_name
ORDER BY avg_delay_days DESC;


-- ------------------------------------------------------------
-- 9.3 Position/Employee Indicators
-- NOTE: employee names must not appear in public-facing reports (Part 10 requirement).
-- Aggregate by position_name for shareable output; join to employee_id only for internal use.
-- ------------------------------------------------------------
WITH analytical AS (SELECT * FROM analytical_dataset)
SELECT
    position_name,
    COUNT(*) AS assigned_tasks,
    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_tasks,
    SUM(CASE WHEN status != 'completed' THEN 1 ELSE 0 END) AS active_tasks,
    SUM(CASE WHEN calculated_overdue THEN 1 ELSE 0 END) AS overdue_tasks,
    ROUND(100.0 * SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) / COUNT(*), 1) AS completion_rate,
    ROUND(100.0 * SUM(CASE WHEN status = 'completed' AND NOT calculated_overdue THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END), 0), 1) AS on_time_completion_rate,
    SUM(task_weight) AS total_assigned_weight
FROM analytical
WHERE position_name IS NOT NULL
GROUP BY position_name
ORDER BY assigned_tasks DESC;

-- Note: these indicators should NOT be used alone to rank employees/positions —
-- task volume and weight vary enormously by role, department context isn't controlled
-- for, and cross-department dependencies can cause delays outside an individual's
-- control (see Part 4 write-up and reasoning Q8).