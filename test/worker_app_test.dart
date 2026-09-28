import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:creative_app/core/i18n.dart';
import 'package:creative_app/core/logic.dart';
import 'package:creative_app/data/store.dart';
import 'package:creative_app/ui/worker/worker_app.dart';

// Renders every tab of the worker app in every language on a small phone; any overflow or
// exception fails the test.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    final m = monthIso(), t = todayIso();
    store.me = {'id': 'u1', 'name': 'Rajesh Kumar', 'worker_id': 'W-1002', 'active': true};
    store.mine = {
      'worker': {'id': 'W-1002', 'name': 'Rajesh Kumar Subramanian', 'trade': 'حدّاد مسلح', 'p': 'p1', 'salary': 2400, 'rateMode': 'auto', 'rate': 15,
        'nat': 'هندي', 'iqama': '2412345678', 'iqamaExpiry': t, 'joined': '2021-05-10', 'phone': '0551234567', 'leaveOpening': 4, 'leaveFrom': '$m-01'},
      'project': {'id': 'p1', 'name': 'برج الريان السكني — المرحلة الثانية', 'site': 'حفر الباطن'},
      'vehicle': {'plate': 'أ ب ج 1234', 'make': 'Toyota', 'model': 'Hilux'},
      'company': {'name': 'مؤسسة إبراهيم حميدي العنزي للمقاولات'},
      'settings': {'meals': {'breakfast': 5, 'lunch': 15}},
      'paidOt': [],
    };
    store.myAtt = [
      for (var d = 1; d <= 9; d++)
        {'id': 'a$d', 'worker_id': 'W-1002', 'date': '$m-0$d', 'status': d == 3 ? 'absent' : d == 5 ? 'leave' : 'present', 'breakfast': d != 3 && d != 5, 'lunch': d != 3 && d != 5, 'breakfast_price': 5, 'lunch_price': 15},
    ];
    store.myDed = [{'id': 'd1', 'worker_id': 'W-1002', 'date': '$m-02', 'kind': 'hours', 'hours': 1, 'amount': 10, 'reason': 'تأخير عن بداية الدوام', 'status': 'approved'}];
    store.myAdv = [{'id': 'v1', 'worker_id': 'W-1002', 'amount': 900, 'installment': 300, 'repaid': 300, 'start_month': m, 'status': 'active'}];
    store.myReq = [
      {'id': 'r1', 'kind': 'leave', 'date_from': '$m-20', 'date_to': '$m-25', 'text': 'سفر', 'status': 'pending', 'reply': '', 'created_at': '${t}T08:00:00Z'},
      {'id': 'r2', 'kind': 'advance', 'amount': 600, 'installments': 2, 'text': '', 'status': 'approved', 'reply': 'تمت الموافقة، يبدأ الخصم الشهر القادم', 'created_at': '${t}T07:00:00Z'},
    ];
    store.myNotes = [
      for (final (i, k, d) in [
        (1, 'ot_new', {'date': t, 'hours': 2, 'status': 'pending'}), (2, 'ot_approved', {'date': t, 'hours': 2}), (3, 'ot_rejected', {'date': t, 'hours': 2, 'note': 'لا يوجد تكليف'}),
        (4, 'ot_changed', {'date': t, 'hours': 3}), (5, 'ot_deleted', {'date': t, 'hours': 3}), (6, 'att', {'date': t, 'status': 'present', 'breakfast': true, 'lunch': true}),
        (7, 'att_deleted', {'date': t}), (8, 'ded', {'date': t, 'amount': 50, 'reason': 'تأخير'}), (9, 'ded_cancelled', {'date': t, 'amount': 50}),
        (10, 'adv', {'amount': 600, 'installment': 300, 'month': m}), (11, 'adv_cancelled', {'amount': 600}), (12, 'req_approved', {'kind': 'leave', 'reply': 'ok'}),
        (13, 'req_rejected', {'kind': 'advance', 'reply': ''}), (14, 'slip', {'month': m, 'net': 2455}), (15, 'slip_paid', {'month': m, 'net': 2455}),
        (16, 'slip_withdrawn', {'month': m}), (17, 'data', {'fields': ['salary', 'rate', 'iban']}), (18, 'vehicle', {'plate': 'أ ب ج 1234'}), (19, 'vehicle_removed', {'plate': 'أ ب ج 1234'}),
      ])
        {'id': i, 'kind': k, 'data': d, 'created_at': '${t}T08:${'$i'.padLeft(2, '0')}:00Z', 'read_at': i > 3 ? '${t}T09:00:00Z' : null},
    ];
    store.mySlips = [{'id': 's1', 'month': '2026-08', 'worker_id': 'W-1002', 'net': 2455, 'paid': true, 'data': {
      'workerId': 'W-1002', 'name': 'Rajesh Kumar Subramanian', 'month': '2026-08', 'base': 2400, 'salary': 2400, 'net': 2455, 'gross': 2855, 'totalDeductions': 400,
      'days': {'present': 25, 'absent': 1, 'leave': 2, 'sick': 1, 'off': 2}, 'overtime': {'hours': 12, 'amount': 180}, 'meals': {'breakfast': 25, 'lunch': 25, 'amount': 500},
      'absence': 80, 'deductions': [{'reason': 'تأخير', 'date': '2026-08-04', 'amount': 20}], 'advancesTotal': 300}}];
  });

  for (final code in workerLangs.keys) {
    testWidgets('worker app renders in $code', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 740 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      lang = code;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(code),
        supportedLocales: [for (final l in workerLangs.keys) Locale(l)],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: const WorkerShell(),
      ));
      await tester.pump();
      expect(find.text(tr('net')), findsWidgets);
      await tester.scrollUntilVisible(find.text(tr('gratuity')), 200);
      expect(find.text(tr('gratuity')), findsOneWidget);
      for (final tab in ['attendance', 'pay', 'requests', 'account', 'home']) {
        await tester.tap(find.text(tr(tab)).last);
        await tester.pump(const Duration(milliseconds: 400));
      }
      // Pay tab sub-views and the request form.
      await tester.tap(find.text(tr('pay')).last);
      await tester.pump(const Duration(milliseconds: 400));
      for (final v in ['overtime', 'deductions', 'advances', 'payslips']) {
        final chip = find.widgetWithText(ChoiceChip, tr(v));
        await tester.ensureVisible(chip);
        await tester.pump();
        await tester.tap(chip);
        await tester.pump(const Duration(milliseconds: 300));
      }
      // A payslip opens its full breakdown in this language.
      await tester.tap(find.text(tr('paid')).first);
      await tester.pumpAndSettle();
      expect(find.text(tr('net')), findsWidgets);
      await tester.tapAt(const Offset(180, 30));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('requests')).last);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(tr('newRequest')));
      await tester.pumpAndSettle();
      expect(find.text(tr('send')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('notifications in $code', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 740 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      lang = code;
      // Every kind has a title and a text with all placeholders filled.
      for (final n in store.myNotes) {
        final (title, body) = noticeText(n);
        expect(title.isNotEmpty && body.isNotEmpty && !body.contains('{'), isTrue, reason: '${n['kind']} → $body');
      }
      await tester.pumpWidget(MaterialApp(
        locale: Locale(code),
        supportedLocales: [for (final l in workerLangs.keys) Locale(l)],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: const WorkerShell(),
      ));
      await tester.pump();
      await tester.tap(find.byTooltip(tr('notifications')));
      await tester.pumpAndSettle();
      expect(find.text(tr('notifications')), findsWidgets);
      final last = find.text(noticeText(store.myNotes.last).$2);
      await tester.scrollUntilVisible(last, 300);
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      // Tapping a notice opens its tab (vehicle → home).
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(find.text(tr('net')), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
