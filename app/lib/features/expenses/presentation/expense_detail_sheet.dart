import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../data/expenses_repository.dart';
import '../domain/expense_model.dart';

class ExpenseDetailSheet extends ConsumerWidget {
  final ExpenseModel expense;
  final String? friendId;

  const ExpenseDetailSheet({
    super.key,
    required this.expense,
    this.friendId,
  });

  static Future<void> show(BuildContext context, ExpenseModel expense, {String? friendId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ExpenseDetailSheet(expense: expense, friendId: friendId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return Container(
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
            // Handle bar
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

            // Receipt Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surfaceFlat,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.divider),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        expense.category.toUpperCase(),
                        style: SplitUpTypography.caption(color: colors.accentBrass)
                            .copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        expense.expenseDate,
                        style: SplitUpTypography.caption(color: colors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    expense.title,
                    style: SplitUpTypography.headline(color: colors.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  MoneyText(
                    expense.totalPaise,
                    variant: MoneyVariant.title,
                    colored: false,
                  ),
                  if (expense.isDisputed) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.accentOwe.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.accentOwe.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag_rounded, size: 14, color: colors.accentOwe),
                          const SizedBox(width: 6),
                          Text(
                            'Disputed Expense',
                            style: SplitUpTypography.caption(color: colors.accentOwe)
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Payers and Splits Breakdown
            Text(
              'Breakdown',
              style: SplitUpTypography.label(color: colors.textMuted),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceFlat,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.divider),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Paid by', style: SplitUpTypography.body(color: colors.textSecondary)),
                      Text(
                        expense.payers.map((p) => p.userId == 'usr_arhaam' ? 'You' : 'Friend').join(', '),
                        style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Split method', style: SplitUpTypography.body(color: colors.textSecondary)),
                      Text(
                        expense.splitType,
                        style: SplitUpTypography.title(color: colors.accentBrass).copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Your share', style: SplitUpTypography.body(color: colors.textSecondary)),
                      Text(
                        formatPaise(expense.splits
                            .where((s) => s.userId == 'usr_arhaam' && s.included)
                            .fold(0, (sum, s) => sum + s.owedPaise)),
                        style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons: Dispute and Delete
            Row(
              children: [
                if (!expense.isDisputed)
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.accentBrass,
                        side: BorderSide(color: colors.accentBrass.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: const Text('Dispute'),
                      onPressed: () async {
                        await ref.read(expensesNotifierProvider.notifier).disputeExpense(expense.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Expense disputed. Creator has been notified.')),
                          );
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ),
                if (!expense.isDisputed) const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.accentOwe,
                      side: BorderSide(color: colors.accentOwe.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: colors.surfaceFlatRaised,
                          title: const Text('Delete Expense?'),
                          content: const Text('This will remove the expense from all ledger balances.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text('Delete', style: TextStyle(color: colors.accentOwe)),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true && context.mounted) {
                        await ref.read(expensesNotifierProvider.notifier).deleteExpense(
                              expense.id,
                              friendId: friendId,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Expense deleted successfully.')),
                          );
                          Navigator.pop(context);
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
