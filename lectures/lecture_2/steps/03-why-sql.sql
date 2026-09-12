-- ============================================================
-- Lecture 2 — Part 3: Why SQL
-- ============================================================
--
-- Declarative vs. procedural, the five sub-languages
-- (DDL / DML / DQL / DCL / TCL), and the type table are
-- discussion -- see lecture-02-notes.md, Part 3.
--
-- The one runnable demo: text sorts alphabetically, not numerically.

SELECT unnest(ARRAY['9.99', '52.00', '100.00']) AS price_as_text
ORDER BY 1;

-- 100.00, then 52.00, then 9.99 -- the exact opposite of numeric
-- order. That's why `price` on the schema is DECIMAL, not text.
