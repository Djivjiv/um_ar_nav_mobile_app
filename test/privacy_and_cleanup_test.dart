import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/core/config/app_config.dart';
import 'package:um_ar_mobile_app/core/config/campus_bounds.dart';
import 'package:um_ar_mobile_app/core/utils/text_utils.dart';
import 'package:um_ar_mobile_app/data/local/offline_cache.dart';

Iterable<File> dartFiles(String dir) =>
    Directory(dir).listSync(recursive: true).whereType<File>().where(
        (f) => f.path.endsWith('.dart'));

/// Every `debugPrint(...)` and `print(...)` call in lib, as `path: code`.
List<String> logCalls() {
  final call = RegExp(r'\b(debugPrint|print)\(', multiLine: true);
  final found = <String>[];
  for (final file in dartFiles('lib')) {
    final text = file.readAsStringSync();
    for (final m in call.allMatches(text)) {
      var depth = 0;
      var i = m.end - 1;
      do {
        if (text[i] == '(') depth++;
        if (text[i] == ')') depth--;
        i++;
      } while (depth > 0 && i < text.length);
      found.add('${file.path}: ${text.substring(m.start, i)}');
    }
  }
  return found;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('logs', () {
    final calls = logCalls();

    test('the scan finds the logs', () {
      expect(calls.length, greaterThan(150));
    });

    for (final (what, pattern) in [
      ('emails', r'email'),
      ('tokens', r'idToken|accessToken|\$\{?\w*[tT]oken'),
      ('keys', r'apiKey|anonKey|webClientId|ClientId|MAPTILER'),
      ('device codes', r'deviceCode|device_code|\$code'),
      ('coordinates', r'latitude|longitude|LatLng|\.lat\b|\.lng\b'),
      ('user ids', r'\buser\.id|userId|response\.user\?\.id'),
      ('platform error details', r'e\.details'),
    ]) {
      test('print no $what', () {
        final bad = RegExp(pattern);
        expect(calls.where(bad.hasMatch), isEmpty);
      });
    }

    test('a tile error never quotes its URL, which holds the MapTiler key', () {
      final tiles =
          File('lib/data/local/campus_tile_cache.dart').readAsStringSync();

      expect(tiles, contains(r'failed: ${e.runtimeType}'));
    });

    test('a cache key is logged without its id', () async {
      final logged = <String>[];
      final saved = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
      addTearDown(() => debugPrint = saved);

      await OfflineCache().save('user_profile:secret-id', Object());

      expect(logged.single, contains('"user_profile"'));
      expect(logged.single, isNot(contains('secret-id')));
    });
  });

  group('iOS', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    test('asks for when-in-use location only', () {
      expect(plist, contains('NSLocationWhenInUseUsageDescription'));
      expect(plist, isNot(contains('NSLocationAlways')));
    });
  });

  group('one of each', () {
    test('the 150 m limit', () {
      expect(maxOnCampusGpsMeters, 150);
      // InstructionService's own 150 is a step length, not a GPS limit.
      final declared = RegExp(r'^const double \w+ = 150;', multiLine: true);
      expect(
        dartFiles('lib').where((f) => declared.hasMatch(f.readAsStringSync())),
        hasLength(1),
      );
    });

    test('cleanText', () {
      expect(cleanText(null), isNull);
      expect(cleanText('   '), isNull);
      expect(cleanText(' a b '), 'a b');
    });

    test('the login time key', () {
      expect(
        dartFiles('lib')
            .where((f) => f.readAsStringSync().contains("'login_time'")),
        hasLength(1),
      );
    });

    test('the campus gate on the way to the map', () {
      final copies = dartFiles('lib').where((f) =>
          f.readAsStringSync().contains("context.go('/map');\n    _gating") ||
          f.readAsStringSync().contains("context.go('/map');\r\n    _gating"));
      expect(copies, hasLength(1));
    });

    test('the app version, which matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('version: ${AppConfig.appVersion}+'));
      expect(
        dartFiles('lib/presentation')
            .where((f) => f.readAsStringSync().contains("'1.0.0'")),
        isEmpty,
      );
    });
  });

}
