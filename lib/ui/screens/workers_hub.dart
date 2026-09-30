import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import 'deductions.dart';
import 'payroll.dart';
import 'record.dart';
import 'workers.dart';

/// العمال section: workers, overtime, deductions, and the salary payroll, each gated by its own permission.
class WorkersHub extends StatelessWidget {
  const WorkersHub({super.key});
  static final tabs = <(String, String, IconData, Widget Function())>[
    ('workers', 'العمال', Icons.groups_outlined, () => const WorkersScreen()),
    ('record', 'تسجيل إضافي', Icons.add_circle_outline, () => const RecordScreen()),
    ('deductions', 'الخصومات', Icons.remove_circle_outline, () => const DeductionsScreen()),
    ('payroll', 'مسيّر الرواتب', Icons.receipt_long_outlined, () => const PayrollScreen()),
  ];
  @override
  Widget build(BuildContext context) {
    final allowed = tabs.where((t) => store.can(t.$1)).toList();
    if (allowed.length == 1) return allowed.first.$4();
    return DefaultTabController(
      length: allowed.length,
      child: Column(children: [
        Material(
          color: Colors.white,
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: C.primary700,
            unselectedLabelColor: C.fg3,
            indicatorColor: C.primary,
            tabs: [for (final t in allowed) Tab(icon: Icon(t.$3, size: 20), text: t.$2, iconMargin: const EdgeInsets.only(bottom: 2))],
          ),
        ),
        Expanded(child: TabBarView(children: [for (final t in allowed) t.$4()])),
      ]),
    );
  }
}
