-- ============================================================
-- Lecture 4 — Joins, step 9: self-joins — a table joined to itself
-- Notes: Part 4.8
-- Run after steps/00-setup.sql. Read-only: safe to re-run.
-- ONE statement in this file fails ON PURPOSE.
--
-- employees.managerID points at another row of employees (filled in
-- by steps/00-setup.sql). Same table, two roles — so two aliases.
-- ============================================================


-- ---- 0. Look at the raw data first ----
SELECT employeeID, firstName, position, branch, managerID
FROM employees
ORDER BY employeeID;


-- ---- 1. Error on purpose: a self-join without aliases ----
SELECT employees.firstName, employees.firstName
FROM employees
JOIN employees ON employees.employeeID = employees.managerID;
-- There is no way to say "this row" and "that other row of the same
-- table" without giving each copy its own name.


-- ---- 2. Direct manager: e plays the employee, m plays the manager ----
SELECT e.firstName || ' ' || e.lastName AS employee,
       e.position,
       m.firstName || ' ' || m.lastName AS manager
FROM employees e
LEFT JOIN employees m ON m.employeeID = e.managerID
ORDER BY m.employeeID NULLS FIRST, e.employeeID;
-- Why LEFT? Guess what an inner join would do: 7 rows — the boss,
-- whose managerID is NULL, would vanish from the staff list.


-- ---- 3. A second hop: the manager's manager ----
SELECT e.firstName AS employee, m.firstName AS manager, mm.firstName AS managers_manager
FROM employees e
LEFT JOIN employees m  ON m.employeeID  = e.managerID
LEFT JOIN employees mm ON mm.employeeID = m.managerID
WHERE e.branch <> 'Yerevan Center';
-- Two levels up took two joins. "All the way up, however many levels"
-- would need one join per level.


-- ---- 4. Self-join + GROUP BY: direct reports per manager ----
SELECT m.firstName || ' ' || m.lastName AS manager, count(e.employeeID) AS direct_reports
FROM employees m
JOIN employees e ON e.managerID = m.employeeID
GROUP BY m.employeeID, m.firstName, m.lastName
ORDER BY direct_reports DESC;
-- An inner join on purpose: only people who manage someone appear.

-- Any hierarchy stored as "this table points to itself" — org charts,
-- category trees, comment replies — uses exactly this shape.
