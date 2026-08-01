import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shantinath_agro/config/routes.dart';
import 'package:shantinath_agro/models/user_model.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/services/auth_service.dart';
import 'package:shantinath_agro/services/activity_service.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/config/permissions.dart';

class ManageEmployeesScreen extends StatefulWidget {
  const ManageEmployeesScreen({super.key});

  @override
  State<ManageEmployeesScreen> createState() => _ManageEmployeesScreenState();
}

class _ManageEmployeesScreenState extends State<ManageEmployeesScreen> {
  final AuthService _authService = AuthService();

  void _showAddEmployeeDialog(BuildContext context, bool isMarathi) {
    final phoneController = TextEditingController();
    final nameController = TextEditingController();
    String selectedPreset = 'Order Staff';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                isMarathi ? 'नवीन कर्मचारी जोडा' : 'Add New Employee',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: isMarathi ? 'कर्मचाऱ्याचे नाव' : 'Employee Name',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      decoration: InputDecoration(
                        labelText: isMarathi ? '१०-अंकी मोबाईल नंबर' : '10-digit Phone Number',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedPreset,
                      decoration: InputDecoration(
                        labelText: isMarathi ? 'भूमिका प्रीसेट' : 'Role Preset',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: ['Order Staff', 'Sales Rep', 'Full Admin'].map((String val) {
                        return DropdownMenuItem<String>(
                          value: val,
                          child: Text(val),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedPreset = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    isMarathi ? 'रद्द करा' : 'Cancel',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final phone = phoneController.text.trim();

                    if (name.isEmpty || phone.length != 10) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isMarathi ? 'कृपया अचूक नाव व १०-अंकी नंबर प्रविष्ट करा' : 'Please enter valid name and 10-digit phone'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    final authProvider = Provider.of<AuthProvider>(context, listen: false);
                    final currentUser = authProvider.currentUser;

                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(isMarathi ? 'कर्मचारी जोडला जात आहे...' : 'Adding employee...')),
                    );

                    try {
                      List<String> perms = [];
                      if (selectedPreset == 'Order Staff') {
                        perms = AppPermissions.orderStaffPreset;
                      } else if (selectedPreset == 'Sales Rep') {
                        perms = AppPermissions.salesRepPreset;
                      } else {
                        perms = AppPermissions.allPermissions;
                      }

                      await _authService.addEmployee(phone, name, perms);
                      ActivityService.log(
                        action: 'employee_added',
                        targetType: 'user',
                        targetId: phone,
                        summary: 'Admin ${currentUser?.name} added employee $name ($phone) with $selectedPreset preset.',
                        actor: currentUser,
                      );

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isMarathi ? 'कर्मचारी यशस्वीरित्या जोडला गेला!' : 'Employee added successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
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
                  child: Text(isMarathi ? 'जोडा' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRemoveConfirmDialog(BuildContext context, UserModel employee, bool isMarathi) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isMarathi ? 'कर्मचारी काढून टाका?' : 'Remove Employee?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
          content: Text(
            isMarathi
                ? 'तुम्ही निश्चितपणे ${employee.name} यांना कर्मचारी पदावरून काढू इच्छिता? त्यांचे परवानग्या काढून त्यांना सामान्य ग्राहक बनवले जाईल.'
                : 'Are you sure you want to demote ${employee.name}? Their staff permissions will be cleared and they will become a normal customer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(isMarathi ? 'रद्द करा' : 'Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                final currentUser = authProvider.currentUser;

                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isMarathi ? 'कर्मचारी काढला जात आहे...' : 'Removing employee...')),
                );

                try {
                  await _authService.removeEmployee(employee.phone);
                  ActivityService.log(
                    action: 'employee_removed',
                    targetType: 'user',
                    targetId: employee.phone,
                    summary: 'Admin ${currentUser?.name} removed employee ${employee.name} (${employee.phone}).',
                    actor: currentUser,
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isMarathi ? 'कर्मचारी यशस्वीरित्या काढला गेला!' : 'Employee removed successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
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
              child: Text(isMarathi ? 'काढून टाका' : 'Remove'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMarathi = Provider.of<LocaleProvider>(context).isMarathi;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text(
          isMarathi ? 'कर्मचारी व्यवस्थापन' : 'Manage Employees',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        onPressed: () => _showAddEmployeeDialog(context, isMarathi),
        child: const Icon(Icons.person_add_rounded),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'employee')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                isMarathi ? 'डेटा लोड करताना त्रुटी आली' : 'Error loading employees',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.badge_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    isMarathi ? 'अद्याप कोणतेही कर्मचारी जोडलेले नाहीत' : 'No employees added yet',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isMarathi ? 'खालील बटण दाबून कर्मचारी जोडा' : 'Click the button below to add staff',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          final employees = docs
              .map((d) => UserModel.fromJson(d.data() as Map<String, dynamic>))
              .toList();

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: employees.length,
            itemBuilder: (context, index) {
              final employee = employees[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                        foregroundColor: const Color(0xFF2E7D32),
                        child: Text(
                          employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        employee.name,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        employee.phone,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      children: [
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isMarathi ? 'परवानग्या:' : 'Permissions:',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Text(
                                    '${employee.permissions.length} ${isMarathi ? 'सक्रिय' : 'active'}',
                                    style: TextStyle(
                                      color: const Color(0xFF2E7D32),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: employee.permissions.take(3).map((perm) {
                                  return Chip(
                                    label: Text(
                                      AppPermissions.getLabel(perm, isMarathi),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    backgroundColor: Colors.grey[100],
                                    side: BorderSide(color: Colors.grey.shade300),
                                  );
                                }).toList()
                                  ..addAll(employee.permissions.length > 3
                                      ? [
                                          Chip(
                                            label: Text(
                                              '+${employee.permissions.length - 3} ${isMarathi ? 'इतर' : 'more'}',
                                              style: const TextStyle(fontSize: 11),
                                            ),
                                            padding: EdgeInsets.zero,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            backgroundColor: Colors.grey[200],
                                            side: BorderSide(color: Colors.grey.shade300),
                                          )
                                        ]
                                      : []),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pushNamed(
                                        context,
                                        AppRoutes.employeePermissions,
                                        arguments: employee,
                                      );
                                    },
                                    icon: const Icon(Icons.vpn_key_rounded, size: 16),
                                    label: Text(isMarathi ? 'परवानग्या' : 'Permissions'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF2E7D32),
                                      side: const BorderSide(color: Color(0xFF2E7D32)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _showRemoveConfirmDialog(context, employee, isMarathi),
                                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                    label: Text(isMarathi ? 'काढून टाका' : 'Remove'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red[50],
                                      foregroundColor: Colors.red,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                ),
              );
            },
          );
        },
      ),
    );
  }
}
