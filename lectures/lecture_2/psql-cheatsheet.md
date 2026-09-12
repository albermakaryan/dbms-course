# psql Cheat Sheet

**The PostgreSQL command-line client.** Everything below runs *inside* a
`psql` session unless it's marked as a shell command (`$`).

## Quick start for this course

```bash
$ cd lectures/lecture_2      # \copy paths below assume this
$ createdb lecture02         # one time only — see steps/00-create-database.sql
$ psql lecture02
```

```
lecture02=# \i steps/01-01-load.sql
lecture02=# \i steps/01-02-explore.sql
```

Local install fighting you — missing role, port conflicts, multiple
clusters? Skip it with Docker instead: see "Running Postgres in Docker"
below. You still use your own `psql` client either way; only the
*server* changes.

## Connecting

| Command (shell) | What it does |
|---|---|
| `psql` | Connect using defaults: your OS username as both the role and the database |
| `psql dbname` | Connect to `dbname` as your OS username |
| `psql -U user dbname` | Connect to `dbname` as a specific role |
| `psql -U user -d dbname -h host -p port` | Full form — role, database, host, port |
| `psql -U user -W dbname` | Force a password prompt |
| `psql "postgresql://user:pass@host:5432/dbname"` | Connect via a connection URI |

Once you're in:

| Command | What it does |
|---|---|
| `\c dbname` | Switch to a different database, same role |
| `\c dbname user` | Switch database **and** role |
| `\conninfo` | Show what you're currently connected to |
| `\q` | Quit psql |

## Databases

```sql
CREATE DATABASE lecture02;
DROP DATABASE lecture02;              -- no confirmation, no undo
```

Shell equivalents — same result, no need to open psql first:

```bash
$ createdb lecture02
$ dropdb lecture02
```

## Roles and permissions

A **role** is Postgres's account. A role created `WITH LOGIN` is what
people casually call a "user" — same thing, just a role with permission
to connect.

```sql
-- create
CREATE ROLE alber WITH LOGIN PASSWORD 'a-real-password';
CREATE ROLE alber WITH LOGIN SUPERUSER;              -- full admin, bypasses every check
CREATE ROLE readonly WITH LOGIN;                     -- can connect, nothing else yet

-- inspect
\du                                                   -- list roles (psql meta-command)
SELECT rolname, rolsuper, rolcreatedb FROM pg_roles;  -- same info, as a query

-- change
ALTER ROLE alber WITH PASSWORD 'a-new-password';
ALTER ROLE alber WITH CREATEDB;                       -- grant one privilege
ALTER ROLE alber WITH NOSUPERUSER;                    -- take one away

-- grant access to specific things, instead of full SUPERUSER
GRANT ALL PRIVILEGES ON DATABASE lecture02 TO alber;
GRANT SELECT ON customers TO readonly;
REVOKE SELECT ON customers FROM readonly;

-- remove (fails if the role still owns something — reassign or drop that first)
DROP ROLE alber;
```

Shell equivalents:

```bash
$ createuser --interactive alber   # prompts: superuser? createdb? createrole?
$ dropuser alber
```

Common role attributes, for the `CREATE ROLE` / `ALTER ROLE` options above:

| Attribute | Meaning |
|---|---|
| `LOGIN` | Can connect at all. A role *without* this can still own objects or group other roles, just never connect directly |
| `SUPERUSER` | Bypasses every permission check — powerful, use sparingly outside a scratch setup |
| `CREATEDB` | Can create new databases |
| `CREATEROLE` | Can create and alter other roles |
| `PASSWORD 'x'` | Sets a password — needed if a client authenticates by password rather than by OS user |

> **Why the role has to match your OS username locally:** a default local
> PostgreSQL install authenticates the socket connection `psql` uses via
> **peer** auth — it checks that the role you're connecting as matches
> the Linux user running the command, no password involved. That's why
> plain `psql` with no `-U` tries to log in as a role named exactly after
> your OS username, and why `FATAL: role "..." does not exist` is the
> single most common first error — see Troubleshooting below.

## Looking around — what's in this database?

| Command | What it does |
|---|---|
| `\l` | List all databases |
| `\dt` | List tables in the current schema |
| `\dt+` | Same, with size and description |
| `\d tablename` | Describe a table: columns, types, keys, constraints |
| `\d+ tablename` | Same, with storage details |
| `\dn` | List schemas |
| `\dv` | List views |
| `\df` | List functions |
| `\di` | List indexes |
| `\du` | List roles and their privileges |

## Running files and moving data

| Command | What it does |
|---|---|
| `\i path/to/file.sql` | Run a `.sql` file — path is relative to psql's working directory |
| `\o path/to/file.txt` | Redirect all query output to a file (`\o` alone turns it back off) |
| `\copy table FROM 'file.csv' WITH (FORMAT csv, HEADER true)` | Load a CSV into a table |
| `\copy table TO 'file.csv' WITH (FORMAT csv, HEADER true)` | Export a table to a CSV |

> `\copy` runs on **your** machine — file paths are relative to wherever
> you started `psql`. Plain SQL `COPY` (no backslash) runs on the
> **database server** instead and looks for the file there — almost
> never what you want when you're working on your own laptop.

## Making output readable

| Command | What it does |
|---|---|
| `\x` | Toggle expanded display — one column per line; essential for wide rows |
| `\x auto` | Expanded only when a row wouldn't fit on screen (good default) |
| `\timing` | Toggle showing how long each query took |
| `\pset pager off` | Stop long results from opening in `less` |
| `\pset null '∅'` | Show a visible symbol for `NULL` instead of a blank |

## Editing and history

| Command | What it does |
|---|---|
| ↑ / ↓ | Walk through command history |
| `\e` | Open the last query in `$EDITOR`; running it on save + exit |
| `Ctrl+C` | Cancel whatever you're currently typing |
| `Ctrl+D` | Exit — same as `\q` |
| `Tab` | Autocomplete table, column and keyword names |

## Getting help

| Command | What it does |
|---|---|
| `\?` | Help on psql's own backslash commands |
| `\h` | List all SQL commands with syntax help available |
| `\h CREATE TABLE` | Syntax help for one specific SQL command |

## Running Postgres in Docker

A disposable server, completely separate from anything already
installed on your machine — no role to create, no cluster/port
conflicts, and "reinstalling" is one command. You still connect with
your normal `psql` client; only the server lives in a container. `\copy`
is unaffected — it reads local files on *your* machine regardless of
where the server is, since the file never has to be visible to the
container.

```bash
$ docker run --name lecture02-db \
    -e POSTGRES_PASSWORD=lecture02 \
    -e POSTGRES_DB=lecture02 \
    -p 5544:5432 \
    -d postgres:16

$ export PGPASSWORD=lecture02   # avoids a password prompt every time
$ psql -h localhost -p 5544 -U postgres -d lecture02
```

Managing the container:

| Command | What it does |
|---|---|
| `docker stop lecture02-db` | Stop it — data is kept |
| `docker start lecture02-db` | Start it again |
| `docker logs lecture02-db` | See the server's own log output |
| `docker rm -f lecture02-db` | Delete it completely — your "reinstall" button |

By default the data lives *inside* the container, so `docker rm` also
erases it — fine for a scratch lecture database, but if you want the
data to survive being removed and recreated, add a named volume to the
`docker run` command: `-v lecture02-data:/var/lib/postgresql/data`.

## Troubleshooting

**`FATAL: role "yourname" does not exist`** — psql defaults to
connecting as a role named after your OS username, and a fresh
PostgreSQL install only creates the `postgres` role, not yours. Fix it
once, from your own terminal (it'll ask for your **login** password,
not a database one):

```bash
$ sudo -u postgres psql -c "CREATE ROLE yourname WITH LOGIN SUPERUSER;" -c "CREATE DATABASE yourname OWNER yourname;"
```

**`FATAL: database "yourname" does not exist`** — same root cause,
missing default database; the command above fixes both at once.

**More than one PostgreSQL version installed** (common after installing
pgAdmin, which can pull in its own server as a dependency) — each
version runs its own **cluster** on its own port, and plain `psql` only
talks to one of them. Check what you actually have:

```bash
$ pg_lsclusters
Ver Cluster Port Status Owner    Data directory
14  main    5432 online postgres /var/lib/postgresql/14/main
16  main    5433 online postgres /var/lib/postgresql/16/main
```

Connect to a specific one with `-p`: `psql -p 5433 lecture02`. This is a
configuration mix-up, not a broken install — there's rarely a need to
uninstall anything to fix it.

**A query is hanging and `Ctrl+C` isn't helping** — `Ctrl+C` cancels
what you're *typing*, not a query already sent to the server. Open a
second terminal, connect, and run:

```sql
SELECT pid, query FROM pg_stat_activity;   -- find the pid
SELECT pg_cancel_backend(pid);             -- stop that one query
```
