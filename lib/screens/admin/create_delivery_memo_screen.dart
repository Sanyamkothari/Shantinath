import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import 'package:shantinath_agro/models/cart_item.dart';
import 'package:shantinath_agro/models/delivery_memo.dart';
import 'package:shantinath_agro/models/order.dart';
import 'package:shantinath_agro/models/user_model.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/services/auth_service.dart';
import 'package:shantinath_agro/services/delivery_memo_pdf_service.dart';
import 'package:shantinath_agro/services/delivery_memo_service.dart';

class CreateDeliveryMemoScreen extends StatefulWidget {
  final Order order;
  const CreateDeliveryMemoScreen({super.key, required this.order});

  @override
  State<CreateDeliveryMemoScreen> createState() =>
      _CreateDeliveryMemoScreenState();
}

class _CreateDeliveryMemoScreenState extends State<CreateDeliveryMemoScreen> {
  static const Color _green = Color(0xFF2E7D32);

  final _service = DeliveryMemoService();
  final _pdfService = DeliveryMemoPdfService();

  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _batchControllers = {};
  final _vehicleController = TextEditingController();
  final _transporterController = TextEditingController();
  final _driverController = TextEditingController();
  final _notesController = TextEditingController();

  bool _showPrices = false;
  bool _submitting = false;
  UserModel? _party;

  /// Order items that still have quantity left to deliver.
  late final List<CartItem> _deliverable = widget.order.items
      .where((i) => i.pendingQuantity > 0)
      .toList();

  @override
  void initState() {
    super.initState();
    for (final item in _deliverable) {
      _qtyControllers[item.product.id] =
          TextEditingController(text: '${item.pendingQuantity}');
      _batchControllers[item.product.id] = TextEditingController();
    }
    _loadParty();
  }

  Future<void> _loadParty() async {
    final party = await AuthService().getUserByPhone(widget.order.customerId);
    if (mounted) setState(() => _party = party);
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    for (final c in _batchControllers.values) {
      c.dispose();
    }
    _vehicleController.dispose();
    _transporterController.dispose();
    _driverController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final isMarathi = context.read<LocaleProvider>().isMarathi;
    final currentUser = context.read<AuthProvider>().currentUser;
    if (currentUser == null) return;

    // Build the memo lines from the edited quantities.
    final lines = <DeliveryMemoLine>[];
    for (final item in _deliverable) {
      final qty = int.tryParse(_qtyControllers[item.product.id]!.text) ?? 0;
      if (qty <= 0) continue;
      if (qty > item.pendingQuantity) {
        _snack(
          'Cannot deliver $qty of "${item.product.name}" — only ${item.pendingQuantity} pending.',
          isError: true,
        );
        return;
      }
      lines.add(DeliveryMemoLine(
        productId: item.product.id,
        productName:
            isMarathi && item.product.nameMr.isNotEmpty
                ? item.product.nameMr
                : item.product.name,
        packSize: item.product.packSize,
        batchLot: _batchControllers[item.product.id]!.text.trim(),
        quantity: qty,
        rate: item.product.price,
      ));
    }

    if (lines.isEmpty) {
      _snack('Enter a delivery quantity for at least one item.',
          isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final memo = await _service.createFromOrder(
        order: widget.order,
        party: _party,
        lines: lines,
        showPrices: _showPrices,
        vehicleNo: _vehicleController.text,
        transporter: _transporterController.text,
        driverName: _driverController.text,
        notes: _notesController.text,
        createdBy: currentUser,
      );

      final bytes = await _pdfService.buildPdf(memo);
      if (!mounted) return;

      // Opens the system print/share sheet (print, save PDF, or share to WhatsApp).
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: memo.memoNumber.replaceAll('/', '-'),
      );

      if (!mounted) return;
      _snack('Delivery memo ${memo.memoNumber} created.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text('Delivery Memo',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: _deliverable.isEmpty
          ? _emptyState()
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _partyCard(order),
                  const SizedBox(height: 16),
                  Text('Items to deliver',
                      style: GoogleFonts.outfit(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ..._deliverable.map(_itemCard),
                  const SizedBox(height: 8),
                  _pricesToggle(),
                  const SizedBox(height: 16),
                  Text('Transport & notes (optional)',
                      style: GoogleFonts.outfit(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _textField(_vehicleController, 'Vehicle No.',
                      Icons.local_shipping_outlined),
                  const SizedBox(height: 10),
                  _textField(_transporterController, 'Transporter',
                      Icons.business_outlined),
                  const SizedBox(height: 10),
                  _textField(
                      _driverController, 'Driver name', Icons.person_outline),
                  const SizedBox(height: 10),
                  _textField(_notesController, 'Notes', Icons.note_outlined,
                      maxLines: 2),
                ],
              ),
            ),
      bottomNavigationBar: _deliverable.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _generate,
                    icon: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white),
                          )
                        : const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(
                      _submitting ? 'Generating…' : 'Generate & Print Memo',
                      style: GoogleFonts.outfit(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('Nothing left to deliver',
                style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text('All items in this order have already been delivered.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _partyCard(Order order) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('To',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 2),
          Text(
            _party?.firmName.isNotEmpty == true
                ? _party!.firmName
                : order.customerName,
            style: GoogleFonts.outfit(
                fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Text(
            [
              if (order.customerVillage.isNotEmpty) order.customerVillage,
              if (order.customerPhone.isNotEmpty) order.customerPhone,
            ].join('  •  '),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(CartItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.product.name,
              style: GoogleFonts.outfit(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            'Ordered ${item.quantity}  •  Pending ${item.pendingQuantity}'
            '${item.product.packSize.isNotEmpty ? '  •  ${item.product.packSize}' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _qtyControllers[item.product.id],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _fieldDecoration('Deliver now'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _batchControllers[item.product.id],
                  decoration: _fieldDecoration('Batch / Lot no.'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pricesToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: _green,
        title: Text('Show prices on memo',
            style: GoogleFonts.outfit(
                fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: const Text('Off = pure delivery challan (quantities only)',
            style: TextStyle(fontSize: 12)),
        value: _showPrices,
        onChanged: (v) => setState(() => _showPrices = v),
      ),
    );
  }

  Widget _textField(TextEditingController c, String label, IconData icon,
      {int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      decoration: _fieldDecoration(label).copyWith(
        prefixIcon: Icon(icon, color: _green, size: 20),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF7F7F2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _green, width: 1.5),
      ),
    );
  }
}
