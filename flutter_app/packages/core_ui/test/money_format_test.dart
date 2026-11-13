import 'package:core_ui/core_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RvmMoney.fromPaise', () {
    final cases = <int, String>{
      0: '₹0',
      1: '₹0.01',
      10: '₹0.10',
      99: '₹0.99',
      100: '₹1',
      101: '₹1.01',
      99999: '₹999.99',
      100000: '₹1,000',
      1000000: '₹10,000',
      10000000: '₹1,00,000',
      123456789: '₹12,34,567.89',
      1000000000: '₹1,00,00,000',
      12345678901: '₹12,34,56,789.01',
    };
    cases.forEach((paise, rupees) {
      test('$paise paise is $rupees', () {
        expect(RvmMoney.fromPaise(paise), rupees);
      });
    });

    test('a negative amount puts the minus before the rupee sign', () {
      expect(RvmMoney.fromPaise(-1), '-₹0.01');
      expect(RvmMoney.fromPaise(-99), '-₹0.99');
      expect(RvmMoney.fromPaise(-100), '-₹1');
      expect(RvmMoney.fromPaise(-100000), '-₹1,000');
      expect(RvmMoney.fromPaise(-123456789), '-₹12,34,567.89');
    });

    test('zero paise has no minus and no fraction', () {
      expect(RvmMoney.fromPaise(-0), '₹0');
    });

    test('the largest amount keeps every digit, with no rounding', () {
      // 9223372036854775807 paise, the largest 64-bit int.
      expect(RvmMoney.fromPaise(9223372036854775807),
          '₹92,23,37,20,36,85,47,758.07');
    });

    test('the smallest amount works although its negation does not fit', () {
      // -9223372036854775808 paise, the smallest 64-bit int.
      expect(RvmMoney.fromPaise(-9223372036854775807 - 1),
          '-₹92,23,37,20,36,85,47,758.08');
    });

    test('the rupee figure groups the last three digits, then pairs', () {
      for (final (paise, expected) in [
        (100, '₹1'),
        (1000, '₹10'),
        (10000, '₹100'),
        (100000, '₹1,000'),
        (1000000, '₹10,000'),
        (10000000, '₹1,00,000'),
        (100000000, '₹10,00,000'),
      ]) {
        expect(RvmMoney.fromPaise(paise), expected);
      }
    });
  });
}
