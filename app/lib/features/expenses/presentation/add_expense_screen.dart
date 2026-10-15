import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/money/paise.dart';
import '../../../core/names/display_name.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../friends/data/friends_repository.dart';
import '../../friends/domain/friend_model.dart';
import '../../groups/data/groups_repository.dart';
import '../../groups/domain/group_model.dart';
import '../../trips/data/trips_repository.dart';
import '../../trips/domain/trip_model.dart';
import '../data/expenses_repository.dart';
import '../domain/expense_model.dart';
import '../../../core/auth/auth_provider.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String? initialLedgerId;
  final String? friendId;
  final List<String>? friendIds;
  final List<Map<String, dynamic>>? initialMembers;
  final ExpenseModel? existingExpense;

  const AddExpenseScreen({
    super.key,
    this.initialLedgerId,
    this.friendId,
    this.friendIds,
    this.initialMembers,
    this.existingExpense,
  });

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  late final TextEditingController _amountController;
  late final TextEditingController _titleController;
  String _selectedCategory = 'food';
  String _splitType = 'EQUAL';
  String _payerUserId = 'usr_arhaam'; // Default: You paid
  final Set<String> _excludedUserIds = {};
  bool _isSaving = false;

  // Multiple payers state
  bool _isMultiplePayers = false;
  final Map<String, int> _payerAmounts = {};
  final Map<String, TextEditingController> _payerControllers = {};

  final categories = const [
    {'id': 'food', 'name': 'Food & Drinks', 'icon': Icons.restaurant_rounded},
    {'id': 'travel', 'name': 'Travel', 'icon': Icons.directions_car_rounded},
    {'id': 'stay', 'name': 'Stay', 'icon': Icons.hotel_rounded},
    {'id': 'tickets', 'name': 'Tickets', 'icon': Icons.confirmation_number_rounded},
    {'id': 'shopping', 'name': 'Shopping', 'icon': Icons.shopping_bag_rounded},
    {'id': 'other', 'name': 'Other', 'icon': Icons.receipt_long_rounded},
  ];

  @override
  void initState() {
    super.initState();
    final exp = widget.existingExpense;
    if (exp != null) {
      final amtRupees = exp.totalPaise % 100 == 0
          ? (exp.totalPaise ~/ 100).toString()
          : (exp.totalPaise / 100).toStringAsFixed(2);
      _amountController = TextEditingController(text: amtRupees);
      _titleController = TextEditingController(text: exp.title);
      _selectedCategory = exp.category;
      _splitType = exp.splitType;
      for (final s in exp.splits) {
        if (!s.included) {
          _excludedUserIds.add(s.userId);
        }
      }
      if (exp.payers.length > 1) {
        _isMultiplePayers = true;
        for (final p in exp.payers) {
          _payerAmounts[p.userId] = p.paidPaise;
          _syncPayerController(p.userId, p.paidPaise);
        }
      } else if (exp.payers.isNotEmpty) {
        _isMultiplePayers = false;
        _payerUserId = exp.payers.first.userId;
        _payerAmounts[_payerUserId] = exp.payers.first.paidPaise;
        _syncPayerController(_payerUserId, exp.payers.first.paidPaise);
      }
    } else {
      _amountController = TextEditingController(text: '1200');
      _titleController = TextEditingController(text: '');
      final myUserId = ref.read(authNotifierProvider).user?.id ?? 'usr_arhaam';
      _payerUserId = myUserId;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _titleController.dispose();
    for (final c in _payerControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getPayerController(String userId, int initialPaise) {
    if (!_payerControllers.containsKey(userId)) {
      final text = initialPaise == 0
          ? ''
          : (initialPaise % 100 == 0
              ? (initialPaise ~/ 100).toString()
              : (initialPaise / 100).toStringAsFixed(2));
      _payerControllers[userId] = TextEditingController(text: text);
    }
    return _payerControllers[userId]!;
  }

  void _syncPayerController(String userId, int paise) {
    final text = paise == 0
        ? ''
        : (paise % 100 == 0
            ? (paise ~/ 100).toString()
            : (paise / 100).toStringAsFixed(2));
    if (!_payerControllers.containsKey(userId)) {
      _payerControllers[userId] = TextEditingController(text: text);
    } else {
      if (_payerControllers[userId]!.text != text) {
        _payerControllers[userId]!.text = text;
      }
    }
  }

  void _splitEquallyAmongPayers(int totalPaise, List<String> activeIds) {
    if (activeIds.isEmpty || totalPaise <= 0) return;
    // Deterministic sorting by userId
    final sortedIds = List<String>.from(activeIds)..sort((a, b) => a.compareTo(b));
    final n = sortedIds.length;
    final basePaise = totalPaise ~/ n;
    final leftoverPaise = totalPaise % n;

    setState(() {
      for (int i = 0; i < sortedIds.length; i++) {
        final uid = sortedIds[i];
        final amt = basePaise + (i < leftoverPaise ? 1 : 0);
        _payerAmounts[uid] = amt;
        _syncPayerController(uid, amt);
      }
    });
  }

  void _fillRemainingForPayer(String userId, int totalPaise) {
    final otherSum = _payerAmounts.entries
        .where((e) => e.key != userId && !_excludedUserIds.contains(e.key))
        .fold(0, (sum, e) => sum + e.value);
    final remaining = totalPaise - otherSum;
    final targetAmt = remaining > 0 ? remaining : 0;
    setState(() {
      _payerAmounts[userId] = targetAmt;
      _syncPayerController(userId, targetAmt);
    });
  }

  String _formatPayersSummaryText(List<Map<String, dynamic>> members) {
    if (!_isMultiplePayers) {
      final payer = members.firstWhere(
        (m) => m['id'] == _payerUserId,
        orElse: () => {'name': 'You'},
      );
      return payer['name'] as String;
    }
    final activePayers = _payerAmounts.entries
        .where((e) => e.value > 0 && !_excludedUserIds.contains(e.key))
        .toList();
    if (activePayers.isEmpty) return 'No payers selected';
    return activePayers.map((e) {
      final m = members.firstWhere(
        (mem) => mem['id'] == e.key,
        orElse: () => {'name': e.key},
      );
      return '${m['name']} ${formatPaise(e.value)}';
    }).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asyncFriends = ref.watch(friendsNotifierProvider);
    final asyncGroups = ref.watch(groupsNotifierProvider);
    final asyncTrips = ref.watch(tripsNotifierProvider);

    // 1. Check if ledger matches a group
    GroupModel? matchedGroup;
    if (widget.initialLedgerId != null) {
      matchedGroup = asyncGroups.maybeWhen(
        data: (groups) {
          final matches = groups.where((g) => g.id == widget.initialLedgerId);
          return matches.isEmpty ? null : matches.first;
        },
        orElse: () => null,
      );
    }

    // 2. Check if ledger matches a trip
    TripModel? matchedTrip;
    if (widget.initialLedgerId != null && matchedGroup == null) {
      matchedTrip = asyncTrips.maybeWhen(
        data: (trips) {
          final matches = trips.where((t) => t.id == widget.initialLedgerId);
          return matches.isEmpty ? null : matches.first;
        },
        orElse: () => null,
      );
    }

    // 3. Resolve single friend
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

    // 4. Resolve multi-selected friends
    final List<FriendModel> selectedFriends = [];
    if (widget.friendIds != null && widget.friendIds!.isNotEmpty) {
      asyncFriends.whenData((friends) {
        for (final id in widget.friendIds!) {
          final found = friends.where((f) => f.id == id);
          if (found.isNotEmpty) selectedFriends.add(found.first);
        }
      });
    }

    // 5. Construct member list based on context
    final myUserId = ref.watch(authNotifierProvider).user?.id ?? 'usr_arhaam';
    List<Map<String, dynamic>> members = [];
    String screenTitle = widget.existingExpense != null ? 'Edit Expense' : 'Add Expense';

    if (widget.initialMembers != null && widget.initialMembers!.isNotEmpty) {
      members = List<Map<String, dynamic>>.from(widget.initialMembers!);
      if (widget.existingExpense == null) {
        if (matchedGroup != null) {
          screenTitle = 'Add Expense • ${matchedGroup.name}';
        } else if (matchedTrip != null) {
          screenTitle = 'Add Expense • ${matchedTrip.name}';
        }
      }
    } else if (matchedGroup != null) {
      if (widget.existingExpense == null) {
        screenTitle = 'Add Expense • ${matchedGroup.name}';
      }
      members = matchedGroup.members.map((m) {
        final isMe = m.userId == myUserId || m.userId == 'usr_arhaam';
        return {
          'id': m.userId,
          'name': isMe ? 'You' : displayNameFor(profileName: m.name),
          'isMe': isMe,
        };
      }).toList();
    } else if (matchedTrip != null) {
      if (widget.existingExpense == null) {
        screenTitle = 'Add Expense • ${matchedTrip.name}';
      }
      members = matchedTrip.members.map((m) {
        final isMe = m.userId == myUserId || m.userId == 'usr_arhaam';
        return {
          'id': m.userId,
          'name': isMe ? 'You' : displayNameFor(profileName: m.name),
          'isMe': isMe,
        };
      }).toList();
    } else if (selectedFriends.isNotEmpty) {
      if (widget.existingExpense == null) {
        screenTitle = 'Add Expense with ${selectedFriends.length} ${selectedFriends.length == 1 ? 'friend' : 'friends'}';
      }
      members = [
        {'id': myUserId, 'name': 'You', 'isMe': true},
        ...selectedFriends.map((f) => {
              'id': f.id,
              'name': displayNameFor(
                nickname: f.nickname,
                contactName: f.contactName,
                profileName: f.name,
              ),
              'isMe': false,
            }),
      ];
    } else if (targetFriend != null) {
      final fName = displayNameFor(
        nickname: targetFriend.nickname,
        contactName: targetFriend.contactName,
        profileName: targetFriend.name,
      );
      if (widget.existingExpense == null) {
        screenTitle = 'Add Expense with $fName';
      }
      members = [
        {'id': myUserId, 'name': 'You', 'isMe': true},
        {'id': targetFriend.id, 'name': fName, 'isMe': false},
      ];
    } else {
      final allFriends = asyncFriends.maybeWhen(
        data: (list) => list,
        orElse: () => <FriendModel>[],
      );
      members = [
        {'id': myUserId, 'name': 'You', 'isMe': true},
        ...allFriends.take(3).map((f) => {
              'id': f.id,
              'name': displayNameFor(
                nickname: f.nickname,
                contactName: f.contactName,
                profileName: f.name,
              ),
              'isMe': false,
            }),
      ];
    }

    // Ensure payer is a valid member in single-payer mode
    if (!_isMultiplePayers && !members.any((m) => m['id'] == _payerUserId)) {
      if (members.any((m) => m['id'] == myUserId)) {
        _payerUserId = myUserId;
      } else if (members.isNotEmpty) {
        _payerUserId = members.first['id'] as String;
      }
    }

    final int totalPaise = MoneyUtils.parseToPaise(_amountController.text) ?? 0;
    final includedMembers = members.where((m) => !_excludedUserIds.contains(m['id'])).toList();
    final int sharePaise = includedMembers.isNotEmpty ? (totalPaise ~/ includedMembers.length) : 0;

    // Eligible payers: members who are not marked "Not there"
    final eligiblePayers = members.where((m) => !_excludedUserIds.contains(m['id'])).toList();

    // Multi-payer calculation
    final int sumPaid = _isMultiplePayers
        ? _payerAmounts.entries
            .where((e) => eligiblePayers.any((m) => m['id'] == e.key))
            .fold(0, (sum, e) => sum + e.value)
        : totalPaise;
    final int payerDifference = totalPaise - sumPaid;
    final bool isPayerSumValid = !_isMultiplePayers || (sumPaid == totalPaise && sumPaid > 0);
    final bool canSave = totalPaise > 0 && isPayerSumValid && includedMembers.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: colors.textPrimary, size: 24),
          onPressed: () => context.pop(),
        ),
        title: Text(
          screenTitle,
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
                  onChanged: (val) {
                    final newTotal = MoneyUtils.parseToPaise(val) ?? 0;
                    if (!_isMultiplePayers && _payerUserId.isNotEmpty) {
                      _payerAmounts[_payerUserId] = newTotal;
                    }
                    setState(() {});
                  },
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

              // Paid By Header with Split Payers Button (Stitch S20 design)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Paid By',
                    style: SplitUpTypography.label(color: colors.textMuted),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        _isMultiplePayers = !_isMultiplePayers;
                        if (_isMultiplePayers) {
                          // Initialize multi-payer amounts if empty or unallocated
                          if (_payerAmounts.isEmpty || _payerAmounts.values.fold(0, (a, b) => a + b) != totalPaise) {
                            _payerAmounts.clear();
                            final defaultPayer = !_excludedUserIds.contains(_payerUserId)
                                ? _payerUserId
                                : (eligiblePayers.isNotEmpty ? eligiblePayers.first['id'] as String : 'usr_arhaam');
                            _payerAmounts[defaultPayer] = totalPaise;
                            _syncPayerController(defaultPayer, totalPaise);
                          }
                        } else {
                          // Reverting to single payer
                          if (_payerAmounts.isNotEmpty) {
                            final highest = _payerAmounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
                            _payerUserId = highest;
                          }
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isMultiplePayers ? 'Single payer' : 'Split payers',
                            style: SplitUpTypography.label(color: colors.accentBrass).copyWith(fontSize: 13),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _isMultiplePayers ? Icons.person_outline_rounded : Icons.tune_rounded,
                            size: 16,
                            color: colors.accentBrass,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Single Payer Mode vs Multi-Payer Mode
              if (!_isMultiplePayers) ...[
                SegmentedControl<String>(
                  values: members.map((m) => m['id'] as String).toList(),
                  labels: members.map((m) => m['name'] as String).toList(),
                  selected: _payerUserId,
                  onSelected: (val) {
                    setState(() {
                      _payerUserId = val;
                      _payerAmounts.clear();
                      _payerAmounts[val] = totalPaise;
                    });
                  },
                ),
              ] else ...[
                // Multi-Payer Editor Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surfaceFlat,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isPayerSumValid ? colors.accentReceive.withValues(alpha: 0.4) : colors.divider,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Live Status Header
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Paid ${formatPaise(sumPaid)} of ${formatPaise(totalPaise)}',
                              style: SplitUpTypography.caption(color: colors.textPrimary).copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (payerDifference == 0 && sumPaid > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded, size: 14, color: colors.accentReceive),
                                const SizedBox(width: 4),
                                Text(
                                  'Matches total',
                                  style: SplitUpTypography.caption(color: colors.accentReceive).copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            )
                          else if (payerDifference > 0)
                            Text(
                              '${formatPaise(payerDifference)} left',
                              style: SplitUpTypography.caption(color: colors.accentBrass).copyWith(fontWeight: FontWeight.bold),
                            )
                          else
                            Text(
                              '${formatPaise(-payerDifference)} extra',
                              style: SplitUpTypography.caption(color: colors.accentOwe).copyWith(fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Collapsed Summary Line
                      Text(
                        'Payers: ${_formatPayersSummaryText(members)}',
                        style: SplitUpTypography.caption(color: colors.textMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Divider(height: 20),

                      // Helper Action: Split Equally Among Payers
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.accentBrass,
                              side: BorderSide(color: colors.accentBrass.withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.call_split_rounded, size: 14),
                            label: const Text('Split equally among payers', style: TextStyle(fontSize: 12)),
                            onPressed: totalPaise > 0
                                ? () {
                                    // Use active payers if > 1 selected, or default to all eligible
                                    final active = eligiblePayers
                                        .map((m) => m['id'] as String)
                                        .where((id) => (_payerAmounts[id] ?? 0) > 0)
                                        .toList();
                                    final targetIds = active.length > 1
                                        ? active
                                        : eligiblePayers.map((m) => m['id'] as String).toList();
                                    _splitEquallyAmongPayers(totalPaise, targetIds);
                                  }
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Member Rows with Amount Inputs & Fill Remainder
                      ...eligiblePayers.map((m) {
                        final memId = m['id'] as String;
                        final memName = m['name'] as String;
                        final isPayer = (_payerAmounts[memId] ?? 0) > 0 || _payerAmounts.containsKey(memId);
                        final payerAmt = _payerAmounts[memId] ?? 0;
                        final controller = _getPayerController(memId, payerAmt);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: colors.glassFill,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isPayer ? colors.accentReceive.withValues(alpha: 0.3) : colors.divider,
                            ),
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: isPayer,
                                activeColor: colors.accentReceive,
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      // If someone is newly checked, fill with remainder or 0
                                      final otherSum = _payerAmounts.entries
                                          .where((e) => e.key != memId && !_excludedUserIds.contains(e.key))
                                          .fold(0, (sum, e) => sum + e.value);
                                      final rem = totalPaise - otherSum;
                                      final assign = rem > 0 ? rem : 0;
                                      _payerAmounts[memId] = assign;
                                      _syncPayerController(memId, assign);
                                    } else {
                                      _payerAmounts.remove(memId);
                                      _payerControllers[memId]?.clear();
                                    }
                                  });
                                },
                              ),
                              Avatar(name: memName, size: 28),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  memName,
                                  style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isPayer) ...[
                                if (payerDifference > 0 && payerAmt != payerDifference)
                                  InkWell(
                                    onTap: () => _fillRemainingForPayer(memId, totalPaise),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      child: Text(
                                        'Fill rest',
                                        style: SplitUpTypography.caption(color: colors.accentBrass)
                                            .copyWith(fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 90,
                                  height: 36,
                                  child: TextField(
                                    controller: controller,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    textAlign: TextAlign.right,
                                    style: SplitUpTypography.body(color: colors.textPrimary).copyWith(fontSize: 13),
                                    decoration: InputDecoration(
                                      prefixText: '₹',
                                      prefixStyle: SplitUpTypography.caption(color: colors.textMuted),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      filled: true,
                                      fillColor: colors.surfaceFlatRaised,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: colors.divider),
                                      ),
                                      isDense: true,
                                    ),
                                    onChanged: (val) {
                                      final parsed = MoneyUtils.parseToPaise(val) ?? 0;
                                      setState(() {
                                        _payerAmounts[memId] = parsed;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
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
                  Expanded(
                    child: Text(
                      'Split Between (${includedMembers.length})',
                      style: SplitUpTypography.title(color: colors.textPrimary),
                    ),
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
                              // If this member was a payer, remove them from payers and inform the user
                              if (_isMultiplePayers && _payerAmounts.containsKey(memId)) {
                                _payerAmounts.remove(memId);
                                _payerControllers[memId]?.clear();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Removed $memName from payers because they are marked "Not there"'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              } else if (!_isMultiplePayers && _payerUserId == memId) {
                                final replacement = members.firstWhere(
                                  (m) => !_excludedUserIds.contains(m['id']),
                                  orElse: () => {'id': myUserId, 'name': 'You'},
                                );
                                _payerUserId = replacement['id'] as String;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Switched payer from $memName because they are marked "Not there"'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          });
                        },
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 24),

              if (_isMultiplePayers && !isPayerSumValid && totalPaise > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Payer amounts total (${formatPaise(sumPaid)}) must match expense total (${formatPaise(totalPaise)})',
                    style: SplitUpTypography.caption(color: colors.accentOwe).copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),

              PrimaryButton(
                label: _isSaving
                    ? 'Saving...'
                    : (widget.existingExpense != null
                        ? 'Update Expense (${formatPaise(totalPaise)})'
                        : 'Save Expense (${formatPaise(totalPaise)})'),
                icon: Icons.check_rounded,
                onPressed: (canSave && !_isSaving)
                    ? () async {
                        final title = _titleController.text.trim().isEmpty ? 'Expense' : _titleController.text.trim();

                        final String? resolvedLedgerId = widget.existingExpense?.ledgerId ??
                            widget.initialLedgerId ??
                            targetFriend?.individualLedgerId ??
                            (selectedFriends.length == 1 ? selectedFriends.first.individualLedgerId : null);

                        if (resolvedLedgerId == null || resolvedLedgerId.isEmpty) {
                          if (selectedFriends.length > 1) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: colors.accentOwe,
                                content: Text(
                                  'Splitting an expense with multiple friends requires creating a Group. Please create a group first or select a single friend.',
                                  style: SplitUpTypography.body(color: Colors.white),
                                ),
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: colors.accentOwe,
                                content: Text(
                                  'Please select a friend or group before saving this expense.',
                                  style: SplitUpTypography.body(color: Colors.white),
                                ),
                              ),
                            );
                          }
                          return;
                        }

                        final List<ExpensePayer> payers = _isMultiplePayers
                            ? _payerAmounts.entries
                                .where((e) => e.value > 0 && !_excludedUserIds.contains(e.key))
                                .map((e) => ExpensePayer(userId: e.key, paidPaise: e.value))
                                .toList()
                            : [ExpensePayer(userId: _payerUserId, paidPaise: totalPaise)];

                        final splits = members.map((m) {
                          final memId = m['id'] as String;
                          final included = !_excludedUserIds.contains(memId);
                          return ExpenseSplit(
                            userId: memId,
                            owedPaise: included ? sharePaise : 0,
                            included: included,
                          );
                        }).toList();

                        setState(() => _isSaving = true);

                        try {
                          if (widget.existingExpense != null) {
                            await ref.read(expensesNotifierProvider.notifier).editExpense(
                                  widget.existingExpense!.id,
                                  title: title,
                                  totalPaise: totalPaise,
                                  category: _selectedCategory,
                                  splitType: _splitType,
                                  payers: payers,
                                  splits: splits,
                                  friendId: targetFriend?.id ?? (selectedFriends.length == 1 ? selectedFriends.first.id : null),
                                );
                          } else {
                            await ref.read(expensesNotifierProvider.notifier).createExpense(
                                  ledgerId: resolvedLedgerId,
                                  title: title,
                                  totalPaise: totalPaise,
                                  category: _selectedCategory,
                                  splitType: _splitType,
                                  payers: payers,
                                  splits: splits,
                                  friendId: targetFriend?.id ?? (selectedFriends.length == 1 ? selectedFriends.first.id : null),
                                );
                          }

                          if (matchedGroup != null) {
                            ref.invalidate(groupDetailProvider(matchedGroup.id));
                            ref.invalidate(groupDashboardProvider(matchedGroup.id));
                            ref.invalidate(groupsNotifierProvider);
                          }
                          if (matchedTrip != null) {
                            ref.invalidate(tripDetailProvider(matchedTrip.id));
                            ref.invalidate(tripDashboardProvider(matchedTrip.id));
                            ref.invalidate(tripsNotifierProvider);
                          }
                          ref.invalidate(friendsNotifierProvider);

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: colors.surfaceFlatRaised,
                                content: Text(
                                  widget.existingExpense != null
                                      ? 'Expense updated successfully!'
                                      : 'Expense added successfully!',
                                  style: SplitUpTypography.body(color: colors.textPrimary),
                                ),
                              ),
                            );
                            context.pop();
                          }
                        } catch (e) {
                          if (context.mounted) {
                            final rawMsg = e.toString().replaceAll('Exception: ', '').trim();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: colors.accentOwe,
                                content: Text(
                                  rawMsg.isNotEmpty
                                      ? rawMsg
                                      : "Couldn't save. Check your connection and try again.",
                                  style: SplitUpTypography.body(color: Colors.white),
                                ),
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isSaving = false);
                          }
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
