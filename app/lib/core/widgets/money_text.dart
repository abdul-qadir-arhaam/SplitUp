import 'package:flutter/material.dart';
import '../money/paise.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

enum MoneyVariant { display, title, body, label }

class MoneyText extends StatelessWidget {
  final int paise;
  final MoneyVariant variant;
  final bool showSign;
  final bool colored;
  final Color? customColor;
  final bool includeSymbol;

  const MoneyText(
    this.paise, {
    super.key,
    this.variant = MoneyVariant.title,
    this.showSign = false,
    this.colored = true,
    this.customColor,
    this.includeSymbol = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Color textColor;
    if (customColor != null) {
      textColor = customColor!;
    } else if (!colored) {
      textColor = colors.textPrimary;
    } else if (paise > 0) {
      textColor = colors.accentReceive;
    } else if (paise < 0) {
      textColor = colors.accentOwe;
    } else {
      textColor = colors.textSecondary;
    }

    final formatted = MoneyUtils.formatPaise(
      paise,
      includeSymbol: includeSymbol,
      showSign: showSign,
    );

    TextStyle style;
    switch (variant) {
      case MoneyVariant.display:
        style = SplitUpTypography.displayAmount(color: textColor);
        break;
      case MoneyVariant.title:
        style = SplitUpTypography.titleAmount(color: textColor);
        break;
      case MoneyVariant.body:
        style = SplitUpTypography.monoMedium(size: 16, color: textColor);
        break;
      case MoneyVariant.label:
        style = SplitUpTypography.monoMedium(size: 13, color: textColor);
        break;
    }

    return Text(formatted, style: style);
  }
}
