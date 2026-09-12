-- ============================================================
-- Lecture 2 — Part 5a: DML — filling the tables  (inserts)
-- Parents first, children last -- the foreign keys enforce this.
-- Assumes 04-ddl.sql has run. The check lives in 05-02-check.sql.
-- ============================================================

-- Safe to re-run: clear out any previous run of this part first.
-- All four tables in one TRUNCATE handles the foreign keys between
-- them without needing CASCADE. RESTART IDENTITY resets the
-- SERIAL ids back to 1.
TRUNCATE TABLE orders, customers, employees, products RESTART IDENTITY;

INSERT INTO customers (firstName, lastName, birthDate, moneySpent, anniversary)
SELECT DISTINCT customerFirstName, customerLastName, customerBirthDate,
                customerMoneySpent, customerAnniversary
FROM sales_raw;

INSERT INTO employees (firstName, lastName, birthDate)
SELECT DISTINCT employeeFirstName, employeeLastName, employeeBirthDate
FROM sales_raw;

INSERT INTO products (category, price)
SELECT DISTINCT productCategory, productPrice
FROM sales_raw;

-- Orders: translate names/categories into id numbers via JOIN.
-- The customer join needs all THREE natural-key columns.
INSERT INTO orders (orderID, customerID, employeeID, productID, orderTotal, orderDate)
SELECT r.orderID, c.customerID, e.employeeID, p.productID, r.orderTotal, r.orderDate
FROM sales_raw r
JOIN customers c ON c.firstName = r.customerFirstName
                AND c.lastName  = r.customerLastName
                AND c.birthDate = r.customerBirthDate
JOIN employees e ON e.firstName = r.employeeFirstName
                AND e.lastName  = r.employeeLastName
                AND e.birthDate = r.employeeBirthDate
JOIN products  p ON p.category  = r.productCategory;
