# Student VM setup

Use PowerShell and a browser on your Windows lab VM. No IDE is required. The course repository is public; cloning does not require a GitHub sign-in.

## 1. Open PowerShell and check the tools

Run one command at a time:

```powershell
git --version
py --list
```

Expect a Git version and **Python 3.12 (64-bit)**. If either is missing, ask the instructor before continuing.

## Copy commands into the lab VM

If ordinary paste does not work in the browser-based Lab on Demand VM:

1. Copy one command from this guide on your local computer.
2. Click inside PowerShell in the VM.
3. In the lab toolbar at the top left, click the **keyboard icon**.
4. Select **Type Text → Type Clipboard Text** and follow any prompt to send the text.
5. Check the command in PowerShell, then press **Enter** if it has not already run.

Copy only the command, not the `PS C:\...>` prompt. Wait for each command to finish before sending the next.

## 2. Clone the course repository

Run these commands one at a time:

```powershell
New-Item -ItemType Directory -Force "$HOME\Training"
Set-Location "$HOME\Training"
git clone https://github.com/Innovation-In-Software/adv-snowflake-de.git
Set-Location .\adv-snowflake-de
git status
```

Expect cloning to finish without errors and `git status` to report a clean working tree. For the VM user `labadmin`, the prompt should now be:

```text
PS C:\Users\labadmin\Training\adv-snowflake-de>
```

Stay in this folder for the remaining setup commands. If the repository folder already exists, do not clone again; enter it and run `git status`. Ask the instructor if any command fails.

To return to the course folder in a new PowerShell window:

```powershell
Set-Location "$HOME\Training\adv-snowflake-de"
```

## 3. Prepare Python

Create a separate Python environment outside the repository:

```powershell
py -3.12 -m venv "$HOME\.venvs\adv-snowflake-de"
& "$HOME\.venvs\adv-snowflake-de\Scripts\python.exe" --version
```

The first command normally finishes silently. Expect **Python 3.12.x** from the second. No environment activation is needed; use the full Python command shown below.

Install all local course packages, including the optional local Streamlit app
and AWS cleanup tool:

```powershell
& "$HOME\.venvs\adv-snowflake-de\Scripts\python.exe" -m pip install -r .\SetUp\requirements.txt
& "$HOME\.venvs\adv-snowflake-de\Scripts\python.exe" -m pip check
& "$HOME\.venvs\adv-snowflake-de\Scripts\python.exe" -c "import snowflake.connector, snowflake.snowpark, snowflake.ingest.streaming, cryptography, dotenv, jwt, requests, pandas, streamlit, boto3; print('Local course imports OK')"
```

Wait for installation to finish before running the checks. Expect **`No broken requirements found.`** and **`Local course imports OK`**. A pip update notice does not require action. If installation or either check fails, ask the instructor before continuing. These packages are for the local VM; Snowflake-hosted notebooks and apps manage their dependencies separately.

## 4. Enter your connection settings

On first setup, run:

```powershell
Copy-Item .\.env.example .\.env
notepad .\.env
```

If `.env` already exists, open it without copying over it. Fill in these three values for your assigned Snowflake training account:

```dotenv
SNOWFLAKE_ACCOUNT=organization-account
SNOWFLAKE_USER=your_snowflake_username
SNOWFLAKE_PASSWORD=your_snowflake_password
```

Use the account identifier supplied by the instructor, not the browser URL. Leave the other settings unchanged. Save and close Notepad. Keep `.env` private; do not commit or share it.

The AWS placeholders are for the optional AWS connection check and local
cleanup in Lab 21. Leave them unchanged until you are ready to use AWS. Never
put real credentials in `.env.example`.

## 5. Prepare Snowflake

**Skip this step if setup has already been completed in your training account. Rerunning the script resets the lab database.**

Open the script on the VM:

```powershell
notepad .\SetUp\00-Environment.sql
```

1. Sign in to your dedicated training account in Snowsight using the VM browser.
2. Copy the script into a SQL worksheet.
3. Run it **section by section** with the instructor, not Run All.

Expect the setup to create the course role `ADV_LAB`, warehouse `ADV_WH`, and database `ADV_ORDERS`. Stop if a section fails.

## 6. Test your connection

Back in PowerShell, run:

```powershell
& "$HOME\.venvs\adv-snowflake-de\Scripts\python.exe" .\SetUp\test_connection.py
```

Expect **`Snowflake connection confirmed.`** and role **`ADV_LAB`**. If authentication fails, ask the instructor; this setup script requires password authentication permitted by the training account.

### Optional: check AWS connectivity

When ready for Lab 21, replace both AWS placeholders in the local `.env` with
credentials for your existing AWS account. If using temporary credentials, also
set `AWS_SESSION_TOKEN`. Keep all credentials private. Run:

```powershell
& "$HOME\.venvs\adv-snowflake-de\Scripts\python.exe" .\SetUp\test_aws_connection.py
```

Expect **`AWS connection confirmed.`** and check that the displayed account and
identity are the ones you intend to use. If both placeholders are unchanged, the
check is skipped; incomplete or invalid credentials cause an error. Existing
environment variables take precedence over `.env`. The check uses AWS STS and
does not verify Lab 21 permissions for Lambda, API Gateway, IAM or CloudWatch.

## 7. Create and test your key pair

Use your dedicated training user: this script registers a public key on that user, replacing its `RSA_PUBLIC_KEY` value.

```powershell
& "$HOME\.venvs\adv-snowflake-de\Scripts\python.exe" .\SetUp\key_pair_setup.py
```

Expect **`Public key registered`** followed by **`Key-pair connection confirmed.`** The script stores the keys in your Windows user folder under `.snowflake\adv-class-keys`, outside the repository. On a repeat run, it reuses an existing matching key pair. Keep the private key private; do not upload or share it.

**Setup is complete.** Continue with [Day 1, Lab 01](../Day1/Student-guide.md) and follow the labs in order. Labs 03 and 05 use Python on this VM; SQL exercises run in Snowsight. Additional lab-specific setup is provided in those labs.

## Get instructor updates

When instructed, run from the course folder:

```powershell
git pull --ff-only
```

If Git reports a conflict or that local changes would be overwritten, stop and ask the instructor. The current setup scripts explicitly configure the connector's session behavior to avoid its default-setting warning; students do not need to edit Python code.

If you set up the environment before these dependencies were consolidated, rerun
the install and checks in **Prepare Python** after pulling the update; you do
not need to recreate the environment.

## Before leaving class

Run that day's Snowflake stop script and end active notebook sessions. Closing the browser or disconnecting the VM does not stop background Snowflake work.

- Day 1: [99-Stop.sql](../Day1/99-Stop.sql)
- Day 2: [99-Day2-Stop.sql](../Day2/99-Day2-Stop.sql)
- Day 3: [99-CourseStop.sql](../Day3/99-CourseStop.sql), plus Lab 21's AWS cleanup if you created its resources.
