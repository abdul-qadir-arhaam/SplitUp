import 'package:flutter/material.dart';
import '../money/paise.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';
import 'widgets.dart';

class MemberDisplayInfo {
  final String userId;
  final String name;
  final String phoneE164;
  final String? photoUrl;
  final String role; // 'ADMIN' | 'ORGANIZER' | 'MEMBER'
  final int netPaise;
  final bool isAppUser;
  final bool isMe;
  final String? debtDescription;

  const MemberDisplayInfo({
    required this.userId,
    required this.name,
    required this.phoneE164,
    this.photoUrl,
    required this.role,
    required this.netPaise,
    required this.isAppUser,
    required this.isMe,
    this.debtDescription,
  });
}

typedef MemberRemoveCallback = Future<void> Function(MemberDisplayInfo member);
typedef MemberNotifyCallback = Future<void> Function(MemberDisplayInfo member);
typedef MemberAddCallback = Future<MemberDisplayInfo?> Function();

class MembersSheet extends StatefulWidget {
  final String title;
  final String entityName;
  final List<MemberDisplayInfo> members;
  final MemberAddCallback? onAddMember;
  final MemberRemoveCallback? onRemoveMember;
  final MemberNotifyCallback? onRemindToSettle;

  const MembersSheet({
    super.key,
    required this.title,
    required this.entityName,
    required this.members,
    this.onAddMember,
    this.onRemoveMember,
    this.onRemindToSettle,
  });

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String entityName,
    required List<MemberDisplayInfo> members,
    MemberAddCallback? onAddMember,
    MemberRemoveCallback? onRemoveMember,
    MemberNotifyCallback? onRemindToSettle,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MembersSheet(
        title: title,
        entityName: entityName,
        members: members,
        onAddMember: onAddMember,
        onRemoveMember: onRemoveMember,
        onRemindToSettle: onRemindToSettle,
      ),
    );
  }

  @override
  State<MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<MembersSheet> {
  late List<MemberDisplayInfo> _members;
  bool _isRemoveMode = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _members = List.from(widget.members);
  }

  Future<void> _handleRemoveMember(MemberDisplayInfo member) async {
    final colors = context.colors;

    final bool hasDebt = member.netPaise != 0 ||
        (member.debtDescription != null && member.debtDescription!.isNotEmpty);

    if (hasDebt) {
      final desc = member.debtDescription ??
          (member.netPaise < 0
              ? 'owes ${formatPaise(member.netPaise.abs())}'
              : 'is owed ${formatPaise(member.netPaise.abs())}');

      // Automatically send notification to that user to settle payments with friends!
      if (widget.onRemindToSettle != null) {
        await widget.onRemindToSettle!(member);
      }

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: colors.surfaceFlatRaised,
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.accentOwe, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cannot Remove Member',
                  style: SplitUpTypography.title(color: colors.accentOwe),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${member.name} $desc in ${widget.entityName} or with friends.',
                style: SplitUpTypography.body(color: colors.textPrimary),
              ),
              const SizedBox(height: 12),
              Text(
                'A member cannot be removed from ${widget.entityName} until all pending payments with friends are completely settled.',
                style: SplitUpTypography.caption(color: colors.textSecondary),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceFlat,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.accentReceive.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 20, color: colors.accentReceive),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'A settlement notification has been sent to ${member.name} to settle their payment with friends.',
                        style: SplitUpTypography.caption(color: colors.textPrimary).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentReceive,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceFlatRaised,
        title: Text(
          'Remove Member?',
          style: SplitUpTypography.title(color: colors.accentOwe),
        ),
        content: Text(
          'Are you sure you want to remove "${member.name}" from ${widget.entityName}?',
          style: SplitUpTypography.body(color: colors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: SplitUpTypography.label(color: colors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors.accentOwe),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.onRemoveMember != null) {
      setState(() => _isProcessing = true);
      try {
        await widget.onRemoveMember!(member);
        setState(() {
          _members.removeWhere((m) => m.userId == member.userId);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Removed ${member.name} from ${widget.entityName}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: colors.accentOwe,
              content: Text('Failed to remove member: $e'),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceFlat,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: colors.glassBorder, width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row: Title, Subtitle, Add, Remove, Close X
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: SplitUpTypography.title(color: colors.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.entityName} · ${_members.length} members',
                          style: SplitUpTypography.caption(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),

                  // Add button
                  if (widget.onAddMember != null && !_isRemoveMode) ...[
                    TextButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () async {
                              final newMember = await widget.onAddMember!();
                              if (newMember != null && mounted) {
                                setState(() {
                                  _members.add(newMember);
                                });
                              }
                            },
                      icon: Icon(Icons.person_add_outlined, size: 18, color: colors.accentReceive),
                      label: Text(
                        'Add',
                        style: SplitUpTypography.label(color: colors.accentReceive),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],

                  // Remove button next to Add and X
                  if (widget.onRemoveMember != null) ...[
                    TextButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () {
                              setState(() {
                                _isRemoveMode = !_isRemoveMode;
                              });
                            },
                      icon: Icon(
                        _isRemoveMode ? Icons.check_circle_outline_rounded : Icons.person_remove_outlined,
                        size: 18,
                        color: _isRemoveMode ? colors.accentReceive : colors.accentOwe,
                      ),
                      label: Text(
                        _isRemoveMode ? 'Done' : 'Remove',
                        style: SplitUpTypography.label(
                          color: _isRemoveMode ? colors.accentReceive : colors.accentOwe,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],

                  // X button to close the tab
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colors.textMuted, size: 22),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Info banner during removal mode
            if (_isRemoveMode)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.accentOwe.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.accentOwe.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: colors.accentOwe),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap "Remove" next to a member. Unsettled members cannot be removed.',
                        style: SplitUpTypography.caption(color: colors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),

            Divider(color: colors.divider, height: 1),

            // Members List
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                itemCount: _members.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final member = _members[index];
                  final bool isAdmin = member.role.toUpperCase() == 'ADMIN' ||
                      member.role.toUpperCase() == 'ORGANIZER';

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: colors.surfaceFlatRaised,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: member.isMe
                            ? colors.accentReceive.withValues(alpha: 0.35)
                            : colors.divider,
                      ),
                    ),
                    child: Row(
                      children: [
                        Avatar(name: member.name, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      member.isMe ? '${member.name} (You)' : member.name,
                                      style: SplitUpTypography.body(color: colors.textPrimary).copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isAdmin) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colors.accentBrass.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        member.role.toUpperCase() == 'ORGANIZER' ? 'ORGANIZER' : 'ADMIN',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: colors.accentBrass,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                member.debtDescription != null
                                    ? member.debtDescription!
                                    : (member.isAppUser
                                        ? (member.phoneE164.isNotEmpty ? member.phoneE164 : 'SplitUp User')
                                        : 'SMS Invited · Non-app'),
                                style: SplitUpTypography.caption(
                                  color: member.debtDescription != null
                                      ? colors.accentOwe
                                      : (member.isAppUser ? colors.textMuted : colors.accentBrass),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Action area: Either Remove button (in remove mode) or Balance Chip
                        if (_isRemoveMode && !member.isMe)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.accentOwe,
                              side: BorderSide(color: colors.accentOwe.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                            ),
                            onPressed: _isProcessing ? null : () => _handleRemoveMember(member),
                            icon: const Icon(Icons.remove_circle_outline_rounded, size: 16),
                            label: const Text('Remove', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          )
                        else if (member.netPaise != 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    member.netPaise > 0
                                        ? '+${formatPaise(member.netPaise)}'
                                        : formatPaise(member.netPaise),
                                    style: SplitUpTypography.label(
                                      color: member.netPaise > 0
                                          ? colors.accentReceive
                                          : colors.accentOwe,
                                    ).copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    member.netPaise > 0 ? 'gets back' : 'owes',
                                    style: SplitUpTypography.caption(
                                      color: member.netPaise > 0
                                          ? colors.accentReceive
                                          : colors.accentOwe,
                                    ),
                                  ),
                                ],
                              ),
                              if (!member.isMe && widget.onRemindToSettle != null) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(Icons.notifications_active_outlined, size: 20, color: colors.accentReceive),
                                  tooltip: 'Send settlement reminder',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => widget.onRemindToSettle!(member),
                                ),
                              ],
                            ],
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: colors.surfaceFlat,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Settled',
                              style: SplitUpTypography.caption(color: colors.textMuted),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
