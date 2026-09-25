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
    final empty = projectIssues({'name': 'x'}, 0).length;
    final filled = projectIssues({'name': 'x', 'code': 'P-1', 'client': 'c', 'end': '2099-01-01'}, 1).length;
    expect(filled, empty - 4);
    expect(vehicleIssues({'status': 'maint', 'type': 'بيك أب'}).any((t) => t.contains('نوع')), isFalse);
  });
}
