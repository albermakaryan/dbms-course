#!/usr/bin/env python3
"""
Generate the Lecture 3 dataset: four normalized tables for a small
electronics shop, plus the flat one-row-per-sale file they collapse into.
Deterministic (fixed seed): re-running reproduces byte-identical CSVs.

    python3 generate_data.py          # writes into data/

The shop is the one from Lectures 1-2, a year later: same first
customers, employees and product categories (ids 1-8 / 1-4 / the six
original categories), but the business grew and so did every table.

Things a lecture query relies on -- keep them if you edit:
  * 600 orders across all of 2024. Shop closed on Sundays. Busier in
    Sep, Nov and especially Dec. Online orders arrive at any hour;
    in-store ones between 10:00 and 19:59.
  * orders.status: ~88% completed, ~7% returned, ~5% cancelled.
    "Revenue" means completed orders only -- the drill depends on it.
  * orders.channel: ~30% online. Online orders have NO employee
    (employeeID NULL), a deliveryDate, and never pay cash. In-store
    orders have an employee and no deliveryDate.
  * orders.rating: only completed orders, and only ~60% of those.
  * orderTotal = round(quantity * unitPrice * (100 - discountPct) / 100, 2).
    unitPrice equals the product's list price.
  * customers.moneySpent = sum of that customer's COMPLETED orderTotals.
  * Two customers are both named Anna Sargsyan (different birth dates,
    different emails). A third Sargsyan (Mher) shares only the surname.
  * Seven customers have no anniversary; four have no phone. Nobody has
    a NULL birth date, email, city or signup date.
  * Two customers (Levon Arakelyan, Astghik Danielyan) never ordered.
    One product (Ergonomic Chair Pro -- the whole Chairs category) never
    sold. One product (Logitech K380) is discontinued: isActive = false,
    sold only Jan-Jun.
  * Row order in sales_flat.csv and orders.csv is shuffled, so LIMIT
    without ORDER BY visibly returns "whatever came first".
"""
import csv, random, datetime as dt
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from collections import Counter

random.seed(2024)
OUT = Path(__file__).parent / "data"
OUT.mkdir(exist_ok=True)
N_ORDERS = 600
YEAR = 2024

def money(x):
    return Decimal(x).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

def pick(rows, weights):
    return random.choices(rows, weights=weights, k=1)[0]

# ---- Customers -----------------------------------------------------------
# (customerID, firstName, lastName, birthDate, anniversary|None, activity weight)
_customers = [
    (1,  "Anna",    "Sargsyan",      "1991-04-12", "2022-06-01", 1.6),
    (2,  "Davit",   "Petrosyan",     "1988-11-23", "2021-09-14", 3.0),
    (3,  "Mariam",  "Hakobyan",      "1995-02-07", "2023-03-20", 1.2),
    (4,  "Tigran",  "Grigoryan",     "1983-07-30", "2020-11-05", 1.8),
    (5,  "Lusine",  "Avetisyan",     "1999-01-18", "2023-08-11", 0.3),
    (6,  "Narek",   "Manukyan",      "1992-09-03", "2022-02-28", 1.4),
    (7,  "Sona",    "Karapetyan",    "1986-05-25", "2021-04-17", 0.8),
    (8,  "Aram",    "Vardanyan",     "1997-12-09", "2024-01-30", 1.5),
    (9,  "Hayk",    "Melikyan",      "1993-03-30", None,         0.9),
    (10, "Lilit",   "Hovhannisyan",  "1990-06-14", "2019-05-05", 1.1),
    (11, "Anna",    "Sargsyan",      "1978-10-02", None,         0.7),   # same name as #1
    (12, "Armen",   "Gevorgyan",     "1985-12-01", "2015-09-09", 2.2),
    (13, "Gayane",  "Mnatsakanyan",  "1996-04-22", None,         0.5),
    (14, "Vahan",   "Torosyan",      "1989-08-08", "2018-10-10", 1.0),
    (15, "Arpine",  "Simonyan",      "2000-02-29", None,         0.6),
    (16, "Karen",   "Khachatryan",   "1982-01-15", "2012-06-30", 2.5),
    (17, "Nane",    "Galstyan",      "1998-11-11", None,         0.4),
    (18, "Ruben",   "Asatryan",      "1975-03-03", "2005-08-20", 1.3),
    (19, "Tatev",   "Martirosyan",   "1994-07-19", "2020-02-14", 0.9),
    (20, "Artur",   "Baghdasaryan",  "1987-09-27", "2016-12-24", 1.7),
    (21, "Meline",  "Poghosyan",     "1992-05-05", None,         0.8),
    (22, "Suren",   "Hayrapetyan",   "1980-10-30", "2010-04-01", 1.1),
    (23, "Ani",     "Stepanyan",     "1997-01-09", "2023-11-11", 0.5),
    (24, "Levon",   "Arakelyan",     "1984-06-21", "2014-07-07", 0.0),   # never ordered
    (25, "Hasmik",  "Zakaryan",      "1991-02-14", "2021-06-19", 1.0),
    (26, "Samvel",  "Nazaryan",      "1979-12-12", "2006-03-15", 0.6),
    (27, "Diana",   "Aleksanyan",    "1999-09-09", None,         0.2),
    (28, "Gevorg",  "Kocharyan",     "1986-03-17", "2017-05-27", 1.2),
    (29, "Astghik", "Danielyan",     "1995-08-02", "2022-09-03", 0.0),   # never ordered
    (30, "Mher",    "Sargsyan",      "1983-04-04", "2013-10-18", 0.7),   # surname only
]
cities  = ["Yerevan", "Gyumri", "Vanadzor", "Abovyan", "Kapan"]
city_w  = [0.60, 0.15, 0.10, 0.08, 0.07]
domains = ["gmail.com", "mail.ru", "yahoo.com", "outlook.com"]
no_phone = {5, 13, 21, 27}

customers = []
for (cid, first, last, birth, anniv, w) in _customers:
    email = f"{first.lower()}.{last.lower()}@{pick(domains, [0.55, 0.25, 0.1, 0.1])}"
    if cid == 11:
        email = "anna.sargsyan78@mail.ru"
    phone = None if cid in no_phone else f"+374 {random.choice([91,93,94,95,96,98,99])} {random.randint(100000, 999999)}"
    signup = dt.date(random.randint(2019, 2023), random.randint(1, 12), random.randint(1, 28))
    customers.append(dict(customerID=cid, firstName=first, lastName=last, email=email,
                          phone=phone, city=pick(cities, city_w), birthDate=birth,
                          signupDate=signup, anniversary=anniv, weight=w))

# ---- Employees -----------------------------------------------------------
# (employeeID, first, last, birthDate, hireDate, position, branch, salary, in-store weight)
_employees = [
    (1, "Gor",    "Mkrtchyan",    "1990-03-15", "2019-04-01", "Senior Sales",    "Yerevan Center", 1400, 0.20),
    (2, "Ani",    "Harutyunyan",  "1994-08-22", "2020-09-15", "Sales Associate", "Yerevan Center", 1100, 0.22),
    (3, "Vahe",   "Sahakyan",     "1987-06-04", "2017-02-01", "Store Manager",   "Yerevan Center", 1900, 0.08),
    (4, "Nare",   "Ghazaryan",    "1996-10-19", "2022-06-10", "Sales Associate", "Yerevan Mall",   1000, 0.15),
    (5, "Hayk",   "Melikyan",     "1985-02-11", "2018-11-05", "Senior Sales",    "Yerevan Mall",   1350, 0.12),
    (6, "Lilit",  "Hovhannisyan", "1998-07-07", "2023-03-20", "Sales Associate", "Yerevan Mall",    950, 0.07),
    (7, "Arman",  "Grigoryan",    "1992-12-30", "2021-01-11", "Sales Associate", "Gyumri",          900, 0.08),
    (8, "Marine", "Avagyan",      "1989-05-18", "2016-08-01", "Senior Sales",    "Gyumri",         1300, 0.08),
]
employees = [dict(employeeID=e[0], firstName=e[1], lastName=e[2],
                  email=f"{e[1].lower()}.{e[2].lower()}@techshop.am",
                  birthDate=e[3], hireDate=e[4], position=e[5], branch=e[6],
                  salary=money(e[7]), weight=e[8]) for e in _employees]

# ---- Products ------------------------------------------------------------
# (productID, productName, category, brand, price, cost, weight, big-ticket?)
_products = [
    (1,  "ThinkPad X1 Carbon",     "Laptops",     "Lenovo",   "1250.00", "980.00", 0.030, True),
    (2,  "Laptop Sleeve 14",       "Accessories", "Generic",  "25.50",   "10.00",  0.050, False),
    (3,  "MX Keys",                "Keyboards",   "Logitech", "89.99",   "55.00",  0.045, False),
    (4,  "UltraSharp 27",          "Monitors",    "Dell",     "320.00",  "240.00", 0.030, True),
    (5,  "Portable SSD T7 1TB",    "Storage",     "Samsung",  "74.00",   "52.00",  0.050, False),
    (6,  "WH-1000XM5",             "Audio",       "Sony",     "299.00",  "220.00", 0.025, False),
    (7,  "MacBook Air 13",         "Laptops",     "Apple",    "1100.00", "900.00", 0.025, True),
    (8,  "Aspire 5",               "Laptops",     "Acer",     "620.00",  "500.00", 0.020, True),
    (9,  "ZenBook 14",             "Laptops",     "ASUS",     "890.00",  "720.00", 0.015, True),
    (10, "iPhone 15",              "Phones",      "Apple",    "799.00",  "650.00", 0.030, True),
    (11, "Galaxy S24",             "Phones",      "Samsung",  "699.00",  "540.00", 0.025, True),
    (12, "Redmi Note 13",          "Phones",      "Xiaomi",   "249.00",  "190.00", 0.030, True),
    (13, "Pixel 8",                "Phones",      "Google",   "599.00",  "470.00", 0.012, True),
    (14, "iPad 10th gen",          "Tablets",     "Apple",    "449.00",  "360.00", 0.025, True),
    (15, "Galaxy Tab S9",          "Tablets",     "Samsung",  "480.00",  "380.00", 0.015, True),
    (16, "Odyssey G5 32",          "Monitors",    "Samsung",  "349.00",  "260.00", 0.020, True),
    (17, "ProArt 24",              "Monitors",    "ASUS",     "280.00",  "210.00", 0.015, True),
    (18, "K380",                   "Keyboards",   "Logitech", "39.99",   "22.00",  0.030, False),   # discontinued mid-year
    (19, "Huntsman Mini",          "Keyboards",   "Razer",    "119.00",  "75.00",  0.020, False),
    (20, "MX Master 3S",           "Accessories", "Logitech", "99.00",   "60.00",  0.035, False),
    (21, "M185",                   "Accessories", "Logitech", "14.99",   "7.00",   0.045, False),
    (22, "USB-C Hub 7-in-1",       "Accessories", "Anker",    "45.00",   "25.00",  0.040, False),
    (23, "Expansion HDD 2TB",      "Storage",     "Seagate",  "64.00",   "45.00",  0.030, False),
    (24, "USB Flash 128GB",        "Storage",     "SanDisk",  "14.50",   "8.00",   0.045, False),
    (25, "AirPods Pro",            "Audio",       "Apple",    "249.00",  "190.00", 0.030, False),
    (26, "Soundcore Q30",          "Audio",       "Anker",    "79.00",   "48.00",  0.030, False),
    (27, "Flip 6",                 "Audio",       "JBL",      "129.00",  "85.00",  0.025, False),
    (28, "C920",                   "Webcams",     "Logitech", "59.00",   "38.00",  0.035, False),
    (29, "Brio 4K",                "Webcams",     "Logitech", "149.00",  "100.00", 0.015, False),
    (30, "PIXMA TS3450",           "Printers",    "Canon",    "210.00",  "150.00", 0.015, True),
    (31, "LaserJet M110",          "Printers",    "HP",       "149.00",  "105.00", 0.015, True),
    (32, "USB-C Cable 1m",         "Cables",      "Anker",    "9.90",    "3.00",   0.060, False),
    (33, "HDMI 2.1 Cable 2m",      "Cables",      "Generic",  "12.90",   "4.00",   0.045, False),
    (34, "Lightning Cable",        "Cables",      "Apple",    "19.00",   "8.00",   0.035, False),
    (35, "Ergonomic Chair Pro",    "Chairs",      "Generic",  "185.00",  "120.00", 0.000, True),    # never sold
    (36, "Archer AX55 Router",     "Networking",  "TP-Link",  "89.00",   "60.00",  0.025, False),
    (37, "Powerline Kit",          "Networking",  "TP-Link",  "55.00",   "35.00",  0.013, False),
]
products = []
for p in _products:
    pid = p[0]
    products.append(dict(productID=pid, productName=p[1], category=p[2], brand=p[3],
                         price=money(p[4]), cost=money(p[5]), weight=p[6], big=p[7],
                         stockQuantity=random.choice([0, 0, 3, 5, 8, 12, 15, 20, 25, 30, 40, 60]),
                         isActive=(pid != 18)))
products[34]["stockQuantity"] = 6        # the chair is in stock, just unsold

# ---- Orders --------------------------------------------------------------
month_w = {1: .07, 2: .06, 3: .08, 4: .07, 5: .08, 6: .07,
           7: .07, 8: .08, 9: .10, 10: .08, 11: .10, 12: .14}

def random_open_day(month):
    first = dt.date(YEAR, month, 1)
    nxt = dt.date(YEAR + (month == 12), month % 12 + 1, 1)
    days = [first + dt.timedelta(d) for d in range((nxt - first).days)]
    return random.choice([d for d in days if d.weekday() != 6])   # Sunday closed

def random_time(online):
    if online:
        hour = pick(range(24), [1,1,1,1,1,1,2,3,4,5,5,5,5,5,5,5,6,7,8,9,9,8,6,3])
    else:
        hour = pick(range(10, 20), [4,6,7,7,6,6,7,8,8,5])
    return dt.time(hour, random.randint(0, 59), random.randint(0, 59))

cust_w = [c["weight"] for c in customers]
emp_w  = [e["weight"] for e in employees]

raw = []
for _ in range(N_ORDERS):
    month = pick(list(month_w), list(month_w.values()))
    date  = random_open_day(month)
    prod_w = [p["weight"] if (p["isActive"] or month <= 6) else 0 for p in products]
    p = pick(products, prod_w)
    c = pick(customers, cust_w)
    online = random.random() < 0.30
    e = None if online else pick(employees, emp_w)
    qty = pick([1, 2], [0.9, 0.1]) if p["big"] else pick([1, 2, 3], [0.5, 0.3, 0.2])
    disc = pick([0, 5, 10, 15, 20], [0.75, 0.10, 0.08, 0.05, 0.02])
    status = pick(["completed", "returned", "cancelled"], [0.88, 0.07, 0.05])
    payment = pick(["card", "transfer"], [0.85, 0.15]) if online else pick(["cash", "card", "transfer"], [0.45, 0.50, 0.05])
    delivery = None
    if online and status != "cancelled":
        delivery = date + dt.timedelta(days=random.randint(1, 7))
    rating = None
    if status == "completed" and random.random() < 0.60:
        rating = pick([1, 2, 3, 4, 5], [0.03, 0.05, 0.12, 0.35, 0.45])
    total = money(qty * p["price"] * (100 - disc) / 100)
    raw.append(dict(orderDate=date, orderTime=random_time(online), cust=c, emp=e, prod=p,
                    quantity=qty, unitPrice=p["price"], discountPct=disc, orderTotal=total,
                    channel="online" if online else "in_store", paymentMethod=payment,
                    status=status, deliveryDate=delivery, rating=rating))

raw.sort(key=lambda o: (o["orderDate"], o["orderTime"]))     # ids follow the clock
orders = []
for i, o in enumerate(raw, start=1001):
    orders.append(dict(orderID=i, **o))

spent = {c["customerID"]: Decimal("0.00") for c in customers}
for o in orders:
    if o["status"] == "completed":
        spent[o["cust"]["customerID"]] += o["orderTotal"]

# ---- Write CSVs ----------------------------------------------------------
def d(x):        # None -> empty field, which \copy (FORMAT csv) reads as NULL
    return "" if x is None else x

shuffled = orders[:]
random.shuffle(shuffled)

FLAT_COLS = ["orderID", "orderDate", "orderTime", "channel", "status", "paymentMethod",
             "quantity", "unitPrice", "discountPct", "orderTotal", "deliveryDate", "rating",
             "customerFirstName", "customerLastName", "customerEmail", "customerCity",
             "customerBirthDate", "customerSignupDate", "customerAnniversary", "customerMoneySpent",
             "employeeFirstName", "employeeLastName", "employeePosition", "employeeBranch",
             "productName", "productCategory", "productBrand", "productPrice", "productCost"]

def flat_row(o):
    c, e, p = o["cust"], o["emp"], o["prod"]
    return [o["orderID"], o["orderDate"], o["orderTime"], o["channel"], o["status"], o["paymentMethod"],
            o["quantity"], o["unitPrice"], o["discountPct"], o["orderTotal"], o["deliveryDate"], o["rating"],
            c["firstName"], c["lastName"], c["email"], c["city"],
            c["birthDate"], c["signupDate"], c["anniversary"], spent[c["customerID"]],
            e["firstName"] if e else None, e["lastName"] if e else None,
            e["position"] if e else None, e["branch"] if e else None,
            p["productName"], p["category"], p["brand"], p["price"], p["cost"]]

CUST_COLS = ["customerID", "firstName", "lastName", "email", "phone", "city",
             "birthDate", "signupDate", "anniversary", "moneySpent"]
def cust_row(c):
    return [c["customerID"], c["firstName"], c["lastName"], c["email"], c["phone"], c["city"],
            c["birthDate"], c["signupDate"], c["anniversary"], spent[c["customerID"]]]

EMP_COLS = ["employeeID", "firstName", "lastName", "email", "birthDate", "hireDate", "position", "branch", "salary"]
def emp_row(e):
    return [e[k] for k in EMP_COLS]

PROD_COLS = ["productID", "productName", "category", "brand", "price", "cost", "stockQuantity", "isActive"]
def prod_row(p):
    return [p[k] for k in PROD_COLS]

ORD_COLS = ["orderID", "customerID", "employeeID", "productID", "quantity", "unitPrice", "discountPct",
            "orderTotal", "orderDate", "orderTime", "channel", "paymentMethod", "status", "deliveryDate", "rating"]
def ord_row(o):
    return [o["orderID"], o["cust"]["customerID"], o["emp"]["employeeID"] if o["emp"] else None,
            o["prod"]["productID"], o["quantity"], o["unitPrice"], o["discountPct"], o["orderTotal"],
            o["orderDate"], o["orderTime"], o["channel"], o["paymentMethod"], o["status"],
            o["deliveryDate"], o["rating"]]

def write_csv(name, cols, rows):
    with open(OUT / name, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for r in rows:
            w.writerow([("true" if v is True else "false" if v is False else d(v)) for v in r])

write_csv("sales_flat.csv", FLAT_COLS, [flat_row(o) for o in shuffled])
write_csv("customers.csv",  CUST_COLS, [cust_row(c) for c in customers])
write_csv("employees.csv",  EMP_COLS,  [emp_row(e) for e in employees])
write_csv("products.csv",   PROD_COLS, [prod_row(p) for p in products])
write_csv("orders.csv",     ORD_COLS,  [ord_row(o) for o in shuffled])

# ---- Fallback: the same rows as INSERT statements (no \copy needed) -------
def lit(v):
    if v is None or v == "":
        return "NULL"
    if v is True:  return "TRUE"
    if v is False: return "FALSE"
    if isinstance(v, (int, Decimal)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"

def insert_block(table, cols, rows):
    body = ",\n".join("    (" + ", ".join(lit(v) for v in r) + ")" for r in rows)
    return f"INSERT INTO {table} ({', '.join(cols)}) VALUES\n{body};\n\n"

with open(OUT / "all_inserts.sql", "w") as f:
    f.write("-- Fallback loader: the same rows as data/*.csv, as plain INSERTs.\n"
            "-- Use instead of the \\copy lines in steps/00-setup.sql if the CSV\n"
            "-- files aren't reachable. The tables must already exist (run the\n"
            "-- CREATE TABLE part of 00-setup.sql first). Generated by\n"
            "-- generate_data.py -- do not edit by hand.\n\n")
    f.write(insert_block("sales",     FLAT_COLS, [flat_row(o) for o in shuffled]))
    f.write(insert_block("customers", CUST_COLS, [cust_row(c) for c in customers]))
    f.write(insert_block("employees", EMP_COLS,  [emp_row(e) for e in employees]))
    f.write(insert_block("products",  PROD_COLS, [prod_row(p) for p in products]))
    f.write(insert_block("orders",    ORD_COLS,  [ord_row(o) for o in shuffled]))

# ---- Summary -------------------------------------------------------------
done = [o for o in orders if o["status"] == "completed"]
print(f"orders: {len(orders)}  completed: {len(done)}  revenue(completed): {sum(o['orderTotal'] for o in done)}")
print("status:", Counter(o["status"] for o in orders))
print("channel:", Counter(o["channel"] for o in orders), " payment:", Counter(o["paymentMethod"] for o in orders))
print("per month:", dict(sorted(Counter(o["orderDate"].month for o in orders).items())))
print("per category:", Counter(o["prod"]["category"] for o in orders).most_common())
print("per employee:", Counter(o["emp"]["lastName"] if o["emp"] else None for o in orders).most_common())
print("customers with orders:", len({o["cust"]["customerID"] for o in orders}), "of", len(customers))
print("rated:", sum(o["rating"] is not None for o in orders), " discounts:", Counter(o["discountPct"] for o in orders))
print("K380 months:", sorted({o["orderDate"].month for o in orders if o["prod"]["productID"] == 18}))
