import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:creative_app/core/i18n.dart';
import 'package:creative_app/data/update.dart';

Updater _u(int build, Map<String, dynamic>? info, {bool offline = false, TargetPlatform? platform}) =>
    Updater(build: () async => build, fetch: () async => offline ? throw Exception('offline') : info, platform: platform);

const _info = {'min_build': 5, 'url_android': 'https://example.com/app.apk', 'url_ios': 'https://example.com/ios', 'message': 'تحديث مهم'};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('forced update', () {
    test('a build below the minimum must update, with the platform link and message', () async {
      final u = _u(3, _info);
      await u.check();
      expect(u.required, isTrue);
      expect(u.url, 'https://example.com/app.apk');
      expect(u.message, 'تحديث مهم');
      final ios = _u(3, _info, platform: TargetPlatform.iOS);
      await ios.check();
      expect(ios.url, 'https://example.com/ios');
    });

    test('the minimum build itself and newer builds run normally', () async {
      final a = _u(5, _info)..check();
      await a.check();
      expect(a.required, isFalse);
      final b = _u(9, _info);
      await b.check();
      expect(b.required, isFalse);
    });

    test('no minimum set, or no answer and nothing remembered, never blocks', () async {
      final none = _u(1, {'min_build': 0, 'url_android': '', 'url_ios': '', 'message': ''});
      await none.check();
      expect(none.required, isFalse);
      final down = _u(1, null, offline: true);
      await down.check();
      expect(down.required, isFalse, reason: 'a server outage must not lock everybody out');
    });

    test('offline, the last answer is remembered so an old build stays blocked', () async {
      await _u(3, _info).check();  // online once: saved
      final offline = _u(3, null, offline: true);
      await offline.check();
      expect(offline.required, isTrue);
      expect(offline.url, 'https://example.com/app.apk');
    });

    test('raising the minimum later blocks a running app, lowering it releases it', () async {
      var info = {..._info, 'min_build': 3};
      final u = Updater(build: () async => 4, fetch: () async => info);
      await u.check();
      expect(u.required, isFalse);
      info = {..._info, 'min_build': 6};
      await u.check();
      expect(u.required, isTrue);
      info = {..._info, 'min_build': 0};
      await u.check();
      expect(u.required, isFalse);
    });
  });

  testWidgets('the blocking screen covers the app, shows the button and ignores taps underneath', (tester) async {
    lang = 'ar';
    var taps = 0;
    final u = _u(3, _info);
    await u.check();
    await tester.pumpWidget(MaterialApp(home: UpdateGuard(updater: u, child: Scaffold(body: Center(child: ElevatedButton(onPressed: () => taps++, child: const Text('under')))))));
    expect(find.text(tr('updTitle')), findsOneWidget);
    expect(find.text('تحديث مهم'), findsOneWidget);
    expect(find.text(tr('updNow')), findsOneWidget);
    await tester.tap(find.text('under'), warnIfMissed: false);
    expect(taps, 0);
    // Once the app is up to date the screen disappears and the app works again.
    final ok = _u(9, _info);
    await ok.check();
    await tester.pumpWidget(MaterialApp(home: UpdateGuard(updater: ok, child: Scaffold(body: Center(child: ElevatedButton(onPressed: () => taps++, child: const Text('under')))))));
    expect(find.text(tr('updTitle')), findsNothing);
    await tester.tap(find.text('under'));
    expect(taps, 1);
  });
}
