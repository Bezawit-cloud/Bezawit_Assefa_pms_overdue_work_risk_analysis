-- ============================================================
-- DATA QUALITY CHECKS
-- Fill each section in. Keep each check as a standalone query
-- you can run independently during the technical defense.
-- ============================================================

-- ------------------------------------------------------------
-- 0. TABLE PROFILING
-- For each core table: row count, PK, FKs, date range, null %,
-- distinct-record count, orphaned FK count.
-- ------------------------------------------------------------
-- SELECT COUNT(*) AS row_count FROM tasks_task;
-- (repeat / adapt per table)


-- ------------------------------------------------------------
-- 7.1 MISSING ASSIGNMENTS
-- ------------------------------------------------------------
-- Tasks without positions
-- Positions without users
-- Tasks assigned to inactive/deactivated users
-- Users without valid current positions


-- ------------------------------------------------------------
-- 7.2 INVALID DATES
-- ------------------------------------------------------------
-- end_date < start_date
-- actual_end_date < actual_start_date
-- actual completion before task start
-- completed task with no actual_end_date
-- incomplete task WITH an actual_end_date


-- ------------------------------------------------------------
-- 7.3 OVERDUE CONSISTENCY
-- ------------------------------------------------------------
-- Build the independent overdue flag, e.g.:
-- CASE
--   WHEN status = 'completed' AND actual_end_date > planned_end_date THEN TRUE
--   WHEN status <> 'completed' AND planned_end_date < CURRENT_DATE THEN TRUE
--   ELSE FALSE
-- END AS calculated_overdue
--
-- Then compare against stored is_overdue:
-- - is_overdue = true but completed on time
-- - is_overdue = false but deadline passed and still incomplete
-- - completed without completion date
-- - incomplete with deadline already passed


-- ------------------------------------------------------------
-- 7.4 DEPARTMENT CONSISTENCY
-- ------------------------------------------------------------
-- task.department_id <> position.department_id
-- task references invalid department
-- position references invalid department


-- ------------------------------------------------------------
-- 7.5 PARENT-CHILD CONSISTENCY
-- ------------------------------------------------------------
-- Completed task with incomplete sub-tasks
-- Sub-task with invalid task_id
-- Child dates outside parent task timeline
-- Task without a valid major_activity


-- ------------------------------------------------------------
-- 7.6 DUPLICATE RECORDS
-- ------------------------------------------------------------
-- Duplicate task rows from: many-to-many joins, multiple positions,
-- multiple goals, multiple history versions, multiple supporting records.
-- e.g. GROUP BY task_id HAVING COUNT(*) > 1 after each join, to catch
-- which join introduces the fan-out.
