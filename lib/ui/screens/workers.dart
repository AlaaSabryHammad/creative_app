import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/logic.dart';
import '../../core/pay.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';
import '../report.dart';
import 'whatsapp.dart';
import 'worker_form.dart';

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});
  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  String _st = 'active', _q = '';
  @override
  Widget build(BuildContext context) {
    final all = store.workers;
    final list = all.where((w) => (_st == 'all' || (_st == 'active') == (w['active'] != false)) && (_q.isEmpty || str(w['name']).contains(_q) || str(w['id']).contains(_q.toUpperCase()) || str(w['iqama']).contains(_q))).toList();
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverList.list(children: [
            if (store.can('workers')) ...[
              FilledButton.icon(icon: const Icon(Icons.auto_awesome), label: const Text('إضافة عامل بالذكاء الاصطناعي'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const WorkerForm()))),
              const SizedBox(height: 12),
            ],
            FilterChips(items: [('active', 'نشط (${all.where((w) => w['active'] != false).length})'), ('inactive', 'معطّل (${all.where((w) => w['active'] == false).length})'), ('all', 'الكل (${all.length})')], value: _st, onChanged: (v) => setState(() => _st = v)),
            const SizedBox(height: 10),
            SearchField('بحث بالاسم أو الرقم أو الهوية', onChanged: (v) => setState(() => _q = v)),
            if (list.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: CardBox(child: EmptyState('لا يوجد عمال مطابقون'))),
          ]),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 270),
            itemCount: list.length,
            itemBuilder: (c, i) => _card(context, list[i]),
          ),
        ),
      ]),
    );
  }

  Widget _card(BuildContext context, Json w) {
    final active = w['active'] != false;
    final h = store.entries.where((e) => e['workerId'] == w['id'] && e['status'] == 'approved' && str(e['date']).startsWith(monthIso())).fold<double>(0, (a, e) => a + toNum(e['hours']));
    final exp = str(w['iqamaExpiry']);
    final n = exp.isEmpty ? null : daysLeft(exp);
    // the soonest other document (licence, passport…) expiring within 30 days
    final docs = [for (final f in (w['files'] as List?) ?? const []) if (str(f['expiry']).isNotEmpty && f['expiry'] != w['iqamaExpiry'] && daysLeft(str(f['expiry'])) <= 30) f]
      ..sort((a, b) => str(a['expiry']).compareTo(str(b['expiry'])));
    final doc = docs.isEmpty ? null : docs.first;
    return Opacity(
      opacity: active ? 1 : .7,
      child: CardBox(
        padding: EdgeInsets.zero,
        onTap: () => _details(context, w),
        child: Stack(children: [
          Container(height: 64, decoration: const BoxDecoration(gradient: LinearGradient(colors: [C.primary50, Color(0xFFFDF2F8)]))),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
            child: Column(children: [
              Container(decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.white, spreadRadius: 4)]), child: WorkerPhoto(w['photo'], size: 76)),
              const SizedBox(height: 8),
              Text(str(w['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              Pill(str(w['trade']), tone: Tone.blue),
              const SizedBox(height: 6),
              Text(store.site(str(w['id'])).isEmpty ? 'لم يُسجَّل في موقع بعد' : str(store.project(store.site(str(w['id'])))?['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.fg3)),
              if (n != null && n <= 30) Padding(padding: const EdgeInsets.only(top: 6), child: Pill(n < 0 ? 'الإقامة منتهية' : 'الإقامة بعد $n يوم', tone: n < 0 ? Tone.red : Tone.orange))
              else if (doc != null) Padding(padding: const EdgeInsets.only(top: 6), child: Pill('${str(doc['cat']).isEmpty ? 'مستند' : doc['cat']} ${daysLeft(str(doc['expiry'])) < 0 ? 'منتهٍ' : 'بعد ${daysLeft(str(doc['expiry']))} يوم'}', tone: daysLeft(str(doc['expiry'])) < 0 ? Tone.red : Tone.orange)),
              const Spacer(),
              const Divider(height: 14, color: C.slate200),
              Row(children: [
                Expanded(child: Column(children: [const Text('أجر الساعة', style: TextStyle(fontSize: 11, color: C.fg3)), Text('${fmtNum(toNum(w['rate']))} ر.س', style: const TextStyle(fontWeight: FontWeight.w800))])),
                Expanded(child: Column(children: [const Text('إضافي الشهر', style: TextStyle(fontSize: 11, color: C.fg3)), Text('${fmtNum(h)} س', style: const TextStyle(fontWeight: FontWeight.w800))])),
              ]),
            ]),
          ),
          PositionedDirectional(top: 10, start: 10, child: Pill(active ? 'نشط' : 'معطّل', tone: active ? Tone.green : Tone.slate)),
        ]),
      ),
    );
  }

  void _details(BuildContext context, Json w0) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        builder: (c, sc) => ListenableBuilder(listenable: store, builder: (c, _) {
          final w = store.worker(str(w0['id'])) ?? w0;  // refreshed after a document is added
          final files = [for (final f in (w['files'] as List?) ?? const []) Map<String, dynamic>.from(f as Map)];
          return ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Center(child: WorkerPhoto(w['photo'], size: 110)),
          const SizedBox(height: 10),
          Text(str(w['name']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text('${w['id']} · ${w['trade']}', textAlign: TextAlign.center, style: const TextStyle(color: C.fg3)),
          const SizedBox(height: 12),
          Center(child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            onPressed: () => sendWhatsApp(context, w), icon: const Icon(Icons.chat_outlined), label: const Text('رسالة واتساب'))),
          const SizedBox(height: 12),
          KV('الموقع الحالي', str(store.project(store.site(str(w['id'])))?['name'])),
          KV('الجنسية', str(w['nat'])),
          KV('رقم الهوية', str(w['iqama'])),
          Row(children: [const SizedBox(width: 120, child: Text('انتهاء الإقامة', style: TextStyle(color: C.fg3, fontSize: 13))), ExpiryChip(str(w['iqamaExpiry']), days: 30)]),
          KV('الجوال', str(w['phone'])),
          KV('أجر الساعة', '${fmtNum(toNum(w['rate']))} ر.س'),
          KV('تاريخ الالتحاق', fmtDate(str(w['joined']))),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(icon: const Icon(Icons.summarize_outlined), label: const Text('تقرير العامل: الحضور والإضافي والخصومات'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerReportPage(
            worker: w, money: store.can('payroll'),
            load: (f, l) async {
              Query q(Query x) => x.eq('worker_id', str(w['id'])).gte('date', f).lte('date', l);
              final r = await Future.wait([store.fetchAll('attendance', q), store.fetchAll('deductions', q), store.fetchAll('advances', q)]);
              return (att: r[0], ot: [for (final e in store.entries) if (e['workerId'] == w['id'] && str(e['date']).compareTo(f) >= 0 && str(e['date']).compareTo(l) <= 0) e], ded: r[1], adv: r[2]);
            },
          )))),
          if (store.vehicles.where((v) => v['driver'] == w['id']).firstOrNull case final car?) ...[
            SectionTitle('السيارة المخصصة · ${car['plate']}'),
            KV('السيارة', [str(car['type']), str(car['make']), str(car['model']), str(car['year'])].where((x) => x.isNotEmpty).join(' · ')),
            if (str(car['project']).isNotEmpty) KV('المشروع', str(store.project(str(car['project']))?['name'])),
            for (final (k, l) in [('regExpiry', 'الاستمارة'), ('insExpiry', 'التأمين'), ('inspExpiry', 'الفحص الدوري')])
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [SizedBox(width: 120, child: Text(l, style: const TextStyle(color: C.fg3, fontSize: 13))), ExpiryChip(str(car[k]), days: 30)])),
            for (final f in (car['files'] as List?) ?? const []) FileTile(Map<String, dynamic>.from(f as Map)),
          ],
          if (store.can('payroll')) _Installments(str(w['id'])),
          SectionTitle('المستندات (${files.length})'),
          if (files.isEmpty) const Text('لا توجد مستندات — صوّر الإقامة أو الرخصة أو الجواز.', style: TextStyle(color: C.fg3, fontSize: 13)),
          for (final f in files) FileTile(f),
          if (store.can('workers')) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(icon: const Icon(Icons.auto_awesome, color: C.violet), label: const Text('إضافة مستند بالذكاء الاصطناعي'), onPressed: () => addWorkerDoc(context, str(w['id']))),
          ],
        ]);
        }),
      ),
    );
  }
}

class TradesScreen extends StatelessWidget {
  const TradesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final trades = store.trades;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (trades.isEmpty) const CardBox(child: EmptyState('لا توجد مهن')),
      for (final t in trades)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: CardBox(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: C.primary50, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.handyman_outlined, color: C.primary700)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(t['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${store.workers.where((w) => w['trade'] == t['name']).length} عامل', style: const TextStyle(fontSize: 12, color: C.fg3)),
              ])),
              Text(toNum(t['rate']) > 0 ? '${fmtNum(toNum(t['rate']))} ر.س/س' : '—', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
    ]);
  }
}

String fmtMonth(String ym) => DateFormat('MMMM y', 'ar').format(DateTime.parse('$ym-01'));

/// A worker's installment deductions and advances (web: OTWorkerInstallments) and adding a deduction split into
/// monthly installments, taken from each payroll until repaid.
class _Installments extends StatefulWidget {
  final String workerId;
  const _Installments(this.workerId);
  @override
  State<_Installments> createState() => _InstallmentsState();
}

class _InstallmentsState extends State<_Installments> {
  List<Json>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await store.fetchAll('advances', (q) => q.eq('worker_id', widget.workerId));
    if (mounted) setState(() => _rows = r..sort((a, b) => str(b['date']).compareTo(str(a['date']))));
  }

  Future<void> _add() async {
    final reason = TextEditingController(), amount = TextEditingController(), count = TextEditingController(text: '3');
    var start = periodMonth(todayIso(), store.pay.startDay);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final a = toNum(amount.text), n = (int.tryParse(count.text) ?? 1).clamp(1, 60);
        final inst = installmentOf(a, n);
        final last = round2(a - inst * (n - 1));
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('خصم بالتقسيط', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'سبب الخصم', hintText: 'مثال: تلف معدات، مخالفة مرورية…'), onChanged: (_) => set(() {})),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'القيمة الإجمالية', suffixText: 'ر.س'), onChanged: (_) => set(() {}))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الدفعات'), onChanged: (_) => set(() {}))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              const Text('أول دفعة في مسيّر', style: TextStyle(color: C.fg3)),
              const Spacer(),
              IconButton(onPressed: () => set(() => start = addMonths(start, -1)), icon: const Icon(Icons.chevron_left)),
              Text(fmtMonth(start), style: const TextStyle(fontWeight: FontWeight.w800)),
              IconButton(onPressed: () => set(() => start = addMonths(start, 1)), icon: const Icon(Icons.chevron_right)),
            ]),
            if (a > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: C.success50, borderRadius: BorderRadius.circular(12)),
                child: Text('${n > 1 && last != inst ? '${n - 1} دفعات × ${fmtNum(inst)} ر.س والأخيرة ${fmtNum(last)} ر.س' : '$n دفعة × ${fmtNum(inst)} ر.س'} — تُخصم تلقائيًا من كل راتب حتى السداد، ابتداءً من ${fmtMonth(start)}.',
                    style: const TextStyle(color: C.success800, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 14),
            FilledButton(onPressed: a > 0 && reason.text.trim().isNotEmpty ? () => Navigator.pop(c, true) : null, child: const Text('حفظ الخصم')),
          ]),
        );
      }),
    );
    if (ok != true) return;
    final a = toNum(amount.text), n = (int.tryParse(count.text) ?? 1).clamp(1, 60);
    final err = await store.addAdvance({'worker_id': widget.workerId, 'kind': 'deduction', 'reason': reason.text.trim(), 'amount': a,
        'installment': installmentOf(a, n), 'start_month': start, 'date': todayIso()});
    if (!mounted) return;
    toast(context, err ?? 'تم تسجيل الخصم على $n دفعة.', bad: err != null);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    double left(Json a) => round2(toNum(a['amount']) - toNum(a['repaid']));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('الخصومات بالتقسيط والسلف', trailing: TextButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('خصم بالتقسيط'))),
      if (rows == null) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
      if (rows != null && rows.isEmpty) const Text('لا توجد خصومات مقسّطة أو سلف.', style: TextStyle(color: C.fg3, fontSize: 13)),
      for (final a in rows ?? const <Json>[])
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: CardBox(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Pill(a['kind'] == 'deduction' ? 'خصم بالتقسيط' : 'سلفة', tone: a['kind'] == 'deduction' ? Tone.red : Tone.blue),
                const SizedBox(width: 8),
                Expanded(child: Text(str(a['reason']).isEmpty ? fmtDate(str(a['date'])) : str(a['reason']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                Pill(a['status'] == 'cancelled' ? 'موقوف' : left(a) > 0 ? 'متبقٍ ${fmtNum(left(a))}' : 'مسدَّد', tone: a['status'] == 'cancelled' ? Tone.slate : left(a) > 0 ? Tone.orange : Tone.green),
              ]),
              const SizedBox(height: 8),
              ProgressBar(toNum(a['amount']) > 0 ? toNum(a['repaid']) / toNum(a['amount']) * 100 : 0),
              const SizedBox(height: 4),
              Text('${fmtNum(toNum(a['amount']))} ر.س · دفعة ${fmtNum(toNum(a['installment']))} ر.س من ${fmtMonth(str(a['start_month']))} · المسدَّد ${fmtNum(toNum(a['repaid']))}',
                  style: const TextStyle(fontSize: 12, color: C.fg3)),
            ]),
          ),
        ),
    ]);
  }
}
