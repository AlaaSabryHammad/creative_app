import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/logic.dart';
import 'store.dart';

// Reading documents with Claude — same schemas and prompts as the web (src/ai.js).
const _dates = 'كل التواريخ بصيغة YYYY-MM-DD بالتقويم الميلادي؛ إذا ورد التاريخ هجريًا فحوّله إلى ما يقابله ميلاديًا.';
const _empty = 'اترك أي حقل غير موجود في المستند نصًا فارغًا "" ولا تخمّن قيمًا غير مذكورة. summary: جملة أو جملتان بالعربية تصف المستند وما استُخرج منه.';
Json _obj(List<String> keys) => {'type': 'object', 'properties': {for (final k in keys) k: {'type': 'string'}}, 'required': keys, 'additionalProperties': false};

final _kinds = <String, (Json, String Function(Json))>{
  'claim': (
    _obj(['summary', 'no', 'from', 'to', 'date', 'amount', 'previous', 'cumulative', 'deductions', 'vat', 'net', 'progress', 'contractValue', 'project']),
    (h) => 'هذا مستخلص أعمال (فاتورة إنجاز مرحلية) لمشروع إنشاءات${str(h['project']).isEmpty ? '' : ' هو «${h['project']}»'}. استخرج:\n'
        '- no رقم المستخلص (رقم فقط، مثل 3). date تاريخ المستخلص أو تاريخ إصداره. from و to بداية ونهاية الفترة التي يغطيها.\n'
        '- amount قيمة الأعمال المنفذة في هذا المستخلص وحده (الحالي) قبل الخصومات والضريبة.\n'
        '- previous قيمة الأعمال في المستخلصات السابقة. cumulative إجمالي الأعمال المنفذة حتى تاريخه (التراكمي) قبل الخصومات.\n'
        '- deductions إجمالي الخصومات على هذا المستخلص (دفعة مقدمة، محتجزات/ضمان، غرامات…). vat ضريبة القيمة المضافة. net صافي المستحق للصرف.\n'
        '- progress نسبة الإنجاز إذا وردت صراحة في المستند (رقم من 0 إلى 100 بدون %). contractValue قيمة العقد إذا وردت. project اسم المشروع كما ورد.\n'
        'كل المبالغ أرقام فقط بدون عملة أو فواصل آلاف. $_dates\n$_empty',
  ),
  'worker': (
    _obj(['summary', 'docType', 'name', 'iqama', 'nat', 'birth', 'trade', 'phone', 'iqamaExpiry', 'docNumber', 'docExpiry']),
    (h) => 'هذا مستند شخصي لعامل (إقامة، هوية، جواز سفر، رخصة قيادة، عقد عمل، شهادة صحية…). استخرج:\n'
        '- docType نوع المستند ويجب أن يكون أحد الأنواع التالية بنفس الاسم تمامًا: ${(h['docTypes'] as List).join('، ')}.\n'
        '- name اسم العامل الكامل بالعربية إن ورد، وإلا كما ورد. iqama رقم الإقامة أو الهوية (10 أرقام). birth تاريخ الميلاد.\n'
        '- nat الجنسية بصيغة المفرد العربية، واختر من هذه القائمة إن طابقت: ${(h['nationalities'] as List).join('، ')}.\n'
        '- trade المهنة كما وردت، وإذا طابقت إحدى المهن المسجلة فاكتبها بنفس الاسم تمامًا: ${(h['trades'] as List).join('، ')}.\n'
        '- phone رقم الجوال إن ورد (بصيغة 05xxxxxxxx).\n'
        '- iqamaExpiry تاريخ انتهاء الإقامة أو الهوية إن ورد في المستند.\n'
        '- docNumber رقم هذا المستند (رقم الرخصة، رقم الجواز، رقم العقد…). docExpiry تاريخ انتهاء هذا المستند.\n'
        '$_dates\n$_empty',
  ),
};

/// Reads a photo or PDF and returns the fields of [kind] ('claim' | 'worker') as strings.
Future<Json> extractDoc(String kind, Uint8List bytes, String mime, Json hints) async {
  final key = store.aiKey;
  if (key.isEmpty) throw 'لم يُضف مفتاح Claude API بعد. يضيفه مدير النظام من الإعدادات في الموقع.';
  if (bytes.length > 20 * 1024 * 1024) throw 'حجم الملف أكبر من 20 ميجابايت.';
  final (schema, prompt) = _kinds[kind]!;
  final Json doc;
  if (mime == 'application/pdf') {
    doc = {'type': 'document', 'source': {'type': 'base64', 'media_type': mime, 'data': base64Encode(bytes)}};
  } else if (RegExp(r'^image/(jpeg|png|gif|webp)$').hasMatch(mime)) {
    doc = {'type': 'image', 'source': {'type': 'base64', 'media_type': mime, 'data': base64Encode(bytes)}};
  } else {
    throw 'نوع الملف غير مدعوم للقراءة. استخدم صورة أو PDF.';
  }
  final http.Response r;
  try {
    r = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {'x-api-key': key, 'anthropic-version': '2023-06-01', 'anthropic-beta': 'server-side-fallback-2026-07-01', 'content-type': 'application/json'},
      body: jsonEncode({
        'model': 'claude-opus-5',
        'max_tokens': 16000,
        'fallbacks': 'default',
        'output_config': {'format': {'type': 'json_schema', 'schema': schema}},
        'messages': [{'role': 'user', 'content': [doc, {'type': 'text', 'text': prompt(hints)}]}],
      }),
    ).timeout(const Duration(minutes: 5));
  } catch (_) {
    throw 'تعذّر الاتصال بخدمة الذكاء الاصطناعي. تحقق من الإنترنت.';
  }
  final body = jsonDecode(utf8.decode(r.bodyBytes)) as Json;
  if (r.statusCode == 401) throw 'مفتاح Claude API غير صحيح.';
  if (r.statusCode == 429) throw 'تم تجاوز حد الطلبات، حاول بعد قليل.';
  if (r.statusCode >= 400) throw 'خطأ من خدمة الذكاء الاصطناعي: ${body['error']?['message'] ?? r.statusCode}';
  if (body['stop_reason'] == 'refusal') throw 'رفض النموذج معالجة هذا المستند.';
  if (body['stop_reason'] == 'max_tokens') throw 'الرد أطول من المسموح ولم يكتمل.';
  final text = ((body['content'] as List?) ?? []).where((b) => b['type'] == 'text').map((b) => b['text']).join();
  return Map<String, dynamic>.from(jsonDecode(text) as Map);
}
