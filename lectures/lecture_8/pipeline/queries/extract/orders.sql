-- EXTRACT (PostgreSQL): the orders of one period, only the columns the reports need.
-- %(start)s and %(end)s are PARAMETERS: psycopg sends their values (from
-- EXTRACT_PARAMS in src/config.py) separately from this text, as in Part 5.3.
-- Change the period there, not here. Saved as data/raw/orders.parquet.
SELECT orderID, orderDate, employeeID, channel, status, orderTotal
FROM orders_big
WHERE orderDate >= %(start)s
  AND orderDate <  %(end)s
ORDER BY orderID
