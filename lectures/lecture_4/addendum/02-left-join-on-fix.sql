-- ============================================================
-- TRAP 2 (the fix for trap 1): put the right-table condition in ON
--
-- Standalone: creates its own scratch tables, drops them at the end.
-- Same data as file 01.
-- ============================================================

DROP TABLE IF EXISTS items_02, categories_02 CASCADE;

CREATE TABLE categories_02 (
    category_id INT PRIMARY KEY,
    name        TEXT NOT NULL
);

CREATE TABLE items_02 (
    item_id     INT PRIMARY KEY,
    category_id INT NOT NULL REFERENCES categories_02,
    name        TEXT NOT NULL,
    status      TEXT NOT NULL          -- 'in_stock' or 'sold_out'
);

INSERT INTO categories_02 VALUES
    (1, 'Books'),
    (2, 'Games'),
    (3, 'Toys');                       -- Toys has no items at all

INSERT INTO items_02 VALUES
    (10, 1, 'Atlas',  'in_stock'),
    (11, 1, 'Novel',  'sold_out'),
    (20, 2, 'Chess',  'in_stock');


-- ---- BROKEN (from file 01): condition in WHERE ----
SELECT c.name AS category, i.name AS item
FROM categories_02 c
LEFT JOIN items_02 i ON i.category_id = c.category_id
WHERE i.status = 'in_stock'
ORDER BY c.category_id, i.item_id;
-- WRONG: 2 rows
--   Books | Atlas
--   Games | Chess


-- ---- FIXED: the same condition moved into ON ----
SELECT c.name AS category, i.name AS item
FROM categories_02 c
LEFT JOIN items_02 i ON i.category_id = c.category_id
                    AND i.status = 'in_stock'
ORDER BY c.category_id, i.item_id;
-- FIXED: 3 rows
--   Books | Atlas
--   Games | Chess
--   Toys  | NULL
-- The status test now only decides which items count as a match.
-- Toys has no matching item, so it is NULL-padded and kept.


-- ---- The same contrast, aggregated: in-stock items per category ----
SELECT c.name AS category, count(i.item_id) AS in_stock_items
FROM categories_02 c
LEFT JOIN items_02 i ON i.category_id = c.category_id
WHERE i.status = 'in_stock'
GROUP BY c.category_id, c.name
ORDER BY c.category_id;
-- WRONG: 2 rows   Books 1 | Games 1          (Toys missing)

SELECT c.name AS category, count(i.item_id) AS in_stock_items
FROM categories_02 c
LEFT JOIN items_02 i ON i.category_id = c.category_id
                    AND i.status = 'in_stock'
GROUP BY c.category_id, c.name
ORDER BY c.category_id;
-- FIXED: 3 rows   Books 1 | Games 1 | Toys 0


DROP TABLE IF EXISTS items_02, categories_02 CASCADE;

-- LESSON: with a LEFT JOIN, conditions on the right-hand table belong in
-- ON (they decide what counts as a match); conditions on the left-hand
-- table belong in WHERE (they decide which rows you keep).
