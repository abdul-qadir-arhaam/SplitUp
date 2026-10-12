import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_service.dart';
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
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  List<StoredUserAccount> _otherRegisteredUsers = [];
  StoredUserAccount? _detectedAppUser;

  @override
  void initState() {
    super.initState();
    _loadRegisteredUsers();
  }

  Future<void> _loadRegisteredUsers() async {
    try {
      final currentUserId = ref.read(authNotifierProvider).user?.id;
      final accounts = await ref.read(authServiceProvider).getStoredAccounts();
      final friends = ref.read(friendsNotifierProvider).asData?.value ?? [];
      final friendPhones = friends
          .map((f) => f.phoneE164.replaceAll(RegExp(r'[^\d]'), ''))
          .toSet();

      // Only show real registered accounts (excluding current user and existing friends)
      final others = accounts.where((a) {
        if (a.id == currentUserId || a.id == 'usr_arhaam') return false;
        final clean = a.phone.replaceAll(RegExp(r'[^\d]'), '');
        return !friendPhones.contains(clean);
      }).toList();

      if (mounted) {
        setState(() {
          _otherRegisteredUsers = others;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onPhoneChanged(String val) {
    final cleaned = val.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.length >= 10) {
      final match = _otherRegisteredUsers.cast<StoredUserAccount?>().firstWhere(
        (a) => a?.phone == cleaned,
        orElse: () => null,
      );
      if (match != null) {
        setState(() {
          _detectedAppUser = match;
          if (_nameController.text.trim().isEmpty) {
            _nameController.text = match.name;
          }
        });
        return;
      }
    }
    if (_detectedAppUser != null) {
      setState(() => _detectedAppUser = null);
    }
  }

  Future<void> _handleAddFriend({
    required String phone,
    String? name,
    required bool isAppUser,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanPhone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a valid 10-digit mobile number'),
          backgroundColor: context.colors.accentOwe,
        ),
      );
      return;
    }

    final trimmedName = name?.trim();
    if (trimmedName == null || trimmedName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Please enter your friend's name"),
          backgroundColor: context.colors.accentOwe,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(friendsNotifierProvider.notifier).addFriend(
            phone: cleanPhone,
            name: trimmedName,
            contactName: trimmedName,
          );

      if (!mounted) return;
      Navigator.of(context).pop();

      if (!isAppUser) {
        _showInviteSmsDialog(name: trimmedName, phone: cleanPhone);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $trimmedName as friend!'),
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
                '$name is added to your friend ledger. You can split bills immediately.',
                style: SplitUpTypography.body(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              Text(
                'Send an SMS invite so they can download SplitUp and track expenses too?',
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
                final uri = Uri.parse(
                  'sms:$phone?body=Hey! I added you on SplitUp to track our shared expenses. Download the app: https://splitup.app/download',
                );
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

    return GlassSheet(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 16,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.accentReceive.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.person_add_rounded, color: colors.accentReceive, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Friend',
                            style: SplitUpTypography.headline(color: colors.textPrimary).copyWith(fontSize: 20),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Add by mobile number to start splitting bills',
                            style: SplitUpTypography.caption(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Mobile Number Field
                Text(
                  'Mobile Number *',
                  style: SplitUpTypography.label(color: colors.textSecondary),
                ),
                const SizedBox(height: 6),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '🇮🇳 +91',
                        style: SplitUpTypography.title(color: colors.textPrimary),
                      ),
                      const SizedBox(width: 10),
                      Container(width: 1, height: 24, color: colors.divider),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          onChanged: _onPhoneChanged,
                          style: SplitUpTypography.title(color: colors.textPrimary),
                          decoration: InputDecoration(
                            hintText: '10-digit mobile number',
                            hintStyle: SplitUpTypography.title(color: colors.textMuted),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Live status badge if member detected
                if (_detectedAppUser != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.accentReceive.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.accentReceive.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_rounded, size: 16, color: colors.accentReceive),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'SplitUp Member: ${_detectedAppUser!.name}',
                            style: SplitUpTypography.caption(color: colors.accentReceive).copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 14),

                // Friend Name Field
                Text(
                  "Friend's Name *",
                  style: SplitUpTypography.label(color: colors.textSecondary),
                ),
                const SizedBox(height: 6),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    style: SplitUpTypography.title(color: colors.textPrimary),
                    decoration: InputDecoration(
                      icon: Icon(Icons.person_outline_rounded, color: colors.textMuted, size: 20),
                      hintText: 'e.g. Aditi Sharma, Rohan',
                      hintStyle: SplitUpTypography.title(color: colors.textMuted),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Save Friend Button
                PrimaryButton(
                  label: 'Add to Friends',
                  icon: Icons.person_add_rounded,
                  isLoading: _isLoading,
                  onPressed: () {
                    final phone = _phoneController.text.trim();
                    final name = _nameController.text.trim();
                    final isAppUser = _detectedAppUser != null;
                    _handleAddFriend(phone: phone, name: name, isAppUser: isAppUser);
                  },
                ),

                // Discovered Registered Users (if other real users registered on this device/app)
                if (_otherRegisteredUsers.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Text(
                        'Registered Users on SplitUp',
                        style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 14),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.accentReceive.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_otherRegisteredUsers.length}',
                          style: TextStyle(fontSize: 11, color: colors.accentReceive, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _otherRegisteredUsers.length,
                    separatorBuilder: (_, _) => Divider(color: colors.divider, height: 1),
                    itemBuilder: (context, index) {
                      final u = _otherRegisteredUsers[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Avatar(name: u.name, size: 36),
                        title: Text(u.name, style: SplitUpTypography.title(color: colors.textPrimary)),
                        subtitle: Text(
                          '+91 ${u.phone}',
                          style: SplitUpTypography.caption(color: colors.textMuted),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.accentReceive,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          onPressed: _isLoading
                              ? null
                              : () => _handleAddFriend(
                                    phone: u.phone,
                                    name: u.name,
                                    isAppUser: true,
                                  ),
                          child: const Text('Add'),
                        ),
                      );
                    },
                  ),
                ],

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
