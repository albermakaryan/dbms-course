-- ============================================================
-- Fallback loader for sales_raw -- no CSV file or \copy needed.
--
-- Use this instead of the \copy line in Part 1 / steps/01 if you
-- don't have access to data/sales_flat.csv (crashed laptop, no file
-- access, working from a paste buffer, etc.) -- every row from that
-- CSV, as plain INSERT statements. Same 42 rows, same result either
-- way; the rest of the lecture doesn't care which loader you used.
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

TRUNCATE TABLE sales_raw;

INSERT INTO sales_raw (
    orderID, orderDate, customerFirstName, customerLastName, customerBirthDate,
    customerMoneySpent, customerAnniversary, employeeFirstName, employeeLastName,
    employeeBirthDate, productCategory, productPrice, orderTotal
) VALUES
    (1005, '2024-08-01', 'Aram', 'Vardanyan', '1997-12-09', 3564.77, '2024-01-30', 'Ani', 'Harutyunyan', '1994-08-22', 'Audio', 149.90, 299.80),
    (1016, '2024-08-01', 'Narek', 'Manukyan', '1992-09-03', 1679.38, '2022-02-28', 'Vahe', 'Sahakyan', '1987-06-04', 'Laptops', 1250.00, 1250.00),
    (1042, '2024-08-01', 'Narek', 'Manukyan', '1992-09-03', 1679.38, '2022-02-28', 'Vahe', 'Sahakyan', '1987-06-04', 'Audio', 149.90, 149.90),
    (1031, '2024-08-02', 'Aram', 'Vardanyan', '1997-12-09', 3564.77, '2024-01-30', 'Gor', 'Mkrtchyan', '1990-03-15', 'Storage', 74.00, 148.00),
    (1011, '2024-08-03', 'Narek', 'Manukyan', '1992-09-03', 1679.38, '2022-02-28', 'Vahe', 'Sahakyan', '1987-06-04', 'Accessories', 25.50, 25.50),
    (1025, '2024-08-03', 'Narek', 'Manukyan', '1992-09-03', 1679.38, '2022-02-28', 'Nare', 'Ghazaryan', '1996-10-19', 'Keyboards', 89.99, 89.99),
    (1034, '2024-08-03', 'Aram', 'Vardanyan', '1997-12-09', 3564.77, '2024-01-30', 'Ani', 'Harutyunyan', '1994-08-22', 'Keyboards', 89.99, 269.97),
    (1003, '2024-08-05', 'Mariam', 'Hakobyan', '1995-02-07', 2834.98, '2023-03-20', 'Nare', 'Ghazaryan', '1996-10-19', 'Laptops', 1250.00, 1250.00),
    (1023, '2024-08-05', 'Mariam', 'Hakobyan', '1995-02-07', 2834.98, '2023-03-20', 'Gor', 'Mkrtchyan', '1990-03-15', 'Monitors', 320.00, 320.00),
    (1028, '2024-08-06', 'Aram', 'Vardanyan', '1997-12-09', 3564.77, '2024-01-30', 'Ani', 'Harutyunyan', '1994-08-22', 'Storage', 74.00, 148.00),
    (1013, '2024-08-07', 'Davit', 'Petrosyan', '1988-11-23', 8083.49, '2021-09-14', 'Gor', 'Mkrtchyan', '1990-03-15', 'Laptops', 1250.00, 1250.00),
    (1021, '2024-08-07', 'Sona', 'Karapetyan', '1986-05-25', 7500.00, '2021-04-17', 'Nare', 'Ghazaryan', '1996-10-19', 'Laptops', 1250.00, 2500.00),
    (1022, '2024-08-07', 'Anna', 'Sargsyan', '1991-04-12', 4189.99, '2022-06-01', 'Vahe', 'Sahakyan', '1987-06-04', 'Keyboards', 89.99, 89.99),
    (1006, '2024-08-08', 'Davit', 'Petrosyan', '1988-11-23', 8083.49, '2021-09-14', 'Gor', 'Mkrtchyan', '1990-03-15', 'Laptops', 1250.00, 1250.00),
    (1029, '2024-08-08', 'Mariam', 'Hakobyan', '1995-02-07', 2834.98, '2023-03-20', 'Ani', 'Harutyunyan', '1994-08-22', 'Keyboards', 89.99, 179.98),
    (1010, '2024-08-09', 'Lusine', 'Avetisyan', '1999-01-18', 960.00, '2023-08-11', 'Gor', 'Mkrtchyan', '1990-03-15', 'Monitors', 320.00, 960.00),
    (1015, '2024-08-09', 'Sona', 'Karapetyan', '1986-05-25', 7500.00, '2021-04-17', 'Ani', 'Harutyunyan', '1994-08-22', 'Laptops', 1250.00, 3750.00),
    (1032, '2024-08-09', 'Davit', 'Petrosyan', '1988-11-23', 8083.49, '2021-09-14', 'Gor', 'Mkrtchyan', '1990-03-15', 'Laptops', 1250.00, 2500.00),
    (1008, '2024-08-10', 'Tigran', 'Grigoryan', '1983-07-30', 2394.70, '2020-11-05', 'Ani', 'Harutyunyan', '1994-08-22', 'Storage', 74.00, 222.00),
    (1038, '2024-08-10', 'Tigran', 'Grigoryan', '1983-07-30', 2394.70, '2020-11-05', 'Gor', 'Mkrtchyan', '1990-03-15', 'Laptops', 1250.00, 1250.00),
    (1039, '2024-08-12', 'Narek', 'Manukyan', '1992-09-03', 1679.38, '2022-02-28', 'Ani', 'Harutyunyan', '1994-08-22', 'Storage', 74.00, 74.00),
    (1004, '2024-08-13', 'Davit', 'Petrosyan', '1988-11-23', 8083.49, '2021-09-14', 'Gor', 'Mkrtchyan', '1990-03-15', 'Storage', 74.00, 148.00),
    (1012, '2024-08-13', 'Davit', 'Petrosyan', '1988-11-23', 8083.49, '2021-09-14', 'Gor', 'Mkrtchyan', '1990-03-15', 'Monitors', 320.00, 320.00),
    (1014, '2024-08-13', 'Anna', 'Sargsyan', '1991-04-12', 4189.99, '2022-06-01', 'Nare', 'Ghazaryan', '1996-10-19', 'Monitors', 320.00, 960.00),
    (1030, '2024-08-13', 'Tigran', 'Grigoryan', '1983-07-30', 2394.70, '2020-11-05', 'Ani', 'Harutyunyan', '1994-08-22', 'Accessories', 25.50, 76.50),
    (1033, '2024-08-14', 'Tigran', 'Grigoryan', '1983-07-30', 2394.70, '2020-11-05', 'Nare', 'Ghazaryan', '1996-10-19', 'Audio', 149.90, 149.90),
    (1037, '2024-08-15', 'Anna', 'Sargsyan', '1991-04-12', 4189.99, '2022-06-01', 'Vahe', 'Sahakyan', '1987-06-04', 'Laptops', 1250.00, 2500.00),
    (1041, '2024-08-16', 'Mariam', 'Hakobyan', '1995-02-07', 2834.98, '2023-03-20', 'Gor', 'Mkrtchyan', '1990-03-15', 'Storage', 74.00, 74.00),
    (1001, '2024-08-17', 'Aram', 'Vardanyan', '1997-12-09', 3564.77, '2024-01-30', 'Nare', 'Ghazaryan', '1996-10-19', 'Storage', 74.00, 148.00),
    (1019, '2024-08-17', 'Aram', 'Vardanyan', '1997-12-09', 3564.77, '2024-01-30', 'Ani', 'Harutyunyan', '1994-08-22', 'Accessories', 25.50, 51.00),
    (1007, '2024-08-19', 'Anna', 'Sargsyan', '1991-04-12', 4189.99, '2022-06-01', 'Vahe', 'Sahakyan', '1987-06-04', 'Monitors', 320.00, 640.00),
    (1027, '2024-08-19', 'Narek', 'Manukyan', '1992-09-03', 1679.38, '2022-02-28', 'Nare', 'Ghazaryan', '1996-10-19', 'Keyboards', 89.99, 89.99),
    (1002, '2024-08-20', 'Tigran', 'Grigoryan', '1983-07-30', 2394.70, '2020-11-05', 'Nare', 'Ghazaryan', '1996-10-19', 'Accessories', 25.50, 76.50),
    (1026, '2024-08-20', 'Davit', 'Petrosyan', '1988-11-23', 8083.49, '2021-09-14', 'Ani', 'Harutyunyan', '1994-08-22', 'Accessories', 25.50, 25.50),
    (1009, '2024-08-21', 'Aram', 'Vardanyan', '1997-12-09', 3564.77, '2024-01-30', 'Gor', 'Mkrtchyan', '1990-03-15', 'Laptops', 1250.00, 2500.00),
    (1020, '2024-08-21', 'Tigran', 'Grigoryan', '1983-07-30', 2394.70, '2020-11-05', 'Ani', 'Harutyunyan', '1994-08-22', 'Audio', 149.90, 299.80),
    (1035, '2024-08-21', 'Mariam', 'Hakobyan', '1995-02-07', 2834.98, '2023-03-20', 'Nare', 'Ghazaryan', '1996-10-19', 'Accessories', 25.50, 51.00),
    (1017, '2024-08-23', 'Sona', 'Karapetyan', '1986-05-25', 7500.00, '2021-04-17', 'Ani', 'Harutyunyan', '1994-08-22', 'Laptops', 1250.00, 1250.00),
    (1036, '2024-08-24', 'Davit', 'Petrosyan', '1988-11-23', 8083.49, '2021-09-14', 'Ani', 'Harutyunyan', '1994-08-22', 'Keyboards', 89.99, 89.99),
    (1040, '2024-08-24', 'Mariam', 'Hakobyan', '1995-02-07', 2834.98, '2023-03-20', 'Vahe', 'Sahakyan', '1987-06-04', 'Monitors', 320.00, 960.00),
    (1024, '2024-08-25', 'Tigran', 'Grigoryan', '1983-07-30', 2394.70, '2020-11-05', 'Vahe', 'Sahakyan', '1987-06-04', 'Monitors', 320.00, 320.00),
    (1018, '2024-08-26', 'Davit', 'Petrosyan', '1988-11-23', 8083.49, '2021-09-14', 'Gor', 'Mkrtchyan', '1990-03-15', 'Laptops', 1250.00, 2500.00);
SELECT count(*) FROM sales_raw;   -- 42
