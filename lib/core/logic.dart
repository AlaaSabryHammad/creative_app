import 'package:intl/intl.dart';

/// Formatting + business rules shared with the web app (see docs/API.md §7 in the web project).
typedef Json = Map<String, dynamic>;

String todayIso() => DateFormat('yyyy-MM-dd').format(DateTime.now());
String monthIso() => todayIso().substring(0, 7);

DateTime? parseDate(String? s) => (s == null || s.isEmpty) ? null : DateTime.tryParse(s);

int daysLeft(String date) {
  final d = parseDate(date);
  if (d == null) return 0;
  final t = DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(t.year, t.month, t.day)).inDays;
}

final _num = NumberFormat('#,##0.##', 'en_US');
String fmtNum(num n) => _num.format(n);
String money(num n) => '${NumberFormat('#,##0', 'en_US').format(n.round())} ر.س';
String fmtDate(String? s, {bool year = true}) {
  final d = parseDate(s);
  if (d == null) return '—';
  return DateFormat(year ? 'd MMMM y' : 'd MMMM', 'ar').format(d);
}
String monthName() => DateFormat('MMMM y', 'ar').format(DateTime.now());

double toNum(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[^\d.\-]'), '')) ?? 0;
String str(dynamic v) => v == null ? '' : '$v';

/// Day type for overtime: holiday (from settings), Friday, or normal.
String dayType(String date, Json holidays) {
  if (holidays.containsKey(date)) return 'holiday';
  return parseDate(date)?.weekday == DateTime.friday ? 'friday' : 'normal';
}

const dayLabel = {'normal': 'يوم عادي', 'friday': 'جمعة', 'holiday': 'عطلة رسمية'};
const statusLabel = {'pending': 'بانتظار الاعتماد', 'approved': 'معتمد', 'rejected': 'مرفوض'};
const projectStatus = {'active': 'قيد التنفيذ', 'hold': 'متوقف', 'done': 'مكتمل'};
const vehicleStatus = {'active': 'في الخدمة', 'maint': 'في الصيانة', 'out': 'خارج الخدمة'};
const vehicleExpiries = [['regExpiry', 'الاستمارة'], ['insExpiry', 'التأمين'], ['inspExpiry', 'الفحص الدوري']];

/// Overtime amount = hours × the hourly rate saved on the record when it was recorded (see pay.dart otRate).
double otAmount(Json e, [List<Map> workers = const []]) {
  if (e['rate'] != null) return toNum(e['hours']) * toNum(e['rate']);
  for (final w in workers) {
    if (w['id'] == e['workerId']) return toNum(e['hours']) * toNum(w['rate']);
  }
  return 0;
}

class BoqTotals {
  final double total, done;
  BoqTotals(this.total, this.done);
  double get pct => total > 0 ? done / total * 100 : 0;
}

BoqTotals boqTotals(List<dynamic>? boq) {
  double t = 0, d = 0;
  for (final r in boq ?? const []) {
    final qty = toNum(r['qty']), rate = toNum(r['rate']);
    t += qty * rate;
    d += (toNum(r['done']) < qty ? toNum(r['done']) : qty) * rate;
  }
  return BoqTotals(t, d);
}

class AlertItem {
  final String title, sub, date, screen;
  final int n;
  AlertItem(this.title, this.sub, this.date, this.screen) : n = daysLeft(date);
}

/// Everything expired or due within [days] (docs, vehicles, residencies, project deadlines).
List<AlertItem> buildAlerts({required List<Json> docs, required List<Json> vehicles, required List<Json> workers, required List<Json> projects, required int days}) {
  final out = <AlertItem>[];
  void push(String? date, String title, String sub, String screen) {
    if (date == null || date.isEmpty) return;
    if (daysLeft(date) <= days) out.add(AlertItem(title, sub, date, screen));
  }
  for (final d in docs) { push(str(d['expiry']), str(d['name']), str(d['type']), 'docs'); }
  for (final v in vehicles) {
    for (final e in vehicleExpiries) { push(str(v[e[0]]), '${e[1]} — ${v['plate']}', '${str(v['make'])} ${str(v['model'])}'.trim(), 'vehicles'); }
  }
  for (final w in workers.where((w) => w['active'] != false)) { push(str(w['iqamaExpiry']), 'إقامة ${w['name']}', '${w['id']} · ${w['trade']}', 'workers'); }
  // the worker's other dated documents (licence, passport…)
  for (final w in workers.where((w) => w['active'] != false)) {
    for (final f in (w['files'] as List?) ?? const []) {
      if (str(f['expiry']).isNotEmpty && f['expiry'] != w['iqamaExpiry']) push(str(f['expiry']), '${str(f['cat']).isEmpty ? 'مستند' : f['cat']} — ${w['name']}', '${w['id']} · ${f['name']}', 'workers');
    }
  }
  for (final p in projects.where((p) => (p['status'] ?? 'active') == 'active')) { push(str(p['end']), 'موعد تسليم ${p['name']}', str(p['client']), 'projects'); }
  out.sort((a, b) => a.n.compareTo(b.n));
  return out;
}

/// Missing key data for a project (same rules as the web).
List<String> projectIssues(Json p) {
  final out = <String>[];
  void miss(String k, String t) { if (str(p[k]).trim().isEmpty) out.add(t); }
  miss('code', 'رقم المشروع / العقد غير مسجّل');
  miss('client', 'المالك / العميل غير محدد');
  miss('site', 'موقع المشروع غير محدد');
  miss('manager', 'مدير المشروع غير محدد');
  miss('sup', 'مشرف الموقع غير محدد');
  if (toNum(p['value']) <= 0) out.add('قيمة العقد غير مسجّلة');
  miss('start', 'تاريخ بداية المشروع غير محدد');
  miss('end', 'تاريخ نهاية المشروع غير محدد');
  if (str(p['end']).isNotEmpty && (p['status'] ?? 'active') == 'active' && str(p['end']).compareTo(todayIso()) < 0) out.add('تاريخ نهاية المشروع انقضى والمشروع ما زال قيد التنفيذ');
  miss('desc', 'وصف ونطاق العمل غير مكتوب');
  final files = (p['files'] as List?) ?? [];
  if (files.isEmpty) {
    out.add('لا توجد ملفات مرفوعة للمشروع');
  } else if (!files.any((f) => str(f['cat']).contains('عقد'))) {
    out.add('لم يُرفع عقد المشروع');
  }
  if (((p['boq'] as List?) ?? []).isEmpty) out.add('لا يوجد جدول كميات للمشروع');
  return out;
}

/// Missing / expired data for a vehicle.
List<String> vehicleIssues(Json v) {
  final out = <String>[];
  void miss(String k, String t) { if (str(v[k]).trim().isEmpty) out.add(t); }
  miss('type', 'نوع المركبة غير محدد');
  miss('make', 'الشركة المصنعة غير مسجّلة');
  miss('model', 'الطراز غير مسجّل');
  miss('year', 'سنة الصنع غير مسجّلة');
  miss('color', 'اللون غير مسجّل');
  miss('vin', 'رقم الهيكل غير مسجّل');
  miss('serial', 'الرقم التسلسلي غير مسجّل');
  for (final e in vehicleExpiries) {
    final d = str(v[e[0]]);
    if (d.isEmpty) {
      out.add('تاريخ انتهاء ${e[1]} غير مسجّل');
    } else if (daysLeft(d) < 0) {
      out.add('${e[1]} منتهية منذ ${-daysLeft(d)} يوم');
    }
  }
  miss('odometer', 'قراءة العداد غير مسجّلة');
  if (v['status'] == 'active' && str(v['driver']).isEmpty) out.add('لم يُحدَّد سائق للمركبة');
  if (v['status'] == 'active' && str(v['project']).isEmpty) out.add('المركبة غير مخصصة لمشروع');
  if (((v['files'] as List?) ?? []).isEmpty) out.add('لم تُرفع صورة الاستمارة أو وثيقة التأمين');
  return out;
}

// ---------- Overtime payouts (same rules as the web: src/payments.jsx) ----------

const payMethods = {'cash': 'نقدًا', 'transfer': 'تحويل بنكي', 'cheque': 'شيك'};

/// Entry ids covered by any payout — an entry is paid when its id is in some payout's entryIds.
Set<String> paidSet(List<Map> payments) => {for (final p in payments) for (final id in (p['entryIds'] as List? ?? const [])) '$id'};

class Balance {
  final String workerId;
  double hours = 0, amount = 0, paidH = 0, paid = 0;
  final Map<String, double> byDay = {'normal': 0, 'friday': 0, 'holiday': 0};
  Balance(this.workerId);
  double get remH => hours - paidH;
  double get rem => amount - paid;
}

/// Single source for payroll + payout balances: approved overtime in [from, to] per worker,
/// split into paid and remaining.
List<Balance> balances(List<Map> entries, List<Map> workers, Set<String> paid, {String from = '', String to = '', String proj = 'all'}) {
  final out = <String, Balance>{};
  for (final e in entries) {
    final d = str(e['date']);
    if (e['status'] != 'approved' || (from.isNotEmpty && d.compareTo(from) < 0) || (to.isNotEmpty && d.compareTo(to) > 0) || (proj != 'all' && e['projectId'] != proj)) continue;
    final r = out.putIfAbsent(str(e['workerId']), () => Balance(str(e['workerId'])));
    final h = toNum(e['hours']);
    final a = otAmount(Map<String, dynamic>.from(e), workers);
    r.hours += h;
    r.amount += a;
    r.byDay[str(e['dayType'])] = (r.byDay[str(e['dayType'])] ?? 0) + h;
    if (paid.contains(str(e['id']))) {
      r.paidH += h;
      r.paid += a;
    }
  }
  return out.values.toList();
}

(String, String) monthRange(String ym) => ('$ym-01', '$ym-31');
String prevMonth() {
  final n = DateTime.now();
  return DateFormat('yyyy-MM').format(DateTime(n.year, n.month - 1, 1));
}

// ---------- Payment claims — المستخلصات (same rules as the web: src/claims.jsx) ----------

const claimStatus = {'submitted': 'مقدَّم', 'approved': 'معتمد', 'paid': 'مصروف'};

/// A claim's net payable: stated, else value − deductions + VAT.
double claimNet(Json c) => toNum(c['net']) != 0 ? toNum(c['net']) : toNum(c['amount']) - toNum(c['deductions']) + toNum(c['vat']);

class ClaimRow {
  final Json c;
  final double cum;
  final double? pct;
  ClaimRow(this.c, this.cum, this.pct);
}

class ClaimTotals {
  final List<ClaimRow> list;
  final double cum, paid, due;
  final double? pct, remaining;
  ClaimTotals(this.list, this.cum, this.pct, this.paid, this.due, this.remaining);
}

/// Claims in order with their running cumulative (stated, else previous + this claim); progress = the % written
/// on the latest claim, else cumulative ÷ contract value.
ClaimTotals claimTotals(List? claims, dynamic contract) {
  final value = toNum(contract);
  final sorted = [for (final c in claims ?? const []) Map<String, dynamic>.from(c as Map)]
    ..sort((a, b) {
      String end(Json c) => str(c['to']).isNotEmpty ? str(c['to']) : str(c['date']);
      final n = toNum(a['no']).compareTo(toNum(b['no']));
      return n != 0 ? n : end(a).compareTo(end(b));
    });
  var cum = 0.0;
  final list = [
    for (final c in sorted) ClaimRow(c, cum = toNum(c['cumulative']) > 0 ? toNum(c['cumulative']) : cum + toNum(c['amount']), value > 0 ? cum / value * 100 : null),
  ];
  final last = list.isEmpty ? null : list.last;
  final pct = last == null ? null : toNum(last.c['progress']) > 0 ? toNum(last.c['progress']).clamp(0, 100).toDouble() : last.pct?.clamp(0, 100).toDouble();
  final paid = list.where((r) => r.c['status'] == 'paid').fold<double>(0, (a, r) => a + claimNet(r.c));
  final due = list.where((r) => r.c['status'] != 'paid').fold<double>(0, (a, r) => a + claimNet(r.c));
  return ClaimTotals(list, last?.cum ?? 0, pct, paid, due, value > 0 ? (value - (last?.cum ?? 0)).clamp(0, double.infinity).toDouble() : null);
}

/// A worker's document types (worker.files[].cat); the admin can rename them in the web settings (lookups).
const workerDocTypesDefault = ['الإقامة', 'جواز السفر', 'رخصة القيادة', 'عقد العمل', 'الشهادة الصحية', 'التأمين الطبي', 'أخرى'];
