import 'package:creative_app/data/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:creative_app/core/logic.dart';

String iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

void main() {
  test('day type: holiday, Friday, normal', () {
    expect(dayType('2026-09-23', {'2026-09-23': 'اليوم الوطني'}), 'holiday');
    expect(dayType('2026-09-25', {}), 'friday'); // a Friday
    expect(dayType('2026-09-24', {}), 'normal');
  });

  test('overtime amount = hours × worker rate, no multipliers', () {
    final workers = [{'id': 'W-1', 'rate': 20}];
    expect(otAmount({'workerId': 'W-1', 'hours': 3, 'mult': 1.5}, workers), 60);
    expect(otAmount({'workerId': 'missing', 'hours': 3}, workers), 0);
  });

  test('BOQ totals cap executed quantity at the planned quantity', () {
    final t = boqTotals([
      {'qty': 200, 'rate': 25, 'done': 250},
      {'qty': '120', 'rate': '450', 'done': 30},
    ]);
    expect(t.total, 59000);
    expect(t.done, 5000 + 13500);
    expect(t.pct.toStringAsFixed(1), '31.4');
  });

  test('alerts include expired and due-soon items only', () {
    final now = DateTime.now();
    final alerts = buildAlerts(
      docs: [
        {'name': 'expired', 'expiry': iso(now.subtract(const Duration(days: 3)))},
        {'name': 'soon', 'expiry': iso(now.add(const Duration(days: 10)))},
        {'name': 'far', 'expiry': iso(now.add(const Duration(days: 300)))},
      ],
      vehicles: const [], workers: const [], projects: const [], days: 30,
    );
    expect(alerts.map((a) => a.title), ['expired', 'soon']);
    expect(alerts.first.n, -3);
  });

  test('project and vehicle notes shrink as data is filled', () {
    final empty = projectIssues({'name': 'x'}).length;
    final filled = projectIssues({'name': 'x', 'code': 'P-1', 'client': 'c', 'end': '2099-01-01'}).length;
    expect(filled, empty - 3);
    expect(vehicleIssues({'status': 'maint', 'type': 'بيك أب'}).any((t) => t.contains('نوع')), isFalse);
  });

  test('payroll and payout balances: paid vs remaining in a period', () {
    final workers = [{'id': 'W-1', 'rate': 20}, {'id': 'W-2', 'rate': 18}];
    final entries = [
      {'id': 'OT-1', 'workerId': 'W-1', 'date': '2026-09-01', 'hours': 3, 'status': 'approved', 'dayType': 'normal'},
      {'id': 'OT-2', 'workerId': 'W-1', 'date': '2026-09-05', 'hours': 2, 'status': 'approved', 'dayType': 'friday'},
      {'id': 'OT-3', 'workerId': 'W-2', 'date': '2026-09-05', 'hours': 4, 'status': 'approved', 'dayType': 'normal'},
      {'id': 'OT-4', 'workerId': 'W-2', 'date': '2026-09-06', 'hours': 2, 'status': 'pending', 'dayType': 'normal'},
      {'id': 'OT-5', 'workerId': 'W-2', 'date': '2026-08-20', 'hours': 6, 'status': 'approved', 'dayType': 'normal'},
    ];
    final paid = paidSet([{'entryIds': ['OT-1']}]);
    final (from, to) = monthRange('2026-09');
    final month = balances(entries, workers, paid, from: from, to: to);
    double sum(double Function(Balance) f) => month.fold(0, (a, b) => a + f(b));
    expect(sum((b) => b.hours), 9);
    expect(sum((b) => b.amount), 172);
    expect(sum((b) => b.paid), 60);
    expect(sum((b) => b.rem), 112);
    expect(balances(entries, workers, paid).fold<double>(0, (a, b) => a + b.hours), 15); // all periods
  });

  // A supervisor linked to their worker record keeps the staff app and also has the worker side.
  test('account kinds', () {
    store.me = {'worker_id': 'W-1', 'perms': []};
    expect((store.isWorker, store.hasWorker), (true, true));
    store.me = {'worker_id': 'W-1', 'perms': ['attendance']};
    expect((store.isWorker, store.hasWorker, store.can('attendance')), (false, true, true));
    store.me = {'worker_id': null, 'perms': ['attendance']};
    expect((store.isWorker, store.hasWorker), (false, false));
    store.me = null;
  });
}
