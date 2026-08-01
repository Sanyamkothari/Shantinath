import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';

/// Reusable banner header showing when Tally data was last synced to Firestore.
/// Displayed at the top of Stock Status, Ledger Book, and Ledger Report screens.
///
/// Multi-tiered fallback mechanism:
/// 1. Reads `app_metadata/tally_sync` (global sync timestamp)
/// 2. Reads newest `updatedAt` from `tally_ledgers` or `tally_stock` collection
/// 3. Reads optional `fallbackTimestamp` passed from parent screen
class TallyLastUpdatedHeader extends StatelessWidget {
  final DateTime? fallbackTimestamp;
  final String? customLabel;

  const TallyLastUpdatedHeader({
    super.key,
    this.fallbackTimestamp,
    this.customLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isMarathi = context.watch<LocaleProvider>().isMarathi;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('app_metadata')
          .doc('tally_sync')
          .snapshots(),
      builder: (context, snapshot) {
        DateTime? syncTime = fallbackTimestamp;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null && data['lastSyncedAt'] != null) {
            final ts = data['lastSyncedAt'] as Timestamp?;
            if (ts != null) {
              syncTime = ts.toDate();
            }
          }
        }

        if (syncTime != null) {
          return _buildBanner(context, syncTime, isMarathi);
        }

        // Secondary fallback: query the most recently updated document in tally_ledgers
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('tally_ledgers')
              .orderBy('updatedAt', descending: true)
              .limit(1)
              .snapshots(),
          builder: (context, ledgerSnap) {
            DateTime? ledgerSyncTime = fallbackTimestamp;

            if (ledgerSnap.hasData && ledgerSnap.data!.docs.isNotEmpty) {
              final data = ledgerSnap.data!.docs.first.data() as Map<String, dynamic>?;
              if (data != null && data['updatedAt'] != null) {
                final ts = data['updatedAt'] as Timestamp?;
                if (ts != null) {
                  ledgerSyncTime = ts.toDate();
                }
              }
            }

            return _buildBanner(context, ledgerSyncTime, isMarathi);
          },
        );
      },
    );
  }

  Widget _buildBanner(BuildContext context, DateTime? syncTime, bool isMarathi) {
    final timeStr = syncTime != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(syncTime)
        : (isMarathi ? 'माहिती उपलब्ध नाही' : 'Sync timestamp unavailable');

    final defaultLabel = isMarathi ? 'शेवटचे अपडेट :' : 'Last updated :';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '🔄 ',
            style: TextStyle(fontSize: 13),
          ),
          Flexible(
            child: Text(
              '${customLabel ?? defaultLabel} $timeStr',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1B5E20),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
