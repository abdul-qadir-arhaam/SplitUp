import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/friends_repository.dart';
import '../domain/friend_model.dart';
import 'edit_nickname_dialog.dart';

class FriendDetailScreen extends ConsumerWidget {
  final String friendId;

  const FriendDetailScreen({super.key, required this.friendId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final asyncFriends = ref.watch(friendsNotifierProvider);

    final friend = asyncFriends.maybeWhen(
      data: (items) => items.firstWhere(
        (f) => f.id == friendId,
        orElse: () => FriendModel(
          id: friendId,
          name: 'Friend',
          phoneE164: '+919876543210',
          isAppUser: true,
          individualLedgerId: 'ldg_default',
          netPaise: 0,
        ),
      ),
      orElse: () => FriendModel(
        id: friendId,
        name: 'Friend',
        phoneE164: '+919876543210',
        isAppUser: true,
        individualLedgerId: 'ldg_default',
        netPaise: 0,
      ),
    );

    final expenses = MockDataRepository.expenses;
    final isOwe = friend.netPaise < 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          friend.resolvedName,
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: colors.textPrimary),
            color: colors.surfaceFlatRaised,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (value) async {
              if (value == 'edit_nickname') {
                EditNicknameDialog.show(context, friend);
              } else if (value == 'unfriend') {
                try {
                  await ref.read(friendsNotifierProvider.notifier).removeFriend(friend.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Removed ${friend.resolvedName} from friends.')),
                    );
                    context.pop();
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: colors.accentOwe),
                    );
                  }
                }
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'edit_nickname',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: colors.textPrimary),
                    const SizedBox(width: 10),
                    Text('Edit Name / Nickname', style: TextStyle(color: colors.textPrimary)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'unfriend',
                child: Row(
                  children: [
                    Icon(Icons.person_remove_outlined, size: 18, color: colors.accentOwe),
                    const SizedBox(width: 10),
                    Text('Remove Friend', style: TextStyle(color: colors.accentOwe)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              // Friend Header Hero Card
              GlassCard(
                strong: true,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Avatar(
                      name: friend.resolvedName,
                      size: 64,
                      isPlaceholder: !friend.isAppUser,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      friend.resolvedName,
                      style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 20),
                    ),
                    if (friend.nickname != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Profile name: ${friend.name}',
                        style: SplitUpTypography.caption(color: colors.textMuted),
                      ),
                    ],
                    Text(
                      friend.phoneE164,
                      style: SplitUpTypography.label(color: colors.textMuted),
                    ),
                    if (!friend.isAppUser) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.accentReceive),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(Icons.sms_outlined, size: 16, color: colors.accentReceive),
                        label: Text('Not on app. Invite again.', style: TextStyle(color: colors.accentReceive)),
                        onPressed: () async {
                          final uri = Uri.parse('sms:${friend.phoneE164}?body=Hey! I added you on SplitUp to track our shared expenses. Download the app: https://splitup.app/download');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(height: 1, color: colors.divider),
                    const SizedBox(height: 16),
                    Text(
                      isOwe ? 'YOU OWE ${friend.resolvedName.toUpperCase()}' : (friend.netPaise > 0 ? '${friend.resolvedName.toUpperCase()} OWES YOU' : 'ALL SETTLED UP'),
                      style: SplitUpTypography.caption(color: colors.textMuted).copyWith(
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    MoneyText(
                      friend.netPaise.abs(),
                      variant: MoneyVariant.title,
                      customColor: isOwe
                          ? colors.accentOwe
                          : (friend.netPaise > 0 ? colors.accentReceive : colors.textSecondary),
                    ),
                    if (isOwe) ...[
                      const SizedBox(height: 18),
                      PrimaryButton(
                        label: 'Settle ${formatPaise(friend.netPaise.abs())}',
                        icon: Icons.check_circle_outline,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: colors.surfaceFlatRaised,
                              content: Text(
                                'Settlement request sent to ${friend.resolvedName}!',
                                style: SplitUpTypography.body(color: colors.textPrimary),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),

              // "Also in" Groups section
              if (friend.commonGroups.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Also in groups',
                  style: SplitUpTypography.label(color: colors.textMuted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: friend.commonGroups.map((g) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colors.surfaceFlat,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.divider),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.group_outlined, size: 14, color: colors.accentBrass),
                          const SizedBox(width: 6),
                          Text(
                            g,
                            style: SplitUpTypography.label(color: colors.textPrimary),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 24),
              Text(
                'Shared Expenses & Activity',
                style: SplitUpTypography.title(color: colors.textPrimary),
              ),
              const SizedBox(height: 12),

              // Expense items
              ...expenses.map((exp) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceFlat,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.surfaceFlatRaised,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          exp.category == 'food'
                              ? Icons.restaurant_rounded
                              : (exp.category == 'travel' ? Icons.directions_car_rounded : Icons.receipt_long_rounded),
                          size: 20,
                          color: colors.accentBrass,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exp.title,
                              style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Paid by ${exp.paidBy.displayName}',
                              style: SplitUpTypography.caption(color: colors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(
                            exp.totalPaise,
                            variant: MoneyVariant.body,
                            colored: false,
                          ),
                          Text(
                            'Equal split',
                            style: SplitUpTypography.caption(color: colors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
