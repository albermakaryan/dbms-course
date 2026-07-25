# Lab 01 — Setup & First Queries

**Week 01 — Why not just files?** · Database Systems & Data Platforms

Goal for today: leave this room with a working database connection and your
first successful SQL queries. Nothing here is graded.

---

## Part 1 — Connect DBeaver to the course PostgreSQL (20 min)

1. Download and install **DBeaver Community Edition**: <https://dbeaver.io/download/>
2. Open DBeaver → **Database ▸ New Database Connection ▸ PostgreSQL**.
3. Enter the course instance details (from the credentials handout / course page):

   | Field | Value |
   |---|---|
   | Host | `[COURSE DB HOST]` |
   | Port | `[COURSE DB PORT — usually 5432]` |
   | Database | `[COURSE DB NAME]` |
   | Username | `[YOUR USERNAME]` |
   | Password | `[YOUR PASSWORD]` |

   Or paste the full connection string: `[CONNECTION STRING]`

4. Click **Test Connection** (DBeaver will offer to download the driver — accept).
5. Open a SQL editor (**SQL Editor ▸ New SQL Editor**) and run:

   ```sql
   SELECT version();
   ```

   If you see a PostgreSQL version string, you're connected. 🎉

**Stuck?** Raise a hand — lab helpers are marked. Common issues: university
Wi-Fi blocking the port (use `[FALLBACK NETWORK / VPN NOTE]`), typo in the
password, wrong database name.

---

## Part 2 — The 5-minute diagnostic (not graded)

Answer on paper, honestly — this only tells us who already knows SQL so they
can become lab helpers. It does **not** affect your grade in any way.

1. Have you written SQL before? (never / a little / regularly)
2. Without running it, what does this return?
   `SELECT COUNT(*) FROM customers WHERE city = 'Lisbon';`
3. What's the difference between `WHERE` and `ORDER BY`, in one sentence each?

---

## Part 3 — First queries (rest of the lab)

The course database contains a generic e-commerce schema:

- `customers` (`customer_id`, `name`, `email`, `city`, `created_at`)
- `products` (`product_id`, `product_name`, `category`, `price`)
- `orders` (`order_id`, `customer_id`, `order_date`, `status`, `total_amount`)
- `order_items` (`order_id`, `product_id`, `quantity`, `unit_price`)

Open `starter.sql` in DBeaver and work through it. The exercises, for
reference:

### Exercises

1. **Look around.** Return the first 10 rows of `customers`. (`SELECT … LIMIT`)
2. **Pick columns.** Return only `name` and `city` for the first 20 customers.
3. **Filter.** All products in the category `'electronics'`.
4. **Filter, numerically.** All products with `price` greater than 50, cheapest
   first. (`WHERE` + `ORDER BY`)
5. **Sort descending.** The 5 most expensive products. (`ORDER BY … DESC LIMIT`)
6. **Combine filters.** Orders with status `'delivered'` placed on or after
   `2026-01-01`. (`AND`)
7. **Count.** How many customers are in the table? (`COUNT(*)`)
8. **Challenge.** The 10 largest orders by `total_amount` that are *not*
   cancelled, largest first. Before running it, write down in English what
   question this answers for the business.

### Before you leave

Show a lab helper your exercise 8 result — or, if time ran out, your
exercise 4 result. That's the whole exit ticket.

**Next week:** we stop querying tables someone else designed and start
designing our own.
