import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../friends/data/friends_repository.dart';
import '../../groups/data/groups_repository.dart';
import '../data/trips_repository.dart';

class CreateTripScreen extends ConsumerStatefulWidget {
  const CreateTripScreen({super.key});

  @override
  ConsumerState<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends ConsumerState<CreateTripScreen> {
  final _nameController = TextEditingController();
  final _budgetController = TextEditingController(text: '50000');
  final Set<String> _selectedFriendIds = {
    MockDataRepository.userRahul.id,
    MockDataRepository.userPriya.id,
    MockDataRepository.userSneha.id,
  };

  DateTime? _startDate = DateTime.now().add(const Duration(days: 2));
  DateTime? _endDate = DateTime.now().add(const Duration(days: 6));
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final initialDate = isStart
        ? (_startDate ?? now)
        : (_endDate ?? (_startDate ?? now).add(const Duration(days: 4)));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = _startDate!.add(const Duration(days: 1));
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  String _formatDateDisplay(DateTime? dt) {
    if (dt == null) return 'Select';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String? _formatIso(DateTime? dt) {
    if (dt == null) return null;
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _submitTrip() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a trip name')),
      );
      return;
    }

    final budgetRupees = int.tryParse(_budgetController.text.trim()) ?? 0;
    if (budgetRupees <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid budget in ₹')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final budgetPaise = budgetRupees * 100;
      await ref.read(tripsNotifierProvider.notifier).createTrip(
            name: name,
            budgetPaise: budgetPaise,
            startDate: _formatIso(_startDate),
            endDate: _formatIso(_endDate),
            memberUserIds: _selectedFriendIds.toList(),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.colors.surfaceFlatRaised,
            content: Text(
              'Trip "$name" created successfully!',
              style: SplitUpTypography.body(color: context.colors.textPrimary),
            ),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create trip: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asyncFriends = ref.watch(friendsNotifierProvider);
    final asyncGroups = ref.watch(groupsNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Create Trip',
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              // Trip Icon & Name
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: colors.accentBrass.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.glassBorder, width: 1.5),
                  ),
                  child: Icon(Icons.beach_access_rounded, color: colors.accentBrass, size: 34),
                ),
              ),
              const SizedBox(height: 18),
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _nameController,
                  style: SplitUpTypography.title(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Trip Name (e.g. Manali Expedition)',
                    hintStyle: SplitUpTypography.title(color: colors.textMuted),
                    border: InputBorder.none,
                    icon: Icon(Icons.flight_takeoff_rounded, color: colors.accentBrass),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Total Budget Input
              Text(
                'Trip Budget (INR)',
                style: SplitUpTypography.label(color: colors.textMuted),
              ),
              const SizedBox(height: 8),
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _budgetController,
                  keyboardType: TextInputType.number,
                  style: SplitUpTypography.titleAmount(color: colors.textPrimary).copyWith(fontSize: 22),
                  decoration: InputDecoration(
                    hintText: '50000',
                    prefixText: '₹ ',
                    prefixStyle: SplitUpTypography.titleAmount(color: colors.accentBrass).copyWith(fontSize: 22),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Trip Dates Row
              Text(
                'Trip Dates (Optional)',
                style: SplitUpTypography.label(color: colors.textMuted),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(true),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: colors.surfaceFlat,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colors.divider),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 16, color: colors.accentBrass),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Start Date', style: SplitUpTypography.caption(color: colors.textMuted)),
                                  Text(
                                    _formatDateDisplay(_startDate),
                                    style: SplitUpTypography.body(color: colors.textPrimary).copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(false),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: colors.surfaceFlat,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colors.divider),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.event_available_rounded, size: 16, color: colors.accentBrass),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('End Date', style: SplitUpTypography.caption(color: colors.textMuted)),
                                  Text(
                                    _formatDateDisplay(_endDate),
                                    style: SplitUpTypography.body(color: colors.textPrimary).copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // "Add all members of an existing group" (copies members, no live link)
              asyncGroups.when(
                data: (groups) {
                  if (groups.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Copy Members from Group (Snapshot)',
                        style: SplitUpTypography.label(color: colors.textMuted),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: groups.map((g) {
                          return ActionChip(
                            avatar: Icon(Icons.group_add_rounded, size: 16, color: colors.accentBrass),
                            label: Text('Add "${g.name}" members (${g.members.length})'),
                            backgroundColor: colors.surfaceFlat,
                            side: BorderSide(color: colors.divider),
                            labelStyle: SplitUpTypography.caption(color: colors.textPrimary),
                            onPressed: () {
                              setState(() {
                                for (final m in g.members) {
                                  if (m.userId != MockDataRepository.currentUser.id) {
                                    _selectedFriendIds.add(m.userId);
                                  }
                                }
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  duration: const Duration(seconds: 2),
                                  content: Text('Copied ${g.members.length} members from "${g.name}" (no live link)'),
                                ),
                              );
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (e, st) => const SizedBox.shrink(),
              ),

              Text(
                'Trip Members (${_selectedFriendIds.length + 1})',
                style: SplitUpTypography.title(color: colors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'Non-app members will receive an SMS invite. App users will receive an in-app notification.',
                style: SplitUpTypography.caption(color: colors.textMuted),
              ),
              const SizedBox(height: 12),

              // Creator Card (You)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceFlat,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.accentReceive.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Avatar(name: 'Arhaam', size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('You (Organizer)', style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 14)),
                          Text('Trip Creator · Admin', style: SplitUpTypography.caption(color: colors.accentReceive)),
                        ],
                      ),
                    ),
                    Icon(Icons.check_circle_rounded, color: colors.accentReceive, size: 20),
                  ],
                ),
              ),

              // Friends list
              asyncFriends.when(
                data: (friends) {
                  return Column(
                    children: friends.map((f) {
                      final isSelected = _selectedFriendIds.contains(f.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.surfaceFlat,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isSelected ? colors.accentReceive.withValues(alpha: 0.3) : colors.divider),
                        ),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedFriendIds.remove(f.id);
                              } else {
                                _selectedFriendIds.add(f.id);
                              }
                            });
                          },
                          child: Row(
                            children: [
                              Avatar(name: f.resolvedName, size: 36),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      f.resolvedName,
                                      style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 14),
                                    ),
                                    Text(
                                      !f.isAppUser ? 'Non-app member (SMS invite)' : 'SplitUp user',
                                      style: SplitUpTypography.caption(
                                        color: !f.isAppUser ? colors.accentBrass : colors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Checkbox(
                                activeColor: colors.accentReceive,
                                value: isSelected,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedFriendIds.add(f.id);
                                    } else {
                                      _selectedFriendIds.remove(f.id);
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error loading friends: $e', style: SplitUpTypography.caption(color: colors.accentOwe)),
              ),

              const SizedBox(height: 24),
              PrimaryButton(
                label: _isLoading ? 'Creating Trip...' : 'Create Trip',
                icon: Icons.check_circle_outline,
                onPressed: _isLoading ? null : _submitTrip,
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }
}
