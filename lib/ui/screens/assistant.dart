import 'package:flutter/material.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/ai.dart';
import '../widgets.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

// Chat history lives for the app session.
final List<Json> _chat = [];

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;
  static const _suggest = [
    'لخّص وضع المنشأة اليوم وأهم 5 أمور تحتاج انتباهي',
    'ما الوثائق والاستمارات التي تنتهي خلال 60 يومًا؟',
    'ما تكلفة العمل الإضافي المعتمد لكل مشروع هذا الشهر؟',
    'من أكثر 5 عمال في ساعات العمل الإضافي هذا الشهر؟',
    'ما نسبة إنجاز كل مشروع حسب جدول الكميات؟',
  ];

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() { _chat.add({'role': 'user', 'content': text}); _busy = true; });
    _down();
    try {
      final reply = await askAssistant(List.of(_chat));
      _chat.add({'role': 'assistant', 'content': reply});
    } catch (e) {
      _chat.removeLast();
      _input.text = text;
      if (mounted) toast(context, '$e', bad: true);
    }
    if (mounted) setState(() => _busy = false);
    _down();
  }

  void _down() => WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: _chat.isEmpty
            ? ListView(padding: const EdgeInsets.all(20), children: [
                const SizedBox(height: 20),
                Center(child: Container(width: 64, height: 64, decoration: BoxDecoration(gradient: const LinearGradient(colors: [C.primary, Color(0xFF7C3AED)]), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.auto_awesome, color: Colors.white, size: 32))),
                const SizedBox(height: 14),
                const Text('كيف أساعدك اليوم؟', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const Text('يقرأ المساعد بيانات المنشأة الحالية ويجيب عليها مباشرة.', textAlign: TextAlign.center, style: TextStyle(color: C.fg3)),
                const SizedBox(height: 18),
                for (final q in _suggest) Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton(onPressed: () => _send(q), style: OutlinedButton.styleFrom(alignment: AlignmentDirectional.centerStart, padding: const EdgeInsets.all(14)), child: Text(q, style: const TextStyle(color: C.fg2)))),
              ])
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: _chat.length + (_busy ? 1 : 0),
                itemBuilder: (c, i) {
                  if (i == _chat.length) return const Align(alignment: AlignmentDirectional.centerEnd, child: Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))));
                  final m = _chat[i];
                  final user = m['role'] == 'user';
                  return Align(
                    alignment: user ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .85),
                      decoration: BoxDecoration(
                        gradient: user ? C.primaryGradient : null,
                        color: user ? null : Colors.white,
                        border: user ? null : Border.all(color: C.slate100),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SelectableText(str(m['content']), style: TextStyle(color: user ? Colors.white : C.fg1, height: 1.7, fontSize: 14.5)),
                    ),
                  );
                },
              ),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.slate100))),
          child: Row(children: [
            Expanded(child: TextField(controller: _input, minLines: 1, maxLines: 4, enabled: !_busy, decoration: const InputDecoration(hintText: 'اكتب سؤالك…'), onSubmitted: _send)),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _busy ? null : () => _send(_input.text), icon: const Icon(Icons.send)),
          ]),
        ),
      ),
    ]);
  }
}
