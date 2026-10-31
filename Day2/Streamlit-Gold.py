# Copyright © 2026 Innovation In Software Corporation. All rights reserved.
# Optional hosted consumer: create as ADV_ANALYST_US in Snowsight.
import streamlit as st
from snowflake.snowpark.context import get_active_session

session = get_active_session()
role = session.sql("SELECT CURRENT_ROLE()").collect()[0][0]
if role != "ADV_ANALYST_US":
    st.error("Create this training app as ADV_ANALYST_US before reading Gold.")
    st.stop()

st.title("US order operations")
st.caption("All app viewers receive this app owner's US-scoped, masked contract.")
orders = session.sql("""SELECT ORDER_ID, STATUS, AMOUNT, REGION, EMAIL
    FROM ADV_ORDERS.CONSUMER.ORDERS ORDER BY ORDER_ID""").to_pandas()
active = orders[orders["STATUS"] != "CANCELLED"]
st.metric("Active orders", len(active))
st.metric("Active order value (USD)", f"{active['AMOUNT'].sum():.2f}")
st.dataframe(orders, hide_index=True)
