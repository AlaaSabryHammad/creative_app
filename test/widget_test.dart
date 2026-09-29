import 'package:creative_app/data/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:creative_app/core/logic.dart';
import 'package:creative_app/core/pay.dart';

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

  // Same figures as the web check: cumulative fills in from the previous claim; progress = cumulative ÷ contract.
  test('claim totals', () {
    final t = claimTotals([
      {'id': 'b', 'no': '2', 'from': '2026-09-01', 'to': '2026-09-28', 'amount': '4100000', 'status': 'submitted'},
      {'id': 'a', 'no': '1', 'from': '2026-08-01', 'to': '2026-08-31', 'amount': '6200000', 'deductions': '620000', 'status': 'paid'},
    ], '48500000');
    expect(t.list.map((r) => r.c['no']), ['1', '2']);
    expect(t.cum, 10300000);
    expect(t.pct!.round(), 21);
    expect((t.paid, t.due, t.remaining), (5580000, 4100000, 38200000));
    // a percentage written on the latest claim wins
    expect(claimTotals([{'no': '1', 'amount': '100', 'progress': '35'}], '1000').pct, 35);
  });

  test('payroll period: company month from the 26th, custom range, mid-period joiner', () {
    expect(period('2026-10', 26), ('2026-09-26', '2026-10-25', 30));
    expect(period('2026-01', 26), ('2025-12-26', '2026-01-25', 31));
    expect(period('2026-02', 1), ('2026-02-01', '2026-02-28', 28));
    expect((periodMonth('2026-09-30', 26), periodMonth('2026-09-25', 26), periodMonth('2026-12-26', 26)), ('2026-10', '2026-09', '2027-01'));
    const s = PaySettings(startDay: 26);
    Json slip(Json w, {String? from, String? to}) => payslip(worker: w, month: '2026-10', from: from, to: to, attendance: [
          {'worker_id': 'W1', 'date': '2026-09-27', 'status': 'absent'}, {'worker_id': 'W1', 'date': '2026-10-27', 'status': 'absent'},
        ], overtime: const [], deductions: const [], advances: const [], s: s);
    final m = slip({'id': 'W1', 'salary': 3000});
    expect((m['base'], (m['days'] as Map)['absent'], m['from']), (3000, 1, '2026-09-26'));
    expect(slip({'id': 'W1', 'salary': 3000}, from: '2026-10-01', to: '2026-10-15')['base'], 1500);
    expect(slip({'id': 'W1', 'salary': 3000, 'joined': '2026-10-16'})['base'], 1000);
  });
}
