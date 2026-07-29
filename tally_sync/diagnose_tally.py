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
        return set(), []
    names = findall('LEDNAMEF', raw)
    parents = findall('LEDPARENTF', raw)
    bals = findall('LEDBALF', raw)
    isdrs = findall('LEDISDRF', raw)
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
            'isdr_raw': isdrs[i].strip() if i < len(isdrs) else '',
            'phone_raw': phones[i].strip() if i < len(phones) else '',
            'gst': gsts[i].strip() if i < len(gsts) else '',
        })

    scope = "under 'Sundry Debtors'" if debtor_groups else "(all ledgers — Sundry Debtors group not found)"
    print(f"  → {len(debtors)} debtor ledger(s) {scope}.")

    if not debtors:
        print("  ⚠️  No debtor ledgers to analyse.")
        return set(), []

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

    # Dr/Cr flag check — the sync now trusts Tally's $$IsDebit ($ClosingBalance
    # exports as an unsigned magnitude, so parse_balance alone can't tell Dr
    # from Cr). This section proves the flag is populated AND actually finds
    # credit ledgers. If it shows "0 Cr", $$IsDebit did NOT work on this Tally
    # and credit balances would still be mislabelled — tell your developer.
    flagged = [d for d in debtors if d['isdr_raw']]
    cr = [d for d in debtors if d['isdr_raw'].strip().lower() in ('no', 'false', '0')]
    print(f"\n  Dr/Cr flag ($$IsDebit) check: {len(flagged)}/{len(debtors)} ledgers "
          f"returned a flag · {len(debtors) - len(cr)} Dr / {len(cr)} Cr")
    if not flagged:
        print("    ❌ No $$IsDebit flag came back — this Tally build may not support it.")
        print("       Credit balances will fall back to the (wrong) 'Dr' default.")
    elif not cr:
        print("    ⚠️  Flag populated but found ZERO credit ledgers — verify against Tally's")
        print("       Group Summary (Sundry Debtors should show a Credit column total).")
    else:
        print("    Sample CREDIT ledgers correctly detected:")
        for d in cr[:4]:
            print(f"      (Cr) {d['name'][:34]:34s} | bal {d['bal_raw']!r}")

    # Flag odd balance strings the parser may not expect
    odd = [d for d in debtors if d['bal_raw'] and not re.match(
        r'^-?[\d,]+(\.\d+)?\s*(Dr|Cr)?$', d['bal_raw'], re.IGNORECASE)]
    if odd:
        print(f"\n  ⚠️  {len(odd)} ledger balance(s) have an unusual format — verify parsing:")
        for d in odd[:3]:
            print(f"     '{d['name']}': {d['bal_raw']!r}")

    # Candidate ledgers most likely to have transactions (non-zero balance,
    # prefer those with a phone), used by the Ledger Statement probe below.
    def _bal_val(d):
        amt, _ = parse_balance(d['bal_raw'])
        return amt
    active = [d for d in debtors if _bal_val(d) > 0]
    active.sort(key=lambda d: (0 if sanitize_phone(d['phone_raw']) else 1, -_bal_val(d)))
    candidates = [d['name'] for d in active[:10]] or [d['name'] for d in debtors[:10]]

    return {d['name'] for d in debtors}, candidates


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


def _xml_escape(s):
    return (s or '').replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def _ledger_vouchers_xml(company, ledger_name, from_str, to_str):
    """Proven 'Ledger Vouchers' TDL (a single party's statement), adapted to XML
    export. Unlike a raw <WALK>AllLedgerEntries> (which returned empty ledger /
    amount fields on this setup), this FETCHes the ledger entries and uses
    $$FilterValue / $$FilterAmtTotal to pick out just the target ledger — the
    reliable pattern from the excelkida/dhananjay1405 query.

    Fields per voucher: FldDate, FldVoucherType, FldVoucherNumber,
    FldLedger (the contra/opposite ledger = 'particulars'), FldAmount
    (signed: negative=Dr, positive=Cr — IF the sign survives XML export) and
    FldIsDr (explicit $$IsDr flag, our reliable Dr/Cr source)."""
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


def _parse_ledger_vouchers(raw):
    """Parses the Ledger Vouchers XML response into statement rows. Dr/Cr comes
    from the explicit FldIsDr ($$IsDr) flag; the FldAmount sign is kept only as
    a cross-check (it may not survive XML export)."""
    dates = findall('FLDDATE', raw)
    vtypes = findall('FLDVOUCHERTYPE', raw)
    vnos = findall('FLDVOUCHERNUMBER', raw)
    parties = findall('FLDLEDGER', raw)
    amts = findall('FLDAMOUNT', raw)
    isdrs = findall('FLDISDR', raw)
    narrs = findall('FLDNARRATION', raw)
    rows = []
    for i in range(len(dates)):
        signed = _parse_signed_amount(amts[i] if i < len(amts) else '')
        flag = (isdrs[i].strip().lower() if i < len(isdrs) else '')
        if flag in ('yes', 'true', '1'):
            typ = 'Dr'
        elif flag in ('no', 'false', '0'):
            typ = 'Cr'
        else:
            typ = 'Dr' if signed < 0 else 'Cr'  # fall back to the amount sign
        rows.append({
            'date': dates[i].strip(),
            'vtype': vtypes[i].strip() if i < len(vtypes) else '',
            'vno': vnos[i].strip() if i < len(vnos) else '',
            'party': parties[i].strip() if i < len(parties) else '',
            'amount': abs(signed),
            'signed': signed,
            'flag': flag,
            'type': typ,
            'narration': narrs[i].strip() if i < len(narrs) else '',
        })
    return rows


def probe_ledger_statement(requests, url, company, candidates, chosen='', raw_dump=False):
    hr("5. LEDGER STATEMENT PROBE (Ledger Vouchers report)")
    print("Tests the proven per-party 'Ledger Vouchers' TDL — the correct source")
    print("for the app's Account Statement (customer list + admin drill-down).")

    targets = ([chosen] if chosen else []) + [c for c in candidates if c != chosen]
    if not targets:
        print('  ⚠️  No candidate ledger to test. Pass one with --ledger "NAME".')
        return

    frm, to = "20240401", "20270331"   # whole 2024-2027 company period
    tried = 0
    for name in targets:
        if tried >= 6:
            break
        tried += 1
        raw = tally_request(requests, url, _ledger_vouchers_xml(company, name, frm, to))
        if not raw:
            print(f"  • {name[:42]:42s} → request failed / empty")
            continue
        if raw_dump:
            print(f"  [raw head for '{name}'] {raw[:600]!r}\n")
        rows = _parse_ledger_vouchers(raw)
        if not rows:
            print(f"  • {name[:42]:42s} → 0 vouchers")
            continue

        dr = sum(r['amount'] for r in rows if r['type'] == 'Dr')
        cr = sum(r['amount'] for r in rows if r['type'] == 'Cr')
        n_dr = sum(1 for r in rows if r['type'] == 'Dr')
        n_cr = sum(1 for r in rows if r['type'] == 'Cr')
        sign_kept = any(r['signed'] < 0 for r in rows)
        flagged = sum(1 for r in rows if r['flag'])

        print(f"\n  ✔ '{name}' → {len(rows)} voucher(s) in {frm}–{to}")
        print(f"    Totals: Dr Rs {dr:,.2f} ({n_dr}) · Cr Rs {cr:,.2f} ({n_cr})")
        print(f"    FldIsDr flag returned on {flagged}/{len(rows)} rows "
              f"(this is what we'll trust for Dr/Cr).")
        print(f"    FldAmount sign survived XML export: "
              f"{'YES' if sign_kept else 'NO — good thing we added the $$IsDr flag'}")
        print("\n    First 8 rows (date | type #no | particulars | amount):")
        for r in rows[:8]:
            print(f"      {r['date']:>11} | {r['vtype'][:16]:16s} #{r['vno'][:8]:8s} | "
                  f"{r['party'][:22]:22s} | Rs {r['amount']:>13,.2f} {r['type']}")
            if r['narration']:
                print(f"          note: {r['narration'][:60]}")
        print("\n  → If these rows match this party's statement in Tally (Display →")
        print("    Account Books → Ledger), this is the method to wire into the sync.")
        return

    print(f"\n  ⚠️  Tried {tried} ledger(s); none returned vouchers in {frm}–{to}.")
    print("     Pick a party you KNOW has transactions and re-run, e.g.:")
    print('       python diagnose_tally.py --ledger "AAI KRISHI KENDRA MANGRUL"')


def _walk_inventory_xml(company, ledger_name, from_str, to_str):
    """Walks AllInventoryEntries of the party's vouchers (tally-database-loader
    pattern: TYPE Voucher + FETCH + WALK — the FETCH is what our old attempt
    lacked). One row per invoice line: voucher date/no/type + item/qty/rate/amt."""
    led = _xml_escape(ledger_name)
    comp = f"<SVCURRENTCOMPANY>{_xml_escape(company)}</SVCURRENTCOMPANY>" if company else ""
    return (
        '<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST>'
        '<TYPE>Data</TYPE><ID>StnInv</ID></HEADER><BODY><DESC><STATICVARIABLES>'
        f'<SVFROMDATE>{from_str}</SVFROMDATE><SVTODATE>{to_str}</SVTODATE>'
        '<SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>'
        f'{comp}</STATICVARIABLES><TDL><TDLMESSAGE>'
        '<REPORT NAME="StnInv"><FORMS>StnInvForm</FORMS></REPORT>'
        '<FORM NAME="StnInvForm"><PARTS>StnInvPart</PARTS></FORM>'
        '<PART NAME="StnInvPart"><LINES>StnInvLine</LINES>'
        '<REPEAT>StnInvLine : StnInvColl</REPEAT><SCROLLED>Vertical</SCROLLED></PART>'
        '<LINE NAME="StnInvLine"><FIELDS>InvDate,InvNo,InvType,InvItem,InvQty,InvRate,InvAmt</FIELDS></LINE>'
        '<FIELD NAME="InvDate"><SET>$Date</SET></FIELD>'
        '<FIELD NAME="InvNo"><SET>$VoucherNumber</SET></FIELD>'
        '<FIELD NAME="InvType"><SET>$VoucherTypeName</SET></FIELD>'
        '<FIELD NAME="InvItem"><SET>$StockItemName</SET></FIELD>'
        '<FIELD NAME="InvQty"><SET>$ActualQty</SET></FIELD>'
        '<FIELD NAME="InvRate"><SET>$Rate</SET></FIELD>'
        '<FIELD NAME="InvAmt"><SET>$Amount</SET></FIELD>'
        '<COLLECTION NAME="StnInvColl"><TYPE>Voucher</TYPE>'
        '<FETCH>AllInventoryEntries,AllLedgerEntries</FETCH>'
        '<WALK>AllInventoryEntries</WALK>'
        '<FILTER>FilterCancelledVouchers,FilterOptionalVouchers,FilterVch</FILTER></COLLECTION>'
        '<SYSTEM TYPE="Formulae" NAME="FilterVch">NOT $$IsEmpty:($$FilterValue:$LedgerName:AllLedgerEntries:First:FilterVchLedger)</SYSTEM>'
        f'<SYSTEM TYPE="Formulae" NAME="FilterVchLedger">$$IsEqual:$LedgerName:"{led}"</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FilterCancelledVouchers">NOT $IsCancelled</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FilterOptionalVouchers">NOT $IsOptional</SYSTEM>'
        '</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>'
    )


def _walk_ledgers_xml(company, ledger_name, from_str, to_str):
    """Walks AllLedgerEntries of the party's vouchers — gives the full ledger
    breakup per voucher (party + sales ledger + CGST/SGST tax ledgers)."""
    led = _xml_escape(ledger_name)
    comp = f"<SVCURRENTCOMPANY>{_xml_escape(company)}</SVCURRENTCOMPANY>" if company else ""
    return (
        '<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST>'
        '<TYPE>Data</TYPE><ID>StnLed</ID></HEADER><BODY><DESC><STATICVARIABLES>'
        f'<SVFROMDATE>{from_str}</SVFROMDATE><SVTODATE>{to_str}</SVTODATE>'
        '<SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>'
        f'{comp}</STATICVARIABLES><TDL><TDLMESSAGE>'
        '<REPORT NAME="StnLed"><FORMS>StnLedForm</FORMS></REPORT>'
        '<FORM NAME="StnLedForm"><PARTS>StnLedPart</PARTS></FORM>'
        '<PART NAME="StnLedPart"><LINES>StnLedLine</LINES>'
        '<REPEAT>StnLedLine : StnLedColl</REPEAT><SCROLLED>Vertical</SCROLLED></PART>'
        '<LINE NAME="StnLedLine"><FIELDS>LedDate,LedNo,LedType,LedName,LedAmt,LedIsDr</FIELDS></LINE>'
        '<FIELD NAME="LedDate"><SET>$Date</SET></FIELD>'
        '<FIELD NAME="LedNo"><SET>$VoucherNumber</SET></FIELD>'
        '<FIELD NAME="LedType"><SET>$VoucherTypeName</SET></FIELD>'
        '<FIELD NAME="LedName"><SET>$LedgerName</SET></FIELD>'
        '<FIELD NAME="LedAmt"><SET>$Amount</SET></FIELD>'
        '<FIELD NAME="LedIsDr"><SET>$$IsDr:$Amount</SET></FIELD>'
        '<COLLECTION NAME="StnLedColl"><TYPE>Voucher</TYPE>'
        '<FETCH>AllLedgerEntries</FETCH>'
        '<WALK>AllLedgerEntries</WALK>'
        '<FILTER>FilterCancelledVouchers,FilterOptionalVouchers,FilterVch</FILTER></COLLECTION>'
        '<SYSTEM TYPE="Formulae" NAME="FilterVch">NOT $$IsEmpty:($$FilterValue:$LedgerName:AllLedgerEntries:First:FilterVchLedger)</SYSTEM>'
        f'<SYSTEM TYPE="Formulae" NAME="FilterVchLedger">$$IsEqual:$LedgerName:"{led}"</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FilterCancelledVouchers">NOT $IsCancelled</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FilterOptionalVouchers">NOT $IsOptional</SYSTEM>'
        '</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>'
    )


def _parse_inventory_walk(raw):
    dates = findall('INVDATE', raw)
    nos = findall('INVNO', raw)
    types = findall('INVTYPE', raw)
    items = findall('INVITEM', raw)
    qtys = findall('INVQTY', raw)
    rates = findall('INVRATE', raw)
    amts = findall('INVAMT', raw)
    rows = []
    for i in range(len(items)):
        qv, qu = parse_quantity(qtys[i]) if i < len(qtys) else (0.0, '')
        rows.append({
            'date': dates[i].strip() if i < len(dates) else '',
            'vno': nos[i].strip() if i < len(nos) else '',
            'vtype': types[i].strip() if i < len(types) else '',
            'item': items[i].strip(),
            'qty': qv, 'unit': qu,
            'rate': abs(_parse_signed_amount(rates[i])) if i < len(rates) else 0.0,
            'amount': abs(_parse_signed_amount(amts[i])) if i < len(amts) else 0.0,
        })
    return rows


def _parse_ledger_walk(raw):
    nos = findall('LEDNO', raw)
    names = findall('LEDNAME', raw)
    amts = findall('LEDAMT', raw)
    isdrs = findall('LEDISDR', raw)
    rows = []
    for i in range(len(names)):
        signed = _parse_signed_amount(amts[i]) if i < len(amts) else 0.0
        flag = (isdrs[i].strip().lower() if i < len(isdrs) else '')
        if flag in ('yes', 'true', '1'):
            typ = 'Dr'
        elif flag in ('no', 'false', '0'):
            typ = 'Cr'
        else:
            typ = 'Dr' if signed < 0 else 'Cr'
        rows.append({
            'vno': nos[i].strip() if i < len(nos) else '',
            'ledger': names[i].strip(),
            'amount': abs(signed),
            'type': typ,
        })
    return rows


def _explode_inventory_xml(company, ledger_name, from_str, to_str):
    """EXPLODE pattern: outer voucher line explodes a sub-part that REPEATs over
    AllInventoryEntries — the classic invoice-print construct. Each item line
    carries its parent voucher number ($VoucherNumber) so we can regroup."""
    led = _xml_escape(ledger_name)
    comp = f"<SVCURRENTCOMPANY>{_xml_escape(company)}</SVCURRENTCOMPANY>" if company else ""
    return (
        '<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST>'
        '<TYPE>Data</TYPE><ID>StnInvX</ID></HEADER><BODY><DESC><STATICVARIABLES>'
        f'<SVFROMDATE>{from_str}</SVFROMDATE><SVTODATE>{to_str}</SVTODATE>'
        '<SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>'
        f'{comp}</STATICVARIABLES><TDL><TDLMESSAGE>'
        '<REPORT NAME="StnInvX"><FORMS>StnInvXF</FORMS></REPORT>'
        '<FORM NAME="StnInvXF"><PARTS>StnInvXP</PARTS></FORM>'
        '<PART NAME="StnInvXP"><TOPLINES>StnInvXV</TOPLINES>'
        '<REPEAT>StnInvXV : StnInvXC</REPEAT><SCROLLED>Vertical</SCROLLED></PART>'
        '<LINE NAME="StnInvXV"><FIELDS>XVHdr</FIELDS><EXPLODE>StnInvXIP</EXPLODE></LINE>'
        '<FIELD NAME="XVHdr"><SET>$VoucherNumber</SET></FIELD>'
        '<PART NAME="StnInvXIP"><TOPLINES>StnInvXI</TOPLINES>'
        '<REPEAT>StnInvXI : AllInventoryEntries</REPEAT><SCROLLED>Vertical</SCROLLED></PART>'
        '<LINE NAME="StnInvXI"><FIELDS>XINo,XItem,XQty,XBQty,XRate,XAmt</FIELDS></LINE>'
        '<FIELD NAME="XINo"><SET>$VoucherNumber</SET></FIELD>'
        '<FIELD NAME="XItem"><SET>$StockItemName</SET></FIELD>'
        '<FIELD NAME="XQty"><SET>$ActualQty</SET></FIELD>'
        '<FIELD NAME="XBQty"><SET>$BilledQty</SET></FIELD>'
        '<FIELD NAME="XRate"><SET>$Rate</SET></FIELD>'
        '<FIELD NAME="XAmt"><SET>$Amount</SET></FIELD>'
        '<COLLECTION NAME="StnInvXC"><TYPE>Voucher</TYPE>'
        '<FETCH>AllInventoryEntries,AllLedgerEntries</FETCH>'
        '<FILTER>FilterCancelledVouchers,FilterOptionalVouchers,FilterVch</FILTER></COLLECTION>'
        '<SYSTEM TYPE="Formulae" NAME="FilterVch">NOT $$IsEmpty:($$FilterValue:$LedgerName:AllLedgerEntries:First:FilterVchLedger)</SYSTEM>'
        f'<SYSTEM TYPE="Formulae" NAME="FilterVchLedger">$$IsEqual:$LedgerName:"{led}"</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FilterCancelledVouchers">NOT $IsCancelled</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FilterOptionalVouchers">NOT $IsOptional</SYSTEM>'
        '</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>'
    )


def _explode_ledgers_xml(company, ledger_name, from_str, to_str):
    """EXPLODE over AllLedgerEntries — full ledger breakup per voucher (party +
    sales ledger + CGST/SGST tax ledgers), each row tagged with its voucher no."""
    led = _xml_escape(ledger_name)
    comp = f"<SVCURRENTCOMPANY>{_xml_escape(company)}</SVCURRENTCOMPANY>" if company else ""
    return (
        '<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST>'
        '<TYPE>Data</TYPE><ID>StnLedX</ID></HEADER><BODY><DESC><STATICVARIABLES>'
        f'<SVFROMDATE>{from_str}</SVFROMDATE><SVTODATE>{to_str}</SVTODATE>'
        '<SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>'
        f'{comp}</STATICVARIABLES><TDL><TDLMESSAGE>'
        '<REPORT NAME="StnLedX"><FORMS>StnLedXF</FORMS></REPORT>'
        '<FORM NAME="StnLedXF"><PARTS>StnLedXP</PARTS></FORM>'
        '<PART NAME="StnLedXP"><TOPLINES>StnLedXV</TOPLINES>'
        '<REPEAT>StnLedXV : StnLedXC</REPEAT><SCROLLED>Vertical</SCROLLED></PART>'
        '<LINE NAME="StnLedXV"><FIELDS>YVHdr</FIELDS><EXPLODE>StnLedXEP</EXPLODE></LINE>'
        '<FIELD NAME="YVHdr"><SET>$VoucherNumber</SET></FIELD>'
        '<PART NAME="StnLedXEP"><TOPLINES>StnLedXE</TOPLINES>'
        '<REPEAT>StnLedXE : AllLedgerEntries</REPEAT><SCROLLED>Vertical</SCROLLED></PART>'
        '<LINE NAME="StnLedXE"><FIELDS>YINo,YLed,YAmt,YIsDr</FIELDS></LINE>'
        '<FIELD NAME="YINo"><SET>$VoucherNumber</SET></FIELD>'
        '<FIELD NAME="YLed"><SET>$LedgerName</SET></FIELD>'
        '<FIELD NAME="YAmt"><SET>$Amount</SET></FIELD>'
        '<FIELD NAME="YIsDr"><SET>$$IsDr:$Amount</SET></FIELD>'
        '<COLLECTION NAME="StnLedXC"><TYPE>Voucher</TYPE>'
        '<FETCH>AllLedgerEntries</FETCH>'
        '<FILTER>FilterCancelledVouchers,FilterOptionalVouchers,FilterVch</FILTER></COLLECTION>'
        '<SYSTEM TYPE="Formulae" NAME="FilterVch">NOT $$IsEmpty:($$FilterValue:$LedgerName:AllLedgerEntries:First:FilterVchLedger)</SYSTEM>'
        f'<SYSTEM TYPE="Formulae" NAME="FilterVchLedger">$$IsEqual:$LedgerName:"{led}"</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FilterCancelledVouchers">NOT $IsCancelled</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FilterOptionalVouchers">NOT $IsOptional</SYSTEM>'
        '</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>'
    )


def _parse_explode_inventory(raw):
    nos = findall('XINO', raw)
    items = findall('XITEM', raw)
    qtys = findall('XQTY', raw)
    bqtys = findall('XBQTY', raw)
    rates = findall('XRATE', raw)
    amts = findall('XAMT', raw)
    rows = []
    for i in range(len(items)):
        qv, qu = parse_quantity(qtys[i]) if i < len(qtys) else (0.0, '')
        if qv == 0 and i < len(bqtys):
            qv, qu2 = parse_quantity(bqtys[i])
            qu = qu or qu2
        rows.append({
            'vno': nos[i].strip() if i < len(nos) else '',
            'item': items[i].strip(),
            'qty': qv, 'unit': qu,
            'rate': abs(_parse_signed_amount(rates[i])) if i < len(rates) else 0.0,
            'amount': abs(_parse_signed_amount(amts[i])) if i < len(amts) else 0.0,
        })
    return rows


def _parse_explode_ledgers(raw):
    nos = findall('YINO', raw)
    leds = findall('YLED', raw)
    amts = findall('YAMT', raw)
    isdrs = findall('YISDR', raw)
    rows = []
    for i in range(len(leds)):
        signed = _parse_signed_amount(amts[i]) if i < len(amts) else 0.0
        flag = (isdrs[i].strip().lower() if i < len(isdrs) else '')
        if flag in ('yes', 'true', '1'):
            typ = 'Dr'
        elif flag in ('no', 'false', '0'):
            typ = 'Cr'
        else:
            typ = 'Dr' if signed < 0 else 'Cr'
        rows.append({
            'vno': nos[i].strip() if i < len(nos) else '',
            'ledger': leds[i].strip(),
            'amount': abs(signed),
            'type': typ,
        })
    return rows


def probe_invoice(requests, url, company, candidates, chosen='', raw_dump=False):
    hr("6. INVOICE / BILL EXTRACTION PROBE (line items + tax)")
    print("Tests two ways to pull invoice line items — WALK vs nested EXPLODE —")
    print("and reports which returns real qty + rate + tax (for the 'Bills' tab).")

    targets = ([chosen] if chosen else []) + [c for c in candidates if c != chosen]
    if not targets:
        print('  ⚠️  No candidate ledger. Pass one with --ledger "NAME".')
        return

    frm, to = "20240401", "20270331"
    for name in targets[:6]:
        st_raw = tally_request(requests, url, _ledger_vouchers_xml(company, name, frm, to))
        st = _parse_ledger_vouchers(st_raw) if st_raw else []
        sales = [r for r in st if any(k in r['vtype'].lower() for k in ('sale', 'invoice'))]
        if not sales:
            print(f"  • {name[:40]:40s} → no sales vouchers in statement, trying next")
            continue

        invA = _parse_inventory_walk(
            tally_request(requests, url, _walk_inventory_xml(company, name, frm, to)) or '')
        invB_raw = tally_request(requests, url, _explode_inventory_xml(company, name, frm, to))
        ledB_raw = tally_request(requests, url, _explode_ledgers_xml(company, name, frm, to))
        invB = _parse_explode_inventory(invB_raw) if invB_raw else []
        ledB = _parse_explode_ledgers(ledB_raw) if ledB_raw else []

        if raw_dump:
            print(f"\n  [EXPLODE inventory raw head] {(invB_raw or '')[:900]!r}")
            print(f"\n  [EXPLODE ledger raw head]    {(ledB_raw or '')[:900]!r}\n")

        a_ok = any(r['qty'] > 0 or r['rate'] > 0 for r in invA)
        b_ok = any(r['qty'] > 0 or r['rate'] > 0 for r in invB)
        print(f"\n  Party '{name}'")
        print(f"    Method A  WALK   : {len(invA):>4} inv line(s) · qty/rate present: {'YES' if a_ok else 'NO'}")
        print(f"    Method B  EXPLODE: {len(invB):>4} inv line(s) · qty/rate present: {'YES' if b_ok else 'NO'}")
        print(f"    Tax/ledger lines (EXPLODE): {len(ledB)}")

        inv = invB if b_ok else (invA if a_ok else (invB or invA))
        if not inv:
            print("    ❌ No inventory lines from either method — re-run with --raw and send")
            print("       me the [EXPLODE ... raw head] lines so I can adjust the TDL.")
            return

        target = sales[0]['vno']
        items = [r for r in inv if r['vno'] == target]
        if not items:
            target = inv[0]['vno']
            items = [r for r in inv if r['vno'] == target]
        ledgers = [r for r in ledB if r['vno'] == target]

        method = 'EXPLODE' if inv is invB else 'WALK'
        print(f"\n  ── Reconstructed invoice #{target}  (via {method}) ──")
        print("    Line items:")
        taxable = 0.0
        for it in items:
            taxable += it['amount']
            print(f"      {it['item'][:30]:30s} {it['qty']:>8,.2f} {it['unit'][:4]:4s} "
                  f"@ {it['rate']:>10,.2f} = Rs {it['amount']:>12,.2f}")
        print(f"    Taxable value: Rs {taxable:,.2f}")
        if ledgers:
            print("    Ledger / tax breakup (party + sales + GST):")
            for l in ledgers:
                print(f"      {l['ledger'][:36]:36s} Rs {l['amount']:>12,.2f} {l['type']}")
        else:
            print("    (no ledger/tax lines regrouped for this voucher — check EXPLODE ledger head)")
        print("\n  → Whichever method shows real qty + rate + tax is the one we wire in.")
        return

    print("\n  ⚠️  None of the tried ledgers yielded a sales invoice with line items.")
    print('     Re-run targeting a party you know has sales: --ledger "NAME" --raw')


def _bulk_ledgers_xml(company, from_str, to_str):
    """ONE pass: explode AllLedgerEntries of EVERY voucher in the window (no
    party filter). Each row = (voucher no + date + type, ledger, amount, Dr/Cr).
    Python then buckets by ledger to build every party's statement at once."""
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
        '<LINE NAME="BLE"><FIELDS>CNo,CDate,CType,CLed,CAmt,CIsDr,CMid</FIELDS></LINE>'
        '<FIELD NAME="CNo"><SET>$VoucherNumber</SET></FIELD>'
        '<FIELD NAME="CDate"><SET>$Date</SET></FIELD>'
        '<FIELD NAME="CType"><SET>$VoucherTypeName</SET></FIELD>'
        '<FIELD NAME="CLed"><SET>$LedgerName</SET></FIELD>'
        '<FIELD NAME="CAmt"><SET>$Amount</SET></FIELD>'
        '<FIELD NAME="CIsDr"><SET>$$IsDr:$Amount</SET></FIELD>'
        '<FIELD NAME="CMid"><SET>$MasterId</SET></FIELD>'
        '<COLLECTION NAME="BLC"><TYPE>Voucher</TYPE><FETCH>AllLedgerEntries</FETCH>'
        '<FILTER>FBulkCancel,FBulkOpt</FILTER></COLLECTION>'
        '<SYSTEM TYPE="Formulae" NAME="FBulkCancel">NOT $IsCancelled</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FBulkOpt">NOT $IsOptional</SYSTEM>'
        '</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>'
    )


def _bulk_inventory_xml(company, from_str, to_str):
    """ONE pass: explode AllInventoryEntries of EVERY voucher in the window.
    Each row = (voucher no + date, party ledger, item, qty, rate, amount).
    Python buckets by party+voucher to build every invoice at once."""
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
        '<LINE NAME="BIE"><FIELDS>BNo,BDate,BParty,BItem,BQty,BAQty,BRate,BAmt,BMid</FIELDS></LINE>'
        '<FIELD NAME="BNo"><SET>$VoucherNumber</SET></FIELD>'
        '<FIELD NAME="BDate"><SET>$Date</SET></FIELD>'
        '<FIELD NAME="BParty"><SET>$PartyLedgerName</SET></FIELD>'
        '<FIELD NAME="BItem"><SET>$StockItemName</SET></FIELD>'
        '<FIELD NAME="BQty"><SET>$BilledQty</SET></FIELD>'
        '<FIELD NAME="BAQty"><SET>$ActualQty</SET></FIELD>'
        '<FIELD NAME="BRate"><SET>$Rate</SET></FIELD>'
        '<FIELD NAME="BAmt"><SET>$Amount</SET></FIELD>'
        '<FIELD NAME="BMid"><SET>$MasterId</SET></FIELD>'
        '<COLLECTION NAME="BIC"><TYPE>Voucher</TYPE><FETCH>AllInventoryEntries</FETCH>'
        '<FILTER>FBulkCancel,FBulkOpt</FILTER></COLLECTION>'
        '<SYSTEM TYPE="Formulae" NAME="FBulkCancel">NOT $IsCancelled</SYSTEM>'
        '<SYSTEM TYPE="Formulae" NAME="FBulkOpt">NOT $IsOptional</SYSTEM>'
        '</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>'
    )


def _parse_bulk_ledgers(raw):
    nos = findall('CNO', raw)
    leds = findall('CLED', raw)
    amts = findall('CAMT', raw)
    isdrs = findall('CISDR', raw)
    mids = findall('CMID', raw)
    rows = []
    for i in range(len(leds)):
        signed = _parse_signed_amount(amts[i]) if i < len(amts) else 0.0
        flag = (isdrs[i].strip().lower() if i < len(isdrs) else '')
        typ = 'Dr' if flag in ('yes', 'true', '1') else ('Cr' if flag in ('no', 'false', '0')
              else ('Dr' if signed < 0 else 'Cr'))
        rows.append({
            'vno': nos[i].strip() if i < len(nos) else '',
            'mid': mids[i].strip() if i < len(mids) else '',
            'ledger': leds[i].strip(),
            'amount': abs(signed), 'type': typ,
        })
    return rows


def _parse_bulk_inventory(raw):
    nos = findall('BNO', raw)
    parties = findall('BPARTY', raw)
    items = findall('BITEM', raw)
    qtys = findall('BQTY', raw)
    aqtys = findall('BAQTY', raw)
    rates = findall('BRATE', raw)
    amts = findall('BAMT', raw)
    mids = findall('BMID', raw)
    rows = []
    for i in range(len(items)):
        qv, qu = parse_quantity(qtys[i]) if i < len(qtys) else (0.0, '')
        if qv == 0 and i < len(aqtys):
            qv, qu2 = parse_quantity(aqtys[i])
            qu = qu or qu2
        rows.append({
            'vno': nos[i].strip() if i < len(nos) else '',
            'mid': mids[i].strip() if i < len(mids) else '',
            'party': parties[i].strip() if i < len(parties) else '',
            'item': items[i].strip(),
            'qty': qv, 'unit': qu,
            'rate': abs(_parse_signed_amount(rates[i])) if i < len(rates) else 0.0,
            'amount': abs(_parse_signed_amount(amts[i])) if i < len(amts) else 0.0,
        })
    return rows


def probe_hsn_batch(requests, url, company, days=90, raw_dump=False):
    """Section 8 — find the TDL expressions that yield HSN/SAC and Batch on an
    exploded inventory entry.

    These two columns are on the printed TAX INVOICE but are NOT in the sync
    yet, deliberately: Tally fails the ENTIRE export when a TDL references a
    method it doesn't recognise, so guessing inside the working
    get_bulk_inventory_xml would take the invoice pipeline down with it. Each
    candidate below is therefore sent as its own isolated request — a candidate
    that errors costs nothing but that one request.

    Whichever candidates come back populated are the ones to wire into
    tally_sync.get_bulk_inventory_xml (add the FIELD + its tag to the LINE, then
    read it in parse_bulk_inventory into the row's 'hsn' / 'batch' key, which
    already exist and currently default to '')."""
    hr("8. HSN / BATCH FIELD PROBE (for the TAX INVOICE format)")

    to_date = datetime.now()
    from_date = to_date - timedelta(days=days)
    fs, ts = from_date.strftime('%Y%m%d'), to_date.strftime('%Y%m%d')
    comp = f"<SVCURRENTCOMPANY>{_xml_escape(company)}</SVCURRENTCOMPANY>" if company else ""

    # (label, TDL expression). Ordered most- to least-likely.
    candidates = [
        ('hsn',   '$GSTHSNCode:StockItem:$StockItemName'),
        ('hsn',   '$GSTItemHSNCodeEx'),
        ('hsn',   '$GSTHSNCode'),
        ('hsn',   '$HSNCode'),
        ('hsn',   '$HSNCode:GSTDetails:[Last]'),
        ('hsn',   '$$StockItemHSN:$StockItemName'),
        ('hsn',   '$GSTDetails'),
        ('batch', '$BatchName'),
        ('batch', '$$FilterValue:$BatchName:BatchAllocations:First:FBAny'),
        ('batch', '$$CollectionFieldByKey:$BatchName:1:BatchAllocations'),
    ]

    def payload(expr):
        return (
            '<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST>'
            '<TYPE>Data</TYPE><ID>StnProbeHB</ID></HEADER><BODY><DESC><STATICVARIABLES>'
            f'<SVFROMDATE>{fs}</SVFROMDATE><SVTODATE>{ts}</SVTODATE>'
            '<SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>'
            f'{comp}</STATICVARIABLES><TDL><TDLMESSAGE>'
            '<REPORT NAME="StnProbeHB"><FORMS>PHF</FORMS></REPORT>'
            '<FORM NAME="PHF"><PARTS>PHP</PARTS></FORM>'
            '<PART NAME="PHP"><TOPLINES>PHV</TOPLINES><REPEAT>PHV : PHC</REPEAT>'
            '<SCROLLED>Vertical</SCROLLED></PART>'
            '<LINE NAME="PHV"><FIELDS>PHdr</FIELDS><EXPLODE>PHEP</EXPLODE></LINE>'
            '<FIELD NAME="PHdr"><SET>$VoucherNumber</SET></FIELD>'
            '<PART NAME="PHEP"><TOPLINES>PHE</TOPLINES>'
            '<REPEAT>PHE : AllInventoryEntries</REPEAT><SCROLLED>Vertical</SCROLLED></PART>'
            '<LINE NAME="PHE"><FIELDS>PItem,PVal</FIELDS></LINE>'
            '<FIELD NAME="PItem"><SET>$StockItemName</SET></FIELD>'
            f'<FIELD NAME="PVal"><SET>{expr}</SET></FIELD>'
            '<COLLECTION NAME="PHC"><TYPE>Voucher</TYPE>'
            '<FETCH>AllInventoryEntries,BatchAllocations</FETCH>'
            '<FILTER>FPCancel</FILTER></COLLECTION>'
            '<SYSTEM TYPE="Formulae" NAME="FPCancel">NOT $IsCancelled</SYSTEM>'
            '<SYSTEM TYPE="Formulae" NAME="FBAny">$$IsEmpty:$$Nothing OR NOT $$IsEmpty:$BatchName</SYSTEM>'
            '</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>'
        )

    headers = {'Content-Type': 'text/xml; charset=utf-8'}
    winners = {}
    for kind, expr in candidates:
        try:
            r = requests.post(url, data=payload(expr), headers=headers, timeout=120)
            r.raise_for_status()
            raw = r.content.decode('utf-8', errors='ignore')
        except Exception as e:
            print(f"  ❌ {kind:5} {expr:58} request failed ({type(e).__name__})")
            continue

        if '<LINEERROR>' in raw.upper() or 'Unknown' in raw[:400]:
            print(f"  ❌ {kind:5} {expr:58} rejected by Tally")
            continue

        vals = [v.strip() for v in re.findall(r'<PVAL>(.*?)</PVAL>', raw, re.DOTALL)]
        items = [v.strip() for v in re.findall(r'<PITEM>(.*?)</PITEM>', raw, re.DOTALL)]
        filled = [v for v in vals if v]
        if not vals:
            print(f"  ⚠️  {kind:5} {expr:58} no rows returned")
        elif not filled:
            print(f"  ⚠️  {kind:5} {expr:58} {len(vals)} rows, ALL EMPTY")
        else:
            pct = 100 * len(filled) / len(vals)
            sample = ', '.join(f"{i}={v}" for i, v in list(zip(items, vals))[:3] if v)
            print(f"  ✅ {kind:5} {expr:58} {len(filled)}/{len(vals)} filled ({pct:.0f}%)")
            print(f"       e.g. {sample[:110]}")
            winners.setdefault(kind, expr)
        if raw_dump:
            print(f"       --- raw head ---\n{raw[:600]}\n")

    print()
    if winners:
        print("  WIRE THESE INTO tally_sync.get_bulk_inventory_xml:")
        for kind, expr in winners.items():
            print(f"    {kind}: {expr}")
    else:
        print("  No candidate worked. HSN/Batch may not be set on these stock items,")
        print("  or this Tally exposes them under a different method — check a stock")
        print("  item's GST Details in Tally before extending the TDL.")

    # ── Stock-item-master-level HSN probe ──
    # HSN lives in GSTDETAILS.LIST on the Stock Item master, not on voucher
    # inventory entries. Probe the Stock Item collection directly.
    if 'hsn' not in winners:
        print("\n  ── Stock Item master HSN probe (GSTDETAILS.LIST) ──")
        stk_candidates = [
            '$$CollectionField:$HSNCode:1:GSTDetails',
            '$HSNCode:GSTDetails:[Last]',
            '$GSTHSNCode',
            '$HSNCode',
        ]

        def stk_payload(expr):
            return (
                '<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST>'
                '<TYPE>Data</TYPE><ID>StnProbeStk</ID></HEADER><BODY><DESC><STATICVARIABLES>'
                '<SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>'
                f'{comp}</STATICVARIABLES><TDL><TDLMESSAGE>'
                '<REPORT NAME="StnProbeStk"><FORMS>PSF</FORMS></REPORT>'
                '<FORM NAME="PSF"><PARTS>PSP</PARTS></FORM>'
                '<PART NAME="PSP"><TOPLINES>PSL</TOPLINES><REPEAT>PSL : PSC</REPEAT>'
                '<SCROLLED>Vertical</SCROLLED></PART>'
                '<LINE NAME="PSL"><FIELDS>PItem,PVal</FIELDS></LINE>'
                '<FIELD NAME="PItem"><SET>$Name</SET></FIELD>'
                f'<FIELD NAME="PVal"><SET>{expr}</SET></FIELD>'
                '<COLLECTION NAME="PSC"><TYPE>Stock Item</TYPE>'
                '<FETCH>GSTDetails</FETCH></COLLECTION>'
                '</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>'
            )

        for expr in stk_candidates:
            try:
                r = requests.post(url, data=stk_payload(expr), headers=headers, timeout=60)
                r.raise_for_status()
                raw = r.content.decode('utf-8', errors='ignore')
            except Exception as e:
                print(f"    ❌ {expr:55} request failed ({type(e).__name__})")
                continue

            if '<LINEERROR>' in raw.upper() or 'Unknown' in raw[:400]:
                print(f"    ❌ {expr:55} rejected by Tally")
                continue

            vals = [v.strip() for v in re.findall(r'<PVAL>(.*?)</PVAL>', raw, re.DOTALL)]
            items = [v.strip() for v in re.findall(r'<PITEM>(.*?)</PITEM>', raw, re.DOTALL)]
            filled = [v for v in vals if v]
            if not vals:
                print(f"    ⚠️  {expr:55} no rows returned")
            elif not filled:
                print(f"    ⚠️  {expr:55} {len(vals)} rows, ALL EMPTY")
            else:
                pct = 100 * len(filled) / len(vals)
                sample = ', '.join(f"{i}={v}" for i, v in list(zip(items, vals))[:3] if v)
                print(f"    ✅ {expr:55} {len(filled)}/{len(vals)} filled ({pct:.0f}%)")
                print(f"       e.g. {sample[:110]}")
                if 'hsn' not in winners:
                    winners['hsn'] = f"(stock item master) {expr}"
                break  # Found a working expression, no need to test more

        if 'hsn' in winners and '(stock item master)' in winners['hsn']:
            print("\n    HSN found on Stock Item masters — tally_sync.py fetches it from")
            print("    get_stock_items_xml() and injects into invoice items via lookup.")

    return winners


def probe_bulk_explode(requests, url, company, days=90, raw_dump=False, debtors=None):
    import time
    from collections import Counter
    debtors = debtors or set()
    hr("7. BULK EXPLODE PROBE (one pass for ALL parties — scalability)")
    print("Confirms the scalable engine: ONE windowed EXPLODE over every voucher,")
    print("bucketed by party in Python — vs 971 per-party scans that hung earlier.")

    try:
        to_date = datetime.now()
        from_date = to_date - timedelta(days=days)
    except Exception:
        print("  datetime unavailable; skipping.")
        return
    frm, to = from_date.strftime('%Y%m%d'), to_date.strftime('%Y%m%d')
    print(f"  Window: {frm}–{to} ({days} days), no party filter.\n")

    t0 = time.time()
    led_raw = tally_request(requests, url, _bulk_ledgers_xml(company, frm, to))
    t_led = time.time() - t0
    led = _parse_bulk_ledgers(led_raw) if led_raw else []

    t0 = time.time()
    inv_raw = tally_request(requests, url, _bulk_inventory_xml(company, frm, to))
    t_inv = time.time() - t0
    inv = _parse_bulk_inventory(inv_raw) if inv_raw else []

    if raw_dump:
        print(f"  [bulk ledger head]    {(led_raw or '')[:700]!r}\n")
        print(f"  [bulk inventory head] {(inv_raw or '')[:700]!r}\n")

    # Join inventory → party via MasterId. A sales voucher's customer is the
    # ledger entry that is a KNOWN debtor (Sundry Debtor); we prefer that over a
    # bare "first Dr" (which can wrongly pick the sales ledger on returns etc.).
    # This mirrors exactly how the real sync will attribute each invoice.
    mid_debtor, mid_firstdr = {}, {}
    for r in led:
        if r['type'] == 'Dr' and r['mid']:
            if r['ledger'] in debtors and r['mid'] not in mid_debtor:
                mid_debtor[r['mid']] = r['ledger']
            if r['mid'] not in mid_firstdr:
                mid_firstdr[r['mid']] = r['ledger']
    for r in inv:
        if not r['party']:
            r['party'] = mid_debtor.get(r['mid']) or mid_firstdr.get(r['mid'], '')

    led_parties = len({r['ledger'] for r in led})
    inv_parties = len({r['party'] for r in inv if r['party']})
    joined = sum(1 for r in inv if r['party'])
    qty_ok = any(r['qty'] > 0 or r['rate'] > 0 for r in inv)

    print(f"  Ledger   explode: {len(led):>6} lines · {len({r['mid'] for r in led})} vouchers · "
          f"{led_parties} distinct ledgers · {t_led:5.1f}s")
    print(f"  Inventory explode:{len(inv):>6} lines · {len({r['mid'] for r in inv})} vouchers · "
          f"{inv_parties} parties (via MasterId join) · {t_inv:5.1f}s")
    print(f"  Inventory qty/rate present: {'YES' if qty_ok else 'NO'} · "
          f"party resolved on {joined}/{len(inv)} inv lines")

    if not led and not inv:
        print("  ❌ Bulk explode returned nothing — re-run with --raw and send the heads.")
        return

    # Prove the bucketing works: reconstruct one invoice for a real party.
    if inv:
        cnt = Counter(r['party'] for r in inv if r['party'])
        if cnt:
            party = cnt.most_common(1)[0][0]
            pv = [r for r in inv if r['party'] == party]
            mid = pv[0]['mid']
            items = [r for r in pv if r['mid'] == mid]
            print(f"\n  Bucketed sample — party '{party}', invoice #{items[0]['vno']}:")
            for it in items[:6]:
                print(f"    {it['item'][:30]:30s} {it['qty']:>8,.2f} {it['unit'][:4]:4s} "
                      f"@ {it['rate']:>10,.2f} = Rs {it['amount']:>12,.2f}")
        else:
            print("\n  ⚠️  Could not resolve any party via the join — re-run with --raw so I")
            print("     can check the CMID/BMID (MasterId) tags in the heads.")

    print(f"\n  → BOTH passes covered ALL parties in ~{t_led + t_inv:.0f}s for this {days}-day window.")
    print("    That is the whole-company engine for statements + invoices in 2 requests,")
    print("    versus ~971 per-party scans. If the counts look complete, bulk is the way.")


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
    parser.add_argument("--ledger", default="",
                        help="Exact ledger name to test in the Ledger Statement "
                             "probe (default: auto-pick an active debtor)")
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
        debtor_names, ledger_candidates = explore_ledgers(
            requests, args.tally_url, effective_company, groups)
        explore_stock(requests, args.tally_url, effective_company, raw_dump=args.raw)
        explore_vouchers(requests, args.tally_url, effective_company, args.days,
                         raw_dump=args.raw, debtor_names=debtor_names)
        probe_vouchers(requests, args.tally_url, effective_company)
        probe_ledger_statement(requests, args.tally_url, effective_company,
                               ledger_candidates, chosen=args.ledger, raw_dump=args.raw)
        probe_invoice(requests, args.tally_url, effective_company,
                      ledger_candidates, chosen=args.ledger, raw_dump=args.raw)
        probe_bulk_explode(requests, args.tally_url, effective_company,
                           days=args.days, raw_dump=args.raw, debtors=debtor_names)
        probe_hsn_batch(requests, args.tally_url, effective_company,
                        days=args.days, raw_dump=args.raw)

    hr("DIAGNOSTIC COMPLETE")
    print("Review the sections above. Anything marked ⚠️ or ❌ is worth fixing")
    print("before relying on that feature. Share this output with your developer")
    print("to tune parsers for your exact Tally setup.")


if __name__ == '__main__':
    main()
