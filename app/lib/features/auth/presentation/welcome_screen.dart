import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),

                // Hero Logo & Tagline
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colors.glassFillStrong,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: colors.glassBorder, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'S',
                      style: SplitUpTypography.displayAmount(
                        color: colors.accentReceive,
                      ).copyWith(fontSize: 42, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'SplitUp',
                  textAlign: TextAlign.center,
                  style: SplitUpTypography.headline(color: colors.textPrimary).copyWith(
                    fontSize: 32,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Split up the bill, not the friendship.',
                  textAlign: TextAlign.center,
                  style: SplitUpTypography.body(color: colors.textSecondary).copyWith(
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 24),

                // Features Card Preview
                GlassCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      _FeatureRow(
                        icon: Icons.flash_on_rounded,
                        title: 'Fast & Amount-First',
                        subtitle: 'Log shared expenses with real-time Indian split math.',
                        colors: colors,
                      ),
                      const SizedBox(height: 14),
                      _FeatureRow(
                        icon: Icons.verified_user_rounded,
                        title: 'Two-Party Settlement',
                        subtitle: 'Confirmations by both friends avoid any payment dispute.',
                        colors: colors,
                      ),
                      const SizedBox(height: 14),
                      _FeatureRow(
                        icon: Icons.hub_rounded,
                        title: 'Smart Simplification',
                        subtitle: 'Visual node graph reduces group dues to minimal transactions.',
                        colors: colors,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Sign-In Actions
                PrimaryButton(
                  label: 'Create Account (Sign Up)',
                  icon: Icons.person_add_rounded,
                  onPressed: () => context.push('/signup'),
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Log In with Phone & Password',
                  icon: Icons.login_rounded,
                  onPressed: () => context.push('/login'),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: Icon(Icons.g_mobiledata_rounded, color: colors.textSecondary, size: 22),
                  label: Text('Continue with Google', style: SplitUpTypography.label(color: colors.textSecondary)),
                  onPressed: () async {
                    final res = await ref.read(authNotifierProvider.notifier).signInWithGoogle();
                    if (!context.mounted) return;
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
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'By continuing, you agree to our Terms & Privacy Policy.',
                  textAlign: TextAlign.center,
                  style: SplitUpTypography.caption(color: colors.textMuted),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final SplitUpColors colors;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.accentReceive.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: colors.accentReceive),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15)),
              const SizedBox(height: 2),
              Text(subtitle, style: SplitUpTypography.body(color: colors.textMuted).copyWith(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}
