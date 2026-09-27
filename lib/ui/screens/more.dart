import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/logic.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';
import 'workers.dart';

const webUrl = 'https://overtime.alhemedy.com/#login';

/// Settings: general info + المهن (moved here from the main menu; keeps its own permission).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final tabs = [if (store.can('settings')) ('الإعدادات العامة', const _GeneralSettings()), if (store.can('trades')) ('المهن', const TradesScreen())];
    if (tabs.length == 1) return tabs.first.$2;
    return DefaultTabController(
      length: tabs.length,
      child: Column(children: [
        Material(color: Colors.white, child: TabBar(labelColor: C.primary700, indicatorColor: C.primary, tabs: [for (final t in tabs) Tab(text: t.$1)])),
        Expanded(child: TabBarView(children: [for (final t in tabs) t.$2])),
      ]),
    );
  }
}

class _GeneralSettings extends StatelessWidget {
  const _GeneralSettings();
  @override
  Widget build(BuildContext context) {
    final c = store.company, s = store.settings;
    final holidays = Map<String, dynamic>.from((s['holidays'] as Map?) ?? {});
    return ListView(padding: const EdgeInsets.all(16), children: [
      const SectionTitle('بيانات المنشأة'),
      CardBox(child: Column(children: [
        KV('اسم المنشأة', str(c['name'])), KV('السجل التجاري', str(c['cr'])), KV('الرقم الضريبي', str(c['vat'])),
        KV('المدينة', str(c['city'])), KV('العنوان', str(c['address'])), KV('الهاتف', str(c['phone'])), KV('البريد', str(c['email'])),
        KV('التنبيه قبل الانتهاء', '${store.alertDays} يوم'),
      ])),
      const SectionTitle('العمل الإضافي'),
      CardBox(child: Column(children: [
        KV('الحد اليومي — أيام العمل', '${fmtNum(toNum(s['dailyMax']))} ساعة'),
        KV('الحد اليومي — الجمعة والعطل', '${fmtNum(toNum(s['restMax']))} ساعة'),
        KV('الحد الشهري لكل عامل', '${fmtNum(toNum(s['monthlyMax']))} ساعة'),
        KV('طريقة الاحتساب', 'الساعات × أجر الساعة المسجّل للعامل'),
        for (final h in holidays.entries) KV(fmtDate(h.key), '${h.value}'),
      ])),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse(webUrl), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new), label: const Text('تعديل الإعدادات والمسميات والمستخدمين من الموقع')),
    ]);
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _cur = TextEditingController(), _next = TextEditingController(), _again = TextEditingController();
  bool _busy = false;

  Future<void> _change() async {
    final n = _next.text;
    String? err;
    if (n.length < 8) {
      err = 'كلمة المرور 8 أحرف على الأقل';
    } else if (!RegExp(r'[A-Za-z؀-ۿ]').hasMatch(n) || !RegExp(r'\d').hasMatch(n)) {
      err = 'يجب أن تحتوي كلمة المرور على حروف وأرقام';
    } else if (n != _again.text) {
      err = 'كلمتا المرور غير متطابقتين';
    }
    if (err != null) return toast(context, err, bad: true);
    setState(() => _busy = true);
    err = await store.changePassword(_cur.text, n);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) { _cur.clear(); _next.clear(); _again.clear(); }
    toast(context, err ?? 'تم تغيير كلمة المرور.', bad: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final me = store.me!;
    final avatar = str(me['avatar']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      CardBox(child: Column(children: [
        CircleAvatar(
          radius: 46,
          backgroundColor: C.primary50,
          backgroundImage: avatar.startsWith('data:') ? MemoryImage(base64Decode(avatar.split(',').last)) : null,
          child: avatar.startsWith('data:') ? null : const Icon(Icons.person, size: 48, color: C.primary700),
        ),
        const SizedBox(height: 10),
        Text(str(me['name']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text(str(me['email']), style: const TextStyle(color: C.fg3)),
        const SizedBox(height: 8),
        Pill(me['admin'] == true ? 'مدير النظام' : (str(me['title']).isEmpty ? 'مستخدم' : str(me['title'])), tone: Tone.blue),
      ])),
      const SectionTitle('تغيير كلمة المرور'),
      CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _cur, obscureText: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'كلمة المرور الحالية')),
        const SizedBox(height: 10),
        TextField(controller: _next, obscureText: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة', helperText: '8 أحرف على الأقل وتحتوي على حروف وأرقام')),
        const SizedBox(height: 10),
        TextField(controller: _again, obscureText: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور')),
        const SizedBox(height: 14),
        FilledButton(onPressed: _busy ? null : _change, child: const Text('تغيير كلمة المرور')),
      ])),
      const SizedBox(height: 16),
      OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: C.danger), onPressed: () => store.signOut(), icon: const Icon(Icons.logout), label: const Text('تسجيل الخروج')),
    ]);
  }
}
