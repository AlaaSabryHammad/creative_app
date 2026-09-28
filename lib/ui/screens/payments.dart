import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';

/// Overtime payouts: balances per worker for a period, payout history, and recording a new payout.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  String _tab = 'balances', _period = 'month', _proj = 'all';
  (String, String) _range = monthRange(monthIso());

  (String, String) get _dates => switch (_period) {
        'month' => monthRange(monthIso()),
        'prev' => monthRange(prevMonth()),
        'all' => ('', ''),
        _ => _range,
      };

  @override
  Widget build(BuildContext context) {
    final payments = store.payments;
    final paid = store.paidIds;
    final (from, to) = _dates;
    final rows = balances(store.entries, store.workers, paid, from: from, to: to, proj: _proj)..sort((a, b) => b.rem.compareTo(a.rem));
    double sum(double Function(Balance) f) => rows.fold(0, (a, b) => a + f(b));
    bool inPeriod(Json e) => (from.isEmpty || str(e['date']).compareTo(from) >= 0) && (to.isEmpty || str(e['date']).compareTo(to) <= 0) && (_proj == 'all' || e['projectId'] == _proj);
    final pendingAmt = store.entries.where((e) => e['status'] == 'pending' && inPeriod(e)).fold<double>(0, (a, e) => a + otAmount(e, store.workers));
    final unpaidWorkers = store.entries.where((e) => e['status'] == 'approved' && !paid.contains(e['id'])).map((e) => str(e['workerId'])).toSet();
    final history = [...payments]..sort((a, b) => '${b['date']}${b['id']}'.compareTo('${a['date']}${a['id']}'));

    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        FilledButton.icon(
          onPressed: unpaidWorkers.isEmpty ? null : () => _openForm(context, null),
          icon: const Icon(Icons.payments_outlined),
          label: const Text('تسجيل صرف جديد'),
        ),
        const SizedBox(height: 12),
        StatGrid([
          StatTile(tone: Tone.blue, icon: Icons.schedule, label: 'المستحق المعتمد', value: money(sum((b) => b.amount)), sub: '${fmtNum(sum((b) => b.hours))} ساعة'),
          StatTile(tone: Tone.green, icon: Icons.payments_outlined, label: 'المصروف', value: money(sum((b) => b.paid)), sub: '${fmtNum(sum((b) => b.paidH))} ساعة'),
          StatTile(tone: Tone.orange, icon: Icons.account_balance_wallet_outlined, label: 'المتبقي للصرف', value: money(sum((b) => b.rem)), sub: '${fmtNum(sum((b) => b.remH))} ساعة'),
          StatTile(tone: Tone.slate, icon: Icons.hourglass_bottom, label: 'بانتظار الاعتماد', value: money(pendingAmt), sub: 'لا يُصرف قبل الاعتماد'),
        ]),
        const SizedBox(height: 12),
        FilterChips(items: [('balances', 'أرصدة العمال'), ('history', 'سجل الصرف (${payments.length})')], value: _tab, onChanged: (v) => setState(() => _tab = v)),
        const SizedBox(height: 10),
        if (_tab == 'balances') ...[
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: _period, isExpanded: true, decoration: const InputDecoration(labelText: 'الفترة'),
              items: const [DropdownMenuItem(value: 'month', child: Text('الشهر الحالي')), DropdownMenuItem(value: 'prev', child: Text('الشهر السابق')), DropdownMenuItem(value: 'all', child: Text('كل الفترات')), DropdownMenuItem(value: 'range', child: Text('فترة مخصصة'))],
              onChanged: (v) => setState(() => _period = v ?? 'month'),
            )),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: _proj, isExpanded: true, decoration: const InputDecoration(labelText: 'المشروع'),
              items: [const DropdownMenuItem(value: 'all', child: Text('كل المشاريع')), for (final p in store.projects) DropdownMenuItem(value: str(p['id']), child: Text(str(p['name']), overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _proj = v ?? 'all'),
            )),
          ]),
          if (_period == 'range') Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(child: DateField('من', _range.$1, (d) => setState(() => _range = (d, _range.$2)))),
              const SizedBox(width: 8),
              Expanded(child: DateField('إلى', _range.$2, (d) => setState(() => _range = (_range.$1, d)))),
            ]),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty) const CardBox(child: EmptyState('لا توجد ساعات معتمدة في هذه الفترة')),
          for (final r in rows) _balanceCard(context, r, unpaidWorkers.contains(r.workerId)),
        ] else ...[
          if (history.isEmpty) const CardBox(child: EmptyState('لم يُسجّل أي صرف بعد')),
          for (final p in history)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CardBox(
                onTap: () => _details(context, p),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: C.success50, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.receipt_long, color: C.success800)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(str(p['id']), style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('${fmtDate(str(p['from']), year: false)} – ${fmtDate(str(p['to']))}', style: const TextStyle(fontSize: 12.5, color: C.fg3)),
                    Text('${((p['items'] as List?) ?? []).length} عامل · ${payMethods[p['method']] ?? p['method']}', style: const TextStyle(fontSize: 12, color: C.fg3)),
                  ])),
                  Text(money(toNum(p['total'])), style: const TextStyle(fontWeight: FontWeight.w800, color: C.success800)),
                ]),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _balanceCard(BuildContext context, Balance r, bool canPay) {
    final w = store.worker(r.workerId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CardBox(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            WorkerPhoto(w?['photo'], size: 42),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(w?['name'] ?? r.workerId), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${r.workerId} · ${fmtNum(r.hours)} ساعة معتمدة', style: const TextStyle(fontSize: 12, color: C.fg3)),
            ])),
            if (canPay) OutlinedButton.icon(onPressed: () => _openForm(context, r.workerId), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)), icon: const Icon(Icons.payments_outlined, size: 18), label: const Text('صرف')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _mini('المستحق', money(r.amount), Tone.blue)),
            const SizedBox(width: 6),
            Expanded(child: _mini('المصروف', money(r.paid), Tone.green)),
            const SizedBox(width: 6),
            Expanded(child: _mini('المتبقي', r.rem > 0 ? money(r.rem) : 'مصروف بالكامل', r.rem > 0 ? Tone.orange : Tone.green)),
          ]),
        ]),
      ),
    );
  }

  Widget _mini(String k, String v, Tone t) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: const TextStyle(fontSize: 11, color: C.fg3)), FittedBox(child: Text(v, style: TextStyle(fontWeight: FontWeight.w800, color: t.fg)))]),
      );

  Future<void> _openForm(BuildContext context, String? preset) async {
    final msg = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => PayoutForm(preset: preset)));
    if (msg != null && context.mounted) {
      setState(() => _tab = 'history');
      toast(context, msg);
    }
  }

  void _details(BuildContext context, Json p) {
    final items = ((p['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .75,
        builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Text('سند صرف ${p['id']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          KV('الفترة', '${fmtDate(str(p['from']))} – ${fmtDate(str(p['to']))}'),
          KV('تاريخ الصرف', fmtDate(str(p['date']))),
          KV('طريقة الصرف', '${payMethods[p['method']] ?? p['method']}${str(p['ref']).isEmpty ? '' : ' · ${p['ref']}'}'),
          KV('الإجمالي', money(toNum(p['total']))),
          KV('سجّله', str(p['by'])),
          if (str(p['note']).isNotEmpty) KV('ملاحظات', str(p['note'])),
          const SectionTitle('العمال'),
          for (final i in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: WorkerPhoto(store.worker(str(i['workerId']))?['photo'], size: 38),
              title: Text(str(store.worker(str(i['workerId']))?['name'] ?? i['workerId'])),
              subtitle: Text('${fmtNum(toNum(i['hours']))} ساعة'),
              trailing: Text(money(toNum(i['amount'])), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          if (store.isAdmin) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: C.danger),
              icon: const Icon(Icons.undo),
              label: const Text('إلغاء الصرف'),
              onPressed: () async {
                final ok = await showDialog<bool>(context: c, builder: (d) => AlertDialog(
                  title: const Text('إلغاء سند الصرف؟'),
                  content: Text('ستعود سجلات ${p['id']} إلى المستحقات غير المصروفة.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(style: FilledButton.styleFrom(backgroundColor: C.danger), onPressed: () => Navigator.pop(d, true), child: const Text('إلغاء الصرف'))],
                ));
                if (ok != true) return;
                final err = await store.save('payments', store.payments.where((x) => x['id'] != p['id']).toList());
                if (c.mounted) Navigator.pop(c);
                if (context.mounted) toast(context, err ?? 'تم إلغاء سند الصرف ${p['id']}.', bad: err != null);
              },
            ),
          ],
        ]),
      ),
    );
  }
}

/// Date input that opens the platform date picker.
class DateField extends StatelessWidget {
  final String label, value;
  final ValueChanged<String> onChanged;
  const DateField(this.label, this.value, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final d = await showDatePicker(context: context, initialDate: parseDate(value) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
          if (d != null) onChanged(DateFormat('yyyy-MM-dd').format(d));
        },
        child: InputDecorator(decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.event, size: 20)), child: Text(fmtDate(value))),
      );
}

class PayoutForm extends StatefulWidget {
  final String? preset;
  const PayoutForm({super.key, this.preset});
  @override
  State<PayoutForm> createState() => _PayoutFormState();
}

class _PayoutFormState extends State<PayoutForm> {
  late String _from, _to = todayIso();
  String _proj = 'all', _date = todayIso(), _method = 'cash';
  final _ref = TextEditingController(), _note = TextEditingController();
  final Set<String> _off = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final paid = store.paidIds;
    final earliest = store.entries.where((e) => e['status'] == 'approved' && !paid.contains(e['id'])).fold<String>(todayIso(), (m, e) => str(e['date']).compareTo(m) < 0 ? str(e['date']) : m);
    final monthStart = '${monthIso()}-01';
    _from = widget.preset != null || earliest.compareTo(monthStart) < 0 ? earliest : monthStart;
  }

  @override
  Widget build(BuildContext context) {
    final paid = store.paidIds;
    bool inRange(Json e) => str(e['date']).compareTo(_from) >= 0 && str(e['date']).compareTo(_to) <= 0 && (_proj == 'all' || e['projectId'] == _proj) && (widget.preset == null || e['workerId'] == widget.preset);
    final due = store.entries.where((e) => e['status'] == 'approved' && !paid.contains(e['id']) && inRange(e)).toList();
    final pendingN = store.entries.where((e) => e['status'] == 'pending' && inRange(e)).length;
    final byWorker = <String, ({double hours, double amount, List<String> ids})>{};
    for (final e in due) {
      final k = str(e['workerId']);
      final r = byWorker[k] ?? (hours: 0.0, amount: 0.0, ids: <String>[]);
      byWorker[k] = (hours: r.hours + toNum(e['hours']), amount: r.amount + otAmount(e, store.workers), ids: [...r.ids, str(e['id'])]);
    }
    final rows = byWorker.entries.toList()..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    final chosen = rows.where((r) => !_off.contains(r.key)).toList();
    final total = chosen.fold<double>(0, (a, r) => a + r.value.amount);
    final bad = _from.compareTo(_to) > 0 ? 'تحقق من تاريخ البداية والنهاية.' : chosen.isEmpty ? 'لا توجد مستحقات معتمدة غير مصروفة في هذه الفترة.' : null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.preset == null ? 'تسجيل صرف عمل إضافي' : 'صرف — ${str(store.worker(widget.preset)?['name'])}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: DateField('من تاريخ', _from, (d) => setState(() => _from = d))),
          const SizedBox(width: 8),
          Expanded(child: DateField('إلى تاريخ', _to, (d) => setState(() => _to = d))),
        ]),
        if (widget.preset == null) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _proj, isExpanded: true, decoration: const InputDecoration(labelText: 'المشروع'),
            items: [const DropdownMenuItem(value: 'all', child: Text('كل المشاريع')), for (final p in store.projects) DropdownMenuItem(value: str(p['id']), child: Text(str(p['name'])))],
            onChanged: (v) => setState(() => _proj = v ?? 'all'),
          ),
        ],
        if (pendingN > 0) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: C.warning50, borderRadius: BorderRadius.circular(12)),
            child: Text('يوجد $pendingN سجل بانتظار الاعتماد في هذه الفترة، لن يُصرف حتى يتم اعتماده.', style: const TextStyle(color: C.warning800))),
        ),
        const SectionTitle('المستحقات'),
        if (rows.isEmpty) const CardBox(child: EmptyState('لا توجد مستحقات معتمدة غير مصروفة في هذه الفترة')),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CardBox(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Checkbox(value: !_off.contains(r.key), onChanged: (v) => setState(() => v == true ? _off.remove(r.key) : _off.add(r.key))),
                WorkerPhoto(store.worker(r.key)?['photo'], size: 36),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(str(store.worker(r.key)?['name'] ?? r.key), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${r.value.ids.length} سجل · ${fmtNum(r.value.hours)} ساعة', style: const TextStyle(fontSize: 12, color: C.fg3)),
                ])),
                Text(money(r.value.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        const SectionTitle('بيانات الصرف'),
        DateField('تاريخ الصرف', _date, (d) => setState(() => _date = d)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _method, decoration: const InputDecoration(labelText: 'طريقة الصرف'),
          items: [for (final m in payMethods.entries) DropdownMenuItem(value: m.key, child: Text(m.value))],
          onChanged: (v) => setState(() => _method = v ?? 'cash'),
        ),
        const SizedBox(height: 10),
        TextField(controller: _ref, decoration: const InputDecoration(labelText: 'رقم المرجع (اختياري)', hintText: 'رقم الحوالة أو الشيك')),
        const SizedBox(height: 10),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
        const SizedBox(height: 90),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: bad != null || _busy ? null : () => _save(chosen, total),
            icon: const Icon(Icons.done_all),
            label: Text(total > 0 ? 'تأكيد الصرف (${money(total)})' : 'تأكيد الصرف'),
          ),
        ),
      ),
    );
  }

  Future<void> _save(List<MapEntry<String, ({double hours, double amount, List<String> ids})>> chosen, double total) async {
    setState(() => _busy = true);
    final list = store.payments;
    final n = list.fold<int>(0, (m, x) => (int.tryParse(str(x['id']).replaceAll('PAY-', '')) ?? 0) > m ? int.parse(str(x['id']).replaceAll('PAY-', '')) : m);
    final p = {
      'id': 'PAY-${'${n + 1}'.padLeft(4, '0')}',
      'from': _from, 'to': _to, 'date': _date, 'method': _method, 'ref': _ref.text.trim(), 'note': _note.text.trim(),
      'by': store.me?['name'], 'createdAt': DateTime.now().toUtc().toIso8601String(),
      'entryIds': [for (final r in chosen) ...r.value.ids],
      'items': [for (final r in chosen) {'workerId': r.key, 'hours': r.value.hours, 'amount': (r.value.amount * 100).round() / 100}],
      'total': (total * 100).round() / 100,
    };
    final err = await store.save('payments', [p, ...list]);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) return toast(context, err, bad: true);
    Navigator.pop(context, 'تم تسجيل صرف ${money(total)} لـ ${chosen.length} عامل.');
  }
}
