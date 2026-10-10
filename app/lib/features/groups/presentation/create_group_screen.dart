import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../friends/data/friends_repository.dart';
import '../data/groups_repository.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final Set<String> _selectedFriendIds = {};
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(groupsNotifierProvider.notifier).createGroup(
            name: name,
            memberUserIds: _selectedFriendIds.toList(),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Group "$name" created successfully!')),
        );
        context.pop();
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $err')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asyncFriends = ref.watch(friendsNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Create Group',
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              // Group Photo & Name Input
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: colors.surfaceFlatRaised,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.glassBorder, width: 1.5),
                  ),
                  child: Icon(Icons.camera_alt_outlined, color: colors.accentBrass, size: 30),
                ),
              ),
              const SizedBox(height: 18),
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _nameController,
                  style: SplitUpTypography.title(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Group Name (e.g. Weekend Trips)',
                    hintStyle: SplitUpTypography.title(color: colors.textMuted),
                    border: InputBorder.none,
                    icon: Icon(Icons.group_outlined, color: colors.accentBrass),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Select Members (${_selectedFriendIds.length + 1})',
                style: SplitUpTypography.title(color: colors.textPrimary),
              ),
              const SizedBox(height: 12),

              // Current User (Creator / Admin)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceFlat,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.divider),
                ),
                child: Row(
                  children: [
                    const Avatar(name: 'Arhaam', size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Arhaam (You)',
                            style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                          ),
                          Text(
                            'Group Admin',
                            style: SplitUpTypography.caption(color: colors.accentBrass),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.check_circle_rounded, color: colors.accentReceive, size: 22),
                  ],
                ),
              ),

              // Friends list with checkmarks
              asyncFriends.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error loading friends: $err', style: TextStyle(color: colors.accentOwe)),
                ),
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
                          border: Border.all(color: colors.divider),
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
                              Avatar(name: f.resolvedName, size: 40, isPlaceholder: !f.isAppUser),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      f.resolvedName,
                                      style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                                    ),
                                    Text(
                                      f.phoneE164,
                                      style: SplitUpTypography.caption(color: colors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                color: isSelected ? colors.accentReceive : colors.textMuted,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 24),
              PrimaryButton(
                label: _isSubmitting ? 'Creating...' : 'Create Group',
                onPressed: _isSubmitting ? () {} : _handleCreateGroup,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
