USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE API INTEGRATION GIT_GITHUB_INT_ADE
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/Innovation-In-Software/')
  ENABLED = TRUE;


-- When creating a Workspace from Git repository use the following:
-- Repository URL: https://github.com/Innovation-In-Software/adv-snowflake-de
-- Workspace Name: adv-snowflake-de
-- API Integration: GIT_GITHUB_INT_ADE
-- Public repository
