#!/usr/bin/env python3
"""
Tally to Firebase Firestore Sync Agent
Author: Antigravity AI Coding Assistant
Description: Connects to local Tally Prime/ERP 9 instance via HTTP XML API,
             extracts ledger balances and transaction statement logs for retailers,
             and syncs them to Cloud Firestore.

Uses TDL Report-based XML format for maximum compatibility across Tally versions.
"""

import argparse
import sys
import re
from datetime import datetime, timedelta
import requests

try:
    import firebase_admin
    from firebase_admin import credentials, firestore, messaging
except ImportError:
    print("Error: The 'firebase-admin' package is not installed.")
    print("Please install it using: pip install firebase-admin")
    sys.exit(1)


def send_push_notification(token, title, body):
    """Sends a push notification using Firebase Cloud Messaging."""
    if not token:
        return
    try:
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            token=token,
        )
        response = messaging.send(message)
        print(f"    ✔ Sent push notification. Response: {response}")
    except Exception as e:
        print(f"    ✗ Failed to send push notification: {e}")


# ---------------------------------------------------------------------------
# Tally XML Requests (TDL Report-based format)
# ---------------------------------------------------------------------------

def get_static_variables(company_name=None, extra_vars=""):
    vars_str = "<SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>"
    if company_name:
        vars_str += f"\n        <SVCURRENTCOMPANY>{company_name}</SVCURRENTCOMPANY>"
    if extra_vars:
        vars_str += f"\n        {extra_vars}"
    return vars_str


def get_groups_xml(company_name=None):
    """Generates TDL XML to fetch all groups with their parent hierarchy."""
    static_vars = get_static_variables(company_name)
    return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Data</TYPE>
    <ID>AllGroups</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        {static_vars}
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <REPORT NAME="AllGroups">
            <FORMS>AllGroups</FORMS>
          </REPORT>
          <FORM NAME="AllGroups">
            <TOPPARTS>AllGroups</TOPPARTS>
          </FORM>
          <PART NAME="AllGroups">
            <TOPLINES>GrpLine</TOPLINES>
            <REPEAT>GrpLine : GrpColl</REPEAT>
            <SCROLLED>Vertical</SCROLLED>
          </PART>
          <LINE NAME="GrpLine">
            <LEFTFIELDS>GrpNameF, GrpParentF</LEFTFIELDS>
          </LINE>
          <FIELD NAME="GrpNameF">
            <SET>$Name</SET>
          </FIELD>
          <FIELD NAME="GrpParentF">
            <SET>$Parent</SET>
          </FIELD>
          <COLLECTION NAME="GrpColl">
            <TYPE>Group</TYPE>
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>"""


def get_ledgers_xml(company_name=None):
    """Generates TDL XML to fetch all ledgers with name, parent, and closing balance."""
    static_vars = get_static_variables(company_name)
    return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Data</TYPE>
    <ID>AllLedgers</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        {static_vars}
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <REPORT NAME="AllLedgers">
            <FORMS>AllLedgers</FORMS>
          </REPORT>
          <FORM NAME="AllLedgers">
            <TOPPARTS>AllLedgers</TOPPARTS>
          </FORM>
          <PART NAME="AllLedgers">
            <TOPLINES>LedLine</TOPLINES>
            <REPEAT>LedLine : LedColl</REPEAT>
            <SCROLLED>Vertical</SCROLLED>
          </PART>
          <LINE NAME="LedLine">
            <LEFTFIELDS>LedNameF, LedParentF, LedBalF, LedPhoneF, LedGSTF</LEFTFIELDS>
          </LINE>
          <FIELD NAME="LedNameF">
            <SET>$Name</SET>
          </FIELD>
          <FIELD NAME="LedParentF">
            <SET>$Parent</SET>
          </FIELD>
          <FIELD NAME="LedBalF">
            <SET>$ClosingBalance</SET>
          </FIELD>
          <FIELD NAME="LedPhoneF">
            <SET>$LedgerMobile</SET>
          </FIELD>
          <FIELD NAME="LedGSTF">
            <SET>$GSTRegistrationNo</SET>
          </FIELD>
          <COLLECTION NAME="LedColl">
            <TYPE>Ledger</TYPE>
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>"""


def get_vouchers_xml(from_date, to_date, company_name=None):
    """Lean custom-TDL report that flattens every voucher's ledger entries.

    The full native voucher export is huge (hundreds of fields per voucher) and
    times out on ~5k+ vouchers; the Day Book report ignores the date range on
    this setup. So we use a Voucher collection with <WALK>AllLedgerEntries</WALK>,
    which yields ONE row per ledger entry carrying just the six fields we need:
    the voucher's Date / Type / Number (walked up from the parent) and the
    entry's LedgerName / Amount / IsDeemedPositive. Small + fast + complete.
    Date args unused (we filter by date in Python); kept for signature parity.
    """
    company_var = f"<SVCURRENTCOMPANY>{company_name}</SVCURRENTCOMPANY>" if company_name else ""
    return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Data</TYPE>
    <ID>StnVchReport</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
        {company_var}
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <REPORT NAME="StnVchReport"><FORMS>StnVchForm</FORMS></REPORT>
          <FORM NAME="StnVchForm"><TOPPARTS>StnVchPart</TOPPARTS></FORM>
          <PART NAME="StnVchPart">
            <TOPLINES>StnVchLine</TOPLINES>
            <REPEAT>StnVchLine : StnVchColl</REPEAT>
            <SCROLLED>Vertical</SCROLLED>
          </PART>
          <LINE NAME="StnVchLine">
            <LEFTFIELDS>VDateF, VTypeF, VNoF, VLedgerF, VAmtF, VDeemedF</LEFTFIELDS>
          </LINE>
          <FIELD NAME="VDateF"><SET>$Date</SET></FIELD>
          <FIELD NAME="VTypeF"><SET>$VoucherTypeName</SET></FIELD>
          <FIELD NAME="VNoF"><SET>$VoucherNumber</SET></FIELD>
          <FIELD NAME="VLedgerF"><SET>$LedgerName</SET></FIELD>
          <FIELD NAME="VAmtF"><SET>$Amount</SET></FIELD>
          <FIELD NAME="VDeemedF"><SET>$IsDeemedPositive</SET></FIELD>
          <COLLECTION NAME="StnVchColl">
            <TYPE>Voucher</TYPE>
            <WALK>AllLedgerEntries</WALK>
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>"""


def _xml_first(tag, text):
    """Returns the text of the first <tag>...</tag> in [text], or '' if absent.
    The tag may contain dots (e.g. ALLLEDGERENTRIES.LIST) which are escaped."""
    m = re.search(rf'<{re.escape(tag)}>(.*?)</{re.escape(tag)}>', text, re.DOTALL)
    return m.group(1).strip() if m else ''


def _parse_amount_magnitude(amt_raw):
    """Parses a Tally <AMOUNT> string into a positive float magnitude."""
    if not amt_raw or not amt_raw.strip():
        return 0.0
    token = amt_raw.strip().split()[0]
    cleaned = re.sub(r'[^0-9.\-]', '', token)
    if cleaned in ('', '-', '.', '-.'):
        return 0.0
    try:
        return abs(float(cleaned))
    except ValueError:
        return 0.0


def parse_daybook_vouchers(raw):
    """Parses a native Day Book XML export into {ledger_name: [txn, ...]}.

    Each voucher's ledger entries are expanded, so a transaction is recorded
    against every ledger it touches (the statement sync later reads only the
    debtor ledgers it cares about)."""
    vouchers_by_ledger = {}
    vblocks = re.findall(r'<VOUCHER\b.*?</VOUCHER>', raw, re.DOTALL)

    for vb in vblocks:
        vtype = _xml_first('VOUCHERTYPENAME', vb)
        vno = _xml_first('VOUCHERNUMBER', vb)
        party = _xml_first('PARTYLEDGERNAME', vb)
        narration = _xml_first('NARRATION', vb)
        date_raw = _xml_first('DATE', vb)

        date_val = None
        for fmt in ('%Y%m%d', '%d-%b-%Y', '%d-%b-%y', '%d-%m-%Y'):
            try:
                date_val = datetime.strptime(date_raw, fmt)
                break
            except ValueError:
                continue
        if date_val is None:
            date_val = datetime.now()

        entries = re.findall(r'<ALLLEDGERENTRIES\.LIST>(.*?)</ALLLEDGERENTRIES\.LIST>', vb, re.DOTALL)
        if not entries:
            entries = re.findall(r'<LEDGERENTRIES\.LIST>(.*?)</LEDGERENTRIES\.LIST>', vb, re.DOTALL)

        for e in entries:
            lname = _xml_first('LEDGERNAME', e)
            if not lname:
                continue
            amount = _parse_amount_magnitude(_xml_first('AMOUNT', e))
            deemed = _xml_first('ISDEEMEDPOSITIVE', e).lower()
            entry_type = 'Dr' if deemed == 'yes' else 'Cr'
            vouchers_by_ledger.setdefault(lname, []).append({
                'date': date_val,
                'voucherType': vtype,
                'voucherNo': vno,
                'amount': amount,
                'type': entry_type,
                'particulars': party or lname,
                'narration': narration,
            })

    return vouchers_by_ledger


def _parse_tally_date(raw):
    for fmt in ('%Y%m%d', '%d-%b-%Y', '%d-%b-%y', '%d-%m-%Y'):
        try:
            return datetime.strptime(raw.strip(), fmt)
        except ValueError:
            continue
    return datetime.now()


def parse_voucher_report(raw):
    """Parses the lean flattened voucher report (one ledger entry per row) into
    {ledger_name: [txn, ...]}. Falls back to native <VOUCHER> block parsing if
    the flat fields are absent."""
    ledgers = re.findall(r'<VLEDGERF>(.*?)</VLEDGERF>', raw, re.DOTALL)
    if not ledgers:
        return parse_daybook_vouchers(raw)

    dates = re.findall(r'<VDATEF>(.*?)</VDATEF>', raw, re.DOTALL)
    types = re.findall(r'<VTYPEF>(.*?)</VTYPEF>', raw, re.DOTALL)
    nos = re.findall(r'<VNOF>(.*?)</VNOF>', raw, re.DOTALL)
    amts = re.findall(r'<VAMTF>(.*?)</VAMTF>', raw, re.DOTALL)
    deemed = re.findall(r'<VDEEMEDF>(.*?)</VDEEMEDF>', raw, re.DOTALL)

    by_ledger = {}
    for i in range(len(ledgers)):
        lname = ledgers[i].strip()
        if not lname:
            continue
        date_val = _parse_tally_date(dates[i]) if i < len(dates) else datetime.now()
        amount = _parse_amount_magnitude(amts[i]) if i < len(amts) else 0.0
        d = deemed[i].strip().lower() if i < len(deemed) else ''
        by_ledger.setdefault(lname, []).append({
            'date': date_val,
            'voucherType': types[i].strip() if i < len(types) else '',
            'voucherNo': nos[i].strip() if i < len(nos) else '',
            'amount': amount,
            'type': 'Dr' if d == 'yes' else 'Cr',
            'particulars': lname,
            'narration': '',
        })
    return by_ledger


def get_stock_items_xml(company_name=None):
    """Generates TDL XML to fetch all stock items with closing quantity/value."""
    static_vars = get_static_variables(company_name)
    return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Data</TYPE>
    <ID>AllStockItems</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        {static_vars}
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <REPORT NAME="AllStockItems">
            <FORMS>AllStockItems</FORMS>
          </REPORT>
          <FORM NAME="AllStockItems">
            <TOPPARTS>AllStockItems</TOPPARTS>
          </FORM>
          <PART NAME="AllStockItems">
            <TOPLINES>StkLine</TOPLINES>
            <REPEAT>StkLine : StkColl</REPEAT>
            <SCROLLED>Vertical</SCROLLED>
          </PART>
          <LINE NAME="StkLine">
            <LEFTFIELDS>StkNameF, StkParentF, StkQtyF, StkValF, StkUnitF</LEFTFIELDS>
          </LINE>
          <FIELD NAME="StkNameF">
            <SET>$Name</SET>
          </FIELD>
          <FIELD NAME="StkParentF">
            <SET>$Parent</SET>
          </FIELD>
          <FIELD NAME="StkQtyF">
            <SET>$ClosingBalance</SET>
          </FIELD>
          <FIELD NAME="StkValF">
            <SET>$ClosingValue</SET>
          </FIELD>
          <FIELD NAME="StkUnitF">
            <SET>$BaseUnits</SET>
          </FIELD>
          <COLLECTION NAME="StkColl">
            <TYPE>Stock Item</TYPE>
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>"""


# ---------------------------------------------------------------------------
# Utility Parsers
# ---------------------------------------------------------------------------

def parse_balance(balance_str):
    """
    Parses Tally balance string (e.g. '12,500.00', '-500.00', '4500 Dr', '4500 Cr')
    Returns: (float_amount, 'Dr'|'Cr')
    Tally convention: positive = Dr (customer owes you), negative = Cr (overpaid)
    """
    if not balance_str or not balance_str.strip():
        return 0.0, 'Dr'

    balance_str = balance_str.strip()

    # Check for explicit Dr/Cr suffix
    bal_type = 'Dr'
    if balance_str.endswith('Cr') or balance_str.endswith('CR'):
        bal_type = 'Cr'
        balance_str = balance_str[:-2].strip()
    elif balance_str.endswith('Dr') or balance_str.endswith('DR'):
        bal_type = 'Dr'
        balance_str = balance_str[:-2].strip()

    # Clean commas and parse float
    try:
        amount = float(balance_str.replace(',', ''))
        # If amount is negative, swap the Dr/Cr type
        if amount < 0:
            amount = abs(amount)
            bal_type = 'Cr' if bal_type == 'Dr' else 'Dr'
        return amount, bal_type
    except ValueError:
        return 0.0, 'Dr'


def sanitize_phone(phone_str):
    """Strips all non-digit characters and extracts the last 10 digits."""
    if not phone_str:
        return ""
    digits = re.sub(r'\D', '', str(phone_str))
    if len(digits) >= 10:
        return digits[-10:]
    return digits


# ---------------------------------------------------------------------------
# Core Integration Functions
# ---------------------------------------------------------------------------

def build_group_hierarchy(tally_url, company_name=None):
    """Fetches all groups from Tally and builds the hierarchy tree.
    Returns a dict mapping group_name -> parent_name, and a set of all
    groups that are descendants of 'Sundry Debtors' -> 'SHOP LIST'.
    """
    headers = {'Content-Type': 'text/xml; charset=utf-8'}
    payload = get_groups_xml(company_name)

    print("Fetching group hierarchy from Tally...")
    try:
        response = requests.post(tally_url, data=payload, headers=headers, timeout=30)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(f"Warning: Could not fetch group hierarchy: {e}")
        return {}, set(), set()

    raw = response.content.decode('utf-8', errors='ignore')
    names = re.findall(r'<GRPNAMEF>(.*?)</GRPNAMEF>', raw)
    parents = re.findall(r'<GRPPARENTF>(.*?)</GRPPARENTF>', raw)

    # Build parent map
    group_parent = {}
    for i in range(min(len(names), len(parents))):
        group_parent[names[i]] = parents[i]

    # Find all descendant groups of a given root
    def find_descendants(root_name):
        descendants = set()
        queue = [root_name]
        while queue:
            current = queue.pop(0)
            for name, parent in group_parent.items():
                if parent == current and name not in descendants:
                    descendants.add(name)
                    queue.append(name)
        return descendants

    # All groups under Sundry Debtors (complete debtor tree)
    all_debtor_groups = find_descendants("Sundry Debtors")
    all_debtor_groups.add("Sundry Debtors")

    # Shop List sub-tree specifically (for registration lookup)
    shop_list_groups = find_descendants("SHOP LIST")
    shop_list_groups.add("SHOP LIST")

    print(f"  Found {len(group_parent)} total groups")
    print(f"  {len(all_debtor_groups)} groups under Sundry Debtors")
    print(f"  {len(shop_list_groups)} groups under SHOP LIST (customer shops)")

    return group_parent, all_debtor_groups, shop_list_groups


def fetch_ledgers_from_tally(tally_url, debtor_groups, shop_list_groups, company_name=None):
    """Sends TDL XML request to Tally, parses response, and returns ledger lists."""
    headers = {'Content-Type': 'text/xml; charset=utf-8'}
    payload = get_ledgers_xml(company_name)

    print(f"\nConnecting to Tally at {tally_url}...")
    try:
        response = requests.post(tally_url, data=payload, headers=headers, timeout=60)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(f"\nError: Failed to connect to Tally server. Make sure Tally is open and running on your PC.")
        print(f"Details: {e}")
        sys.exit(1)

    raw = response.content.decode('utf-8', errors='ignore')

    # Parse the flat XML response using regex
    names = re.findall(r'<LEDNAMEF>(.*?)</LEDNAMEF>', raw)
    parents = re.findall(r'<LEDPARENTF>(.*?)</LEDPARENTF>', raw)
    balances = re.findall(r'<LEDBALF>(.*?)</LEDBALF>', raw)
    phones = re.findall(r'<LEDPHONEF>(.*?)</LEDPHONEF>', raw)
    gsts = re.findall(r'<LEDGSTF>(.*?)</LEDGSTF>', raw)

    print(f"  Fetched {len(names)} total ledgers from Tally")

    all_debtor_ledgers = []
    shop_ledgers = []

    for i in range(len(names)):
        name = names[i] if i < len(names) else ""
        parent = parents[i] if i < len(parents) else ""
        bal_str = balances[i] if i < len(balances) else "0.00"
        phone_str = phones[i] if i < len(phones) else ""
        gst_str = gsts[i] if i < len(gsts) else ""

        if not name:
            continue

        balance, bal_type = parse_balance(bal_str)
        phone_clean = sanitize_phone(phone_str)

        ledger = {
            'name': name,
            'parent': parent,
            'outstandingBalance': balance,
            'balanceType': bal_type,
            'phone': phone_clean,
            'gstNo': gst_str.strip() if gst_str else ""
        }

        # Check if this ledger belongs to any Sundry Debtor sub-group
        if parent in debtor_groups:
            all_debtor_ledgers.append(ledger)

        # Check if this ledger belongs to SHOP LIST sub-tree
        if parent in shop_list_groups:
            shop_ledgers.append(ledger)

    print(f"  {len(all_debtor_ledgers)} customer ledgers under Sundry Debtors")
    print(f"  {len(shop_ledgers)} shop ledgers under SHOP LIST (for registration lookup)")

    return all_debtor_ledgers, shop_ledgers


def parse_quantity(qty_str):
    """Parses a Tally closing-quantity string (e.g. '50.00 Bag', '-5 Nos',
    '1,200.00 Kg') into (float_value, unit_string)."""
    if not qty_str or not qty_str.strip():
        return 0.0, ''
    s = qty_str.strip().replace(',', '')
    m = re.match(r'^(-?\d+(?:\.\d+)?)\s*(.*)$', s)
    if not m:
        return 0.0, s
    try:
        value = float(m.group(1))
    except ValueError:
        value = 0.0
    unit = m.group(2).strip()
    return value, unit


def fetch_stock_items_from_tally(tally_url, company_name=None):
    """Fetches all stock items (name, group, closing qty/value, unit) from Tally."""
    headers = {'Content-Type': 'text/xml; charset=utf-8'}
    payload = get_stock_items_xml(company_name)

    print("\nFetching stock items from Tally...")
    try:
        response = requests.post(tally_url, data=payload, headers=headers, timeout=60)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(f"  Warning: Could not fetch stock items ({e}). Skipping stock sync.")
        return []

    raw = response.content.decode('utf-8', errors='ignore')

    names = re.findall(r'<STKNAMEF>(.*?)</STKNAMEF>', raw)
    parents = re.findall(r'<STKPARENTF>(.*?)</STKPARENTF>', raw)
    qtys = re.findall(r'<STKQTYF>(.*?)</STKQTYF>', raw)
    vals = re.findall(r'<STKVALF>(.*?)</STKVALF>', raw)
    units = re.findall(r'<STKUNITF>(.*?)</STKUNITF>', raw)

    items = []
    for i in range(len(names)):
        name = names[i].strip() if i < len(names) else ''
        if not name:
            continue
        qty_raw = qtys[i] if i < len(qtys) else '0'
        val_raw = vals[i] if i < len(vals) else '0'
        quantity, unit = parse_quantity(qty_raw)
        if not unit and i < len(units):
            unit = units[i].strip()
        # Closing value magnitude (strip Dr/Cr and commas).
        val_clean = re.sub(r'[^0-9.\-]', '', (val_raw or '').split()[0]) if val_raw.strip() else '0'
        try:
            value = abs(float(val_clean)) if val_clean not in ('', '-') else 0.0
        except ValueError:
            value = 0.0
        items.append({
            'name': name,
            'group': parents[i].strip() if i < len(parents) else '',
            'quantity': quantity,
            'unit': unit,
            'value': value,
        })

    print(f"  Fetched {len(items)} stock items from Tally.")
    return items


def fetch_vouchers_from_tally(tally_url, days, company_name=None):
    """Fetches all current-period vouchers from Tally (via the Voucher
    collection) and keeps only those within the last [days], grouped by
    ledger. Date filtering happens here in Python because the collection
    export returns the whole period."""
    headers = {'Content-Type': 'text/xml; charset=utf-8'}
    to_date = datetime.now()
    from_date = to_date - timedelta(days=days)
    cutoff = datetime(from_date.year, from_date.month, from_date.day)

    payload = get_vouchers_xml(from_date, to_date, company_name)

    print(f"Retrieving vouchers, keeping those since {cutoff.strftime('%Y-%m-%d')}...")
    try:
        # The full voucher collection can be several MB — allow a long timeout.
        response = requests.post(tally_url, data=payload, headers=headers, timeout=180)
        response.raise_for_status()
    except Exception as e:
        print(f"Warning: Failed to fetch vouchers from Tally. Skipping transaction history sync. Error: {e}")
        return {}

    raw = response.content.decode('utf-8', errors='ignore')

    all_by_ledger = parse_voucher_report(raw)

    # Keep only transactions within the requested window.
    vouchers_by_ledger = {}
    for lname, txns in all_by_ledger.items():
        kept = [t for t in txns if t['date'] >= cutoff]
        if kept:
            vouchers_by_ledger[lname] = kept

    total_all = sum(len(v) for v in all_by_ledger.values())
    total_kept = sum(len(v) for v in vouchers_by_ledger.values())
    print(f"  Parsed {total_all} voucher lines; kept {total_kept} within the last {days} days "
          f"for {len(vouchers_by_ledger)} ledgers.")
    return vouchers_by_ledger


# ---------------------------------------------------------------------------
# Firestore Sync Functions
# ---------------------------------------------------------------------------

def sync_to_firestore(debtor_ledgers, shop_ledgers, vouchers, service_account_path, dry_run=False, stock_items=None):
    """Matches Tally ledgers with Firestore users and updates databases."""
    print("\nConnecting to Cloud Firestore...")
    try:
        cred = credentials.Certificate(service_account_path)
        firebase_admin.initialize_app(cred)
        db = firestore.client()
    except Exception as e:
        print(f"Error initializing Firebase Admin SDK: {e}")
        print("Please check if your Service Account JSON key is correct and accessible.")
        sys.exit(1)

    # ----- Step 0: Sync stock items to 'tally_stock' (read-only admin status view) -----
    # This is a standalone snapshot of Tally inventory for the admin Stock Status
    # screen. It does NOT touch the products catalog or any ordering logic.
    stock_items = stock_items or []
    print(f"\nSyncing {len(stock_items)} stock items to 'tally_stock' collection...")
    if not dry_run and stock_items:
        stock_ref = db.collection('tally_stock')
        batch = db.batch()
        batch_count = 0
        for item in stock_items:
            doc_id = re.sub(r'[/.#$\[\]]', '_', item['name']).strip()
            if not doc_id:
                continue
            batch.set(stock_ref.document(doc_id), {
                'name': item['name'],
                'group': item.get('group', ''),
                'quantity': item.get('quantity', 0.0),
                'unit': item.get('unit', ''),
                'value': item.get('value', 0.0),
                'updatedAt': firestore.SERVER_TIMESTAMP,
            }, merge=True)
            batch_count += 1
            if batch_count >= 400:
                batch.commit()
                batch = db.batch()
                batch_count = 0
        if batch_count > 0:
            batch.commit()
        print(f"  ✔ Successfully synced {len(stock_items)} stock items to 'tally_stock'.")
    elif dry_run:
        print(f"  [Dry Run] Would sync {len(stock_items)} stock items to 'tally_stock'.")

    # ----- Step 1: Sync shop ledgers to tally_parties collection for registration lookup -----
    print(f"\nSyncing {len(shop_ledgers)} shop names to 'tally_parties' lookup collection...")
    if not dry_run:
        parties_ref = db.collection('tally_parties')
        batch = db.batch()
        batch_count = 0

        for ledger in shop_ledgers:
            # Use sanitized name as document ID
            doc_id = re.sub(r'[/.]', '_', ledger['name']).strip()
            if not doc_id:
                continue

            doc_ref = parties_ref.document(doc_id)
            batch.set(doc_ref, {
                'name': ledger['name'],
                'village': ledger['parent'],  # City/area group name
                'phone': ledger['phone'],
                'gstNo': ledger['gstNo'],
                'updatedAt': firestore.SERVER_TIMESTAMP
            }, merge=True)

            batch_count += 1
            if batch_count >= 400:
                batch.commit()
                batch = db.batch()
                batch_count = 0

        if batch_count > 0:
            batch.commit()
        print(f"  ✔ Successfully synced {len(shop_ledgers)} shop names to 'tally_parties'.")
    else:
        print(f"  [Dry Run] Would sync {len(shop_ledgers)} shop names to 'tally_parties'.")

    # ----- Step 1.5: Sync ALL debtor ledgers (with balances) to 'tally_ledgers' -----
    # This gives admins the outstanding Dr/Cr of every customer in Tally,
    # whether or not they have registered on the app. Registered users still
    # get their own private/financials doc (Step 3) for their in-app view.
    print(f"\nSyncing {len(debtor_ledgers)} debtor balances to 'tally_ledgers' collection...")
    if not dry_run:
        ledgers_ref = db.collection('tally_ledgers')
        batch = db.batch()
        batch_count = 0

        for ledger in debtor_ledgers:
            doc_id = re.sub(r'[/.]', '_', ledger['name']).strip()
            if not doc_id:
                continue

            doc_ref = ledgers_ref.document(doc_id)
            batch.set(doc_ref, {
                'name': ledger['name'],
                'village': ledger['parent'],  # City/area group name
                'phone': ledger['phone'],
                'gstNo': ledger['gstNo'],
                'outstandingBalance': ledger['outstandingBalance'],
                'balanceType': ledger['balanceType'],
                'updatedAt': firestore.SERVER_TIMESTAMP,
            }, merge=True)

            batch_count += 1
            if batch_count >= 400:
                batch.commit()
                batch = db.batch()
                batch_count = 0

        if batch_count > 0:
            batch.commit()
        print(f"  ✔ Successfully synced {len(debtor_ledgers)} balances to 'tally_ledgers'.")
    else:
        print(f"  [Dry Run] Would sync {len(debtor_ledgers)} balances to 'tally_ledgers'.")

    # ----- Step 1.6: Sync account statements for ALL debtors -----
    # Mirrors the per-user ledger_transactions write, but into
    # tally_ledgers/{id}/transactions so the admin Ledger Book can show a full
    # statement for EVERY customer — registered on the app or not.
    debtors_with_txns = [l for l in debtor_ledgers if vouchers.get(l['name'])]
    print(f"\nSyncing account statements for {len(debtors_with_txns)} debtors to 'tally_ledgers/*/transactions'...")
    if not dry_run:
        for ledger in debtors_with_txns:
            doc_id = re.sub(r'[/.]', '_', ledger['name']).strip()
            if not doc_id:
                continue
            ledger_vouchers = vouchers.get(ledger['name'], [])
            txns_ref = db.collection('tally_ledgers').document(doc_id).collection('transactions')

            # Replace the existing statement with the latest sync window.
            for t_doc in txns_ref.stream():
                t_doc.reference.delete()

            batch = db.batch()
            for idx, txn in enumerate(ledger_vouchers):
                d_id = re.sub(r'[^a-zA-Z0-9_]', '_',
                              f"{txn['date'].strftime('%Y%m%d')}_{txn['voucherNo']}")
                doc_ref = txns_ref.document(f"{d_id}_{idx}")
                batch.set(doc_ref, {
                    'date': txn['date'],
                    'voucherType': txn['voucherType'],
                    'voucherNo': txn['voucherNo'],
                    'amount': txn['amount'],
                    'type': txn['type'],
                    'particulars': txn['particulars'],
                    'narration': txn['narration'],
                    'createdAt': firestore.SERVER_TIMESTAMP,
                })
                if (idx + 1) % 490 == 0:
                    batch.commit()
                    batch = db.batch()
            batch.commit()
        print(f"  ✔ Synced statements for {len(debtors_with_txns)} debtors.")
    else:
        print(f"  [Dry Run] Would sync statements for {len(debtors_with_txns)} debtors.")

    # ----- Step 2: Match Tally debtor ledgers with registered Firestore users -----
    print("\nFetching registered customers from Firestore...")
    users_ref = db.collection('users')

    try:
        users = list(users_ref.where('role', '==', 'customer').stream())
    except Exception as e:
        print(f"Error fetching users from Firestore: {e}")
        sys.exit(1)

    print(f"  Found {len(users)} registered customers in mobile application database.")

    matched_count = 0

    # Index users by phone, firm name, and GST for fast matching
    users_by_phone = {}
    users_by_firm = {}
    users_by_gst = {}
    user_data_by_id = {}

    for user_doc in users:
        data = user_doc.to_dict()
        user_data_by_id[user_doc.id] = data
        phone = sanitize_phone(data.get('phone', ''))
        firm = data.get('firmName', '').strip().lower()
        gst = data.get('gstNo', '').strip().upper()

        if phone:
            users_by_phone[phone] = user_doc.id
        if firm:
            users_by_firm[firm] = user_doc.id
        if gst:
            users_by_gst[gst] = user_doc.id

    # Iterate through ALL Sundry Debtor ledgers and match
    for ledger in debtor_ledgers:
        t_phone = ledger['phone']
        t_name = ledger['name']
        t_gst = ledger['gstNo'].strip().upper() if ledger['gstNo'] else ""
        t_firm_lower = t_name.strip().lower()

        matched_user_id = None
        match_reason = ""

        # Match logic hierarchy:
        # 1. Firm/Ledger Name match (most reliable for this setup)
        if t_firm_lower in users_by_firm:
            matched_user_id = users_by_firm[t_firm_lower]
            match_reason = f"Firm Name ('{t_name}')"
        # 2. Phone number match
        elif t_phone and t_phone in users_by_phone:
            matched_user_id = users_by_phone[t_phone]
            match_reason = f"Phone Number ({t_phone})"
        # 3. GST Number match
        elif t_gst and t_gst in users_by_gst:
            matched_user_id = users_by_gst[t_gst]
            match_reason = f"GSTIN ({t_gst})"

        if matched_user_id:
            matched_count += 1
            print(f"  ✔ Matched: '{t_name}' -> User ID: {matched_user_id} via {match_reason}")

            user_profile = user_data_by_id.get(matched_user_id, {})
            fcm_token = user_profile.get('fcmToken', '')

            # Fetch financials from subcollection
            financials_ref = db.collection('users').document(matched_user_id).collection('private').document('financials').get()
            financials_data = financials_ref.to_dict() if financials_ref.exists else {}
            prev_balance = financials_data.get('outstandingBalance', 0.0)
            prev_bal_type = financials_data.get('balanceType', 'Dr')

            new_balance = ledger['outstandingBalance']
            new_bal_type = ledger['balanceType']

            # Check if balance changed
            balance_changed = (prev_balance != new_balance) or (prev_bal_type != new_bal_type)

            # Prepare profile updates
            update_data = {
                'outstandingBalance': new_balance,
                'balanceType': new_bal_type,
                'lastTallySync': firestore.SERVER_TIMESTAMP
            }

            if dry_run:
                print(f"    [Dry Run] Would update financials subdoc: Bal={new_balance} {new_bal_type}")
                if balance_changed and fcm_token:
                    print(f"    [Dry Run] Would send push notification: Bal updated from {prev_balance} {prev_bal_type} to {new_balance} {new_bal_type}")
            else:
                db.collection('users').document(matched_user_id).collection('private').document('financials').set(update_data, merge=True)
                if balance_changed and fcm_token:
                    title = "Account Balance Sync 🌾"
                    body = f"Your outstanding balance is updated to ₹{new_balance:,.2f} ({'Owed/Dr' if new_bal_type == 'Dr' else 'Advance/Cr'})."
                    send_push_notification(fcm_token, title, body)

            # Sync transactions for this ledger if available
            ledger_vouchers = vouchers.get(t_name, [])
            if ledger_vouchers:
                if dry_run:
                    print(f"    [Dry Run] Would sync {len(ledger_vouchers)} transaction entries.")
                else:
                    txns_ref = db.collection('users').document(matched_user_id).collection('ledger_transactions')

                    # Fetch existing transactions to detect new vouchers
                    existing_txns = list(txns_ref.stream())
                    existing_vch_nos = set()
                    for t_doc in existing_txns:
                        t_data = t_doc.to_dict()
                        v_no = t_data.get('voucherNo')
                        if v_no:
                            existing_vch_nos.add(str(v_no))

                    # Identify new vouchers for notifications
                    new_receipts = []
                    new_invoices = []
                    for txn in ledger_vouchers:
                        vch_no = str(txn['voucherNo'])
                        if vch_no not in existing_vch_nos:
                            vch_type = txn['voucherType'].lower()
                            vch_amount = txn['amount']
                            if 'receipt' in vch_type:
                                new_receipts.append((vch_no, vch_amount))
                            elif 'sales' in vch_type or 'invoice' in vch_type:
                                new_invoices.append((vch_no, vch_amount))

                    # Delete existing transactions
                    for t_doc in existing_txns:
                        t_doc.reference.delete()

                    # Write new transactions
                    batch = db.batch()
                    for idx, txn in enumerate(ledger_vouchers):
                        doc_id = f"{txn['date'].strftime('%Y%m%d')}_{txn['voucherNo']}"
                        clean_doc_id = re.sub(r'[^a-zA-Z0-9_]', '_', doc_id)

                        doc_ref = txns_ref.document(f"{clean_doc_id}_{idx}")

                        batch.set(doc_ref, {
                            'date': txn['date'],
                            'voucherType': txn['voucherType'],
                            'voucherNo': txn['voucherNo'],
                            'amount': txn['amount'],
                            'type': txn['type'],
                            'particulars': txn['particulars'],
                            'narration': txn['narration'],
                            'createdAt': firestore.SERVER_TIMESTAMP
                        })

                        # Firestore batch limit is 500
                        if (idx + 1) % 490 == 0:
                            batch.commit()
                            batch = db.batch()

                    batch.commit()
                    print(f"    Synced {len(ledger_vouchers)} transaction entries.")

                    # Send push notifications for new receipts or invoices
                    if fcm_token:
                        for vch_no, amount in new_receipts:
                            title = "Payment Confirmed 🤝"
                            body = f"Payment of ₹{amount:,.2f} received against Receipt #{vch_no}. Thank you!"
                            send_push_notification(fcm_token, title, body)
                        for vch_no, amount in new_invoices:
                            title = "New Invoice Raised 📄"
                            body = f"New sales invoice #{vch_no} raised for ₹{amount:,.2f}."
                            send_push_notification(fcm_token, title, body)

    print(f"\n{'='*50}")
    print(f"Sync complete. Matched and updated {matched_count} of {len(debtor_ledgers)} debtor ledgers.")
    print(f"Shop names in registration lookup: {len(shop_ledgers)}")
    if dry_run:
        print("NOTE: Executed in DRY RUN mode. No data was written to Firestore.")


# ---------------------------------------------------------------------------
# Main Entry Point
# ---------------------------------------------------------------------------

def detect_companies(tally_url):
    """Returns the list of company names Tally knows about (data directory),
    without forcing SVCurrentCompany. Used to auto-resolve the active company
    so a financial-year name change (e.g. 2024-2025 -> 2025-2026) doesn't break
    the sync."""
    payload = """<ENVELOPE>
  <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Data</TYPE><ID>CompList</ID></HEADER>
  <BODY><DESC>
    <STATICVARIABLES><SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT></STATICVARIABLES>
    <TDL><TDLMESSAGE>
      <REPORT NAME="CompList"><FORMS>CompList</FORMS></REPORT>
      <FORM NAME="CompList"><TOPPARTS>CompList</TOPPARTS></FORM>
      <PART NAME="CompList"><TOPLINES>CompLine</TOPLINES><REPEAT>CompLine : CompColl</REPEAT><SCROLLED>Vertical</SCROLLED></PART>
      <LINE NAME="CompLine"><LEFTFIELDS>CompNameF</LEFTFIELDS></LINE>
      <FIELD NAME="CompNameF"><SET>$Name</SET></FIELD>
      <COLLECTION NAME="CompColl"><TYPE>Company</TYPE></COLLECTION>
    </TDLMESSAGE></TDL>
  </DESC></BODY>
</ENVELOPE>"""
    try:
        r = requests.post(tally_url, data=payload,
                          headers={'Content-Type': 'text/xml; charset=utf-8'}, timeout=30)
        r.raise_for_status()
        raw = r.content.decode('utf-8', errors='ignore')
    except Exception as e:
        print(f"  Warning: could not list Tally companies: {e}")
        return []
    names = [n.strip() for n in re.findall(r'<COMPNAMEF>(.*?)</COMPNAMEF>', raw, re.DOTALL)]
    seen, out = set(), []
    for n in names:
        if n and n not in seen:
            seen.add(n)
            out.append(n)
    return out


def resolve_company(tally_url, requested):
    """Resolves the effective company name: uses [requested] if Tally has it,
    otherwise falls back to the single open company (auto-correcting a stale
    financial-year suffix). Returns the name to use."""
    companies = detect_companies(tally_url)
    if not companies:
        return requested
    if requested in companies:
        return requested
    if len(companies) == 1:
        print(f"⚠️  Configured company '{requested}' not found in Tally.")
        print(f"   Auto-using the open company: '{companies[0]}'")
        return companies[0]
    print(f"⚠️  Configured company '{requested}' not found. Open companies: {companies}")
    print("   Using the configured name as-is (pass --company to override).")
    return requested


def main():
    parser = argparse.ArgumentParser(description="Synchronize Tally ledger balances with Firebase Firestore.")
    parser.add_argument("--tally-url", default="http://localhost:9000",
                        help="Tally Local HTTP URL (default: http://localhost:9000)")
    parser.add_argument("--service-account", default="service-account.json",
                        help="Path to Firebase Service Account private key JSON (default: service-account.json)")
    parser.add_argument("--days", type=int, default=90,
                        help="Number of days of ledger transactions statement history to sync (default: 90)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Run matching logic and fetch Tally data without writing to Firestore")
    parser.add_argument("--company", default="SHANTINATH AGRO AGENCIES ARNI 2024-2027",
                        help="Exact name of the company in Tally. If it doesn't match, "
                             "the sync auto-uses the single open company.")

    args = parser.parse_args()

    print("==============================================")
    print("      TALLY TO FIRESTORE SYNC AGENT")
    print("==============================================\n")

    # Resolve the effective company (auto-corrects a stale financial-year name).
    company = resolve_company(args.tally_url, args.company)
    print(f"Target Tally Company: '{company}'\n")

    # 1. Build group hierarchy to know which groups are customer groups
    group_parent, debtor_groups, shop_list_groups = build_group_hierarchy(args.tally_url, company)

    if not debtor_groups:
        print("\nWarning: Could not determine group hierarchy. Falling back to fetching all ledgers.")
        # Fallback: treat all ledgers as potential debtors
        debtor_groups = set()
        shop_list_groups = set()

    # 2. Fetch all ledgers from Tally and filter by group
    debtor_ledgers, shop_ledgers = fetch_ledgers_from_tally(args.tally_url, debtor_groups, shop_list_groups, company)

    # 3. Transaction-statement history is intentionally DISABLED.
    # Extracting per-voucher ledger entries from this Tally setup proved
    # unreliable (Day Book ignores the date range; full-object exports time out
    # and can hang Tally). Only outstanding balances are synced. To re-enable
    # later, restore: vouchers = fetch_vouchers_from_tally(args.tally_url, args.days, company)
    vouchers = {}

    # 4. Fetch stock items (for the admin Stock Status view)
    stock_items = fetch_stock_items_from_tally(args.tally_url, company)

    # 5. Sync to Firebase
    sync_to_firestore(debtor_ledgers, shop_ledgers, vouchers, args.service_account,
                      dry_run=args.dry_run, stock_items=stock_items)


if __name__ == "__main__":
    main()
