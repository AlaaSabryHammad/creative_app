import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';
import '../../core/logic.dart';
import '../../core/pay.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../report.dart';
import '../widgets.dart';
import 'payroll_pdf.dart';

/// Salary payroll for a month (web: src/payroll.jsx): the approved payslips, or a live draft.
/// Approving and reopening a month is done on the website.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  Period _per = Period(periodMonth(todayIso(), store.pay.startDay));
  String _span = '';  // the approved run's period
  (String, String)? _runDates;
  bool _loading = true;
  bool _approved = false;
  List<Json> _slips = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final month = _per.month;
    final (first, last) = _per.bounds(store.pay.startDay);
    final r = await Future.wait([
      store.fetchAll('payroll_runs', (q) => q.eq('month', month)),
      store.fetchAll('payslips', (q) => q.eq('month', month)),
      store.fetchAll('attendance', (q) => q.gte('date', first).lte('date', last)),
      store.fetchAll('deductions', (q) => q.gte('date', first).lte('date', last)),
      store.fetchAll('advances'),
    ]);
    if (!mounted) return;
    final approved = r[0].isNotEmpty;
    final touched = {for (final a in r[2]) a['worker_id']};
    final slips = approved
        ? [for (final s in r[1]) {...Map<String, dynamic>.from(s['data'] as Map), 'paid': s['paid']}]
        : [
            for (final w in store.allWorkers.where((w) => (w['active'] != false || touched.contains(w['id'])) && (str(w['joined']).isEmpty || str(w['joined']).compareTo(last) <= 0)))
              payslip(worker: w, month: month, from: _per.custom?.$1, to: _per.custom?.$2, attendance: r[2], overtime: store.entries, deductions: r[3], advances: r[4], s: store.pay),
          ];
    if (!mounted || _per.month != month) return;
    final run = approved ? r[0].first : null;
    _span = run == null || run['date_from'] == null ? '' : '${fmtDate(str(run['date_from']))} — ${fmtDate(str(run['date_to']))}';
    _runDates = run == null || run['date_from'] == null ? null : (str(run['date_from']), str(run['date_to']));
    setState(() { _approved = approved; _slips = slips..sort((a, b) => str(a['workerId']).compareTo(str(b['workerId']))); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    double tot(String k) => _slips.fold<double>(0, (a, p) => a + toNum(p[k]));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        PeriodBar(value: _per, onChanged: (p) { _per = p; _load(); }),
        if (_per.custom != null) Text('يُحفظ كمسيّر ${DateFormat('MMMM y', 'ar').format(DateTime.parse('${_per.month}-01'))}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: C.fg3)),
        const SizedBox(height: 6),
        Center(child: Pill(_approved ? 'معتمد ومقفل${_span.isEmpty ? '' : ' ($_span)'}' : 'مسودة — الاعتماد من الموقع', tone: _approved ? Tone.green : Tone.orange, icon: _approved ? Icons.lock_outline : Icons.edit_note)),
        const SizedBox(height: 12),
        if (store.scoped) const CardBox(child: EmptyState('المسيّر يعمل على مستوى المنشأة، وحسابك محدد بمشاريع معينة.')),
        if (!store.scoped) ...[
          StatGrid([
            StatTile(tone: Tone.blue, icon: Icons.account_balance_wallet_outlined, label: 'إجمالي المستحقات', value: money(tot('gross'))),
            StatTile(tone: Tone.red, icon: Icons.remove_circle_outline, label: 'إجمالي الخصومات', value: money(tot('totalDeductions'))),
            StatTile(tone: Tone.orange, icon: Icons.payments_outlined, label: 'صافي الرواتب', value: money(tot('net')), sub: '${_slips.length} عامل'),
            StatTile(tone: Tone.green, icon: Icons.restaurant_outlined, label: 'بدل الوجبات', value: money(_slips.fold<double>(0, (a, p) => a + toNum(p['meals']['amount'])))),
          ]),
          const SizedBox(height: 10),
          if (!_loading && _slips.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('تصدير PDF'),
              onPressed: () async {
                final (f, l) = _runDates ?? _per.bounds(store.pay.startDay);
                final html = payrollHtml(_slips, _per.month, f, l, str(store.company['name']), fontCss: await printFontCss(), logo: await printLogo());
                Printing.layoutPdf(name: 'مسير رواتب ${_per.month}', format: PdfPageFormat.a4.landscape,
                    // ponytail: convertHtml is deprecated but still works on Android/iOS and keeps the web's design;
                    // rebuild with package:pdf widgets (and an Arabic font) if printing drops it.
                    // ignore: deprecated_member_use
                    onLayout: (format) => Printing.convertHtml(format: format, html: html));
              },
            ),
          const SizedBox(height: 12),
          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
          if (!_loading && _slips.isEmpty) const CardBox(child: EmptyState('لا يوجد عمال في هذا المسيّر')),
          if (!_loading) for (final p in _slips) _SlipCard(p),
        ],
      ]),
    );
  }
}

class _SlipCard extends StatelessWidget {
  final Json p;
  const _SlipCard(this.p);
  @override
  Widget build(BuildContext context) {
    final w = store.worker(str(p['workerId']));
    final days = Map<String, dynamic>.from(p['days'] as Map), ot = Map<String, dynamic>.from(p['overtime'] as Map), meals = Map<String, dynamic>.from(p['meals'] as Map);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CardBox(
        onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => SlipDetails(p)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            WorkerPhoto(w?['photo'], size: 40),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(p['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${p['workerId']} · ${str(p['trade'])}', style: const TextStyle(fontSize: 12, color: C.fg3)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(toNum(p['net'])), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: C.primary700)),
              if (p['paid'] == true) const Pill('مصروف', tone: Tone.green) else if (toNum(p['salary']) <= 0) const Pill('بلا راتب', tone: Tone.orange),
            ]),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            Pill('حضور ${days['present']} · غياب ${days['absent']}'),
            Pill('إضافي ${fmtNum(toNum(ot['hours']))} س', tone: Tone.blue),
            Pill('وجبات ${money(toNum(meals['amount']))}', tone: Tone.green),
            if (toNum(p['totalDeductions']) > 0) Pill('خصومات ${money(toNum(p['totalDeductions']))}', tone: Tone.red),
            if (p['capExceeded'] == true) const Pill('الخصومات فوق نصف الأجر', tone: Tone.orange, icon: Icons.warning_amber),
          ]),
        ]),
      ),
    );
  }
}

/// Full breakdown of one payslip (also used by the worker app with translated labels).
class SlipDetails extends StatelessWidget {
  final Json p;
  final String Function(String key, String ar)? tr;
  const SlipDetails(this.p, {super.key, this.tr});
  @override
  Widget build(BuildContext context) {
    String t(String k, String ar) => tr?.call(k, ar) ?? ar;
    final ot = Map<String, dynamic>.from(p['overtime'] as Map), meals = Map<String, dynamic>.from(p['meals'] as Map), days = Map<String, dynamic>.from(p['days'] as Map);
    Widget line(String l, num v, {bool neg = false, bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: Text(l, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w500, color: strong ? C.fg1 : C.fg2))),
            Text('${neg && v > 0 ? '− ' : ''}${fmtNum(round2(v))} ${t('sar', 'ر.س')}', style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, color: neg && v > 0 ? C.danger : C.fg1)),
          ]),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('${p['name']} — ${p['month']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('${t('present', 'حضور')} ${days['present']} · ${t('absent', 'غياب')} ${days['absent']} · ${t('leave', 'إجازة')} ${days['leave']} · ${t('sick', 'مرضية')} ${days['sick']}', style: const TextStyle(color: C.fg3)),
          const Divider(height: 24),
          line(t('salary', 'الراتب'), toNum(p['base'])),
          line('${t('overtime', 'العمل الإضافي')} (${fmtNum(toNum(ot['hours']))} ${t('h', 'س')})', toNum(ot['amount'])),
          line('${t('meals', 'بدل الوجبات')} (${meals['breakfast']} + ${meals['lunch']})', toNum(meals['amount'])),
          line(t('gross', 'إجمالي المستحقات'), toNum(p['gross']), strong: true),
          const Divider(height: 20),
          line('${t('absence', 'خصم الغياب')} (${days['absent']})', toNum(p['absence']), neg: true),
          for (final d in (p['deductions'] as List? ?? const [])) line('${d['reason']} — ${d['date']}', toNum(d['amount']), neg: true),
          for (final a in (p['advances'] as List? ?? const []))
            line(a['kind'] == 'deduction' ? '${t('instDeduction', 'قسط خصم')}${str(a['reason']).isEmpty ? '' : ' — ${a['reason']}'}' : t('advance', 'قسط سلفة'), toNum(a['amount']), neg: true),
          line(t('totalDeductions', 'إجمالي الخصومات'), toNum(p['totalDeductions']), neg: true, strong: true),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(gradient: C.primaryGradient, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(child: Text(t('net', 'الصافي'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
              Text('${fmtNum(round2(toNum(p['net'])))} ${t('sar', 'ر.س')}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      ),
    );
  }
}
