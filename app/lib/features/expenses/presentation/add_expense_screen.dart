import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../friends/data/friends_repository.dart';
import '../../friends/domain/friend_model.dart';
import '../data/expenses_repository.dart';
import '../domain/expense_model.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String? initialLedgerId;
  final String? friendId;

  const AddExpenseScreen({
    super.key,
    this.initialLedgerId,
    this.friendId,
  });

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _amountController = TextEditingController(text: '1200');
  final _titleController = TextEditingController(text: '');
  String _selectedCategory = 'food';
  String _splitType = 'EQUAL';
  String _payerUserId = 'usr_arhaam'; // Default: You paid
  final Set<String> _excludedUserIds = {};

  final categories = const [
    {'id': 'food', 'name': 'Food & Drinks', 'icon': Icons.restaurant_rounded},
    {'id': 'travel', 'name': 'Travel', 'icon': Icons.directions_car_rounded},
    {'id': 'stay', 'name': 'Stay', 'icon': Icons.hotel_rounded},
    {'id': 'tickets', 'name': 'Tickets', 'icon': Icons.confirmation_number_rounded},
    {'id': 'shopping', 'name': 'Shopping', 'icon': Icons.shopping_bag_rounded},
    {'id': 'other', 'name': 'Other', 'icon': Icons.receipt_long_rounded},
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asyncFriends = ref.watch(friendsNotifierProvider);

    // Resolve members
    FriendModel? targetFriend;
    if (widget.friendId != null) {
      targetFriend = asyncFriends.maybeWhen(
        data: (list) {
          final matches = list.where((f) => f.id == widget.friendId);
          return matches.isEmpty ? null : matches.first;
        },
        orElse: () => null,
      );
    }

    final List<Map<String, dynamic>> members = [
      {'id': 'usr_arhaam', 'name': 'You', 'isMe': true},
      if (targetFriend != null)
        {'id': targetFriend.id, 'name': targetFriend.resolvedName, 'isMe': false}
      else ...[
        {'id': 'usr_rahul', 'name': 'Rahul', 'isMe': false},
        {'id': 'usr_priya', 'name': 'Priya', 'isMe': false},
      ],
    ];

    final int totalPaise = MoneyUtils.parseToPaise(_amountController.text) ?? 0;
    final includedMembers = members.where((m) => !_excludedUserIds.contains(m['id'])).toList();
    final int sharePaise = includedMembers.isNotEmpty ? (totalPaise ~/ includedMembers.length) : 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: colors.textPrimary, size: 24),
          onPressed: () => context.pop(),
        ),
        title: Text(
          targetFriend != null ? 'Add Expense with ${targetFriend.resolvedName}' : 'Add Expense',
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              // Amount Input Hero
              Center(
                child: AmountInput(
                  controller: _amountController,
                  onChanged: (val) => setState(() {}),
                ),
              ),
              const SizedBox(height: 20),

              // Title Input
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _titleController,
                  style: SplitUpTypography.title(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'What was this for? (e.g. Dinner, Cab)',
                    hintStyle: SplitUpTypography.title(color: colors.textMuted),
                    border: InputBorder.none,
                    icon: Icon(Icons.edit_note_rounded, color: colors.accentBrass),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Categories
              Text(
                'Category',
                style: SplitUpTypography.label(color: colors.textMuted),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isSelected = cat['id'] == _selectedCategory;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedCategory = cat['id'] as String),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? colors.glassFillStrong : colors.surfaceFlat,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? colors.accentReceive : colors.divider,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              cat['icon'] as IconData,
                              size: 16,
                              color: isSelected ? colors.accentReceive : colors.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              cat['name'] as String,
                              style: SplitUpTypography.label(
                                color: isSelected ? colors.textPrimary : colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Paid By Selector
              Text(
                'Paid By',
                style: SplitUpTypography.label(color: colors.textMuted),
              ),
              const SizedBox(height: 10),
              SegmentedControl<String>(
                values: members.map((m) => m['id'] as String).toList(),
                labels: members.map((m) => m['name'] as String).toList(),
                selected: _payerUserId,
                onSelected: (val) => setState(() => _payerUserId = val),
              ),
              const SizedBox(height: 24),

              // Split Type Selector
              Text(
                'Split Method',
                style: SplitUpTypography.label(color: colors.textMuted),
              ),
              const SizedBox(height: 10),
              SegmentedControl<String>(
                values: const ['EQUAL', 'EXACT', 'PERCENT', 'SHARES'],
                labels: const ['Equal', 'Exact', 'Percent', 'Shares'],
                selected: _splitType,
                onSelected: (val) => setState(() => _splitType = val),
              ),
              const SizedBox(height: 24),

              // Participants & "Not there" exclusions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Split Between (${includedMembers.length})',
                    style: SplitUpTypography.title(color: colors.textPrimary),
                  ),
                  Text(
                    'Per person: ${formatPaise(sharePaise)}',
                    style: SplitUpTypography.label(color: colors.accentReceive),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              ...members.map((member) {
                final String memId = member['id'] as String;
                final String memName = member['name'] as String;
                final isExcluded = _excludedUserIds.contains(memId);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.surfaceFlat,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Row(
                    children: [
                      Avatar(name: memName, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              memName,
                              style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 14),
                            ),
                            Text(
                              isExcluded ? 'Not there (Excluded)' : 'Share: ${formatPaise(sharePaise)}',
                              style: SplitUpTypography.caption(
                                color: isExcluded ? colors.accentOwe : colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        activeTrackColor: colors.accentReceive,
                        inactiveThumbColor: colors.textMuted,
                        value: !isExcluded,
                        onChanged: (included) {
                          setState(() {
                            if (included) {
                              _excludedUserIds.remove(memId);
                            } else {
                              _excludedUserIds.add(memId);
                            }
                          });
                        },
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Save Expense (${formatPaise(totalPaise)})',
                icon: Icons.check_rounded,
                onPressed: totalPaise > 0
                    ? () async {
                        final title = _titleController.text.trim().isEmpty ? 'Expense' : _titleController.text.trim();
                        final ledgerId = widget.initialLedgerId ?? targetFriend?.individualLedgerId ?? 'ldg_default';

                        final payers = [ExpensePayer(userId: _payerUserId, paidPaise: totalPaise)];
                        final splits = members.map((m) {
                          final memId = m['id'] as String;
                          final included = !_excludedUserIds.contains(memId);
                          return ExpenseSplit(
                            userId: memId,
                            owedPaise: included ? sharePaise : 0,
                            included: included,
                          );
                        }).toList();

                        await ref.read(expensesNotifierProvider.notifier).createExpense(
                              ledgerId: ledgerId,
                              title: title,
                              totalPaise: totalPaise,
                              category: _selectedCategory,
                              splitType: _splitType,
                              payers: payers,
                              splits: splits,
                              friendId: targetFriend?.id,
                            );

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: colors.surfaceFlatRaised,
                              content: Text(
                                'Expense added successfully!',
                                style: SplitUpTypography.body(color: colors.textPrimary),
                              ),
                            ),
                          );
                          context.pop();
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
