import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:shantinath_agro/models/broadcast_message.dart';
import 'package:shantinath_agro/providers/broadcast_provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Mark all notifications as read upon opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BroadcastProvider>().markAllAsRead();
    });
  }

  String _formatRelativeTime(DateTime dateTime, bool isMarathi) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return isMarathi ? 'आत्ताच' : 'Just now';
    } else if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return isMarathi ? '$mins मिनिटांपूर्वी' : '$mins mins ago';
    } else if (difference.inHours < 24) {
      final hrs = difference.inHours;
      return isMarathi ? '$hrs तासांपूर्वी' : '$hrs hrs ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      if (days == 1) {
        return isMarathi ? 'काल' : 'Yesterday';
      }
      return isMarathi ? '$days दिवसांपूर्वी' : '$days days ago';
    } else {
      return DateFormat('dd MMM yyyy').format(dateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BroadcastProvider>();
    final isMarathi = context.watch<LocaleProvider>().isMarathi;
    final broadcasts = provider.broadcasts;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          isMarathi ? 'घोषणा आणि सूचना' : 'Announcements & Alerts',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: provider.isLoading && broadcasts.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : broadcasts.isEmpty
              ? _buildEmptyState(isMarathi)
              : RefreshIndicator(
                  color: const Color(0xFF2E7D32),
                  onRefresh: provider.loadBroadcasts,
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: broadcasts.length,
                    itemBuilder: (context, index) {
                      final msg = broadcasts[index];
                      return _buildNotificationCard(context, msg, isMarathi);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState(bool isMarathi) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none_rounded, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            isMarathi ? 'कोणतीही सूचना नाही' : 'No announcements yet',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isMarathi 
                ? 'नवीन ऑफर्स आणि अपडेट्स येथे दिसतील.' 
                : 'Seasonal updates & arrivals will appear here.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(BuildContext context, BroadcastMessage msg, bool isMarathi) {
    final title = isMarathi ? msg.titleMr : msg.title;
    final body = isMarathi ? msg.bodyMr : msg.body;
    final timeStr = _formatRelativeTime(msg.createdAt, isMarathi);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 0.8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: msg.imageUrl,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 160,
                  color: Colors.grey.shade50,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D32)),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 160,
                  color: Colors.grey.shade100,
                  child: const Center(
                    child: Icon(Icons.broken_image_rounded, color: Colors.grey),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.campaign_rounded, size: 14, color: Color(0xFF2E7D32)),
                            const SizedBox(width: 4),
                            Text(
                              isMarathi ? 'अपडेट' : 'Update',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2E7D32),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF263238),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
