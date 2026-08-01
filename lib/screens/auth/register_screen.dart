import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/config/routes.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/widgets/otp_verification_sheet.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _villageController = TextEditingController();
  
  final _firmNameController = TextEditingController();
  final _seedLicenceController = TextEditingController();
  final _fertilizerLicenceController = TextEditingController();
  final _proprietorNameController = TextEditingController();
  final _gstNoController = TextEditingController();
  final _secondLicenceController = TextEditingController();
  final _talukaController = TextEditingController();
  final _districtController = TextEditingController();
  final _khatIdController = TextEditingController();
  String _customerType = 'retail'; // wholesale or retail

  bool _isLoading = false;
  List<Map<String, dynamic>> _tallyParties = [];
  bool _isLoadingParties = false;
  bool _isManualFirmEntry = false;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
    _fetchTallyParties();
  }

  Future<void> _fetchTallyParties() async {
    setState(() => _isLoadingParties = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final parties = await authProvider.getTallyParties();
      setState(() {
        _tallyParties = parties;
        _isLoadingParties = false;
      });
    } catch (e) {
      setState(() => _isLoadingParties = false);
    }
  }

  void _showPartySelectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      builder: (context) {
        return _PartySelectionBottomSheet(
          parties: _tallyParties,
          isLoading: _isLoadingParties,
          onSelected: (party) {
            setState(() {
              _firmNameController.text = party['name'] as String? ?? '';
              
              final partyGst = party['gstNo'] as String? ?? '';
              if (partyGst.isNotEmpty) {
                _gstNoController.text = partyGst;
              }
              
              final partyVillage = party['village'] as String? ?? '';
              if (partyVillage.isNotEmpty) {
                _villageController.text = partyVillage;
              }
              
              final partyDistrict = party['district'] as String? ?? '';
              if (partyDistrict.isNotEmpty) {
                _districtController.text = partyDistrict;
              }
            });
            Navigator.pop(context);
          },
          onManualEntry: () {
            setState(() {
              _isManualFirmEntry = true;
              _firmNameController.clear();
            });
            Navigator.pop(context);
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _villageController.dispose();
    _firmNameController.dispose();
    _seedLicenceController.dispose();
    _fertilizerLicenceController.dispose();
    _proprietorNameController.dispose();
    _gstNoController.dispose();
    _secondLicenceController.dispose();
    _talukaController.dispose();
    _districtController.dispose();
    _khatIdController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final phone = _phoneController.text.trim();

      // Verify phone ownership via OTP before creating the account, unless this
      // phone was already verified earlier in the session (e.g. the user came
      // here from the login screen after a successful OTP check).
      if (!authProvider.isPhoneVerified(phone)) {
        final verified = await _verifyPhoneViaOtp(phone);
        if (!mounted) return;
        if (!verified) {
          setState(() => _isLoading = false);
          return;
        }
      }

      final success = await authProvider.register(
        name: _nameController.text.trim(),
        phone: phone,
        village: _villageController.text.trim(),
        firmName: _firmNameController.text.trim(),
        seedLicenceNumber: _seedLicenceController.text.trim(),
        fertilizerLicenceNumber: _fertilizerLicenceController.text.trim(),
        proprietorName: _proprietorNameController.text.trim(),
        gstNo: _gstNoController.text.trim().toUpperCase(),
        secondLicenceNumber: _secondLicenceController.text.trim(),
        taluka: _talukaController.text.trim(),
        district: _districtController.text.trim(),
        khatIdNo: _khatIdController.text.trim(),
        customerType: _customerType,
      );

      if (!mounted) return;

      if (success && authProvider.isLoggedIn) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => false,
        );
      } else {
        throw Exception(authProvider.errorMessage ?? 'Registration failed');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: ${e.toString()}'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Sends an OTP to [phone] and shows the verification sheet.
  /// Returns true only once the code has been successfully verified.
  Future<bool> _verifyPhoneViaOtp(String phone) async {
    final authProvider = context.read<AuthProvider>();

    final sent = await authProvider.sendOtp(phone);
    if (!mounted) return false;
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Failed to send OTP code'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return false;
    }

    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      builder: (_) => OtpVerificationSheet(
        phone: phone,
        onVerify: (otp) async {
          final ok = await authProvider.verifyOtpAndLogin(phone, otp);
          return ok
              ? null
              : (authProvider.errorMessage ??
                  'Incorrect OTP code. Please try again.');
        },
        onResend: () => authProvider.sendOtp(phone),
      ),
    );

    if (!mounted) return false;
    return verified == true && authProvider.isPhoneVerified(phone);
  }

  bool _phonePreFilled = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    if (!_phonePreFilled) {
      final verifiedPhone = ModalRoute.of(context)?.settings.arguments as String?;
      if (verifiedPhone != null && verifiedPhone.isNotEmpty) {
        _phoneController.text = verifiedPhone;
        _phonePreFilled = true;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(size),
            FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      Text(
                        'Create Account',
                        style: GoogleFonts.outfit(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1B5E20),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Fill in your details to get started',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildForm(),
                      const SizedBox(height: 32),
                      _buildRegisterButton(),
                      const SizedBox(height: 20),
                      _buildLoginLink(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Size size) {
    return Container(
      width: double.infinity,
      height: size.height * 0.28,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF43A047)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            // Back button
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Join Shantinath Agro',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.5,
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

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Section 1: Business Profile
          _buildSectionCard(
            title: 'Business & Contact Profile',
            children: [
              _buildTextField(
                controller: _nameController,
                label: 'Full Name',
                hint: 'Enter your full name',
                icon: Icons.person_rounded,
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  if (value.trim().length < 2) {
                    return 'Name must be at least 2 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _proprietorNameController,
                label: 'Proprietor Name',
                hint: 'Enter proprietor name',
                icon: Icons.assignment_ind_rounded,
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Proprietor name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _isManualFirmEntry ? null : _showPartySelectionSheet,
                child: AbsorbPointer(
                  absorbing: !_isManualFirmEntry,
                  child: _buildTextField(
                    controller: _firmNameController,
                    label: 'Firm Name',
                    hint: _isManualFirmEntry ? 'Enter your firm name' : 'Tap to select your firm (Tally Party Name)',
                    icon: Icons.business_rounded,
                    textCapitalization: TextCapitalization.words,
                    suffixIcon: _isManualFirmEntry
                        ? IconButton(
                            icon: const Icon(Icons.list_alt_rounded, color: Color(0xFF2E7D32)),
                            tooltip: 'Select from list',
                            onPressed: () {
                              setState(() {
                                _isManualFirmEntry = false;
                                _firmNameController.clear();
                              });
                            },
                          )
                        : const Icon(Icons.arrow_drop_down_circle_outlined, color: Color(0xFF2E7D32)),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Firm name is required';
                      }
                      return null;
                    },
                  ),
                ),
              ),
              if (!_isManualFirmEntry) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _isManualFirmEntry = true;
                        _firmNameController.clear();
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'My firm is not listed (New Customer)',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF2E7D32),
                          decoration: TextDecoration.underline,
                          decorationColor: const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
               _buildTextField(
                controller: _phoneController,
                label: 'Phone Number',
                hint: 'Enter 10-digit phone number',
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                enabled: !_phonePreFilled,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Phone number is required';
                  }
                  if (value.length != 10) {
                    return 'Enter a valid 10-digit number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildCustomerTypeSelector(),
            ],
          ),

          // Section 2: Location Info
          _buildSectionCard(
            title: 'Location Details',
            children: [
              _buildTextField(
                controller: _villageController,
                label: 'Village / City',
                hint: 'Enter your village or city name',
                icon: Icons.location_on_rounded,
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Village / City is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _talukaController,
                label: 'Taluka',
                hint: 'Enter taluka name',
                icon: Icons.map_rounded,
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Taluka is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _districtController,
                label: 'District',
                hint: 'Enter district name',
                icon: Icons.my_location_rounded,
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'District is required';
                  }
                  return null;
                },
              ),
            ],
          ),

          // Section 3: Licensing & Taxes (Optional)
          _buildSectionCard(
            title: 'Licensing & Taxes (Optional)',
            children: [
              _buildTextField(
                controller: _seedLicenceController,
                label: 'Seed License Number',
                hint: 'Enter seed license number',
                icon: Icons.receipt_rounded,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _fertilizerLicenceController,
                label: 'Fertilizer License Number',
                hint: 'Enter fertilizer license number',
                icon: Icons.science_rounded,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _secondLicenceController,
                label: '2nd License Number',
                hint: 'Enter secondary license number',
                icon: Icons.description_rounded,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _gstNoController,
                label: 'GST Number',
                hint: 'Enter 15-character GST number',
                icon: Icons.percent_rounded,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(15),
                ],
                validator: (value) {
                  if (value != null && value.isNotEmpty && value.length != 15) {
                    return 'GST number must be exactly 15 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _khatIdController,
                label: 'Khat ID Number',
                hint: 'Enter khat ID number',
                icon: Icons.tag_rounded,
                textCapitalization: TextCapitalization.characters,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1B5E20),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
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
            children: children,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCustomerTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer Type',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1B5E20),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  child: Text(
                    'Retailer',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      color: _customerType == 'retail' ? Colors.white : const Color(0xFF2E7D32),
                    ),
                  ),
                ),
                selected: _customerType == 'retail',
                selectedColor: const Color(0xFF2E7D32),
                backgroundColor: const Color(0xFFF5F5F0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _customerType == 'retail' ? const Color(0xFF2E7D32) : Colors.grey.shade200,
                    width: 1.5,
                  ),
                ),
                showCheckmark: false,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _customerType = 'retail');
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChoiceChip(
                label: Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  child: Text(
                    'Wholesaler',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      color: _customerType == 'wholesale' ? Colors.white : const Color(0xFF2E7D32),
                    ),
                  ),
                ),
                selected: _customerType == 'wholesale',
                selectedColor: const Color(0xFF2E7D32),
                backgroundColor: const Color(0xFFF5F5F0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _customerType == 'wholesale' ? const Color(0xFF2E7D32) : Colors.grey.shade200,
                    width: 1.5,
                  ),
                ),
                showCheckmark: false,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _customerType = 'wholesale');
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    bool enabled = true,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      validator: validator,
      enabled: enabled,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF2E7D32), size: 22),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: enabled ? const Color(0xFFF5F5F0) : Colors.grey.shade200,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  Widget _buildRegisterButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.6),
          elevation: 4,
          shadowColor: const Color(0xFF2E7D32).withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                'Create Account',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account? ',
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade600,
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Text(
            'Login',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2E7D32),
              decoration: TextDecoration.underline,
              decorationColor: const Color(0xFF2E7D32),
            ),
          ),
        ),
      ],
    );
  }
}

class _PartySelectionBottomSheet extends StatefulWidget {
  final List<Map<String, dynamic>> parties;
  final bool isLoading;
  final Function(Map<String, dynamic>) onSelected;
  final VoidCallback onManualEntry;

  const _PartySelectionBottomSheet({
    required this.parties,
    required this.isLoading,
    required this.onSelected,
    required this.onManualEntry,
  });

  @override
  State<_PartySelectionBottomSheet> createState() =>
      _PartySelectionBottomSheetState();
}

class _PartySelectionBottomSheetState
    extends State<_PartySelectionBottomSheet> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredParties = [];

  @override
  void initState() {
    super.initState();
    _filteredParties = widget.parties;
    _searchController.addListener(_filterParties);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterParties() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredParties = widget.parties;
      } else {
        _filteredParties = widget.parties.where((party) {
          final name = (party['name'] as String? ?? '').toLowerCase();
          final village = (party['village'] as String? ?? '').toLowerCase();
          final district = (party['district'] as String? ?? '').toLowerCase();
          return name.contains(query) ||
              village.contains(query) ||
              district.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: size.height * 0.8,
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: bottomPadding + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Select Your Firm',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1B5E20),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Search and select the name registered in Tally',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search firm name, village or district...',
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF2E7D32)),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF5F5F0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: widget.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
                    ),
                  )
                : _filteredParties.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        itemCount: _filteredParties.length,
                        separatorBuilder: (_, index) => Divider(color: Colors.grey.shade100, height: 1),
                        itemBuilder: (context, index) {
                          final party = _filteredParties[index];
                          final name = party['name'] as String? ?? 'Unknown Firm';
                          final village = party['village'] as String? ?? '';
                          final district = party['district'] as String? ?? '';
                          
                          String sub = '';
                          if (village.isNotEmpty && district.isNotEmpty) {
                            sub = '$village, $district';
                          } else {
                            sub = village.isNotEmpty ? village : district;
                          }

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            title: Text(
                              name,
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            subtitle: sub.isNotEmpty
                                ? Row(
                                    children: [
                                      const Icon(Icons.location_on_rounded, size: 12, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        sub,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  )
                                : null,
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFF2E7D32),
                            ),
                            onTap: () => widget.onSelected(party),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: widget.onManualEntry,
              icon: const Icon(Icons.add_business_rounded),
              label: Text(
                'My Firm is Not Listed (New Customer)',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2E7D32),
                side: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.search_off_rounded,
          size: 64,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 16),
        Text(
          'No matching firm found',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Check spelling or tap the button below to register as a new customer.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
          ),
        ),
      ],
    );
  }
}
