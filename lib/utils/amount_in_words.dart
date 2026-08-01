/// Converts a rupee amount into the words printed on a tax invoice, using the
/// Indian numbering system (crore / lakh / thousand), e.g.
///   19800     -> "INR Nineteen Thousand Eight Hundred Only"
///   19800.50  -> "INR Nineteen Thousand Eight Hundred and Fifty Paise Only"
///
/// Matches the wording Tally prints in the "Amount Chargeable (in words)" box:
/// title case, no "and" between the hundreds and the remainder.
library;

const List<String> _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
  'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
  'Seventeen', 'Eighteen', 'Nineteen',
];

const List<String> _tens = [
  '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty',
  'Ninety',
];

/// Words for 0..99. Returns '' for 0 so callers can skip empty groups.
String _twoDigits(int n) {
  if (n < 20) return _ones[n];
  final t = _tens[n ~/ 10];
  final o = _ones[n % 10];
  return o.isEmpty ? t : '$t $o';
}

/// Words for 0..999 (used for the hundreds group and, recursively, for crores
/// beyond 99 so very large amounts still read correctly).
String _threeDigits(int n) {
  final parts = <String>[];
  if (n >= 100) parts.add('${_ones[n ~/ 100]} Hundred');
  final rest = _twoDigits(n % 100);
  if (rest.isNotEmpty) parts.add(rest);
  return parts.join(' ');
}

/// Words for a whole number of rupees, without the "INR"/"Only" wrapper.
/// Returns 'Zero' for 0.
String rupeesToWords(int amount) {
  if (amount == 0) return 'Zero';
  if (amount < 0) return 'Minus ${rupeesToWords(-amount)}';

  var n = amount;
  final parts = <String>[];

  final crore = n ~/ 10000000;
  n %= 10000000;
  if (crore > 0) {
    // Crores can exceed 99 (>= 100 crore), so recurse rather than truncate.
    parts.add('${crore > 99 ? rupeesToWords(crore) : _twoDigits(crore)} Crore');
  }

  final lakh = n ~/ 100000;
  n %= 100000;
  if (lakh > 0) parts.add('${_twoDigits(lakh)} Lakh');

  final thousand = n ~/ 1000;
  n %= 1000;
  if (thousand > 0) parts.add('${_twoDigits(thousand)} Thousand');

  final rest = _threeDigits(n);
  if (rest.isNotEmpty) parts.add(rest);

  return parts.join(' ');
}

/// Full invoice line: `INR <words> Only`, with paise appended when present.
/// [currency] lets a caller override the "INR" prefix; pass '' to omit it.
String amountInWords(double amount, {String currency = 'INR'}) {
  // Round to paise first so 19799.999 doesn't read as "Nineteen Thousand Seven
  // Hundred Ninety Nine and Ninety Nine Paise" when it is really 19,800.
  final totalPaise = (amount.abs() * 100).round();
  final rupees = totalPaise ~/ 100;
  final paise = totalPaise % 100;

  final buffer = StringBuffer();
  if (currency.isNotEmpty) buffer.write('$currency ');
  if (amount < 0) buffer.write('Minus ');
  buffer.write(rupeesToWords(rupees));
  if (paise > 0) buffer.write(' and ${_twoDigits(paise)} Paise');
  buffer.write(' Only');
  return buffer.toString();
}
