import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/config/routes.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/providers/order_provider.dart';
import 'package:shantinath_agro/models/user_model.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    final orderProvider = context.watch<OrderProvider>();
    final isMarathi = localeProvider.isMarathi;

    final user = authProvider.currentUser;
    final totalOrders = orderProvider.orders.length;

    if (user == null) {
      return Scaffold(
        body: Center(
          child: Text(
            isMarathi ? 'कोणताही वापरकर्ता लॉग इन केलेला नाही' : 'No user logged in',
            style: const TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    final initials = user.name.isNotEmpty
        ? user.name.split(' ').map((e) => e[0]).take(2).join().toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // User Avatar with initials
              CircleAvatar(
                radius: 50,
                backgroundColor: const Color(0xFF2E7D32),
                child: Text(
                  initials,
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // User name
              Text(
                user.name,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1B5E20),
                ),
              ),
              const SizedBox(height: 4),
              // User phone
              Text(
                user.phone,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),

              // Statistics Section (Total Orders)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          '$totalOrders',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2E7D32),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isMarathi ? 'एकूण ऑर्डर्स' : 'Total Orders',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey.shade200,
                    ),
                    Column(
                      children: [
                        Text(
                          user.village.isNotEmpty ? user.village : '-',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFFF8F00),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isMarathi ? 'गाव / शहर' : 'Village / City',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Business Profile card (if customer)
              if (user.isCustomer) ...[
                _buildBusinessDetailsCard(context, user, isMarathi),
                const SizedBox(height: 24),
              ],

              // Options Menu
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Language Selection Tile
                    ListTile(
                      leading: const Icon(Icons.language, color: Color(0xFF2E7D32)),
                      title: Text(
                        isMarathi ? 'भाषा (Language)' : 'Language',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            localeProvider.currentLanguageName,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Switch(
                            value: localeProvider.isMarathi,
                            onChanged: (_) {
                              localeProvider.toggleLocale();
                            },
                            activeColor: const Color(0xFF2E7D32),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Admin Panel button (only if user is admin)
                    if (authProvider.isAdmin) ...[
                      ListTile(
                        leading: const Icon(Icons.admin_panel_settings_outlined, color: Color(0xFFFF8F00)),
                        title: Text(
                          isMarathi ? 'ॲडमीन पॅनेल' : 'Admin Panel',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.pushNamed(context, AppRoutes.adminDashboard);
                        },
                      ),
                      const Divider(height: 1),
                    ],
                    // Logout tile
                    ListTile(
                      leading: const Icon(Icons.logout_rounded, color: Colors.red),
                      title: Text(
                        isMarathi ? 'लॉगआउट' : 'Logout',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        // Confirm logout
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(isMarathi ? 'लॉगआउटची पुष्टी करा' : 'Confirm Logout'),
                            content: Text(
                              isMarathi
                                  ? 'तुम्हाला नक्की लॉगआउट करायचे आहे का?'
                                  : 'Are you sure you want to logout?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  isMarathi ? 'रद्द करा' : 'Cancel',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  authProvider.logout();
                                  Navigator.pushNamedAndRemoveUntil(
                                    context,
                                    AppRoutes.login,
                                    (route) => false,
                                  );
                                },
                                child: Text(
                                  isMarathi ? 'लॉगआउट' : 'Logout',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // App logo branding / Version
              Text(
                'Shantinath Agro Agency',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Version 1.0.0 (Mock)',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBusinessDetailsCard(BuildContext context, UserModel user, bool isMarathi) {
    Widget _buildDetailRow(String label, String value, IconData icon) {
      if (value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: const Color(0xFF2E7D32)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF212121),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.business_rounded, color: Color(0xFF2E7D32), size: 24),
              const SizedBox(width: 10),
              Text(
                isMarathi ? 'व्यवसाय तपशील' : 'Business Details',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1B5E20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            isMarathi ? 'फर्मचे नाव' : 'Firm Name',
            user.firmName,
            Icons.storefront_rounded,
          ),
          _buildDetailRow(
            isMarathi ? 'मालकाचे नाव' : 'Proprietor Name',
            user.proprietorName,
            Icons.assignment_ind_rounded,
          ),
          _buildDetailRow(
            isMarathi ? 'ग्राहक प्रकार' : 'Customer Type',
            user.customerType.isEmpty 
                ? '' 
                : (user.customerType == 'wholesale' 
                    ? (isMarathi ? 'घाऊक विक्रेता (Wholesaler)' : 'Wholesaler') 
                    : (isMarathi ? 'किरकोळ विक्रेता (Retailer)' : 'Retailer')),
            Icons.badge_rounded,
          ),
          _buildDetailRow(
            isMarathi ? 'तालुका' : 'Taluka',
            user.taluka,
            Icons.map_rounded,
          ),
          _buildDetailRow(
            isMarathi ? 'जिल्हा' : 'District',
            user.district,
            Icons.my_location_rounded,
          ),
          _buildDetailRow(
            isMarathi ? 'जीएसटी क्रमांक' : 'GST Number',
            user.gstNo,
            Icons.percent_rounded,
          ),
          _buildDetailRow(
            isMarathi ? 'बियाणे परवाना क्रमांक' : 'Seed License Number',
            user.seedLicenceNumber,
            Icons.receipt_rounded,
          ),
          _buildDetailRow(
            isMarathi ? 'खत परवाना क्रमांक' : 'Fertilizer License Number',
            user.fertilizerLicenceNumber,
            Icons.science_rounded,
          ),
          _buildDetailRow(
            isMarathi ? '२ रा परवाना क्रमांक' : '2nd License Number',
            user.secondLicenceNumber,
            Icons.description_rounded,
          ),
          _buildDetailRow(
            isMarathi ? 'खात आयडी क्रमांक' : 'Khat ID Number',
            user.khatIdNo,
            Icons.tag_rounded,
          ),
        ],
      ),
    );
  }
}
