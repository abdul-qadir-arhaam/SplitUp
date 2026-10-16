import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../data/friends_repository.dart';
import '../domain/friend_model.dart';
import 'edit_nickname_dialog.dart';
import '../../expenses/data/expenses_repository.dart';
import '../../expenses/presentation/expense_detail_sheet.dart';
import '../../settlements/data/settlements_repository.dart';
import '../../settlements/domain/settlement_model.dart';
import '../../settlements/presentation/settle_sheet.dart';
import '../../expenses/presentation/add_expense_screen.dart';
import '../../../core/auth/auth_provider.dart';

class FriendDetailScreen extends ConsumerStatefulWidget {
  final String friendId;

  const FriendDetailScreen({super.key, required this.friendId});

  @override
  ConsumerState<FriendDetailScreen> createState() => _FriendDetailScreenState();
}

class _FriendDetailScreenState extends ConsumerState<FriendDetailScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncServerData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncServerData();
    }
  }

  Future<void> _syncServerData() async {
    try {
      final refreshed = await ref.read(friendsNotifierProvider.notifier).refresh();
      final matches = refreshed.where((f) => f.id == widget.friendId);
      final friend = matches.isNotEmpty ? matches.first : null;
      final ledgerId = friend?.individualLedgerId;

      if (ledgerId != null &&
          ledgerId.isNotEmpty &&
          ledgerId != 'ldg_default') {
        await ref.read(expensesNotifierProvider.notifier).syncExpensesForLedger(ledgerId);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final myUserId = ref.watch(authNotifierProvider).user?.id ?? '';
    final asyncFriends = ref.watch(friendsNotifierProvider);
    final asyncExpenses = ref.watch(expensesNotifierProvider);
    final asyncSettlements = ref.watch(settlementsNotifierProvider);

    final friend = asyncFriends.maybeWhen(
      data: (items) => items.firstWhere(
        (f) => f.id == widget.friendId,
        orElse: () => FriendModel(
          id: widget.friendId,
          name: 'Friend',
          phoneE164: '+919876543210',
          isAppUser: true,
          individualLedgerId: 'ldg_default',
          netPaise: 0,
        ),
      ),
      orElse: () => FriendModel(
        id: widget.friendId,
        name: 'Friend',
        phoneE164: '+919876543210',
        isAppUser: true,
        individualLedgerId: 'ldg_default',
        netPaise: 0,
      ),
    );

    final expenses = asyncExpenses.maybeWhen(
      data: (list) => list
          .where((e) =>
              e.ledgerId == friend.individualLedgerId ||
              e.payers.any((p) => p.userId == friend.id) ||
              e.splits.any((s) => s.userId == friend.id))
          .toList(),
      orElse: () => const [],
    );

    final settlements = asyncSettlements.maybeWhen(
      data: (list) => list.where((s) => s.fromUserId == friend.id || s.toUserId == friend.id).toList(),
      orElse: () => const <SettlementModel>[],
    );

    final pendingMatches = settlements.where((s) => s.isPending || s.isOutdated);
    final pendingSettlement = pendingMatches.isEmpty ? null : pendingMatches.first;

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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.accentReceive,
        foregroundColor: Colors.black,
        elevation: 4,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: Text(
          'Add Expense',
          style: SplitUpTypography.title(color: Colors.black).copyWith(fontSize: 14),
        ),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (ctx) => AddExpenseScreen(
                friendId: friend.id,
                initialLedgerId: friend.individualLedgerId,
              ),
            ),
          );
        },
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: colors.accentReceive,
            backgroundColor: colors.surfaceFlatRaised,
            onRefresh: _syncServerData,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
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
                    if (friend.commonGroups.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Also in:',
                            style: SplitUpTypography.caption(color: colors.textMuted),
                          ),
                          ...friend.commonGroups.map(
                            (grp) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.accentBrass.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colors.accentBrass.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                grp,
                                style: SplitUpTypography.caption(color: colors.accentBrass),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
                          final uri = Uri.parse(
                              'sms:${friend.phoneE164}?body=Hey! I added you on SplitUp to track our shared expenses. Download the app: https://splitup.app/download');
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
                      isOwe
                          ? 'YOU OWE ${friend.resolvedName.toUpperCase()}'
                          : (friend.netPaise > 0
                              ? '${friend.resolvedName.toUpperCase()} OWES YOU'
                              : 'ALL SETTLED UP'),
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

                    // Settle Button: STRICT INVARIANT: Visible ONLY when user owes money
                    if (isOwe) ...[
                      const SizedBox(height: 18),
                      PrimaryButton(
                        label: 'Settle ${formatPaise(friend.netPaise.abs())}',
                        icon: Icons.check_circle_outline,
                        onPressed: () => SettleSheet.show(context, friend),
                      ),
                    ],
                  ],
                ),
              ),

              // Pending / Outdated Settlement Banner if present
              if (pendingSettlement != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: pendingSettlement.isOutdated
                        ? colors.accentOwe.withValues(alpha: 0.12)
                        : colors.surfaceFlatRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: pendingSettlement.isOutdated ? colors.accentOwe : colors.accentBrass,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                pendingSettlement.isOutdated
                                    ? Icons.warning_amber_rounded
                                    : Icons.hourglass_top_rounded,
                                size: 18,
                                color: pendingSettlement.isOutdated ? colors.accentOwe : colors.accentBrass,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                pendingSettlement.isOutdated ? 'Settlement Outdated' : 'Settlement Pending',
                                style: SplitUpTypography.title(
                                  color: pendingSettlement.isOutdated ? colors.accentOwe : colors.accentBrass,
                                ).copyWith(fontSize: 14),
                              ),
                            ],
                          ),
                          Text(
                            formatPaise(pendingSettlement.amountPaise),
                            style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        pendingSettlement.isOutdated
                            ? 'The balance changed since this request was made. Tap resubmit to adjust the amount.'
                            : (pendingSettlement.fromUserId != friend.id
                                ? 'Waiting for ${friend.resolvedName} to confirm receipt.'
                                : '${friend.resolvedName} sent you this settlement request.'),
                        style: SplitUpTypography.caption(color: colors.textSecondary),
                      ),
                      if (pendingSettlement.isOutdated && (pendingSettlement.fromUserId != friend.id)) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.accentBrass),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(Icons.refresh_rounded, size: 16, color: colors.accentBrass),
                          label: Text('Resubmit Amount', style: TextStyle(color: colors.accentBrass)),
                          onPressed: () async {
                            await ref.read(settlementsNotifierProvider.notifier).resubmitSettlement(
                                  pendingSettlement.id,
                                  newAmountPaise: friend.netPaise.abs(),
                                );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Resubmitted settlement with current balance.')),
                              );
                            }
                          },
                        ),
                      ],
                      if (pendingSettlement.isPending && (pendingSettlement.toUserId != friend.id)) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colors.accentReceive,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: const Text('Confirm'),
                                onPressed: () => ref
                                    .read(settlementsNotifierProvider.notifier)
                                    .confirmSettlement(pendingSettlement.id),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colors.accentOwe,
                                  side: BorderSide(color: colors.accentOwe),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.close_rounded, size: 16),
                                label: const Text('Reject'),
                                onPressed: () => ref
                                    .read(settlementsNotifierProvider.notifier)
                                    .rejectSettlement(pendingSettlement.id),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],

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
                'Shared Expenses (${expenses.length})',
                style: SplitUpTypography.title(color: colors.textPrimary),
              ),
              const SizedBox(height: 12),

              // Real Expense Items list
              if (expenses.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colors.surfaceFlat,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Center(
                    child: Text(
                      'No shared expenses yet. Tap Add Expense below to record your first expense!',
                      style: SplitUpTypography.body(color: colors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ...expenses.map((exp) {
                  final isDisputed = exp.isDisputed;
                  final isPayerMe = exp.payers.isNotEmpty &&
                      (exp.payers.first.userId != friend.id || exp.payers.first.userId == myUserId);
                  final payerName = isPayerMe ? 'You' : friend.resolvedName;

                  return InkWell(
                    onTap: () => ExpenseDetailSheet.show(context, exp, friendId: friend.id),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surfaceFlat,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDisputed ? colors.accentOwe.withValues(alpha: 0.6) : colors.divider,
                        ),
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
                                  : (exp.category == 'travel'
                                      ? Icons.directions_car_rounded
                                      : Icons.receipt_long_rounded),
                              size: 20,
                              color: isDisputed ? colors.accentOwe : colors.accentBrass,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        exp.title,
                                        style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isDisputed) ...[
                                      const SizedBox(width: 6),
                                      Icon(Icons.flag_rounded, size: 14, color: colors.accentOwe),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Paid by $payerName',
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
                                exp.splitType.toLowerCase(),
                                style: SplitUpTypography.caption(color: colors.textMuted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    ),
  );
  }
}
