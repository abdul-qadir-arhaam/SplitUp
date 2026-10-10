import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../friends/data/friends_repository.dart';
import '../../friends/domain/friend_model.dart';

class ProfileScreen extends ConsumerWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const ProfileScreen({
    super.key,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final user = MockDataRepository.currentUser;
    final asyncFriends = ref.watch(friendsNotifierProvider);

    final friends = asyncFriends.maybeWhen(
      data: (items) => items,
      orElse: () => const <FriendModel>[],
    );

    int totalYouOwe = 0;
    int totalYouAreOwed = 0;
    for (final f in friends) {
      if (f.netPaise < 0) {
        totalYouOwe += f.netPaise.abs();
      } else if (f.netPaise > 0) {
        totalYouAreOwed += f.netPaise;
      }
    }
    final netBalance = totalYouAreOwed - totalYouOwe;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Profile',
          style: SplitUpTypography.headline(color: colors.textPrimary),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              // User Card
              GlassCard(
                strong: true,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Avatar(name: user.name, size: 64),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 20),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.phone,
                            style: SplitUpTypography.label(color: colors.textMuted),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.accentReceive.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Verified Account',
                              style: SplitUpTypography.caption(color: colors.accentReceive).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.edit_outlined, color: colors.textSecondary),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Summary Totals Card: Total you owe, Total you are owed, Net
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FINANCIAL TOTALS',
                      style: SplitUpTypography.caption(color: colors.textMuted).copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total you owe', style: SplitUpTypography.body(color: colors.textSecondary)),
                        MoneyText(totalYouOwe, variant: MoneyVariant.title, customColor: colors.accentOwe),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total you are owed', style: SplitUpTypography.body(color: colors.textSecondary)),
                        MoneyText(totalYouAreOwed, variant: MoneyVariant.title, customColor: colors.accentReceive),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Net Balance', style: SplitUpTypography.title(color: colors.textPrimary)),
                        MoneyText(
                          netBalance.abs(),
                          variant: MoneyVariant.title,
                          customColor: netBalance < 0
                              ? colors.accentOwe
                              : (netBalance > 0 ? colors.accentReceive : colors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Theme Appearance Selector
              Text(
                'Appearance',
                style: SplitUpTypography.label(color: colors.textMuted),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.surfaceFlat,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.divider),
                ),
                child: SegmentedControl<ThemeMode>(
                  values: const [ThemeMode.system, ThemeMode.dark, ThemeMode.light],
                  labels: const ['System', 'Dark', 'Light'],
                  selected: currentThemeMode,
                  onSelected: onThemeModeChanged,
                ),
              ),
              const SizedBox(height: 24),

              // Settings Items
              Text(
                'Settings & Preferences',
                style: SplitUpTypography.label(color: colors.textMuted),
              ),
              const SizedBox(height: 8),

              _SettingsTile(
                icon: Icons.notifications_none_rounded,
                title: 'Notification Preferences',
                colors: colors,
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.block_flipped,
                title: 'Blocked Users',
                colors: colors,
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.system_update_rounded,
                title: 'App Version',
                trailingText: 'v1.0.0 (Build 1)',
                colors: colors,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: colors.surfaceFlatRaised,
                      content: Text(
                        'You are running the latest version of SplitUp.',
                        style: SplitUpTypography.body(color: colors.textPrimary),
                      ),
                    ),
                  );
                },
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy & Terms',
                colors: colors,
                onTap: () {},
              ),

              const SizedBox(height: 20),

              // Logout Button
              SecondaryButton(
                label: 'Sign Out',
                icon: Icons.logout_rounded,
                textColor: colors.accentOwe,
                onPressed: () => context.go('/welcome'),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingText;
  final SplitUpColors colors;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailingText,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surfaceFlat,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          leading: Icon(icon, color: colors.textSecondary, size: 20),
          title: Text(
            title,
            style: SplitUpTypography.body(color: colors.textPrimary),
          ),
          trailing: trailingText != null
              ? Text(trailingText!, style: SplitUpTypography.caption(color: colors.textMuted))
              : Icon(Icons.arrow_forward_ios_rounded, color: colors.textMuted, size: 14),
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
