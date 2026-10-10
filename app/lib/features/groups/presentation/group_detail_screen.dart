import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../data/groups_repository.dart';
import '../domain/group_model.dart';
import '../../expenses/data/expenses_repository.dart';
import '../../settlements/presentation/settle_sheet.dart';
import '../../offsets/data/offsets_repository.dart';
import '../../offsets/domain/offset_model.dart';
import '../../friends/data/friends_repository.dart';
import '../../friends/domain/friend_model.dart';
import '../../expenses/presentation/add_expense_screen.dart';
import '../../notifications/data/notifications_repository.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showRenameDialog(GroupModel group) {
    final controller = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceFlatRaised,
        title: Text('Rename Group', style: SplitUpTypography.title(color: context.colors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: SplitUpTypography.body(color: context.colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'New group name',
            hintStyle: SplitUpTypography.caption(color: context.colors.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.colors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.colors.accentReceive),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(ctx);
                try {
                  await ref.read(groupsNotifierProvider.notifier).updateGroup(group.id, name: newName);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Renamed group to "$newName"')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to rename: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<MemberDisplayInfo?> _showAddMemberDialog(GroupModel group) async {
    final friendsAsync = ref.read(friendsNotifierProvider);
    final currentGroup = await ref.read(groupsRepositoryProvider).getGroupById(group.id);
    final availableFriends = friendsAsync.maybeWhen(
      data: (list) => list.where((f) => !currentGroup.memberIds.contains(f.id)).toList(),
      orElse: () => [],
    );

    if (availableFriends.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All your friends are already in this group!')),
        );
      }
      return null;
    }

    if (!mounted) return null;

    final selectedFriend = await showDialog<FriendModel>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: context.colors.surfaceFlatRaised,
        title: Text('Add Member to Group', style: SplitUpTypography.title(color: context.colors.textPrimary)),
        children: availableFriends.map((f) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, f),
            child: Row(
              children: [
                Avatar(name: f.resolvedName, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    f.resolvedName,
                    style: SplitUpTypography.body(color: context.colors.textPrimary),
                  ),
                ),
                Icon(Icons.add_circle_outline_rounded, color: context.colors.accentReceive, size: 20),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (selectedFriend != null) {
      try {
        await ref.read(groupsNotifierProvider.notifier).addMember(group.id, selectedFriend.id);
        ref.invalidate(groupDetailProvider(widget.groupId));
        ref.invalidate(groupDashboardProvider(widget.groupId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added ${selectedFriend.resolvedName} to group')),
          );
        }
        return MemberDisplayInfo(
          userId: selectedFriend.id,
          name: selectedFriend.resolvedName,
          phoneE164: selectedFriend.phoneE164,
          photoUrl: selectedFriend.photoUrl,
          role: 'MEMBER',
          netPaise: 0,
          isAppUser: selectedFriend.isAppUser,
          isMe: false,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to add member: $e')),
          );
        }
      }
    }
    return null;
  }

  void _showMembersSheet(GroupModel group) {
    final repo = ref.read(groupsRepositoryProvider);
    final members = group.members.map((m) {
      final debtDesc = repo.checkPendingDebts(m.userId, groupId: group.id);
      return MemberDisplayInfo(
        userId: m.userId,
        name: m.name,
        phoneE164: m.phoneE164,
        photoUrl: m.photoUrl,
        role: m.role,
        netPaise: m.netPaise,
        isAppUser: m.isAppUser,
        isMe: m.userId == 'usr_arhaam',
        debtDescription: debtDesc,
      );
    }).toList();

    MembersSheet.show(
      context: context,
      title: 'Group Members',
      entityName: group.name,
      members: members,
      onAddMember: group.isAdmin ? () => _showAddMemberDialog(group) : null,
      onRemoveMember: group.isAdmin
          ? (member) async {
              await ref
                  .read(groupsNotifierProvider.notifier)
                  .removeMember(group.id, member.userId);
              ref.invalidate(groupDetailProvider(widget.groupId));
              ref.invalidate(groupDashboardProvider(widget.groupId));
            }
          : null,
      onRemindToSettle: (member) async {
        final debtDesc = member.debtDescription ??
            (member.netPaise < 0 ? 'owes ${formatPaise(member.netPaise.abs())}' : 'unsettled balance');
        final notif = NotificationModel(
          id: 'notif_remind_${DateTime.now().millisecondsSinceEpoch}',
          type: 'SETTLEMENT_REQUESTED',
          title: 'Settlement Required: ${group.name}',
          body: '${member.name}, you need to settle some payment in ${group.name} with your friends ($debtDesc) before removal. Please settle your dues.',
          isRead: false,
          createdAt: DateTime.now(),
          payload: {
            'groupId': group.id,
            'groupName': group.name,
            'userId': member.userId,
            'userName': member.name,
            'netPaise': member.netPaise,
            'debtDescription': member.debtDescription,
          },
        );
        await ref.read(notificationsNotifierProvider.notifier).addNotification(notif);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: context.colors.accentReceive,
              content: Text(
                'Settlement notification sent to ${member.name} to settle payment with friends.',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
      },
    );
  }

  Future<void> _handleLeaveGroup(GroupModel group) async {
    try {
      await ref.read(groupsNotifierProvider.notifier).removeMember(group.id, 'usr_arhaam');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You left the group')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.colors.accentOwe,
            content: Text(
              e.toString().contains('UNSETTLED_BALANCE')
                  ? 'Cannot leave group while your balance is unsettled!'
                  : 'Failed to leave group: $e',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteGroup(GroupModel group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceFlatRaised,
        title: Text('Delete Group?', style: SplitUpTypography.title(color: context.colors.accentOwe)),
        content: Text(
          'Are you sure you want to delete "${group.name}"? This action cannot be undone.',
          style: SplitUpTypography.body(color: context.colors.textPrimary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.colors.accentOwe),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(groupsNotifierProvider.notifier).deleteGroup(group.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Group "${group.name}" deleted')),
          );
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: context.colors.accentOwe,
              content: Text(
                e.toString().contains('UNSETTLED_BALANCE')
                    ? 'Cannot delete group with unsettled balances among members!'
                    : 'Failed to delete group: $e',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asyncGroup = ref.watch(groupDetailProvider(widget.groupId));
    final dashboard = ref.watch(groupDashboardProvider(widget.groupId));
    final asyncSuggestions = ref.watch(offsetSuggestionsProvider(widget.groupId));

    return asyncGroup.when(
      loading: () => Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Center(child: Text('Error: $err', style: TextStyle(color: colors.accentOwe))),
      ),
      data: (group) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
              onPressed: () => context.pop(),
            ),
            title: Text(
              group.name,
              style: SplitUpTypography.title(color: colors.textPrimary),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.hub_outlined, color: colors.accentBrass, size: 24),
                tooltip: 'Settle Graph',
                onPressed: () => context.push('/groups/${group.id}/graph'),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: colors.textPrimary),
                color: colors.surfaceFlatRaised,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (val) {
                  if (val == 'view_members') {
                    _showMembersSheet(group);
                  } else if (val == 'rename') {
                    _showRenameDialog(group);
                  } else if (val == 'add_member') {
                    _showAddMemberDialog(group);
                  } else if (val == 'leave') {
                    _handleLeaveGroup(group);
                  } else if (val == 'delete') {
                    _handleDeleteGroup(group);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'view_members',
                    child: Row(
                      children: [
                        Icon(Icons.people_alt_outlined, size: 18, color: colors.textPrimary),
                        const SizedBox(width: 10),
                        Text('View Members', style: TextStyle(color: colors.textPrimary)),
                      ],
                    ),
                  ),
                  if (group.isAdmin) ...[
                    PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18, color: colors.textPrimary),
                          const SizedBox(width: 10),
                          Text('Rename Group', style: TextStyle(color: colors.textPrimary)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'add_member',
                      child: Row(
                        children: [
                          Icon(Icons.person_add_outlined, size: 18, color: colors.textPrimary),
                          const SizedBox(width: 10),
                          Text('Add Member', style: TextStyle(color: colors.textPrimary)),
                        ],
                      ),
                    ),
                  ],
                  PopupMenuItem(
                    value: 'leave',
                    child: Row(
                      children: [
                        Icon(Icons.exit_to_app_rounded, size: 18, color: colors.accentBrass),
                        const SizedBox(width: 10),
                        Text('Leave Group', style: TextStyle(color: colors.accentBrass)),
                      ],
                    ),
                  ),
                  if (group.isAdmin)
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18, color: colors.accentOwe),
                          const SizedBox(width: 10),
                          Text('Delete Group', style: TextStyle(color: colors.accentOwe)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: colors.accentReceive,
              labelColor: colors.textPrimary,
              unselectedLabelColor: colors.textMuted,
              labelStyle: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 14),
              tabs: const [
                Tab(text: 'Expenses'),
                Tab(text: 'Dashboard'),
                Tab(text: 'Settle'),
              ],
            ),
          ),
          body: AppBackground(
            child: SafeArea(
              bottom: false,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildExpensesTab(colors, group),
                  _buildDashboardTab(colors, group, dashboard),
                  _buildSettleTab(colors, group, asyncSuggestions),
                ],
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: colors.accentReceive,
            foregroundColor: Colors.black,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => AddExpenseScreen(
                    initialLedgerId: group.id,
                    initialMembers: group.members.map((m) {
                      final isMe = m.userId == 'usr_arhaam';
                      return {
                        'id': m.userId,
                        'name': isMe ? 'You' : m.name,
                        'isMe': isMe,
                      };
                    }).toList(),
                  ),
                ),
              );
            },
            child: const Icon(Icons.add_rounded, size: 28),
          ),
        );
      },
    );
  }

  Widget _buildExpensesTab(SplitUpColors colors, GroupModel group) {
    final asyncExpenses = ref.watch(expensesNotifierProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        GlassCard(
          strong: true,
          padding: const EdgeInsets.all(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR GROUP BALANCE',
                    style: SplitUpTypography.caption(color: colors.textMuted).copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  MoneyText(group.myNetPaise, variant: MoneyVariant.title, showSign: true),
                ],
              ),
              if (group.myNetPaise < 0)
                SettleButton(
                  amountPaise: group.myNetPaise.abs(),
                  onPressed: () => _tabController.animateTo(2),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Group Activity',
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        asyncExpenses.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          error: (err, _) => Text('Error loading expenses: $err', style: TextStyle(color: colors.accentOwe)),
          data: (expenses) {
            final groupExpenses = expenses.where((e) => e.ledgerId == group.id).toList();
            if (groupExpenses.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 48, color: colors.textMuted),
                    const SizedBox(height: 12),
                    Text('No expenses yet in this group', style: SplitUpTypography.title(color: colors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Tap + to record your first shared expense', style: SplitUpTypography.caption(color: colors.textMuted)),
                  ],
                ),
              );
            }

            return Column(
              children: groupExpenses.map((exp) {
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
                        child: Icon(Icons.restaurant_rounded, size: 20, color: colors.accentBrass),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(exp.title, style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15)),
                            const SizedBox(height: 2),
                            Text('Paid ₹${(exp.totalPaise / 100).toStringAsFixed(0)}', style: SplitUpTypography.caption(color: colors.textMuted)),
                          ],
                        ),
                      ),
                      MoneyText(exp.totalPaise, variant: MoneyVariant.body, colored: false),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildDashboardTab(SplitUpColors colors, GroupModel group, GroupDashboardData dashboard) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // Category Donut Chart
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spending by Category',
                style: SplitUpTypography.title(color: colors.textPrimary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 160,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 40,
                    sections: dashboard.categories.asMap().entries.map((entry) {
                      final i = entry.key;
                      final c = entry.value;
                      final chartColors = [colors.accentReceive, colors.accentBrass, colors.statusInfo, colors.accentOwe];
                      return PieChartSectionData(
                        value: c.percentage.toDouble(),
                        color: chartColors[i % chartColors.length],
                        title: '${c.category} (${c.percentage}%)',
                        titleStyle: SplitUpTypography.caption(color: Colors.white).copyWith(fontSize: 10),
                        radius: 36,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Member Spending & Share comparative bars
        Text(
          'Member Paid vs. Share',
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        ...dashboard.memberBars.map((m) {
          final net = m.paidPaise - m.sharePaise;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceFlat,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              children: [
                Avatar(name: m.name, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15)),
                      Text('Paid ${formatPaise(m.paidPaise)} · Share ${formatPaise(m.sharePaise)}',
                          style: SplitUpTypography.caption(color: colors.textMuted)),
                    ],
                  ),
                ),
                MoneyText(net, variant: MoneyVariant.body, showSign: true),
              ],
            ),
          );
        }),

        const SizedBox(height: 20),
        // Spending over time
        Text(
          'Spending Over Time',
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: dashboard.spendingOverTime.asMap().entries.map((e) {
                      return FlSpot(e.key.toDouble(), e.value.totalPaise / 100000.0);
                    }).toList(),
                    isCurved: true,
                    color: colors.accentReceive,
                    barWidth: 3,
                    belowBarData: BarAreaData(
                      show: true,
                      color: colors.accentReceive.withValues(alpha: 0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSettleTab(
    SplitUpColors colors,
    GroupModel group,
    AsyncValue<List<OffsetSuggestion>> asyncSuggestions,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // Offset Suggestion Banner (Group with Individual)
        asyncSuggestions.when(
          loading: () => const SizedBox.shrink(),
          error: (err, st) => const SizedBox.shrink(),
          data: (suggestions) {
            if (suggestions.isEmpty) return const SizedBox.shrink();
            final s = suggestions.first;
            return Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.accentBrass.withValues(alpha: 0.25),
                    colors.accentBrass.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.accentBrass.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.swap_horizontal_circle_rounded, color: colors.accentBrass, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Offset Available',
                        style: SplitUpTypography.title(color: colors.accentBrass).copyWith(fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${s.toUserName} owes you ${formatPaise(s.individualCreditPaise)} individually. You owe ${formatPaise(s.groupDebtPaise)} in this group.',
                    style: SplitUpTypography.body(color: colors.textPrimary).copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Offset ${formatPaise(s.maxOffsetPaise)}? Remaining ${formatPaise(s.remainingGroupDebtPaise)} settled normally.',
                    style: SplitUpTypography.caption(color: colors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.accentBrass,
                          foregroundColor: Colors.black,
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          'Offset ${formatPaise(s.maxOffsetPaise)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onPressed: () async {
                          try {
                            final offset = await ref.read(offsetsRepositoryProvider).createOffset(
                                  groupLedgerId: group.id,
                                  toUserId: s.toUserId,
                                  amountPaise: s.maxOffsetPaise,
                                );
                            // Auto-confirm for interactive testing
                            await ref.read(offsetsRepositoryProvider).confirmOffset(offset.id);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Offset of ${formatPaise(s.maxOffsetPaise)} confirmed! Both ledgers updated.'),
                                ),
                              );
                              // Refresh group
                              ref.invalidate(groupDetailProvider(group.id));
                              ref.invalidate(offsetSuggestionsProvider(group.id));
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Offset error: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),

        // Settle Graph CTA Card
        GlassCard(
          strong: true,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.hub_rounded, size: 48, color: colors.accentBrass),
              const SizedBox(height: 12),
              Text(
                'Settlement Node Graph',
                style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                'View simplified multi-party payments (at most N-1 transactions) or pairwise actual debts.',
                textAlign: TextAlign.center,
                style: SplitUpTypography.body(color: colors.textMuted).copyWith(fontSize: 13),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Open Settlement Graph',
                icon: Icons.hub_outlined,
                onPressed: () => context.push('/groups/${group.id}/graph'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Direct Settlement Options',
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),

        // Rahul Settlement Row: The user owes Rahul in this group
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceFlat,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Avatar(name: 'Rahul', size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pay Rahul Sharma', style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15)),
                    Text('Simplified debt: ₹1,200', style: SplitUpTypography.caption(color: colors.textMuted)),
                  ],
                ),
              ),
              // Rule: Settle button is shown ONLY for rows where user pays!
              SettleButton(
                amountPaise: 120000,
                compact: true,
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => SettleSheet(
                      friendId: 'usr_rahul',
                      friendName: 'Rahul Sharma',
                      ledgerId: group.id,
                      amountPaise: 120000,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Amit to Priya Row: Settle between two OTHER members (User does NOT pay)
        // Rule: NO Settle button here!
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceFlat,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Avatar(name: 'Amit', size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Amit owes Priya', style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15)),
                    Text('Simplified debt: ₹1,500', style: SplitUpTypography.caption(color: colors.textMuted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.surfaceFlatRaised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.divider),
                ),
                child: Text('Between Members', style: SplitUpTypography.caption(color: colors.textMuted)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}
