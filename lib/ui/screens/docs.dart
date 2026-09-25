import 'package:flutter/material.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';

class DocsScreen extends StatefulWidget {
  const DocsScreen({super.key});
  @override
  State<DocsScreen> createState() => _DocsScreenState();
}

class _DocsScreenState extends State<DocsScreen> {
  String _st = 'all', _q = '';
  String _state(Json d) {
    final e = str(d['expiry']);
    if (e.isEmpty) return 'none';
    final n = daysLeft(e);
    return n < 0 ? 'expired' : n <= store.alertDays ? 'soon' : 'valid';
  }

  @override
  Widget build(BuildContext context) {
    final all = store.docs;
    int n(String s) => all.where((d) => _state(d) == s).length;
    final list = all.where((d) => (_st == 'all' || _state(d) == _st) && (_q.isEmpty || [d['name'], d['number'], d['issuer']].any((x) => str(x).contains(_q)))).toList()
      ..sort((a, b) => (str(a['expiry']).isEmpty ? '9999' : str(a['expiry'])).compareTo(str(b['expiry']).isEmpty ? '9999' : str(b['expiry'])));
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        StatGrid([
          StatTile(tone: Tone.blue, icon: Icons.folder_shared_outlined, label: 'إجمالي الوثائق', value: '${all.length}'),
          StatTile(tone: Tone.green, icon: Icons.verified_outlined, label: 'سارية', value: '${n('valid')}'),
          StatTile(tone: Tone.orange, icon: Icons.alarm, label: 'تنتهي قريبًا', value: '${n('soon')}'),
          StatTile(tone: Tone.red, icon: Icons.error_outline, label: 'منتهية', value: '${n('expired')}'),
        ]),
        const SizedBox(height: 12),
        FilterChips(items: const [('all', 'الكل'), ('expired', 'منتهية'), ('soon', 'تنتهي قريبًا'), ('valid', 'سارية')], value: _st, onChanged: (v) => setState(() => _st = v)),
        const SizedBox(height: 10),
        SearchField('بحث بالاسم أو الرقم أو الجهة', onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: 12),
        if (list.isEmpty) const CardBox(child: EmptyState('لا توجد وثائق')),
        for (final d in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CardBox(
              onTap: () => _details(context, d),
              child: Row(children: [
                Container(width: 46, height: 46, decoration: BoxDecoration(color: C.primary50, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.description_outlined, color: C.primary700)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(str(d['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text([str(d['type']), str(d['number'])].where((x) => x.isNotEmpty).join(' · '), style: const TextStyle(fontSize: 12, color: C.fg3)),
                  const SizedBox(height: 6),
                  ExpiryChip(str(d['expiry']), days: store.alertDays),
                ])),
                if (((d['files'] as List?) ?? []).isNotEmpty) Pill('${(d['files'] as List).length}', icon: Icons.attach_file, tone: Tone.blue),
              ]),
            ),
          ),
      ]),
    );
  }

  void _details(BuildContext context, Json d) {
    final files = ((d['files'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .65,
        builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Text(str(d['name']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ExpiryChip(str(d['expiry']), days: store.alertDays),
          const SizedBox(height: 12),
          KV('النوع', str(d['type'])),
          KV('رقم الوثيقة', str(d['number'])),
          KV('الجهة المصدرة', str(d['issuer'])),
          KV('تاريخ الإصدار', fmtDate(str(d['issue']))),
          KV('تاريخ الانتهاء', fmtDate(str(d['expiry']))),
          KV('ملاحظات', str(d['notes'])),
          const SectionTitle('الملفات'),
          if (files.isEmpty) const Text('لا توجد ملفات', style: TextStyle(color: C.fg3)),
          for (final f in files) FileTile(f),
        ]),
      ),
    );
  }
}
