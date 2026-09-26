-- ============================================================
-- NOT A TRAP: several conditional counts in one query —
--             count(*) FILTER (WHERE ...) vs the older CASE WHEN
--
-- Standalone: creates its own scratch table, drops it at the end.
-- ============================================================

DROP TABLE IF EXISTS tickets_08 CASCADE;

CREATE TABLE tickets_08 (
    ticket_id INT PRIMARY KEY,
    priority  TEXT NOT NULL,           -- 'high' or 'low'
    status    TEXT NOT NULL            -- 'open' or 'closed'
);

INSERT INTO tickets_08 VALUES
    (1, 'high', 'open'),
    (2, 'high', 'closed'),
    (3, 'low',  'open'),
    (4, 'low',  'open'),
    (5, 'high', 'open');


-- ---- FILTER: each aggregate sees only the rows its condition keeps ----
SELECT count(*)                                                AS total,
       count(*) FILTER (WHERE priority = 'high')               AS high,
       count(*) FILTER (WHERE status = 'open')                 AS open,
       count(*) FILTER (WHERE priority = 'high' AND status = 'open') AS high_open
FROM tickets_08;
-- 1 row:  total 5 | high 3 | open 4 | high_open 2


-- ---- The older idiom: sum a CASE that is 1 or 0 ----
SELECT count(*)                                                        AS total,
       sum(CASE WHEN priority = 'high' THEN 1 ELSE 0 END)              AS high,
       sum(CASE WHEN status = 'open' THEN 1 ELSE 0 END)                AS open,
       sum(CASE WHEN priority = 'high' AND status = 'open' THEN 1 ELSE 0 END) AS high_open
FROM tickets_08;
-- 1 row:  total 5 | high 3 | open 4 | high_open 2   (identical)


-- ---- Proof they agree ----
SELECT count(*), count(*) FILTER (WHERE priority = 'high'),
       count(*) FILTER (WHERE status = 'open'),
       count(*) FILTER (WHERE priority = 'high' AND status = 'open')
FROM tickets_08
EXCEPT
SELECT count(*), sum(CASE WHEN priority = 'high' THEN 1 ELSE 0 END),
       sum(CASE WHEN status = 'open' THEN 1 ELSE 0 END),
       sum(CASE WHEN priority = 'high' AND status = 'open' THEN 1 ELSE 0 END)
FROM tickets_08;
-- 0 rows


DROP TABLE IF EXISTS tickets_08 CASCADE;

-- LESSON: FILTER (WHERE ...) says "count only these rows" directly, and
-- several FILTERs give several conditional counts in one pass; the
-- CASE WHEN version means the same and works in any SQL database.
