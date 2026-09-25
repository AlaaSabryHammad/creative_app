import 'package:flutter/material.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';

Tone statusTone(String s) => s == 'approved' ? Tone.green : s == 'rejected' ? Tone.red : Tone.orange;

Future<void> setStatus(BuildContext context, List<String> ids, String status, {String note = ''}) async {
  final list = store.entries.map((e) => ids.contains(e['id']) ? {...e, 'status': status, 'note': note} : e).toList();
  final err = await store.save('entries', list);
  if (context.mounted) toast(context, err ?? (status == 'approved' ? 'تم اعتماد ${ids.length} سجل.' : 'تم رفض ${ids.length} سجل.'), bad: err != null);
}

Future<void> rejectDialog(BuildContext context, List<String> ids) async {
  final c = TextEditingController();
  final note = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('سبب الرفض'),
      content: TextField(controller: c, maxLines: 3, autofocus: true, decoration: const InputDecoration(hintText: 'اكتب سبب الرفض')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: C.danger), onPressed: () { if (c.text.trim().isNotEmpty) Navigator.pop(ctx, c.text.trim()); }, child: const Text('تأكيد الرفض')),
      ],
    ),
  );
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
    final canAct = st == 'pending' && (store.can('requests') || store.can('dashboard'));
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
            Pill(statusLabel[st] ?? st, tone: statusTone(st)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Pill(dayLabel[e['dayType']] ?? '', tone: e['dayType'] == 'normal' ? Tone.slate : e['dayType'] == 'friday' ? Tone.blue : Tone.orange),
            const SizedBox(width: 8),
            Text(fmtDate(str(e['date'])), style: const TextStyle(fontSize: 13, color: C.fg2)),
            const Spacer(),
            Text('${fmtNum(toNum(e['hours']))} س', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            Text(money(otAmount(e, store.workers)), style: const TextStyle(fontWeight: FontWeight.w800, color: C.primary700)),
          ]),
          if (str(e['note']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(str(e['note']), style: const TextStyle(fontSize: 12.5, color: C.danger800))),
          if (canAct) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: C.success, minimumSize: const Size(0, 40)), onPressed: () => setStatus(context, [str(e['id'])], 'approved'), icon: const Icon(Icons.check, size: 18), label: const Text('اعتماد'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: C.danger, minimumSize: const Size(0, 40)), onPressed: () => rejectDialog(context, [str(e['id'])]), icon: const Icon(Icons.close, size: 18), label: const Text('رفض'))),
            ]),
          ],
        ]),
      ),
    );
  }
}

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  String _f = 'pending', _q = '';
  @override
  Widget build(BuildContext context) {
    final all = store.entries;
    final list = all.where((e) => (_f == 'all' || e['status'] == _f) && (_q.isEmpty || str(store.worker(str(e['workerId']))?['name']).contains(_q))).toList()..sort((a, b) => str(b['date']).compareTo(str(a['date'])));
    final pendIds = list.where((e) => e['status'] == 'pending').map((e) => str(e['id'])).toList();
    int n(String s) => all.where((e) => e['status'] == s).length;
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        FilterChips(items: [('pending', 'بانتظار الاعتماد (${n('pending')})'), ('approved', 'معتمد (${n('approved')})'), ('rejected', 'مرفوض (${n('rejected')})'), ('all', 'الكل (${all.length})')], value: _f, onChanged: (v) => setState(() => _f = v)),
        const SizedBox(height: 10),
        SearchField('بحث باسم العامل', onChanged: (v) => setState(() => _q = v)),
        if (_f == 'pending' && pendIds.length > 1 && store.can('requests')) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: C.success), onPressed: () => setStatus(context, pendIds, 'approved'), icon: const Icon(Icons.done_all), label: Text('اعتماد الكل (${pendIds.length})')),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty) const CardBox(child: EmptyState('لا توجد سجلات')),
        for (final e in list) EntryCard(e),
      ]),
    );
  }
}
