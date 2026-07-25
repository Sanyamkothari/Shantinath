import 'package:flutter_test/flutter_test.dart';
import 'package:shantinath_agro/utils/amount_in_words.dart';

void main() {
  group('rupeesToWords — Indian numbering', () {
    test('the amount from the reference invoice', () {
      expect(rupeesToWords(19800), 'Nineteen Thousand Eight Hundred');
    });

    test('zero and single digits', () {
      expect(rupeesToWords(0), 'Zero');
      expect(rupeesToWords(7), 'Seven');
    });

    test('teens and tens do not collide', () {
      expect(rupeesToWords(15), 'Fifteen');
      expect(rupeesToWords(50), 'Fifty');
      expect(rupeesToWords(19), 'Nineteen');
      expect(rupeesToWords(90), 'Ninety');
    });

    test('compound tens', () {
      expect(rupeesToWords(21), 'Twenty One');
      expect(rupeesToWords(99), 'Ninety Nine');
    });

    test('hundreds, with no "and" (matches the Tally print)', () {
      expect(rupeesToWords(100), 'One Hundred');
      expect(rupeesToWords(101), 'One Hundred One');
      expect(rupeesToWords(999), 'Nine Hundred Ninety Nine');
    });

    test('lakh and crore groupings, not millions', () {
      expect(rupeesToWords(100000), 'One Lakh');
      expect(rupeesToWords(1000000), 'Ten Lakh');
      expect(rupeesToWords(10000000), 'One Crore');
      expect(rupeesToWords(1234567),
          'Twelve Lakh Thirty Four Thousand Five Hundred Sixty Seven');
    });

    test('beyond 99 crore recurses instead of truncating', () {
      expect(rupeesToWords(1000000000), 'One Hundred Crore');
      expect(rupeesToWords(9990000000), 'Nine Hundred Ninety Nine Crore');
    });

    test('skips empty groups rather than emitting stray words', () {
      expect(rupeesToWords(10000007), 'One Crore Seven');
      expect(rupeesToWords(100005), 'One Lakh Five');
    });
  });

  group('amountInWords — invoice line', () {
    test('whole rupees match the reference invoice exactly', () {
      expect(amountInWords(19800), 'INR Nineteen Thousand Eight Hundred Only');
    });

    test('paise are appended when present', () {
      expect(amountInWords(19800.50),
          'INR Nineteen Thousand Eight Hundred and Fifty Paise Only');
      expect(amountInWords(1.05), 'INR One and Five Paise Only');
    });

    test('rounds to paise before splitting, so 19799.999 is not read down', () {
      expect(amountInWords(19799.999),
          'INR Nineteen Thousand Eight Hundred Only');
    });

    test('floating point noise does not leak into the words', () {
      // 0.1 + 0.2 == 0.30000000000000004
      expect(amountInWords(0.1 + 0.2), 'INR Zero and Thirty Paise Only');
    });

    test('currency prefix can be dropped', () {
      expect(amountInWords(500, currency: ''), 'Five Hundred Only');
    });

    test('negatives are marked rather than silently flipped', () {
      expect(amountInWords(-250), 'INR Minus Two Hundred Fifty Only');
    });
  });
}
