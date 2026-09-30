import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../core/logic.dart';
import '../../core/pay.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';

const attLabel = {'present': 'حاضر', 'absent': 'غائب', 'leave': 'إجازة', 'sick': 'مرضية', 'off': 'راحة'};
const attTone = {'present': Tone.green, 'absent': Tone.red, 'leave': Tone.blue, 'sick': Tone.orange, 'off': Tone.slate};

/// The phone's position, or null when location is off or refused (the sheet is saved either way).
Future<Position?> _locate() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)));
  } catch (_) {
    return null;
  }
}

/// Daily sheet (web: src/attendance.jsx): attendance, breakfast/lunch and overtime for one project and day.
/// Workers are not assigned to projects: the sheet lists those whose latest record is here, and any worker can be added.
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});
  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  String _date = todayIso();
  String? _project;
  List<Json>? _att;
  Map<String, Json> _sites = {};
  final Map<String, Json> _edits = {};
  final List<String> _extra = [];
  bool _locked = false, _busy = false;
  String? _reason;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _att = null; _edits.clear(); _extra.clear(); });
    final r = await Future.wait([store.fetchAll('attendance', (q) => q.eq('date', _date)), store.monthLocked(_date), store.sitesAt(_date)]);
    if (mounted) setState(() { _att = r[0] as List<Json>; _locked = r[1] as bool; _sites = r[2] as Map<String, Json>; });
  }

  Json? _saved(String id) => _att?.cast<Json?>().firstWhere((a) => a!['worker_id'] == id, orElse: () => null);
  Json _base(String id, PaySettings p) {
    final a = _saved(id);
    return a != null
        ? {'status': a['status'], 'breakfast': a['breakfast'] == true, 'lunch': a['lunch'] == true, 'note': str(a['note'])}
        : {'status': 'present', 'breakfast': p.mealsDefault, 'lunch': p.mealsDefault, 'note': ''};
  }
  Json _row(String id, PaySettings p) => {..._base(id, p), 'ot': 0.0, ...?_edits[id]};
  void _set(String id, PaySettings p, Json patch) => setState(() {
        final prev = _row(id, p);
        final next = {...prev, ...patch};
        if (patch['status'] != null && patch['status'] != 'present') next.addAll({'breakfast': false, 'lunch': false, 'ot': 0.0});
        if (patch['status'] == 'present' && prev['status'] != 'present') next.addAll({'breakfast': p.mealsDefault, 'lunch': p.mealsDefault});
        _edits[id] = next;
      });
  List<Json> _dayOt(String id) => store.entries.where((e) => e['workerId'] == id && e['date'] == _date && e['status'] != 'rejected').toList();

  @override
  Widget build(BuildContext context) {
    final p = store.pay;
    final projects = store.projects;
    if (projects.isEmpty) return const Center(child: EmptyState('لا توجد مشاريع متاحة لك'));
    _project ??= str(projects.first['id']);
    final site = store.project(_project);
    final reasons = ((store.lookups['otReasons'] as List?) ?? const ['أعمال طارئة']).map((e) => '$e').toList();
    _reason ??= reasons.isNotEmpty ? reasons.first : '';
    final holidays = Map<String, dynamic>.from((store.settings['holidays'] as Map?) ?? {});
    final dt = dayType(_date, holidays);
    final max = toNum(dt == 'normal' ? store.settings['dailyMax'] : store.settings['restMax']);

    String siteOf(String id) => str(_sites[id]?['project_id']);
    final inProject = store.allWorkers.where((w) => w['active'] != false && siteOf(str(w['id'])) == _project).map((w) => str(w['id']));
    final here = (_att ?? []).where((a) => a['project_id'] == _project).map((a) => str(a['worker_id']));
    final ids = {...inProject, ...here, ..._extra}.toList();
    final everyone = [for (final id in ids) ?store.worker(id)];
    // Recorded today at another project (the sites also see projects outside this user's scope).
    Json? elsewhere(String id) {
      final a = _saved(id), s = _sites[id];
      if (a != null) return a['project_id'] != _project ? a : null;
      return s != null && str(s['date']) == _date && siteOf(id) != _project ? s : null;
    }
    final editable = everyone.where((w) => elsewhere(str(w['id'])) == null).toList();
    final dirty = editable.where((w) => _saved(str(w['id'])) == null || _edits.containsKey(str(w['id']))).toList();
    final rows = [for (final w in editable) (w, _row(str(w['id']), p))];
    int count(String s) => rows.where((x) => x.$2['status'] == s).length;
    final bf = rows.where((x) => x.$2['breakfast'] == true).length, ln = rows.where((x) => x.$2['lunch'] == true).length;
    final otNew = rows.where((x) => x.$2['status'] == 'present' && toNum(x.$2['ot']) > 0 && _dayOt(str(x.$1['id'])).isEmpty).toList();
    final others = store.allWorkers.where((w) => w['active'] != false && !ids.contains(w['id']) && elsewhere(str(w['id'])) == null).toList();

    void all(Json Function(Json r) patch) => setState(() {
          for (final w in editable) {
            final id = str(w['id']);
            final r = {..._row(id, p), ...patch(_row(id, p))};
            if (r['status'] != 'present') r.addAll({'breakfast': false, 'lunch': false, 'ot': 0.0});
            _edits[id] = r;
          }
        });

    Future<void> save() async {
      setState(() => _busy = true);
      final pos = await _locate();
      final lat = toNum(site?['lat']), lng = toNum(site?['lng']);
      final distance = pos != null && lat != 0 && lng != 0 ? distanceM(pos.latitude, pos.longitude, lat, lng) : null;
      final payload = [
        for (final w in dirty)
          () {
            final id = str(w['id']), r = _row(id, p), s = _saved(id), present = r['status'] == 'present';
            return {
              'worker_id': id, 'date': _date, 'project_id': _project, 'status': r['status'], 'breakfast': present && r['breakfast'] == true, 'lunch': present && r['lunch'] == true,
              'breakfast_price': s?['breakfast_price'] ?? p.breakfast, 'lunch_price': s?['lunch_price'] ?? p.lunch, 'note': str(r['note']).trim(),
              'by_name': s?['by_name'] ?? store.myName, 'lat': pos?.latitude, 'lng': pos?.longitude, 'accuracy': pos?.accuracy, 'distance': distance,
            };
          }(),
      ];
      var err = payload.isEmpty ? null : await store.saveAttendance(payload);
      if (err == null && otNew.isNotEmpty) {
        err = await store.insertOt([
          for (final (w, r) in otNew)
            {'workerId': w['id'], 'projectId': _project, 'date': _date, 'hours': toNum(r['ot']), 'dayType': dt, 'rate': w['rate'], 'reason': _reason, 'status': 'pending', 'note': '', 'by': store.myName},
        ]);
      }
      if (!context.mounted) return;
      setState(() => _busy = false);
      if (err != null) return toast(context, err, bad: true);
      toast(context, 'تم حفظ كشف ${fmtDate(_date)} لـ ${payload.length} عامل وأُرسل للاعتماد${otNew.isNotEmpty ? ' و${otNew.length} سجل إضافي للاعتماد' : ''}'
          '${distance != null && distance > p.gpsRadius ? ' — تنبيه: على بعد ${fmtNum(distance)} م من الموقع' : ''}.');
      _load();
    }

    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (_locked)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: C.warning50, borderRadius: BorderRadius.circular(12)),
                child: const Row(children: [Icon(Icons.lock_outline, color: C.warning), SizedBox(width: 8), Expanded(child: Text('هذا الشهر مقفل لأن مسيّر رواتبه معتمد.', style: TextStyle(color: C.warning800, fontWeight: FontWeight.w600)))]),
              ),
            CardBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: DateTime.parse(_date), firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (d != null) { _date = DateFormat('yyyy-MM-dd').format(d); _load(); }
                  },
                  child: InputDecorator(decoration: const InputDecoration(labelText: 'التاريخ', prefixIcon: Icon(Icons.calendar_today_outlined)), child: Text(fmtDate(_date))),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _project,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'المشروع / الموقع'),
                  items: [for (final pr in projects) DropdownMenuItem(value: str(pr['id']), child: Text(str(pr['name']), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() { _project = v; _edits.clear(); _extra.clear(); }),
                ),
                const SizedBox(height: 10),
                Text('${dayLabel[dt]}${holidays[_date] != null ? ' · ${holidays[_date]}' : ''} · الفطار ${fmtNum(p.breakfast)} · الغداء ${fmtNum(p.lunch)} ر.س (بدل فوق الراتب) · حد الإضافي ${fmtNum(max)} س',
                    style: const TextStyle(fontSize: 12.5, color: C.fg3)),
              ]),
            ),
            const SizedBox(height: 12),
            StatGrid([
              StatTile(tone: Tone.green, icon: Icons.how_to_reg_outlined, label: 'حاضر', value: '${count('present')}', sub: 'من ${editable.length} عامل'),
              StatTile(tone: Tone.red, icon: Icons.person_off_outlined, label: 'غائب', value: '${count('absent')}', sub: 'إجازة ${count('leave')} · مرضية ${count('sick')}'),
              StatTile(tone: Tone.orange, icon: Icons.restaurant_outlined, label: 'بدل الوجبات', value: money(bf * p.breakfast + ln * p.lunch), sub: 'فطار $bf · غداء $ln'),
              StatTile(tone: Tone.blue, icon: Icons.schedule, label: 'إضافي جديد', value: '${fmtNum(otNew.fold<double>(0, (a, x) => a + toNum(x.$2['ot'])))} س', sub: '${otNew.length} سجل للاعتماد'),
            ]),
            const SizedBox(height: 8),
            if (!_locked)
              Wrap(spacing: 8, runSpacing: 6, children: [
                ActionChip(avatar: const Icon(Icons.done_all, size: 16), label: const Text('الكل حاضر'), onPressed: () => all((_) => {'status': 'present'})),
                ActionChip(label: const Text('فطار للحاضرين'), onPressed: () => all((r) => {'breakfast': r['status'] == 'present'})),
                ActionChip(label: const Text('غداء للحاضرين'), onPressed: () => all((r) => {'lunch': r['status'] == 'present'})),
                ActionChip(label: const Text('بدون وجبات'), onPressed: () => all((_) => {'breakfast': false, 'lunch': false})),
              ]),
            if (!_locked)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: DropdownButtonFormField<String>(
                  initialValue: reasons.contains(_reason) ? _reason : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'سبب الإضافي', isDense: true),
                  items: [for (final r in reasons) DropdownMenuItem(value: r, child: Text(r))],
                  onChanged: (v) => setState(() => _reason = v),
                ),
              ),
            const SizedBox(height: 10),
            if (_att == null) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
            if (_att != null && everyone.isEmpty) const CardBox(child: EmptyState('لا يوجد عمال في هذا الموقع بعد — أضفهم من الأسفل، وسيظهرون تلقائيًا في الكشوف التالية')),
            if (_att != null)
              for (final w in everyone) _card(w, p, max, elsewhere(str(w['id']))),
            if (!_locked && others.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.person_add_alt),
                label: const Text('إضافة عامل يعمل هنا اليوم'),
                onPressed: () async {
                  final id = await showModalBottomSheet<String>(
                    context: context,
                    builder: (c) => ListView(children: [
                      for (final w in others) ListTile(leading: WorkerPhoto(w['photo'], size: 34), title: Text(str(w['name'])), subtitle: Text('${w['trade']} · ${siteOf(str(w['id'])).isEmpty ? 'بدون موقع سابق' : str(store.project(siteOf(str(w['id'])))?['name'])}'), onTap: () => Navigator.pop(c, str(w['id']))),
                    ]),
                  );
                  if (id != null) setState(() => _extra.add(id));
                },
              ),
          ]),
        ),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.slate100))),
          child: Row(children: [
            Expanded(child: Text(dirty.isEmpty ? 'كل التغييرات محفوظة' : '${dirty.length} عامل بتغييرات غير محفوظة\nيُسجَّل موقعك مع الكشف', style: const TextStyle(color: C.fg3, fontSize: 12.5))),
            FilledButton.icon(
              onPressed: _busy || _locked || dirty.isEmpty || _att == null ? null : save,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
              label: const Text('حفظ الكشف'),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _card(Json w, PaySettings p, double max, Json? other) {
    final id = str(w['id']);
    final r = _row(id, p), present = r['status'] == 'present', done = _dayOt(id), off = _locked || other != null;
    final v = store.vehicles.cast<Json?>().firstWhere((x) => x!['driver'] == id, orElse: () => null);
    final h = toNum(r['ot']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CardBox(
        padding: const EdgeInsets.all(12),
        topStrip: _edits.containsKey(id) || (_saved(id) == null && other == null) ? C.primary : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            WorkerPhoto(w['photo'], size: 40),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(w['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('$id · ${w['trade']}', style: const TextStyle(fontSize: 12, color: C.fg3)),
            ])),
            if (v != null) Pill(str(v['plate']), icon: Icons.directions_car_outlined),
          ]),
          if (other != null) Padding(padding: const EdgeInsets.only(top: 6), child: Pill('مسجّل اليوم في ${str(store.project(str(other['project_id']))?['name'])}', tone: Tone.orange)),
          if (other == null && _saved(id) != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: switch (str(_saved(id)!['approval'])) {
              'pending' => const Pill('بانتظار الاعتماد', tone: Tone.orange),
              'rejected' => const Pill('مرفوض — عدّله وأعد الحفظ', tone: Tone.red),
              _ => const Pill('معتمد', tone: Tone.green),
            }),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in attLabel.keys)
              ChoiceChip(
                label: Text(attLabel[s]!),
                selected: r['status'] == s,
                onSelected: off ? null : (_) => _set(id, p, {'status': s}),
                selectedColor: attTone[s]!.bg,
                labelStyle: TextStyle(color: r['status'] == s ? attTone[s]!.fg : C.fg2, fontWeight: FontWeight.w700, fontSize: 13),
                side: BorderSide(color: r['status'] == s ? attTone[s]!.solid : C.slate200),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
              ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Checkbox(value: r['breakfast'] == true, onChanged: off || !present ? null : (x) => _set(id, p, {'breakfast': x == true})),
            const Text('فطار'),
            const SizedBox(width: 6),
            Checkbox(value: r['lunch'] == true, onChanged: off || !present ? null : (x) => _set(id, p, {'lunch': x == true})),
            const Text('غداء'),
            const Spacer(),
            if (done.isNotEmpty)
              Pill('إضافي ${fmtNum(done.fold<double>(0, (a, e) => a + toNum(e['hours'])))} س · ${done.any((e) => e['status'] == 'approved') ? 'معتمد' : 'بانتظار'}', tone: Tone.blue)
            else
              Container(
                decoration: BoxDecoration(border: Border.all(color: C.slate200), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(visualDensity: VisualDensity.compact, onPressed: off || !present || h <= 0 ? null : () => _set(id, p, {'ot': (h - .5).clamp(0, 24).toDouble()}), icon: const Icon(Icons.remove, size: 18)),
                  Text(h > 0 ? '${fmtNum(h)} س' : 'إضافي', style: TextStyle(fontWeight: FontWeight.w800, color: h > max ? C.warning : C.fg1)),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: off || !present ? null : () => _set(id, p, {'ot': (h + .5).clamp(0, 24).toDouble()}), icon: const Icon(Icons.add, size: 18)),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }
}
