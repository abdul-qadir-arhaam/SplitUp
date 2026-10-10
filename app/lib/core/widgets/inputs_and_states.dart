import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

class AmountInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final bool autofocus;

  const AmountInput({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = '0',
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: colors.glassFillStrong,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.glassBorder, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '₹',
            style: SplitUpTypography.displayAmount(
              color: colors.accentBrass,
            ).copyWith(fontSize: 36),
          ),
          const SizedBox(width: 8),
          IntrinsicWidth(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: autofocus,
              onChanged: onChanged,
              style: SplitUpTypography.displayAmount(
                color: colors.textPrimary,
              ).copyWith(fontSize: 38),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: SplitUpTypography.displayAmount(
                  color: colors.textMuted.withValues(alpha: 0.5),
                ).copyWith(fontSize: 38),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String status;

  const StatusChip({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Color bg;
    Color text;

    switch (status.toUpperCase()) {
      case 'CONFIRMED':
      case 'ACTIVE':
        bg = colors.accentReceive.withValues(alpha: 0.18);
        text = colors.accentReceive;
        break;
      case 'PENDING':
        bg = colors.statusWarn.withValues(alpha: 0.18);
        text = colors.statusWarn;
        break;
      case 'REJECTED':
      case 'OUTDATED':
        bg = colors.accentOwe.withValues(alpha: 0.18);
        text = colors.accentOwe;
        break;
      case 'COMPLETED':
        bg = colors.accentBrass.withValues(alpha: 0.18);
        text = colors.accentBrass;
        break;
      default:
        bg = colors.surfaceFlatRaised;
        text = colors.textMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: text.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        status.toUpperCase(),
        style: SplitUpTypography.caption(color: text).copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.glassFill,
                shape: BoxShape.circle,
                border: Border.all(color: colors.glassBorder, width: 1),
              ),
              child: Icon(icon, size: 40, color: colors.textSecondary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: SplitUpTypography.title(color: colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: SplitUpTypography.body(color: colors.textMuted),
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class SegmentedControl<T> extends StatelessWidget {
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onSelected;

  const SegmentedControl({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelected,
  }) : assert(values.length == labels.length);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceFlatRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: List.generate(values.length, (index) {
          final val = values[index];
          final label = labels[index];
          final isSelected = val == selected;

          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(val),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? colors.glassFillStrong : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: colors.glassBorder, width: 1)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: SplitUpTypography.label(
                    color: isSelected ? colors.textPrimary : colors.textMuted,
                  ).copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
