import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/i18n.dart';
import '../data/store.dart';

class LoginScreen extends StatefulWidget {
  final String? notice;
  const LoginScreen({super.key, this.notice});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _show = false, _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _err = widget.notice;
  }

  Future<void> _submit() async {
    if (_busy || _email.text.trim().isEmpty || _pw.text.isEmpty) return;
    setState(() { _busy = true; _err = null; });
    final err = await store.signIn(_email.text, _pw.text);
    if (mounted) setState(() { _busy = false; _err = err; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Image.asset('assets/logo.png', height: 96),
                const SizedBox(height: 10),
                ShaderMask(
                  shaderCallback: (r) => C.brandGradient.createShader(r),
                  child: const Text('CREATIVE', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 4, color: Colors.white)),
                ),
                const Text('مؤسسة إبراهيم حميدي العنزي للمقاولات', textAlign: TextAlign.center, style: TextStyle(color: C.gold, fontWeight: FontWeight.w600)),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Color(0x330F2240), blurRadius: 60, offset: Offset(0, 30), spreadRadius: -30)],
                  ),
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: C.goldLight, borderRadius: BorderRadius.circular(99)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.verified_user_outlined, size: 15, color: C.gold), SizedBox(width: 6), Text('بوابة الموظفين والعمال', style: TextStyle(color: C.gold, fontWeight: FontWeight.w700, fontSize: 12.5))]),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('مرحبًا بعودتك', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: C.ink)),
                      const Text('للموظفين والمشرفين والعمال.', style: TextStyle(color: C.fg3)),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textDirection: TextDirection.ltr,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'البريد الإلكتروني أو رقم الهوية / الإقامة', helperText: 'Workers: iqama / ID number · عمال: رقم الإقامة', prefixIcon: Icon(Icons.person_outline)),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pw,
                        obscureText: !_show,
                        textDirection: TextDirection.ltr,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => _show = !_show)),
                        ),
                      ),
                      if (_err != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: C.danger50, borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [const Icon(Icons.error, color: C.danger, size: 20), const SizedBox(width: 8), Expanded(child: Text(_err!, style: const TextStyle(color: C.danger800)))]),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: C.ink, minimumSize: const Size(0, 54)),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text('تسجيل الدخول'), SizedBox(width: 8), Icon(Icons.arrow_forward, size: 18)]),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('الدخول مخصص لموظفي المؤسسة المصرّح لهم فقط.', textAlign: TextAlign.center, style: TextStyle(color: C.slate400, fontSize: 12.5)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Right after signing in with the temporary password: nothing else is reachable until it is replaced.
/// Text follows the account's language (tr), so workers read it in theirs.
class ForcePasswordScreen extends StatefulWidget {
  const ForcePasswordScreen({super.key});
  @override
  State<ForcePasswordScreen> createState() => _ForcePasswordScreenState();
}

class _ForcePasswordScreenState extends State<ForcePasswordScreen> {
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _submit() async {
    final n = _next.text;
    final problem = n.length < 8 || !RegExp(r'\d').hasMatch(n) || !RegExp(r'[^\d\s]').hasMatch(n)
        ? tr('passwordRule')
        : n != _again.text ? tr('passwordMismatch') : null;
    if (problem != null) return setState(() => _err = problem);
    setState(() { _busy = true; _err = null; });
    final err = await store.setFirstPassword(n);
    if (mounted) setState(() { _busy = false; _err = err; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Image.asset('assets/logo.png', height: 80),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Color(0x330F2240), blurRadius: 60, offset: Offset(0, 30), spreadRadius: -30)],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Icon(Icons.lock_reset, size: 40, color: C.gold),
                    const SizedBox(height: 10),
                    Text(tr('firstLogin'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.ink)),
                    const SizedBox(height: 4),
                    Text('${store.myName} — ${tr('firstLoginNote')}', style: const TextStyle(color: C.fg3)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _next,
                      obscureText: true,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(labelText: tr('newPassword'), helperText: tr('passwordRule'), prefixIcon: const Icon(Icons.lock_outline)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _again,
                      obscureText: true,
                      textDirection: TextDirection.ltr,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(labelText: tr('confirmPassword'), prefixIcon: const Icon(Icons.lock_outline)),
                    ),
                    if (_err != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: C.danger50, borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [const Icon(Icons.error, color: C.danger, size: 20), const SizedBox(width: 8), Expanded(child: Text(_err!, style: const TextStyle(color: C.danger800)))]),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: C.ink, minimumSize: const Size(0, 54)),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(tr('saveContinue')),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(icon: const Icon(Icons.logout), label: Text(tr('signOut')), onPressed: _busy ? null : store.signOut),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
