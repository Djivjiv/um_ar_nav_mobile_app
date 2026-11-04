import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/core/utils/postgrest_filter.dart';

void main() {
  group('sanitizeIlikeTerm', () {
    test('plain text is unchanged (trimmed)', () {
      expect(sanitizeIlikeTerm('  Room 101 '), 'Room 101');
    });

    test('commas, brackets, quotes and backslashes become wildcards', () {
      expect(sanitizeIlikeTerm('Room 101 (Lab)'), 'Room 101 %Lab%');
      expect(sanitizeIlikeTerm('a,b'), 'a%b');
      expect(sanitizeIlikeTerm(r'x"y\z'), 'x%y%z');
    });

    test('runs of reserved characters collapse to one wildcard', () {
      expect(sanitizeIlikeTerm('a,(),b'), 'a%b');
    });

    test('no reserved characters survive', () {
      final out = sanitizeIlikeTerm(r'),or(id.gt.0),"\');
      expect(out.contains(RegExp(r'[,()"\\]')), isFalse);
    });

    test('nothing searchable left returns empty', () {
      expect(sanitizeIlikeTerm('   '), '');
      expect(sanitizeIlikeTerm('(),'), '');
      expect(sanitizeIlikeTerm('%%'), '');
    });
  });
}
