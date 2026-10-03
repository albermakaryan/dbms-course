-- ============================================================
-- Lecture 5 — Part 6: Recursive CTEs (a preview)
-- Run after Part 5.
-- ============================================================

-- ---- 6.1 Lecture 4's two-hop self-join ----
SELECT e.firstName AS employee, m.firstName AS manager, mm.firstName AS managers_manager
FROM employees e
LEFT JOIN employees m  ON m.employeeID  = e.managerID
LEFT JOIN employees mm ON mm.employeeID = m.managerID
WHERE e.firstName = 'Nare';
-- employee | manager | managers_manager
-- Nare     | Hayk    | Vahe
-- Two hops reach the top, because the shop's chart is only 3 deep.

-- ---- 6.2 Add one level and the self-join falls short ----
-- HYPOTHETICAL: a trainee, Sevak, reporting to Nare. He is not in the
-- data -- the staff CTE adds him for this query only; nothing is saved.
WITH staff AS (
    SELECT employeeID, firstName, position, managerID FROM employees
  UNION ALL
    SELECT 9, 'Sevak', 'Trainee', 4                -- 4 = Nare
)
SELECT e.firstName AS employee, m.firstName AS manager, mm.firstName AS managers_manager
FROM staff e
LEFT JOIN staff m  ON m.employeeID  = e.managerID
LEFT JOIN staff mm ON mm.employeeID = m.managerID
WHERE e.firstName = 'Sevak';
-- employee | manager | managers_manager
-- Sevak    | Nare    | Hayk
-- Vahe is missing, and nothing says so. A third hop needs a third
-- join; a fourth level needs a fourth. The query hard-codes the depth.

-- ---- 6.3 WITH RECURSIVE: keep hopping until there's no manager ----
WITH RECURSIVE staff AS (
    SELECT employeeID, firstName, position, managerID FROM employees
  UNION ALL
    SELECT 9, 'Sevak', 'Trainee', 4
),
chain AS (
    -- start: the employee himself
    SELECT employeeID, firstName, position, managerID, 1 AS level
    FROM staff
    WHERE firstName = 'Sevak'
  UNION ALL
    -- step: the manager of whoever we found last time
    SELECT m.employeeID, m.firstName, m.position, m.managerID, c.level + 1
    FROM staff m
    JOIN chain c ON m.employeeID = c.managerID
)
SELECT level, firstName, position
FROM chain
ORDER BY level;
-- level | firstname | position
-- 1 | Sevak     | Trainee
-- 2 | Nare      | Sales Associate
-- 3 | Hayk      | Senior Sales
-- 4 | Vahe      | Store Manager
-- Stops by itself: Vahe's managerID is NULL, the step finds no row.

-- The real chart (no Sevak), top down, every level at once:
WITH RECURSIVE org AS (
    SELECT employeeID, firstName, managerID, 1 AS level,
           firstName::text AS path
    FROM employees
    WHERE managerID IS NULL
  UNION ALL
    SELECT e.employeeID, e.firstName, e.managerID, o.level + 1,
           o.path || ' > ' || e.firstName
    FROM employees e
    JOIN org o ON e.managerID = o.employeeID
)
SELECT level, path
FROM org
ORDER BY path;
-- level | path
-- 1 | Vahe
-- 2 | Vahe > Ani
-- 2 | Vahe > Gor
-- 2 | Vahe > Hayk
-- 3 | Vahe > Hayk > Lilit
-- 3 | Vahe > Hayk > Nare
-- 2 | Vahe > Marine
-- 3 | Vahe > Marine > Arman
