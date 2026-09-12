-- ============================================================
-- Lecture 2 — Part 1a: load the flat file  (create + insert)
-- Run psql from the lecture_2/ folder so the \copy path below
-- resolves (it's relative to psql's working directory, not the
-- server). The queries live in 01-02-explore.sql.
-- ============================================================

CREATE TABLE IF NOT EXISTS sales_raw (
    orderID              INT,
    orderDate            DATE,
    customerFirstName    VARCHAR(50),
    customerLastName     VARCHAR(50),
    customerBirthDate    DATE,
    customerMoneySpent   DECIMAL(10,2),
    customerAnniversary  DATE,
    employeeFirstName    VARCHAR(50),
    employeeLastName     VARCHAR(50),
    employeeBirthDate    DATE,
    productCategory      VARCHAR(100),
    productPrice         DECIMAL(8,2),
    orderTotal           DECIMAL(10,2)
);

-- Safe to re-run: clear out any previous load first.
TRUNCATE TABLE sales_raw;

-- No access to the CSV (crashed laptop, no file access)? Run
-- \i data/sales_flat_inserts.sql instead -- same 42 rows, plain
-- INSERT statements, no file needed.
\copy sales_raw FROM 'data/sales_flat.csv' WITH (FORMAT csv, HEADER true);
