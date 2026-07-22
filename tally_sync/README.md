# Tally Solutions to Firebase Firestore Sync Agent

This folder contains the **Tally Sync Agent** which connects your local Tally Prime/ERP 9 database with the Cloud Firestore database used by your mobile application. It automatically updates each retailer's outstanding credit/debit balance and posts their statement transaction history (vouchers) to the app.

---

## 📋 How It Works

1. The script connects to the local Tally Gateway server on port `9000`.
2. It queries all ledgers under the parent group **Sundry Debtors** (your customers).
3. It fetches all vouchers (transactions like Sales Invoices, Receipts, Credit Notes, Journals) for the last $N$ days.
4. It connects to Firestore and matches Tally ledgers to mobile users using:
   - **Phone Number**: (Tally ledger contact mobile number $\rightarrow$ User registration phone)
   - **GSTIN**: (Tally ledger GST number $\rightarrow$ User profile GSTIN)
   - **Firm Name**: (Tally ledger name $\rightarrow$ User profile Firm Name)
5. It writes the net balance, debit/credit status, and transaction history to Firestore.

---

## 🛠️ Setup Instructions (On the PC running Tally)

### Step 1: Install Python
Ensure that Python 3 is installed on your computer.
1. Download Python from the [official website](https://www.python.org/downloads/) (make sure to check the box **"Add Python to PATH"** during installation).
2. Open Command Prompt (cmd) and verify the installation:
   ```cmd
   python --version
   ```

### Step 2: Install Python Libraries
Open Command Prompt and install the required dependencies:
```cmd
pip install requests firebase-admin
```

### Step 3: Download Firebase Credentials
The script needs permission to update your Firestore database.
1. Go to your [Firebase Console](https://console.firebase.google.com/).
2. Select your project **Shantinath Agro**.
3. Click the gear icon next to "Project Overview" and choose **Project Settings**.
4. Go to the **Service Accounts** tab.
5. Click the **Generate new private key** button at the bottom.
6. A `.json` file will download to your computer.
7. Rename this downloaded file to `service-account.json` and move it into this `tally_sync` folder (so it is right next to `tally_sync.py`).

### Step 4: Configure Tally Prime
You must tell Tally to listen for connection requests on port 9000:
1. Open **Tally Prime**.
2. Go to **F1: Help** (top right) $\rightarrow$ **Settings** $\rightarrow$ **Startup**.
3. Look for **Enable ODBC Server** (or Gateway Server) and set it to **Yes**.
4. Ensure the **Port** is set to `9000`.
5. Restart Tally Prime. Keep your active company (**SHANTINATH AGRO AGENCIES ARNI 2024-2027**) open.

### Step 5: Run the Diagnostic & Structure Explorer (Highly Recommended)
Before running the main sync, verify everything is connected AND inspect how your
Tally data is actually arranged:
```cmd
python diagnose_tally.py
```
This tool checks Python + libraries, the `service-account.json` Firestore connection,
and Tally on port `9000`. It then **explores your Tally structure** — group hierarchy,
customer ledgers (with balance/phone/GST parsing checks), **stock items** (quantity/unit
parsing + compound-unit detection), and recent **vouchers** (types + samples) — using the
sync's own parsers, so you see exactly how the sync will read your data. Add `--raw` to dump
raw response snippets, or `--days 30` to change the voucher window.
60: 
61: ---
62: 
63: ## 🚀 Running the Sync Script

Open Command Prompt, navigate to this directory, and run the script:

### 1. Test Match (Dry Run)
We recommend running a test first. This will fetch Tally data and show you which ledgers successfully match your mobile app users without saving any changes:
```cmd
python tally_sync.py --dry-run
```
Review the command prompt output. It will show:
* `✔ Matched`: Ledgers that successfully linked to a user profile in Firestore.
* `✗ Unmatched`: Ledgers that couldn't be linked. To resolve this, make sure the customer's phone number or GSTIN is entered identically in both Tally and the mobile app.

### 2. Live Synchronize (Default 90 days)
To run a live sync and push balances and the last 90 days of transactions:
```cmd
python tally_sync.py
```

### 3. Synchronize Custom Range (e.g. a full year of statement history)
To sync a longer history range (for example, 365 days of transactions):
```cmd
python tally_sync.py --days 365
```

---

## ⏰ Automating with Windows Task Scheduler

To avoid running the script manually, configure Windows to execute it automatically (e.g., every hour):

1. Press the Windows Key, type **Task Scheduler**, and press Enter.
2. Click **Create Basic Task** in the Actions panel on the right.
3. **Name**: `Tally to App Sync`
4. **Trigger**: Select **Daily** (you can adjust this later to repeat hourly).
5. **Action**: Select **Start a Program**.
6. **Program/Script**: Enter `python`
7. **Add Arguments**: Enter the absolute path to your script (the default 90-day window applies; add `--days 365` for a longer history). 
   *Example:* `C:\Users\sanya\shantinath_agro\tally_sync\tally_sync.py`
8. **Start in**: Enter the absolute path to the directory containing your script:
   *Example:* `C:\Users\sanya\shantinath_agro\tally_sync`
9. Click **Finish**.
10. To make it repeat every hour: Double-click the task in the list, go to the **Triggers** tab, click **Edit**, check the box **"Repeat task every:"** and select **1 hour**.
