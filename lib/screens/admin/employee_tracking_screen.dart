import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shantinath_agro/models/activity_log.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';

class EmployeeTrackingScreen extends StatefulWidget {
  const EmployeeTrackingScreen({super.key});

  @override
  State<EmployeeTrackingScreen> createState() => _EmployeeTrackingScreenState();
}

class _EmployeeTrackingScreenState extends State<EmployeeTrackingScreen> {
  String _searchQuery = '';
  String _selectedActionFilter = 'All';
  DateTime? _selectedDateFilter;
  final TextEditingController _searchController = TextEditingController();

  final List<String> _actionsList = [
    'All',
    'login',
    'logout',
    'order_placed',
    'order_modified',
    'permissions_changed',
    'employee_added',
    'employee_removed'
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'login':
        return Icons.login_rounded;
      case 'logout':
        return Icons.logout_rounded;
      case 'order_placed':
        return Icons.shopping_cart_rounded;
      case 'order_modified':
        return Icons.edit_note_rounded;
      case 'permissions_changed':
        return Icons.security_rounded;
      case 'employee_added':
        return Icons.person_add_rounded;
      case 'employee_removed':
        return Icons.person_remove_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Color _getActionColor(String action) {
    switch (action) {
      case 'login':
        return Colors.green;
      case 'logout':
        return Colors.blueGrey;
      case 'order_placed':
        return const Color(0xFF2E7D32);
      case 'order_modified':
        return Colors.orange;
      case 'permissions_changed':
        return Colors.purple;
      case 'employee_added':
        return Colors.teal;
      case 'employee_removed':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  String _translateAction(String action, bool isMarathi) {
    if (isMarathi) {
      switch (action) {
        case 'All': return 'सर्व हालचाली';
        case 'login': return 'लॉगिन';
        case 'logout': return 'लॉगआउट';
        case 'order_placed': return 'ऑर्डर नोंदवली';
        case 'order_modified': return 'ऑर्डर सुधारली';
        case 'permissions_changed': return 'परवानग्या बदलल्या';
        case 'employee_added': return 'कर्मचारी जोडला';
        case 'employee_removed': return 'कर्मचारी काढला';
        default: return action;
      }
    } else {
      switch (action) {
        case 'All': return 'All Actions';
        case 'login': return 'Login';
        case 'logout': return 'Logout';
        case 'order_placed': return 'Order Placed';
        case 'order_modified': return 'Order Modified';
        case 'permissions_changed': return 'Permissions Changed';
        case 'employee_added': return 'Employee Added';
        case 'employee_removed': return 'Employee Removed';
        default: return action[0].toUpperCase() + action.substring(1);
      }
    }
  }

  List<ActivityLog> _filterLogs(List<ActivityLog> logs) {
    return logs.where((log) {
      final matchesSearch = log.actorName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          log.actorId.contains(_searchQuery) ||
          log.summary.toLowerCase().contains(_searchQuery.toLowerCase());
      
      final matchesAction = _selectedActionFilter == 'All' || log.action == _selectedActionFilter;

      bool matchesDate = true;
      if (_selectedDateFilter != null) {
        matchesDate = log.createdAt.year == _selectedDateFilter!.year &&
            log.createdAt.month == _selectedDateFilter!.month &&
            log.createdAt.day == _selectedDateFilter!.day;
      }

      return matchesSearch && matchesAction && matchesDate;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isMarathi = Provider.of<LocaleProvider>(context).isMarathi;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text(
          isMarathi ? 'कर्मचारी ट्रॅकिंग' : 'Employee Tracking',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('activity_logs')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                isMarathi ? 'डेटा लोड करताना त्रुटी आली' : 'Error loading audit logs',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final allLogs = docs
              .map((d) => ActivityLog.fromJson(d.data() as Map<String, dynamic>))
              .toList();

          final filteredLogs = _filterLogs(allLogs);

          // Compute quick stats
          final loginCount = allLogs.where((l) => l.action == 'login').length;
          final orderCount = allLogs.where((l) => l.action == 'order_placed').length;

          return Column(
            children: [
              // Stats Block
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFF2E7D32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(Icons.history, '${allLogs.length}', isMarathi ? 'एकूण नोंदी' : 'Total Logs'),
                    _buildStatItem(Icons.login, '$loginCount', isMarathi ? 'लॉगिन सत्र' : 'Logins'),
                    _buildStatItem(Icons.shopping_cart, '$orderCount', isMarathi ? 'नोंदवल्या ऑर्डर' : 'Orders Placed'),
                  ],
                ),
              ),

              // Search & Filters panel
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: isMarathi ? 'कर्मचारी किंवा तपशील शोधा...' : 'Search employee or action details...',
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
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isMarathi ? 'कृतीनुसार फिल्टर:' : 'Filter by action:',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedActionFilter,
                                  style: GoogleFonts.outfit(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w500),
                                  items: _actionsList.map((String action) {
                                    return DropdownMenuItem<String>(
                                      value: action,
                                      child: Text(_translateAction(action, isMarathi)),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedActionFilter = val;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isMarathi ? 'दिनांकानुसार फिल्टर:' : 'Filter by date:',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _selectedDateFilter ?? DateTime.now(),
                                      firstDate: DateTime(2025),
                                      lastDate: DateTime.now().add(const Duration(days: 1)),
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        _selectedDateFilter = picked;
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.calendar_today_rounded, size: 14),
                                  label: Text(
                                    _selectedDateFilter == null
                                        ? (isMarathi ? 'तारीख निवडा' : 'Select Date')
                                        : DateFormat('dd/MM/yyyy').format(_selectedDateFilter!),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    side: BorderSide(color: Colors.grey.shade300),
                                  ),
                                ),
                                if (_selectedDateFilter != null) ...[
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        _selectedDateFilter = null;
                                      });
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Activity logs list
              Expanded(
                child: filteredLogs.isEmpty
                    ? Center(
                        child: Text(
                          isMarathi ? 'कोणत्याही हालचाली आढळल्या नाहीत' : 'No activity logs found',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredLogs.length,
                        itemBuilder: (context, index) {
                          final log = filteredLogs[index];
                          final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(log.createdAt);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: _getActionColor(log.action).withValues(alpha: 0.1),
                                    foregroundColor: _getActionColor(log.action),
                                    child: Icon(_getActionIcon(log.action), size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                log.actorName,
                                                style: GoogleFonts.outfit(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _getActionColor(log.action).withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                _translateAction(log.action, isMarathi).toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold,
                                                  color: _getActionColor(log.action),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                log.actorRole.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          log.actorId,
                                          style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          log.summary,
                                          style: GoogleFonts.outfit(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w400,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              formattedDate,
                                              style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                            ),
                                            if (log.targetId != null)
                                              Text(
                                                'ID: ${log.targetId}',
                                                style: TextStyle(
                                                  color: const Color(0xFF2E7D32),
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
