import 'package:flutter/material.dart';
import '../core/i18n.dart';
import '../core/logic.dart';
import '../core/theme.dart';
import '../data/store.dart';
import 'widgets.dart';

/// The user's own email: add / change it; Supabase emails a confirmation link and the email is used
/// for sign-in only once confirmed. Text follows the account language (staff: Arabic).
class EmailCard extends StatefulWidget {
  const EmailCard({super.key});
  @override
  State<EmailCard> createState() => _EmailCardState();
}

class _EmailCardState extends State<EmailCard> {
  final _email = TextEditingController();
  bool _busy = false;

  Future<void> _send() async {
    final v = _email.text.trim();
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(v)) return toast(context, tr('emailInvalid'), bad: true);
    setState(() => _busy = true);
    final err = await store.changeEmail(v);
    if (!mounted) return;
    setState(() { _busy = false; if (err == null) _email.clear(); });
    toast(context, err ?? tr('emailPending', v), bad: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final cur = realEmail(str(store.me?['email']));
    return CardBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.mail_outline, color: C.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(cur.isEmpty ? tr('emailNone') : cur, textDirection: cur.isEmpty ? null : TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 6),
        Text(tr('emailNote'), style: const TextStyle(color: C.fg3, fontSize: 12.5)),
        if (store.pendingEmail.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.warning50, borderRadius: BorderRadius.circular(10)),
            child: Text(tr('emailPending', store.pendingEmail), style: const TextStyle(color: C.warning800, fontSize: 12.5)),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(labelText: cur.isEmpty ? tr('addEmail') : tr('changeEmail'), prefixIcon: const Icon(Icons.alternate_email)),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: _busy ? null : _send, icon: const Icon(Icons.send_outlined, size: 18), label: Text(tr('sendLink'))),
      ]),
    );
  }
}
