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
    expect(p['advances'], [{'id': 'a1', 'amount': 300}, {'id': 'a2', 'amount': 100}]);
    expect([p['gross'], p['totalDeductions'], p['net']], [3517.5, 662.5, 2855]);
    expect(p['capExceeded'], false);

    final joiner = payslip(worker: {...w, 'joined': '2026-09-16'}, month: '2026-09', attendance: [], overtime: [], deductions: [], advances: [], s: s);
    expect([joiner['employedDays'], joiner['base']], [15, 1500]);
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
