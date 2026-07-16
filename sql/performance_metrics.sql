-- ============================================================
-- PMS PERFORMANCE INDICATORS
-- Built on top of the analytical dataset (analytical_dataset.sql).
-- ============================================================

-- 9.1 ORGANIZATIONAL INDICATORS
-- total tasks, completed, active, overdue, planned, unplanned,
-- completion rate, on-time completion rate, avg delay (days),
-- % tasks with incorrect stored overdue value (is_overdue <> calculated_overdue)

-- 9.2 DEPARTMENT INDICATORS
-- same breakdown, GROUP BY department

-- 9.3 POSITION / EMPLOYEE INDICATORS
-- same breakdown, GROUP BY position or employee
-- NOTE: exclude employee names from any public-facing output (Part 5 requirement)
-- Remember to note in the report why these should not be used alone to rank people
-- (workload differences, task difficulty/weight differences, cross-dept dependencies,
-- small sample sizes per employee, etc.)
