import 'package:flutter/material.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';

Tone statusTone(String s) => s == 'approved' ? Tone.green : s == 'rejected' ? Tone.red : Tone.orange;

Future<void> setStatus(BuildContext context, List<String> ids, String status, {String note = ''}) async {
  final err = await store.decideOt(ids, status, note: note);
  if (context.mounted) toast(context, err ?? (status == 'approved' ? 'تم اعتماد ${ids.length} سجل.' : 'تم رفض ${ids.length} سجل.'), bad: err != null);
}

Future<String?> askReason(BuildContext context, {String title = 'سبب الرفض', String hint = 'اكتب سبب الرفض', bool required = true}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, maxLines: 3, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () { if (!required || c.text.trim().isNotEmpty) Navigator.pop(ctx, c.text.trim()); }, child: const Text('تأكيد')),
      ],
    ),
  );
}

Future<void> rejectDialog(BuildContext context, List<String> ids) async {
  final note = await askReason(context);
  if (note != null && context.mounted) await setStatus(context, ids, 'rejected', note: note);
}

/// One overtime record with approve / reject actions when pending.
class EntryCard extends StatelessWidget {
  final Json e;
  const EntryCard(this.e, {super.key});
  @override
  Widget build(BuildContext context) {
    final w = store.worker(str(e['workerId']));
    final st = str(e['status']);
    final canAct = st == 'pending' && store.can('requests');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CardBox(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            WorkerPhoto(w?['photo'], size: 42),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(w?['name'] ?? e['workerId']), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${str(store.project(str(e['projectId']))?['name'] ?? '—')} · ${str(e['reason'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.fg3)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Pill(statusLabel[st] ?? st, tone: statusTone(st)),
              if (store.paidIds.contains(e['id'])) const Padding(padding: EdgeInsets.only(top: 4), child: Pill('مصروف', tone: Tone.blue, icon: Icons.payments_outlined)),
            ]),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Pill(dayLabel[e['dayType']] ?? '', tone: e['dayType'] == 'normal' ? Tone.slate : e['dayType'] == 'friday' ? Tone.blue : Tone.orange),
            const SizedBox(width: 8),
            Text(fmtDate(str(e['date'])), style: const TextStyle(fontSize: 13, color: C.fg2)),
            const Spacer(),
            Text('${fmtNum(toNum(e['hours']))} س', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            Text(money(otAmount(e)), style: const TextStyle(fontWeight: FontWeight.w800, color: C.primary700)),
          ]),
          if (str(e['note']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(str(e['note']), style: const TextStyle(fontSize: 12.5, color: C.danger800))),
          if (canAct) ...[
            const SizedBox(height: 10),
            _Actions(onOk: () => setStatus(context, [str(e['id'])], 'approved'), onNo: () => rejectDialog(context, [str(e['id'])])),
          ],
        ]),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final VoidCallback onOk, onNo;
  final String ok;
  const _Actions({required this.onOk, required this.onNo, this.ok = 'اعتماد'});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: C.success, minimumSize: const Size(0, 40)), onPressed: onOk, icon: const Icon(Icons.check, size: 18), label: Text(ok))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: C.danger, minimumSize: const Size(0, 40)), onPressed: onNo, icon: const Icon(Icons.close, size: 18), label: const Text('رفض'))),
      ]);
}

/// Approvals: overtime, deductions recorded by supervisors, and requests sent from the worker app.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  String _tab = 'ot', _f = 'pending', _q = '';
  List<Json>? _ded, _req;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!store.can('requests')) return;
    final r = await Future.wait([store.fetchAll('deductions', (q) => q.eq('status', 'pending')), store.fetchAll('requests')]);
    if (mounted) setState(() { _ded = r[0]; _req = r[1]; });
  }

  @override
  Widget build(BuildContext context) {
    final approver = store.can('requests');
    final nDed = _ded?.length ?? 0, nReq = _req?.where((r) => r['status'] == 'pending').length ?? 0;
    final nOt = store.entries.where((e) => e['status'] == 'pending').length;
    return RefreshIndicator(
      onRefresh: () async { await store.refresh(); await _load(); },
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (approver) ...[
          FilterChips(items: [('ot', 'الإضافي ($nOt)'), ('ded', 'الخصومات ($nDed)'), ('req', 'طلبات العمال ($nReq)')], value: _tab, onChanged: (v) => setState(() => _tab = v)),
          const SizedBox(height: 12),
        ],
        if (_tab == 'ot') ..._overtime(),
        if (_tab == 'ded') ..._deductions(),
        if (_tab == 'req') ..._requests(),
      ]),
    );
  }

  List<Widget> _overtime() {
    final all = store.entries;
    final list = all.where((e) => (_f == 'all' || e['status'] == _f) && (_q.isEmpty || str(store.worker(str(e['workerId']))?['name']).contains(_q))).toList()..sort((a, b) => str(b['date']).compareTo(str(a['date'])));
    final pendIds = list.where((e) => e['status'] == 'pending').map((e) => str(e['id'])).toList();
    int n(String s) => all.where((e) => e['status'] == s).length;
    return [
      FilterChips(items: [('pending', 'بانتظار الاعتماد (${n('pending')})'), ('approved', 'معتمد (${n('approved')})'), ('rejected', 'مرفوض (${n('rejected')})'), ('all', 'الكل (${all.length})')], value: _f, onChanged: (v) => setState(() => _f = v)),
      const SizedBox(height: 10),
      SearchField('بحث باسم العامل', onChanged: (v) => setState(() => _q = v)),
      if (_f == 'pending' && pendIds.length > 1 && store.can('requests'))
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: C.success), onPressed: () => setStatus(context, pendIds, 'approved'), icon: const Icon(Icons.done_all), label: Text('اعتماد الكل (${pendIds.length})')),
        ),
      const SizedBox(height: 12),
      if (list.isEmpty) const CardBox(child: EmptyState('لا توجد سجلات')),
      for (final e in list) EntryCard(e),
    ];
  }

  Future<void> _decideDed(List<String> ids, String status) async {
    var note = '';
    if (status == 'rejected') {
      final n = await askReason(context);
      if (n == null) return;
      note = n;
    }
    final err = await store.decideDeductions(ids, status, note: note);
    if (!mounted) return;
    toast(context, err ?? (status == 'approved' ? 'تم اعتماد ${ids.length} خصم.' : 'تم رفض ${ids.length} خصم.'), bad: err != null);
    _load();
  }

  List<Widget> _deductions() {
    if (_ded == null) return const [Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))];
    final list = [..._ded!]..sort((a, b) => str(a['date']).compareTo(str(b['date'])));
    return [
      if (list.length > 1) FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: C.success), onPressed: () => _decideDed(list.map((d) => str(d['id'])).toList(), 'approved'), icon: const Icon(Icons.done_all), label: Text('اعتماد الكل (${list.length})')),
      const SizedBox(height: 10),
      if (list.isEmpty) const CardBox(child: EmptyState('لا توجد خصومات بانتظار الاعتماد')),
      for (final d in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CardBox(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                WorkerPhoto(store.worker(str(d['worker_id']))?['photo'], size: 40),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(str(store.worker(str(d['worker_id']))?['name'] ?? d['worker_id']), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${fmtDate(str(d['date']))} · ${d['kind'] == 'hours' ? '${fmtNum(toNum(d['hours']))} ساعة' : 'مبلغ'} · سجّله ${str(d['by_name'])}', style: const TextStyle(fontSize: 12, color: C.fg3)),
                ])),
                Text(money(toNum(d['amount'])), style: const TextStyle(fontWeight: FontWeight.w800, color: C.danger)),
              ]),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(str(d['reason']), style: const TextStyle(fontWeight: FontWeight.w600))),
              _Actions(onOk: () => _decideDed([str(d['id'])], 'approved'), onNo: () => _decideDed([str(d['id'])], 'rejected')),
            ]),
          ),
        ),
    ];
  }

  Future<void> _decideReq(Json r, bool ok) async {
    final reply = await askReason(context, title: ok ? 'الموافقة على الطلب' : 'رفض الطلب', hint: 'ردّك للعامل (اختياري)', required: false);
    if (reply == null) return;
    final err = await store.decideRequest(str(r['id']), ok, reply);
    if (!mounted) return;
    toast(context, err ?? (ok ? 'تمت الموافقة على الطلب.' : 'تم رفض الطلب.'), bad: err != null);
    _load();
  }

  List<Widget> _requests() {
    if (_req == null) return const [Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))];
    int rank(Json r) => r['status'] == 'pending' ? 0 : 1;  // pending first, then newest
    final list = [..._req!]..sort((a, b) { final c = rank(a).compareTo(rank(b)); return c != 0 ? c : str(b['created_at']).compareTo(str(a['created_at'])); });
    const kinds = {'leave': ('إجازة', Icons.luggage_outlined), 'advance': ('سلفة', Icons.payments_outlined), 'objection': ('اعتراض', Icons.feedback_outlined), 'other': ('طلب آخر', Icons.chat_outlined)};
    return [
      if (list.isEmpty) const CardBox(child: EmptyState('لا توجد طلبات من العمال')),
      for (final r in list.take(60))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CardBox(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(kinds[r['kind']]?.$2 ?? Icons.chat_outlined, color: C.primary),
                const SizedBox(width: 10),
                Expanded(child: Text('${kinds[r['kind']]?.$1 ?? ''} — ${str(store.worker(str(r['worker_id']))?['name'] ?? r['worker_id'])}', style: const TextStyle(fontWeight: FontWeight.w800))),
                Pill(r['status'] == 'pending' ? 'بانتظار الرد' : statusLabel[r['status']] ?? '', tone: statusTone(str(r['status']))),
              ]),
              const SizedBox(height: 6),
              if (r['kind'] == 'leave') Text('${fmtDate(str(r['date_from']))} – ${fmtDate(str(r['date_to']))}', style: const TextStyle(color: C.fg2)),
              if (r['kind'] == 'advance') Text('${money(toNum(r['amount']))} على ${r['installments'] ?? 1} قسط', style: const TextStyle(color: C.fg2)),
              if (str(r['text']).isNotEmpty) Text(str(r['text']), style: const TextStyle(color: C.fg2)),
              if (str(r['reply']).isNotEmpty) Text('الرد: ${r['reply']}', style: const TextStyle(color: C.fg3, fontSize: 12.5)),
              if (r['status'] == 'pending') ...[
                const SizedBox(height: 10),
                _Actions(ok: 'موافقة', onOk: () => _decideReq(r, true), onNo: () => _decideReq(r, false)),
              ],
            ]),
          ),
        ),
    ];
  }
}
