import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/logic.dart';
import 'store.dart';

// Claude has no official Dart SDK, so the Messages API is called over HTTPS directly.
const _assist = '''أنت "مساعد CREATIVE" الذكي لنظام إدارة منشأة مقاولات سعودية: العمالة والعمل الإضافي، المشاريع، وثائق المنشأة، والسيارات والمعدات.
- أجب بالعربية بدقة وإيجاز اعتمادًا على البيانات المرفقة فقط، وإذا لم تتوفر المعلومة فقل ذلك صراحة.
- احسب الأرقام بعناية. المبالغ بالريال السعودي، ومبلغ العمل الإضافي = الساعات × أجر الساعة للعامل بدون أي زيادات.
- "اليوم" هو التاريخ الوارد في today.
- لا تستخدم جداول Markdown ولا رموز ** أو #؛ استخدم أسطرًا قصيرة وقوائم تبدأ بشرطة.''';

Json _snapshot(Store s) {
  final t = boqTotals;
  final paid = paidSet(s.payments);
  return {
    'today': todayIso(),
    'company': {'name': s.company['name'], 'city': s.company['city']},
    'settings': {'dailyMax': s.settings['dailyMax'], 'restMax': s.settings['restMax'], 'monthlyMax': s.settings['monthlyMax'], 'holidays': s.settings['holidays'], 'alertDays': s.alertDays},
    'projects': s.projects.map((p) {
      final b = t(p['boq'] as List?);
      return {...p, 'files': ((p['files'] as List?) ?? []).map((f) => f['name']).toList(), 'boq': {'total': b.total.round(), 'executed': b.done.round(), 'progressPct': b.pct.round(), 'items': ((p['boq'] as List?) ?? []).map((r) => [r['section'], r['code'], r['desc'], r['unit'], r['qty'], r['rate'], r['done']]).toList()}};
    }).toList(),
    'trades': s.trades,
    'workers': s.workers.map((w) => {'id': w['id'], 'name': w['name'], 'trade': w['trade'], 'hourlyRate': w['rate'], 'project': w['p'], 'nationality': w['nat'], 'active': w['active'], 'iqamaExpiry': w['iqamaExpiry'] ?? ''}).toList(),
    'overtime': {
      'columns': ['id', 'date', 'workerId', 'projectId', 'hours', 'amount', 'status', 'paid', 'reason'],
      'rows': s.entries.map((e) => [e['id'], e['date'], e['workerId'], e['projectId'], e['hours'], otAmount(e, s.workers).round(), e['status'], paid.contains(e['id']), e['reason']]).toList(),
    },
    'overtimePayouts': s.payments.map((p) => {'id': p['id'], 'from': p['from'], 'to': p['to'], 'paidOn': p['date'], 'method': p['method'], 'total': p['total'], 'items': p['items']}).toList(),
    'documents': s.docs.map((d) => {...d, 'files': ((d['files'] as List?) ?? []).map((f) => f['name']).toList()}).toList(),
    'vehicles': s.vehicles.map((v) => {...v, 'files': ((v['files'] as List?) ?? []).map((f) => f['name']).toList()}).toList(),
  };
}

/// Sends the chat history (user/assistant turns) and returns the assistant's reply text.
Future<String> askAssistant(List<Json> history) async {
  final key = store.aiKey;
  if (key.isEmpty) throw 'لم يُضف مفتاح Claude API بعد. يضيفه مدير النظام من الإعدادات في الموقع.';
  var recent = history.length > 20 ? history.sublist(history.length - 20) : history;
  while (recent.isNotEmpty && recent.first['role'] != 'user') { recent = recent.sublist(1); }
  final http.Response r;
  try {
    r = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {'x-api-key': key, 'anthropic-version': '2023-06-01', 'anthropic-beta': 'server-side-fallback-2026-07-01', 'content-type': 'application/json'},
      body: jsonEncode({
        'model': 'claude-opus-5',
        'max_tokens': 16000,
        'fallbacks': 'default',
        'system': [
          {'type': 'text', 'text': _assist},
          {'type': 'text', 'text': 'بيانات المنشأة الحالية (JSON):\n${jsonEncode(_snapshot(store))}', 'cache_control': {'type': 'ephemeral'}},
        ],
        'messages': recent,
      }),
    ).timeout(const Duration(minutes: 10));
  } catch (_) {
    throw 'تعذّر الاتصال بخدمة الذكاء الاصطناعي. تحقق من الإنترنت.';
  }
  final body = jsonDecode(utf8.decode(r.bodyBytes)) as Json;
  if (r.statusCode == 401) throw 'مفتاح Claude API غير صحيح.';
  if (r.statusCode == 429) throw 'تم تجاوز حد الطلبات، حاول بعد قليل.';
  if (r.statusCode >= 400) throw 'خطأ من خدمة الذكاء الاصطناعي: ${body['error']?['message'] ?? r.statusCode}';
  if (body['stop_reason'] == 'refusal') throw 'رفض النموذج معالجة هذا الطلب.';
  final text = ((body['content'] as List?) ?? []).where((b) => b['type'] == 'text').map((b) => b['text']).join();
  return text.replaceAll('**', '').replaceAll(RegExp(r'^#+\s*', multiLine: true), '');
}
