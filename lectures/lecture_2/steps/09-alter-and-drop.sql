-- ============================================================
-- Lecture 2 — Part 9: ALTER and DROP — evolving and retiring a schema
-- Run after Part 5 (tables need to exist and be filled). Every
-- statement below was checked against a live database -- the
-- comments show the real output/errors, not guesses.
-- ============================================================

-- ---- ALTER TABLE: add a column, the wrong way then the right way ----

-- No DEFAULT -> every existing row gets NULL
ALTER TABLE orders ADD COLUMN saleChannel VARCHAR(20);
SELECT count(*) FROM orders WHERE saleChannel IS NULL;   -- 42

-- Can't require NOT NULL while NULLs still exist
ALTER TABLE orders ALTER COLUMN saleChannel SET NOT NULL;
-- ERROR: column "salechannel" of relation "orders" contains null values

-- Backfill, then it works
UPDATE orders SET saleChannel = 'in_store' WHERE saleChannel IS NULL;
ALTER TABLE orders ALTER COLUMN saleChannel SET NOT NULL;

-- Fix a name you're not happy with
ALTER TABLE orders RENAME COLUMN saleChannel TO channel;

-- Make room -- widening is always safe. Shrinking back succeeds here
-- too, but only because none of our names are actually over 50
-- characters; a real shrink can fail if existing data no longer fits.
ALTER TABLE customers ALTER COLUMN firstName TYPE VARCHAR(100);
ALTER TABLE customers ALTER COLUMN firstName TYPE VARCHAR(50);

-- Add a constraint after the fact -- same CHECK vocabulary as Part 4,
-- just applied later. Naming it means you can find and drop it again.
ALTER TABLE orders ADD CONSTRAINT channel_known
    CHECK (channel IN ('in_store', 'online'));

-- Watch it fire, same as Part 8 watched the original constraints fire.
UPDATE orders SET channel = 'carrier_pigeon'
WHERE orderID = (SELECT orderID FROM orders LIMIT 1);
-- ERROR: new row for relation "orders" violates check constraint "channel_known"
-- DETAIL: Failing row contains (..., carrier_pigeon).

-- Remove the constraint, then the column entirely.
-- (Didn't name a constraint yourself? \d tablename lists every
-- constraint's generated name -- tablename_column_check, the same
-- pattern Part 8's error messages already showed you.)
ALTER TABLE orders DROP CONSTRAINT channel_known;
ALTER TABLE orders DROP COLUMN channel;
-- orders is now back to exactly the 6 columns from Part 4.


-- ---- DELETE vs TRUNCATE vs DROP TABLE: three ways to remove data ----
-- All three refuse to touch a row/table another table still points to.

-- 1. DELETE one referenced row
DELETE FROM products WHERE productID = 1;
-- ERROR: update or delete on table "products" violates foreign key
--        constraint "orders_productid_fkey" on table "orders"

-- 2. TRUNCATE the whole referenced table
TRUNCATE products;
-- ERROR: cannot truncate a table referenced in a foreign key constraint
-- HINT:  Truncate table "orders" at the same time, or use TRUNCATE ... CASCADE.

-- 3. DROP the referenced table entirely
DROP TABLE products;
-- ERROR: cannot drop table products because other objects depend on it
-- HINT:  Use DROP ... CASCADE to drop the dependent objects too.

-- Three different statements, the same refusal underneath: the
-- foreign key from orders to products is doing exactly what Part 4
-- promised -- protecting data you didn't ask it to touch.

-- IF EXISTS makes DROP safe to run even when you're not sure the
-- table is there -- a notice instead of an error.
DROP TABLE IF EXISTS not_a_real_table;
-- NOTICE: table "not_a_real_table" does not exist, skipping


-- ---- What CASCADE actually does ----
-- The HINT above suggests DROP TABLE products CASCADE, but that's
-- easy to misread as "and delete everything that used to point at
-- it." It doesn't -- CASCADE drops the dependent CONSTRAINT, not the
-- dependent table or its rows. Not something to try on tables you
-- actually care about, so try it on a disposable pair instead:

CREATE TABLE scratch_categories (name VARCHAR(50) PRIMARY KEY);
CREATE TABLE scratch_items (
    id  SERIAL PRIMARY KEY,
    cat VARCHAR(50) REFERENCES scratch_categories(name)
);

DROP TABLE scratch_categories CASCADE;
-- NOTICE: drop cascades to constraint scratch_items_cat_fkey on table scratch_items

\d scratch_items
-- still exists, still has its rows -- just no foreign key anymore.

DROP TABLE scratch_items;   -- clean up the sandbox


-- ---- Confirm the real schema is untouched ----
-- Every DELETE/TRUNCATE/DROP against products/orders failed on
-- purpose, the column added earlier nets to zero, and firstName's
-- width was widened then shrunk back.
SELECT 'products' AS t, count(*) FROM products
UNION ALL SELECT 'orders', count(*) FROM orders;
-- Expected: 6 / 42 -- unchanged since Part 5.
