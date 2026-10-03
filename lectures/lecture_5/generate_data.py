"""Lecture 5 data: Lecture 4's shop, but an order can hold several products.

Reads the original one-product-per-order CSVs from ../lecture_3/data/ (never
modified; Lecture 4 began with byte-identical copies) and writes this
lecture's own files to data/:

  customers.csv    same 30 customers; moneySpent recomputed from the new totals
  employees.csv    unchanged (managerID is added by steps/00-setup.sql)
  products.csv     unchanged
  orders.csv       one row per ORDER -- the header: who, when, where, status,
                   orderTotal. No product columns any more.
  order_items.csv  one row per PRODUCT IN AN ORDER -- the lines
  all_inserts.sql  the same data as INSERT statements (fallback for \\copy)

What changes, and what deliberately doesn't:

  * Every Lecture 4 order keeps its original product as its first line
    (same productID, quantity, unitPrice, discountPct, line total).
  * About 4 in 10 orders get 1-3 more lines: products that are commonly
    bought together with the first one (a sleeve or mouse with a laptop,
    a cable or earbuds with a phone, ...). An added line uses the product's
    list price and the order's discountPct, like the first line.
  * lineTotal  = round(quantity * unitPrice * (100 - discountPct) / 100, 2)
    orderTotal = the sum of the order's lineTotals
    moneySpent = the sum of the customer's COMPLETED orderTotals
    (the same rules as Lecture 3's generator).
  * Unchanged, so the facts students know from Lecture 4 still hold: the 600
    orders and their customers, employees, dates, channels, statuses and
    ratings; Levon and Astghik have no orders; productID 35 (Ergonomic Chair
    Pro) is never added, so it is still never ordered; the 181 online orders
    still have no employee.
  * What DOES change: every total built from orderTotal (revenue, spend per
    customer, ...). The lecture's numbers come from this data.

Seeded: running it again reproduces the files byte for byte. Edit this
script, not the CSVs.
"""
import csv
import random
import shutil
from collections import defaultdict
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE.parent / "lecture_3" / "data"   # the original one-product-per-order data (Lecture 4 started from the same files)
OUT = HERE / "data"
SEED = 20241005
MULTI_LINE_SHARE = 0.40                 # share of orders that get extra lines
EXTRA_LINES = [(1, 0.6), (2, 0.3), (3, 0.1)]
NEVER_ADD = {35}                        # Ergonomic Chair Pro stays never-ordered

# What gets bought together with a product of each category (productIDs).
ADD_ONS = {
    "Laptops":     [2, 20, 21, 22, 5, 23, 3, 18, 28],
    "Phones":      [32, 34, 25, 26, 27, 24],
    "Tablets":     [32, 34, 18, 25, 26],
    "Monitors":    [33, 20, 21, 3, 18, 28],
    "Audio":       [32, 34, 27],
    "Keyboards":   [20, 21, 32],
    "Accessories": [32, 33, 24, 21],
    "Storage":     [32, 24, 22],
    "Webcams":     [22, 32, 33],
    "Printers":    [32, 33],
    "Cables":      [32, 33, 34, 24],
    "Networking":  [33, 32],
}


def money(x):
    return Decimal(x).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def line_total(qty, price, disc):
    return money(Decimal(qty) * Decimal(price) * (100 - Decimal(disc)) / 100)


def read(name):
    with open(SRC / name, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write(name, cols, rows):
    with open(OUT / name, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(cols)
        w.writerows([[r[c] for c in cols] for r in rows])


rng = random.Random(SEED)
customers = read("customers.csv")
employees = read("employees.csv")
products = read("products.csv")
old_orders = read("orders.csv")
prod = {int(p["productID"]): p for p in products}

# Lecture 4's CSV is not sorted by orderID; sort so the seed decides the same
# extra lines no matter how that file is ordered.
old_orders.sort(key=lambda o: int(o["orderID"]))

orders, items = [], []
for o in old_orders:
    first = int(o["productID"])
    disc = int(o["discountPct"])
    lines = [{"productID": first, "quantity": int(o["quantity"]),
              "unitPrice": o["unitPrice"], "discountPct": disc}]
    # sanity: the first line reproduces Lecture 4's orderTotal exactly
    assert line_total(lines[0]["quantity"], lines[0]["unitPrice"], disc) == money(o["orderTotal"]), o
    if rng.random() < MULTI_LINE_SHARE:
        n = rng.choices([k for k, _ in EXTRA_LINES], [w for _, w in EXTRA_LINES])[0]
        pool = [p for p in ADD_ONS[prod[first]["category"]] if p != first and p not in NEVER_ADD]
        for pid in rng.sample(pool, min(n, len(pool))):
            qty = rng.choice([1, 1, 1, 2]) if prod[pid]["category"] in ("Cables", "Storage") else 1
            lines.append({"productID": pid, "quantity": qty,
                          "unitPrice": prod[pid]["price"], "discountPct": disc})
    for ln in lines:
        ln["orderID"] = o["orderID"]
        ln["lineTotal"] = line_total(ln["quantity"], ln["unitPrice"], disc)
        items.append(ln)
    header = {k: o[k] for k in ["orderID", "customerID", "employeeID", "orderDate", "orderTime",
                                "channel", "paymentMethod", "status", "deliveryDate", "rating"]}
    header["orderTotal"] = sum(ln["lineTotal"] for ln in lines)
    orders.append(header)

# moneySpent = sum of completed orderTotals
spent = defaultdict(Decimal)
for o in orders:
    if o["status"] == "completed":
        spent[o["customerID"]] += o["orderTotal"]
for c in customers:
    c["moneySpent"] = money(spent[c["customerID"]])

assert not any(int(i["productID"]) in NEVER_ADD for i in items)
assert len(orders) == 600 and len({(i["orderID"], i["productID"]) for i in items}) == len(items)

OUT.mkdir(exist_ok=True)
CUST_COLS = list(customers[0].keys())
EMP_COLS = list(employees[0].keys())
PROD_COLS = list(products[0].keys())
ORD_COLS = ["orderID", "customerID", "employeeID", "orderDate", "orderTime", "channel",
            "paymentMethod", "status", "deliveryDate", "rating", "orderTotal"]
ITEM_COLS = ["orderID", "productID", "quantity", "unitPrice", "discountPct", "lineTotal"]
write("customers.csv", CUST_COLS, customers)
shutil.copyfile(SRC / "employees.csv", OUT / "employees.csv")   # unchanged: copy as is
shutil.copyfile(SRC / "products.csv", OUT / "products.csv")
write("orders.csv", ORD_COLS, orders)
write("order_items.csv", ITEM_COLS, items)


def sql_value(v):
    if v == "" or v is None:
        return "NULL"
    if isinstance(v, (int, Decimal)):
        return str(v)
    try:
        Decimal(v)
        return v
    except Exception:
        return "'" + str(v).replace("'", "''") + "'"


def inserts(table, cols, rows):
    out = [f"INSERT INTO {table} ({', '.join(cols)}) VALUES"]
    out.append(",\n".join("  (" + ", ".join(sql_value(r[c]) for c in cols) + ")" for r in rows) + ";")
    return "\n".join(out)


with open(OUT / "all_inserts.sql", "w", encoding="utf-8") as f:
    f.write("-- Lecture 5 data as INSERT statements: the fallback if \\copy doesn't work.\n"
            "-- Generated by generate_data.py -- edit that, not this file.\n\n")
    f.write(inserts("customers", CUST_COLS, customers) + "\n\n")
    f.write(inserts("employees", EMP_COLS, employees) + "\n\n")
    f.write(inserts("products", PROD_COLS, products) + "\n\n")
    f.write(inserts("orders", ORD_COLS, orders) + "\n\n")
    f.write(inserts("order_items", ITEM_COLS, items) + "\n")

multi = sum(1 for o in orders if sum(1 for i in items if i["orderID"] == o["orderID"]) > 1)
done = [o for o in orders if o["status"] == "completed"]
print(f"orders: {len(orders)}  lines: {len(items)}  multi-line orders: {multi}  "
      f"completed revenue: {sum(o['orderTotal'] for o in done)}")
