import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:creative_app/core/custody.dart';
import 'package:creative_app/core/i18n.dart';
import 'package:creative_app/data/store.dart';
import 'package:creative_app/ui/screens/my_custody.dart';

Map<String, dynamic> _item(String d, num q, num r) => {'desc': d, 'unit': 'pcs', 'qty': q, 'rate': r};

// The same data and figures as the web app's custody tests (src/custody.jsx): 5000 given, 828 + 184 spent, 500 returned.
final _txs = <Map<String, dynamic>>[
  {'id': 'a1', 'type': 'give', 'holderId': 'h1', 'date': '2026-09-28', 'amount': 5000, 'method': 'تحويل بنكي', 'at': '1'},
  {'id': 'a2', 'type': 'expense', 'holderId': 'h1', 'date': '2026-10-01', 'projectId': 'p1', 'supplier': 'مؤسسة الإنشاءات', 'number': '1042', 'cat': 'مواد بناء', 'vatRate': '15', 'items': [_item('أسمنت', 40, 18)], 'at': '2'},
  {'id': 'a3', 'type': 'expense', 'holderId': 'h1', 'date': '2026-10-03', 'projectId': '', 'supplier': 'محطة وقود', 'vatRate': '15', 'items': [_item('بنزين', 1, 160)], 'at': '3'},
  {'id': 'a4', 'type': 'return', 'holderId': 'h1', 'date': '2026-10-12', 'amount': 500, 'at': '4'},
];

void main() {
  setUpAll(() => initializeDateFormatting());

  group('custody maths', () {
    test('invoice totals: items, discount, VAT and the default 15% for an empty rate', () {
      final v = invTotals({'items': [_item('a', 2, 100), _item('b', 1, 50)], 'discount': '50', 'vatRate': ''});
      expect(v.sub, 250);
      expect(v.disc, 50);
      expect(v.taxable, 200);
      expect(v.vat, 30);
      expect(v.total, 230);
      expect(invTotals({'items': [_item('a', 1, 100)], 'vatRate': '0'}).total, 100);
      expect(invTotals({'items': [_item('a', 1, 100)], 'discount': 500}).total, 0, reason: 'a discount larger than the invoice never goes negative');
    });

    test('pending and rejected invoices are listed but never counted in the balance', () {
      final pending = {'id': 'p1', 'type': 'expense', 'holderId': 'h1', 'date': '2026-10-20', 'supplier': 'x', 'vatRate': '15', 'items': [_item('a', 1, 1000)], 'status': 'pending', 'at': '9'};
      final rejected = {...pending, 'id': 'p2', 'status': 'rejected'};
      final approved = {...pending, 'id': 'p3', 'status': 'approved'};
      final base = custodyTotals(_txs);
      expect(custodyTotals([..._txs, pending, rejected]).balance, base.balance);
      expect(custodyTotals([..._txs, approved]).spent, base.spent + 1150);
      expect(deltaOf(pending), 0);
      expect(statusOf(_txs[1]), 'approved', reason: 'older invoices without a status are approved');
      expect(custodyLedger([..._txs, pending]).last.$2, custodyLedger(_txs).last.$2, reason: 'the running balance does not move');
    });

    test('totals and balance of an account', () {
      final t = custodyTotals(_txs);
      expect(t.given, 5000);
      expect(t.spent, 1012); // 828 on a project + 184 outside
      expect(t.spentProject, 828);
      expect(t.spentOutside, 184);
      expect(t.returned, 500);
      expect(t.balance, 3488);
    });

    test('ledger runs the balance in time order; an opening balance (signed) is part of it', () {
      final l = custodyLedger([..._txs, {'id': 'o', 'type': 'open', 'holderId': 'h1', 'date': '2026-01-01', 'amount': -150, 'at': '0'}]);
      expect(l.first.$1['type'], 'open');
      expect([for (final r in l) r.$2], [-150, 4850, 4022, 3838, 3338]);
      expect(custodyTotals(l.map((r) => r.$1)).opening, -150);
    });
  });

  group('My custody screen', () {
    Future<void> show(WidgetTester tester) async {
      lang = 'ar';
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MyCustodyScreen())));
    }

    tearDown(() => store.myCustody = {});

    testWidgets('empty state when the user holds no custody', (tester) async {
      store.myCustody = {};
      await show(tester);
      expect(find.text(tr('cuEmpty')), findsOneWidget);
    });

    testWidgets('shows the balance, the totals and the ledger; tapping an invoice opens its details', (tester) async {
      store.myCustody = {
        'holders': [{'id': 'h1', 'name': 'محمد أحمد'}],
        'txs': _txs,
        'archive': [{'id': 'z1', 'holderId': 'h1', 'year': 2025, 'mode': 'carry', 'balance': 10}],
        'projects': {'p1': 'برج الريان'},
      };
      await show(tester);
      expect(find.text(tr('cuHeld')), findsOneWidget); // positive balance: still with the person
      expect(find.text('3,488 ${tr('sar')}'), findsWidgets);
      expect(find.text(tr('cuGiven')), findsOneWidget);
      expect(find.text('مؤسسة الإنشاءات · #1042'), findsOneWidget);
      // Pills are rich text (icon + text), hence findRichText.
      expect(find.textContaining('برج الريان', findRichText: true), findsOneWidget); // project name from the my_custody() projects map
      expect(find.textContaining(tr('cuOutside'), findRichText: true), findsWidgets); // the fuel invoice has no project
      expect(find.text(tr('cuArchive')), findsOneWidget);
      expect(find.text('2025'), findsOneWidget);

      // Filter: only returns.
      await tester.tap(find.text(tr('cuReturn')).first);
      await tester.pump();
      expect(find.text('مؤسسة الإنشاءات · #1042'), findsNothing);

      // Back to all, then open the invoice.
      await tester.tap(find.text(tr('cuAll')));
      await tester.pump();
      await tester.tap(find.text('مؤسسة الإنشاءات · #1042'));
      await tester.pumpAndSettle();
      expect(find.text(tr('cuTotal')), findsOneWidget);
      expect(find.text('828 ${tr('sar')}'), findsWidgets);
      expect(find.text('أسمنت'), findsOneWidget);
    });

    testWidgets('a negative balance reads as owed to the person', (tester) async {
      store.myCustody = {
        'holders': [{'id': 'h1', 'name': 'x'}],
        'txs': [
          {'id': 'g', 'type': 'give', 'holderId': 'h1', 'date': '2026-01-01', 'amount': 100, 'at': '1'},
          {'id': 'e', 'type': 'expense', 'holderId': 'h1', 'date': '2026-01-02', 'projectId': '', 'supplier': 's', 'vatRate': '0', 'items': [_item('i', 1, 250)], 'at': '2'},
        ],
      };
      await show(tester);
      expect(find.text(tr('cuOwed')), findsOneWidget);
      expect(find.text('150 ${tr('sar')}'), findsWidgets);
    });
  });
}
