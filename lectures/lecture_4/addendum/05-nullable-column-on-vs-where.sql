-- ============================================================
-- TRAP 5: IS NULL on a nullable column — ON and WHERE answer
--         two different questions
--
-- Standalone: creates its own scratch tables, drops them at the end.
-- ============================================================

DROP TABLE IF EXISTS lines_05, products_05 CASCADE;

CREATE TABLE products_05 (
    product_id INT PRIMARY KEY,
    name       TEXT NOT NULL
);

CREATE TABLE lines_05 (
    line_id       INT PRIMARY KEY,
    product_id    INT NOT NULL REFERENCES products_05,
    discount_code TEXT                 -- nullable: NULL = sold at full price
);

INSERT INTO products_05 VALUES
    (1, 'A'),
    (2, 'B'),
    (3, 'C');

INSERT INTO lines_05 VALUES
    (1, 1, NULL),                      -- A: one full-price line ...
    (2, 1, 'SPRING'),                  --    ... and one discounted line
    (3, 2, 'SPRING');                  -- B: only a discounted line
                                       -- C: no lines at all


-- ---- Version 1: the NULL test in WHERE ----
SELECT p.name AS product, l.line_id, l.discount_code
FROM products_05 p
LEFT JOIN lines_05 l ON l.product_id = p.product_id
WHERE l.discount_code IS NULL
ORDER BY p.product_id;
-- 2 rows
--   A | 1    | NULL      <- A's real full-price line
--   C | NULL | NULL      <- C's NULL-padded placeholder (no lines at all)
-- B is gone.


-- ---- Version 2: the NULL test in ON ----
SELECT p.name AS product, l.line_id, l.discount_code
FROM products_05 p
LEFT JOIN lines_05 l ON l.product_id = p.product_id
                    AND l.discount_code IS NULL
ORDER BY p.product_id;
-- 3 rows
--   A | 1    | NULL      <- A's real full-price line
--   B | NULL | NULL      <- placeholder: B has no full-price line
--   C | NULL | NULL      <- placeholder: C has no lines at all


-- ---- Why B is the row that differs ----
-- B has exactly one line, and it is discounted.
-- In version 1, the join matches B to that line (a REAL match, so no
-- placeholder is made), and then WHERE removes it because
-- discount_code is not NULL. Nothing is left for B.
-- In version 2, the NULL test is part of matching, so B's discounted
-- line never counts as a match. B has no qualifying match, so the
-- LEFT JOIN gives it a placeholder.
--
-- Neither is simply "the buggy one". They answer different questions:
--   version 1: full-price lines, plus the products that have NO lines
--              at all (and you cannot tell those NULLs apart from a
--              real line's NULL without looking at line_id)
--   version 2: every product, with its full-price lines — a product
--              with no QUALIFYING line gets a placeholder
-- Decide which question you mean before choosing where the test goes.


DROP TABLE IF EXISTS lines_05, products_05 CASCADE;

-- LESSON: when the condition tests a nullable column for NULL, moving it
-- between ON and WHERE changes the question, not just the correctness —
-- WHERE sees both real NULLs and padding NULLs, ON sees only real rows.
