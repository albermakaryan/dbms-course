"""BEGIN ... ROLLBACK over several SQL cells in lecture-07-notebook.py.

marimo sends COMMIT after every SQL cell (see marimo/_sql/engines/dbapi.py,
DBAPIEngine.execute). So a BEGIN typed in one cell is committed before the
next cell runs, and a later ROLLBACK has nothing to undo.

psql_like(engine) is the same connection, but marimo's automatic COMMIT does
nothing: BEGIN, COMMIT and ROLLBACK happen only when you type them, as in psql.
Use it as engine=psql_like in the SQL cells of a hand-made transaction.
"""


class _OnlyTypedCommits:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self):
        return self._connection.cursor()

    def commit(self):
        # marimo calls this after every cell: ignore it.
        pass

    def rollback(self):
        self._connection.rollback()

    def close(self):
        # The notebook's connection stays open.
        pass


def psql_like(connection):
    """The same connection, without marimo's COMMIT after each cell."""
    return _OnlyTypedCommits(connection)
