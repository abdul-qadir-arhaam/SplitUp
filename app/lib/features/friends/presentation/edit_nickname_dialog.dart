import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../domain/friend_model.dart';
import '../data/friends_repository.dart';

class EditNicknameDialog extends ConsumerStatefulWidget {
  final FriendModel friend;

  const EditNicknameDialog({super.key, required this.friend});

  static Future<void> show(BuildContext context, FriendModel friend) {
    return showDialog(
      context: context,
      builder: (context) => EditNicknameDialog(friend: friend),
    );
  }

  @override
  ConsumerState<EditNicknameDialog> createState() => _EditNicknameDialogState();
}

class _EditNicknameDialogState extends ConsumerState<EditNicknameDialog> {
  late final TextEditingController _controller;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.friend.nickname ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave([String? nickname]) async {
    setState(() => _isLoading = true);
    try {
      await ref.read(friendsNotifierProvider.notifier).updateNickname(
            widget.friend.id,
            nickname?.trim().isEmpty == true ? null : nickname?.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: context.colors.accentOwe),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.surfaceFlatRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Edit Friend Name', style: SplitUpTypography.title(color: colors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This nickname is private and only visible to you.',
            style: SplitUpTypography.caption(color: colors.textMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            style: SplitUpTypography.body(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Private Nickname',
              labelStyle: TextStyle(color: colors.textSecondary),
              filled: true,
              fillColor: colors.glassFill,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Profile Name: ${widget.friend.name}',
            style: SplitUpTypography.caption(color: colors.textMuted),
          ),
        ],
      ),
      actions: [
        if (widget.friend.nickname != null)
          TextButton(
            onPressed: _isLoading ? null : () => _handleSave(null),
            child: Text('Reset to Default', style: TextStyle(color: colors.accentOwe)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.accentReceive,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _isLoading ? null : () => _handleSave(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
