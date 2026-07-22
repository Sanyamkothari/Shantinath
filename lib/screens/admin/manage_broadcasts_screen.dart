import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:shantinath_agro/models/broadcast_message.dart';
import 'package:shantinath_agro/providers/broadcast_provider.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';

class ManageBroadcastsScreen extends StatefulWidget {
  const ManageBroadcastsScreen({super.key});

  @override
  State<ManageBroadcastsScreen> createState() => _ManageBroadcastsScreenState();
}

class _ManageBroadcastsScreenState extends State<ManageBroadcastsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _titleMrController = TextEditingController();
  final _bodyController = TextEditingController();
  final _bodyMrController = TextEditingController();
  final _imageUrlController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _titleMrController.dispose();
    _bodyController.dispose();
    _bodyMrController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  void _clearForm() {
    _titleController.clear();
    _titleMrController.clear();
    _bodyController.clear();
    _bodyMrController.clear();
    _imageUrlController.clear();
  }

  void _showAddBroadcastDialog(BuildContext context) {
    _clearForm();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Compose Broadcast',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF1B5E20)),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'English Details',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleController,
                      decoration: _inputDecoration('Title (English)'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bodyController,
                      decoration: _inputDecoration('Message (English)'),
                      maxLines: 3,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Marathi Details (मराठी तपशील)',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleMrController,
                      decoration: _inputDecoration('शीर्षक (मराठी) / Title (Marathi)'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bodyMrController,
                      decoration: _inputDecoration('संदेश (मराठी) / Message (Marathi)'),
                      maxLines: 3,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _imageUrlController,
                      decoration: _inputDecoration('Optional Image URL'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
            ),
            FilledButton(
              onPressed: () => _submitBroadcast(ctx),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              child: const Text('Publish'),
            ),
          ],
        );
      },
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade600),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Future<void> _submitBroadcast(BuildContext dialogContext) async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<BroadcastProvider>();
    final adminPhone = context.read<AuthProvider>().currentUser?.phone ?? '';

    final newMessage = BroadcastMessage(
      id: '',
      title: _titleController.text.trim(),
      titleMr: _titleMrController.text.trim(),
      body: _bodyController.text.trim(),
      bodyMr: _bodyMrController.text.trim(),
      imageUrl: _imageUrlController.text.trim(),
      createdAt: DateTime.now(),
      senderId: adminPhone,
    );

    Navigator.pop(dialogContext); // Close dialog

    // Show loading snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 16),
            Text('Publishing announcement...'),
          ],
        ),
        duration: Duration(days: 1), // persists until dismissed
      ),
    );

    await provider.addBroadcast(newMessage);
    
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      if (provider.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish: ${provider.errorMessage}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Announcement published successfully!'),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, BroadcastMessage msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Announcement?'),
        content: Text('Are you sure you want to delete "${msg.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final provider = context.read<BroadcastProvider>();
              await provider.deleteBroadcast(msg.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Announcement deleted'),
                    backgroundColor: Colors.red.shade700,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BroadcastProvider>();
    final broadcasts = provider.broadcasts;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text(
          'Manage Broadcasts',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddBroadcastDialog(context),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.campaign_rounded),
        label: Text(
          'Broadcast',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
      ),
      body: provider.isLoading && broadcasts.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : broadcasts.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: const Color(0xFF2E7D32),
                  onRefresh: provider.loadBroadcasts,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    itemCount: broadcasts.length,
                    itemBuilder: (context, index) {
                      final msg = broadcasts[index];
                      return _buildBroadcastCard(context, msg);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.campaign_outlined, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No broadcasts published',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Announce stock arrivals or price drops here.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildBroadcastCard(BuildContext context, BroadcastMessage msg) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      shadowColor: Colors.black12,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (msg.imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: CachedNetworkImage(
                imageUrl: msg.imageUrl,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: Colors.grey.shade100, child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D32)))),
                errorWidget: (context, url, error) => Container(color: Colors.grey.shade100, child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.grey))),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('dd MMM yyyy, hh:mm a').format(msg.createdAt),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _confirmDelete(context, msg),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  msg.title,
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF263238)),
                ),
                const SizedBox(height: 4),
                Text(
                  msg.body,
                  style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'मराठी (Marathi Version):',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11, color: const Color(0xFF2E7D32)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        msg.titleMr,
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF263238)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        msg.bodyMr,
                        style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
