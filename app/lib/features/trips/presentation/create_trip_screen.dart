import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key});

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _nameController = TextEditingController();
  final _budgetController = TextEditingController(text: '50000');
  final Set<String> _selectedFriendIds = {
    MockDataRepository.userRahul.id,
    MockDataRepository.userPriya.id,
    MockDataRepository.userSneha.id,
  };

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
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
                    hintText: 'Trip Name (e.g. Goa Vacation)',
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
              const SizedBox(height: 20),

              // Quick copy from group button
              SecondaryButton(
                label: 'Add all members from "Friday Gang"',
                icon: Icons.group_add_rounded,
                onPressed: () {
                  setState(() {
                    for (final m in MockDataRepository.groups.first.members) {
                      _selectedFriendIds.add(m.id);
                    }
                  });
                },
              ),
              const SizedBox(height: 24),

              Text(
                'Trip Members (${_selectedFriendIds.length + 1})',
                style: SplitUpTypography.title(color: colors.textPrimary),
              ),
              const SizedBox(height: 12),

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
                          child: Text(
                            f.user.displayName,
                            style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
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
                label: 'Create Trip',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: colors.surfaceFlatRaised,
                      content: Text(
                        'Trip created successfully!',
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
