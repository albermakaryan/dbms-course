-- ============================================================
-- TRAP 7: AND binds tighter than OR — inside ON too
--
-- Standalone: creates its own scratch tables, drops them at the end.
-- ============================================================

DROP TABLE IF EXISTS transfers_07, accounts_07 CASCADE;

CREATE TABLE accounts_07 (
    account_id INT PRIMARY KEY,
    owner      TEXT NOT NULL
);

CREATE TABLE transfers_07 (
    transfer_id INT PRIMARY KEY,
    account_id  INT NOT NULL REFERENCES accounts_07,
    method      TEXT NOT NULL,         -- 'card' or 'cash'
    flagged     BOOLEAN NOT NULL
);

INSERT INTO accounts_07 VALUES
    (1, 'Ann'),
    (2, 'Ben'),
    (3, 'Cid');

INSERT INTO transfers_07 VALUES
    (501, 1, 'card', false),
    (502, 2, 'cash', true),            -- flagged, and it belongs to Ben
    (503, 3, 'cash', false);


-- ---- The intent: each account's transfers that were by card OR flagged ----

-- ---- WRONG: no parentheses ----
SELECT a.owner, t.transfer_id, t.account_id AS transfer_belongs_to
FROM accounts_07 a
JOIN transfers_07 t ON t.account_id = a.account_id
                   AND t.method = 'card'
                    OR t.flagged
ORDER BY a.account_id, t.transfer_id;
-- WRONG: 4 rows
--   Ann | 501 | 1
--   Ann | 502 | 2      <- Ben's transfer, attached to Ann
--   Ben | 502 | 2
--   Cid | 502 | 2      <- Ben's transfer, attached to Cid
-- AND binds tighter, so this is
--   (t.account_id = a.account_id AND t.method = 'card') OR t.flagged
-- A flagged transfer satisfies the ON on its own, whatever the account:
-- it matches EVERY account.


-- ---- FIXED: parenthesize the OR ----
SELECT a.owner, t.transfer_id, t.account_id AS transfer_belongs_to
FROM accounts_07 a
JOIN transfers_07 t ON t.account_id = a.account_id
                   AND (t.method = 'card' OR t.flagged)
ORDER BY a.account_id, t.transfer_id;
-- FIXED: 2 rows
--   Ann | 501 | 1
--   Ben | 502 | 2
--
-- This is worse than the same mistake in WHERE. In WHERE it lets an
-- extra row through a filter; in ON it loosens the join key itself and
-- pairs rows that are not related at all.


DROP TABLE IF EXISTS transfers_07, accounts_07 CASCADE;

-- LESSON: whenever AND and OR appear together — in ON as much as in
-- WHERE — put parentheses around the OR, or the join key can stop
-- applying to some rows.
