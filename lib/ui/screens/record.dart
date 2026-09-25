import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';

/// Record overtime: hours per worker, paid at the worker's hourly rate only.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});
  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  String _date = todayIso();
  String? _project;
  String? _reason;
  final _note = TextEditingController();
  final Map<String, double> _sel = {};
  bool _all = false, _busy = false;

  @override
  Widget build(BuildContext context) {
    final projects = store.projects;
    _project ??= projects.isNotEmpty ? str(projects.first['id']) : null;
    final reasons = ((store.lookups['otReasons'] as List?) ?? const ['أعمال طارئة']).map((e) => '$e').toList();
    _reason ??= reasons.isNotEmpty ? reasons.first : '';
    final holidays = Map<String, dynamic>.from((store.settings['holidays'] as Map?) ?? {});
    final dt = dayType(_date, holidays);
    final max = toNum(dt == 'normal' ? store.settings['dailyMax'] : store.settings['restMax']);
    final workers = store.workers.where((w) => w['active'] != false && (_all || w['p'] == _project)).toList();
    final chosen = store.workers.where((w) => _sel.containsKey(w['id'])).toList();
    final totH = _sel.values.fold<double>(0, (a, b) => a + b);
    final totA = chosen.fold<double>(0, (a, w) => a + _sel[w['id']]! * toNum(w['rate']));
    bool dup(String id) => store.entries.any((e) => e['workerId'] == id && e['date'] == _date && e['status'] != 'rejected');

    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          CardBox(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: DateTime.parse(_date), firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (d != null) setState(() => _date = DateFormat('yyyy-MM-dd').format(d));
                },
                child: InputDecorator(decoration: const InputDecoration(labelText: 'التاريخ', prefixIcon: Icon(Icons.calendar_today_outlined)), child: Text(fmtDate(_date))),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _project,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'المشروع'),
                items: [for (final p in projects) DropdownMenuItem(value: str(p['id']), child: Text(str(p['name']), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() { _project = v; _sel.clear(); }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: reasons.contains(_reason) ? _reason : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'السبب'),
                items: [for (final r in reasons) DropdownMenuItem(value: r, child: Text(r))],
                onChanged: (v) => setState(() => _reason = v),
              ),
              const SizedBox(height: 10),
              TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: C.slate50, borderRadius: BorderRadius.circular(12)),
                child: Text('${dayLabel[dt]}${holidays[_date] != null ? ' · ${holidays[_date]}' : ''} · المستحق = الساعات × أجر الساعة · الحد اليومي ${fmtNum(max)} س', style: const TextStyle(fontSize: 12.5, color: C.fg2)),
              ),
            ]),
          ),
          SectionTitle('العمال', trailing: Row(mainAxisSize: MainAxisSize.min, children: [const Text('كل المشاريع', style: TextStyle(fontSize: 12, color: C.fg3)), Switch(value: _all, onChanged: (v) => setState(() => _all = v))])),
          if (workers.isEmpty) const CardBox(child: EmptyState('لا يوجد عمال في هذا المشروع')),
          for (final w in workers) _row(w, max, dup(str(w['id']))),
        ]),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.slate100))),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${_sel.length} عامل · ${fmtNum(totH)} ساعة', style: const TextStyle(color: C.fg3, fontSize: 12.5)),
              Text(money(totA), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ])),
            FilledButton.icon(onPressed: _busy || _sel.isEmpty ? null : () => _submit(chosen, dt), icon: const Icon(Icons.send), label: const Text('إرسال للاعتماد')),
          ]),
        ),
      ),
    ]);
  }

  Widget _row(Json w, double max, bool dup) {
    final id = str(w['id']);
    final on = _sel.containsKey(id);
    final h = _sel[id] ?? 2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            Checkbox(value: on, onChanged: (v) => setState(() => v == true ? _sel[id] = 2 : _sel.remove(id))),
            WorkerPhoto(w['photo'], size: 36),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(w['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${w['trade']} · ${fmtNum(toNum(w['rate']))} ر.س/س', style: const TextStyle(fontSize: 12, color: C.fg3)),
            ])),
            if (on)
              Container(
                decoration: BoxDecoration(border: Border.all(color: C.slate200), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _sel[id] = (h - .5).clamp(.5, 24)), icon: const Icon(Icons.remove, size: 18)),
                  Text(fmtNum(h), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _sel[id] = (h + .5).clamp(.5, 24)), icon: const Icon(Icons.add, size: 18)),
                ]),
              ),
          ]),
          if (on || dup)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 48, top: 4),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                if (on) Pill('المستحق ${money(h * toNum(w['rate']))}', tone: Tone.blue),
                if (dup) const Pill('مسجّل مسبقًا في هذا التاريخ', tone: Tone.red),
                if (on && h > max) Pill('يتجاوز الحد اليومي (${fmtNum(max)} س)', tone: Tone.orange),
              ]),
            ),
        ]),
      ),
    );
  }

  Future<void> _submit(List<Json> chosen, String dt) async {
    final dups = chosen.where((w) => store.entries.any((e) => e['workerId'] == w['id'] && e['date'] == _date && e['status'] != 'rejected'));
    if (dups.isNotEmpty) {
      toast(context, 'يوجد سجل سابق في هذا التاريخ لـ: ${dups.map((w) => w['name']).join('، ')}', bad: true);
      return;
    }
    setState(() => _busy = true);
    var n = store.entries.fold<int>(0, (m, e) => (int.tryParse(str(e['id']).replaceAll('OT-', '')) ?? 0) > m ? int.parse(str(e['id']).replaceAll('OT-', '')) : m);
    final reason = _note.text.trim().isEmpty ? _reason : '$_reason — ${_note.text.trim()}';
    final added = [
      for (final w in chosen)
        {'id': 'OT-${'${++n}'.padLeft(4, '0')}', 'workerId': w['id'], 'projectId': _project, 'date': _date, 'hours': _sel[w['id']], 'dayType': dt, 'mult': 1, 'reason': reason, 'status': 'pending', 'note': '', 'by': store.me?['name']},
    ];
    final err = await store.save('entries', [...added, ...store.entries]);
    if (!mounted) return;
    setState(() { _busy = false; if (err == null) { _sel.clear(); _note.clear(); } });
    toast(context, err ?? 'تم إرسال ${added.length} سجل للاعتماد.', bad: err != null);
  }
}
