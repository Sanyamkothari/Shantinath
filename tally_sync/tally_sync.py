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
import hashlib
import json
import sys
import re
from collections import defaultdict
from datetime import datetime, timedelta, timezone
import requests

# This script prints ✔ / ⚠️ / ❌ status markers. On Windows those encode fine to
# a console, but when stdout is a pipe or a file (Task Scheduler, `> log.txt`)
# Python falls back to cp1252 and every such print raises UnicodeEncodeError —
# killing the sync mid-run. Pin stdout/stderr to UTF-8 instead.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding='utf-8', errors='replace')
    except (AttributeError, ValueError):
        pass

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
            <LEFTFIELDS>LedNameF, LedParentF, LedBalF, LedIsDrF, LedPhoneF, LedGSTF, LedStateF</LEFTFIELDS>
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
          <FIELD NAME="LedIsDrF">
            <SET>$$IsDebit:$ClosingBalance</SET>
          </FIELD>
          <FIELD NAME="LedPhoneF">
            <SET>$LedgerMobile</SET>
          </FIELD>
          <FIELD NAME="LedStateF">
            <SET>$LedStateName</SET>
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


# ---------------------------------------------------------------------------
# Ledger statement ("Ledger Vouchers" report) — the reliable per-party method.
# The bulk Voucher-collection walk / Day Book (get_vouchers_xml above) returned
# empty ledger entries on this Tally, so we instead pull one party's statement
# at a time with the proven filter+aggregate TDL (dhananjay1405/excelkida).
# ---------------------------------------------------------------------------

def _xml_escape(s):
    return (s or '').replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def _parse_signed_amount(s):
    """Parses a Tally amount string into a signed float (keeps the minus sign)."""
    s = (s or '').strip()
    if not s:
        return 0.0
    tok = s.split()[0]
    cleaned = re.sub(r'[^0-9.\-]', '', tok)
    if cleaned in ('', '-', '.', '-.'):
        return 0.0
    try:
        return float(cleaned)
    except ValueError:
        return 0.0


def get_ledger_vouchers_xml(company, ledger_name, from_str, to_str):
    """Builds the 'Ledger Vouchers' TDL (one party's statement) as an XML export.
    FETCHes AllLedgerEntries and filters to the target ledger via $$FilterValue /
    $$FilterAmtTotal (no <WALK>, which failed here). Per voucher it returns:
    FldDate, FldVoucherType, FldVoucherNumber, FldLedger (first contra ledger =
    particulars), FldAmount (signed: neg=Dr, pos=Cr) and FldIsDr ($$IsDr flag —
    the reliable Dr/Cr source in case the amount sign is dropped in XML)."""
    led = _xml_escape(ledger_name)
    comp = f"<SVCURRENTCOMPANY>{_xml_escape(company)}</SVCURRENTCOMPANY>" if company else ""
    return (
        '<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST>'
        '<TYPE>Data</TYPE><ID>StnLedgerVch</ID></HEADER><BODY><DESC><STATICVARIABLES>'
        f'<SVFROMDATE>{from_str}</SVFROMDATE><SVTODATE>{to_str}</SVTODATE>'
        '<SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>'
        f'{comp}</STATICVARIABLES><TDL><TDLMESSAGE>'
        '<REPORT NAME="StnLedgerVch"><FORMS>StnLVForm</FORMS></REPORT>'
        '<FORM NAME="StnLVForm"><PARTS>StnLVPart</PARTS></FORM>'
        '<PART NAME="StnLVPart"><LINES>StnLVLine</LINES>'
        '<REPEAT>StnLVLine : StnLVColl</REPEAT><SCROLLED>Vertical</SCROLLED></PART>'
        '<LINE NAME="StnLVLine"><FIELDS>FldDate,FldVoucherType,FldVoucherNumber,'
        'FldLedger,FldAmount,FldIsDr,FldNarration</FIELDS></LINE>'
        '<FIELD NAME="FldDate"><SET>$Date</SET></FIELD>'
        '<FIELD NAME="FldVoucherType"><SET>$VoucherTypeName</SET></FIELD>'
        '<FIELD NAME="FldVoucherNumber"><SET>$VoucherNumber</SET></FIELD>'
        '<FIELD NAME="FldLedger"><SET>$FldLedger</SET></FIELD>'
        '<FIELD NAME="FldAmount"><SET>$FldAmount</SET></FIELD>'
        '<FIELD NAME="FldIsDr"><SET>$$IsDr:$$FilterAmtTotal:AllLedgerEntries:FilterVchLedger:$Amount</SET></FIELD>'
        '<FIELD NAME="FldNarration"><SET>$Narration</SET></FIELD>'
        '<COLLECTION NAME="StnLVColl"><TYPE>Voucher</TYPE>'
        '<FETCH>Narration,AllLedgerEntries</FETCH>'
        '<FILTER>FilterCancelledVouchers,FilterOptionalVouchers,FilterVch</FILTER></COLLECTION>'
        '<SYSTEM TYPE="Formulae" NAME="FilterVch">NOT $$IsEmpty:($$FilterValue:$LedgerName:AllLedgerEntries:First:FilterVchLedger)</SYSTEM>'
        f'<SYSTEM TYPE="Formulae" NAME="FilterVchLedger">$$IsEqual:$LedgerName:"{led}"</SYSTEM>'
        f'<SYSTEM TYPE="Formulae" NAME="FilterVchLedgerNot">NOT $$IsEqual:$LedgerName:"{led}"</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FldAmount">if $$IsDr:$$FilterAmtTotal:AllLedgerEntries:FilterVchLedger:$Amount then (-$$FilterAmtTotal:AllLedgerEntries:FilterVchLedger:$Amount) else ($$FilterAmtTotal:AllLedgerEntries:FilterVchLedger:$Amount)</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FldLedger">$$FilterValue:$LedgerName:AllLedgerEntries:First:FilterVchLedgerNot</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FilterCancelledVouchers">NOT $IsCancelled</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FilterOptionalVouchers">NOT $IsOptional</SYSTEM>'
        '</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>'
    )


def parse_ledger_statement(raw):
    """Parses a 'Ledger Vouchers' XML response into a list of statement txns:
    {date, voucherType, voucherNo, amount(magnitude), type('Dr'/'Cr'),
    particulars, narration}. Dr/Cr is taken from the explicit FldIsDr flag,
    falling back to the FldAmount sign."""
    dates = re.findall(r'<FLDDATE>(.*?)</FLDDATE>', raw, re.DOTALL)
    vtypes = re.findall(r'<FLDVOUCHERTYPE>(.*?)</FLDVOUCHERTYPE>', raw, re.DOTALL)
    vnos = re.findall(r'<FLDVOUCHERNUMBER>(.*?)</FLDVOUCHERNUMBER>', raw, re.DOTALL)
    parties = re.findall(r'<FLDLEDGER>(.*?)</FLDLEDGER>', raw, re.DOTALL)
    amts = re.findall(r'<FLDAMOUNT>(.*?)</FLDAMOUNT>', raw, re.DOTALL)
    isdrs = re.findall(r'<FLDISDR>(.*?)</FLDISDR>', raw, re.DOTALL)
    narrs = re.findall(r'<FLDNARRATION>(.*?)</FLDNARRATION>', raw, re.DOTALL)

    txns = []
    for i in range(len(dates)):
        signed = _parse_signed_amount(amts[i] if i < len(amts) else '')
        flag = (isdrs[i].strip().lower() if i < len(isdrs) else '')
        if flag in ('yes', 'true', '1'):
            typ = 'Dr'
        elif flag in ('no', 'false', '0'):
            typ = 'Cr'
        else:
            typ = 'Dr' if signed < 0 else 'Cr'
        txns.append({
            'date': _parse_tally_date(dates[i]),
            'voucherType': vtypes[i].strip() if i < len(vtypes) else '',
            'voucherNo': vnos[i].strip() if i < len(vnos) else '',
            'amount': abs(signed),
            'type': typ,
            'particulars': parties[i].strip() if i < len(parties) else '',
            'narration': narrs[i].strip() if i < len(narrs) else '',
        })
    return txns


def fetch_ledger_statement(tally_url, ledger_name, from_str, to_str, company=None):
    """Fetches ONE ledger's statement via the Ledger Vouchers report.
    Returns [] on any error so a single bad ledger never aborts the batch."""
    headers = {'Content-Type': 'text/xml; charset=utf-8'}
    payload = get_ledger_vouchers_xml(company, ledger_name, from_str, to_str)
    try:
        response = requests.post(tally_url, data=payload, headers=headers, timeout=30)
        response.raise_for_status()
    except Exception:
        return []
    raw = response.content.decode('utf-8', errors='ignore')
    return parse_ledger_statement(raw)


# ---------------------------------------------------------------------------
# Bulk statement + invoice engine.
# Per-party queries scan ALL vouchers each time — impractical at ~35k vouchers ×
# ~1000 shops (it hung Tally). Instead we EXPLODE every voucher's ledger and
# inventory entries in a few windowed passes and bucket by party in Python
# (proven in diagnose_tally.py section 7). $PartyLedgerName is empty in the
# exploded context, so we join inventory→customer via $MasterId + the debtor set.
# ---------------------------------------------------------------------------

def get_bulk_ledgers_xml(company, from_str, to_str):
    """EXPLODE AllLedgerEntries of every voucher in the window (no party filter).
    One row per ledger entry: voucher no/date/type/narration, ledger, amount,
    Dr/Cr, and $MasterId (join key)."""
    comp = f"<SVCURRENTCOMPANY>{_xml_escape(company)}</SVCURRENTCOMPANY>" if company else ""
    return (
        '<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST>'
        '<TYPE>Data</TYPE><ID>StnBulkLed</ID></HEADER><BODY><DESC><STATICVARIABLES>'
        f'<SVFROMDATE>{from_str}</SVFROMDATE><SVTODATE>{to_str}</SVTODATE>'
        '<SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>'
        f'{comp}</STATICVARIABLES><TDL><TDLMESSAGE>'
        '<REPORT NAME="StnBulkLed"><FORMS>BLF</FORMS></REPORT>'
        '<FORM NAME="BLF"><PARTS>BLP</PARTS></FORM>'
        '<PART NAME="BLP"><TOPLINES>BLV</TOPLINES><REPEAT>BLV : BLC</REPEAT><SCROLLED>Vertical</SCROLLED></PART>'
        '<LINE NAME="BLV"><FIELDS>CHdr</FIELDS><EXPLODE>BLEP</EXPLODE></LINE>'
        '<FIELD NAME="CHdr"><SET>$VoucherNumber</SET></FIELD>'
        '<PART NAME="BLEP"><TOPLINES>BLE</TOPLINES><REPEAT>BLE : AllLedgerEntries</REPEAT><SCROLLED>Vertical</SCROLLED></PART>'
        '<LINE NAME="BLE"><FIELDS>CNo,CDate,CType,CLed,CAmt,CIsDr,CMid,CNarr,CRef</FIELDS></LINE>'
        '<FIELD NAME="CNo"><SET>$VoucherNumber</SET></FIELD>'
        '<FIELD NAME="CDate"><SET>$Date</SET></FIELD>'
        '<FIELD NAME="CType"><SET>$VoucherTypeName</SET></FIELD>'
        '<FIELD NAME="CLed"><SET>$LedgerName</SET></FIELD>'
        '<FIELD NAME="CAmt"><SET>$Amount</SET></FIELD>'
        '<FIELD NAME="CIsDr"><SET>$$IsDr:$Amount</SET></FIELD>'
        '<FIELD NAME="CMid"><SET>$MasterId</SET></FIELD>'
        '<FIELD NAME="CNarr"><SET>$Narration</SET></FIELD>'
        '<FIELD NAME="CRef"><SET>$Reference</SET></FIELD>'
        '<COLLECTION NAME="BLC"><TYPE>Voucher</TYPE><FETCH>AllLedgerEntries</FETCH>'
        '<FILTER>FBulkCancel,FBulkOpt</FILTER></COLLECTION>'
        '<SYSTEM TYPE="Formulae" NAME="FBulkCancel">NOT $IsCancelled</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FBulkOpt">NOT $IsOptional</SYSTEM>'
        '</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>'
    )


def get_bulk_inventory_xml(company, from_str, to_str):
    """EXPLODE AllInventoryEntries of every voucher in the window. One row per
    invoice line: voucher no/date, item, billed/actual qty, rate, amount, and
    $MasterId (join key to the ledger pass)."""
    comp = f"<SVCURRENTCOMPANY>{_xml_escape(company)}</SVCURRENTCOMPANY>" if company else ""
    return (
        '<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST>'
        '<TYPE>Data</TYPE><ID>StnBulkInv</ID></HEADER><BODY><DESC><STATICVARIABLES>'
        f'<SVFROMDATE>{from_str}</SVFROMDATE><SVTODATE>{to_str}</SVTODATE>'
        '<SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>'
        f'{comp}</STATICVARIABLES><TDL><TDLMESSAGE>'
        '<REPORT NAME="StnBulkInv"><FORMS>BIF</FORMS></REPORT>'
        '<FORM NAME="BIF"><PARTS>BIP</PARTS></FORM>'
        '<PART NAME="BIP"><TOPLINES>BIV</TOPLINES><REPEAT>BIV : BIC</REPEAT><SCROLLED>Vertical</SCROLLED></PART>'
        '<LINE NAME="BIV"><FIELDS>BHdr</FIELDS><EXPLODE>BIEP</EXPLODE></LINE>'
        '<FIELD NAME="BHdr"><SET>$VoucherNumber</SET></FIELD>'
        '<PART NAME="BIEP"><TOPLINES>BIE</TOPLINES><REPEAT>BIE : AllInventoryEntries</REPEAT><SCROLLED>Vertical</SCROLLED></PART>'
        '<LINE NAME="BIE"><FIELDS>BNo,BDate,BItem,BQty,BAQty,BRate,BAmt,BMid,BBatch,BHSN</FIELDS></LINE>'
        '<FIELD NAME="BNo"><SET>$VoucherNumber</SET></FIELD>'
        '<FIELD NAME="BDate"><SET>$Date</SET></FIELD>'
        '<FIELD NAME="BItem"><SET>$StockItemName</SET></FIELD>'
        '<FIELD NAME="BQty"><SET>$BilledQty</SET></FIELD>'
        '<FIELD NAME="BAQty"><SET>$ActualQty</SET></FIELD>'
        '<FIELD NAME="BRate"><SET>$Rate</SET></FIELD>'
        '<FIELD NAME="BAmt"><SET>$Amount</SET></FIELD>'
        '<FIELD NAME="BMid"><SET>$MasterId</SET></FIELD>'
        '<FIELD NAME="BBatch"><SET>$BatchName</SET></FIELD>'
        '<FIELD NAME="BHSN"><SET>$GSTHSNCode:StockItem:$StockItemName</SET></FIELD>'
        '<COLLECTION NAME="BIC"><TYPE>Voucher</TYPE><FETCH>AllInventoryEntries,AllInventoryEntries.BatchAllocations</FETCH>'
        '<FILTER>FBulkCancel,FBulkOpt</FILTER></COLLECTION>'
        '<SYSTEM TYPE="Formulae" NAME="FBulkCancel">NOT $IsCancelled</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FBulkOpt">NOT $IsOptional</SYSTEM>'
        '</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>'
    )


def parse_bulk_ledgers(raw):
    """Parses the bulk ledger EXPLODE into rows:
    {mid, voucherNo, date, voucherType, ledger, amount, type, narration}."""
    nos = re.findall(r'<CNO>(.*?)</CNO>', raw, re.DOTALL)
    dates = re.findall(r'<CDATE>(.*?)</CDATE>', raw, re.DOTALL)
    types = re.findall(r'<CTYPE>(.*?)</CTYPE>', raw, re.DOTALL)
    leds = re.findall(r'<CLED>(.*?)</CLED>', raw, re.DOTALL)
    amts = re.findall(r'<CAMT>(.*?)</CAMT>', raw, re.DOTALL)
    isdrs = re.findall(r'<CISDR>(.*?)</CISDR>', raw, re.DOTALL)
    mids = re.findall(r'<CMID>(.*?)</CMID>', raw, re.DOTALL)
    narrs = re.findall(r'<CNARR>(.*?)</CNARR>', raw, re.DOTALL)
    refs = re.findall(r'<CREF>(.*?)</CREF>', raw, re.DOTALL)
    rows = []
    for i in range(len(leds)):
        signed = _parse_signed_amount(amts[i]) if i < len(amts) else 0.0
        flag = (isdrs[i].strip().lower() if i < len(isdrs) else '')
        typ = 'Dr' if flag in ('yes', 'true', '1') else ('Cr' if flag in ('no', 'false', '0')
              else ('Dr' if signed < 0 else 'Cr'))
        rows.append({
            'mid': mids[i].strip() if i < len(mids) else '',
            'voucherNo': nos[i].strip() if i < len(nos) else '',
            'date': _parse_tally_date(dates[i]) if i < len(dates) else datetime.now(),
            'voucherType': types[i].strip() if i < len(types) else '',
            'ledger': leds[i].strip(),
            'amount': abs(signed),
            'type': typ,
            'narration': narrs[i].strip() if i < len(narrs) else '',
            'refNo': refs[i].strip() if i < len(refs) else '',
        })
    return rows


def _clean_hsn(raw):
    """Strips Tally's '&#4; Not Found' placeholder and control characters."""
    v = re.sub('[\x00-\x1f]', '', (raw or '')).strip()
    if 'Not Found' in v:
        return ''
    return v


def parse_bulk_inventory(raw):
    """Parses the bulk inventory EXPLODE into rows:
    {mid, voucherNo, date, item, qty, unit, rate, amount}."""
    nos = re.findall(r'<BNO>(.*?)</BNO>', raw, re.DOTALL)
    dates = re.findall(r'<BDATE>(.*?)</BDATE>', raw, re.DOTALL)
    items = re.findall(r'<BITEM>(.*?)</BITEM>', raw, re.DOTALL)
    qtys = re.findall(r'<BQTY>(.*?)</BQTY>', raw, re.DOTALL)
    aqtys = re.findall(r'<BAQTY>(.*?)</BAQTY>', raw, re.DOTALL)
    rates = re.findall(r'<BRATE>(.*?)</BRATE>', raw, re.DOTALL)
    amts = re.findall(r'<BAMT>(.*?)</BAMT>', raw, re.DOTALL)
    mids = re.findall(r'<BMID>(.*?)</BMID>', raw, re.DOTALL)
    batches = re.findall(r'<BBATCH>(.*?)</BBATCH>', raw, re.DOTALL)
    hsns = re.findall(r'<BHSN>(.*?)</BHSN>', raw, re.DOTALL)
    rows = []
    for i in range(len(items)):
        qv, qu = parse_quantity(qtys[i]) if i < len(qtys) else (0.0, '')
        if qv == 0 and i < len(aqtys):
            qv2, qu2 = parse_quantity(aqtys[i])
            qv = qv2 or qv
            qu = qu or qu2
        rows.append({
            'mid': mids[i].strip() if i < len(mids) else '',
            'voucherNo': nos[i].strip() if i < len(nos) else '',
            'date': _parse_tally_date(dates[i]) if i < len(dates) else datetime.now(),
            'item': items[i].strip(),
            'qty': qv, 'unit': qu,
            'rate': abs(_parse_signed_amount(rates[i])) if i < len(rates) else 0.0,
            'amount': abs(_parse_signed_amount(amts[i])) if i < len(amts) else 0.0,
            'batch': batches[i].strip() if i < len(batches) else '',
            'hsn': _clean_hsn(hsns[i]) if i < len(hsns) else '',
        })
    return rows


def _date_chunks(from_date, to_date, chunk_days=90):
    """Splits [from_date, to_date] into <=chunk_days windows so each bulk request
    stays bounded (avoids huge single responses / Tally hangs)."""
    chunks = []
    cur = from_date
    while cur <= to_date:
        end = min(cur + timedelta(days=chunk_days - 1), to_date)
        chunks.append((cur, end))
        cur = end + timedelta(days=1)
    return chunks


def fetch_bulk_statements_invoices(tally_url, days, company, debtor_names, shop_names):
    """ONE-pass-per-window bulk engine. Returns (statements, invoices, complete,
    from_date, to_date):
      statements = {ledger_name: [txn, ...]}  for every debtor with activity
      invoices   = {shop_name:   [inv, ...]}  for every SHOP LIST shop with sales
      complete   = True only if EVERY window fetched and the rows joined cleanly
    Fetches ledger + inventory EXPLODE in <=90-day chunks and buckets in Python.

    `complete` matters: the Firestore sync deletes docs that are absent from what
    we hand it, so a partial result must never be treated as authoritative."""
    headers = {'Content-Type': 'text/xml; charset=utf-8'}
    to_date = datetime.now()
    from_date = to_date - timedelta(days=days)
    chunks = _date_chunks(from_date, to_date, chunk_days=90)

    print(f"\nBulk-fetching vouchers {from_date:%Y-%m-%d}–{to_date:%Y-%m-%d} "
          f"in {len(chunks)} window(s) (ledger + inventory EXPLODE)...")

    led_rows, inv_rows = [], []
    failures = []
    for ci, (cf, ct) in enumerate(chunks, 1):
        fs, ts = cf.strftime('%Y%m%d'), ct.strftime('%Y%m%d')
        for label, builder, sink in (
                ('ledgers', get_bulk_ledgers_xml, led_rows),
                ('inventory', get_bulk_inventory_xml, inv_rows)):
            try:
                resp = requests.post(tally_url, data=builder(company, fs, ts),
                                     headers=headers, timeout=300)
                resp.raise_for_status()
                raw = resp.content.decode('utf-8', errors='ignore')
            except Exception as e:
                print(f"  ⚠️  window {ci}/{len(chunks)} {label} fetch failed ({e}); skipping.")
                failures.append(f"{fs}-{ts}/{label}")
                continue
            sink.extend(parse_bulk_ledgers(raw) if label == 'ledgers'
                        else parse_bulk_inventory(raw))
        print(f"  window {ci}/{len(chunks)} {fs}–{ts}: "
              f"{len(led_rows)} ledger / {len(inv_rows)} inventory rows so far")

    statements, invoices, joined_ok = bucket_statements_invoices(
        led_rows, inv_rows, debtor_names, shop_names)
    total_txns = sum(len(v) for v in statements.values())
    total_bills = sum(len(v) for v in invoices.values())
    print(f"  ✔ Built {total_txns} statement rows for {len(statements)} debtor(s) · "
          f"{total_bills} invoices for {len(invoices)} shop(s).")

    complete = joined_ok and not failures
    if failures:
        print(f"  ⚠️  {len(failures)} window fetch(es) failed: {', '.join(failures)}")
        print("     Syncing in append-only mode — nothing will be deleted this run.")
    return statements, invoices, complete, from_date, to_date


def bucket_statements_invoices(led_rows, inv_rows, debtor_names, shop_names):
    """Pure bucketing of exploded ledger + inventory rows into
    (statements, invoices, ok). Kept separate from I/O so it can be unit-tested.
      statements[name] = [{date, voucherType, voucherNo, amount, type,
                           particulars, narration}, ...]  (oldest first)
      invoices[shop]   = [{mid, voucherNo, voucherType, date, taxableValue,
                           total, items[], ledgers[]}, ...]  (newest first)
      ok               = False if the rows could not be joined safely"""
    # $MasterId is the ONLY join key here — txn -> its contra ledger, and
    # invoice -> its stock lines. Tally leaves some fields empty in the exploded
    # context ($PartyLedgerName does exactly that), and if $MasterId is one of
    # them every voucher collapses into a single '' bucket. The result is not an
    # error, it is silently wrong data: every statement row gets an arbitrary
    # unrelated ledger as its "particulars", and every shop gets one bogus
    # invoice holding the whole window's stock lines. Refuse instead.
    blank_mids = sum(1 for r in led_rows if not r['mid'])
    distinct_mids = len({r['mid'] for r in led_rows if r['mid']})
    if led_rows and (distinct_mids == 0 or blank_mids / len(led_rows) > 0.05):
        print(f"  ❌ $MasterId missing on {blank_mids}/{len(led_rows)} ledger rows "
              f"({distinct_mids} distinct values) — vouchers cannot be joined.")
        print("     Skipping statements + invoices this run; existing data is left "
              "untouched. Run 'python diagnose_tally.py --raw' to inspect the export.")
        return {}, {}, False

    by_ledger = defaultdict(list)     # ledger name -> its entries (statement source)
    by_mid_led = defaultdict(list)    # voucher MasterId -> all its ledger entries
    for r in led_rows:
        by_ledger[r['ledger']].append(r)
        by_mid_led[r['mid']].append(r)
    by_mid_inv = defaultdict(list)    # voucher MasterId -> its inventory lines
    for r in inv_rows:
        by_mid_inv[r['mid']].append(r)

    # --- Statements: for every debtor, its own ledger entries (particulars = the
    # first contra ledger in the same voucher). ---
    statements = {}
    for name in debtor_names:
        entries = by_ledger.get(name)
        if not entries:
            continue
        txns = []
        for e in entries:
            contra = next((L['ledger'] for L in by_mid_led.get(e['mid'], [])
                           if L['ledger'] != name), name)
            txns.append({
                'mid': e['mid'],
                'date': e['date'],
                'voucherType': e['voucherType'],
                'voucherNo': e['voucherNo'],
                'amount': e['amount'],
                'type': e['type'],
                'particulars': contra,
                'narration': e['narration'],
            })
        txns.sort(key=lambda t: t['date'])
        statements[name] = txns

    # --- Invoices: for every SHOP LIST shop, the sales vouchers where the shop is
    # the debtor (Dr) AND the voucher has inventory. Join line items by MasterId. ---
    # A voucher carrying stock is a SALE when the shop is debited and a CREDIT
    # NOTE (sales return) when it is credited. Both are kept, tagged by docType,
    # in the same subcollection — the app's Bills and Credit Note tabs filter on
    # it. Receipts and payments never reach here: they carry no inventory, so the
    # `mid in by_mid_inv` test already drops them.
    invoices = {}
    for name in shop_names:
        doc_mids = {}   # mid -> 'invoice' | 'credit_note'
        for e in by_ledger.get(name, []):
            if e['mid'] not in by_mid_inv:
                continue
            doc_mids[e['mid']] = 'invoice' if e['type'] == 'Dr' else 'credit_note'
        if not doc_mids:
            continue
        bills = []
        for mid, doc_type in doc_mids.items():
            items = by_mid_inv.get(mid, [])
            ledgers = by_mid_led.get(mid, [])
            head = ledgers[0] if ledgers else (items[0] if items else None)
            # Grand total = the shop's own posting on the side that defines this
            # document — its debit on a sale, its credit on a return.
            side = 'Dr' if doc_type == 'invoice' else 'Cr'
            total = sum(L['amount'] for L in ledgers
                        if L['ledger'] == name and L['type'] == side)
            bills.append({
                'mid': mid,
                'docType': doc_type,
                'voucherNo': head['voucherNo'] if head else '',
                'voucherType': head['voucherType'] if head else '',
                'date': head['date'] if head else datetime.now(),
                'refNo': (head.get('refNo', '') if head else ''),
                'taxableValue': round(sum(it['amount'] for it in items), 2),
                'total': round(total, 2),
                # hsn/batch stay '' until the TDL fields are confirmed against a
                # live Tally (see probe_hsn_batch in diagnose_tally.py). The keys
                # ship now so the invoice PDF and Firestore schema don't change
                # shape later.
                'items': [{'item': it['item'], 'qty': it['qty'], 'unit': it['unit'],
                           'rate': it['rate'], 'amount': it['amount'],
                           'hsn': it.get('hsn', ''), 'batch': it.get('batch', '')}
                          for it in items],
                'ledgers': [{'ledger': L['ledger'], 'amount': L['amount'],
                             'type': L['type']} for L in ledgers],
            })
        bills.sort(key=lambda b: b['date'], reverse=True)
        invoices[name] = bills

    return statements, invoices, True


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
            <LEFTFIELDS>StkNameF, StkParentF, StkQtyF, StkValF, StkUnitF, StkHSNF</LEFTFIELDS>
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
          <FIELD NAME="StkHSNF">
            <SET>$$CollectionField:$HSNCode:1:GSTDetails</SET>
          </FIELD>
          <COLLECTION NAME="StkColl">
            <TYPE>Stock Item</TYPE>
            <FETCH>GSTDetails</FETCH>
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
    isdrs = re.findall(r'<LEDISDRF>(.*?)</LEDISDRF>', raw)
    phones = re.findall(r'<LEDPHONEF>(.*?)</LEDPHONEF>', raw)
    gsts = re.findall(r'<LEDGSTF>(.*?)</LEDGSTF>', raw)
    states = re.findall(r'<LEDSTATEF>(.*?)</LEDSTATEF>', raw)

    print(f"  Fetched {len(names)} total ledgers from Tally")

    all_debtor_ledgers = []
    shop_ledgers = []

    for i in range(len(names)):
        name = names[i] if i < len(names) else ""
        parent = parents[i] if i < len(parents) else ""
        bal_str = balances[i] if i < len(balances) else "0.00"
        isdr_str = isdrs[i] if i < len(isdrs) else ""
        phone_str = phones[i] if i < len(phones) else ""
        gst_str = gsts[i] if i < len(gsts) else ""
        state_str = states[i] if i < len(states) else ""

        if not name:
            continue

        balance, bal_type = parse_balance(bal_str)
        # Tally exports $ClosingBalance here as an UNSIGNED magnitude (no minus,
        # no Dr/Cr suffix), so parse_balance always guesses 'Dr' and credit
        # balances get counted as debit. Trust Tally's explicit $$IsDebit flag
        # (LedIsDrF) instead; fall back to the sign inference only if it's
        # missing (older Tally / field not populated).
        flag = isdr_str.strip().lower()
        if flag in ('yes', 'true', '1'):
            bal_type = 'Dr'
        elif flag in ('no', 'false', '0'):
            bal_type = 'Cr'
        phone_clean = sanitize_phone(phone_str)

        ledger = {
            'name': name,
            'parent': parent,
            'outstandingBalance': balance,
            'balanceType': bal_type,
            'phone': phone_clean,
            'gstNo': gst_str.strip() if gst_str else "",
            'state': state_str.strip() if state_str else "",
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
    hsns = re.findall(r'<STKHSNF>(.*?)</STKHSNF>', raw)

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
            'hsn': _clean_hsn(hsns[i]) if i < len(hsns) else '',
        })

    print(f"  Fetched {len(items)} stock items from Tally.")
    hsn_filled = sum(1 for it in items if it['hsn'])
    if hsn_filled:
        print(f"  HSN codes found on {hsn_filled}/{len(items)} stock items.")
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

# ---------------------------------------------------------------------------
# Incremental write helpers. Firestore's free tier caps writes at 20k/day, so we
# write only docs whose content actually changed (compared by a stored content
# hash) and delete only docs that vanished — instead of rewriting everything
# every run. Reads (to diff) are cheaper and capped much higher.
# ---------------------------------------------------------------------------

def _doc_hash(data):
    """Stable content hash of a doc's business fields. Server-timestamp sentinels
    and the hash field itself are excluded so unchanged docs hash identically
    run-to-run."""
    skip = {'updatedAt', 'createdAt', 'lastTallySync', 'syncHash'}

    def norm(v):
        if isinstance(v, bool):
            return v
        if isinstance(v, float):
            return round(v, 4)
        if isinstance(v, datetime):
            return v.isoformat()
        if isinstance(v, list):
            return [norm(x) for x in v]
        if isinstance(v, dict):
            return {k: norm(x) for k, x in sorted(v.items()) if k not in skip}
        return v

    payload = {k: norm(x) for k, x in sorted(data.items()) if k not in skip}
    return hashlib.md5(
        json.dumps(payload, sort_keys=True, default=str).encode('utf-8')).hexdigest()


def _apply_incremental(db, coll_ref, desired, dry_run, allow_deletes=True, keep=None):
    """Writes only new/changed docs and deletes docs no longer present.
    `desired` = {doc_id: data} (SERVER_TIMESTAMP allowed; must NOT pre-set
    syncHash). Returns (written, deleted, unchanged). In dry-run it still reads to
    compute an accurate diff but writes nothing.

    Deleting whatever is absent from `desired` is only correct when `desired` is
    a COMPLETE picture of what should exist. Two knobs keep that honest:
      allow_deletes=False  — the source fetch was partial (a window failed), so
                             write what we have and delete nothing.
      keep(doc_id, data)   — return True to protect a doc from deletion even
                             though it's absent; used to scope deletes to the
                             date window actually synced, so a short --days run
                             cannot wipe older history."""
    existing = {}
    for d in coll_ref.stream():
        existing[d.id] = d.to_dict() or {}

    writes = {}
    for doc_id, data in desired.items():
        h = _doc_hash(data)
        if existing.get(doc_id, {}).get('syncHash') != h:
            writes[doc_id] = {**data, 'syncHash': h}
    if allow_deletes:
        deletes = [i for i, d in existing.items()
                   if i not in desired and not (keep and keep(i, d))]
    else:
        deletes = []
    written, deleted, unchanged = len(writes), len(deletes), len(desired) - len(writes)

    if dry_run:
        return written, deleted, unchanged

    batch = db.batch()
    n = 0
    for doc_id in deletes:
        batch.delete(coll_ref.document(doc_id))
        n += 1
        if n >= 400:
            batch.commit()
            batch = db.batch()
            n = 0
    for doc_id, data in writes.items():
        batch.set(coll_ref.document(doc_id), data, merge=True)
        n += 1
        if n >= 400:
            batch.commit()
            batch = db.batch()
            n = 0
    if n > 0:
        batch.commit()
    return written, deleted, unchanged


def _incr_label(dry_run, name, w, d, u, extra=''):
    tag = '[Dry Run] ' if dry_run else '  ✔ '
    verb = 'would write' if dry_run else 'written'
    print(f"{tag}{name}: {w} {verb}, {d} deleted, {u} unchanged{extra}.")


def _naive_utc(v):
    """Firestore hands datetimes back tz-aware (UTC); the values we write are
    naive. Normalise so the two can be compared."""
    if not isinstance(v, datetime):
        return None
    return v.astimezone(timezone.utc).replace(tzinfo=None) if v.tzinfo else v


def _outside_window(from_date, to_date, pad_days=2):
    """Builds a `keep` predicate protecting docs dated outside the synced window.
    Without it, a run with a shorter --days than the previous one deletes every
    older row: `desired` only covers the new window, and anything absent from it
    is treated as gone from Tally. Padded because the window is local-naive while
    stored dates are UTC — over-keeping is the safe direction."""
    lo = from_date - timedelta(days=pad_days)
    hi = to_date + timedelta(days=pad_days)

    def keep(_doc_id, data):
        d = _naive_utc((data or {}).get('date'))
        if d is None:
            return True   # undated / unreadable row — never delete it blindly
        return d < lo or d > hi

    return keep


def sync_to_firestore(debtor_ledgers, shop_ledgers, vouchers, service_account_path,
                      dry_run=False, stock_items=None, invoices=None,
                      statements_complete=True, statement_window=None):
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
    if stock_items:
        desired = {}
        for item in stock_items:
            doc_id = re.sub(r'[/.#$\[\]]', '_', item['name']).strip()
            if not doc_id:
                continue
            desired[doc_id] = {
                'name': item['name'],
                'group': item.get('group', ''),
                'quantity': item.get('quantity', 0.0),
                'unit': item.get('unit', ''),
                'value': item.get('value', 0.0),
                'updatedAt': firestore.SERVER_TIMESTAMP,
            }
        w, d, u = _apply_incremental(db, db.collection('tally_stock'), desired, dry_run)
        _incr_label(dry_run, 'tally_stock', w, d, u)
    else:
        print("  (No stock items from Tally — skipping, not clearing existing.)")

    # ----- Step 1: Sync shop ledgers to tally_parties collection for registration lookup -----
    print(f"\nSyncing {len(shop_ledgers)} shop names to 'tally_parties' lookup collection...")
    desired = {}
    for ledger in shop_ledgers:
        doc_id = re.sub(r'[/.]', '_', ledger['name']).strip()
        if not doc_id:
            continue
        desired[doc_id] = {
            'name': ledger['name'],
            'village': ledger['parent'],  # City/area group name
            'phone': ledger['phone'],
            'gstNo': ledger['gstNo'],
            'updatedAt': firestore.SERVER_TIMESTAMP,
        }
    if desired:
        w, d, u = _apply_incremental(db, db.collection('tally_parties'), desired, dry_run)
        _incr_label(dry_run, 'tally_parties', w, d, u)
    else:
        print("  (No shop ledgers — skipping, not clearing existing.)")

    # ----- Step 1.5: Sync SHOP LIST ledgers (with balances) to 'tally_ledgers' -----
    # The admin Ledger Book reads this collection, so it must hold ONLY the
    # SHOP LIST sub-tree (retail shops). Syncing the whole Sundry Debtors tree
    # here would fold DEBTORS / FARMER LIST / BOOKING balances into the totals
    # (that is what inflated the Dr/Cr figures). Balances carry the explicit
    # Dr/Cr flag resolved from Tally's $$IsDebit in fetch_ledgers_from_tally.

    # Correctness check: these SHOP LIST totals must equal the Debit / Credit
    # columns of the SHOP LIST row in Tally's Group Summary (Sundry Debtors).
    # This is the definitive proof the Dr/Cr split and scope are right — verify
    # it (works in --dry-run too) before trusting the numbers in the app.
    shop_dr = sum(l['outstandingBalance'] for l in shop_ledgers if l['balanceType'] == 'Dr')
    shop_cr = sum(l['outstandingBalance'] for l in shop_ledgers if l['balanceType'] == 'Cr')
    n_dr = sum(1 for l in shop_ledgers if l['balanceType'] == 'Dr' and l['outstandingBalance'])
    n_cr = sum(1 for l in shop_ledgers if l['balanceType'] == 'Cr' and l['outstandingBalance'])
    print("\n  SHOP LIST balance check (must match Tally Group Summary row):")
    print(f"    Receivable (Dr): Rs {shop_dr:>16,.2f}  across {n_dr} ledger(s)")
    print(f"    Payable    (Cr): Rs {shop_cr:>16,.2f}  across {n_cr} ledger(s)")

    print(f"\nSyncing {len(shop_ledgers)} SHOP LIST balances to 'tally_ledgers' collection...")
    desired = {}
    for ledger in shop_ledgers:
        doc_id = re.sub(r'[/.]', '_', ledger['name']).strip()
        if not doc_id:
            continue
        desired[doc_id] = {
            'name': ledger['name'],
            'village': ledger['parent'],  # City/area group name
            'phone': ledger['phone'],
            'gstNo': ledger['gstNo'],
            'state': ledger.get('state', ''),
            'outstandingBalance': ledger['outstandingBalance'],
            'balanceType': ledger['balanceType'],
            'updatedAt': firestore.SERVER_TIMESTAMP,
        }
    if desired:
        # The diff also deletes any doc not in the SHOP LIST set — this is what
        # purges stale non-shop ledgers from earlier full-Sundry-Debtors syncs.
        w, d, u = _apply_incremental(db, db.collection('tally_ledgers'), desired, dry_run)
        _incr_label(dry_run, 'tally_ledgers', w, d, u,
                    extra=' (deletes include stale non-shop docs)')
    else:
        print("  (No shop ledgers — skipping, not clearing existing.)")

    # ----- Step 1.6: Sync account statements into tally_ledgers/*/transactions -----
    # Powers the admin Ledger Book drill-down (a full statement per SHOP LIST
    # customer, registered on the app or not). Scoped to SHOP LIST so it matches
    # exactly the tally_ledgers docs (registered non-shop debtors still get their
    # own users/*/ledger_transactions in Step 2).
    #
    # Deletes here are gated twice: `statements_complete` is False when any
    # fetch window failed or the MasterId join was unsafe (append-only, delete
    # nothing), and `window_keep` protects rows dated outside the range we
    # actually fetched so a shorter --days run can't erase older history.
    window_keep = _outside_window(*statement_window) if statement_window else None
    if not statements_complete:
        print("\n  ⚠️  Statement/invoice source data was incomplete — writing in "
              "append-only mode (no deletes).")

    debtors_with_txns = [l for l in shop_ledgers if vouchers.get(l['name'])]
    print(f"\nSyncing account statements for {len(debtors_with_txns)} shops to 'tally_ledgers/*/transactions'...")
    tw = td = tu = 0
    for ledger in debtors_with_txns:
        doc_id = re.sub(r'[/.]', '_', ledger['name']).strip()
        if not doc_id:
            continue
        txns_ref = db.collection('tally_ledgers').document(doc_id).collection('transactions')

        # Deterministic, order-independent doc ids (keyed on the voucher's
        # MasterId) so new/back-dated vouchers don't reshuffle everyone else.
        desired = {}
        mid_seen = {}
        for txn in vouchers.get(ledger['name'], []):
            mid = str(txn.get('mid') or '')
            k = mid_seen.get(mid, 0)
            mid_seen[mid] = k + 1
            base = mid if mid else f"{txn['date'].strftime('%Y%m%d')}_{txn['voucherNo']}"
            d_id = re.sub(r'[^a-zA-Z0-9_]', '_', f"{base}_{k}")
            desired[d_id] = {
                'date': txn['date'],
                'voucherType': txn['voucherType'],
                'voucherNo': txn['voucherNo'],
                'amount': txn['amount'],
                'type': txn['type'],
                'particulars': txn['particulars'],
                'narration': txn['narration'],
                'masterId': mid,
                'createdAt': firestore.SERVER_TIMESTAMP,
            }
        w, d, u = _apply_incremental(db, txns_ref, desired, dry_run,
                                     allow_deletes=statements_complete,
                                     keep=window_keep)
        tw += w
        td += d
        tu += u
    _incr_label(dry_run, 'statements', tw, td, tu,
                extra=f' across {len(debtors_with_txns)} shops')

    # ----- Step 1.7: Sync per-shop invoices into tally_ledgers/*/invoices -----
    # Powers the admin Ledger Book "Bills" tab: each sales bill with its line
    # items (item/qty/rate/amount) + full ledger breakup, so it can be viewed and
    # sent to the shop. SHOP LIST only.
    invoices = invoices or {}
    shops_with_bills = [l for l in shop_ledgers if invoices.get(l['name'])]
    total_bills = sum(len(invoices.get(l['name'], [])) for l in shops_with_bills)
    print(f"\nSyncing {total_bills} invoices for {len(shops_with_bills)} shops to 'tally_ledgers/*/invoices'...")
    iw = idl = iu = 0
    for ledger in shops_with_bills:
        doc_id = re.sub(r'[/.]', '_', ledger['name']).strip()
        if not doc_id:
            continue
        inv_ref = db.collection('tally_ledgers').document(doc_id).collection('invoices')

        desired = {}
        for idx, inv in enumerate(invoices.get(ledger['name'], [])):
            inv_id = re.sub(r'[^a-zA-Z0-9_]', '_',
                            str(inv.get('mid') or f"{inv['voucherNo']}_{idx}"))
            desired[inv_id] = {
                'voucherNo': inv['voucherNo'],
                'voucherType': inv['voucherType'],
                # 'invoice' | 'credit_note'. Docs written before this field
                # existed have no docType; the app treats that as 'invoice'.
                'docType': inv.get('docType', 'invoice'),
                'date': inv['date'],
                'refNo': inv.get('refNo', ''),
                'masterId': str(inv.get('mid', '')),
                'taxableValue': inv['taxableValue'],
                'total': inv['total'],
                'items': inv['items'],
                'ledgers': inv['ledgers'],
                'createdAt': firestore.SERVER_TIMESTAMP,
            }
        w, d, u = _apply_incremental(db, inv_ref, desired, dry_run,
                                     allow_deletes=statements_complete,
                                     keep=window_keep)
        iw += w
        idl += d
        iu += u
    _incr_label(dry_run, 'invoices', iw, idl, iu,
                extra=f' across {len(shops_with_bills)} shops')

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

    if not dry_run:
        try:
            db.collection('app_metadata').document('tally_sync').set({
                'lastSyncedAt': firestore.SERVER_TIMESTAMP,
                'stockCount': len(stock_items),
                'shopCount': len(shop_ledgers),
                'invoiceCount': len(invoices),
            }, merge=True)
        except Exception as e:
            print(f"  Warning: Could not update app_metadata sync timestamp: {e}")

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
    parser.add_argument("--days", type=int, default=365,
                        help="Days of statement history to sync per ledger (default: 365). "
                             "Rows dated outside this window are left alone, so a shorter "
                             "run tops up recent data without erasing older history.")
    parser.add_argument("--no-statements", action="store_true",
                        help="Skip the statement + invoice sync; sync balances/stock only")
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

    # 3. Bulk-fetch statements + invoices in a few windowed EXPLODE passes and
    # bucket by party in Python (scales to ~35k vouchers; per-party scanning did
    # not). Statements go to all debtors; invoices only to SHOP LIST shops.
    if args.no_statements:
        print("\nSkipping statement + invoice sync (--no-statements). Balances only.")
        vouchers, invoices = {}, {}
        statements_complete, statement_window = True, None
    else:
        debtor_names = {l['name'] for l in debtor_ledgers}
        shop_names = {l['name'] for l in shop_ledgers}
        (vouchers, invoices, statements_complete,
         stmt_from, stmt_to) = fetch_bulk_statements_invoices(
            args.tally_url, args.days, company, debtor_names, shop_names)
        statement_window = (stmt_from, stmt_to)

    # 4. Fetch stock items (for the admin Stock Status view)
    stock_items = fetch_stock_items_from_tally(args.tally_url, company)

    # 4.5 Build HSN lookup from stock item masters and inject into invoices.
    # The bulk inventory EXPLODE can't reliably cross-reference the Stock Item
    # master's GSTDETAILS, so we look it up from the master fetch above.
    hsn_lookup = {it['name']: it['hsn'] for it in stock_items if it.get('hsn')}
    if hsn_lookup and invoices:
        patched = 0
        for bills in invoices.values():
            for bill in bills:
                for item in bill.get('items', []):
                    master_hsn = hsn_lookup.get(item.get('item', ''), '')
                    cur = item.get('hsn', '')
                    if master_hsn and (not cur or 'Not Found' in cur or '\x04' in cur):
                        item['hsn'] = master_hsn
                        patched += 1
        if patched:
            print(f"  ✔ Injected HSN codes from stock item masters into {patched} invoice line(s).")

    # 5. Sync to Firebase
    sync_to_firestore(debtor_ledgers, shop_ledgers, vouchers, args.service_account,
                      dry_run=args.dry_run, stock_items=stock_items, invoices=invoices,
                      statements_complete=statements_complete,
                      statement_window=statement_window)


if __name__ == "__main__":
    main()
