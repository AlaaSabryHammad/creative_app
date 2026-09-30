import 'dart:convert' show HtmlEscape, base64Encode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import '../../core/logic.dart';
import '../../core/pay.dart';
import '../../data/store.dart';

/// The landing page's logo (web: src/assets/creative-logo.png), embedded so the report needs no network.
Future<String> printLogo() async => 'data:image/png;base64,${base64Encode((await rootBundle.load('assets/print-logo.png')).buffer.asUint8List())}';

/// Print font: IBM Plex Sans Arabic (web: PRINT_FONT in src/payroll.jsx), embedded so the report needs no network.
Future<String> printFontCss() async {
  final faces = <String>[];
  for (final s in ['arabic', 'latin']) {
    for (final w in [400, 700]) {
      final b = await rootBundle.load('assets/fonts/plex-$s-$w.woff2');
      final range = s == 'arabic' ? 'U+0600-06FF,U+0750-077F,U+08A0-08FF,U+200C-200E,U+FB50-FDFF,U+FE70-FEFF' : 'U+0000-00FF,U+2000-206F';
      faces.add("@font-face{font-family:Plex;font-weight:$w;src:url(data:font/woff2;base64,${base64Encode(b.buffer.asUint8List())}) format('woff2');unicode-range:$range}");
    }
  }
  return faces.join();
}

/// The payroll as a landscape report, one row per worker (web: exportPdf in src/payroll.jsx; keep in step).
String payrollHtml(List<Json> slips, String month, String from, String to, String company, {String fontCss = '', String logo = ''}) {
  final e = const HtmlEscape().convert;
  String n(num v) => round2(v).toStringAsFixed(2);
  String dmy(String d) => d.split('-').reversed.join('-');
  final pay = store.pay;
  Map m(Json p) => p['meals'] as Map;
  Map ot(Json p) => p['overtime'] as Map;
  num meal(Json p, String k) => m(p)['${k}Amount'] ?? toNum(m(p)[k]) * (k == 'breakfast' ? pay.breakfast : pay.lunch);
  final cols = <(String, String Function(Json))>[
    ('الاسم', (p) => e(str(p['name']))), ('الراتب', (p) => n(toNum(p['base']))), ('الأيام', (p) => '${(p['days'] as Map)['present']}'),
    ('عدد أيام الفطار', (p) => '${m(p)['breakfast']}'), ('قيمة الفطار', (p) => n(meal(p, 'breakfast'))),
    ('عدد أيام الغداء', (p) => '${m(p)['lunch']}'), ('قيمة الغداء', (p) => n(meal(p, 'lunch'))),
    ('عدد الساعات', (p) => fmtNum(toNum(ot(p)['hours']))), ('قيمة الساعات الإضافية', (p) => n(toNum(ot(p)['amount']))),
    ('الإجمالي', (p) => n(toNum(ot(p)['amount']) + toNum(m(p)['amount']))), ('الاستقطاعات', (p) => n(toNum(p['totalDeductions']))),
    ('صافي المستحق', (p) => n(toNum(p['net']))),
  ];
  double sum(num Function(Json) f) => slips.fold<double>(0, (a, p) => a + f(p));
  final tot = [
    'الإجمالي (${slips.length})', n(sum((p) => toNum(p['base']))), fmtNum(sum((p) => toNum((p['days'] as Map)['present']))),
    fmtNum(sum((p) => toNum(m(p)['breakfast']))), n(sum((p) => meal(p, 'breakfast'))),
    fmtNum(sum((p) => toNum(m(p)['lunch']))), n(sum((p) => meal(p, 'lunch'))),
    fmtNum(sum((p) => toNum(ot(p)['hours']))), n(sum((p) => toNum(ot(p)['amount']))),
    n(sum((p) => toNum(ot(p)['amount']) + toNum(m(p)['amount']))), n(sum((p) => toNum(p['totalDeductions']))), n(sum((p) => toNum(p['net']))),
  ];
  final title = DateFormat('MMMM y', 'ar').format(DateTime.parse('$month-01'));
  final head = cols.map((c) => '<th>${c.$1}</th>').join();
  String cls(int i) => i == 0 ? ' class="name"' : i == cols.length - 1 ? ' class="net"' : '';
  final rows = slips.map((p) => '<tr>${[for (final (i, c) in cols.indexed) '<td${cls(i)}>${c.$2(p)}</td>'].join()}</tr>').join();
  final foot = [for (final (i, v) in tot.indexed) '<td${i == 0 ? ' class="name"' : ''}>$v</td>'].join();
  return '<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><style>$fontCss'
      'body{font-family:Plex,Tahoma,sans-serif;margin:0;color:#1e293b;-webkit-print-color-adjust:exact;print-color-adjust:exact}'
      'header{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:14px}'
      'h1{margin:0 0 6px;font-size:22px;color:#2b3a8f}.meta{color:#475569;font-size:12px;line-height:1.7;white-space:nowrap}header img{height:54px}'
      'table{width:100%;border-collapse:collapse;font-size:10px}thead{display:table-header-group}tr{page-break-inside:avoid}'
      'th{background:#3f5bd8;color:#fff;padding:7px 4px;border:1px solid #3450c4}'
      'td{padding:6px 4px;border:1px solid #cbd5e1;text-align:center;white-space:nowrap}td.name{text-align:right;white-space:normal}td.net{font-weight:700}'
      'tbody tr:nth-child(6n+1) td{background:#fff}tbody tr:nth-child(6n+2) td{background:#e8f1fd}tbody tr:nth-child(6n+3) td{background:#fdf4e3}'
      'tbody tr:nth-child(6n+4) td{background:#e7f6ea}tbody tr:nth-child(6n+5) td{background:#fbe9ef}tbody tr:nth-child(6n) td{background:#efe9fb}'
      'tfoot td{background:#e2e8f0;font-weight:700}'
      '</style></head><body>'
      '<header><div><h1>مسير رواتب $title</h1><div class="meta">${e(company)}<br>الفترة: <bdi dir="ltr">${dmy(from)} - ${dmy(to)}</bdi><br>عدد العمال: ${slips.length}</div></div>'
      '${logo.isEmpty ? '' : '<img src="$logo" alt="">'}</header>'
      '<table><thead><tr>$head</tr></thead><tbody>$rows</tbody><tfoot><tr>$foot</tr></tfoot></table>'
      '</body></html>';
}
