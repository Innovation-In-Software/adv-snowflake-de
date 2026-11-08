"""Verify password-based connectivity using credentials from a discovered .env."""

from __future__ import annotations

import os

import snowflake.connector
from dotenv import load_dotenv


def main() -> None:
    if not load_dotenv(override=False):
        raise SystemExit("Could not find .env. Copy .env.example to the repository root.")

    required = ("SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PASSWORD")
    missing = [name for name in required if not os.getenv(name, "").strip()]
    if missing:
        raise SystemExit("Set these values in .env before continuing: " + ", ".join(missing))

    connection_parameters = {
        "account": os.environ["SNOWFLAKE_ACCOUNT"].strip(),
        "user": os.environ["SNOWFLAKE_USER"].strip(),
        "password": os.environ["SNOWFLAKE_PASSWORD"],
        "role": os.getenv("SNOWFLAKE_ROLE", "ACCOUNTADMIN").strip(),
        "login_timeout": 30,
    }

    connection = None
    try:
        connection = snowflake.connector.connect(**connection_parameters)
        row = connection.cursor().execute(
            "SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT()"
        ).fetchone()
        print("Snowflake connection confirmed.")
        print(f"User: {row[0]} | Role: {row[1]} | Account: {row[2]}")
    except snowflake.connector.errors.Error as exc:
        raise SystemExit(
            "Snowflake connection failed. Check account, username, password, network access, "
            "and whether this account permits password authentication. "
            f"Connector message: {exc}"
        ) from None
    finally:
        if connection is not None:
            connection.close()


if __name__ == "__main__":
    main()
