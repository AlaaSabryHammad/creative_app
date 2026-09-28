import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:creative_app/core/i18n.dart';
import 'package:creative_app/data/store.dart';
import 'package:creative_app/ui/login.dart';

// The first-sign-in screen renders in every worker language on a small phone and rejects weak / mismatched passwords
// before calling the server.
void main() {
  testWidgets('force password screen', (t) async {
    store.me = {'id': 'u1', 'name': 'Rajesh Kumar', 'worker_id': 'W-1002', 'active': true, 'must_change_pw': true};
    expect(store.mustChangePw, isTrue);
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    for (final l in workerLangs.keys) {
      lang = l;
      await t.pumpWidget(MaterialApp(home: Directionality(textDirection: rtlLangs.contains(l) ? TextDirection.rtl : TextDirection.ltr, child: ForcePasswordScreen(key: ValueKey(l)))));
      final fields = find.byType(TextField);
      await t.enterText(fields.at(0), '1234');
      await t.ensureVisible(find.text(tr('saveContinue')));
      await t.tap(find.text(tr('saveContinue')));
      await t.pump();
      expect(find.text(tr('passwordRule')), findsNWidgets(2));  // helper text + the error
      await t.enterText(fields.at(0), 'abc12345');
      await t.enterText(fields.at(1), 'abc12399');
      await t.ensureVisible(find.text(tr('saveContinue')));
      await t.tap(find.text(tr('saveContinue')));
      await t.pump();
      expect(find.text(tr('passwordMismatch')), findsOneWidget);
    }
  });
}
