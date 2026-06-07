import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/models/order.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for sharing order details via WhatsApp using url_launcher.
class WhatsAppService {
  WhatsAppService._();

  /// Formats the order as a human-readable text message and opens WhatsApp
  /// via the wa.me deep link. Sends to the admin WhatsApp number.
  ///
  /// Throws [Exception] if WhatsApp cannot be launched.
  static Future<void> shareOrderViaWhatsApp(Order order) async {
    final message = _formatOrderMessage(order);
    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUrl =
        'https://wa.me/${AppConstants.adminPhone}?text=$encodedMessage';

    final uri = Uri.parse(whatsappUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw Exception(
        'Could not open WhatsApp. Please ensure WhatsApp is installed.',
      );
    }
  }

  /// Shares an order message to a specific phone number.
  static Future<void> shareOrderToNumber(Order order, String phoneNumber) async {
    final message = _formatOrderMessage(order);
    final encodedMessage = Uri.encodeComponent(message);

    // Ensure phone number has country code
    final formattedPhone = phoneNumber.startsWith('91')
        ? phoneNumber
        : '91$phoneNumber';

    final whatsappUrl =
        'https://wa.me/$formattedPhone?text=$encodedMessage';

    final uri = Uri.parse(whatsappUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw Exception(
        'Could not open WhatsApp. Please ensure WhatsApp is installed.',
      );
    }
  }

  /// Formats an [Order] into a readable text message for WhatsApp sharing.
  static String _formatOrderMessage(Order order) {
    final buffer = StringBuffer();

    buffer.writeln('🌾 *Order from Shantinath Agro Agency*');
    buffer.writeln('---');
    buffer.writeln('📋 Order ID: ${order.id}');
    buffer.writeln('👤 Customer: ${order.customerName}');
    buffer.writeln('📞 Phone: ${order.customerPhone}');
    buffer.writeln('🏘️ Village: ${order.customerVillage}');
    buffer.writeln('');
    buffer.writeln('📦 *Items:*');

    for (var i = 0; i < order.items.length; i++) {
      final item = order.items[i];
      final itemTotal = item.totalPrice.toStringAsFixed(2);
      buffer.writeln(
        '${i + 1}. ${item.product.name} (${item.product.packSize}) '
        'x${item.quantity} - ₹$itemTotal',
      );
    }

    buffer.writeln('');
    buffer.writeln('💰 *Total: ₹${order.totalAmount.toStringAsFixed(2)}*');

    if (order.notes.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('📝 Notes: ${order.notes}');
    }

    buffer.writeln('');
    buffer.writeln('Status: ${order.status.name.toUpperCase()}');
    buffer.writeln('---');
    buffer.writeln('शांतिनाथ एग्रो एजेंसी');

    return buffer.toString();
  }

  /// Get a formatted text representation of the order (without sending).
  /// Useful for copying to clipboard.
  static String getOrderText(Order order) {
    return _formatOrderMessage(order);
  }
}
