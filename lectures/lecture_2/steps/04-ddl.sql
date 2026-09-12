-- ============================================================
-- Lecture 2 — Part 4: DDL — creating the tables
-- Exactly the ER diagram from Part 2, now as real SQL.
-- ============================================================

-- IF NOT EXISTS makes these safe to re-run if you already ran this
-- part once this session.

-- 6 columns
CREATE TABLE IF NOT EXISTS customers (
    customerID   SERIAL PRIMARY KEY,          -- surrogate key, auto-generated
    firstName    VARCHAR(50) NOT NULL,
    lastName     VARCHAR(50) NOT NULL,
    birthDate    DATE,
    moneySpent   DECIMAL(10,2) DEFAULT 0 CHECK (moneySpent >= 0),
    anniversary  DATE
);

-- 4 columns
CREATE TABLE IF NOT EXISTS employees (
    employeeID   SERIAL PRIMARY KEY,
    firstName    VARCHAR(50) NOT NULL,
    lastName     VARCHAR(50) NOT NULL,
    birthDate    DATE
);

-- 3 columns
CREATE TABLE IF NOT EXISTS products (
    productID    SERIAL PRIMARY KEY,
    category     VARCHAR(100) NOT NULL UNIQUE,
    price        DECIMAL(8,2) NOT NULL CHECK (price >= 0)
);

-- 6 columns -- the EVENT table
CREATE TABLE IF NOT EXISTS orders (
    orderID      INT PRIMARY KEY,
    customerID   INT NOT NULL REFERENCES customers(customerID),
    employeeID   INT NOT NULL REFERENCES employees(employeeID),
    productID    INT NOT NULL REFERENCES products(productID),
    orderTotal   DECIMAL(10,2) NOT NULL CHECK (orderTotal >= 0),
    orderDate    DATE NOT NULL
);

-- Notice what is NOT in orders: no names, no category text, no price.
-- Only references -- REFERENCES = foreign key = referential integrity.
