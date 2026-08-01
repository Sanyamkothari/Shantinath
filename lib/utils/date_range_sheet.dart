import 'package:flutter/material.dart';

/// Result of the ledger date-range sheet.
/// - null              → user cancelled (no change)
/// - cleared == true   → user chose "All time" (clear the range)
/// - range != null     → a specific range was chosen
class DateRangeResult {
  final bool cleared;
  final DateTimeRange? range;
  const DateRangeResult({this.cleared = false, this.range});
}

/// Shows a bottom sheet of quick date-range presets plus a custom picker.
/// Returns a [DateRangeResult], or null if dismissed without a choice.
Future<DateRangeResult?> showLedgerDateRangeSheet(
  BuildContext context, {
  DateTimeRange? current,
  bool isMarathi = false,
}) async {
  const green = Color(0xFF2E7D32);
  final now = DateTime.now();

  DateTimeRange thisMonth() =>
      DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);

  DateTimeRange last30() =>
      DateTimeRange(start: now.subtract(const Duration(days: 29)), end: now);

  DateTimeRange thisFy() {
    final startYear = now.month >= 4 ? now.year : now.year - 1;
    return DateTimeRange(start: DateTime(startYear, 4, 1), end: now);
  }

  return showModalBottomSheet<DateRangeResult>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      Widget tile(IconData icon, String label, VoidCallback onTap) {
        return ListTile(
          leading: Icon(icon, color: green),
          title: Text(label),
          onTap: onTap,
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            tile(Icons.calendar_view_month_rounded,
                isMarathi ? 'हा महिना' : 'This month', () {
              Navigator.pop(sheetCtx, DateRangeResult(range: thisMonth()));
            }),
            tile(Icons.history_rounded,
                isMarathi ? 'मागील ३० दिवस' : 'Last 30 days', () {
              Navigator.pop(sheetCtx, DateRangeResult(range: last30()));
            }),
            tile(Icons.account_balance_wallet_rounded,
                isMarathi ? 'हे आर्थिक वर्ष' : 'This financial year', () {
              Navigator.pop(sheetCtx, DateRangeResult(range: thisFy()));
            }),
            tile(Icons.date_range_rounded,
                isMarathi ? 'सानुकूल श्रेणी…' : 'Custom range…', () async {
              final picked = await showDateRangePicker(
                context: sheetCtx,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 1),
                initialDateRange: current,
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.light(primary: green),
                  ),
                  child: child!,
                ),
              );
              if (sheetCtx.mounted) {
                Navigator.pop(
                  sheetCtx,
                  picked != null ? DateRangeResult(range: picked) : null,
                );
              }
            }),
            if (current != null)
              tile(Icons.clear_rounded, isMarathi ? 'सर्व वेळ' : 'All time', () {
                Navigator.pop(sheetCtx, const DateRangeResult(cleared: true));
              }),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
