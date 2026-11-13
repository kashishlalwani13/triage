"""Check that this computer can reach the Supabase database.

Run from the project folder:  python src/check_connection.py
It never prints DATABASE_URL, because that string contains the password.
"""

import os
import sys

import psycopg
from dotenv import load_dotenv


def get_database_url() -> str:
    # Read .env so the password stays out of the code.
    load_dotenv()
    url = os.getenv("DATABASE_URL")
    if not url:
        sys.exit("DATABASE_URL is missing. Copy .env.example to .env and fill it in.")
    return url


def main() -> None:
    url = get_database_url()
    try:
        with psycopg.connect(url, connect_timeout=10) as conn:
            answer = conn.execute("select 1").fetchone()[0]
            version = conn.execute("show server_version").fetchone()[0]
    except psycopg.OperationalError as error:
        # Usually a wrong password, a typo in the URL, or no internet.
        sys.exit(f"Could not connect to the database:\n{error}")

    print(f"Connected. select 1 returned: {answer}")
    print(f"PostgreSQL version: {version}")


if __name__ == "__main__":
    main()
