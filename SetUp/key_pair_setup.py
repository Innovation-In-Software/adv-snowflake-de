"""Generate, register, and verify a Snowflake RSA key pair from a discovered .env."""

from __future__ import annotations

import base64
import os
from pathlib import Path
import snowflake.connector
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from dotenv import load_dotenv


REPO_ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    # python-dotenv searches upward from this script when no path is supplied.
    if not load_dotenv(override=False):
        raise SystemExit("Could not find .env. Copy .env.example to the repository root.")
        
    user = os.getenv("SNOWFLAKE_USER", "").strip()
    key_setting = os.getenv("SNOWFLAKE_PRIVATE_KEY_FILE", "").strip()
    
    if not user:
        raise SystemExit("Set SNOWFLAKE_USER in the repository-root .env first.")
        
    if not key_setting:
        raise SystemExit("Set SNOWFLAKE_PRIVATE_KEY_FILE in the repository-root .env first.")
        
    password = os.getenv("SNOWFLAKE_PASSWORD", "")
    account = os.getenv("SNOWFLAKE_ACCOUNT", "").strip()
    if not account or not password:
        raise SystemExit("Set SNOWFLAKE_ACCOUNT and SNOWFLAKE_PASSWORD in .env first.")

    key_path = Path(key_setting).expanduser()
    
    if not key_path.is_absolute():
        key_path = (REPO_ROOT / key_path).resolve()
        
    public_path = key_path.with_suffix(key_path.suffix + ".pub")
    private_exists = key_path.is_file()
    public_exists = public_path.is_file()
    
    if private_exists != public_exists:
        raise SystemExit(
            "Only one key file exists. For safety, the script will not replace or reconstruct it. "
            f"Check these files manually: {key_path} and {public_path}"
        )

    if private_exists:
        print(f"Reusing existing private key: {key_path}")
        print(f"Reusing existing public key:  {public_path}")
        
        try:
            private_key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
        except (ValueError, TypeError) as exc:
            raise SystemExit(
                "Could not load the existing private key. It may be encrypted or invalid; "
                "the script will not overwrite it. " + str(exc)
            ) from None
            
        try:
            saved_public_key = serialization.load_pem_public_key(public_path.read_bytes())
        except (ValueError, TypeError):
            raise SystemExit(
                "The existing public key file is invalid. The script will not overwrite either file."
            ) from None
            
        derived_public_bytes = private_key.public_key().public_bytes(
            encoding=serialization.Encoding.DER,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        saved_public_bytes = saved_public_key.public_bytes(
            encoding=serialization.Encoding.DER,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        
        if derived_public_bytes != saved_public_bytes:
            raise SystemExit(
                "The existing private and public key files do not match. "
                "The script will not overwrite either file."
            )
    else:
        print("No existing key pair found; generating a new pair.")
        private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        
        # Classroom default: an unencrypted key avoids an extra secret or prompt.
        private_bytes = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
        
        # Production option: use BestAvailableEncryption with an interactively
        # entered passphrase, and supply private_key_password on connector login.
        public_bytes = private_key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )

        key_path.parent.mkdir(parents=True, exist_ok=True)
        key_path.write_bytes(private_bytes)
        
        try:
            os.chmod(key_path, 0o600)
        except OSError:
            pass  # Windows ACLs control access; chmod is not supported on every filesystem.
            
        public_path.write_bytes(public_bytes)
        
        print(f"Private key saved to: {key_path}")
        print(f"Public key saved to:  {public_path}")

    public_der = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    
    public_key_sql = base64.b64encode(public_der).decode("ascii")
    print("Connecting to Snowflake as ACCOUNTADMIN to register the public key...")
    connection = None
    
    try:
        connection = snowflake.connector.connect(
            account=account,
            user=user,
            password=password,
            role="ACCOUNTADMIN",
            login_timeout=30,
        )
        
        with connection.cursor() as cursor:
            cursor.execute(f'ALTER USER {user} SET RSA_PUBLIC_KEY = \'{public_key_sql}\'')
            
        print(f"Public key registered for Snowflake user {user}.")
    except snowflake.connector.errors.Error as exc:
        raise SystemExit(
            "Key pair was generated, but registration failed. Confirm password login, "
            "ACCOUNTADMIN access, and that the Snowflake username is correct. "
            f"Connector message: {exc}"
        ) from None
    finally:
        if connection is not None:
            connection.close()

    print("Testing a new connection using the generated private key...")
    connection = None
    try:
        connection = snowflake.connector.connect(
            account=account,
            user=user,
            private_key_file=str(key_path),
            role=os.getenv("SNOWFLAKE_ROLE", "ADV_LAB").strip(),
            warehouse=os.getenv("SNOWFLAKE_WAREHOUSE", "ADV_WH").strip(),
            database=os.getenv("SNOWFLAKE_DATABASE", "ADV_ORDERS").strip(),
            schema=os.getenv("SNOWFLAKE_SCHEMA", "BRONZE").strip(),
            login_timeout=30,
        )
        with connection.cursor() as cursor:
            row = cursor.execute("SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT()").fetchone()
        
        print("Key-pair connection confirmed.")
        print(f"User: {row[0]} | Role: {row[1]} | Account: {row[2]}")
    except snowflake.connector.errors.Error as exc:
        raise SystemExit(
            "The public key was registered, but key-pair authentication failed. "
            "Check the user, key file, and RSA_PUBLIC_KEY registration. "
            f"Connector message: {exc}"
        ) from None
    finally:
        if connection is not None:
            connection.close()
            
    print("This classroom key has no passphrase. Keep the private key private and never commit it.")


if __name__ == "__main__":
    main()
