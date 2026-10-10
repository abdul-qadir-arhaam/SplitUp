import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../friends/domain/friend_model.dart';
import '../data/settlements_repository.dart';

class SettleSheet extends ConsumerStatefulWidget {
  final FriendModel friend;

  const SettleSheet({super.key, required this.friend});

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

  @override
  void initState() {
    super.initState();
    final defaultDebtRupees = (widget.friend.netPaise.abs() / 100).toStringAsFixed(0);
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
    final int maxDebtPaise = widget.friend.netPaise.abs();
    final int enteredPaise = MoneyUtils.parseToPaise(_amountController.text) ?? 0;
    final bool isOverpaying = enteredPaise > maxDebtPaise;
    final bool isValid = enteredPaise > 0 && !isOverpaying;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceFlatRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SafeArea(
          top: false,
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
                'Settle with ${widget.friend.resolvedName}',
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
              if (!widget.friend.isAppUser) ...[
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
                          'Self-confirmed (unverified): Since ${widget.friend.resolvedName} is not yet on SplitUp, this settlement will be immediately recorded on their behalf.',
                          style: SplitUpTypography.caption(color: colors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              PrimaryButton(
                label: 'Confirm Settlement (${formatPaise(enteredPaise)})',
                icon: Icons.check_circle_rounded,
                onPressed: isValid
                    ? () async {
                        await ref.read(settlementsNotifierProvider.notifier).createSettlement(
                              ledgerId: widget.friend.individualLedgerId,
                              toUserId: widget.friend.id,
                              amountPaise: enteredPaise,
                              method: _selectedMethod,
                              isPlaceholderReceiver: !widget.friend.isAppUser,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: colors.surfaceFlatRaised,
                              content: Text(
                                !widget.friend.isAppUser
                                    ? 'Settlement self-confirmed (unverified) with ${widget.friend.resolvedName}.'
                                    : 'Settlement request sent to ${widget.friend.resolvedName}!',
                                style: SplitUpTypography.body(color: colors.textPrimary),
                              ),
                            ),
                          );
                          Navigator.pop(context);
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
