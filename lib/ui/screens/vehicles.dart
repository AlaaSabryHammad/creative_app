import 'package:flutter/material.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});
  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  String _st = 'all', _q = '';
  IconData _icon(String t) => t.contains('شاحنة') ? Icons.local_shipping_outlined : t.contains('باص') ? Icons.directions_bus_outlined : (t.contains('معدة') || t.contains('رافعة')) ? Icons.precision_manufacturing_outlined : Icons.directions_car_outlined;

  @override
  Widget build(BuildContext context) {
    final all = store.vehicles;
    final list = all.where((v) => (_st == 'all' || v['status'] == _st) && (_q.isEmpty || [v['plate'], v['make'], v['model'], store.worker(str(v['driver']))?['name']].any((x) => str(x).contains(_q)))).toList();
    final maint = all.fold<double>(0, (a, v) => a + ((v['log'] as List?) ?? []).fold<double>(0, (b, x) => b + toNum(x['cost'])));
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        StatGrid([
          StatTile(tone: Tone.blue, icon: Icons.directions_car_outlined, label: 'إجمالي الأسطول', value: '${all.length}'),
          StatTile(tone: Tone.orange, icon: Icons.build_outlined, label: 'في الصيانة', value: '${all.where((v) => v['status'] == 'maint').length}'),
          StatTile(tone: Tone.green, icon: Icons.account_balance_wallet_outlined, label: 'تكاليف الصيانة', value: money(maint)),
        ]),
        const SizedBox(height: 12),
        FilterChips(items: [('all', 'الكل (${all.length})'), for (final e in vehicleStatus.entries) (e.key, '${e.value} (${all.where((v) => v['status'] == e.key).length})')], value: _st, onChanged: (v) => setState(() => _st = v)),
        const SizedBox(height: 10),
        SearchField('بحث باللوحة أو الطراز أو السائق', onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: 12),
        if (list.isEmpty) const CardBox(child: EmptyState('لا توجد مركبات')),
        for (final v in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(context, v)),
      ]),
    );
  }

  Widget _card(BuildContext context, Json v) {
    final st = str(v['status']).isEmpty ? 'active' : str(v['status']);
    final issues = vehicleIssues(v).length;
    final cost = ((v['log'] as List?) ?? []).fold<double>(0, (a, x) => a + toNum(x['cost']));
    return CardBox(
      topStrip: st == 'maint' ? C.warning : st == 'out' ? C.slate400 : C.primary,
      onTap: () => _details(context, v),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Pill(vehicleStatus[st] ?? st, tone: st == 'active' ? Tone.green : st == 'maint' ? Tone.orange : Tone.slate),
          const Spacer(),
          issues > 0 ? Pill('$issues ملاحظة', tone: Tone.orange, icon: Icons.error_outline) : const Pill('مكتمل', tone: Tone.green, icon: Icons.check_circle_outline),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: C.primary50, borderRadius: BorderRadius.circular(14)), child: Icon(_icon(str(v['type'])), color: C.primary700)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${str(v['make'])} ${str(v['model'])}'.trim().isEmpty ? 'مركبة بدون طراز' : '${str(v['make'])} ${str(v['model'])}'.trim(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text([str(v['type']), str(v['year']), str(v['color'])].where((x) => x.isNotEmpty).join(' · '), style: const TextStyle(fontSize: 12.5, color: C.fg3)),
          ])),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 3, 10, 5),
            decoration: BoxDecoration(border: Border.all(color: C.fg1, width: 2), borderRadius: BorderRadius.circular(8)),
            child: Column(children: [const Text('KSA', style: TextStyle(fontSize: 8, letterSpacing: 2, color: C.fg3)), Text(str(v['plate']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))]),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 4, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.person_outline, size: 15, color: C.slate400), const SizedBox(width: 4), Text(str(store.worker(str(v['driver']))?['name']).isEmpty ? 'بدون سائق' : str(store.worker(str(v['driver']))?['name']), style: const TextStyle(fontSize: 12.5))]),
          Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.apartment_outlined, size: 15, color: C.slate400), const SizedBox(width: 4), Text(str(store.project(str(v['project']))?['name']).isEmpty ? 'غير مخصصة لمشروع' : str(store.project(str(v['project']))?['name']), style: const TextStyle(fontSize: 12.5))]),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          for (final e in vehicleExpiries) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: _exp(e[1], str(v[e[0]])))),
        ]),
        const Divider(height: 22, color: C.slate200),
        Row(children: [
          const Icon(Icons.speed, size: 15, color: C.slate400), const SizedBox(width: 4), Text(toNum(v['odometer']) > 0 ? '${fmtNum(toNum(v['odometer']))} كم' : '—', style: const TextStyle(fontSize: 12.5)),
          const SizedBox(width: 14),
          const Icon(Icons.build_outlined, size: 15, color: C.slate400), const SizedBox(width: 4), Text(money(cost), style: const TextStyle(fontSize: 12.5)),
          const Spacer(),
          const Icon(Icons.arrow_forward, color: C.primary, size: 18),
        ]),
      ]),
    );
  }

  Widget _exp(String label, String date) {
    final n = date.isEmpty ? null : daysLeft(date);
    final tone = n == null ? Tone.slate : n < 0 ? Tone.red : n <= store.alertDays ? Tone.orange : Tone.green;
    final t = n == null ? 'غير مسجّل' : n < 0 ? 'منتهية ${-n} يوم' : n <= store.alertDays ? 'بعد $n يوم' : fmtDate(date);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 10.5, color: C.fg3)), FittedBox(child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: tone.fg)))]),
    );
  }

  void _details(BuildContext context, Json v) {
    final files = ((v['files'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final log = ((v['log'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList()..sort((a, b) => str(b['date']).compareTo(str(a['date'])));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .8,
        builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Text('${str(v['make'])} ${str(v['model'])} — ${str(v['plate'])}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          IssuesBox(vehicleIssues(v)),
          const SizedBox(height: 12),
          KV('النوع', str(v['type'])), KV('سنة الصنع', str(v['year'])), KV('اللون', str(v['color'])),
          KV('رقم الهيكل', str(v['vin'])), KV('الرقم التسلسلي', str(v['serial'])),
          KV('السائق', str(store.worker(str(v['driver']))?['name'])), KV('المشروع', str(store.project(str(v['project']))?['name'])),
          KV('العداد', toNum(v['odometer']) > 0 ? '${fmtNum(toNum(v['odometer']))} كم' : ''),
          for (final e in vehicleExpiries) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [SizedBox(width: 120, child: Text('انتهاء ${e[1]}', style: const TextStyle(color: C.fg3, fontSize: 13))), ExpiryChip(str(v[e[0]]), days: store.alertDays)])),
          const SectionTitle('سجل الصيانة'),
          if (log.isEmpty) const Text('لا توجد سجلات صيانة', style: TextStyle(color: C.fg3)),
          for (final x in log) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.build_circle_outlined, color: C.primary), title: Text(str(x['desc'])), subtitle: Text(fmtDate(str(x['date']))), trailing: Text(toNum(x['cost']) > 0 ? money(toNum(x['cost'])) : '—', style: const TextStyle(fontWeight: FontWeight.w700))),
          const SectionTitle('الملفات'),
          if (files.isEmpty) const Text('لا توجد ملفات', style: TextStyle(color: C.fg3)),
          for (final f in files) FileTile(f),
        ]),
      ),
    );
  }
}
