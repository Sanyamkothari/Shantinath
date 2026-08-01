import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/models/user_model.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/services/auth_service.dart';
import 'package:shantinath_agro/services/activity_service.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/config/permissions.dart';

class EmployeePermissionsScreen extends StatefulWidget {
  final UserModel employee;

  const EmployeePermissionsScreen({super.key, required this.employee});

  @override
  State<EmployeePermissionsScreen> createState() => _EmployeePermissionsScreenState();
}

class _EmployeePermissionsScreenState extends State<EmployeePermissionsScreen> {
  final AuthService _authService = AuthService();
  late List<String> _selectedPermissions;
  String _currentPreset = 'Custom';

  @override
  void initState() {
    super.initState();
    _selectedPermissions = List<String>.from(widget.employee.permissions);
    _detectPreset();
  }

  void _detectPreset() {
    // Basic set equality helper
    final setSel = _selectedPermissions.toSet();
    final setOrderStaff = AppPermissions.orderStaffPreset.toSet();
    final setSalesRep = AppPermissions.salesRepPreset.toSet();
    final setAll = AppPermissions.allPermissions.toSet();

    if (setSel.length == setOrderStaff.length && setSel.containsAll(setOrderStaff)) {
      _currentPreset = 'Order Staff';
    } else if (setSel.length == setSalesRep.length && setSel.containsAll(setSalesRep)) {
      _currentPreset = 'Sales Rep';
    } else if (setSel.length == setAll.length && setSel.containsAll(setAll)) {
      _currentPreset = 'Full Admin';
    } else if (setSel.length == AppPermissions.customerPreset.length && setSel.containsAll(AppPermissions.customerPreset)) {
      _currentPreset = 'Customer';
    } else {
      _currentPreset = 'Custom';
    }
  }

  void _applyPreset(String preset) {
    setState(() {
      _currentPreset = preset;
      if (preset == 'Order Staff') {
        _selectedPermissions = List<String>.from(AppPermissions.orderStaffPreset);
      } else if (preset == 'Sales Rep') {
        _selectedPermissions = List<String>.from(AppPermissions.salesRepPreset);
      } else if (preset == 'Full Admin') {
        _selectedPermissions = List<String>.from(AppPermissions.allPermissions);
      } else if (preset == 'Customer') {
        _selectedPermissions = List<String>.from(AppPermissions.customerPreset);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMarathi = Provider.of<LocaleProvider>(context).isMarathi;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text(
          isMarathi ? 'परवानग्या व्यवस्थापित करा' : 'Manage Permissions',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: () async {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              final currentUser = authProvider.currentUser;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(isMarathi ? 'परवानग्या जतन केल्या जात आहेत...' : 'Saving permissions...')),
              );

              try {
                await _authService.updatePermissions(
                  widget.employee.phone,
                  _selectedPermissions,
                  role: _currentPreset == 'Customer' ? UserRole.customer : UserRole.employee,
                );

                ActivityService.log(
                  action: 'permissions_changed',
                  targetType: 'user',
                  targetId: widget.employee.phone,
                  summary: 'Admin ${currentUser?.name} updated permissions for employee ${widget.employee.name} (${widget.employee.phone}) to $_currentPreset Preset.',
                  metadata: {
                    'permissions': _selectedPermissions,
                    'preset': _currentPreset,
                  },
                  actor: currentUser,
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isMarathi ? 'परवानग्या यशस्वीरित्या जतन केल्या!' : 'Permissions saved successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${isMarathi ? 'त्रुटी' : 'Error'}: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              isMarathi ? 'बदल जतन करा' : 'Save Changes',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Employee details banner card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
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
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                    foregroundColor: const Color(0xFF2E7D32),
                    child: const Icon(Icons.person_rounded, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.employee.name,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.employee.phone,
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Preset selector card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isMarathi ? 'भूमिका प्रीसेट:' : 'Role Preset:',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                  ),
                  DropdownButton<String>(
                    value: _currentPreset,
                    underline: const SizedBox(),
                    items: ['Order Staff', 'Sales Rep', 'Full Admin', 'Customer', 'Custom'].map((String val) {
                      return DropdownMenuItem<String>(
                        value: val,
                        child: Text(val),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null && val != 'Custom') {
                        _applyPreset(val);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Permissions list title
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                isMarathi ? 'सर्व परवानग्यांची यादी' : 'All Feature Permissions',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1B5E20),
                ),
              ),
            ),

            // Toggle list
            Container(
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
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: AppPermissions.allPermissions.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final permKey = AppPermissions.allPermissions[index];
                  final isSelected = _selectedPermissions.contains(permKey);

                  return SwitchListTile(
                    title: Text(
                      AppPermissions.getLabel(permKey, isMarathi),
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      permKey,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                    value: isSelected,
                    activeThumbColor: const Color(0xFF2E7D32),
                    onChanged: (val) {
                      setState(() {
                        if (val) {
                          _selectedPermissions.add(permKey);
                        } else {
                          _selectedPermissions.remove(permKey);
                        }
                        _detectPreset();
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
