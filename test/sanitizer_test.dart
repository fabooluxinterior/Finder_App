import 'package:finder_app/core/sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flags and strips contact info', () {
    for (final s in [
      'call me 98470 12345',
      '+91-9847012345',
      'dm @rohan.codes',
      'insta: rohan_99',
      'my insta is rohan_99',
      'whatsapp - rohan99',
      'see https://x.co/abc',
      'www.example.com',
      'mysite.in',
    ]) {
      expect(ContactSanitizer.containsContactInfo(s), isTrue, reason: s);
      expect(ContactSanitizer.containsContactInfo(ContactSanitizer.sanitize(s)), isFalse, reason: s);
    }
  });

  test('leaves ordinary text alone', () {
    for (final s in ['I am 24, love biryani at 8pm', 'I love Instagram photography', 'Snapchat filters are fun', 'Kochi → Munnar trip in 2025!', 'email me? no.']) {
      expect(ContactSanitizer.containsContactInfo(s), isFalse, reason: s);
      expect(ContactSanitizer.sanitize(s), s);
    }
  });
}
