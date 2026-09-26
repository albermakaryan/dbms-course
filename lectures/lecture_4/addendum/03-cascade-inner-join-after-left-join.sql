-- ============================================================
-- TRAP 3: an INNER JOIN after a LEFT JOIN silently undoes it
--
-- Standalone: creates its own scratch tables, drops them at the end.
-- Chain: authors_03 -> books_03 -> publishers_03
-- ============================================================

DROP TABLE IF EXISTS books_03, authors_03, publishers_03 CASCADE;

CREATE TABLE authors_03 (
    author_id INT PRIMARY KEY,
    name      TEXT NOT NULL
);

CREATE TABLE publishers_03 (
    publisher_id INT PRIMARY KEY,
    name         TEXT NOT NULL
);

CREATE TABLE books_03 (
    book_id      INT PRIMARY KEY,
    author_id    INT NOT NULL REFERENCES authors_03,
    publisher_id INT NOT NULL REFERENCES publishers_03,
    title        TEXT NOT NULL
);

INSERT INTO authors_03 VALUES
    (1, 'Ann'),
    (2, 'Ben'),
    (3, 'Cid');                        -- Cid has written no books yet

INSERT INTO publishers_03 VALUES
    (100, 'North Press'),
    (101, 'South House');

INSERT INTO books_03 VALUES
    (10, 1, 100, 'First Light'),
    (11, 2, 101, 'Deep Water');


-- ---- The intent: every author, with their books and publishers ----

-- ---- WRONG: LEFT JOIN, then an INNER JOIN on the next table ----
SELECT a.name AS author, b.title, p.name AS publisher
FROM authors_03 a
LEFT JOIN books_03      b ON b.author_id    = a.author_id
JOIN      publishers_03 p ON p.publisher_id = b.publisher_id
ORDER BY a.author_id;
-- WRONG: 2 rows
--   Ann | First Light | North Press
--   Ben | Deep Water  | South House
-- Cid is gone. The LEFT JOIN kept him (Cid | NULL, with b.publisher_id
-- NULL), but the next join is INNER, and p.publisher_id = NULL is never
-- true, so that row found no publisher and was dropped.


-- ---- FIXED: every join after the LEFT JOIN is a LEFT JOIN too ----
SELECT a.name AS author, b.title, p.name AS publisher
FROM authors_03 a
LEFT JOIN books_03      b ON b.author_id    = a.author_id
LEFT JOIN publishers_03 p ON p.publisher_id = b.publisher_id
ORDER BY a.author_id;
-- FIXED: 3 rows
--   Ann | First Light | North Press
--   Ben | Deep Water  | South House
--   Cid | NULL        | NULL


DROP TABLE IF EXISTS books_03, authors_03, publishers_03 CASCADE;

-- LESSON: once a table is LEFT JOINed, any later INNER JOIN (or WHERE
-- test) on its columns throws away the NULL-padded rows again — keep
-- the rest of the chain LEFT, or the first LEFT JOIN did nothing.
