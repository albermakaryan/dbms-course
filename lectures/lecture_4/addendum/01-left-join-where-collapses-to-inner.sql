-- ============================================================
-- TRAP 1: a LEFT JOIN + WHERE on the right table collapses to an INNER JOIN
--
-- Standalone: creates its own scratch tables, drops them at the end.
-- ============================================================

DROP TABLE IF EXISTS items_01, categories_01 CASCADE;

CREATE TABLE categories_01 (
    category_id INT PRIMARY KEY,
    name        TEXT NOT NULL
);

CREATE TABLE items_01 (
    item_id     INT PRIMARY KEY,
    category_id INT NOT NULL REFERENCES categories_01,
    name        TEXT NOT NULL,
    status      TEXT NOT NULL          -- 'in_stock' or 'sold_out'
);

INSERT INTO categories_01 VALUES
    (1, 'Books'),
    (2, 'Games'),
    (3, 'Toys');                       -- Toys has no items at all

INSERT INTO items_01 VALUES
    (10, 1, 'Atlas',  'in_stock'),
    (11, 1, 'Novel',  'sold_out'),
    (20, 2, 'Chess',  'in_stock');


-- ---- The intent: every category, with its in-stock items ----
-- "Every category" means Toys should appear too, even with nothing in it.

-- ---- WRONG: the condition on the right table sits in WHERE ----
SELECT c.name AS category, i.name AS item
FROM categories_01 c
LEFT JOIN items_01 i ON i.category_id = c.category_id
WHERE i.status = 'in_stock'
ORDER BY c.category_id, i.item_id;
-- WRONG: 2 rows
--   Books | Atlas
--   Games | Chess
-- Toys is gone. The LEFT JOIN did keep it (as Toys | NULL), but then
-- WHERE tested NULL = 'in_stock', which is not true, and dropped it.


-- ---- The same 2 rows from a plain INNER JOIN ----
SELECT c.name AS category, i.name AS item
FROM categories_01 c
JOIN items_01 i ON i.category_id = c.category_id
               AND i.status = 'in_stock'
ORDER BY c.category_id, i.item_id;
-- 2 rows
--   Books | Atlas
--   Games | Chess


-- ---- Proof that the two are identical: difference in both directions ----
(SELECT c.name, i.name
 FROM categories_01 c
 LEFT JOIN items_01 i ON i.category_id = c.category_id
 WHERE i.status = 'in_stock'
 EXCEPT
 SELECT c.name, i.name
 FROM categories_01 c
 JOIN items_01 i ON i.category_id = c.category_id AND i.status = 'in_stock')
UNION ALL
(SELECT c.name, i.name
 FROM categories_01 c
 JOIN items_01 i ON i.category_id = c.category_id AND i.status = 'in_stock'
 EXCEPT
 SELECT c.name, i.name
 FROM categories_01 c
 LEFT JOIN items_01 i ON i.category_id = c.category_id
 WHERE i.status = 'in_stock');
-- 0 rows: nothing in either result that isn't in the other.
--
-- If this 2-row result is genuinely what you want, write INNER JOIN and
-- say so. If you wanted Toys too, the fix is in file 02.


DROP TABLE IF EXISTS items_01, categories_01 CASCADE;

-- LESSON: a WHERE condition on a LEFT JOIN's right-hand table that can't
-- be true for NULL deletes every NULL-padded row, so the LEFT JOIN
-- silently becomes an INNER JOIN.
