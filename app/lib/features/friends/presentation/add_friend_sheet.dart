import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../data/friends_repository.dart';

class AddFriendSheet extends ConsumerStatefulWidget {
  const AddFriendSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddFriendSheet(),
    );
  }

  @override
  ConsumerState<AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends ConsumerState<AddFriendSheet> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isManualEntry = false;
  bool _isLoading = false;

  final List<Map<String, dynamic>> _contacts = [
    {'name': 'Aarav Sharma', 'phone': '9876543211', 'isOnApp': true},
    {'name': 'Bhavna Patel', 'phone': '9876543212', 'isOnApp': true},
    {'name': 'Chetan Verma', 'phone': '9876543215', 'isOnApp': false},
    {'name': 'Divya Reddy', 'phone': '9876543216', 'isOnApp': false},
    {'name': 'Farhan Khan', 'phone': '9876543217', 'isOnApp': false},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleAddFriend({required String phone, String? name, required bool isAppUser}) async {
    setState(() => _isLoading = true);
    try {
      await ref.read(friendsNotifierProvider.notifier).addFriend(
            phone: phone,
            name: name,
            contactName: name,
          );

      if (!mounted) return;
      Navigator.of(context).pop();

      if (!isAppUser) {
        _showInviteSmsDialog(name: name ?? phone, phone: phone);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $name as friend! In-app notification sent.'),
            backgroundColor: context.colors.accentReceive,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: context.colors.accentOwe,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showInviteSmsDialog({required String name, required String phone}) {
    showDialog(
      context: context,
      builder: (ctx) {
        final colors = ctx.colors;
        return AlertDialog(
          backgroundColor: colors.surfaceFlatRaised,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Invite $name', style: SplitUpTypography.title(color: colors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name is not on SplitUp yet. You can still record expenses together, and they will merge automatically when they join.',
                style: SplitUpTypography.body(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              Text(
                'Send an SMS invite with the link?',
                style: SplitUpTypography.caption(color: colors.textMuted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Not now', style: TextStyle(color: colors.textMuted)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentReceive,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.sms_rounded, size: 18),
              label: const Text('Invite via SMS'),
              onPressed: () async {
                Navigator.of(ctx).pop();
                final uri = Uri.parse('sms:$phone?body=Hey! I added you on SplitUp to track our shared expenses. Download the app: https://splitup.app/download');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filteredContacts = _contacts.where((c) {
      final q = _searchController.text.toLowerCase();
      return c['name'].toString().toLowerCase().contains(q) ||
          c['phone'].toString().contains(q);
    }).toList();

    return GlassSheet(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20,
          right: 20,
          top: 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add Friend',
                  style: SplitUpTypography.headline(color: colors.textPrimary).copyWith(fontSize: 22),
                ),
                TextButton(
                  onPressed: () => setState(() => _isManualEntry = !_isManualEntry),
                  child: Text(
                    _isManualEntry ? 'From Contacts' : 'Manual Entry',
                    style: TextStyle(color: colors.accentReceive),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (!_isManualEntry) ...[
              // Search Field
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: SplitUpTypography.body(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search contacts or enter phone...',
                  hintStyle: TextStyle(color: colors.textMuted),
                  prefixIcon: Icon(Icons.search_rounded, color: colors.textMuted),
                  filled: true,
                  fillColor: colors.glassFill,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colors.glassBorder),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Contacts List
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filteredContacts.length,
                  separatorBuilder: (_, _) => Divider(color: colors.divider, height: 1),
                  itemBuilder: (context, index) {
                    final c = filteredContacts[index];
                    final isOnApp = c['isOnApp'] as bool;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Avatar(name: c['name'] as String, size: 40),
                      title: Text(c['name'] as String, style: SplitUpTypography.title(color: colors.textPrimary)),
                      subtitle: Text(
                        '+91 ${c['phone']}',
                        style: SplitUpTypography.caption(color: colors.textMuted),
                      ),
                      trailing: isOnApp
                          ? ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors.accentReceive,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                              onPressed: _isLoading
                                  ? null
                                  : () => _handleAddFriend(
                                        phone: c['phone'] as String,
                                        name: c['name'] as String,
                                        isAppUser: true,
                                      ),
                              child: const Text('Add'),
                            )
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: colors.accentReceive),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                              onPressed: _isLoading
                                  ? null
                                  : () => _handleAddFriend(
                                        phone: c['phone'] as String,
                                        name: c['name'] as String,
                                        isAppUser: false,
                                      ),
                              child: Text('Invite', style: TextStyle(color: colors.accentReceive)),
                            ),
                    );
                  },
                ),
              ),
            ] else ...[
              // Manual Entry Form
              TextField(
                controller: _nameController,
                style: SplitUpTypography.body(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Friend Name',
                  labelStyle: TextStyle(color: colors.textSecondary),
                  filled: true,
                  fillColor: colors.glassFill,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: SplitUpTypography.body(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Phone Number (10 digits)',
                  prefixText: '+91 ',
                  labelStyle: TextStyle(color: colors.textSecondary),
                  filled: true,
                  fillColor: colors.glassFill,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Save Friend',
                icon: Icons.person_add_rounded,
                isLoading: _isLoading,
                onPressed: () {
                  final phone = _phoneController.text.trim();
                  final name = _nameController.text.trim();
                  if (phone.isEmpty) return;
                  _handleAddFriend(phone: phone, name: name.isEmpty ? null : name, isAppUser: false);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
