-- ============================================================
-- PMS Data Quality Checks
-- All core tables contain exact-duplicate rows (2:1 ratio) —
-- every query below dedupes with DISTINCT ON (id) before use.
-- ============================================================

-- ------------------------------------------------------------
-- 0. Baseline: row counts vs distinct IDs (confirms dup ratio)
-- ------------------------------------------------------------
SELECT 'tasks_task' AS table_name, COUNT(*) AS raw_rows, COUNT(DISTINCT id) AS distinct_ids FROM tasks_task
UNION ALL SELECT 'tasks_sub_task', COUNT(*), COUNT(DISTINCT id) FROM tasks_sub_task
UNION ALL SELECT 'tasks_goal', COUNT(*), COUNT(DISTINCT id) FROM tasks_goal
UNION ALL SELECT 'tasks_ksi', COUNT(*), COUNT(DISTINCT id) FROM tasks_ksi
UNION ALL SELECT 'tasks_milestone', COUNT(*), COUNT(DISTINCT id) FROM tasks_milestone
UNION ALL SELECT 'tasks_kpi', COUNT(*), COUNT(DISTINCT id) FROM tasks_kpi
UNION ALL SELECT 'tasks_major_activity', COUNT(*), COUNT(DISTINCT id) FROM tasks_major_activity
UNION ALL SELECT 'basedata_department', COUNT(*), COUNT(DISTINCT id) FROM basedata_department
UNION ALL SELECT 'basedata_position', COUNT(*), COUNT(DISTINCT id) FROM basedata_position
UNION ALL SELECT 'users_user', COUNT(*), COUNT(DISTINCT id) FROM users_user;

-- confirm duplicates are exact clones, not conflicting versions
SELECT 'tasks_goal' AS table_name, COUNT(*) AS raw_rows, COUNT(DISTINCT t.*) AS distinct_rows FROM tasks_goal t
UNION ALL SELECT 'tasks_kpi', COUNT(*), COUNT(DISTINCT t.*) FROM tasks_kpi t
UNION ALL SELECT 'tasks_major_activity', COUNT(*), COUNT(DISTINCT t.*) FROM tasks_major_activity t
UNION ALL SELECT 'basedata_department', COUNT(*), COUNT(DISTINCT t.*) FROM basedata_department t
UNION ALL SELECT 'basedata_position', COUNT(*), COUNT(DISTINCT t.*) FROM basedata_position t;


-- ------------------------------------------------------------
-- 7.1 Missing Assignments
-- ------------------------------------------------------------

-- Tasks without a position
SELECT COUNT(*) AS tasks_without_position
FROM (SELECT DISTINCT ON (id) * FROM tasks_task) t
WHERE t.position_id IS NULL;
-- Result: 664 (4.8% of 13,895)

-- Positions without users
SELECT COUNT(*) AS positions_without_users
FROM (SELECT DISTINCT ON (id) * FROM basedata_position) p
WHERE p.user_id IS NULL;

-- Tasks assigned to inactive/deactivated users
WITH t AS (SELECT DISTINCT ON (id) * FROM tasks_task),
     p AS (SELECT DISTINCT ON (id) * FROM basedata_position),
     u AS (SELECT DISTINCT ON (id) * FROM users_user)
SELECT COUNT(*) AS tasks_assigned_to_inactive_users
FROM t
JOIN p ON t.position_id = p.id
JOIN u ON p.user_id = u.id
WHERE u.is_active = FALSE;
-- Result: 0

-- Users without a valid current position
WITH u AS (SELECT DISTINCT ON (id) * FROM users_user),
     p AS (SELECT DISTINCT ON (id) * FROM basedata_position)
SELECT COUNT(*) AS users_without_valid_position
FROM u
WHERE u.current_position_id IS NULL
   OR u.current_position_id NOT IN (SELECT id FROM p);


-- ------------------------------------------------------------
-- 7.2 Invalid Dates
-- ------------------------------------------------------------
WITH t AS (SELECT DISTINCT ON (id) * FROM tasks_task)
SELECT
    SUM(CASE WHEN end_date < start_date THEN 1 ELSE 0 END) AS end_before_start,
    SUM(CASE WHEN actual_end_date < actual_start_date THEN 1 ELSE 0 END) AS actual_end_before_actual_start,
    SUM(CASE WHEN actual_end_date < start_date THEN 1 ELSE 0 END) AS actual_end_before_planned_start,
    SUM(CASE WHEN status = 'completed' AND actual_end_date IS NULL THEN 1 ELSE 0 END) AS completed_no_end_date,
    SUM(CASE WHEN status != 'completed' AND actual_end_date IS NOT NULL THEN 1 ELSE 0 END) AS incomplete_with_end_date
FROM t;
-- Result: end_before_start=2, actual_end_before_actual_start=1, actual_end_before_planned_start=27,
--         completed_no_end_date=5658, incomplete_with_end_date=16


-- ------------------------------------------------------------
-- 7.3 Overdue Consistency — independent overdue label vs stored field
-- ------------------------------------------------------------
WITH t AS (SELECT DISTINCT ON (id) * FROM tasks_task),
calc AS (
    SELECT
        id, status, is_overdue AS stored_overdue, end_date, actual_end_date, updated_date,
        CASE
            WHEN status = 'completed' AND actual_end_date IS NOT NULL THEN actual_end_date > end_date
            WHEN status = 'completed' AND actual_end_date IS NULL THEN updated_date::date > end_date
            WHEN status != 'completed' THEN end_date < CURRENT_DATE
            ELSE NULL
        END AS calculated_overdue
    FROM t
)
SELECT
    COUNT(*) AS total_tasks,
    SUM(CASE WHEN stored_overdue = TRUE  AND calculated_overdue = FALSE THEN 1 ELSE 0 END) AS stored_true_calc_false,
    SUM(CASE WHEN stored_overdue = FALSE AND calculated_overdue = TRUE  THEN 1 ELSE 0 END) AS stored_false_calc_true,
    SUM(CASE WHEN stored_overdue = calculated_overdue THEN 1 ELSE 0 END) AS agree,
    SUM(CASE WHEN calculated_overdue IS TRUE THEN 1 ELSE 0 END) AS calc_overdue_total,
    SUM(CASE WHEN stored_overdue IS TRUE THEN 1 ELSE 0 END) AS stored_overdue_total
FROM calc;
-- Result: total=13895, stored_true_calc_false=75, stored_false_calc_true=4829,
--         agree=8991, calc_overdue=7168 (51.6%), stored_overdue=2414 (17.4%)
-- --> 35.3% of tasks have an incorrect stored is_overdue value. Never use stored field as target.

-- Break down by whether the updated_date fallback was used (confirms mismatch isn't just an artifact of the fallback)
WITH t AS (SELECT DISTINCT ON (id) * FROM tasks_task),
calc AS (
    SELECT
        id, status, is_overdue AS stored_overdue, end_date, actual_end_date, updated_date,
        CASE WHEN actual_end_date IS NULL AND status = 'completed' THEN 'fallback_used'
             ELSE 'real_date' END AS date_source,
        CASE
            WHEN status = 'completed' AND actual_end_date IS NOT NULL THEN actual_end_date > end_date
            WHEN status = 'completed' AND actual_end_date IS NULL THEN updated_date::date > end_date
            WHEN status != 'completed' THEN end_date < CURRENT_DATE
            ELSE NULL
        END AS calculated_overdue
    FROM t
)
SELECT date_source, COUNT(*) AS total,
       SUM(CASE WHEN calculated_overdue THEN 1 ELSE 0 END) AS calc_overdue,
       SUM(CASE WHEN stored_overdue = TRUE  AND calculated_overdue = FALSE THEN 1 ELSE 0 END) AS mismatch_stored_true,
       SUM(CASE WHEN stored_overdue = FALSE AND calculated_overdue = TRUE  THEN 1 ELSE 0 END) AS mismatch_calc_true
FROM calc
GROUP BY date_source;


-- ------------------------------------------------------------
-- 7.4 Department Consistency
-- ------------------------------------------------------------

-- Task department vs position's department
WITH clean_task AS (SELECT DISTINCT ON (id) * FROM tasks_task),
     clean_position AS (SELECT DISTINCT ON (id) * FROM basedata_position)
SELECT
    COUNT(*) AS total_tasks,
    SUM(CASE WHEN t.department_id IS NOT NULL
              AND t.department_id != p.department_id THEN 1 ELSE 0 END) AS conflicting_dept,
    SUM(CASE WHEN t.department_id IS NULL THEN 1 ELSE 0 END) AS task_dept_null,
    SUM(CASE WHEN p.department_id IS NULL THEN 1 ELSE 0 END) AS position_dept_null
FROM clean_task t
LEFT JOIN clean_position p ON t.position_id = p.id;
-- Result: total=13895, conflicting_dept=31 (out of ~1,493 where task.department_id populated),
--         task_dept_null=12402 (89.3%), position_dept_null=664
-- Decision: use position's department as authoritative (see analytical_dataset.sql)

-- Invalid FK references (task -> department, position -> department)
WITH t AS (SELECT DISTINCT ON (id) * FROM tasks_task),
     d AS (SELECT DISTINCT ON (id) * FROM basedata_department),
     p AS (SELECT DISTINCT ON (id) * FROM basedata_position)
SELECT
    (SELECT COUNT(*) FROM t WHERE department_id IS NOT NULL
        AND department_id NOT IN (SELECT id FROM d)) AS task_invalid_dept,
    (SELECT COUNT(*) FROM p WHERE department_id IS NOT NULL
        AND department_id NOT IN (SELECT id FROM d)) AS position_invalid_dept;
-- Result: both 0 (clean)


-- ------------------------------------------------------------
-- 7.5 Parent-Child Consistency
-- ------------------------------------------------------------
WITH t AS (SELECT DISTINCT ON (id) * FROM tasks_task),
     st AS (SELECT DISTINCT ON (id) * FROM tasks_sub_task),
     ma AS (SELECT DISTINCT ON (id) * FROM tasks_major_activity)
SELECT
    (SELECT COUNT(DISTINCT t.id) FROM t
     JOIN st ON st.task_id = t.id
     WHERE t.status = 'completed' AND st.status != 'completed') AS completed_task_incomplete_subtasks,
    (SELECT COUNT(*) FROM st
     WHERE st.task_id IS NOT NULL AND st.task_id NOT IN (SELECT id FROM t)) AS orphaned_subtasks,
    (SELECT COUNT(*) FROM st
     JOIN t ON st.task_id = t.id
     WHERE st.start_date < t.start_date OR st.end_date > t.end_date) AS subtask_outside_parent_range,
    (SELECT COUNT(*) FROM t
     WHERE t.major_activity_id IS NULL
        OR t.major_activity_id NOT IN (SELECT id FROM ma)) AS task_invalid_major_activity;
-- Result: completed_task_incomplete_subtasks=138, orphaned_subtasks=0,
--         subtask_outside_parent_range=40, task_invalid_major_activity=0


-- ------------------------------------------------------------
-- 7.6 Duplicate Records — confirm which joins fan out task rows
-- ------------------------------------------------------------

-- Example: joining task -> position without dedup inflates row count 2x
SELECT COUNT(*) AS row_count_no_dedup
FROM tasks_task t
LEFT JOIN basedata_position p ON t.position_id = p.id;
-- Result: 27126 (vs 13895 distinct tasks) — confirms 2:1 duplication risk on every join