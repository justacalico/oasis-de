import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_ui/oasis_ui.dart';

void main() {
  group('Version.parse', () {
    test('parses plain versions', () {
      final v = Version.parse('1.2.3')!;
      expect(v.core, [1, 2, 3]);
      expect(v.pre, isNull);
      expect(v.toString(), '1.2.3');
    });

    test('strips v prefix and build metadata', () {
      expect(Version.parse('v1.2.3')!.core, [1, 2, 3]);
      expect(Version.parse('V2.0.0')!.core, [2, 0, 0]);
      expect(Version.parse('1.2.3+build.5')!.core, [1, 2, 3]);
    });

    test('parses pre-release identifiers', () {
      final v = Version.parse('1.0.0-alpha.2')!;
      expect(v.pre, ['alpha', '2']);
      expect(v.toString(), '1.0.0-alpha.2');
    });

    test('rejects invalid input', () {
      for (final s in [
        '',
        'abc',
        '1.2',
        '1.2.3.4',
        '01.2.3',
        '1.-2.3',
        '1.2.x',
        '1.0.0-',
        '1.0.0-a..b',
        '1.0.0-a_underscore',
        '1.0.0-02',
        '  ',
        'v',
      ]) {
        expect(Version.parse(s), isNull, reason: s);
      }
      expect(Version.parse(null), isNull);
      expect(Version.parse(' 1.2.3 '), isNotNull);
    });
  });

  group('Version.compareTo', () {
    test('compares core fields', () {
      expect(Version.parse('1.0.0')!.compareTo(Version.parse('2.0.0')!), lessThan(0));
      expect(Version.parse('1.2.0')!.compareTo(Version.parse('1.10.0')!), lessThan(0));
      expect(Version.parse('1.2.3')!.compareTo(Version.parse('1.2.4')!), lessThan(0));
      expect(Version.parse('2.0.0')!.compareTo(Version.parse('1.0.0')!), greaterThan(0));
    });

    test('release outranks pre-release', () {
      expect(Version.parse('1.0.0')!.compareTo(Version.parse('1.0.0-alpha')!), greaterThan(0));
      expect(Version.parse('1.0.0-alpha')!.compareTo(Version.parse('1.0.0')!), lessThan(0));
      expect(Version.parse('1.0.0-a')!.compareTo(Version.parse('1.0.0-b')!), lessThan(0));
      expect(Version.parse('1.0.0-a.1')!.compareTo(Version.parse('1.0.0-a')!), greaterThan(0));
    });

    test('numeric identifiers compare numerically and lose to strings', () {
      expect(Version.parse('1.0.0-2')!.compareTo(Version.parse('1.0.0-10')!), lessThan(0));
      expect(Version.parse('1.0.0-10')!.compareTo(Version.parse('1.0.0-2')!), greaterThan(0));
      expect(Version.parse('1.0.0-1')!.compareTo(Version.parse('1.0.0-a')!), lessThan(0));
      expect(Version.parse('1.0.0-a')!.compareTo(Version.parse('1.0.0-1')!), greaterThan(0));
    });

    test('equality and hashCode', () {
      expect(Version.parse('1.2.3'), Version.parse('v1.2.3'));
      expect(Version.parse('1.2.3')!.hashCode, Version.parse('1.2.3')!.hashCode);
      expect(Version.parse('1.2.3') == Version.parse('1.2.4'), isFalse);
      expect(Version.parse('1.2.3') == Object(), isFalse);
      expect(Version.parse('1.0.0-a'), Version.parse('1.0.0-a'));
      expect(Version.parse('1.0.0-a') == Version.parse('1.0.0'), isFalse);
      expect(Version.parse('') == Version.parse('1.0.0'), isFalse);
    });
  });
}
