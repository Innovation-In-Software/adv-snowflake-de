# Copyright © 2026 Innovation In Software Corporation. All rights reserved.
# Optional hosted consumer: create as ADV_ANALYST_US in Snowsight.
# Run locally with: python -m streamlit run Day2\Streamlit-Gold.py -- --local
import os
import sys
from pathlib import Path

import streamlit as st
from snowflake.snowpark.context import get_active_session


@st.cache_resource
def local_session():
    from dotenv import load_dotenv
    from snowflake.snowpark import Session

    root = Path(__file__).resolve().parents[1]
    load_dotenv(root / ".env")
    required = ("SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PRIVATE_KEY_FILE")
    missing = [name for name in required if not os.getenv(name, "").strip()]
    if missing:
        raise ValueError("Set these values in the repository-root .env: " + ", ".join(missing))

    key_path = Path(os.environ["SNOWFLAKE_PRIVATE_KEY_FILE"].strip()).expanduser()
    if not key_path.is_absolute():
        key_path = root / key_path
    config = {
        "account": os.environ["SNOWFLAKE_ACCOUNT"].strip(),
        "user": os.environ["SNOWFLAKE_USER"].strip(),
        "private_key_file": str(key_path),
        "role": "ADV_ANALYST_US",
        "warehouse": "ADV_WH",
        "database": "ADV_ORDERS",
        "schema": "CONSUMER",
        "login_timeout": 30,
    }
    if os.getenv("SNOWFLAKE_PRIVATE_KEY_FILE_PWD"):
        config["private_key_file_pwd"] = os.environ["SNOWFLAKE_PRIVATE_KEY_FILE_PWD"]
    session = Session.builder.configs(config).create()
    try:
        session.sql("USE SECONDARY ROLES NONE").collect()
    except Exception:
        session.close()
        raise
    return session


session = local_session() if "--local" in sys.argv[1:] else get_active_session()
role = session.sql("SELECT CURRENT_ROLE()").collect()[0][0]
if role != "ADV_ANALYST_US":
    st.error("Run this training app as ADV_ANALYST_US before reading Gold.")
    st.stop()

st.title("US order operations")
st.caption("This app uses the US-scoped, masked consumer contract.")
orders = session.sql("""SELECT ORDER_ID, STATUS, AMOUNT, REGION, EMAIL
    FROM ADV_ORDERS.CONSUMER.VW_ORDERS ORDER BY ORDER_ID""").to_pandas()
# Moving the slider reruns the app and filters only the rows the role can see.
minimum_amount = st.slider("Minimum order amount (USD)", 0, 200, 0, step=5)
filtered_orders = orders[orders["AMOUNT"] >= minimum_amount]
active = filtered_orders[filtered_orders["STATUS"] != "CANCELLED"]
st.metric("Active orders", len(active))
st.metric("Active order value (USD)", f"{active['AMOUNT'].sum():.2f}")
st.dataframe(filtered_orders, hide_index=True)
