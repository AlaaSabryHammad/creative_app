import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/i18n.dart' show defaultLang;
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/llm.dart';
import '../../data/store.dart';
import '../doc_pick.dart';
import '../widgets.dart';

/// Languages a message can be translated into (the worker app's languages) — web: src/whatsapp.jsx.
const _langs = {'ar': ('العربية', 'Arabic'), 'en': ('English', 'English'), 'ur': ('اردو', 'Urdu'), 'hi': ('हिन्दी', 'Hindi'), 'bn': ('বাংলা', 'Bengali'), 'ne': ('नेपाली', 'Nepali')};

/// Writes a message in Arabic, translates it into the worker's language (editable), and sends it with an optional
/// photo or file through the 'wa' Edge Function, which holds the WhatsApp gateway key.
Future<void> sendWhatsApp(BuildContext context, Json w) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _WhatsAppSheet(w),
    );

class _WhatsAppSheet extends StatefulWidget {
  final Json w;
  const _WhatsAppSheet(this.w);
  @override
  State<_WhatsAppSheet> createState() => _WhatsAppSheetState();
}

class _WhatsAppSheetState extends State<_WhatsAppSheet> {
  late String _lang = defaultLang(widget.w);
  final _text = TextEditingController(), _out = TextEditingController();
  bool _translated = false;
  PickedDoc? _file;
  String _busy = '', _err = '';

  bool get _phoneOk => RegExp(r'^05\d{8}$').hasMatch(str(widget.w['phone']));
  String get _final => _lang == 'ar' ? _text.text.trim() : _out.text.trim();

  Future<void> _translate() async {
    setState(() { _busy = 'tr'; _err = ''; });
    try {
      final cfg = store.ai;
      final t = await aiComplete(cfg, cfg.assistant, what: 'الترجمة',
          system: "You translate WhatsApp messages from a Saudi construction company's office to its workers. Translate the user's message into ${_langs[_lang]!.$2}. "
              'Keep the meaning, tone, numbers, dates, amounts and names exactly. Use simple everyday words a worker understands. '
              'Reply with the translated message only — no notes, quotes or explanations.',
          messages: [{'role': 'user', 'content': _text.text.trim()}], maxTokens: 4000);
      setState(() { _out.text = t.trim(); _translated = true; });
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _send() async {
    setState(() { _busy = 'send'; _err = ''; });
    try {
      final f = _file;
      await Supabase.instance.client.functions.invoke('wa', body: {
        'phone': str(widget.w['phone']),
        'text': _final,
        if (f != null) 'file': {'base64': base64Encode(f.bytes), 'mimetype': f.mime, 'filename': f.name},
      });
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, 'تم إرسال الرسالة إلى ${widget.w['name']} على واتساب.');
    } on FunctionException catch (e) {
      final d = e.details;
      setState(() { _err = d is Map && d['error'] != null ? '${d['error']}' : 'تعذّر الإرسال (${e.status})'; _busy = ''; });
    } catch (_) {
      setState(() { _err = 'تعذّر الاتصال بخدمة واتساب. تحقق من الإنترنت.'; _busy = ''; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w, needsTr = _lang != 'ar' && _text.text.trim().isNotEmpty && !_translated;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('رسالة واتساب إلى ${w['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(str(w['phone']).isEmpty ? 'لا يوجد رقم جوال' : str(w['phone']), textDirection: TextDirection.ltr, textAlign: TextAlign.right, style: const TextStyle(color: C.fg3)),
          if (!_phoneOk)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('لا يوجد رقم جوال صحيح للعامل (05xxxxxxxx). أضفه في بيانات العامل أولًا.', style: TextStyle(color: C.danger, fontWeight: FontWeight.w600))),
          if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err, style: const TextStyle(color: C.danger))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _lang,
            decoration: const InputDecoration(labelText: 'لغة الرسالة'),
            items: [for (final e in _langs.entries) DropdownMenuItem(value: e.key, child: Text('${e.value.$1}${e.key == defaultLang(w) ? ' (لغة العامل)' : ''}'))],
            onChanged: (v) => setState(() { _lang = v!; _translated = false; }),
          ),
          const SizedBox(height: 10),
          TextField(controller: _text, minLines: 3, maxLines: 6,
              decoration: InputDecoration(labelText: _lang == 'ar' ? 'الرسالة' : 'الرسالة (اكتبها بالعربية وتُترجم تلقائيًا)'),
              onChanged: (_) => setState(() => _translated = false)),
          if (_lang != 'ar' && _translated) ...[
            const SizedBox(height: 10),
            TextField(controller: _out, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: 'الترجمة إلى ${_langs[_lang]!.$1} — راجعها قبل الإرسال')),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: Icon(_file == null ? Icons.attach_file : Icons.check_circle, color: _file == null ? null : C.success),
            label: Text(_file == null ? 'إرفاق صورة أو ملف (اختياري)' : _file!.name, overflow: TextOverflow.ellipsis),
            onPressed: () async {
              final f = await pickDoc(context, title: 'إرفاق صورة أو ملف');
              if (f != null && mounted) setState(() => _file = f);
            },
          ),
          const SizedBox(height: 14),
          if (needsTr)
            FilledButton.icon(
              onPressed: _busy.isNotEmpty || store.ai.assistant == null ? null : _translate,
              icon: _busy == 'tr' ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.translate),
              label: Text('ترجمة إلى ${_langs[_lang]!.$1}'),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
              onPressed: _busy.isNotEmpty || !_phoneOk || (_final.isEmpty && _file == null) ? null : _send,
              icon: _busy == 'send' ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
              label: const Text('إرسال على واتساب'),
            ),
          if (_lang != 'ar' && store.ai.assistant == null)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('الترجمة تحتاج نموذج ذكاء اصطناعي من إعدادات الموقع، أو اختر العربية.', style: TextStyle(color: C.fg3, fontSize: 12))),
        ]),
      ),
    );
  }
}
