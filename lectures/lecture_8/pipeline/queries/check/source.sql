-- CHECK, the source side (PostgreSQL): the numbers the pipeline must reproduce,
-- for the SAME period as the extract (the same %(start)s and %(end)s).
SELECT count(*)                                                 AS orders,
       sum(orderTotal)                                          AS total,
       sum(orderTotal) FILTER (WHERE status = 'completed')      AS completed,
       sum(orderTotal) FILTER (WHERE status = 'completed'
                                 AND channel = 'in_store')      AS completed_in_store
FROM orders_big
WHERE orderDate >= %(start)s
  AND orderDate <  %(end)s
