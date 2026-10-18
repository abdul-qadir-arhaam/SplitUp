import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../friends/domain/friend_model.dart';
import '../data/settlements_repository.dart';

class SettleSheet extends ConsumerStatefulWidget {
  final FriendModel? friend;
  final String? friendId;
  final String? friendName;
  final String? ledgerId;
  final int? amountPaise;

  const SettleSheet({
    super.key,
    this.friend,
    this.friendId,
    this.friendName,
    this.ledgerId,
    this.amountPaise,
  });

  static Future<void> show(BuildContext context, FriendModel friend) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SettleSheet(friend: friend),
    );
  }

  @override
  ConsumerState<SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends ConsumerState<SettleSheet> {
  late final TextEditingController _amountController;
  String _selectedMethod = 'UPI';
  bool _isSubmitting = false;

  String get targetUserId => widget.friend?.id ?? widget.friendId ?? '';
  String get targetName => widget.friend?.resolvedName ?? widget.friendName ?? 'Member';
  String get targetLedgerId => widget.ledgerId ?? widget.friend?.individualLedgerId ?? '';
  int get maxDebtPaise => widget.amountPaise ?? widget.friend?.netPaise.abs() ?? 0;
  bool get isPlaceholder => widget.friend != null ? !widget.friend!.isAppUser : false;

  @override
  void initState() {
    super.initState();
    final defaultDebtRupees = (maxDebtPaise / 100).toStringAsFixed(0);
    _amountController = TextEditingController(text: defaultDebtRupees);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final int enteredPaise = MoneyUtils.parseToPaise(_amountController.text) ?? 0;
    final bool isOverpaying = enteredPaise > maxDebtPaise;
    final bool isValid = enteredPaise > 0 && !isOverpaying;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceFlatRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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

              Text(
                'Settle with $targetName',
                style: SplitUpTypography.headline(color: colors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Total balance owed: ${formatPaise(maxDebtPaise)}',
                style: SplitUpTypography.body(color: colors.accentOwe),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Amount Input
              Center(
                child: AmountInput(
                  controller: _amountController,
                  onChanged: (val) => setState(() {}),
                ),
              ),
              if (isOverpaying) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Overpayment blocked: max ${formatPaise(maxDebtPaise)}',
                    style: SplitUpTypography.caption(color: colors.accentOwe),
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Method Segmented Control
              Text(
                'Settlement Method',
                style: SplitUpTypography.label(color: colors.textMuted),
              ),
              const SizedBox(height: 8),
              SegmentedControl<String>(
                values: const ['UPI', 'CASH', 'OTHER'],
                labels: const ['UPI', 'Cash', 'Other'],
                selected: _selectedMethod,
                onSelected: (val) => setState(() => _selectedMethod = val),
              ),
              const SizedBox(height: 16),

              // Placeholder note if applicable
              if (isPlaceholder) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.accentReceive.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.accentReceive.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_outlined, size: 18, color: colors.accentReceive),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Self-confirmed (unverified): Since $targetName is not yet on SplitUp, this settlement will be immediately recorded on their behalf.',
                          style: SplitUpTypography.caption(color: colors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              PrimaryButton(
                label: _isSubmitting
                    ? 'Submitting...'
                    : 'Confirm Settlement (${formatPaise(enteredPaise)})',
                icon: _isSubmitting ? null : Icons.check_circle_rounded,
                onPressed: (isValid && !_isSubmitting)
                    ? () async {
                        if (_isSubmitting) return;
                        setState(() => _isSubmitting = true);

                        final idempotencyKey = 'idem_stl_${DateTime.now().millisecondsSinceEpoch}';
                        try {
                          await ref.read(settlementsNotifierProvider.notifier).createSettlement(
                                ledgerId: targetLedgerId,
                                toUserId: targetUserId,
                                amountPaise: enteredPaise,
                                method: _selectedMethod,
                                isPlaceholderReceiver: isPlaceholder,
                                idempotencyKey: idempotencyKey,
                              );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: colors.surfaceFlatRaised,
                                content: Text(
                                  isPlaceholder
                                      ? 'Settlement self-confirmed (unverified) with $targetName.'
                                      : 'Settlement request sent to $targetName!',
                                  style: SplitUpTypography.body(color: colors.textPrimary),
                                ),
                              ),
                            );
                            Navigator.pop(context);
                          }
                        } on Exception catch (e) {
                          if (context.mounted) {
                            final errStr = e.toString();
                            final isConflict = errStr.contains('already exists') || errStr.contains('409') || errStr.contains('CONFLICT');
                            if (isConflict) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: colors.surfaceFlatRaised,
                                  content: Text(
                                    'A pending settlement already exists with $targetName.',
                                    style: SplitUpTypography.body(color: colors.accentBrass),
                                  ),
                                ),
                              );
                              await ref.read(settlementsNotifierProvider.notifier).syncSettlementsForLedger(targetLedgerId);
                              Navigator.pop(context);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: colors.accentOwe,
                                  content: Text(
                                    errStr.replaceAll('Exception: ', ''),
                                    style: SplitUpTypography.body(color: Colors.white),
                                  ),
                                ),
                              );
                            }
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isSubmitting = false);
                          }
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    ),
  );
}
}
