import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final Set<String> _selectedFriendIds = {
    MockDataRepository.userRahul.id,
    MockDataRepository.userPriya.id,
  };

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final friends = MockDataRepository.friends;

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
                    Avatar(name: MockDataRepository.currentUser.name, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${MockDataRepository.currentUser.name} (You)',
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
              ...friends.map((f) {
                final isSelected = _selectedFriendIds.contains(f.user.id);
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
                          _selectedFriendIds.remove(f.user.id);
                        } else {
                          _selectedFriendIds.add(f.user.id);
                        }
                      });
                    },
                    child: Row(
                      children: [
                        Avatar(name: f.user.displayName, size: 40, isPlaceholder: f.user.isPlaceholder),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.user.displayName,
                                style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                              ),
                              Text(
                                f.user.phone,
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
              }),

              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Create Group',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: colors.surfaceFlatRaised,
                      content: Text(
                        'Group created successfully!',
                        style: SplitUpTypography.body(color: colors.textPrimary),
                      ),
                    ),
                  );
                  context.pop();
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
