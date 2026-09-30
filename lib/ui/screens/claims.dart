import 'package:flutter/material.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/extract.dart';
import '../../data/store.dart';
import '../doc_pick.dart';
import '../widgets.dart';

/// A project's payment claims (المستخلصات): totals, progress and the list; staff with the projects
/// permission add claims — a photo or PDF of the claim is read by the AI (same rules as the web).
class ClaimsTab extends StatelessWidget {
  final Json project;
  const ClaimsTab(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = claimTotals(project['claims'] as List?, project['value']);
    final canEdit = store.can('projects');
    final value = toNum(project['value']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (canEdit)
        FilledButton.icon(icon: const Icon(Icons.add), label: const Text('مستخلص جديد'), onPressed: () => _open(context, null)),
      const SizedBox(height: 12),
      StatGrid([
        StatTile(tone: Tone.blue, icon: Icons.receipt_long_outlined, label: 'عدد المستخلصات', value: '${t.list.length}'),
        StatTile(tone: Tone.green, icon: Icons.trending_up, label: 'نسبة الإنجاز', value: t.pct == null ? '—' : '${t.pct!.round()}%', sub: 'منفذ ${money(t.cum)}'),
        StatTile(tone: Tone.orange, icon: Icons.payments_outlined, label: 'المصروف', value: money(t.paid), sub: 'مستحق ${money(t.due)}'),
        StatTile(tone: Tone.red, icon: Icons.balance_outlined, label: 'المتبقي من العقد', value: t.remaining == null ? '—' : money(t.remaining!)),
      ]),
      if (t.pct != null) ...[
        const SizedBox(height: 12),
        CardBox(child: Column(children: [
          Row(children: [const Text('الإنجاز حسب المستخلصات', style: TextStyle(color: C.fg3)), const Spacer(), Text('${t.pct!.round()}%', style: const TextStyle(fontWeight: FontWeight.w800))]),
          const SizedBox(height: 8),
          ProgressBar(t.pct!, gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)])),
          if (value <= 0) const Padding(padding: EdgeInsets.only(top: 8), child: Text('سجّل قيمة العقد لحساب النسبة بدقة.', style: TextStyle(fontSize: 12, color: C.fg3))),
        ])),
      ],
      const SizedBox(height: 12),
      if (t.list.isEmpty) const CardBox(child: EmptyState('لا توجد مستخلصات بعد')),
      for (final r in t.list.reversed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: CardBox(
            onTap: canEdit ? () => _open(context, r.c) : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text('مستخلص #${r.c['no']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                Pill(claimStatus[r.c['status'] ?? 'submitted'] ?? '', tone: r.c['status'] == 'paid' ? Tone.green : r.c['status'] == 'approved' ? Tone.orange : Tone.blue),
              ]),
              const SizedBox(height: 4),
              Text(str(r.c['from']).isNotEmpty && str(r.c['to']).isNotEmpty ? '${fmtDate(str(r.c['from']))} – ${fmtDate(str(r.c['to']))}' : fmtDate(str(r.c['date'])), style: const TextStyle(color: C.fg3, fontSize: 13)),
              const Divider(height: 18, color: C.slate200),
              Row(children: [
                Expanded(child: _kv('قيمة المستخلص', money(toNum(r.c['amount'])))),
                Expanded(child: _kv('التراكمي', money(r.cum))),
                Expanded(child: _kv('الإنجاز', toNum(r.c['progress']) > 0 ? '${fmtNum(toNum(r.c['progress']))}%' : r.pct == null ? '—' : '${r.pct!.round()}%')),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: _kv('الصافي', money(claimNet(r.c)))),
                if (r.c['file'] is Map) TextButton.icon(icon: const Icon(Icons.attach_file, size: 18), label: const Text('الملف'), onPressed: () => openStoredFile(context, Map<String, dynamic>.from(r.c['file']))),
              ]),
            ]),
          ),
        ),
    ]);
  }

  Widget _kv(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(fontSize: 11.5, color: C.fg3)),
        FittedBox(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w800))),
      ]);

  void _open(BuildContext context, Json? claim) =>
      Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => ClaimForm(project: project, claim: claim)));
}

class ClaimForm extends StatefulWidget {
  final Json project;
  final Json? claim;
  const ClaimForm({super.key, required this.project, this.claim});
  @override
  State<ClaimForm> createState() => _ClaimFormState();
}

class _ClaimFormState extends State<ClaimForm> {
  static const _money = ['amount', 'cumulative', 'deductions', 'vat', 'net', 'progress'];
  late final Json _c = {
    'no': '', 'from': '', 'to': '', 'date': todayIso(), 'status': 'submitted', 'paidOn': '', 'notes': '', 'file': null,
    for (final k in _money) k: '',
    ...?widget.claim,
  };
  late final _ctl = {for (final k in ['no', ..._money, 'notes']) k: TextEditingController(text: str(_c[k]))};
  bool _busy = false;
  String? _summary;
  final Set<String> _ai = {};

  Future<void> _read() async {
    final d = await pickDoc(context, title: 'ملف المستخلص');
    if (d == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final meta = await store.uploadFile(d.bytes, d.name, d.mime);
      _c['file'] = meta;
      final r = await extractDoc('claim', d.bytes, d.mime, {'project': widget.project['name']});
      bool date(String v) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v);
      for (final k in ['no', ..._money]) {
        final v = str(r[k]).replaceAll(RegExp(r'[^\d.\-]'), '');
        if (v.isNotEmpty) { _ctl[k]!.text = v; _ai.add(k); }
      }
      for (final k in ['from', 'to', 'date']) {
        if (date(str(r[k]))) { _c[k] = r[k]; _ai.add(k); }
      }
      if (toNum(_ctl['cumulative']!.text) == 0 && toNum(r['previous']) > 0 && toNum(_ctl['amount']!.text) > 0) {
        _ctl['cumulative']!.text = '${toNum(r['previous']) + toNum(_ctl['amount']!.text)}';
        _ai.add('cumulative');
      }
      _summary = str(r['summary']);
    } catch (e) {
      if (mounted) toast(context, '$e', bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    for (final e in _ctl.entries) { _c[e.key] = e.value.text.trim(); }
    final err = str(_c['no']).isEmpty ? 'أدخل رقم المستخلص'
        : toNum(_c['amount']) <= 0 && toNum(_c['cumulative']) <= 0 ? 'أدخل قيمة المستخلص أو القيمة التراكمية'
        : str(_c['from']).isNotEmpty && str(_c['to']).isNotEmpty && str(_c['to']).compareTo(str(_c['from'])) < 0 ? 'نهاية الفترة قبل بدايتها' : null;
    if (err != null) return toast(context, err, bad: true);
    final p = store.project(str(widget.project['id']));
    if (p == null) return;
    setState(() => _busy = true);
    final claim = {..._c, 'id': str(_c['id']).isEmpty ? 'c-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}' : _c['id']};
    final list = [for (final x in (p['claims'] as List?) ?? const []) Map<String, dynamic>.from(x as Map)];
    final i = list.indexWhere((x) => x['id'] == claim['id']);
    if (i >= 0) { list[i] = claim; } else { list.add(claim); }
    final files = [for (final f in (p['files'] as List?) ?? const []) Map<String, dynamic>.from(f as Map)];
    if (claim['file'] is Map && !files.any((f) => f['id'] == (claim['file'] as Map)['id'])) {
      files.insert(0, {...Map<String, dynamic>.from(claim['file'] as Map), 'cat': 'مستخلص'});  // also listed in the project's files
    }
    final err2 = await store.saveProject({...p, 'claims': list, 'files': files});
    if (!mounted) return;
    setState(() => _busy = false);
    if (err2 != null) return toast(context, err2, bad: true);
    toast(context, 'تم حفظ المستخلص رقم ${claim['no']}.');
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: Text('حذف المستخلص رقم ${widget.claim!['no']}؟'), content: const Text('يبقى ملفه في ملفات المشروع.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')), FilledButton(style: FilledButton.styleFrom(backgroundColor: C.danger), onPressed: () => Navigator.pop(c, true), child: const Text('حذف'))]));
    if (ok != true) return;
    final p = store.project(str(widget.project['id']))!;
    final err = await store.saveProject({...p, 'claims': [for (final x in (p['claims'] as List?) ?? const []) if (x['id'] != widget.claim!['id']) x]});
    if (!mounted) return;
    if (err != null) return toast(context, err, bad: true);
    Navigator.pop(context);
  }

  Widget _field(String k, String label, {String? suffix, String? help}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _ctl[k],
          keyboardType: k == 'notes' ? TextInputType.multiline : const TextInputType.numberWithOptions(decimal: true),
          maxLines: k == 'notes' ? 3 : 1,
          decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: help, prefixIcon: _ai.contains(k) ? const Icon(Icons.auto_awesome, color: C.violet, size: 18) : null),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.claim == null ? 'مستخلص جديد' : 'المستخلص رقم ${widget.claim!['no']}'), actions: [
        if (widget.claim != null) IconButton(icon: const Icon(Icons.delete_outline, color: C.danger), onPressed: _busy ? null : _delete),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        CardBox(
          onTap: _busy ? null : _read,
          child: Row(children: [
            _busy ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.auto_awesome, color: C.violet, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_busy ? 'يقرأ الذكاء الاصطناعي المستخلص…' : 'صوّر المستخلص أو اختر ملفه', style: const TextStyle(fontWeight: FontWeight.w800)),
              const Text('يستخرج الرقم والفترة والقيم ويُرفق الملف بالمشروع', style: TextStyle(fontSize: 12.5, color: C.fg3)),
            ])),
          ]),
        ),
        if (_summary != null && _summary!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: AiNote(_summary!)),
        if (_c['file'] is Map) Padding(padding: const EdgeInsets.only(top: 8), child: FileTile(Map<String, dynamic>.from(_c['file'] as Map))),
        const SizedBox(height: 14),
        _field('no', 'رقم المستخلص'),
        DateField('تاريخ المستخلص', str(_c['date']), (v) => setState(() => _c['date'] = v)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DateField('الفترة من', str(_c['from']), (v) => setState(() => _c['from'] = v))),
          const SizedBox(width: 10),
          Expanded(child: DateField('إلى', str(_c['to']), (v) => setState(() => _c['to'] = v))),
        ]),
        const SizedBox(height: 12),
        _field('amount', 'قيمة المستخلص الحالي', suffix: 'ر.س', help: 'قبل الخصومات'),
        _field('cumulative', 'إجمالي الأعمال حتى تاريخه', suffix: 'ر.س', help: 'اتركه فارغًا ليُحسب من المستخلصات السابقة'),
        _field('deductions', 'الخصومات', suffix: 'ر.س'),
        _field('vat', 'ضريبة القيمة المضافة', suffix: 'ر.س'),
        _field('net', 'صافي المستحق', suffix: 'ر.س', help: 'اتركه فارغًا ليُحسب'),
        _field('progress', 'نسبة الإنجاز المذكورة', suffix: '%', help: 'إن لم تُذكر تُحسب من التراكمي ÷ قيمة العقد'),
        DropdownButtonFormField<String>(
          initialValue: str(_c['status']).isEmpty ? 'submitted' : str(_c['status']),
          decoration: const InputDecoration(labelText: 'الحالة'),
          items: [for (final e in claimStatus.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _c['status'] = v),
        ),
        const SizedBox(height: 12),
        if (_c['status'] == 'paid') ...[DateField('تاريخ الصرف', str(_c['paidOn']), (v) => setState(() => _c['paidOn'] = v)), const SizedBox(height: 12)],
        _field('notes', 'ملاحظات'),
        const SizedBox(height: 6),
        FilledButton.icon(icon: const Icon(Icons.save_outlined), label: const Text('حفظ المستخلص'), onPressed: _busy ? null : _save),
      ]),
    );
  }
}
