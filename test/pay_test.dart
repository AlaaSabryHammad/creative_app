import 'package:flutter_test/flutter_test.dart';
import 'package:creative_app/core/logic.dart';
import 'package:creative_app/core/pay.dart';

// Same fixtures and expected figures as the web app's payroll checks (src/pay.js), so both apps agree.
void main() {
  const s = PaySettings();
  final w = {'id': 'W-1', 'name': 'Ali', 'salary': 3000, 'rateMode': 'auto', 'rate': 20, 'joined': '2024-01-01', 'p': 'p1'};

  test('rates', () {
    expect(PaySettings.from({'meals': {'breakfast': 5}}).lunch, 15);
    expect(autoRate(w, s), 18.75);
    expect(otRate(w, s), 18.75);
    expect(otRate({...w, 'rateMode': 'manual'}, s), 20);
    expect(otRate({'id': 'old', 'rate': 25}, s), 25);
    expect(otRate({...w, 'salary': 0}, s), 20);
    expect(hourlyWage(w, s), 12.5);
    expect(hourlyWage({'rate': 30}, s), 20);
  });

  test('months', () {
    expect(monthBounds('2026-02'), ('2026-02-01', '2026-02-28', 28));
    expect([addMonths('2026-09', 1), addMonths('2026-09', -1), addMonths('2026-12', 1), addMonths('2026-01', -1), addMonths('2026-03', -14)],
        ['2026-10', '2026-08', '2027-01', '2025-12', '2025-01']);
  });

  test('payslip', () {
    final att = <Map<String, dynamic>>[];
    for (var d = 1; d <= 30; d++) {
      final date = '2026-09-${'$d'.padLeft(2, '0')}';
      final status = d == 3 || d == 4 ? 'absent' : d == 5 ? 'leave' : 'present';
      att.add({'worker_id': 'W-1', 'date': date, 'status': status, 'breakfast': status == 'present' && d <= 21, 'lunch': status == 'present' && d <= 19, 'breakfast_price': 5, 'lunch_price': 15});
    }
    att.add({'worker_id': 'W-2', 'date': '2026-09-01', 'status': 'absent', 'breakfast': false, 'lunch': false});
    att.add({'worker_id': 'W-1', 'date': '2026-10-01', 'status': 'absent', 'breakfast': false, 'lunch': false});
    final ot = [
      {'id': 'OT-1', 'workerId': 'W-1', 'date': '2026-09-10', 'hours': 6, 'rate': 18.75, 'status': 'approved', 'dayType': 'normal'},
      {'id': 'OT-2', 'workerId': 'W-1', 'date': '2026-09-11', 'hours': 4, 'rate': 18.75, 'status': 'approved', 'dayType': 'friday'},
      {'id': 'OT-3', 'workerId': 'W-1', 'date': '2026-09-12', 'hours': 2, 'rate': 18.75, 'status': 'approved', 'dayType': 'normal'},
      {'id': 'OT-4', 'workerId': 'W-1', 'date': '2026-09-13', 'hours': 3, 'rate': 18.75, 'status': 'pending', 'dayType': 'normal'},
    ];
    final ded = [
      {'id': 'd1', 'worker_id': 'W-1', 'date': '2026-09-07', 'kind': 'hours', 'hours': 1, 'amount': 12.5, 'reason': 'x', 'status': 'approved'},
      {'id': 'd2', 'worker_id': 'W-1', 'date': '2026-09-08', 'kind': 'amount', 'hours': 0, 'amount': 50, 'reason': 'y', 'status': 'approved'},
      {'id': 'd3', 'worker_id': 'W-1', 'date': '2026-09-09', 'kind': 'amount', 'hours': 0, 'amount': 999, 'reason': 'z', 'status': 'pending'},
    ];
    final adv = [
      {'id': 'a1', 'worker_id': 'W-1', 'amount': 900, 'installment': 300, 'repaid': 0, 'start_month': '2026-09', 'status': 'active'},
      {'id': 'a2', 'worker_id': 'W-1', 'amount': 500, 'installment': 200, 'repaid': 400, 'start_month': '2026-06', 'status': 'active'},
      {'id': 'a3', 'worker_id': 'W-1', 'amount': 500, 'installment': 200, 'repaid': 0, 'start_month': '2026-10', 'status': 'active'},
      {'id': 'a4', 'worker_id': 'W-1', 'amount': 500, 'installment': 200, 'repaid': 0, 'start_month': '2026-01', 'status': 'cancelled'},
    ];
    final p = payslip(worker: w, month: '2026-09', attendance: att, overtime: ot, deductions: ded, advances: adv, paidOtIds: {'OT-3'}, s: s);
    expect(p['days'], {'recorded': 30, 'present': 27, 'absent': 2, 'leave': 1, 'sick': 0, 'off': 0});
    expect(p['absence'], 200);
    expect(p['meals'], {'breakfast': 18, 'lunch': 16, 'amount': 330, 'breakfastAmount': 90, 'lunchAmount': 240});
    expect([p['overtime']['hours'], p['overtime']['amount'], p['overtime']['paidSeparately']], [10, 187.5, 37.5]);
    expect(p['otIds'], ['OT-1', 'OT-2']);
    expect(p['deductionsTotal'], 62.5);
    expect(p['advances'], [{'id': 'a1', 'amount': 300, 'kind': 'advance', 'reason': ''}, {'id': 'a2', 'amount': 100, 'kind': 'advance', 'reason': ''}]);
    expect([p['gross'], p['totalDeductions'], p['net']], [3517.5, 662.5, 2855]);
    expect(p['capExceeded'], false);

    final joiner = payslip(worker: {...w, 'joined': '2026-09-16'}, month: '2026-09', attendance: [], overtime: [], deductions: [], advances: [], s: s);
    expect([joiner['employedDays'], joiner['base']], [15, 1500]);
  });

  test('days not yet in an approved payroll: from the day after the last payroll ends until today', () {
    const s26 = PaySettings(startDay: 26);
    Json slip(String month, [String? to]) => {'month': month, 'data': {'to': ?to}};
    // A payroll approved for 26 Aug – 25 Sep: the next days start on the 26th.
    expect(unpaidStart([slip('2026-09', '2026-09-25')], s26, '2026-10-12'), ('2026-09-26', '2026-09-25'));
    // The latest payslip wins, whatever the list order; a custom period ending mid-month starts the day after.
    expect(unpaidStart([slip('2026-10', '2026-10-25'), slip('2026-09', '2026-09-25'), slip('2026-10', '2026-10-20')], s26, '2026-10-27'), ('2026-10-26', '2026-10-25'));
    expect(unpaidStart([slip('2026-09', '2026-10-20')], s26, '2026-10-27'), ('2026-10-21', '2026-10-20'));
    // Month and year ends roll over.
    expect(unpaidStart([slip('2026-12', '2026-12-31')], s, '2027-01-05'), ('2027-01-01', '2026-12-31'));
    // Older payslips without their own dates use the end of their payroll month.
    expect(unpaidStart([slip('2026-09')], s26, '2026-10-12'), ('2026-09-26', '2026-09-25'));
    expect(unpaidStart([slip('2026-08')], s, '2026-10-12'), ('2026-09-01', '2026-08-31'));
    // No payslip yet: the current payroll period.
    expect(unpaidStart([], s26, '2026-10-12'), ('2026-09-26', ''));
    expect(unpaidStart([], s26, '2026-10-27'), ('2026-10-26', ''));
    expect(unpaidStart([], s, '2026-10-12'), ('2026-10-01', ''));

    // Overtime and meals of those days only: approved ones, not paid separately, from the 26th to today.
    final att = [
      for (final d in ['2026-09-24', '2026-09-26', '2026-09-30', '2026-10-05', '2026-10-12'])
        {'worker_id': 'W-1', 'date': d, 'status': 'present', 'breakfast': true, 'lunch': true, 'breakfast_price': 5, 'lunch_price': 15, 'approval': 'approved'},
      {'worker_id': 'W-1', 'date': '2026-10-08', 'status': 'present', 'breakfast': true, 'lunch': true, 'breakfast_price': 5, 'lunch_price': 15, 'approval': 'pending'},
      {'worker_id': 'W-1', 'date': '2026-10-13', 'status': 'present', 'breakfast': true, 'lunch': true, 'breakfast_price': 5, 'lunch_price': 15, 'approval': 'approved'},
    ];
    final ot = [
      {'id': 'o0', 'workerId': 'W-1', 'date': '2026-09-24', 'hours': 9, 'rate': 20, 'status': 'approved', 'dayType': 'normal'}, // paid in the last payroll
      {'id': 'o1', 'workerId': 'W-1', 'date': '2026-09-27', 'hours': 2, 'rate': 20, 'status': 'approved', 'dayType': 'normal'},
      {'id': 'o2', 'workerId': 'W-1', 'date': '2026-10-02', 'hours': 3, 'rate': 20, 'status': 'approved', 'dayType': 'friday'},
      {'id': 'o3', 'workerId': 'W-1', 'date': '2026-10-03', 'hours': 4, 'rate': 20, 'status': 'pending', 'dayType': 'normal'},
      {'id': 'o4', 'workerId': 'W-1', 'date': '2026-10-04', 'hours': 5, 'rate': 20, 'status': 'approved', 'dayType': 'normal'}, // paid through a payout
    ];
    final (from, _) = unpaidStart([slip('2026-09', '2026-09-25')], s26, '2026-10-12');
    final r = payslip(worker: w, month: '2026-10', from: from, to: '2026-10-12', attendance: att, overtime: ot, deductions: [], advances: [], paidOtIds: {'o4'}, s: s26);
    expect([r['overtime']['hours'], r['overtime']['amount']], [5, 100]);
    // Meals: 26 Sep, 30 Sep, 5 Oct and 12 Oct. Not counted: 24 Sep (last payroll), 8 Oct (sheet still pending), 13 Oct (after today).
    expect(r['meals'], {'breakfast': 4, 'lunch': 4, 'amount': 80, 'breakfastAmount': 20, 'lunchAmount': 60});
  });

  test('end-of-service award', () {
    ({double years, double full, double share, double amount})? g(String joined, String end, String reason) => gratuity({'salary': 3000, 'joined': joined}, end, reason);
    expect(serviceYears('2019-09-28', '2026-09-28'), 7);
    expect((serviceYears('2024-02-29', '2025-02-28') - 1).abs() < .01, true);
    expect(g('2019-09-28', '2026-09-28', 'end'), (years: 7.0, full: 13500.0, share: 1.0, amount: 13500.0));
    expect(g('2019-09-28', '2026-09-28', 'resign')!.amount, 9000);
    expect(g('2023-09-28', '2026-09-28', 'resign')!.amount, 1500);
    expect(g('2025-03-28', '2026-09-28', 'resign')!.amount, 0);
    expect(g('2025-03-28', '2026-09-28', 'end')!.amount, 2256.16);
    expect(g('2014-01-01', '2026-01-01', 'resign')!.amount, 28500);
    expect(gratuity({'salary': 0, 'joined': '2020-01-01'}, '2026-01-01'), null);
  });

  test('payslip project = where most of the month was worked', () {
    Json a(String p, String d) => {'project_id': p, 'date': d};
    expect(mainProject([a('p1', '2026-09-01'), a('p2', '2026-09-02'), a('p2', '2026-09-03')], []), 'p2');
    expect(mainProject([a('p1', '2026-09-05'), a('p2', '2026-09-02')], []), 'p1');
    expect(mainProject([a('', '2026-09-05'), a('p3', '2026-09-01')], []), 'p3');
    expect(mainProject([], [{'projectId': 'p4', 'date': '2026-09-01'}]), 'p4');
    expect(mainProject([], []), '');
    final slip = payslip(worker: {'id': 'W-1', 'salary': 3000, 'p': 'old'}, month: '2026-09', attendance: [
      {'worker_id': 'W-1', 'date': '2026-09-02', 'status': 'present', 'project_id': 'p2'},
      {'worker_id': 'W-2', 'date': '2026-09-02', 'status': 'present', 'project_id': 'p9'},
    ], overtime: [], deductions: [], advances: [], s: s);
    expect(slip['project'], 'p2');
  });

  test('leave and distance', () {
    expect(leaveBalance({'joined': '2025-01-01', 'leaveFrom': '2025-01-01', 'leaveOpening': 0}, [], s, '2026-01-01'), 21);
    expect(leaveBalance({'joined': '2018-01-01', 'leaveFrom': '2026-01-01', 'leaveOpening': 10}, ['2026-03-01', '2026-03-02', '2025-12-30'], s, '2026-07-02'), 23);
    expect(distanceM(28.4146492, 45.9701386, 28.4146492, 45.9701386), 0);
    expect((distanceM(28, 45, 29, 45) / 1000).round(), 111);
  });
}
