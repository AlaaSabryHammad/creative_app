import 'package:flutter/material.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});
  static const _icons = {'docs': Icons.folder_shared_outlined, 'vehicles': Icons.directions_car_outlined, 'workers': Icons.person_outline, 'projects': Icons.apartment_outlined};
  @override
  Widget build(BuildContext context) {
    final days = store.alertDays;
    final all = buildAlerts(docs: store.docs, vehicles: store.vehicles, workers: store.workers, projects: store.projects, days: days);
    final expired = all.where((a) => a.n < 0).toList();
    final soon = all.where((a) => a.n >= 0).toList();
    final pending = store.entries.where((e) => e['status'] == 'pending').length;
    Widget section(String title, List<AlertItem> l) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle(title, trailing: Pill('${l.length}')),
          CardBox(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: l.isEmpty
                ? const EmptyState('لا توجد عناصر', icon: Icons.task_alt)
                : Column(children: [
                    for (final a in l)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: C.slate100, borderRadius: BorderRadius.circular(10)), child: Icon(_icons[a.screen], color: C.fg2)),
                        title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        subtitle: Text(a.sub, style: const TextStyle(fontSize: 12)),
                        trailing: ExpiryChip(a.date, days: days),
                      ),
                  ]),
          ),
        ]);
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        StatGrid([
          StatTile(tone: Tone.red, icon: Icons.error_outline, label: 'منتهية', value: '${expired.length}', sub: 'تحتاج إجراءً فوريًا'),
          StatTile(tone: Tone.orange, icon: Icons.alarm, label: 'تنتهي قريبًا', value: '${soon.length}', sub: 'خلال $days يوم'),
          StatTile(tone: Tone.blue, icon: Icons.fact_check_outlined, label: 'طلبات معلّقة', value: '$pending', sub: 'بانتظار الاعتماد'),
        ]),
        section('منتهية', expired),
        section('تنتهي قريبًا', soon),
      ]),
    );
  }
}
