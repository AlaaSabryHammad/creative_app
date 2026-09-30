import 'dart:convert';
import 'llm.dart';
import '../core/logic.dart';
import 'store.dart';

const _assist = '''أنت "مساعد CREATIVE" الذكي لنظام إدارة منشأة مقاولات سعودية: العمالة والعمل الإضافي، المشاريع، وثائق المنشأة، والسيارات والمعدات.
- أجب بالعربية بدقة وإيجاز اعتمادًا على البيانات المرفقة فقط، وإذا لم تتوفر المعلومة فقل ذلك صراحة.
- احسب الأرقام بعناية. المبالغ بالريال السعودي، ومبلغ العمل الإضافي = الساعات × أجر الساعة للعامل بدون أي زيادات.
- "اليوم" هو التاريخ الوارد في today.
- لا تستخدم جداول Markdown ولا رموز ** أو #؛ استخدم أسطرًا قصيرة وقوائم تبدأ بشرطة.''';

Json _snapshot(Store s) {
  final t = boqTotals;
  final paid = s.paidIds;
  return {
    'today': todayIso(),
    'company': {'name': s.company['name'], 'city': s.company['city']},
    'settings': {'dailyMax': s.settings['dailyMax'], 'restMax': s.settings['restMax'], 'monthlyMax': s.settings['monthlyMax'], 'holidays': s.settings['holidays'], 'alertDays': s.alertDays},
    'projects': s.projects.map((p) {
      final b = t(p['boq'] as List?);
      final c = claimTotals(p['claims'] as List?, p['value']);
      return {...p, 'claims': {'count': c.list.length, 'executedToDate': c.cum.round(), 'progressPct': c.pct?.round(), 'paid': c.paid.round(), 'dueUnpaid': c.due.round(),
          'list': [for (final r in c.list) {'no': r.c['no'], 'from': r.c['from'], 'to': r.c['to'], 'amount': r.c['amount'], 'cumulative': r.cum.round(), 'net': claimNet(r.c).round(), 'status': r.c['status']}]}, 'files': ((p['files'] as List?) ?? []).map((f) => f['name']).toList(), 'boq': {'total': b.total.round(), 'executed': b.done.round(), 'progressPct': b.pct.round(), 'items': ((p['boq'] as List?) ?? []).map((r) => [r['section'], r['code'], r['desc'], r['unit'], r['qty'], r['rate'], r['done']]).toList()}};
    }).toList(),
    'trades': s.trades,
    'workers': s.workers.map((w) => {'id': w['id'], 'name': w['name'], 'trade': w['trade'], 'hourlyRate': w['rate'], 'currentProject': s.site(str(w['id'])), 'nationality': w['nat'], 'active': w['active'], 'iqamaExpiry': w['iqamaExpiry'] ?? '', 'documents': [for (final f in (w['files'] as List?) ?? const []) {'type': f['cat'], 'expiry': f['expiry'] ?? ''}]}).toList(),
    'overtime': {
      'columns': ['id', 'date', 'workerId', 'projectId', 'hours', 'amount', 'status', 'paid', 'reason'],
      'rows': s.entries.map((e) => [e['id'], e['date'], e['workerId'], e['projectId'], e['hours'], otAmount(e, s.workers).round(), e['status'], paid.contains(e['id']), e['reason']]).toList(),
    },
    'documents': s.docs.map((d) => {...d, 'files': ((d['files'] as List?) ?? []).map((f) => f['name']).toList()}).toList(),
    'vehicles': s.vehicles.map((v) => {...v, 'files': ((v['files'] as List?) ?? []).map((f) => f['name']).toList()}).toList(),
  };
}

/// Sends the chat history (user/assistant turns) to the assistant model and returns its reply text.
Future<String> askAssistant(List<Json> history) async {
  var recent = history.length > 20 ? history.sublist(history.length - 20) : history;
  while (recent.isNotEmpty && recent.first['role'] != 'user') { recent = recent.sublist(1); }
  final cfg = store.ai;
  final text = await aiComplete(cfg, cfg.assistant, what: 'المساعد الذكي', messages: recent,
      system: '$_assist\n\nبيانات المنشأة الحالية (JSON):\n${jsonEncode(_snapshot(store))}');
  return text.replaceAll('**', '').replaceAll(RegExp(r'^#+\s*', multiLine: true), '');
}
