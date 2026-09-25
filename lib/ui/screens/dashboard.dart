import 'package:flutter/material.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';
import 'requests.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final month = store.entries.where((e) => str(e['date']).startsWith(monthIso())).toList();
    final appr = month.where((e) => e['status'] == 'approved').toList();
    final pend = store.entries.where((e) => e['status'] == 'pending').toList();
    double hours(List<Json> l) => l.fold(0, (a, e) => a + toNum(e['hours']));
    final cost = appr.fold<double>(0, (a, e) => a + otAmount(e, store.workers));
    final cap = toNum(store.settings['monthlyMax']) > 0 ? toNum(store.settings['monthlyMax']) : 40;
    final perWorker = <String, double>{};
    for (final e in month.where((e) => e['status'] != 'rejected')) { perWorker[str(e['workerId'])] = (perWorker[str(e['workerId'])] ?? 0) + toNum(e['hours']); }
    final near = perWorker.entries.where((x) => x.value >= cap * .8).length;
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daily = List.generate(daysInMonth, (i) {
      final d = '${monthIso()}-${'${i + 1}'.padLeft(2, '0')}';
      final l = month.where((e) => e['date'] == d);
      return (hours(l.where((e) => e['status'] == 'approved').toList()), hours(l.where((e) => e['status'] == 'pending').toList()));
    });
    final maxDay = daily.fold<double>(8, (m, x) => (x.$1 + x.$2) > m ? x.$1 + x.$2 : m);
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('مرحبًا، ${str(store.me?['name']).split(' ').first}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        Text('ملخص العمل الإضافي لشهر ${monthName()}', style: const TextStyle(color: C.fg3)),
        const SizedBox(height: 14),
        StatGrid([
          StatTile(tone: Tone.blue, icon: Icons.schedule, label: 'الساعات المعتمدة', value: fmtNum(hours(appr)), sub: '${appr.length} سجل هذا الشهر'),
          StatTile(tone: Tone.orange, icon: Icons.hourglass_bottom, label: 'بانتظار الاعتماد', value: '${pend.length}', sub: '${fmtNum(hours(pend))} ساعة'),
          StatTile(tone: Tone.green, icon: Icons.account_balance_wallet_outlined, label: 'التكلفة المعتمدة', value: money(cost), sub: 'هذا الشهر'),
          StatTile(tone: Tone.red, icon: Icons.warning_amber_rounded, label: 'قرب الحد الشهري', value: '$near', sub: 'عامل تجاوز 80% من ${fmtNum(cap)} س'),
        ]),
        const SectionTitle('الساعات اليومية'),
        CardBox(
          child: SizedBox(
            height: 150,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < daily.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Container(height: 120 * daily[i].$2 / maxDay, decoration: const BoxDecoration(color: C.warning, borderRadius: BorderRadius.vertical(top: Radius.circular(3)))),
                      Container(height: 120 * daily[i].$1 / maxDay, color: C.primary),
                      const SizedBox(height: 4),
                      Text('${i + 1}', style: TextStyle(fontSize: 8, color: i + 1 == now.day ? C.primary700 : C.fg3)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
        const SectionTitle('آخر الطلبات بانتظار الاعتماد'),
        if (pend.isEmpty) const CardBox(child: EmptyState('لا توجد طلبات معلّقة', icon: Icons.task_alt)),
        for (final e in (pend..sort((a, b) => str(b['date']).compareTo(str(a['date'])))).take(6)) EntryCard(e),
      ]),
    );
  }
}
