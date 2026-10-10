import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';

class PhoneOtpScreen extends ConsumerStatefulWidget {
  const PhoneOtpScreen({super.key});

  @override
  ConsumerState<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends ConsumerState<PhoneOtpScreen> {
  final _phoneController = TextEditingController(text: '9876543210');
  final _otpController = TextEditingController();
  bool _codeSent = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleSendCode() async {
    setState(() => _isLoading = true);
    await ref.read(authNotifierProvider.notifier).sendOtp(_phoneController.text);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _codeSent = true;
        _otpController.text = '123456'; // Test OTP
      });
    }
  }

  Future<void> _handleVerify() async {
    setState(() => _isLoading = true);
    final res = await ref.read(authNotifierProvider.notifier).verifyOtp(
          _phoneController.text,
          _otpController.text,
        );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res?.mergeSummary?.merged == true) {
      context.go(
        '/welcome-back',
        extra: {
          'expenseCount': res!.mergeSummary!.expenseCount,
          'totalPaise': res.mergeSummary!.totalPaise,
        },
      );
    } else {
      context.go('/home');
    }
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
          onPressed: () => context.pop(),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _codeSent ? 'Verify Phone' : 'Enter Phone Number',
                  style: SplitUpTypography.headline(color: colors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  _codeSent
                      ? 'We sent a 6-digit verification code to +91 ${_phoneController.text}.'
                      : 'We will send a 6-digit OTP to verify your account.',
                  style: SplitUpTypography.body(color: colors.textSecondary),
                ),
                const SizedBox(height: 32),

                if (!_codeSent) ...[
                  // Phone Input
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          '🇮🇳 +91',
                          style: SplitUpTypography.title(color: colors.textPrimary),
                        ),
                        const SizedBox(width: 12),
                        Container(width: 1, height: 28, color: colors.divider),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: SplitUpTypography.title(color: colors.textPrimary),
                            decoration: InputDecoration(
                              hintText: '10-digit number',
                              hintStyle: SplitUpTypography.title(color: colors.textMuted),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  PrimaryButton(
                    label: 'Send Verification Code',
                    isLoading: _isLoading,
                    onPressed: _handleSendCode,
                  ),
                ] else ...[
                  // OTP Input
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: SplitUpTypography.titleAmount(color: colors.textPrimary).copyWith(
                        fontSize: 28,
                        letterSpacing: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: '------',
                        hintStyle: SplitUpTypography.titleAmount(color: colors.textMuted).copyWith(
                          fontSize: 28,
                          letterSpacing: 16,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _handleSendCode,
                      child: Text(
                        'Resend OTP (Dev Code: 123456)',
                        style: SplitUpTypography.label(color: colors.accentBrass),
                      ),
                    ),
                  ),
                  const Spacer(),
                  PrimaryButton(
                    label: 'Verify & Continue',
                    isLoading: _isLoading,
                    onPressed: _handleVerify,
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
