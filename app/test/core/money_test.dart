import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/money/paise.dart';

void main() {
  group('MoneyUtils formatPaise tests', () {
    test('12000000 paise displays as ₹1,20,000', () {
      expect(formatPaise(12000000), '₹1,20,000');
      expect(formatPaise(12000000, includeSymbol: false), '1,20,000');
    });

    test('1250 paise displays as ₹12.50', () {
      expect(formatPaise(1250), '₹12.50');
    });

    test('0 paise displays as ₹0', () {
      expect(formatPaise(0), '₹0');
    });

    test('Negative paise formats with leading minus', () {
      expect(formatPaise(-20000), '-₹200');
      expect(formatPaise(-1250), '-₹12.50');
    });

    test('showSign flag adds + for positive amounts', () {
      expect(formatPaise(50000, showSign: true), '+₹500');
      expect(formatPaise(-50000, showSign: true), '-₹500');
      expect(formatPaise(0, showSign: true), '₹0');
    });

    test('Indian number grouping across thousands, lakhs, and crores', () {
      expect(MoneyUtils.formatIndianRupees(120), '120');
      expect(MoneyUtils.formatIndianRupees(1200), '1,200');
      expect(MoneyUtils.formatIndianRupees(120000), '1,20,000');
      expect(MoneyUtils.formatIndianRupees(1000000), '10,00,000');
      expect(MoneyUtils.formatIndianRupees(10000000), '1,00,00,000');
    });

    test('parseToPaise works for integer and decimal amounts', () {
      expect(MoneyUtils.parseToPaise('120'), 12000);
      expect(MoneyUtils.parseToPaise('12.50'), 1250);
      expect(MoneyUtils.parseToPaise('₹1,200.50'), 120050);
      expect(MoneyUtils.parseToPaise('invalid'), isNull);
    });
  });
}
