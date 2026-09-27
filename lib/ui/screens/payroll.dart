import 'package:flutter/material.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  String _p = 'all';
  @override
  Widget build(BuildContext context) {
    // Same calculation as the payouts tab (balances) for the current month.
    final (from, to) = monthRange(monthIso());
    final rows = balances(store.entries, store.workers, paidSet(store.payments), from: from, to: to, proj: _p)
        .map((b) => (w: store.worker(b.workerId) ?? {'id': b.workerId, 'name': b.workerId}, n: b.byDay['normal'] ?? 0, f: b.byDay['friday'] ?? 0, h: b.byDay['holiday'] ?? 0, t: b.hours, a: b.amount, paid: b.paid, rem: b.rem))
        .toList()..sort((a, b) => b.a.compareTo(a.a));
    final totH = rows.fold<double>(0, (a, r) => a + r.t), totA = rows.fold<double>(0, (a, r) => a + r.a), totRem = rows.fold<double>(0, (a, r) => a + r.rem);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('الفترة: ${monthName()} · السجلات المعتمدة فقط', style: const TextStyle(color: C.fg3)),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: _p,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'المشروع'),
        items: [const DropdownMenuItem(value: 'all', child: Text('كل المشاريع')), for (final p in store.projects) DropdownMenuItem(value: str(p['id']), child: Text(str(p['name'])))],
        onChanged: (v) => setState(() => _p = v ?? 'all'),
      ),
      const SizedBox(height: 12),
      StatGrid([
        StatTile(tone: Tone.blue, icon: Icons.groups_outlined, label: 'عمال في المسيّر', value: '${rows.length}'),
        StatTile(tone: Tone.green, icon: Icons.schedule, label: 'إجمالي الساعات', value: fmtNum(totH)),
        StatTile(tone: Tone.green, icon: Icons.account_balance_wallet_outlined, label: 'إجمالي المستحق', value: money(totA), sub: 'المصروف ${money(totA - totRem)}'),
        StatTile(tone: Tone.orange, icon: Icons.payments_outlined, label: 'المتبقي للصرف', value: money(totRem), sub: 'جمعة وعطل ${fmtNum(rows.fold<double>(0, (a, r) => a + r.f + r.h))} س'),
      ]),
      const SectionTitle('تفصيل العمال'),
      if (rows.isEmpty) const CardBox(child: EmptyState('لا توجد ساعات معتمدة هذا الشهر')),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: CardBox(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              WorkerPhoto(r.w['photo'], size: 40),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(r.w['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('عادي ${fmtNum(r.n)} · جمعة ${fmtNum(r.f)} · عطلة ${fmtNum(r.h)} س', style: const TextStyle(fontSize: 12, color: C.fg3)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(r.a), style: const TextStyle(fontWeight: FontWeight.w800, color: C.primary700)),
                Text('${fmtNum(r.t)} س × ${fmtNum(toNum(r.w['rate']))}', style: const TextStyle(fontSize: 11.5, color: C.fg3)),
                const SizedBox(height: 4),
                r.rem > 0 ? Pill('متبقٍ ${money(r.rem)}', tone: Tone.orange) : const Pill('مصروف', tone: Tone.green),
              ]),
            ]),
          ),
        ),
    ]);
  }
}
