import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../friends/data/friends_repository.dart';
import '../../friends/domain/friend_model.dart';
import '../data/user_profile_provider.dart';
import '../../../core/auth/auth_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const ProfileScreen({
    super.key,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
  });

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  void _confirmSignOut(BuildContext context, SplitUpColors colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceFlatRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Sign Out', style: SplitUpTypography.title(color: colors.textPrimary)),
        content: Text(
          'Are you sure you want to sign out? Your ledger data is safely saved on this device.',
          style: SplitUpTypography.body(color: colors.textSecondary),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          PrimaryButton(
            label: 'Sign Out',
            height: 40,
            icon: Icons.logout_rounded,
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(authNotifierProvider.notifier).signOut();
              if (context.mounted) {
                context.go('/welcome');
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final profile = ref.watch(userProfileProvider);
    final asyncFriends = ref.watch(friendsNotifierProvider);

    final friends = asyncFriends.maybeWhen(
      data: (items) => items,
      orElse: () => const <FriendModel>[],
    );

    int totalYouOwe = 0;
    int totalYouAreOwed = 0;
    for (final f in friends) {
      if (f.netPaise < 0) {
        totalYouOwe += f.netPaise.abs();
      } else if (f.netPaise > 0) {
        totalYouAreOwed += f.netPaise;
      }
    }
    final netBalance = totalYouAreOwed - totalYouOwe;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Profile',
          style: SplitUpTypography.headline(color: colors.textPrimary),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              // User Card
              FadeSlideEntrance(
                offset: const Offset(0.0, -0.04),
                child: GlassCard(
                  strong: true,
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _EditProfileSheet.show(
                          context,
                          initialName: profile.name,
                          phone: profile.phone,
                          initialUpi: profile.upiId,
                          initialPhotoUrl: profile.photoUrl,
                          onSave: ({required name, required upiId, photoUrl, required clearPhoto}) {
                            ref.read(userProfileProvider.notifier).updateProfile(
                              name: name,
                              upiId: upiId,
                              photoUrl: photoUrl,
                              clearPhoto: clearPhoto,
                            );
                          },
                        ),
                        child: Stack(
                          children: [
                            Avatar(name: profile.name, photoUrl: profile.photoUrl, size: 64),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: colors.accentReceive,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: colors.surfaceFlatRaised, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.name,
                              style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 20),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              profile.phone,
                              style: SplitUpTypography.label(color: colors.textMuted),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.accentReceive.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Verified Account',
                                style: SplitUpTypography.caption(color: colors.accentReceive).copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit Profile',
                        icon: Icon(Icons.edit_outlined, color: colors.textSecondary),
                        onPressed: () => _EditProfileSheet.show(
                          context,
                          initialName: profile.name,
                          phone: profile.phone,
                          initialUpi: profile.upiId,
                          initialPhotoUrl: profile.photoUrl,
                          onSave: ({required name, required upiId, photoUrl, required clearPhoto}) {
                            ref.read(userProfileProvider.notifier).updateProfile(
                              name: name,
                              upiId: upiId,
                              photoUrl: photoUrl,
                              clearPhoto: clearPhoto,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Summary Totals Card: Total you owe, Total you are owed, Net
              FadeSlideEntrance(
                delay: const Duration(milliseconds: 70),
                child: GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FINANCIAL TOTALS',
                        style: SplitUpTypography.caption(color: colors.textMuted).copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total you owe', style: SplitUpTypography.body(color: colors.textSecondary)),
                          MoneyText(totalYouOwe, variant: MoneyVariant.title, customColor: colors.accentOwe),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total you are owed', style: SplitUpTypography.body(color: colors.textSecondary)),
                          MoneyText(totalYouAreOwed, variant: MoneyVariant.title, customColor: colors.accentReceive),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Net Balance', style: SplitUpTypography.title(color: colors.textPrimary)),
                          MoneyText(
                            netBalance.abs(),
                            variant: MoneyVariant.title,
                            customColor: netBalance < 0
                                ? colors.accentOwe
                                : (netBalance > 0 ? colors.accentReceive : colors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Theme Appearance Selector
              FadeSlideEntrance(
                delay: const Duration(milliseconds: 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: SplitUpTypography.label(color: colors.textMuted),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colors.surfaceFlat,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.divider),
                      ),
                      child: SegmentedControl<ThemeMode>(
                        values: const [ThemeMode.system, ThemeMode.dark, ThemeMode.light],
                        labels: const ['System', 'Dark', 'Light'],
                        selected: widget.currentThemeMode,
                        onSelected: widget.onThemeModeChanged,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Settings Items
              FadeSlideEntrance(
                delay: const Duration(milliseconds: 170),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings & Preferences',
                      style: SplitUpTypography.label(color: colors.textMuted),
                    ),
                    const SizedBox(height: 8),

                    _SettingsTile(
                      icon: Icons.notifications_none_rounded,
                      title: 'Notification Preferences',
                      colors: colors,
                      onTap: () => _NotificationPreferencesSheet.show(context),
                    ),
                    _SettingsTile(
                      icon: Icons.block_flipped,
                      title: 'Blocked Users',
                      colors: colors,
                      onTap: () => _BlockedUsersSheet.show(context),
                    ),
                    _SettingsTile(
                      icon: Icons.system_update_rounded,
                      title: 'App Version',
                      trailingText: 'v1.0.0 (Build 1)',
                      colors: colors,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: colors.surfaceFlatRaised,
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              'You are running the latest version of SplitUp.',
                              style: SplitUpTypography.body(color: colors.textPrimary),
                            ),
                          ),
                        );
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy & Terms',
                      colors: colors,
                      onTap: () => _PrivacyTermsSheet.show(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Logout Button
              FadeSlideEntrance(
                delay: const Duration(milliseconds: 220),
                child: SecondaryButton(
                  label: 'Sign Out',
                  icon: Icons.logout_rounded,
                  textColor: colors.accentOwe,
                  onPressed: () => _confirmSignOut(context, colors),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingText;
  final SplitUpColors colors;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailingText,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surfaceFlat,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          leading: Icon(icon, color: colors.textSecondary, size: 20),
          title: Text(
            title,
            style: SplitUpTypography.body(color: colors.textPrimary),
          ),
          trailing: trailingText != null
              ? Text(trailingText!, style: SplitUpTypography.caption(color: colors.textMuted))
              : Icon(Icons.arrow_forward_ios_rounded, color: colors.textMuted, size: 14),
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// Interactive Sheets
// -------------------------------------------------------------

/// 1. Edit Profile Sheet
class _EditProfileSheet extends StatefulWidget {
  final String initialName;
  final String phone;
  final String initialUpi;
  final String? initialPhotoUrl;
  final void Function({
    required String name,
    required String upiId,
    String? photoUrl,
    required bool clearPhoto,
  }) onSave;

  const _EditProfileSheet({
    required this.initialName,
    required this.phone,
    required this.initialUpi,
    this.initialPhotoUrl,
    required this.onSave,
  });

  static void show(
    BuildContext context, {
    required String initialName,
    required String phone,
    required String initialUpi,
    String? initialPhotoUrl,
    required void Function({
      required String name,
      required String upiId,
      String? photoUrl,
      required bool clearPhoto,
    }) onSave,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditProfileSheet(
        initialName: initialName,
        phone: phone,
        initialUpi: initialUpi,
        initialPhotoUrl: initialPhotoUrl,
        onSave: onSave,
      ),
    );
  }

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _upiController;
  String? _currentPhotoUrl;
  bool _clearedPhoto = false;

  static const List<String> _presetAvatars = [
    'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=240&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=240&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=240&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=240&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=240&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=240&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=240&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=240&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=240&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1501196354995-cbb51c65aaea?w=240&auto=format&fit=crop&q=80',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _upiController = TextEditingController(text: widget.initialUpi);
    _currentPhotoUrl = widget.initialPhotoUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.of(context).pop(); // Close bottom sheet menu
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        final mime = file.mimeType ?? 'image/jpeg';
        final dataUri = 'data:$mime;base64,${base64Encode(bytes)}';
        setState(() {
          _currentPhotoUrl = dataUri;
          _clearedPhoto = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not access image: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showAvatarPicker(SplitUpColors colors) {
    Navigator.of(context).pop(); // Close source menu
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: colors.surfaceFlatRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Choose an Avatar', style: SplitUpTypography.title(color: colors.textPrimary)),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: colors.textMuted),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: _presetAvatars.map((url) {
                      final isSelected = _currentPhotoUrl == url && !_clearedPhoto;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentPhotoUrl = url;
                            _clearedPhoto = false;
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? colors.accentReceive : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 28,
                            backgroundImage: NetworkImage(url),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showUrlInputDialog(SplitUpColors colors) {
    Navigator.of(context).pop(); // Close source menu
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceFlatRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Image Web Link', style: SplitUpTypography.title(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Paste a direct URL to any image (HTTPS):',
              style: SplitUpTypography.body(color: colors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'https://example.com/avatar.jpg',
                hintStyle: TextStyle(color: colors.textMuted),
                filled: true,
                fillColor: colors.surfaceFlat,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          PrimaryButton(
            label: 'Apply',
            height: 38,
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                setState(() {
                  _currentPhotoUrl = url;
                  _clearedPhoto = false;
                });
              }
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  void _showPhotoSourceOptions(BuildContext context, SplitUpColors colors) {
    final hasPhoto = (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) && !_clearedPhoto;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            color: colors.surfaceFlatRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Profile Photo',
              style: SplitUpTypography.title(color: colors.textPrimary),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceFlat,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.photo_library_rounded, color: colors.accentBrass),
              ),
              title: Text('Choose from Gallery / Files', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text('Upload an image from your device', style: TextStyle(color: colors.textMuted, fontSize: 12)),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceFlat,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.camera_alt_rounded, color: colors.accentReceive),
              ),
              title: Text('Take Photo', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text('Capture with your camera', style: TextStyle(color: colors.textMuted, fontSize: 12)),
              onTap: () => _pickImage(ImageSource.camera),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceFlat,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.face_retouching_natural_rounded, color: colors.accentReceive),
              ),
              title: Text('Choose an Avatar Preset', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text('Pick from curated profile pictures', style: TextStyle(color: colors.textMuted, fontSize: 12)),
              onTap: () => _showAvatarPicker(colors),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceFlat,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.link_rounded, color: colors.textSecondary),
              ),
              title: Text('Image Web Link', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text('Paste an image URL', style: TextStyle(color: colors.textMuted, fontSize: 12)),
              onTap: () => _showUrlInputDialog(colors),
            ),
            if (hasPhoto) ...[
              const Divider(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.accentOwe.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.delete_outline_rounded, color: colors.accentOwe),
                ),
                title: Text('Remove Current Photo', style: TextStyle(color: colors.accentOwe, fontWeight: FontWeight.w600)),
                onTap: () {
                  setState(() {
                    _currentPhotoUrl = null;
                    _clearedPhoto = true;
                  });
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          ],
        ),
      ),
    ),
  ),
);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final photoUrlToDisplay = _clearedPhoto ? null : _currentPhotoUrl;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceFlatRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Edit Profile', style: SplitUpTypography.title(color: colors.textPrimary)),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: colors.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => _showPhotoSourceOptions(context, colors),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.accentBrass.withValues(alpha: 0.4), width: 2),
                          ),
                          child: Avatar(
                            name: _nameController.text.isEmpty ? 'U' : _nameController.text,
                            photoUrl: photoUrlToDisplay,
                            size: 80,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: colors.accentReceive,
                              shape: BoxShape.circle,
                              border: Border.all(color: colors.surfaceFlatRaised, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _showPhotoSourceOptions(context, colors),
                    icon: Icon(Icons.photo_camera_rounded, size: 16, color: colors.accentReceive),
                    label: Text(
                      photoUrlToDisplay != null ? 'Change Profile Photo' : 'Add Profile Photo',
                      style: TextStyle(color: colors.accentReceive, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Full Name', style: SplitUpTypography.caption(color: colors.textMuted)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              style: TextStyle(color: colors.textPrimary),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                filled: true,
                fillColor: colors.surfaceFlat,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.divider)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.divider)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Phone Number (Verified)', style: SplitUpTypography.caption(color: colors.textMuted)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: colors.surfaceFlat.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.divider),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.phone, style: TextStyle(color: colors.textSecondary)),
                  Icon(Icons.verified_rounded, size: 18, color: colors.accentReceive),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text('Default UPI ID', style: SplitUpTypography.caption(color: colors.textMuted)),
            const SizedBox(height: 6),
            TextField(
              controller: _upiController,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: colors.surfaceFlat,
                hintText: 'e.g. yourname@okaxis',
                hintStyle: TextStyle(color: colors.textMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.divider)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.divider)),
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Save Changes',
              icon: Icons.check_circle_outline_rounded,
              onPressed: () {
                final newName = _nameController.text.trim();
                final newUpi = _upiController.text.trim();
                if (newName.isNotEmpty) {
                  widget.onSave(
                    name: newName,
                    upiId: newUpi,
                    photoUrl: _currentPhotoUrl,
                    clearPhoto: _clearedPhoto,
                  );
                }
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: colors.surfaceFlatRaised,
                    behavior: SnackBarBehavior.floating,
                    content: Text('Profile updated successfully!', style: TextStyle(color: colors.accentReceive)),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 2. Notification Preferences Sheet
class _NotificationPreferencesSheet extends StatefulWidget {
  const _NotificationPreferencesSheet();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _NotificationPreferencesSheet(),
    );
  }

  @override
  State<_NotificationPreferencesSheet> createState() => _NotificationPreferencesSheetState();
}

class _NotificationPreferencesSheetState extends State<_NotificationPreferencesSheet> {
  bool _expenseAlerts = true;
  bool _settlementAlerts = true;
  bool _dueReminders = true;
  bool _weeklyDigest = false;
  bool _smsFallbacks = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: colors.surfaceFlatRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notification Preferences', style: SplitUpTypography.title(color: colors.textPrimary)),
                    const SizedBox(height: 2),
                    Text('Manage how you receive alerts and reminders', style: SplitUpTypography.caption(color: colors.textMuted)),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: colors.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildToggle(
              title: 'Expense Updates',
              subtitle: 'When an expense is added, edited, or disputed in your groups',
              icon: Icons.receipt_long_rounded,
              value: _expenseAlerts,
              onChanged: (v) => setState(() => _expenseAlerts = v),
              colors: colors,
            ),
            _buildToggle(
              title: 'Settlement Alerts',
              subtitle: 'When a friend records a payment or confirms settlement',
              icon: Icons.account_balance_wallet_rounded,
              value: _settlementAlerts,
              onChanged: (v) => setState(() => _settlementAlerts = v),
              colors: colors,
            ),
            _buildToggle(
              title: 'Due Reminders',
              subtitle: 'Gentle nudges before dues remain unpaid for too long',
              icon: Icons.alarm_rounded,
              value: _dueReminders,
              onChanged: (v) => setState(() => _dueReminders = v),
              colors: colors,
            ),
            _buildToggle(
              title: 'Weekly Summary Digest',
              subtitle: 'A weekly snapshot of your shared balances and total splits',
              icon: Icons.auto_graph_rounded,
              value: _weeklyDigest,
              onChanged: (v) => setState(() => _weeklyDigest = v),
              colors: colors,
            ),
            _buildToggle(
              title: 'SMS / WhatsApp Fallback',
              subtitle: 'Notify placeholder friends who are not yet on the app',
              icon: Icons.sms_outlined,
              value: _smsFallbacks,
              onChanged: (v) => setState(() => _smsFallbacks = v),
              colors: colors,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Save Preferences',
              icon: Icons.check_circle_outline_rounded,
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: colors.surfaceFlatRaised,
                    behavior: SnackBarBehavior.floating,
                    content: Text('Notification preferences saved successfully.', style: TextStyle(color: colors.accentReceive)),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    required SplitUpColors colors,
  }) {
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
          Icon(icon, color: colors.accentBrass, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SplitUpTypography.body(color: colors.textPrimary).copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: SplitUpTypography.caption(color: colors.textMuted).copyWith(fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: colors.accentReceive,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 3. Blocked Users Sheet
class _BlockedUsersSheet extends StatefulWidget {
  const _BlockedUsersSheet();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _BlockedUsersSheet(),
    );
  }

  @override
  State<_BlockedUsersSheet> createState() => _BlockedUsersSheetState();
}

class _BlockedUsersSheetState extends State<_BlockedUsersSheet> {
  final List<Map<String, String>> _blockedList = [
    {
      'id': 'blk_1',
      'name': 'Vikram Malhotra',
      'phone': '+91 98200 11223',
      'reason': 'Spam requests',
    },
  ];

  void _unblockUser(int index, SplitUpColors colors) {
    final user = _blockedList[index];
    setState(() {
      _blockedList.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: colors.surfaceFlatRaised,
        behavior: SnackBarBehavior.floating,
        content: Text('${user['name']} has been unblocked.', style: TextStyle(color: colors.accentReceive)),
      ),
    );
  }

  void _showBlockNewUserDialog(SplitUpColors colors) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceFlatRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Block a Contact', style: SplitUpTypography.title(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter contact name or phone number:', style: SplitUpTypography.caption(color: colors.textMuted)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g. Ramesh or +91...',
                hintStyle: TextStyle(color: colors.textMuted),
                filled: true,
                fillColor: colors.surfaceFlat,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.divider)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          PrimaryButton(
            label: 'Block',
            height: 40,
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  _blockedList.add({
                    'id': 'blk_${DateTime.now().millisecondsSinceEpoch}',
                    'name': text,
                    'phone': '+91 90000 00000',
                    'reason': 'Manually blocked',
                  });
                });
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: colors.surfaceFlatRaised,
                    behavior: SnackBarBehavior.floating,
                    content: Text('$text has been blocked.', style: TextStyle(color: colors.accentOwe)),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: colors.surfaceFlatRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Blocked Users', style: SplitUpTypography.title(color: colors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('Blocked contacts cannot add you to expenses or groups', style: SplitUpTypography.caption(color: colors.textMuted)),
                ],
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: colors.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_blockedList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: EmptyState(
                  icon: Icons.shield_outlined,
                  title: 'No Blocked Contacts',
                  message: 'You have full communication open with all your contacts.',
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _blockedList.length,
                itemBuilder: (context, index) {
                  final b = _blockedList[index];
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
                        Avatar(name: b['name']!, size: 44),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b['name']!, style: SplitUpTypography.body(color: colors.textPrimary).copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text('${b['phone']} · ${b['reason']}', style: SplitUpTypography.caption(color: colors.textMuted)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _unblockUser(index, colors),
                          child: Text('Unblock', style: TextStyle(color: colors.accentReceive, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          SecondaryButton(
            label: 'Block a User',
            icon: Icons.person_add_disabled_rounded,
            onPressed: () => _showBlockNewUserDialog(colors),
          ),
        ],
      ),
    );
  }
}

/// 4. Privacy Policy & Terms Sheet
class _PrivacyTermsSheet extends StatefulWidget {
  const _PrivacyTermsSheet();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _PrivacyTermsSheet(),
    );
  }

  @override
  State<_PrivacyTermsSheet> createState() => _PrivacyTermsSheetState();
}

class _PrivacyTermsSheetState extends State<_PrivacyTermsSheet> {
  int _selectedTab = 0; // 0 = Privacy, 1 = Terms

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      decoration: BoxDecoration(
        color: colors.surfaceFlatRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Legal & Privacy', style: SplitUpTypography.title(color: colors.textPrimary)),
              IconButton(
                icon: Icon(Icons.close_rounded, color: colors.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedControl<int>(
            values: const [0, 1],
            labels: const ['Privacy Policy', 'Terms of Service'],
            selected: _selectedTab,
            onSelected: (val) => setState(() => _selectedTab = val),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: _selectedTab == 0 ? _buildPrivacyContent(colors) : _buildTermsContent(colors),
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Acknowledge & Close',
            icon: Icons.check_circle_outline_rounded,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPrivacyContent(SplitUpColors colors) {
    return [
      _buildLegalSection(
        icon: Icons.lock_outline_rounded,
        title: '1. Zero Data Selling & Privacy First',
        body: 'SplitUp never sells, leases, or monetizes your personal transaction histories or contact graph to advertisers or third parties.',
        colors: colors,
      ),
      _buildLegalSection(
        icon: Icons.storage_rounded,
        title: '2. Offline-First & Local Encryption',
        body: 'All balance matrices and group transactions are cached locally on your device and synchronized using secure TLS encryption.',
        colors: colors,
      ),
      _buildLegalSection(
        icon: Icons.contacts_outlined,
        title: '3. Contact Permissions',
        body: 'Address book access is strictly used locally to resolve names and simplify adding friends. Your full address book is never uploaded in bulk.',
        colors: colors,
      ),
      _buildLegalSection(
        icon: Icons.delete_outline_rounded,
        title: '4. Right to Deletion & Export',
        body: 'You retain full ownership of your financial records. You can export a CSV copy or permanently delete your account at any time.',
        colors: colors,
      ),
    ];
  }

  List<Widget> _buildTermsContent(SplitUpColors colors) {
    return [
      _buildLegalSection(
        icon: Icons.calculate_outlined,
        title: '1. Ledger Calculation Tool',
        body: 'SplitUp operates as a mathematical ledger tool. SplitUp does not hold user funds, act as an escrow agent, or process banking deposits directly.',
        colors: colors,
      ),
      _buildLegalSection(
        icon: Icons.account_balance_outlined,
        title: '2. External UPI Settlements',
        body: 'All monetary settlements occur peer-to-peer via external payment providers (Google Pay, PhonePe, Paytm, BHIM UPI). Mark settlements only after money is sent.',
        colors: colors,
      ),
      _buildLegalSection(
        icon: Icons.handshake_outlined,
        title: '3. Good Faith Usage',
        body: 'Users agree to enter honest amounts and agree on split distributions mutually within their groups and trips.',
        colors: colors,
      ),
      _buildLegalSection(
        icon: Icons.verified_user_outlined,
        title: '4. Admin Responsibilities',
        body: 'Group creators maintain administrative authority to archive groups or adjust member roles once outstanding balances are fully settled.',
        colors: colors,
      ),
    ];
  }

  Widget _buildLegalSection({
    required IconData icon,
    required String title,
    required String body,
    required SplitUpColors colors,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceFlat,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.accentBrass, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 14)),
                const SizedBox(height: 4),
                Text(body, style: SplitUpTypography.body(color: colors.textSecondary).copyWith(fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
