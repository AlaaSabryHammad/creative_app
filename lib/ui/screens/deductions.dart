import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/logic.dart';
import '../../core/pay.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';
import 'requests.dart' show statusTone;

/// Deductions (web: src/deductions.jsx): by hours (× the normal hourly wage) or a fixed amount, always with a reason.
class DeductionsScreen extends StatefulWidget {
  const DeductionsScreen({super.key});
  @override
  State<DeductionsScreen> createState() => _DeductionsScreenState();
}

class _DeductionsScreenState extends State<DeductionsScreen> {
  String _month = monthIso();
  List<Json>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _rows = null);
    final (first, last, _) = monthBounds(_month);
    final r = await store.fetchAll('deductions', (q) => q.gte('date', first).lte('date', last));
    if (mounted) setState(() => _rows = r..sort((a, b) => str(b['date']).compareTo(str(a['date']))));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows ?? [];
    final approved = rows.where((d) => d['status'] == 'approved').fold<double>(0, (a, d) => a + toNum(d['amount']));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _add(context), icon: const Icon(Icons.add), label: const Text('تسجيل خصم')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
          Row(children: [
            IconButton(onPressed: () { _month = addMonths(_month, -1); _load(); }, icon: const Icon(Icons.chevron_right)),
            Expanded(child: Text(DateFormat('MMMM y', 'ar').format(DateTime.parse('$_month-01')), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            IconButton(onPressed: _month.compareTo(monthIso()) >= 0 ? null : () { _month = addMonths(_month, 1); _load(); }, icon: const Icon(Icons.chevron_left)),
          ]),
          StatGrid([
            StatTile(tone: Tone.red, icon: Icons.remove_circle_outline, label: 'الخصومات المعتمدة', value: money(approved)),
            StatTile(tone: Tone.orange, icon: Icons.hourglass_empty, label: 'بانتظار الاعتماد', value: '${rows.where((d) => d['status'] == 'pending').length}'),
          ]),
          const SizedBox(height: 12),
          if (_rows == null) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
          if (_rows != null && rows.isEmpty) const CardBox(child: EmptyState('لا توجد خصومات في هذا الشهر')),
          for (final d in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CardBox(
                child: Row(children: [
                  WorkerPhoto(store.worker(str(d['worker_id']))?['photo'], size: 40),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(str(store.worker(str(d['worker_id']))?['name'] ?? d['worker_id']), style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(str(d['reason']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: C.fg2)),
                    Text('${fmtDate(str(d['date']))} · ${d['kind'] == 'hours' ? '${fmtNum(toNum(d['hours']))} ساعة' : 'مبلغ'} · ${str(d['by_name'])}', style: const TextStyle(fontSize: 12, color: C.fg3)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(money(toNum(d['amount'])), style: const TextStyle(fontWeight: FontWeight.w800, color: C.danger)),
                    const SizedBox(height: 4),
                    Pill(statusLabel[d['status']] ?? '', tone: statusTone(str(d['status']))),
                    if (d['status'] == 'pending' && (d['created_by'] == store.me?['id'] || store.isAdmin))
                      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.delete_outline, color: C.danger, size: 20), onPressed: () async {
                        final err = await store.deleteRow('deductions', str(d['id']));
                        if (context.mounted) toast(context, err ?? 'تم حذف الخصم.', bad: err != null);
                        _load();
                      }),
                  ]),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final saved = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (c) => const _DeductionForm());
    if (saved == true) _load();
  }
}

class _DeductionForm extends StatefulWidget {
  const _DeductionForm();
  @override
  State<_DeductionForm> createState() => _DeductionFormState();
}

class _DeductionFormState extends State<_DeductionForm> {
  String? _worker;
  String _date = todayIso(), _kind = 'hours';
  final _hours = TextEditingController(text: '1'), _amount = TextEditingController(), _reason = TextEditingController(), _note = TextEditingController();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = store.pay;
    final workers = store.workers.where((w) => w['active'] != false).toList();
    final w = _worker == null ? null : store.worker(_worker);
    final wage = w == null ? 0.0 : hourlyWage(w, p);
    final amount = _kind == 'hours' ? round2(toNum(_hours.text) * wage) : toNum(_amount.text);
    final reasons = ((store.lookups['deductionReasons'] as List?) ?? const ['تأخير عن بداية الدوام', 'خروج قبل نهاية الدوام', 'مخالفة تعليمات السلامة']).map((e) => '$e').toList();
    final bad = w == null ? 'اختر العامل' : _kind == 'hours' && wage == 0 ? 'لا يوجد راتب لهذا العامل — استخدم الخصم بمبلغ' : amount <= 0 ? 'أدخل قيمة الخصم' : _reason.text.trim().isEmpty ? 'اكتب سبب الخصم' : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('تسجيل خصم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _worker,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'العامل'),
            items: [for (final x in workers) DropdownMenuItem(value: str(x['id']), child: Text('${x['name']} — ${x['id']}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _worker = v),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: DateTime.parse(_date), firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) setState(() => _date = DateFormat('yyyy-MM-dd').format(d));
            },
            child: InputDecorator(decoration: const InputDecoration(labelText: 'التاريخ'), child: Text(fmtDate(_date))),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'hours', label: Text('بالساعات'), icon: Icon(Icons.schedule)), ButtonSegment(value: 'amount', label: Text('بمبلغ'), icon: Icon(Icons.payments_outlined))],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 10),
          if (_kind == 'hours')
            TextField(controller: _hours, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'عدد الساعات', helperText: w == null ? null : 'الساعة العادية ${fmtNum(wage)} ر.س → ${money(amount)}'))
          else
            TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'المبلغ (ر.س)')),
          const SizedBox(height: 10),
          TextField(controller: _reason, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'السبب')),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [for (final r in reasons.take(5)) ActionChip(label: Text(r, style: const TextStyle(fontSize: 12)), onPressed: () => setState(() => _reason.text = r))]),
          const SizedBox(height: 10),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
          const SizedBox(height: 14),
          if (bad != null && w != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(bad, style: const TextStyle(color: C.danger))),
          FilledButton.icon(
            onPressed: bad != null || _busy ? null : () async {
              setState(() => _busy = true);
              final approver = store.can('requests');
              final projectId = store.projects.any((x) => x['id'] == w!['p']) ? w!['p'] : (store.projects.isNotEmpty ? store.projects.first['id'] : '');
              final err = await store.addDeduction({
                'worker_id': w!['id'], 'project_id': projectId, 'date': _date, 'kind': _kind, 'hours': _kind == 'hours' ? toNum(_hours.text) : 0,
                'rate': _kind == 'hours' ? wage : 0, 'amount': amount, 'reason': _reason.text.trim(), 'note': _note.text.trim(),
                'status': approver ? 'approved' : 'pending', 'by_name': store.myName,
              });
              if (!context.mounted) return;
              setState(() => _busy = false);
              toast(context, err ?? (approver ? 'تم تسجيل الخصم.' : 'تم إرسال الخصم للاعتماد.'), bad: err != null);
              if (err == null) Navigator.pop(context, true);
            },
            icon: const Icon(Icons.save_outlined),
            label: Text('حفظ الخصم${amount > 0 ? ' (${money(amount)})' : ''}'),
          ),
        ]),
      ),
    );
  }
}
