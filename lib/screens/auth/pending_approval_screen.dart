import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/config/routes.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/services/notification_service.dart';

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}
class _PendingApprovalScreenState extends State<PendingApprovalScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  bool _isChecking = false;
  AuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();
    _authProvider = context.read<AuthProvider>();
    _authProvider!.addListener(_onAuthChanged);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.initialize(context, _authProvider!);
    });
  }

  void _onAuthChanged() {
    final user = _authProvider?.currentUser;
    if (user != null && user.isApproved) {
      if (mounted) {
        final isMarathi = context.read<LocaleProvider>().isMarathi;
        Navigator.pushReplacementNamed(context, AppRoutes.home);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isMarathi
                  ? 'तुमचे खाते मंजूर झाले आहे! स्वागत आहे.'
                  : 'Your account is approved! Welcome.',
            ),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthChanged);
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus(BuildContext context, AuthProvider authProvider, bool isMarathi) async {
    setState(() {
      _isChecking = true;
    });

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 1200));
    await authProvider.refreshCurrentUser();

    if (context.mounted) {
      setState(() {
        _isChecking = false;
      });

      final user = authProvider.currentUser;
      if (user != null && user.isApproved) {
        // Route to home if approved
        Navigator.pushReplacementNamed(context, AppRoutes.home);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isMarathi
                  ? 'तुमचे खाते मंजूर झाले आहे! स्वागत आहे.'
                  : 'Your account is approved! Welcome.',
            ),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isMarathi
                  ? 'तुमचे खाते अजूनही मंजुरीच्या प्रतीक्षेत आहे.'
                  : 'Your account is still pending admin approval.',
            ),
            backgroundColor: const Color(0xFFFF8F00),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    final isMarathi = localeProvider.isMarathi;

    final user = authProvider.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              // Animated Illustration/Icon
              ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.lock_clock_rounded,
                      size: 72,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Title
              Text(
                isMarathi ? 'खाते मंजुरी प्रलंबित आहे' : 'Account Approval Pending',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1B5E20),
                ),
              ),
              const SizedBox(height: 16),

              // Subtitle
              Text(
                isMarathi
                    ? 'शातीनाथ ॲग्रो एजन्सीच्या प्रशासकाद्वारे आपल्या खात्याचे पुनरावलोकन केले जात आहे. खाते मंजूर झाल्यानंतर आपल्याला सर्व सुविधेचा लाभ घेता येईल.'
                    : 'Your account is being verified by the Shantinath Agro Agency administrator. You will get full access once approved.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              // Details Card
              if (user != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: Colors.grey.shade100, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow(
                        isMarathi ? 'फर्मचे नाव:' : 'Firm Name:',
                        user.firmName,
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        isMarathi ? 'मालक:' : 'Proprietor:',
                        user.proprietorName,
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        isMarathi ? 'भ्रमणध्वनी:' : 'Phone:',
                        user.phone,
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        isMarathi ? 'गाव / शहर:' : 'Village / City:',
                        user.village,
                      ),
                    ],
                  ),
                ),

              const Spacer(),

              // Refresh Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isChecking ? null : () => _checkStatus(context, authProvider, isMarathi),
                  icon: _isChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync_rounded, color: Colors.white),
                  label: Text(
                    isMarathi ? 'स्थिती तपासा' : 'Check Status',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Logout Button
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    await authProvider.logout();
                    if (context.mounted) {
                      Navigator.pushReplacementNamed(context, AppRoutes.login);
                    }
                  },
                  icon: const Icon(Icons.logout_rounded, color: Colors.red),
                  label: Text(
                    isMarathi ? 'लॉगआउट करा' : 'Logout',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.red,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF212121),
            ),
          ),
        ),
      ],
    );
  }
}
