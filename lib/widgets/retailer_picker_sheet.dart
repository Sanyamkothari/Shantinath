import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shantinath_agro/models/user_model.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';

class RetailerPickerSheet extends StatefulWidget {
  const RetailerPickerSheet({super.key});

  @override
  State<RetailerPickerSheet> createState() => _RetailerPickerSheetState();
}

class _RetailerPickerSheetState extends State<RetailerPickerSheet> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<UserModel> _filterCustomers(List<UserModel> customers) {
    if (_searchQuery.isEmpty) return customers;
    final query = _searchQuery.toLowerCase();
    return customers.where((c) {
      return c.name.toLowerCase().contains(query) ||
          c.firmName.toLowerCase().contains(query) ||
          c.phone.contains(query) ||
          c.village.toLowerCase().contains(query) ||
          c.taluka.toLowerCase().contains(query) ||
          c.district.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMarathi = Provider.of<LocaleProvider>(context).isMarathi;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            height: 4,
            width: 40,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.people_alt_rounded, color: Color(0xFF2E7D32)),
                const SizedBox(width: 10),
                Text(
                  isMarathi ? 'किरकोळ विक्रेता निवडा' : 'Select Retailer',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1B5E20),
                  ),
                ),
              ],
            ),
          ),
          // Search box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: isMarathi ? 'नाव, फर्म, गाव किंवा नंबर शोधा...' : 'Search by name, firm, village, phone...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          // Retailers List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'customer')
                  .where('isApproved', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      isMarathi ? 'डेटा लोड करताना त्रुटी आली' : 'Error loading retailers',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      isMarathi ? 'कोणतेही किरकोळ विक्रेते आढळले नाहीत' : 'No retailers registered yet',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  );
                }

                final allCustomers = docs
                    .map((d) => UserModel.fromJson(d.data() as Map<String, dynamic>))
                    .toList();

                final filteredCustomers = _filterCustomers(allCustomers);

                if (filteredCustomers.isEmpty) {
                  return Center(
                    child: Text(
                      isMarathi ? 'शोध जुळला नाही' : 'No matching retailers found',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  );
                }

                return ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: filteredCustomers.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 70),
                  itemBuilder: (context, index) {
                    final customer = filteredCustomers[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                        foregroundColor: const Color(0xFF2E7D32),
                        child: Text(
                          customer.firmName.isNotEmpty
                              ? customer.firmName[0].toUpperCase()
                              : (customer.name.isNotEmpty
                                  ? customer.name[0].toUpperCase()
                                  : '?'),
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        customer.firmName.isNotEmpty ? customer.firmName : customer.name,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (customer.firmName.isNotEmpty)
                            Text(
                              customer.name,
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 14, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Text(
                                '${customer.village}, ${customer.taluka}',
                                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                              ),
                              const SizedBox(width: 10),
                              Icon(Icons.phone_outlined, size: 14, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Text(
                                customer.phone,
                                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(context, customer);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
