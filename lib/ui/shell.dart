import 'package:flutter/material.dart';
import '../core/logic.dart';
import '../core/theme.dart';
import '../data/store.dart';
import 'widgets.dart';
import 'screens/dashboard.dart';
import 'screens/alerts.dart';
import 'screens/assistant.dart';
import 'screens/record.dart';
import 'screens/requests.dart';
import 'screens/workers.dart';
import 'screens/payroll.dart';
import 'screens/projects.dart';
import 'screens/docs.dart';
import 'screens/vehicles.dart';
import 'screens/more.dart';

class Module {
  final String key, label;
  final IconData icon;
  final Widget Function() build;
  const Module(this.key, this.label, this.icon, this.build);
}

// Same grouping and permission keys as the web sidebar.
final groups = <(String, List<Module>)>[
  ('الرئيسية', [
    Module('assistant', 'المساعد الذكي', Icons.auto_awesome, () => const AssistantScreen()),
    Module('alerts', 'التنبيهات', Icons.notifications_none, () => const AlertsScreen()),
  ]),
  ('العمالة والعمل الإضافي', [
    Module('dashboard', 'لوحة الملخص', Icons.space_dashboard_outlined, () => const DashboardScreen()),
    Module('record', 'تسجيل ساعات إضافية', Icons.add_circle_outline, () => const RecordScreen()),
    Module('requests', 'الطلبات والاعتماد', Icons.fact_check_outlined, () => const RequestsScreen()),
    Module('workers', 'العمال', Icons.groups_outlined, () => const WorkersScreen()),
    Module('trades', 'المهن', Icons.handyman_outlined, () => const TradesScreen()),
    Module('payroll', 'مسيّر الشهر', Icons.receipt_long_outlined, () => const PayrollScreen()),
  ]),
  ('المشاريع', [Module('projects', 'المشاريع', Icons.apartment_outlined, () => const ProjectsScreen())]),
  ('المنشأة', [
    Module('docs', 'ملفات المنشأة', Icons.folder_shared_outlined, () => const DocsScreen()),
    Module('vehicles', 'السيارات والمعدات', Icons.directions_car_outlined, () => const VehiclesScreen()),
  ]),
  ('النظام', [
    Module('settings', 'الإعدادات', Icons.settings_outlined, () => const SettingsScreen()),
    Module('profile', 'ملفي الشخصي', Icons.person_outline, () => const ProfileScreen()),
  ]),
];

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  String? _cur;

  List<Module> get _allowed => [for (final g in groups) ...g.$2.where((m) => store.can(m.key))];

  int _badge(String k) {
    final alerts = buildAlerts(docs: store.docs, vehicles: store.vehicles, workers: store.workers, projects: store.projects, days: store.alertDays);
    if (k == 'alerts') return alerts.length;
    if (k == 'requests') return store.entries.where((e) => e['status'] == 'pending').length;
    if (k == 'docs' || k == 'vehicles' || k == 'workers' || k == 'projects') return alerts.where((a) => a.screen == k).length;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final allowed = _allowed;
        final cur = allowed.firstWhere((m) => m.key == _cur, orElse: () => allowed.firstWhere((m) => m.key == 'dashboard', orElse: () => allowed.first));
        return Scaffold(
          appBar: AppBar(
            title: Text(cur.label),
            actions: [IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh), onPressed: () => store.refresh())],
          ),
          drawer: _drawer(context, cur),
          body: KeyedSubtree(key: ValueKey(cur.key), child: cur.build()),
        );
      },
    );
  }

  Widget _drawer(BuildContext context, Module cur) {
    final me = store.me!;
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(children: [
              Image.asset('assets/logo.png', width: 42, height: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ShaderMask(shaderCallback: (r) => C.brandGradient.createShader(r), child: const Text('CREATIVE', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 2, color: Colors.white))),
                  Text(str(store.company['name']).isEmpty ? 'إدارة المنشأة' : str(store.company['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.fg3)),
                ]),
              ),
            ]),
          ),
          const Divider(height: 1, color: C.slate100),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
              for (final g in groups)
                if (g.$2.any((m) => store.can(m.key))) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 4), child: Text(g.$1, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: C.slate400))),
                  for (final m in g.$2.where((m) => store.can(m.key))) _item(context, m, m.key == cur.key),
                ],
            ]),
          ),
          const Divider(height: 1, color: C.slate100),
          ListTile(
            leading: CircleAvatar(backgroundColor: C.primary50, child: Text(str(me['name']).isEmpty ? '؟' : str(me['name']).substring(0, 1), style: const TextStyle(color: C.primary700, fontWeight: FontWeight.w800))),
            title: Text(str(me['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(str(me['title']).isNotEmpty ? str(me['title']) : (me['admin'] == true ? 'مدير النظام' : 'مستخدم'), style: const TextStyle(fontSize: 12)),
            trailing: IconButton(tooltip: 'تسجيل الخروج', icon: const Icon(Icons.logout, color: C.danger), onPressed: () => store.signOut()),
          ),
        ]),
      ),
    );
  }

  Widget _item(BuildContext context, Module m, bool active) {
    final b = _badge(m.key);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: ListTile(
        dense: true,
        selected: active,
        selectedTileColor: C.primary50,
        selectedColor: C.primary700,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(m.icon, size: 22),
        title: Text(m.label, style: TextStyle(fontSize: 14.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        trailing: b > 0 ? Pill('$b', tone: m.key == 'requests' ? Tone.orange : Tone.red) : null,
        onTap: () {
          setState(() => _cur = m.key);
          Navigator.pop(context);
        },
      ),
    );
  }
}
