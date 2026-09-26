-- ============================================================
-- TRAP 6: NATURAL JOIN joins on EVERY shared column name — silently
--
-- Standalone: creates its own scratch tables, drops them at the end.
-- A minimal version of the real orders/sales collision (97 rows, not 600).
-- ============================================================

DROP TABLE IF EXISTS invoices_06, payments_06 CASCADE;

-- Both tables have columns named id, amount and status.
CREATE TABLE invoices_06 (
    id     INT PRIMARY KEY,
    amount NUMERIC(8,2) NOT NULL,
    status TEXT                        -- nullable
);

CREATE TABLE payments_06 (
    id      INT PRIMARY KEY,           -- same id = payment for that invoice
    amount  NUMERIC(8,2) NOT NULL,
    status  TEXT,                      -- nullable
    paid_on DATE NOT NULL
);

INSERT INTO invoices_06 VALUES
    (1, 100.00, 'closed'),
    (2, 250.00, 'closed'),
    (3,  80.00, 'open'),
    (4,  60.00, NULL);

INSERT INTO payments_06 VALUES
    (1, 100.00, 'closed', DATE '2024-03-01'),   -- agrees on all three
    (2, 250.00, 'closed', DATE '2024-03-02'),   -- agrees on all three
    (3,  50.00, 'open',   DATE '2024-03-03'),   -- partial payment: amount differs
    (4,  60.00, NULL,     DATE '2024-03-04');   -- status NULL on both sides


-- ---- The intent: each invoice next to its payment (4 pairs) ----

-- ---- WRONG: NATURAL JOIN ----
SELECT *
FROM invoices_06 NATURAL JOIN payments_06
ORDER BY id;
-- WRONG: 2 rows (ids 1 and 2)
-- Invoice 3 is dropped because the amounts differ; invoice 4 because
-- NULL = NULL is not true. Nothing in the query says so.


-- ---- The hidden condition, spelled out ----
SELECT i.id, i.amount, i.status, p.paid_on
FROM invoices_06 i
JOIN payments_06 p ON p.id     = i.id
                  AND p.amount = i.amount
                  AND p.status = i.status
ORDER BY i.id;
-- 2 rows (ids 1 and 2): exactly what NATURAL JOIN did.


-- ---- FIXED: say which column the join is on ----
SELECT id, i.amount AS invoiced, p.amount AS paid, p.paid_on
FROM invoices_06 i
JOIN payments_06 p USING (id)
ORDER BY id;
-- FIXED: 4 rows
--   1 | 100.00 | 100.00 | 2024-03-01
--   2 | 250.00 | 250.00 | 2024-03-02
--   3 |  80.00 |  50.00 | 2024-03-03
--   4 |  60.00 |  60.00 | 2024-03-04
-- (JOIN ... ON p.id = i.id gives the same 4 pairs.)


DROP TABLE IF EXISTS invoices_06, payments_06 CASCADE;

-- LESSON: NATURAL JOIN matches on every column name the tables happen to
-- share, including ones that differ or are NULL — write the join
-- condition yourself with ON or USING so it is visible and stable.
