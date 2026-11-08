"""Create local JSON files, upload them, and invoke COPY through Snowflake SQL API."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import jwt
import requests
import snowflake.connector
from cryptography.hazmat.primitives import serialization
from dotenv import load_dotenv


def required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"Set {name} in the repository-root .env first.")
    return value


def make_jwt(account: str, user: str, private_key) -> str:
    # Snowflake JWT account/user claims use uppercase names. The account value
    # here should be the account identifier used by the Python connector.
    account_claim = account.split(".", 1)[0].upper()
    user_claim = user.upper()
    public_der = private_key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(public_der).digest()).decode("ascii")
    qualified_user = f"{account_claim}.{user_claim}"
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "iss": f"{qualified_user}.{fingerprint}",
            "sub": qualified_user,
            "iat": now,
            "exp": now + timedelta(minutes=10),
        },
        private_key,
        algorithm="RS256",
    )


def main() -> None:
    if not load_dotenv(override=False):
        raise SystemExit("Could not find .env. Copy .env.example to the repository root.")

    account = required_env("SNOWFLAKE_ACCOUNT")
    user = required_env("SNOWFLAKE_USER")
    key_setting = required_env("SNOWFLAKE_PRIVATE_KEY_FILE")
    key_path = Path(key_setting).expanduser()
    if not key_path.is_absolute():
        key_path = (Path(__file__).resolve().parents[1] / key_path).resolve()
    if not key_path.is_file():
        raise SystemExit(f"Private key not found: {key_path}")

    private_key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
    connector = snowflake.connector.connect(
        account=account,
        user=user,
        private_key_file=str(key_path),
        role=os.getenv("SNOWFLAKE_ROLE", "ADV_LAB").strip(),
        warehouse=os.getenv("SNOWFLAKE_WAREHOUSE", "ADV_WH").strip(),
        database=os.getenv("SNOWFLAKE_DATABASE", "ADV_ORDERS").strip(),
        schema="BRONZE",
        login_timeout=30,
    )

    try:
        with tempfile.TemporaryDirectory(prefix="snowflake_api_lab_") as temp_dir:
            temp_path = Path(temp_dir)
            with connector.cursor() as cursor:
                rows = cursor.execute(
                    "SELECT BATCH, PAYLOAD FROM ADV_ORDERS.BRONZE.VW_ORDER_EVENTS_SOURCE "
                    "ORDER BY BATCH, PAYLOAD:event_id::STRING"
                ).fetchall()

                for batch in (1, 2):
                    batch_rows = [row for row in rows if int(row[0]) == batch]
                    local_file = temp_path / f"events_batch{batch}.json"
                    with local_file.open("w", encoding="utf-8") as output:
                        for _, payload in batch_rows:
                            if isinstance(payload, str):
                                payload = json.loads(payload)
                            output.write(json.dumps(payload, separators=(",", ":")) + "\n")
                    file_uri = "file://" + local_file.as_posix()
                    escaped_uri = file_uri.replace("'", "''")
                    cursor.execute(
                        f"PUT '{escaped_uri}' @ADV_ORDERS.BRONZE.API_EVENTS_STAGE "
                        "AUTO_COMPRESS=TRUE OVERWRITE=TRUE"
                    )
                    print(f"Uploaded batch {batch}: {len(batch_rows)} rows")

        copy_sql = """COPY INTO ADV_ORDERS.BRONZE.API_EVENTS_RAW
FROM (
  SELECT $1, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, METADATA$START_SCAN_TIME
  FROM @ADV_ORDERS.BRONZE.API_EVENTS_STAGE
)
FILE_FORMAT = ADV_ORDERS.BRONZE.API_EVENTS_JSON
ON_ERROR = SKIP_FILE"""

        token = make_jwt(account, user, private_key)
        base_url = f"https://{account}.snowflakecomputing.com/api/v2/statements"
        headers = {
            "Authorization": f"Bearer {token}",
            "X-Snowflake-Authorization-Token-Type": "KEYPAIR_JWT",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "AdvancedSnowflakeLab/1.0",
        }
        body = {
            "statement": copy_sql,
            "timeout": 60,
            "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE", "ADV_WH").strip(),
            "database": "ADV_ORDERS",
            "schema": "BRONZE",
            "role": os.getenv("SNOWFLAKE_ROLE", "ADV_LAB").strip(),
        }

        response = requests.post(base_url, headers=headers, json=body, timeout=90)
        response.raise_for_status()
        result = response.json()
        if response.status_code == 202:
            handle = result.get("statementHandle")
            if not handle:
                raise RuntimeError(f"Async SQL API response omitted statementHandle: {result}")
            status_url = f"{base_url}/{handle}"
            deadline = time.monotonic() + 300
            while time.monotonic() < deadline:
                response = requests.get(status_url, headers=headers, timeout=30)
                if response.status_code == 202:
                    time.sleep(2)
                    continue
                response.raise_for_status()
                result = response.json()
                break
            else:
                raise TimeoutError(f"SQL API statement did not finish; handle: {handle}")

        print("SQL API COPY statement completed.")
        print(json.dumps(result, indent=2))
    finally:
        connector.close()


if __name__ == "__main__":
    main()
