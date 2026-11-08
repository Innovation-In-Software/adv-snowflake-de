"""Upload duplicate events and submit their file to the existing Snowpipe REST API."""

from __future__ import annotations

import base64
import hashlib
import uuid
import json
import os
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
    # JWT (JSON Web Token) consists of header.payload.signature.
    # The header names the signing algorithm; the payload carries identity/time
    # claims. These parts are encoded, not encrypted: never put secrets in them.
    # RS256 signs with our private key. Snowflake verifies the signature with the
    # public key registered on this user. The private key is never sent.
    # SNOWFLAKE_ACCOUNT in .env supplies the ORGNAME-ACCOUNTNAME identifier.
    # Snowflake requires uppercase account/user claims and hyphens for periods.
    # Reference: https://docs.snowflake.com/en/developer-guide/sql-api/authenticating
    account_claim = account.replace(".", "-").upper()
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
            "iss": f"{qualified_user}.{fingerprint}",  # Issuer: identity + public-key fingerprint
            "sub": qualified_user,  # Subject: the account and user being authenticated
            "iat": now,  # Issued at (UTC); PyJWT encodes this as a numeric timestamp
            "exp": now + timedelta(minutes=10),  # Short-lived credential: expires in 10 minutes
        },
        private_key,
        algorithm="RS256",
    )


PIPE = "ADV_ORDERS.BRONZE.ORDERS_PIPE"
FILE_NAME = "rest_api_replay.json.gz"
SOURCE_FILE = "batch2/" + FILE_NAME


def submit_file(base_url, headers):
    response = requests.post(
        base_url + "/insertFiles",
        params={"requestId": str(uuid.uuid4()), "showSkippedFiles": "true"},
        headers=headers,
        # Relative to the pipe's @EVENTS_STAGE/batch2/ location, NOT stage root.
        json={"files": [{"path": FILE_NAME}]},
        timeout=30,
    )
    response.raise_for_status()
    result = response.json()

    if result.get("responseCode") != "SUCCESS":
        raise RuntimeError(f"Snowpipe rejected the request: {result}")

    print("Snowpipe accepted the request; this does not confirm loading.")
    print(json.dumps(result, indent=2))


def wait_for_rows(cursor, base_url, headers):
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        response = requests.get(base_url + "/insertReport", headers=headers, timeout=30)
        response.raise_for_status()

        for entry in response.json().get("files", []):
            if entry.get("path") == FILE_NAME:
                if entry.get("errorsSeen", 0) or entry.get("status") in ("LOAD_FAILED", "PARTIALLY_LOADED"):
                    raise RuntimeError(f"Snowpipe load error: {entry}")

        # Durable verification also works on reruns after the REST report expires.
        count = cursor.execute("SELECT COUNT(*) FROM ADV_ORDERS.BRONZE.EVENTS_RAW WHERE SOURCE_FILE = %s", (SOURCE_FILE,)).fetchone()[0]

        if count == 4:
            print("Confirmed four replay deliveries in EVENTS_RAW.")
            return

        if count > 4:
            raise RuntimeError(f"Expected four rows for {SOURCE_FILE}, found {count}.")

        time.sleep(5)
    raise TimeoutError("Load not confirmed within five minutes. Inspect COPY_HISTORY and SYSTEM$PIPE_STATUS; do not rename the file to retry.")


def main() -> None:
    load_dotenv()

    account = required_env("SNOWFLAKE_ACCOUNT")
    user = required_env("SNOWFLAKE_USER")
    key_path = Path(required_env("SNOWFLAKE_PRIVATE_KEY_FILE")).expanduser()

    if not key_path.is_absolute():
        key_path = (Path(__file__).resolve().parents[1] / key_path).resolve()

    private_key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)

    connect_params = {"account": account, "user": user, "private_key_file": str(key_path),
                      "role": "ADV_LAB", "warehouse": "ADV_WH", "database": "ADV_ORDERS",
                      "schema" :"BRONZE", "login_timeout": 30}

    with snowflake.connector.connect(**connect_params) as connection, connection.cursor() as cursor:
        rows = cursor.execute(
            "SELECT PAYLOAD FROM ADV_ORDERS.BRONZE.VW_ORDER_EVENTS_SOURCE "
            "WHERE BATCH = 2 ORDER BY PAYLOAD:event_id::STRING"
        ).fetchall()

        if len(rows) != 4:
            raise RuntimeError("Expected four batch-2 events; complete Lab 01 first.")

        local_file = Path(__file__).resolve().parent / "rest_api_replay.json"
        payloads = [json.loads(r[0]) if isinstance(r[0], str) else r[0] for r in rows]
        content = "".join(json.dumps(p, separators=(",", ":")) + "\n" for p in payloads)
        # Keep one readable JSON Lines file for students to inspect.
        # PUT compresses it during upload as rest_api_replay.json.gz on the stage.
        local_file.write_bytes(content.encode("utf-8"))
        print(f"JSON file: {local_file}")
        uri = ("file://" + local_file.as_posix()).replace("'", "''")

        cursor.execute(f"PUT '{uri}' @ADV_ORDERS.BRONZE.EVENTS_STAGE/batch2/ AUTO_COMPRESS=TRUE OVERWRITE=TRUE")
        upload = cursor.fetchone()

        if upload is None or upload[6] not in ("UPLOADED", "SKIPPED"):
            raise RuntimeError(f"Upload failed: {upload}")

        print(f"Stage upload: {upload[6]} ({SOURCE_FILE})")


        # Bearer sends the signed token as the request credential over HTTPS.
        # The token authenticates the user; the user's DEFAULT_ROLE authorizes
        # pipe access. Never print the token: anyone holding it can use it until expiry.
        headers = {
            "Authorization": "Bearer " + make_jwt(account, user, private_key),
            "Content-Type": "application/json", "Accept": "application/json",
        }

        base_url = f"https://{account}.snowflakecomputing.com/v1/data/pipes/{PIPE}"
        submit_file(base_url, headers)

        wait_for_rows(cursor, base_url, headers)

        total = cursor.execute("SELECT COUNT(*) FROM ADV_ORDERS.BRONZE.EVENTS_RAW").fetchone()[0]
        print(f"Total Bronze rows: {total}; expected 12 immediately after Labs 02 and 02A.")


if __name__ == "__main__":
    main()
