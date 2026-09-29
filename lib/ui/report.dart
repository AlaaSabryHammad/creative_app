import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/i18n.dart' show lang;
import '../core/logic.dart';
import '../core/pay.dart';
import '../core/theme.dart';
import '../data/store.dart';
import 'widgets.dart';

/// Label lookup: the worker app passes its translations, the staff app keeps the Arabic text.
typedef Tr = String Function(String key, String ar);
String _ar(String key, String ar) => ar;

/// A payroll month (from the company's start day, e.g. the 26th to the 25th) or a custom from–to period.
class Period {
  final String month;
  final (String, String)? custom;
  const Period(this.month, [this.custom]);
  (String, String) bounds(int startDay) {
    if (custom != null) return custom!;
    final (f, l, _) = period(month, startDay);
    return (f, l);
  }
}

/// Month / custom-period switch with the month arrows or the date-range button (web: OTPeriodPick).
class PeriodBar extends StatelessWidget {
  final Period value;
  final ValueChanged<Period> onChanged;
  final Tr t;
  const PeriodBar({super.key, required this.value, required this.onChanged, this.t = _ar});
  @override
  Widget build(BuildContext context) {
    final sd = store.pay.startDay, max = periodMonth(todayIso(), sd);
    final (first, last) = value.bounds(sd);
    String d(String iso, {bool y = false}) => DateFormat(y ? 'd MMM y' : 'd MMM', lang).format(DateTime.parse(iso));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [ButtonSegment(value: false, label: Text(t('month', 'شهر'))), ButtonSegment(value: true, label: Text(t('customPeriod', 'من تاريخ إلى تاريخ')))],
        selected: {value.custom != null},
        onSelectionChanged: (s) => onChanged(Period(value.month, s.first ? (first, last) : null)),
      ),
      const SizedBox(height: 8),
      if (value.custom == null)
        Row(children: [
          IconButton(onPressed: () => onChanged(Period(addMonths(value.month, -1))), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Column(children: [
            Text(DateFormat('MMMM y', lang).format(DateTime.parse('${value.month}-01')), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            if (sd > 1) Text('${d(first)} — ${d(last, y: true)}', style: const TextStyle(fontSize: 12, color: C.fg3)),
          ])),
          IconButton(onPressed: value.month.compareTo(max) >= 0 ? null : () => onChanged(Period(addMonths(value.month, 1))), icon: const Icon(Icons.chevron_right)),
        ])
      else
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_outlined),
          label: Text('${t('from', 'من')} ${d(first)} ${t('to', 'إلى')} ${d(last, y: true)}'),
          onPressed: () async {
            final r = await showDateRangePicker(
              context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 366)),
              initialDateRange: DateTimeRange(start: DateTime.parse(first), end: DateTime.parse(last)),
            );
            if (r == null) return;
            final f = DateFormat('yyyy-MM-dd').format(r.start), l = DateFormat('yyyy-MM-dd').format(r.end);
            onChanged(Period(l.substring(0, 7), (f, l)));
          },
        ),
    ]);
  }
}

/// The rows a report shows for from..to: attendance, overtime (entry shape), deductions, advances.
typedef ReportRows = ({List<Json> att, List<Json> ot, List<Json> ded, List<Json> adv});

/// A worker's attendance, overtime, meals, deductions and advances in a period (web: OTWorkerReport).
/// [money] shows amounts and the period's net estimate.
class WorkerReportPage extends StatefulWidget {
  final Json worker;
  final bool money;
  final Tr t;
  final Future<ReportRows> Function(String from, String to) load;
  const WorkerReportPage({super.key, required this.worker, required this.load, this.money = true, this.t = _ar});
  @override
  State<WorkerReportPage> createState() => _WorkerReportPageState();
}

class _WorkerReportPageState extends State<WorkerReportPage> {
  late Period _per = Period(periodMonth(todayIso(), store.pay.startDay));
  ReportRows? _rows;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (f, l) = _per.bounds(store.pay.startDay);
    setState(() { _rows = null; _err = ''; });
    try {
      final r = await widget.load(f, l);
      if (mounted && _per.bounds(store.pay.startDay) == (f, l)) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t, w = widget.worker, r = _rows;
    return Scaffold(
      appBar: AppBar(title: Text(t('myReport', 'تقرير العامل')), bottom: PreferredSize(preferredSize: const Size.fromHeight(18), child: Text(str(w['name']), style: const TextStyle(color: C.fg3)))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        PeriodBar(value: _per, t: t, onChanged: (p) { _per = p; _load(); }),
        const SizedBox(height: 12),
        if (_err.isNotEmpty) CardBox(child: Text(_err, style: const TextStyle(color: C.danger))),
        if (r == null && _err.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
        if (r != null) ..._body(r),
      ]),
    );
  }

  List<Widget> _body(ReportRows r) {
    final t = widget.t, w = widget.worker, money = widget.money;
    final p = payslip(worker: w, month: _per.month, from: _per.custom?.$1, to: _per.custom?.$2, attendance: r.att, overtime: r.ot, deductions: r.ded, advances: const [], s: store.pay);
    final days = Map<String, dynamic>.from(p['days'] as Map), ot = p['overtime'] as Map, meals = p['meals'] as Map;
    final pendingOt = r.ot.where((e) => e['status'] == 'pending').fold<double>(0, (a, e) => a + toNum(e['hours']));
    String sar(num v) => '${fmtNum(round2(v))} ${t('sar', 'ر.س')}';
    String h(num v) => '${fmtNum(v)} ${t('h', 'س')}';
    Tone st(String s) => s == 'approved' ? Tone.green : s == 'rejected' ? Tone.red : Tone.orange;
    String stL(String s) => t(s, const {'approved': 'معتمد', 'rejected': 'مرفوض', 'pending': 'بانتظار الاعتماد'}[s] ?? s);
    const att = {'present': (Tone.green, 'حاضر'), 'absent': (Tone.red, 'غائب'), 'leave': (Tone.blue, 'إجازة'), 'sick': (Tone.orange, 'مرضية'), 'off': (Tone.slate, 'راحة')};
    final dates = {...r.att.map((a) => str(a['date'])), ...r.ot.map((e) => str(e['date'])), ...r.ded.map((d) => str(d['date']))}.toList()..sort((a, b) => b.compareTo(a));
    final deducted = toNum(p['absence']) + toNum(p['deductionsTotal']);
    return [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in att.entries) Pill('${t(e.key, e.value.$2)} ${days[e.key]}', tone: e.value.$1),
        Pill(t('recorded', '{n} يوم مسجّل').replaceAll('{n}', '${days['recorded']}')),
      ]),
      const SizedBox(height: 12),
      StatGrid([
        StatTile(tone: Tone.green, icon: Icons.bolt, label: t('overtime', 'العمل الإضافي'), value: h(toNum(ot['hours'])),
            sub: [if (money) sar(toNum(ot['amount'])), if (pendingOt > 0) '${t('pending', 'بانتظار الاعتماد')} ${h(pendingOt)}'].join(' · ')),
        StatTile(tone: Tone.blue, icon: Icons.restaurant_outlined, label: t('meals', 'الوجبات'), value: '${toNum(meals['breakfast']) + toNum(meals['lunch'])}',
            sub: '${t('breakfast', 'فطار')} ${meals['breakfast']} · ${t('lunch', 'غداء')} ${meals['lunch']}${money ? ' · ${sar(toNum(meals['amount']))}' : ''}'),
        StatTile(tone: Tone.red, icon: Icons.remove_circle_outline, label: t('deductions', 'الخصومات'), value: money ? sar(deducted) : '${(p['deductions'] as List).length}',
            sub: '${t('absent', 'غياب')} ${days['absent']}'),
        if (money)
          StatTile(tone: Tone.orange, icon: Icons.account_balance_wallet_outlined, label: t('periodNet', 'صافي الفترة (تقديري)'), value: sar(toNum(p['gross']) - deducted), sub: '${t('salary', 'الراتب')} ${sar(toNum(p['base']))}')
        else
          StatTile(tone: Tone.orange, icon: Icons.volunteer_activism_outlined, label: t('advances', 'السلف'), value: '${r.adv.length}'),
      ]),
      const SizedBox(height: 12),
      if (dates.isEmpty) CardBox(child: EmptyState(t('noData', 'لا توجد سجلات في هذه الفترة'))),
      for (final d in dates)
        () {
          final a = r.att.where((x) => x['date'] == d).firstOrNull;
          final es = r.ot.where((x) => x['date'] == d), ds = r.ded.where((x) => x['date'] == d);
          final look = att[str(a?['status'])];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CardBox(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(DateFormat('EEE d MMM', lang).format(DateTime.parse(d)), style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (look != null) Pill(t(str(a!['status']), look.$2), tone: look.$1),
                ]),
                if (a?['breakfast'] == true || a?['lunch'] == true)
                  IconText(Icons.restaurant, [if (a?['breakfast'] == true) t('breakfast', 'فطار'), if (a?['lunch'] == true) t('lunch', 'غداء')].join(' · ')),
                for (final e in es)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                    const Icon(Icons.bolt, size: 16, color: C.primary),
                    Expanded(child: Text(' ${t('overtime', 'إضافي')} ${h(toNum(e['hours']))}${money ? ' · ${sar(toNum(e['hours']) * toNum(e['rate']))}' : ''}')),
                    Pill(stL(str(e['status'])), tone: st(str(e['status']))),
                  ])),
                for (final x in ds)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                    const Icon(Icons.remove_circle_outline, size: 16, color: C.danger),
                    Expanded(child: Text(' − ${sar(toNum(x['amount']))} · ${str(x['reason'])}', maxLines: 2, overflow: TextOverflow.ellipsis)),
                    if (x['status'] != 'approved') Pill(stL(str(x['status'])), tone: st(str(x['status']))),
                  ])),
              ]),
            ),
          );
        }(),
      if (r.adv.isNotEmpty) ...[
        SectionTitle(t('advances', 'السلف')),
        for (final a in r.adv)
          CardBox(child: Row(children: [
            Expanded(child: Text(DateFormat('d MMM y', lang).format(DateTime.parse(str(a['date']))))),
            Text(sar(toNum(a['amount'])), style: const TextStyle(fontWeight: FontWeight.w800)),
          ])),
      ],
      if (money) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t('estimate', 'تقديري — يصبح نهائيًا بعد اعتماد المسيّر'), style: const TextStyle(fontSize: 12, color: C.fg3))),
    ];
  }
}
