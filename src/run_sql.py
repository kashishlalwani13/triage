"""Run a .sql file against the Supabase database in .env.

Usage:  python src/run_sql.py sql/schema.sql
If the last statement returns rows (like a check query), they are printed as a table.
"""

import sys

import pandas as pd
import psycopg

# Reuse the same .env reader as the connection check.
from check_connection import get_database_url


def run_sql_file(path: str) -> None:
    with open(path) as f:
        sql = f.read()

    # One connection = one transaction: if any statement fails, nothing is saved.
    with psycopg.connect(get_database_url()) as conn:
        cursor = conn.execute(sql)
        if cursor.description:   # the last statement returned rows
            columns = [col.name for col in cursor.description]
            print(pd.DataFrame(cursor.fetchall(), columns=columns).to_string(index=False))

    print(f"Ran {path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python src/run_sql.py <file.sql>")
    run_sql_file(sys.argv[1])
