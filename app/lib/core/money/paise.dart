/// Pure money formatting and calculation helpers in integer paise.
class MoneyUtils {
  /// Converts integer paise to Indian Rupee formatted string.
  /// Example: 12000000 paise -> "1,20,000" or "₹1,20,000"
  /// Example: 1250 paise -> "12.50" or "₹12.50"
  static String formatPaise(
    int paise, {
    bool includeSymbol = true,
    bool showSign = false,
    bool forceDecimals = false,
  }) {
    final isNegative = paise < 0;
    final absPaise = paise.abs();
    final rupees = absPaise ~/ 100;
    final fractionalPaise = absPaise % 100;

    final formattedRupees = formatIndianRupees(rupees);
    String result;
    if (fractionalPaise > 0 || forceDecimals) {
      result = '$formattedRupees.${fractionalPaise.toString().padLeft(2, '0')}';
    } else {
      result = formattedRupees;
    }

    final prefix = isNegative
        ? '-'
        : (showSign && paise > 0 ? '+' : '');

    final symbol = includeSymbol ? '₹' : '';

    return '$prefix$symbol$result';
  }

  /// Formats an integer rupee amount using Indian number grouping (lakhs, crores).
  /// e.g. 120000 -> "1,20,000", 10000000 -> "1,00,00,000"
  static String formatIndianRupees(int amount) {
    if (amount < 0) return '-${formatIndianRupees(amount.abs())}';
    final str = amount.toString();
    if (str.length <= 3) return str;

    final last3 = str.substring(str.length - 3);
    var remaining = str.substring(0, str.length - 3);
    final parts = <String>[];

    while (remaining.length > 2) {
      parts.insert(0, remaining.substring(remaining.length - 2));
      remaining = remaining.substring(0, remaining.length - 2);
    }
    if (remaining.isNotEmpty) {
      parts.insert(0, remaining);
    }

    return '${parts.join(',')},$last3';
  }

  /// Parses an amount string (e.g. "1200" or "12.50") into integer paise.
  static int? parseToPaise(String input) {
    final clean = input.replaceAll('₹', '').replaceAll('Rs', '').replaceAll(',', '').trim();
    if (clean.isEmpty) return null;
    final parts = clean.split('.');
    if (parts.length > 2) return null;

    final rupees = int.tryParse(parts[0]);
    if (rupees == null) return null;

    int paise = rupees * 100;
    if (parts.length == 2) {
      var fracStr = parts[1];
      if (fracStr.length > 2) fracStr = fracStr.substring(0, 2);
      if (fracStr.length == 1) fracStr += '0';
      final frac = int.tryParse(fracStr) ?? 0;
      paise += frac;
    }
    return paise;
  }
}

String formatPaise(int paise, {bool includeSymbol = true, bool showSign = false}) =>
    MoneyUtils.formatPaise(paise, includeSymbol: includeSymbol, showSign: showSign);
