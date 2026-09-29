import 'dart:math' as math;
import 'logic.dart';

/// Salary, overtime, meals, deductions and leave rules — a port of the web app's src/pay.js
/// (keep the two in step; see docs/API.md §7 in the web project).
/// Salaries are monthly: a day = salary / monthDays, an hour = a day / dayHours.
class PaySettings {
  final double breakfast, lunch, monthDays, dayHours, otMultiplier, deductionCap, annual, annualAfter5, gpsRadius;
  /// Payroll month start: 1 = the calendar month, 26 = the 26th to the 25th.
  final int startDay;
  final bool mealsDefault;
  const PaySettings({
    this.breakfast = 5, this.lunch = 15, this.mealsDefault = true,
    this.monthDays = 30, this.dayHours = 8, this.otMultiplier = 1.5, this.deductionCap = 50,
    this.annual = 21, this.annualAfter5 = 30, this.gpsRadius = 300, this.startDay = 1,
  });

  /// Stored settings with the payroll defaults filled in.
  factory PaySettings.from(Json s) {
    Json g(String k) => Map<String, dynamic>.from((s[k] as Map?) ?? const {});
    double n(Json m, String k, double d) => m[k] == null ? d : toNum(m[k]);
    final meals = g('meals'), pay = g('pay'), leave = g('leave');
    return PaySettings(
      breakfast: n(meals, 'breakfast', 5), lunch: n(meals, 'lunch', 15), mealsDefault: s['mealsDefault'] != false,
      monthDays: n(pay, 'monthDays', 30), dayHours: n(pay, 'dayHours', 8), otMultiplier: n(pay, 'otMultiplier', 1.5), deductionCap: n(pay, 'deductionCap', 50),
      startDay: n(pay, 'startDay', 1).round().clamp(1, 28),
      annual: n(leave, 'annual', 21), annualAfter5: n(leave, 'annualAfter5', 30), gpsRadius: n(s, 'gpsRadius', 300),
    );
  }
}

double round2(num v) => (v * 100).roundToDouble() / 100;

double dailyWage(Json w, PaySettings s) => toNum(w['salary']) / s.monthDays;
/// Saudi Labor Law art. 107: an overtime hour = the hourly wage + 50% of the basic hourly wage.
double autoRate(Json w, PaySettings s) => round2(dailyWage(w, s) / s.dayHours * s.otMultiplier);
/// Overtime hourly rate: from the salary when the worker is on 'auto', otherwise the manual rate.
double otRate(Json w, PaySettings s) => w['rateMode'] == 'auto' && toNum(w['salary']) > 0 ? autoRate(w, s) : toNum(w['rate']);
/// Normal hourly wage (deductions in hours); estimated from the overtime rate without a salary.
double hourlyWage(Json w, PaySettings s) => round2(toNum(w['salary']) > 0 ? dailyWage(w, s) / s.dayHours : toNum(w['rate']) / s.otMultiplier);

/// 'YYYY-MM' ± n months.
String addMonths(String ym, int n) {
  final t = int.parse(ym.substring(0, 4)) * 12 + int.parse(ym.substring(5, 7)) - 1 + n;
  return '${t ~/ 12}-${'${t % 12 + 1}'.padLeft(2, '0')}';
}

/// First day, last day and length of a month.
(String, String, int) monthBounds(String ym) {
  final days = DateTime(int.parse(ym.substring(0, 4)), int.parse(ym.substring(5, 7)) + 1, 0).day;
  return ('$ym-01', '$ym-${'$days'.padLeft(2, '0')}', days);
}

/// Days from one ISO date to another, both included.
int daysIn(String from, String to) => DateTime.utc(int.parse(to.substring(0, 4)), int.parse(to.substring(5, 7)), int.parse(to.substring(8, 10)))
        .difference(DateTime.utc(int.parse(from.substring(0, 4)), int.parse(from.substring(5, 7)), int.parse(from.substring(8, 10))))
        .inDays + 1;

/// The payroll period of [ym] when the company month starts on [startDay] (see pay.js otPeriod):
/// 26 = the 26th of the previous month to the 25th of [ym].
(String, String, int) period(String ym, int startDay) {
  if (startDay <= 1) return monthBounds(ym);
  String pad(int n) => '$n'.padLeft(2, '0');
  final first = '${addMonths(ym, -1)}-${pad(startDay)}', last = '$ym-${pad(startDay - 1)}';
  return (first, last, daysIn(first, last));
}

/// The payroll month a date belongs to (on or after the start day = the next month).
String periodMonth(String date, int startDay) =>
    startDay > 1 && int.parse(date.substring(8, 10)) >= startDay ? addMonths(date.substring(0, 7), 1) : date.substring(0, 7);

/// One worker's month (same shape as payslips.data). attendance/deductions/advances are table rows;
/// overtime uses the app's entry shape; paidOtIds = overtime already paid through overtime payouts.
/// The project a worker's month belongs to (see pay.js otMainProject): where most attendance days were
/// (the latest wins a tie), else most overtime days — workers are not assigned to one project.
String mainProject(List<Json> att, List<Json> overtime) {
  final rows = att.isNotEmpty ? [for (final a in att) (str(a['project_id']), str(a['date']))] : [for (final e in overtime) (str(e['projectId']), str(e['date']))];
  final n = <String, (int, String)>{};
  for (final (p, d) in rows) {
    if (p.isEmpty) continue;
    final x = n[p] ?? (0, '');
    n[p] = (x.$1 + 1, d.compareTo(x.$2) > 0 ? d : x.$2);
  }
  final best = n.entries.toList()..sort((a, b) => a.value.$1 != b.value.$1 ? b.value.$1 - a.value.$1 : b.value.$2.compareTo(a.value.$2));
  return best.isEmpty ? '' : best.first.key;
}

/// [from]/[to] = a custom period instead of the payroll month: the salary is then paid per day in it.
Json payslip({required Json worker, required String month, String? from, String? to, required List<Json> attendance, required List<Json> overtime,
    required List<Json> deductions, required List<Json> advances, Set<String> paidOtIds = const {}, required PaySettings s}) {
  final custom = from != null && to != null;
  final (first, last, monthLen) = custom ? (from, to, daysIn(from, to)) : period(month, s.startDay);
  bool inMonth(dynamic d) => str(d).compareTo(first) >= 0 && str(d).compareTo(last) <= 0;
  final id = str(worker['id']);
  final salary = toNum(worker['salary']);
  final daily = salary / s.monthDays;
  final joined = str(worker['joined']);
  final employed = joined.compareTo(first) > 0 ? (joined.compareTo(last) > 0 ? 0 : daysIn(joined, last)) : monthLen;
  final base = employed < monthLen || custom ? round2(daily * math.min(employed, s.monthDays)) : salary;

  final att = attendance.where((a) => a['worker_id'] == id && inMonth(a['date'])).toList();
  int count(String st) => att.where((a) => a['status'] == st).length;
  final absent = count('absent');
  final absence = round2(absent * daily);
  final bf = att.where((a) => a['breakfast'] == true).toList(), ln = att.where((a) => a['lunch'] == true).toList();
  final meals = round2(bf.fold<double>(0, (a, x) => a + toNum(x['breakfast_price'])) + ln.fold<double>(0, (a, x) => a + toNum(x['lunch_price'])));

  final otAll = overtime.where((e) => e['workerId'] == id && e['status'] == 'approved' && inMonth(e['date'])).toList();
  final ot = otAll.where((e) => !paidOtIds.contains(e['id'])).toList();
  final otAmount = round2(ot.fold<double>(0, (a, e) => a + toNum(e['hours']) * toNum(e['rate'])));
  final byDay = <String, double>{'normal': 0, 'friday': 0, 'holiday': 0};
  for (final e in ot) { byDay[str(e['dayType'])] = (byDay[str(e['dayType'])] ?? 0) + toNum(e['hours']); }

  final ded = deductions.where((d) => d['worker_id'] == id && d['status'] == 'approved' && inMonth(d['date'])).toList();
  final dedTotal = round2(ded.fold<double>(0, (a, d) => a + toNum(d['amount'])));
  final adv = [
    for (final a in advances.where((a) => a['worker_id'] == id && a['status'] == 'active' && str(a['start_month']).compareTo(month) <= 0))
      {'id': a['id'], 'amount': round2(math.min(toNum(a['installment']), toNum(a['amount']) - toNum(a['repaid'])))},
  ].where((a) => toNum(a['amount']) > 0).toList();
  final advTotal = round2(adv.fold<double>(0, (a, x) => a + toNum(x['amount'])));

  final gross = round2(base + otAmount + meals);
  final totalDeductions = round2(absence + dedTotal + advTotal);
  return {
    'workerId': id, 'name': worker['name'], 'trade': worker['trade'], 'project': mainProject(att, otAll), 'iqama': worker['iqama'] ?? '',
    'month': month, 'from': first, 'to': last, 'salary': salary, 'base': base, 'dailyWage': round2(daily), 'employedDays': math.min(employed, monthLen),
    'days': {'recorded': att.length, 'present': count('present'), 'absent': absent, 'leave': count('leave'), 'sick': count('sick'), 'off': count('off')},
    'overtime': {'hours': ot.fold<double>(0, (a, e) => a + toNum(e['hours'])), 'amount': otAmount, 'count': ot.length, 'byDay': byDay,
      'paidSeparately': round2(otAll.where((e) => paidOtIds.contains(e['id'])).fold<double>(0, (a, e) => a + toNum(e['hours']) * toNum(e['rate'])))},
    'otIds': [for (final e in ot) e['id']],
    'meals': {'breakfast': bf.length, 'lunch': ln.length, 'amount': meals},
    'absence': absence,
    'deductions': [for (final d in ded) {'id': d['id'], 'date': d['date'], 'kind': d['kind'], 'hours': toNum(d['hours']), 'amount': toNum(d['amount']), 'reason': d['reason']}],
    'deductionsTotal': dedTotal,
    'advances': adv,
    'advancesTotal': advTotal,
    'gross': gross,
    'totalDeductions': totalDeductions,
    'net': round2(gross - totalDeductions),
    'capExceeded': totalDeductions > gross * s.deductionCap / 100,
  };
}

/// Annual leave balance in days (see pay.js otLeaveBalance).
double leaveBalance(Json w, List<String> leaveDays, PaySettings s, String today) {
  final starts = [str(w['joined']), str(w['leaveFrom'])].where((x) => x.isNotEmpty).toList()..sort();
  if (starts.isEmpty || starts.last.compareTo(today) > 0) return toNum(w['leaveOpening']);
  final start = starts.last;
  double yrs(String a, String b) => DateTime.parse(b).difference(DateTime.parse(a)).inDays / 365;
  final years = yrs(start, today);
  final served = str(w['joined']).isNotEmpty ? yrs(str(w['joined']), today) : years;
  final before5 = math.max(0.0, math.min(years, 5 - (served - years)));
  final accrued = before5 * s.annual + (years - before5) * s.annualAfter5;
  final taken = leaveDays.where((d) => d.compareTo(start) >= 0).length;
  return ((toNum(w['leaveOpening']) + accrued - taken) * 10).roundToDouble() / 10;
}

/// End-of-service award (see pay.js otGratuity): art. 84 half a month per year for 5 years then a full month,
/// art. 85 on resignation: none under 2 years, 1/3 for 2–5, 2/3 for 5–10, all from 10. reason: 'end' | 'resign'.
/// Years of service: whole anniversaries plus the remaining days as a fraction of a year.
double serviceYears(String from, String to) {
  final a = DateTime.parse('${from}T00:00:00Z'), b = DateTime.parse('${to}T00:00:00Z');
  final years = b.year - a.year - (b.month < a.month || (b.month == a.month && b.day < a.day) ? 1 : 0);
  return years + b.difference(DateTime.utc(a.year + years, a.month, a.day)).inDays / 365;
}

({double years, double full, double share, double amount})? gratuity(Json w, String end, [String reason = 'end']) {
  final salary = toNum(w['salary']), joined = str(w['joined']);
  if (joined.isEmpty || salary <= 0 || end.isEmpty || end.compareTo(joined) < 0) return null;
  final years = serviceYears(joined, end);
  final full = salary / 2 * math.min(years, 5) + salary * math.max(0, years - 5);
  final share = reason != 'resign' ? 1.0 : years < 2 ? 0.0 : years < 5 ? 1 / 3 : years < 10 ? 2 / 3 : 1.0;
  return (years: (years * 100).roundToDouble() / 100, full: round2(full), share: share, amount: round2(full * share));
}

/// Great-circle distance in metres.
double distanceM(double lat1, double lng1, double lat2, double lng2) {
  const r = math.pi / 180, earth = 6371000.0;
  final a = math.pow(math.sin((lat2 - lat1) * r / 2), 2) + math.cos(lat1 * r) * math.cos(lat2 * r) * math.pow(math.sin((lng2 - lng1) * r / 2), 2);
  return (2 * earth * math.asin(math.sqrt(a))).roundToDouble();
}
