import 'package:flutter/material.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';
import 'requests.dart';

Color projectStrip(String s) => s == 'hold' ? C.warning : s == 'done' ? C.slate400 : C.primary;

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  String _st = 'all', _q = '';
  @override
  Widget build(BuildContext context) {
    final all = store.projects;
    final list = all.where((p) => (_st == 'all' || (p['status'] ?? 'active') == _st) && (_q.isEmpty || [p['name'], p['code'], p['client'], p['site']].any((x) => str(x).contains(_q)))).toList();
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        FilterChips(items: [('all', 'الكل (${all.length})'), for (final e in projectStatus.entries) (e.key, '${e.value} (${all.where((p) => (p['status'] ?? 'active') == e.key).length})')], value: _st, onChanged: (v) => setState(() => _st = v)),
        const SizedBox(height: 10),
        SearchField('بحث بالاسم أو الرقم أو العميل', onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: 12),
        if (list.isEmpty) const CardBox(child: EmptyState('لا توجد مشاريع')),
        for (final p in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(context, p)),
      ]),
    );
  }

  Widget _card(BuildContext context, Json p) {
    final st = str(p['status']).isEmpty ? 'active' : str(p['status']);
    final nW = store.workers.where((w) => w['p'] == p['id']).length;
    final issues = projectIssues(p, nW).length;
    final boq = boqTotals(p['boq'] as List?);
    final hasBoq = ((p['boq'] as List?) ?? []).isNotEmpty;
    double? timePct;
    if (str(p['start']).isNotEmpty && str(p['end']).isNotEmpty) {
      final span = daysLeft(str(p['end'])) - daysLeft(str(p['start']));
      if (span > 0) timePct = (-daysLeft(str(p['start'])) / span * 100).clamp(0, 100).toDouble();
    }
    final left = str(p['end']).isEmpty ? null : daysLeft(str(p['end']));
    final cost = store.entries.where((e) => e['projectId'] == p['id'] && e['status'] == 'approved').fold<double>(0, (a, e) => a + otAmount(e, store.workers));
    return CardBox(
      topStrip: projectStrip(st),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectDetail(id: str(p['id'])))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Pill(projectStatus[st] ?? st, tone: st == 'active' ? Tone.green : st == 'hold' ? Tone.orange : Tone.slate),
          const Spacer(),
          issues > 0 ? Pill('$issues ملاحظة', tone: Tone.orange, icon: Icons.error_outline) : const Pill('مكتمل', tone: Tone.green, icon: Icons.check_circle_outline),
        ]),
        const SizedBox(height: 10),
        Text(str(p['name']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text([str(p['code']), str(p['client'])].where((x) => x.isNotEmpty).join(' · '), style: const TextStyle(color: C.fg3, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _meta(Icons.place_outlined, str(p['site']).isEmpty ? 'الموقع غير محدد' : str(p['site'])),
          _meta(Icons.date_range_outlined, str(p['start']).isNotEmpty && str(p['end']).isNotEmpty ? '${fmtDate(str(p['start']))} – ${fmtDate(str(p['end']))}' : 'المدة غير محددة'),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.slate50, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            _bar('إنجاز الأعمال', hasBoq ? boq.pct : null, const LinearGradient(colors: [C.success, Color(0xFF047857)])),
            const SizedBox(height: 10),
            _bar('المدة المنقضية', timePct, C.primaryGradient),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _box('قيمة العقد', toNum(p['value']) > 0 ? money(toNum(p['value'])) : '—')),
          const SizedBox(width: 8),
          Expanded(child: _box('تكلفة الإضافي', money(cost))),
        ]),
        const Divider(height: 22, color: C.slate200),
        Row(children: [
          _meta(Icons.groups_outlined, '$nW'),
          const SizedBox(width: 12),
          _meta(Icons.folder_outlined, '${((p['files'] as List?) ?? []).length}'),
          const SizedBox(width: 12),
          _meta(Icons.list_alt, '${((p['boq'] as List?) ?? []).length}'),
          const Spacer(),
          if (left != null && st == 'active') Pill(left < 0 ? 'متأخر ${-left} يوم' : 'متبقٍ $left يوم', tone: left < 0 ? Tone.red : left <= 30 ? Tone.orange : Tone.blue),
        ]),
      ]),
    );
  }

  Widget _meta(IconData i, String t) => IconText(i, t);
  Widget _box(String k, String v) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: C.slate100), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: const TextStyle(fontSize: 11.5, color: C.fg3)), FittedBox(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w800)))]),
      );
  Widget _bar(String l, double? pct, Gradient g) => Column(children: [
        Row(children: [Text(l, style: const TextStyle(fontSize: 12.5, color: C.fg3)), const Spacer(), Text(pct == null ? '—' : '${pct.round()}%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))]),
        const SizedBox(height: 5),
        ProgressBar(pct ?? 0, gradient: g),
      ]);
}

class ProjectDetail extends StatelessWidget {
  final String id;
  const ProjectDetail({super.key, required this.id});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.project(id);
        if (p == null) return Scaffold(appBar: AppBar(), body: const EmptyState('المشروع غير موجود'));
        final workers = store.workers.where((w) => w['p'] == id).toList();
        final entries = store.entries.where((e) => e['projectId'] == id).toList()..sort((a, b) => str(b['date']).compareTo(str(a['date'])));
        final boq = ((p['boq'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final files = ((p['files'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final t = boqTotals(boq);
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              title: Text(str(p['name'])),
              bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, labelColor: C.primary700, indicatorColor: C.primary, tabs: [
                const Tab(text: 'البيانات'),
                Tab(text: 'جدول الكميات (${boq.length})'),
                Tab(text: 'الملفات (${files.length})'),
                Tab(text: 'العمال (${workers.length})'),
                Tab(text: 'الإضافي (${entries.length})'),
              ]),
            ),
            body: TabBarView(children: [
              ListView(padding: const EdgeInsets.all(16), children: [
                IssuesBox(projectIssues(p, workers.length)),
                const SizedBox(height: 12),
                CardBox(child: Column(children: [
                  KV('رقم المشروع', str(p['code'])),
                  KV('المالك / العميل', str(p['client'])),
                  KV('الموقع', str(p['site'])),
                  KV('مدير المشروع', str(p['manager'])),
                  KV('مشرف الموقع', str(p['sup'])),
                  KV('قيمة العقد', toNum(p['value']) > 0 ? money(toNum(p['value'])) : ''),
                  KV('الحالة', projectStatus[p['status'] ?? 'active'] ?? ''),
                  KV('تاريخ البداية', fmtDate(str(p['start']))),
                  KV('تاريخ النهاية', fmtDate(str(p['end']))),
                  KV('الوصف', str(p['desc'])),
                ])),
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                if (boq.isEmpty) const CardBox(child: EmptyState('لا يوجد جدول كميات — أضفه من الموقع'))
                else ...[
                  StatGrid([
                    StatTile(tone: Tone.blue, icon: Icons.list_alt, label: 'عدد البنود', value: '${boq.length}'),
                    StatTile(tone: Tone.green, icon: Icons.payments_outlined, label: 'الإجمالي', value: money(t.total)),
                    StatTile(tone: Tone.orange, icon: Icons.construction, label: 'المنفذ', value: money(t.done)),
                    StatTile(tone: Tone.red, icon: Icons.pie_chart_outline, label: 'نسبة الإنجاز', value: '${t.pct.toStringAsFixed(1)}%'),
                  ]),
                  const SizedBox(height: 12),
                  for (final r in boq) _boqRow(r),
                ],
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                CardBox(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: files.isEmpty ? const EmptyState('لا توجد ملفات') : Column(children: [for (final f in files) FileTile(f)])),
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                if (workers.isEmpty) const CardBox(child: EmptyState('لا يوجد عمال في هذا المشروع')),
                for (final w in workers)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: CardBox(padding: const EdgeInsets.all(10), child: Row(children: [
                    WorkerPhoto(w['photo'], size: 40), const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(str(w['name']), style: const TextStyle(fontWeight: FontWeight.w700)), Text(str(w['trade']), style: const TextStyle(fontSize: 12, color: C.fg3))])),
                    Text('${fmtNum(toNum(w['rate']))} ر.س', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]))),
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                if (entries.isEmpty) const CardBox(child: EmptyState('لا توجد سجلات عمل إضافي')),
                for (final e in entries.take(50)) EntryCard(e),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _boqRow(Json r) {
    final qty = toNum(r['qty']), rate = toNum(r['rate']), done = toNum(r['done']);
    final pct = qty > 0 ? (done / qty * 100).clamp(0, 100).toDouble() : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (str(r['code']).isNotEmpty) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: Pill(str(r['code']))),
            Expanded(child: Text(str(r['section']), style: const TextStyle(fontSize: 12, color: C.primary700, fontWeight: FontWeight.w700))),
            Pill('${pct.round()}%', tone: pct >= 100 ? Tone.green : pct > 0 ? Tone.orange : Tone.slate),
          ]),
          const SizedBox(height: 6),
          Text(str(r['desc']), style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5)),
          const SizedBox(height: 6),
          Row(children: [
            Text('${fmtNum(qty)} ${str(r['unit'])} × ${fmtNum(rate)}', style: const TextStyle(fontSize: 12.5, color: C.fg3)),
            const Spacer(),
            Text(money(qty * rate), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          ProgressBar(pct),
        ]),
      ),
    );
  }
}
