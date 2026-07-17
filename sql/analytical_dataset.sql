
-- ============================================================
-- TASK-LEVEL ANALYTICAL DATASET
-- One row per task. Verified: 13,895 rows = 13,895 distinct task_id.
-- ============================================================

-- ------------------------------------------------------------
-- JOIN DECISIONS (documented, as required by the assignment)
-- ------------------------------------------------------------
-- 1. DEDUPLICATION: Every core table except tasks_task and users_user
--    contains exact duplicate rows at a consistent 2:1 ratio (confirmed
--    via row-comparison in Part 2). Every table below is wrapped in
--    `SELECT DISTINCT ON (id) * FROM <table>` before joining, to prevent
--    row fan-out. This was tested incrementally: the full hierarchy join
--    (task -> major_activity -> kpi -> milestone -> ksi) stays at exactly
--    13,895 rows only because of this dedup step.
--
-- 2. DEPARTMENT SELECTION: tasks_task.department_id is populated on only
--    ~11% of tasks (89.3% missing). basedata_position.department_id
--    (reached via the task's position_id) is used as the authoritative
--    department, since it is far more complete. Where both exist, they
--    agree in all but 31 of ~1,493 cases (see Part 2, finding #4) --
--    those 31 conflicts are NOT silently overridden; they are captured
--    separately in the data quality report, not corrected here.
--
-- 3. MULTIPLE POSITIONS: users_user.current_position_id and
--    basedata_position.user_id both exist as a bidirectional link.
--    This dataset uses the task's own position_id (its direct FK) as
--    the position of record for that task, rather than the employee's
--    *current* position -- a task should reflect who held the position
--    when the task was assigned, not who holds it now.
--
-- 4. KSI -> GOAL (many-to-many): tasks_kpi has a direct (but 92.5% NULL)
--    goal_id field that bypasses the Milestone -> KSI chain. This dataset
--    does NOT use that direct field. Instead it follows the intended
--    hierarchy Goal -> KSI -> Milestone -> KPI, via tasks_ksi_goals (the
--    KSI-to-Goal bridge table). Since a KSI can link to multiple goals,
--    `DISTINCT ON (ksi_id)` picks a single (first) goal per KSI to
--    preserve one row per task. This is a documented simplification --
--    a KSI linked to >1 goal will only show one of them here.
--
-- 5. HISTORY TABLES: tasks_task_history is never joined directly (it has
--    many rows per task). It is aggregated via COUNT(*) grouped by
--    history_relation_id (the FK back to the current task's id, NOT the
--    history row's own id) to produce num_revisions.
--
-- 6. INDEPENDENT OVERDUE LABEL: the stored is_overdue field disagrees
--    with reality on 35% of tasks (Part 2, finding #2) and is not used
--    as ground truth anywhere. calculated_overdue is derived here as:
--      - completed with a real actual_end_date: overdue if it finished
--        after planned end_date
--      - completed but actual_end_date is NULL (41% of tasks -- see
--        Part 2 finding #5): falls back to updated_date as a proxy
--        completion date. This is a documented assumption, not ground
--        truth -- flagged as a limitation in the technical report.
--      - not completed: overdue if planned end_date has already passed
-- ------------------------------------------------------------

WITH t AS (SELECT DISTINCT ON (id) * FROM tasks_task),
ma AS (SELECT DISTINCT ON (id) * FROM tasks_major_activity),
kpi AS (SELECT DISTINCT ON (id) * FROM tasks_kpi),
ms AS (SELECT DISTINCT ON (id) * FROM tasks_milestone),
ksi AS (SELECT DISTINCT ON (id) * FROM tasks_ksi),
ksi_goal AS (SELECT DISTINCT ON (ksi_id) ksi_id, goal_id FROM tasks_ksi_goals),
goal AS (SELECT DISTINCT ON (id) * FROM tasks_goal),
p AS (SELECT DISTINCT ON (id) * FROM basedata_position),
d AS (SELECT DISTINCT ON (id) * FROM basedata_department),
u AS (SELECT DISTINCT ON (id) * FROM users_user),
st AS (SELECT DISTINCT ON (id) * FROM tasks_sub_task),
subtask_agg AS (
    SELECT task_id,
           COUNT(*) AS num_subtasks,
           SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS num_completed_subtasks
    FROM st
    GROUP BY task_id
),
revision_agg AS (
    SELECT history_relation_id AS task_id, COUNT(*) AS num_revisions
    FROM tasks_task_history
    GROUP BY history_relation_id
)

SELECT
    t.id AS task_id,
    t.task_name,
    ma.id AS major_activity_id,
    kpi.id AS kpi_id,
    ms.id AS milestone_id,
    ksi.id AS ksi_id,
    goal.id AS goal_id,
    d.id AS department_id,
    d.department_name,
    p.id AS position_id,
    p.position_name,
    u.id AS employee_id,
    t.start_date AS planned_start_date,
    t.end_date AS planned_end_date,
    t.actual_start_date,
    t.actual_end_date,
    t.status,
    t.is_overdue AS stored_overdue,
    CASE
        WHEN t.status = 'completed' AND t.actual_end_date IS NOT NULL
            THEN t.actual_end_date > t.end_date
        WHEN t.status = 'completed' AND t.actual_end_date IS NULL
            THEN t.updated_date::date > t.end_date
        WHEN t.status != 'completed'
            THEN t.end_date < CURRENT_DATE
        ELSE NULL
    END AS calculated_overdue,
    t.weight AS task_weight,
    t.is_planned AS planning_status,
    COALESCE(sa.num_subtasks, 0) AS num_subtasks,
    COALESCE(sa.num_completed_subtasks, 0) AS num_completed_subtasks,
    CASE WHEN COALESCE(sa.num_subtasks, 0) > 0
         THEN ROUND(sa.num_completed_subtasks::numeric / sa.num_subtasks, 3)
         ELSE NULL END AS subtask_completion_pct,
    COALESCE(ra.num_revisions, 0) AS num_revisions,
    (t.derived_from_cross_department_assignment_id IS NOT NULL) AS is_cross_department,
    t.created_date,
    t.updated_date
FROM t
LEFT JOIN ma ON t.major_activity_id = ma.id
LEFT JOIN kpi ON ma.kpi_id = kpi.id
LEFT JOIN ms ON kpi.milestone_id = ms.id
LEFT JOIN ksi ON ms.ksi_id = ksi.id
LEFT JOIN ksi_goal ON ksi.id = ksi_goal.ksi_id
LEFT JOIN goal ON ksi_goal.goal_id = goal.id
LEFT JOIN p ON t.position_id = p.id
LEFT JOIN d ON p.department_id = d.id
LEFT JOIN u ON p.user_id = u.id
LEFT JOIN subtask_agg sa ON sa.task_id = t.id
LEFT JOIN revision_agg ra ON ra.task_id = t.id;

-- ------------------------------------------------------------
-- VALIDATION: run this after the query above to confirm one row per task.
-- Must return zero rows.
-- ------------------------------------------------------------
-- SELECT task_id, COUNT(*)
-- FROM (<query above>) x
-- GROUP BY task_id
-- HAVING COUNT(*) > 1;
EOF
echo "written"
Output

written
