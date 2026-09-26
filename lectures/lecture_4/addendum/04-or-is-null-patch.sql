-- ============================================================
-- TRAP 4: the "WHERE condition OR column IS NULL" patch
--         looks like the ON fix — but only re-admits rows with NO match
--
-- Standalone: creates its own scratch tables, drops them at the end.
-- Starts from the same data as files 01 and 02.
-- ============================================================

DROP TABLE IF EXISTS items_04, categories_04 CASCADE;

CREATE TABLE categories_04 (
    category_id INT PRIMARY KEY,
    name        TEXT NOT NULL
);

CREATE TABLE items_04 (
    item_id     INT PRIMARY KEY,
    category_id INT NOT NULL REFERENCES categories_04,
    name        TEXT NOT NULL,
    status      TEXT NOT NULL          -- 'in_stock' or 'sold_out'
);

INSERT INTO categories_04 VALUES
    (1, 'Books'),
    (2, 'Games'),
    (3, 'Toys');                       -- Toys has no items at all

INSERT INTO items_04 VALUES
    (10, 1, 'Atlas',  'in_stock'),
    (11, 1, 'Novel',  'sold_out'),
    (20, 2, 'Chess',  'in_stock');


-- ---- Part A: on this data, the patch and the ON fix agree ----

-- The ON fix (file 02):
SELECT c.name AS category, i.name AS item
FROM categories_04 c
LEFT JOIN items_04 i ON i.category_id = c.category_id
                    AND i.status = 'in_stock'
ORDER BY c.category_id, i.item_id;
-- 3 rows:  Books | Atlas,  Games | Chess,  Toys | NULL

-- The patch: keep the condition in WHERE, re-admit the NULL-padded rows
SELECT c.name AS category, i.name AS item
FROM categories_04 c
LEFT JOIN items_04 i ON i.category_id = c.category_id
WHERE i.status = 'in_stock' OR i.item_id IS NULL
ORDER BY c.category_id, i.item_id;
-- 3 rows:  Books | Atlas,  Games | Chess,  Toys | NULL   (same as above)
--
-- It looks like the same logic spelled differently. It isn't quite.


-- ---- Part B: add a category whose only item FAILS the condition ----
INSERT INTO categories_04 VALUES (4, 'Puzzles');
INSERT INTO items_04 VALUES (40, 4, 'Maze', 'sold_out');

-- The ON fix:
SELECT c.name AS category, i.name AS item
FROM categories_04 c
LEFT JOIN items_04 i ON i.category_id = c.category_id
                    AND i.status = 'in_stock'
ORDER BY c.category_id, i.item_id;
-- 4 rows:  Books | Atlas,  Games | Chess,  Toys | NULL,  Puzzles | NULL

-- The patch:
SELECT c.name AS category, i.name AS item
FROM categories_04 c
LEFT JOIN items_04 i ON i.category_id = c.category_id
WHERE i.status = 'in_stock' OR i.item_id IS NULL
ORDER BY c.category_id, i.item_id;
-- WRONG: 3 rows:  Books | Atlas,  Games | Chess,  Toys | NULL
-- Puzzles is missing. It HAD a match (Maze), so the LEFT JOIN never
-- NULL-padded it; WHERE then removed Maze (sold_out, and item_id is not
-- NULL). The patch only re-admits categories with no items at all; the
-- ON version also keeps categories whose items all fail the condition.


DROP TABLE IF EXISTS items_04, categories_04 CASCADE;

-- LESSON: "OR right_key IS NULL" re-admits only left rows that matched
-- nothing; it is not the same as moving the condition into ON, which
-- keeps every left row. Write the condition in ON.
