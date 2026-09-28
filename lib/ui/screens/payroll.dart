import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/logic.dart';
import '../../core/pay.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';

/// Salary payroll for a month (web: src/payroll.jsx): the approved payslips, or a live draft.
/// Approving and reopening a month is done on the website.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  String _month = monthIso();
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
    final (first, last, _) = monthBounds(_month);
    final r = await Future.wait([
      store.fetchAll('payroll_runs', (q) => q.eq('month', _month)),
      store.fetchAll('payslips', (q) => q.eq('month', _month)),
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
              payslip(worker: w, month: _month, attendance: r[2], overtime: store.entries, deductions: r[3], advances: r[4], paidOtIds: paidSet(store.payments), s: store.pay),
          ];
    setState(() { _approved = approved; _slips = slips..sort((a, b) => str(a['workerId']).compareTo(str(b['workerId']))); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    double tot(String k) => _slips.fold<double>(0, (a, p) => a + toNum(p[k]));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          IconButton(onPressed: () { _month = addMonths(_month, -1); _load(); }, icon: const Icon(Icons.chevron_right)),
          Expanded(child: Text(DateFormat('MMMM y', 'ar').format(DateTime.parse('$_month-01')), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          IconButton(onPressed: _month.compareTo(monthIso()) >= 0 ? null : () { _month = addMonths(_month, 1); _load(); }, icon: const Icon(Icons.chevron_left)),
        ]),
        Center(child: Pill(_approved ? 'معتمد ومقفل' : 'مسودة — الاعتماد من الموقع', tone: _approved ? Tone.green : Tone.orange, icon: _approved ? Icons.lock_outline : Icons.edit_note)),
        const SizedBox(height: 12),
        if (store.scoped) const CardBox(child: EmptyState('المسيّر يعمل على مستوى المنشأة، وحسابك محدد بمشاريع معينة.')),
        if (!store.scoped) ...[
          StatGrid([
            StatTile(tone: Tone.blue, icon: Icons.account_balance_wallet_outlined, label: 'إجمالي المستحقات', value: money(tot('gross'))),
            StatTile(tone: Tone.red, icon: Icons.remove_circle_outline, label: 'إجمالي الخصومات', value: money(tot('totalDeductions'))),
            StatTile(tone: Tone.orange, icon: Icons.payments_outlined, label: 'صافي الرواتب', value: money(tot('net')), sub: '${_slips.length} عامل'),
            StatTile(tone: Tone.green, icon: Icons.restaurant_outlined, label: 'بدل الوجبات', value: money(_slips.fold<double>(0, (a, p) => a + toNum(p['meals']['amount'])))),
          ]),
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
          if (toNum(p['advancesTotal']) > 0) line(t('advance', 'قسط سلفة'), toNum(p['advancesTotal']), neg: true),
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
