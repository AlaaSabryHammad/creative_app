import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/logic.dart';

/// AI providers set up by the admin on the website (web: src/ai.js OT_AI_PROVIDERS / otAiConfig).
/// Claude is called directly; the others through the 'ai' Edge Function, which adds the key.
const aiProviders = {
  'anthropic': 'Claude (Anthropic)', 'gemini': 'Gemini (Google)', 'openai': 'ChatGPT (OpenAI)', 'deepseek': 'DeepSeek',
  'openrouter': 'OpenRouter', 'groq': 'Groq', 'mistral': 'Mistral', 'xai': 'Grok (xAI)',
};
const _noFiles = {'deepseek'};
const _claudeDefault = 'claude-opus-5';

typedef AiUse = ({String provider, String model});

class AiConfig {
  final Map<String, Json> providers;
  final AiUse? assistant, documents;
  const AiConfig(this.providers, this.assistant, this.documents);
  String key(String provider) => str(providers[provider]?['key']);
}

/// Stored app_state 'ai': the old plain Claude key, or {providers: {id: {key, models}}, assistant, documents}.
AiConfig aiConfig(dynamic raw) {
  final Map<String, Json> providers = raw is Map
      ? {for (final e in ((raw['providers'] as Map?) ?? const {}).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map)}
      : raw is String && raw.isNotEmpty ? {'anthropic': {'key': raw, 'models': [_claudeDefault]}} : {};
  List models(String id) => (providers[id]?['models'] as List?) ?? const [];
  final on = providers.keys.where((id) => aiProviders.containsKey(id) && str(providers[id]!['key']).isNotEmpty && models(id).isNotEmpty).toList();
  AiUse? pick(dynamic u) {
    if (u is Map && str(providers[str(u['provider'])]?['key']).isNotEmpty && models(str(u['provider'])).contains(u['model'])) {
      return (provider: str(u['provider']), model: str(u['model']));
    }
    return on.isEmpty ? null : (provider: on.first, model: '${models(on.first).first}');
  }
  return AiConfig(providers, pick(raw is Map ? raw['assistant'] : null), pick(raw is Map ? raw['documents'] : null));
}

String _noModel(String what) => 'لم يُحدَّد نموذج ذكاء اصطناعي لـ$what. يضيفه مدير النظام من الإعدادات ← الذكاء الاصطناعي في الموقع.';

/// One request to the model of [use] and its text answer. [file] is sent with the last user message;
/// [schema] asks for JSON in that shape (the answer is still returned as text).
Future<String> aiComplete(AiConfig cfg, AiUse? use, {required String what, String system = '', required List<Json> messages,
    ({Uint8List bytes, String mime, String name})? file, Json? schema, int maxTokens = 16000}) async {
  if (use == null) throw _noModel(what);
  final name = aiProviders[use.provider] ?? use.provider;
  if (file != null && _noFiles.contains(use.provider)) throw '$name لا يقرأ ملفات PDF أو الصور. اختر نموذجًا آخر لقراءة المستندات من الإعدادات في الموقع.';
  final b64 = file == null ? '' : base64Encode(file.bytes);
  final last = messages.length - 1;
  String text(Json m) => str(m['content']);

  if (use.provider == 'anthropic') {
    final key = cfg.key('anthropic');
    final msgs = [
      for (var i = 0; i <= last; i++)
        {'role': messages[i]['role'], 'content': i == last && file != null
            ? [{'type': file.mime == 'application/pdf' ? 'document' : 'image', 'source': {'type': 'base64', 'media_type': file.mime, 'data': b64}}, {'type': 'text', 'text': text(messages[i])}]
            : text(messages[i])},
    ];
    final http.Response r;
    try {
      r = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {'x-api-key': key, 'anthropic-version': '2023-06-01', 'anthropic-beta': 'server-side-fallback-2026-07-01', 'content-type': 'application/json'},
        body: jsonEncode({
          'model': use.model,
          'max_tokens': maxTokens,
          if (use.model == _claudeDefault) 'fallbacks': 'default',
          if (system.isNotEmpty) 'system': [{'type': 'text', 'text': system, 'cache_control': {'type': 'ephemeral'}}],
          if (schema != null) 'output_config': {'format': {'type': 'json_schema', 'schema': schema}},
          'messages': msgs,
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
    if (body['stop_reason'] == 'max_tokens') throw 'الرد أطول من المسموح ولم يكتمل.';
    return ((body['content'] as List?) ?? []).where((b) => b['type'] == 'text').map((b) => b['text']).join();
  }

  final ask = schema == null ? '' : '\n\nأعد النتيجة كائن JSON واحدًا فقط بدون أي نص قبله أو بعده، مطابقًا لهذا المخطط (JSON Schema):\n${jsonEncode(schema)}';
  final String path;
  final Json payload;
  if (use.provider == 'gemini') {
    path = '/models/${use.model}:generateContent';
    payload = {
      if (system.isNotEmpty) 'systemInstruction': {'parts': [{'text': system}]},
      'contents': [
        for (var i = 0; i <= last; i++)
          {'role': messages[i]['role'] == 'assistant' ? 'model' : 'user', 'parts': [
            if (i == last && file != null) {'inline_data': {'mime_type': file.mime, 'data': b64}},
            {'text': text(messages[i]) + (i == last ? ask : '')},
          ]},
      ],
      if (schema != null) 'generationConfig': {'responseMimeType': 'application/json'},
    };
  } else {
    path = '/chat/completions';
    final url = 'data:${file?.mime};base64,$b64';
    payload = {
      'model': use.model,
      'messages': [
        if (system.isNotEmpty) {'role': 'system', 'content': system},
        for (var i = 0; i <= last; i++)
          {'role': messages[i]['role'], 'content': i == last && file != null
              ? [
                  file.mime.startsWith('image/') ? {'type': 'image_url', 'image_url': {'url': url}} : {'type': 'file', 'file': {'filename': file.name, 'file_data': url}},
                  {'type': 'text', 'text': text(messages[i]) + ask},
                ]
              : text(messages[i]) + (i == last ? ask : '')},
      ],
      if (schema != null && use.provider != 'openrouter') 'response_format': {'type': 'json_object'},
    };
  }
  final dynamic body;
  try {
    body = (await Supabase.instance.client.functions.invoke('ai', body: {'provider': use.provider, 'path': path, 'payload': payload})).data;
  } on FunctionException catch (e) {
    final d = e.details;
    final m = d is Map ? (d['error'] is Map ? d['error']['message'] : d['error'] ?? d['message']) : d;
    if (e.status == 401) throw 'مفتاح $name غير صحيح أو لا يملك صلاحية هذا النموذج.';
    if (e.status == 429) throw 'تم تجاوز حد الطلبات أو الرصيد في $name، حاول بعد قليل.';
    throw 'خطأ من $name: ${m ?? e.status}';
  } catch (_) {
    throw 'تعذّر الاتصال بخدمة الذكاء الاصطناعي. تحقق من الإنترنت.';
  }
  final j = body is String ? jsonDecode(body) : body;
  if (use.provider == 'gemini') {
    return (((j['candidates'] as List?)?.firstOrNull?['content']?['parts'] as List?) ?? []).map((p) => p['text'] ?? '').join();
  }
  return str((j['choices'] as List?)?.firstOrNull?['message']?['content']);
}

/// The JSON object in a model's answer, tolerating code fences or a sentence around it.
Json parseAiJson(String t) {
  final i = t.indexOf('{'), j = t.lastIndexOf('}');
  if (i < 0 || j < i) throw 'لم يُرجع النموذج بيانات صالحة. جرّب مرة أخرى أو اختر نموذجًا آخر.';
  return Map<String, dynamic>.from(jsonDecode(t.substring(i, j + 1)) as Map);
}
