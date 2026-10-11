import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

enum AuthTab { signup, login }

class AuthScreen extends ConsumerStatefulWidget {
  final AuthTab initialTab;

  const AuthScreen({
    super.key,
    this.initialTab = AuthTab.login,
  });

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  late AuthTab _currentTab;

  // Sign Up Controllers
  final _signupNameController = TextEditingController();
  final _signupPhoneController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  bool _obscureSignupPassword = true;

  // Log In Controllers
  final _loginPhoneController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  bool _obscureLoginPassword = true;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
  }

  @override
  void dispose() {
    _signupNameController.dispose();
    _signupPhoneController.dispose();
    _signupEmailController.dispose();
    _signupPasswordController.dispose();
    _loginPhoneController.dispose();
    _loginPasswordController.dispose();
    super.dispose();
  }

  void _switchTab(AuthTab tab) {
    setState(() {
      _currentTab = tab;
      _errorMessage = null;
    });
  }

  void _fillDemoLogin() {
    setState(() {
      _loginPhoneController.text = '9876543210';
      _loginPasswordController.text = 'password123';
      _errorMessage = null;
    });
  }

  // --- LOG IN FLOW ---
  Future<void> _handleLogin() async {
    final rawPhone = _loginPhoneController.text.trim();
    final password = _loginPasswordController.text;

    final phone = normalizePhone(rawPhone);
    if (phone.length != 10) {
      setState(() => _errorMessage = 'Please enter a valid 10-digit mobile number.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await ref.read(authNotifierProvider.notifier).login(
            phone: phone,
            password: password,
          );

      if (!mounted) return;
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome back, ${user.name}!'),
          backgroundColor: context.colors.accentReceive,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is AuthException ? e.message : e.toString();
      });
    }
  }

  // --- SIGN UP & OTP FLOW ---
  Future<void> _startSignupVerification() async {
    final name = _signupNameController.text.trim();
    final rawPhone = _signupPhoneController.text.trim();
    final email = _signupEmailController.text.trim();
    final password = _signupPasswordController.text;

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your full name.');
      return;
    }

    final phone = normalizePhone(rawPhone);
    if (phone.length != 10) {
      setState(() => _errorMessage = 'Please enter a valid 10-digit mobile number.');
      return;
    }

    if (email.isNotEmpty && !email.contains('@')) {
      setState(() => _errorMessage = 'Please enter a valid email address or leave it empty.');
      return;
    }

    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters long.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Send OTP to phone
      await ref.read(authNotifierProvider.notifier).sendOtp(phone);
      if (!mounted) return;
      setState(() => _isLoading = false);

      // Open OTP Verification Dialog
      _showOtpModal(
        name: name,
        phone: phone,
        email: email.isEmpty ? null : email,
        password: password,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is AuthException ? e.message : e.toString();
      });
    }
  }

  void _showOtpModal({
    required String name,
    required String phone,
    String? email,
    required String password,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OtpVerificationSheet(
        name: name,
        phone: phone,
        email: email,
        password: password,
        onVerified: () {
          Navigator.of(ctx).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Account created! Welcome, $name!'),
              backgroundColor: context.colors.accentReceive,
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.go('/home');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/welcome');
            }
          },
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Branding Header
                Center(
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: colors.glassFillStrong,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colors.glassBorder, width: 1.2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'S',
                      style: SplitUpTypography.displayAmount(
                        color: colors.accentReceive,
                      ).copyWith(fontSize: 34, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  _currentTab == AuthTab.signup ? 'Create SplitUp Account' : 'Welcome Back',
                  textAlign: TextAlign.center,
                  style: SplitUpTypography.headline(color: colors.textPrimary).copyWith(fontSize: 26),
                ),
                const SizedBox(height: 6),
                Text(
                  _currentTab == AuthTab.signup
                      ? 'Sign up with your mobile number to get started'
                      : 'Log in to access your expenses and split ledger',
                  textAlign: TextAlign.center,
                  style: SplitUpTypography.body(color: colors.textSecondary).copyWith(fontSize: 14),
                ),
                const SizedBox(height: 24),

                // Animated Tab Switcher Pill
                _buildTabSwitcher(colors),
                const SizedBox(height: 24),

                // Error Banner
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colors.accentOwe.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.accentOwe.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: colors.accentOwe, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: SplitUpTypography.body(color: colors.accentOwe).copyWith(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Tab Content
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 260),
                  crossFadeState: _currentTab == AuthTab.signup
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: _buildSignupForm(colors),
                  secondChild: _buildLoginForm(colors),
                ),

                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabSwitcher(SplitUpColors colors) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.glassFillStrong,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'Sign Up',
              icon: Icons.person_add_outlined,
              isSelected: _currentTab == AuthTab.signup,
              onTap: () => _switchTab(AuthTab.signup),
              colors: colors,
            ),
          ),
          Expanded(
            child: _TabButton(
              label: 'Log In',
              icon: Icons.login_rounded,
              isSelected: _currentTab == AuthTab.login,
              onTap: () => _switchTab(AuthTab.login),
              colors: colors,
            ),
          ),
        ],
      ),
    );
  }

  // --- SIGN UP VIEW ---
  Widget _buildSignupForm(SplitUpColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Name Field (Required)
        _buildFieldLabel('Full Name *', colors),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: TextField(
            controller: _signupNameController,
            textCapitalization: TextCapitalization.words,
            style: SplitUpTypography.title(color: colors.textPrimary),
            decoration: InputDecoration(
              icon: Icon(Icons.person_outline_rounded, color: colors.accentReceive, size: 22),
              hintText: 'e.g. Rahul Sharma',
              hintStyle: SplitUpTypography.title(color: colors.textMuted),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Phone Field (Required)
        _buildFieldLabel('Mobile Number *', colors),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              Text(
                '🇮🇳 +91',
                style: SplitUpTypography.title(color: colors.textPrimary),
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 24, color: colors.divider),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _signupPhoneController,
                  keyboardType: TextInputType.phone,
                  style: SplitUpTypography.title(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '10-digit mobile number',
                    hintStyle: SplitUpTypography.title(color: colors.textMuted),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Email Field (Optional)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildFieldLabel('Email Address', colors),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceFlatRaised,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Optional',
                style: SplitUpTypography.caption(color: colors.textMuted),
              ),
            ),
          ],
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: TextField(
            controller: _signupEmailController,
            keyboardType: TextInputType.emailAddress,
            style: SplitUpTypography.title(color: colors.textPrimary),
            decoration: InputDecoration(
              icon: Icon(Icons.email_outlined, color: colors.textSecondary, size: 20),
              hintText: 'name@example.com',
              hintStyle: SplitUpTypography.title(color: colors.textMuted),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Password Field (Required)
        _buildFieldLabel('Set Password *', colors),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: TextField(
            controller: _signupPasswordController,
            obscureText: _obscureSignupPassword,
            style: SplitUpTypography.title(color: colors.textPrimary),
            decoration: InputDecoration(
              icon: Icon(Icons.lock_outline_rounded, color: colors.accentBrass, size: 20),
              hintText: 'Minimum 6 characters',
              hintStyle: SplitUpTypography.title(color: colors.textMuted),
              border: InputBorder.none,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureSignupPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: colors.textMuted,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscureSignupPassword = !_obscureSignupPassword);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Continue Button
        PrimaryButton(
          label: 'Verify Phone & Sign Up',
          icon: Icons.verified_user_rounded,
          isLoading: _isLoading,
          onPressed: _startSignupVerification,
        ),
        const SizedBox(height: 16),

        Center(
          child: GestureDetector(
            onTap: () => _switchTab(AuthTab.login),
            child: RichText(
              text: TextSpan(
                text: 'Already have an account? ',
                style: SplitUpTypography.body(color: colors.textSecondary),
                children: [
                  TextSpan(
                    text: 'Log In',
                    style: SplitUpTypography.title(color: colors.accentReceive).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- LOG IN VIEW ---
  Widget _buildLoginForm(SplitUpColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Quick Demo Fill Action Chip
        Center(
          child: InkWell(
            onTap: _fillDemoLogin,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.accentReceive.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.accentReceive.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, size: 16, color: colors.accentReceive),
                  const SizedBox(width: 6),
                  Text(
                    'Fill Demo Credentials (9876543210)',
                    style: SplitUpTypography.caption(color: colors.accentReceive).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Phone Field
        _buildFieldLabel('Registered Mobile Number', colors),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              Text(
                '🇮🇳 +91',
                style: SplitUpTypography.title(color: colors.textPrimary),
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 24, color: colors.divider),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _loginPhoneController,
                  keyboardType: TextInputType.phone,
                  style: SplitUpTypography.title(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '10-digit mobile number',
                    hintStyle: SplitUpTypography.title(color: colors.textMuted),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Password Field
        _buildFieldLabel('Password', colors),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: TextField(
            controller: _loginPasswordController,
            obscureText: _obscureLoginPassword,
            style: SplitUpTypography.title(color: colors.textPrimary),
            decoration: InputDecoration(
              icon: Icon(Icons.lock_outline_rounded, color: colors.accentReceive, size: 20),
              hintText: 'Enter your password',
              hintStyle: SplitUpTypography.title(color: colors.textMuted),
              border: InputBorder.none,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureLoginPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: colors.textMuted,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscureLoginPassword = !_obscureLoginPassword);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Log In Button
        PrimaryButton(
          label: 'Log In to SplitUp',
          icon: Icons.login_rounded,
          isLoading: _isLoading,
          onPressed: _handleLogin,
        ),
        const SizedBox(height: 16),

        Center(
          child: GestureDetector(
            onTap: () => _switchTab(AuthTab.signup),
            child: RichText(
              text: TextSpan(
                text: "Don't have an account? ",
                style: SplitUpTypography.body(color: colors.textSecondary),
                children: [
                  TextSpan(
                    text: 'Sign Up',
                    style: SplitUpTypography.title(color: colors.accentReceive).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label, SplitUpColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        label,
        style: SplitUpTypography.label(color: colors.textSecondary),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final SplitUpColors colors;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? colors.surfaceFlatRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: colors.glassBorder) : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? colors.accentReceive : colors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: SplitUpTypography.title(
                color: isSelected ? colors.textPrimary : colors.textMuted,
              ).copyWith(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive OTP Verification Sheet
class _OtpVerificationSheet extends ConsumerStatefulWidget {
  final String name;
  final String phone;
  final String? email;
  final String password;
  final VoidCallback onVerified;

  const _OtpVerificationSheet({
    required this.name,
    required this.phone,
    this.email,
    required this.password,
    required this.onVerified,
  });

  @override
  ConsumerState<_OtpVerificationSheet> createState() => _OtpVerificationSheetState();
}

class _OtpVerificationSheetState extends ConsumerState<_OtpVerificationSheet> {
  final _otpController = TextEditingController();
  bool _isSubmitting = false;
  String? _otpError;
  int _secondsLeft = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
      } else {
        t.cancel();
        setState(() => _secondsLeft = 0);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _resendCode() async {
    try {
      await ref.read(authNotifierProvider.notifier).sendOtp(widget.phone);
      _startCountdown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification code resent to +91 ${widget.phone} (Test: 123456)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _submitOtp() async {
    final enteredOtp = _otpController.text.trim();
    if (enteredOtp.length != 6) {
      setState(() => _otpError = 'Please enter the complete 6-digit verification code.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _otpError = null;
    });

    try {
      // Validate OTP
      await ref.read(authNotifierProvider.notifier).verifyOtpOnly(widget.phone, enteredOtp);

      // Register user with credentials
      await ref.read(authNotifierProvider.notifier).register(
            name: widget.name,
            phone: widget.phone,
            email: widget.email,
            password: widget.password,
          );

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      widget.onVerified();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _otpError = e is AuthException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceFlatRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: colors.glassBorder),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.accentReceive.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.sms_rounded, color: colors.accentReceive, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verify Phone Number',
                      style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sent OTP to +91 ${widget.phone}',
                      style: SplitUpTypography.body(color: colors.textSecondary).copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Dev OTP Banner Helper
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.glassFillStrong,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.glassBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.vpn_key_rounded, size: 16, color: colors.accentBrass),
                    const SizedBox(width: 8),
                    Text(
                      'Demo Code: 123456',
                      style: SplitUpTypography.label(color: colors.textSecondary),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _otpController.text = '123456';
                      _otpError = null;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.accentReceive.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Auto-fill',
                      style: SplitUpTypography.caption(color: colors.accentReceive).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // OTP Input Box
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofocus: true,
              style: SplitUpTypography.titleAmount(color: colors.textPrimary).copyWith(
                fontSize: 26,
                letterSpacing: 14,
              ),
              decoration: InputDecoration(
                hintText: '------',
                hintStyle: SplitUpTypography.titleAmount(color: colors.textMuted).copyWith(
                  fontSize: 26,
                  letterSpacing: 14,
                ),
                border: InputBorder.none,
              ),
            ),
          ),

          if (_otpError != null) ...[
            const SizedBox(height: 10),
            Text(
              _otpError!,
              style: SplitUpTypography.body(color: colors.accentOwe).copyWith(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 12),
          Center(
            child: _secondsLeft > 0
                ? Text(
                    'Resend code in ${_secondsLeft}s',
                    style: SplitUpTypography.caption(color: colors.textMuted),
                  )
                : TextButton(
                    onPressed: _resendCode,
                    child: Text(
                      'Resend Verification OTP',
                      style: SplitUpTypography.label(color: colors.accentReceive),
                    ),
                  ),
          ),
          const SizedBox(height: 16),

          PrimaryButton(
            label: 'Verify & Complete Sign Up',
            icon: Icons.check_circle_rounded,
            isLoading: _isSubmitting,
            onPressed: _submitOtp,
          ),
        ],
      ),
    );
  }
}
