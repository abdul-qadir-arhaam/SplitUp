import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../data/friends_repository.dart';
import '../domain/friend_model.dart';

class SelectFriendsSheet extends ConsumerStatefulWidget {
  const SelectFriendsSheet({super.key});

  static Future<List<FriendModel>?> show(BuildContext context) {
    return showModalBottomSheet<List<FriendModel>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const SelectFriendsSheet(),
    );
  }

  @override
  ConsumerState<SelectFriendsSheet> createState() => _SelectFriendsSheetState();
}

class _SelectFriendsSheetState extends ConsumerState<SelectFriendsSheet> {
  final Set<String> _selectedFriendIds = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asyncFriends = ref.watch(friendsNotifierProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: colors.surfaceFlatRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Friends',
                      style: SplitUpTypography.title(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Who is part of this expense?',
                      style: SplitUpTypography.caption(color: colors.textMuted),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: colors.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Search & Quick Select bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: colors.surfaceFlat,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.divider),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 20, color: colors.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: SplitUpTypography.body(color: colors.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Search friends...',
                              hintStyle: SplitUpTypography.body(color: colors.textMuted),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: Icon(Icons.clear_rounded, size: 18, color: colors.textMuted),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Friends List
          Expanded(
            child: asyncFriends.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text('Error loading friends: $err', style: TextStyle(color: colors.accentOwe)),
              ),
              data: (friends) {
                final filteredFriends = friends.where((f) {
                  if (_searchQuery.isEmpty) return true;
                  return f.resolvedName.toLowerCase().contains(_searchQuery) ||
                      f.phoneE164.contains(_searchQuery);
                }).toList();

                if (friends.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_add_outlined, size: 48, color: colors.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          'No friends added yet',
                          style: SplitUpTypography.title(color: colors.textPrimary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Add friends first to split expenses with them',
                          style: SplitUpTypography.caption(color: colors.textMuted),
                        ),
                      ],
                    ),
                  );
                }

                if (filteredFriends.isEmpty) {
                  return Center(
                    child: Text(
                      'No friends matching "$_searchQuery"',
                      style: SplitUpTypography.body(color: colors.textMuted),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount: filteredFriends.length,
                  itemBuilder: (context, index) {
                    final friend = filteredFriends[index];
                    final isSelected = _selectedFriendIds.contains(friend.id);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? colors.glassFill : colors.surfaceFlat,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? colors.accentReceive : colors.divider,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: ListTile(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedFriendIds.remove(friend.id);
                            } else {
                              _selectedFriendIds.add(friend.id);
                            }
                          });
                        },
                        leading: Avatar(name: friend.resolvedName, size: 40),
                        title: Text(
                          friend.resolvedName,
                          style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                        ),
                        subtitle: Text(
                          friend.phoneE164,
                          style: SplitUpTypography.caption(color: colors.textMuted),
                        ),
                        trailing: Checkbox(
                          value: isSelected,
                          activeColor: colors.accentReceive,
                          checkColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedFriendIds.add(friend.id);
                              } else {
                                _selectedFriendIds.remove(friend.id);
                              }
                            });
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Bottom Continue Action
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: colors.surfaceFlat,
              border: Border(top: BorderSide(color: colors.divider)),
            ),
            child: SafeArea(
              top: false,
              child: asyncFriends.maybeWhen(
                data: (friends) {
                  final selectedCount = _selectedFriendIds.length;
                  final selectedFriends = friends.where((f) => _selectedFriendIds.contains(f.id)).toList();

                  return PrimaryButton(
                    label: selectedCount == 0
                        ? 'Select at least 1 friend'
                        : 'Continue with $selectedCount ${selectedCount == 1 ? 'friend' : 'friends'}',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: selectedCount > 0
                        ? () => Navigator.of(context).pop(selectedFriends)
                        : null,
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
