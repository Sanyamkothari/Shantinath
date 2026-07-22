#!/usr/bin/env python3
"""
Tally Integration Diagnostic & Structure Explorer
=================================================
Verifies prerequisites (Python, libraries, Firebase, Tally connectivity) AND
explores the ACTUAL shape of your Tally data — groups, ledgers, stock items and
vouchers — so we can confirm every parser the sync relies on matches your setup.

It imports the real parsers from tally_sync.py, so what you see here is exactly
how the sync will interpret your data.

Usage:
    python diagnose_tally.py
    python diagnose_tally.py --days 90 --raw
"""

import sys
import os
import re
import socket
import argparse

try:
    from datetime import datetime, timedelta
except Exception:  # pragma: no cover
    pass

# Import the sync's pure helpers so the diagnostic tests the SAME code paths.
# (Importing tally_sync is safe — its main() only runs under __main__.)
try:
    from tally_sync import (
        get_groups_xml,
        get_ledgers_xml,
        get_stock_items_xml,
        get_vouchers_xml,
        parse_balance,
        parse_quantity,
        sanitize_phone,
        parse_daybook_vouchers,
        parse_voucher_report,
    )
    SYNC_IMPORT_OK = True
    SYNC_IMPORT_ERR = None
except Exception as e:  # pragma: no cover
    SYNC_IMPORT_OK = False
    SYNC_IMPORT_ERR = e


HEADERS = {'Content-Type': 'text/xml; charset=utf-8'}


def hr(title):
    print("\n" + "=" * 64)
    print(f" {title}")
    print("=" * 64)


def tally_request(requests, url, payload, timeout=180):
    """POSTs an XML payload to Tally and returns decoded text, or None on error.
    Never raises — the diagnostic must keep running through failures."""
    try:
        r = requests.post(url, data=payload, headers=HEADERS, timeout=timeout)
        r.raise_for_status()
        raw = r.content.decode('utf-8', errors='ignore')
        if not raw or "<ENVELOPE>" not in raw:
            if "Unknown Request" in (raw or ""):
                print("   ❌ Tally returned 'Unknown Request' (cannot export in current state).")
            else:
                print(f"   ❌ Invalid response from Tally. Starts: {(raw or '')[:120]!r}")
            return None
        # Tally reports request-level problems (e.g. wrong company) via LINEERROR,
        # while still returning a well-formed <ENVELOPE>. Surface it loudly.
        m = re.search(r'<LINEERROR>(.*?)</LINEERROR>', raw, re.DOTALL)
        if m:
            print(f"   ❌ Tally error: {m.group(1).strip()}")
            return None
        return raw
    except Exception as e:
        print(f"   ⚠️  Tally request failed: {e}")
        return None


def detect_companies(requests, url):
    """Returns the list of company names Tally knows about (data directory).
    Does NOT force SVCURRENTCOMPANY, so it works even when the configured name
    is wrong — which is exactly how we discover the correct name."""
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
    raw = tally_request(requests, url, payload)
    if not raw:
        return []
    names = [n.strip() for n in re.findall(r'<COMPNAMEF>(.*?)</COMPNAMEF>', raw, re.DOTALL)]
    # De-dup while preserving order.
    seen, out = set(), []
    for n in names:
        if n and n not in seen:
            seen.add(n)
            out.append(n)
    return out


def findall(tag, raw):
    return re.findall(rf'<{tag}>(.*?)</{tag}>', raw, re.DOTALL)


def find_descendants(groups, root):
    """All group names under `root` (recursive)."""
    out = set()
    for name, parent in groups.items():
        if parent == root:
            out.add(name)
            out.update(find_descendants(groups, name))
    return out


# ---------------------------------------------------------------------------
# Section runners
# ---------------------------------------------------------------------------

def explore_groups(requests, url, company):
    hr("1. GROUP STRUCTURE")
    raw = tally_request(requests, url, get_groups_xml(company))
    if not raw:
        return None
    names = findall('GRPNAMEF', raw)
    parents = findall('GRPPARENTF', raw)
    groups = {}
    for i in range(min(len(names), len(parents))):
        groups[names[i].strip()] = parents[i].strip()

    print(f"✔ Found {len(groups)} accounting groups.")

    # Top-level (primary) groups
    tops = sorted([n for n, p in groups.items() if p in ('', 'Primary', ' ')])
    if tops:
        print(f"\n  Top-level groups ({len(tops)}): {', '.join(tops[:20])}"
              + (" ..." if len(tops) > 20 else ""))

    for key in ('Sundry Debtors', 'SHOP LIST'):
        if key in groups:
            desc = find_descendants(groups, key)
            print(f"\n  ✔ '{key}' found — {len(desc)} sub-group(s).")
            if desc:
                sample = sorted(desc)[:8]
                print(f"     e.g. {', '.join(sample)}" + (" ..." if len(desc) > 8 else ""))
        else:
            print(f"\n  ❌ '{key}' NOT found — features relying on it will be empty.")
    return groups


def explore_ledgers(requests, url, company, groups):
    hr("2. LEDGER STRUCTURE (customers / balances)")
    raw = tally_request(requests, url, get_ledgers_xml(company))
    if not raw:
        return set()
    names = findall('LEDNAMEF', raw)
    parents = findall('LEDPARENTF', raw)
    bals = findall('LEDBALF', raw)
    phones = findall('LEDPHONEF', raw)
    gsts = findall('LEDGSTF', raw)
    print(f"✔ Found {len(names)} total ledgers.")

    debtor_groups = set()
    if groups and 'Sundry Debtors' in groups:
        debtor_groups = find_descendants(groups, 'Sundry Debtors')
        debtor_groups.add('Sundry Debtors')

    debtors = []
    for i in range(len(names)):
        parent = parents[i].strip() if i < len(parents) else ''
        if debtor_groups and parent not in debtor_groups:
            continue
        debtors.append({
            'name': names[i].strip(),
            'parent': parent,
            'bal_raw': bals[i].strip() if i < len(bals) else '',
            'phone_raw': phones[i].strip() if i < len(phones) else '',
            'gst': gsts[i].strip() if i < len(gsts) else '',
        })

    scope = "under 'Sundry Debtors'" if debtor_groups else "(all ledgers — Sundry Debtors group not found)"
    print(f"  → {len(debtors)} debtor ledger(s) {scope}.")

    if not debtors:
        print("  ⚠️  No debtor ledgers to analyse.")
        return set()

    # Match readiness
    has_phone = sum(1 for d in debtors if sanitize_phone(d['phone_raw']))
    has_gst = sum(1 for d in debtors if d['gst'] and d['gst'] not in ('', 'N/A', '-'))
    print(f"\n  Match readiness: {has_phone}/{len(debtors)} have phone · "
          f"{has_gst}/{len(debtors)} have GSTIN")

    # Balance format validation via the real parser
    print("\n  Balance parsing check (raw → parsed by parse_balance):")
    for d in debtors[:6]:
        amt, typ = parse_balance(d['bal_raw'])
        ph = sanitize_phone(d['phone_raw'])
        print(f"    • {d['name'][:34]:34s} | bal {d['bal_raw']!r:>18} → {amt:>12,.2f} {typ}")
        print(f"      phone {d['phone_raw']!r} → {ph or '—'} | gst {d['gst'] or '—'}")

    # Flag odd balance strings the parser may not expect
    odd = [d for d in debtors if d['bal_raw'] and not re.match(
        r'^-?[\d,]+(\.\d+)?\s*(Dr|Cr)?$', d['bal_raw'], re.IGNORECASE)]
    if odd:
        print(f"\n  ⚠️  {len(odd)} ledger balance(s) have an unusual format — verify parsing:")
        for d in odd[:3]:
            print(f"     '{d['name']}': {d['bal_raw']!r}")

    return {d['name'] for d in debtors}


def explore_stock(requests, url, company, raw_dump=False):
    hr("3. STOCK STRUCTURE (inventory)")
    raw = tally_request(requests, url, get_stock_items_xml(company))
    if not raw:
        return
    if raw_dump:
        print(f"  [raw head] {raw[:400]!r}\n")
    names = findall('STKNAMEF', raw)
    parents = findall('STKPARENTF', raw)
    qtys = findall('STKQTYF', raw)
    vals = findall('STKVALF', raw)
    units = findall('STKUNITF', raw)
    print(f"✔ Found {len(names)} stock items.")
    if not names:
        print("  ℹ️  No stock items — the Stock Status screen will be empty.")
        return

    # Quantity/value parsing check + compound-unit detection
    compound = []
    print("\n  Quantity parsing check (raw → parsed by parse_quantity):")
    for i in range(min(len(names), 6)):
        qty_raw = qtys[i] if i < len(qtys) else ''
        val_raw = vals[i] if i < len(vals) else ''
        unit_raw = units[i].strip() if i < len(units) else ''
        q, u = parse_quantity(qty_raw)
        print(f"    • {names[i].strip()[:34]:34s} | qty {qty_raw!r:>16} → {q:>10,.2f} {u or unit_raw}")
        print(f"      group {parents[i].strip() if i < len(parents) else '—'} | value {val_raw!r} | baseUnit {unit_raw or '—'}")

    # Detect compound units (e.g. "5 Bag 3 Nos") across the whole set
    for i in range(len(names)):
        qraw = (qtys[i] if i < len(qtys) else '').strip()
        # more than one number+word pair suggests a compound unit
        if len(re.findall(r'-?\d[\d,\.]*\s*[A-Za-z]+', qraw)) > 1:
            compound.append((names[i].strip(), qraw))
    if compound:
        print(f"\n  ⚠️  {len(compound)} item(s) use COMPOUND units — parser keeps only the first number:")
        for name, qraw in compound[:5]:
            print(f"     '{name}': {qraw!r}")
        print("     If these matter, tell me and I'll extend parse_quantity for compound units.")
    else:
        print("\n  ✔ All quantities are simple (single unit) — parse_quantity handles them.")

    # Distinct units summary
    unit_set = sorted({u.strip() for u in units if u.strip()})
    if unit_set:
        print(f"\n  Units in use: {', '.join(unit_set[:15])}" + (" ..." if len(unit_set) > 15 else ""))


def _company_var(company):
    return f"<SVCURRENTCOMPANY>{company}</SVCURRENTCOMPANY>" if company else ""


def _daybook_xml(company, from_str, to_str):
    return f"""<ENVELOPE>
  <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Data</TYPE><ID>Day Book</ID></HEADER>
  <BODY><DESC><STATICVARIABLES>
    <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
    <SVFROMDATE>{from_str}</SVFROMDATE>
    <SVTODATE>{to_str}</SVTODATE>
    {_company_var(company)}
  </STATICVARIABLES></DESC></BODY></ENVELOPE>"""


def _all_vouchers_count_xml(company):
    """Enumerates EVERY voucher (no date filter) via a Voucher collection,
    returning just the date so we can count the true total."""
    return f"""<ENVELOPE>
  <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Data</TYPE><ID>VchDump</ID></HEADER>
  <BODY><DESC>
    <STATICVARIABLES><SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>{_company_var(company)}</STATICVARIABLES>
    <TDL><TDLMESSAGE>
      <REPORT NAME="VchDump"><FORMS>VchDump</FORMS></REPORT>
      <FORM NAME="VchDump"><TOPPARTS>VchDump</TOPPARTS></FORM>
      <PART NAME="VchDump"><TOPLINES>VDLine</TOPLINES><REPEAT>VDLine : VDColl</REPEAT><SCROLLED>Vertical</SCROLLED></PART>
      <LINE NAME="VDLine"><LEFTFIELDS>VDDate</LEFTFIELDS></LINE>
      <FIELD NAME="VDDate"><SET>$Date</SET></FIELD>
      <COLLECTION NAME="VDColl"><TYPE>Voucher</TYPE></COLLECTION>
    </TDLMESSAGE></TDL>
  </DESC></BODY></ENVELOPE>"""


def _lean_walk_xml(company, walk_target):
    """Lean voucher report that WALKs into a given sub-collection of ledger
    entries, outputting 6 small fields per entry."""
    return f"""<ENVELOPE>
  <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Data</TYPE><ID>WalkRep</ID></HEADER>
  <BODY><DESC>
    <STATICVARIABLES><SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>{_company_var(company)}</STATICVARIABLES>
    <TDL><TDLMESSAGE>
      <REPORT NAME="WalkRep"><FORMS>WalkForm</FORMS></REPORT>
      <FORM NAME="WalkForm"><TOPPARTS>WalkPart</TOPPARTS></FORM>
      <PART NAME="WalkPart"><TOPLINES>WalkLine</TOPLINES><REPEAT>WalkLine : WalkColl</REPEAT><SCROLLED>Vertical</SCROLLED></PART>
      <LINE NAME="WalkLine"><LEFTFIELDS>WDate, WType, WNo, WLedger, WAmt, WDeemed</LEFTFIELDS></LINE>
      <FIELD NAME="WDate"><SET>$Date</SET></FIELD>
      <FIELD NAME="WType"><SET>$VoucherTypeName</SET></FIELD>
      <FIELD NAME="WNo"><SET>$VoucherNumber</SET></FIELD>
      <FIELD NAME="WLedger"><SET>$LedgerName</SET></FIELD>
      <FIELD NAME="WAmt"><SET>$Amount</SET></FIELD>
      <FIELD NAME="WDeemed"><SET>$IsDeemedPositive</SET></FIELD>
      <COLLECTION NAME="WalkColl"><TYPE>Voucher</TYPE><WALK>{walk_target}</WALK></COLLECTION>
    </TDLMESSAGE></TDL>
  </DESC></BODY></ENVELOPE>"""


def _explode_xml(company, method):
    """Lean report that EXPLODEs each voucher into its ledger entries via the
    given sub-collection [method], outputting ledger + amount per entry."""
    return f"""<ENVELOPE>
  <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Data</TYPE><ID>ExpRep</ID></HEADER>
  <BODY><DESC>
    <STATICVARIABLES><SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>{_company_var(company)}</STATICVARIABLES>
    <TDL><TDLMESSAGE>
      <REPORT NAME="ExpRep"><FORMS>ExpForm</FORMS></REPORT>
      <FORM NAME="ExpForm"><TOPPARTS>ExpPart</TOPPARTS></FORM>
      <PART NAME="ExpPart"><TOPLINES>ExpVLine</TOPLINES><REPEAT>ExpVLine : ExpColl</REPEAT><SCROLLED>Vertical</SCROLLED></PART>
      <LINE NAME="ExpVLine"><TOPLINES>ExpELine</TOPLINES><REPEAT>ExpELine : {method}</REPEAT><EXPLODE>ExpELine</EXPLODE></LINE>
      <LINE NAME="ExpELine"><LEFTFIELDS>ExLedger, ExAmt</LEFTFIELDS></LINE>
      <FIELD NAME="ExLedger"><SET>$LedgerName</SET></FIELD>
      <FIELD NAME="ExAmt"><SET>$Amount</SET></FIELD>
      <COLLECTION NAME="ExpColl"><TYPE>Voucher</TYPE></COLLECTION>
    </TDLMESSAGE></TDL>
  </DESC></BODY></ENVELOPE>"""


def _field_probe_xml(company):
    """One LIGHT report over the Voucher collection outputting a few candidate
    voucher-level fields, so we can see which populate (esp. party + amount)."""
    return f"""<ENVELOPE>
  <HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Data</TYPE><ID>FldRep</ID></HEADER>
  <BODY><DESC>
    <STATICVARIABLES><SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>{_company_var(company)}</STATICVARIABLES>
    <TDL><TDLMESSAGE>
      <REPORT NAME="FldRep"><FORMS>FldForm</FORMS></REPORT>
      <FORM NAME="FldForm"><TOPPARTS>FldPart</TOPPARTS></FORM>
      <PART NAME="FldPart"><TOPLINES>FldLine</TOPLINES><REPEAT>FldLine : FldColl</REPEAT><SCROLLED>Vertical</SCROLLED></PART>
      <LINE NAME="FldLine"><LEFTFIELDS>FPD, FPT, FPN, FPParty, FPAmt</LEFTFIELDS></LINE>
      <FIELD NAME="FPD"><SET>$Date</SET></FIELD>
      <FIELD NAME="FPT"><SET>$VoucherTypeName</SET></FIELD>
      <FIELD NAME="FPN"><SET>$VoucherNumber</SET></FIELD>
      <FIELD NAME="FPParty"><SET>$PartyLedgerName</SET></FIELD>
      <FIELD NAME="FPAmt"><SET>$Amount</SET></FIELD>
      <COLLECTION NAME="FldColl"><TYPE>Voucher</TYPE></COLLECTION>
    </TDLMESSAGE></TDL>
  </DESC></BODY></ENVELOPE>"""


def probe_vouchers(requests, url, company):
    """LIGHT voucher probe. (Heavy queries crash Tally on large data, so this
    uses only small, fast requests.)"""
    hr("4B. VOUCHER FETCH PROBE (light)")

    # (i) Show the ACTUAL ledger-entry XML from one native voucher (Day Book).
    dbraw = tally_request(requests, url, _daybook_xml(company, "20240401", "20270331"))
    if dbraw:
        vb = re.search(r'<VOUCHER\b.*?</VOUCHER>', dbraw, re.DOTALL)
        if vb:
            block = vb.group(0)
            le = re.search(r'<(ALL)?LEDGERENTRIES\.LIST>.*?</(ALL)?LEDGERENTRIES\.LIST>',
                           block, re.DOTALL)
            print("  (i) One voucher's ledger entry (looking for LEDGERNAME + AMOUNT):")
            if le:
                seg = le.group(0)
                lname = re.search(r'<LEDGERNAME>(.*?)</LEDGERNAME>', seg, re.DOTALL)
                amt = re.search(r'<AMOUNT>(.*?)</AMOUNT>', seg, re.DOTALL)
                deemed = re.search(r'<ISDEEMEDPOSITIVE>(.*?)</ISDEEMEDPOSITIVE>', seg, re.DOTALL)
                print(f"      LEDGERNAME = {lname.group(1).strip() if lname else '(missing)'}")
                print(f"      AMOUNT     = {amt.group(1).strip() if amt else '(missing)'}")
                print(f"      ISDEEMEDPOSITIVE = {deemed.group(1).strip() if deemed else '(missing)'}")
            else:
                print("      No LEDGERENTRIES.LIST found in block.")
    print()

    # (ii) LIGHT field probe — which voucher-level fields populate?
    print("  (ii) Voucher-level fields (light report), first 6 rows:")
    fraw = tally_request(requests, url, _field_probe_xml(company))
    if fraw:
        dts = re.findall(r'<FPD>(.*?)</FPD>', fraw, re.DOTALL)
        tys = re.findall(r'<FPT>(.*?)</FPT>', fraw, re.DOTALL)
        nos = re.findall(r'<FPN>(.*?)</FPN>', fraw, re.DOTALL)
        parties = re.findall(r'<FPPARTY>(.*?)</FPPARTY>', fraw, re.DOTALL)
        amts = re.findall(r'<FPAMT>(.*?)</FPAMT>', fraw, re.DOTALL)
        nparty = sum(1 for p in parties if p.strip())
        namt = sum(1 for a in amts if a.strip())
        print(f"      rows: dates={len(dts)}  party non-empty={nparty}  amount non-empty={namt}")
        for i in range(min(6, len(dts))):
            p = parties[i].strip() if i < len(parties) else ''
            a = amts[i].strip() if i < len(amts) else ''
            t = tys[i].strip() if i < len(tys) else ''
            n = nos[i].strip() if i < len(nos) else ''
            print(f"      {dts[i].strip()} | {t} #{n} | party='{p}' | amount='{a}'")
    print()

    # 1) True total — enumerate ALL vouchers ignoring dates.
    rawAll = tally_request(requests, url, _all_vouchers_count_xml(company))
    total = len(findall('VDDATE', rawAll)) if rawAll else 0
    print(f"  A) ALL vouchers (no date filter):        {total}")

    # A wide range covering the whole 2024-2027 company.
    variants = [
        ("B) Day Book  yyyymmdd ", "20240401", "20270331"),
    ]
    best_raw, best_n, best_label = None, 0, None
    for label, f, t in variants:
        raw = tally_request(requests, url, _daybook_xml(company, f, t))
        n = len(re.findall(r'<VOUCHER\b', raw)) if raw else 0
        print(f"  {label}: {n}")
        if n > best_n:
            best_raw, best_n, best_label = raw, n, label

    print("\n  ── Interpretation ──")
    if total and best_n >= total * 0.5:
        print(f"  ✔ Day Book works with the '{best_label.strip()}' date format ({best_n} vouchers).")
        print("     → The sync should use THIS date format. Tell your developer.")
    elif total and best_n < max(50, total * 0.1):
        print(f"  ❌ Every Day Book variant returns far fewer than the {total} real vouchers.")
        print("     → Day Book is not honouring the date range here; the sync should")
        print("       enumerate the Voucher collection and filter by date in code instead.")
    elif total == 0:
        print("  ⚠️  Could not count total vouchers (strategy A failed) — send full output.")

    if best_raw:
        vb = re.search(r'<VOUCHER\b.*?</VOUCHER>', best_raw, re.DOTALL)
        if vb:
            print(f"\n  Raw of one voucher (best method '{best_label.strip()}'):")
            print(f"  {vb.group(0)[:1100]!r}")


def explore_vouchers(requests, url, company, days, raw_dump=False, debtor_names=None):
    hr("4. VOUCHER / STATEMENT STRUCTURE (current period)")
    try:
        to_date = datetime.now()
        from_date = to_date - timedelta(days=days)
    except Exception:
        print("  ⚠️  datetime unavailable; skipping voucher check.")
        return
    raw = tally_request(requests, url, get_vouchers_xml(from_date, to_date, company))
    if not raw:
        return
    if raw_dump:
        vb = re.search(r'<VOUCHER\b.*?</VOUCHER>', raw, re.DOTALL)
        print(f"  [raw first voucher] {(vb.group(0)[:900] if vb else raw[:600])!r}\n")

    by_ledger = parse_voucher_report(raw)
    total = sum(len(v) for v in by_ledger.values())
    print(f"✔ Parsed {total} ledger-entry line(s) across {len(by_ledger)} ledger(s).")
    if total == 0:
        print("  ❌ No ledger entries parsed — statements would be EMPTY.")
        print("     (If vouchers exist but this is 0, the Day Book tags differ — send --raw output.)")
        return

    # Voucher-type distribution across all parsed entries.
    counts = {}
    for txns in by_ledger.values():
        for t in txns:
            counts[t['voucherType']] = counts.get(t['voucherType'], 0) + 1
    print("\n  Voucher types (by entry):")
    for t, c in sorted(counts.items(), key=lambda kv: -kv[1])[:12]:
        print(f"    {c:6d}  {t or '(blank)'}")

    # Sample entries — prefer a debtor ledger so we see a real statement line.
    sample_ledger = None
    if debtor_names:
        for name in by_ledger:
            if name in debtor_names:
                sample_ledger = name
                break
    if sample_ledger is None:
        sample_ledger = next(iter(by_ledger))

    print(f"\n  Sample statement for '{sample_ledger}' (first 5 of {len(by_ledger[sample_ledger])}):")
    for t in by_ledger[sample_ledger][:5]:
        d = t['date'].strftime('%d-%b-%Y')
        print(f"    • {d} | {t['voucherType']} #{t['voucherNo']} | "
              f"{t['amount']:>12,.2f} {t['type']}")
        if t['narration']:
            print(f"      {t['narration'][:70]}")


# ---------------------------------------------------------------------------
# Firebase readiness (kept from the original diagnostic, lightly refactored)
# ---------------------------------------------------------------------------

def check_firebase():
    hr("FIREBASE CONFIGURATION CHECKS")
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
    except ImportError:
        print("❌ firebase_admin not installed. Run: pip install firebase-admin")
        return

    sa = "service-account.json"
    path = None
    for p in [sa, os.path.join(os.path.dirname(__file__) if __file__ else '.', sa)]:
        if p and os.path.exists(p):
            path = p
            break
    if not path:
        print("❌ 'service-account.json' NOT found in this folder.")
        return
    print(f"✔ Found credentials: {os.path.abspath(path)}")
    try:
        firebase_admin.initialize_app(credentials.Certificate(path))
        db = firestore.client()
        db.collection('users').limit(1).get()
        print("✔ Connected to Firestore.")
    except Exception as e:
        print(f"❌ Firestore connection failed: {e}")
        return

    for coll in ('tally_parties', 'tally_ledgers', 'tally_stock'):
        try:
            n = len(list(db.collection(coll).limit(50).stream()))
            print(f"  • '{coll}': {n}{'+' if n == 50 else ''} doc(s) from previous syncs.")
        except Exception as e:
            print(f"  • '{coll}': could not read ({e}).")
    try:
        users = list(db.collection('users').where('role', '==', 'customer').stream())
        wp = sum(1 for u in users if u.to_dict().get('phone', '').strip())
        wg = sum(1 for u in users if u.to_dict().get('gstNo', '').strip())
        wf = sum(1 for u in users if u.to_dict().get('firmName', '').strip())
        print(f"  • registered customers: {len(users)} ({wp} phone, {wg} GST, {wf} firm)")
    except Exception as e:
        print(f"  • registered customers: could not read ({e}).")


def main():
    parser = argparse.ArgumentParser(description="Tally Diagnostic & Structure Explorer")
    parser.add_argument("--company", default="SHANTINATH AGRO AGENCIES ARNI 2024-2027",
                        help="Exact Tally company name (auto-detected if it doesn't match)")
    parser.add_argument("--tally-url", default="http://localhost:9000",
                        help="Tally HTTP URL (default: http://localhost:9000)")
    parser.add_argument("--days", type=int, default=90,
                        help="Voucher window to inspect (default: 90)")
    parser.add_argument("--raw", action="store_true",
                        help="Dump raw response heads for stock & vouchers")
    args = parser.parse_args()

    hr("SYSTEM & DEPENDENCY CHECKS")
    print(f"Python: {sys.version.split()[0]}")
    if sys.version_info < (3, 6):
        print("❌ Python 3.6+ required.")

    missing = []
    for lib in ('requests', 'firebase_admin'):
        try:
            __import__(lib)
            print(f"✔ '{lib}' installed.")
        except ImportError:
            print(f"❌ '{lib}' NOT installed.")
            missing.append(lib)
    if missing:
        print("\nInstall with: pip install " + " ".join(missing))
        sys.exit(1)

    if not SYNC_IMPORT_OK:
        print(f"\n❌ Could not import parsers from tally_sync.py: {SYNC_IMPORT_ERR}")
        print("   Make sure diagnose_tally.py sits next to tally_sync.py.")
        sys.exit(1)
    print("✔ Imported live parsers from tally_sync.py.")

    import requests

    # Firebase side
    check_firebase()

    # Tally side
    hr("TALLY CONNECTIVITY")
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    port_open = False
    try:
        s.connect(('127.0.0.1', 9000))
        s.close()
        print("✔ Port 9000 is OPEN.")
        port_open = True
    except Exception:
        print("❌ Port 9000 is CLOSED — open Tally, load the company, and enable")
        print("   Help(F1) → Settings → Connectivity → HTTP Server = Yes, Port 9000.")

    if port_open:
        # Discover the ACTUAL company name(s) so a wrong --company doesn't
        # silently return 0 of everything (Tally rejects a bad SVCurrentCompany).
        hr("COMPANY DETECTION")
        companies = detect_companies(requests, args.tally_url)
        effective_company = args.company
        if companies:
            print(f"✔ Tally knows {len(companies)} company/companies:")
            for c in companies:
                mark = "  ← configured" if c == args.company else ""
                print(f"    • {c}{mark}")

            if args.company in companies:
                print(f"\n✔ Configured company name matches. Using it.")
            elif len(companies) == 1:
                effective_company = companies[0]
                print(f"\n⚠️  Configured name did NOT match. Auto-using the only open company:")
                print(f"    '{effective_company}'")
                print(f"\n  ❗ IMPORTANT: run the SYNC with this exact name:")
                print(f'     python tally_sync.py --company "{effective_company}"')
            else:
                print(f"\n⚠️  Configured name '{args.company}' is not in the list above.")
                print("   Re-run with the exact name, e.g.:")
                print(f'     python diagnose_tally.py --company "{companies[0]}"')
        else:
            print("⚠️  Could not list companies. Will try the configured name as-is.")

        print(f"\nUsing company: '{effective_company}'")
        groups = explore_groups(requests, args.tally_url, effective_company)
        debtor_names = explore_ledgers(requests, args.tally_url, effective_company, groups)
        explore_stock(requests, args.tally_url, effective_company, raw_dump=args.raw)
        explore_vouchers(requests, args.tally_url, effective_company, args.days,
                         raw_dump=args.raw, debtor_names=debtor_names)
        probe_vouchers(requests, args.tally_url, effective_company)

    hr("DIAGNOSTIC COMPLETE")
    print("Review the sections above. Anything marked ⚠️ or ❌ is worth fixing")
    print("before relying on that feature. Share this output with your developer")
    print("to tune parsers for your exact Tally setup.")


if __name__ == '__main__':
    main()
