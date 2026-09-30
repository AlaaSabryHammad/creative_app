import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../email_card.dart';
import '../../core/i18n.dart';
import '../../core/logic.dart';
import '../../core/pay.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../report.dart';
import '../screens/payroll.dart' show SlipDetails;
import '../widgets.dart';

/// The worker's own app: their attendance, overtime, pay, requests and details — nothing about anyone else.
String sar(num v) => '${fmtNum(round2(v))} ${tr('sar')}';
String wDate(String d, {bool year = false}) => d.isEmpty ? '—' : DateFormat(year ? 'd MMM y' : 'd MMM', lang).format(DateTime.parse(d));
String wMonth(String ym) => DateFormat('MMMM y', lang).format(DateTime.parse('$ym-01'));
const _att = {'present': Tone.green, 'absent': Tone.red, 'leave': Tone.blue, 'sick': Tone.orange, 'off': Tone.slate};
Tone _st(String s) => s == 'approved' ? Tone.green : s == 'rejected' ? Tone.red : Tone.orange;
Set<String> get _paidOt => {...((store.mine['paidOt'] as List?) ?? const []).map((e) => '$e'), for (final e in store.myOt) if (str(e['paidBy']).isNotEmpty) str(e['id'])};

class WorkerShell extends StatefulWidget {
  const WorkerShell({super.key});
  @override
  State<WorkerShell> createState() => _WorkerShellState();
}

class _WorkerShellState extends State<WorkerShell> {
  // Kept in the store: a language change rebuilds the shell from scratch (see main.dart) and must not jump home.
  int get _tab => store.workerTab;
  set _tab(int i) => store.workerTab = i;
  @override
  Widget build(BuildContext context) {
    final pending = store.myReq.where((r) => r['status'] == 'pending').length;
    final tabs = [const _Home(), const _Attendance(), const _Pay(), const _Requests(), const _Account()];
    final unread = store.unread;
    return Scaffold(
      appBar: AppBar(
        title: Text(str(store.mine['company']?['name']).isEmpty ? 'CREATIVE' : str(store.mine['company']['name']), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: tr('notifications'),
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: Icon(unread > 0 ? Icons.notifications_active : Icons.notifications_none)),
            onPressed: () async {
              final tab = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => const _Notices()));
              if (tab != null) setState(() => _tab = tab);
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => store.refresh()),
        ],
      ),
      body: RefreshIndicator(onRefresh: store.refresh, child: tabs[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: tr('home')),
          NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), selectedIcon: const Icon(Icons.calendar_month), label: tr('attendance')),
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet), label: tr('pay')),
          NavigationDestination(icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.inbox_outlined)), label: tr('requests')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: tr('account')),
        ],
      ),
    );
  }
}

// ---------------- Notifications ----------------

/// Every action on the worker's records (attendance, overtime, deductions, pay…) — newest first. Opening the
/// list marks them read; tapping one opens the tab it belongs to.
class _Notices extends StatefulWidget {
  const _Notices();
  @override
  State<_Notices> createState() => _NoticesState();
}

class _NoticesState extends State<_Notices> {
  late final Set<Object?> _unread = {for (final n in store.myNotes) if (n['read_at'] == null) n['id']};
  static const _look = {
    'ot': (Icons.bolt, Tone.blue, 2), 'att': (Icons.event_available_outlined, Tone.green, 1), 'ded': (Icons.remove_circle_outline, Tone.red, 2),
    'adv': (Icons.payments_outlined, Tone.orange, 2), 'req': (Icons.inbox_outlined, Tone.blue, 3), 'slip': (Icons.receipt_long_outlined, Tone.green, 2),
    'data': (Icons.person_outline, Tone.slate, 4), 'vehicle': (Icons.directions_car_outlined, Tone.slate, 0),
  };

  @override
  void initState() {
    super.initState();
    store.readNotes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('notifications'))),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          if (store.myNotes.isEmpty) CardBox(child: EmptyState(tr('noNotifications'))),
          for (final n in store.myNotes)
            () {
              final (title, body) = noticeText(n);
              final look = _look[str(n['kind']).split('_').first] ?? (Icons.notifications_none, Tone.slate, 0);
              final t = DateTime.tryParse(str(n['created_at']))?.toLocal();
              final fresh = _unread.contains(n['id']);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CardBox(
                  topStrip: fresh ? C.primary : null,
                  onTap: () => Navigator.pop(context, look.$3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(backgroundColor: look.$2.bg, child: Icon(look.$1, color: look.$2.fg, size: 20)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: TextStyle(fontWeight: fresh ? FontWeight.w800 : FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(body, style: const TextStyle(color: C.fg2)),
                      if (t != null) Text(DateFormat('d MMM, HH:mm', lang).format(t), style: const TextStyle(fontSize: 12, color: C.fg3)),
                    ])),
                  ]),
                ),
              );
            }(),
        ]),
      ),
    );
  }
}

// ---------------- Home ----------------

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) {
    final w = store.myWorker, p = store.pay, month = periodMonth(todayIso(), p.startDay);
    final slip = payslip(worker: w, month: month, attendance: store.myAtt, overtime: store.myOt, deductions: store.myDed, advances: store.myAdv, paidOtIds: _paidOt, s: p);
    final days = Map<String, dynamic>.from(slip['days'] as Map), ot = slip['overtime'] as Map, meals = slip['meals'] as Map;
    final leave = leaveBalance(w, [for (final a in store.myAtt) if (a['status'] == 'leave' && (a['approval'] ?? 'approved') == 'approved') str(a['date'])], p, todayIso());
    final iq = str(w['iqamaExpiry']).isEmpty ? null : daysLeft(str(w['iqamaExpiry']));
    final award = gratuity(w, todayIso());
    final project = store.mine['project'] as Map?, vehicle = store.mine['vehicle'] as Map?;
    Widget row(String l, num v, {bool neg = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [Expanded(child: Text(l, style: const TextStyle(color: C.fg2))), Text('${neg && v > 0 ? '− ' : ''}${sar(v)}', style: TextStyle(fontWeight: FontWeight.w700, color: neg && v > 0 ? C.danger : C.fg1))]),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      CardBox(
        child: Row(children: [
          WorkerPhoto(w['photo'], size: 64),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tr('hello')}،', style: const TextStyle(color: C.fg3)),
            Text(str(w['name']), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            Text('${w['id']} · ${str(w['trade'])}', style: const TextStyle(color: C.fg3)),
            if (project != null) IconText(Icons.apartment_outlined, str(project['name'])),
            if (vehicle != null) IconText(Icons.directions_car_outlined, '${vehicle['plate']} · ${str(vehicle['make'])} ${str(vehicle['model'])}'),
          ])),
        ]),
      ),
      if (iq != null && iq <= 30)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: iq < 0 ? C.danger50 : C.warning50, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [Icon(Icons.badge_outlined, color: iq < 0 ? C.danger : C.warning), const SizedBox(width: 8), Expanded(child: Text(iq < 0 ? tr('iqamaExpired', -iq) : tr('iqamaSoon', iq), style: const TextStyle(fontWeight: FontWeight.w700)))]),
        ),
      SectionTitle('${tr('thisMonth')} — ${wMonth(month)}'),
      CardBox(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(tr('net'), style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(sar(toNum(slip['net'])), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: C.primary700)),
          ]),
          const Divider(height: 20),
          row(tr('salary'), toNum(slip['base'])),
          row('${tr('overtime')} (${fmtNum(toNum(ot['hours']))} ${tr('h')})', toNum(ot['amount'])),
          row('${tr('meals')} (${meals['breakfast']} + ${meals['lunch']})', toNum(meals['amount'])),
          row(tr('totalDeductions'), toNum(slip['totalDeductions']), neg: true),
          const SizedBox(height: 6),
          Text(tr('estimate'), style: const TextStyle(fontSize: 12, color: C.fg3)),
        ]),
      ),
      const SizedBox(height: 12),
      StatGrid([
        StatTile(tone: Tone.green, icon: Icons.how_to_reg_outlined, label: tr('present'), value: '${days['present']}', sub: '${tr('absent')} ${days['absent']}'),
        StatTile(tone: Tone.blue, icon: Icons.luggage_outlined, label: tr('leaveBalance'), value: '${fmtNum(leave)} ${tr('days')}'),
      ]),
      if (award != null) ...[
        const SizedBox(height: 10),
        CardBox(
          child: Row(children: [
            const Icon(Icons.workspace_premium_outlined, color: C.gold, size: 30),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('gratuity'), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(tr('gratuityNote', fmtNum(award.years)), style: const TextStyle(fontSize: 12, color: C.fg3)),
            ])),
            Text(sar(award.amount), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        ),
      ],
      if (store.mySlips.isNotEmpty) ...[
        SectionTitle(tr('lastPayslip')),
        _SlipTile(store.mySlips.first),
      ],
    ]);
  }
}

class _SlipTile extends StatelessWidget {
  final Json s;
  const _SlipTile(this.s);
  @override
  Widget build(BuildContext context) {
    final data = Map<String, dynamic>.from(s['data'] as Map);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CardBox(
        onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => SlipDetails(data, tr: (k, ar) => tr(k))),
        child: Row(children: [
          const Icon(Icons.receipt_long_outlined, color: C.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(wMonth(str(s['month'])), style: const TextStyle(fontWeight: FontWeight.w800))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(sar(toNum(s['net'])), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Pill(s['paid'] == true ? tr('paid') : tr('unpaid'), tone: s['paid'] == true ? Tone.green : Tone.slate),
          ]),
        ]),
      ),
    );
  }
}

// ---------------- Attendance calendar ----------------

class _Attendance extends StatefulWidget {
  const _Attendance();
  @override
  State<_Attendance> createState() => _AttendanceState();
}

class _AttendanceState extends State<_Attendance> {
  String _month = monthIso();
  @override
  Widget build(BuildContext context) {
    final (first, last, n) = monthBounds(_month);
    final rows = {for (final a in store.myAtt) if (str(a['date']).compareTo(first) >= 0 && str(a['date']).compareTo(last) <= 0) str(a['date']): a};
    final ot = {for (final e in store.myOt) if (str(e['date']).startsWith(_month) && e['status'] != 'rejected') str(e['date']): e};
    final offset = DateTime.parse(first).weekday % 7; // Sunday first
    int count(String s) => rows.values.where((a) => a['status'] == s).length;
    bool inP(dynamic d, String f, String l) => str(d).compareTo(f) >= 0 && str(d).compareTo(l) <= 0;
    return ListView(padding: const EdgeInsets.all(16), children: [
      FilledButton.tonalIcon(
        icon: const Icon(Icons.summarize_outlined),
        label: Text(tr('myReport')),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerReportPage(
          worker: store.myWorker, t: (k, ar) => tr(k),
          load: (f, l) async => (att: [for (final a in store.myAtt) if (inP(a['date'], f, l)) a], ot: [for (final e in store.myOt) if (inP(e['date'], f, l)) e],
              ded: [for (final d in store.myDed) if (inP(d['date'], f, l)) d], adv: [for (final a in store.myAdv) if (inP(a['date'], f, l)) a]),
        ))),
      ),
      const SizedBox(height: 8),
      Row(children: [
        IconButton(onPressed: () => setState(() => _month = addMonths(_month, -1)), icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text(wMonth(_month), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        IconButton(onPressed: _month.compareTo(monthIso()) >= 0 ? null : () => setState(() => _month = addMonths(_month, 1)), icon: const Icon(Icons.chevron_right)),
      ]),
      CardBox(
        padding: const EdgeInsets.all(10),
        child: GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (var i = 0; i < offset; i++) const SizedBox(),
            for (var d = 1; d <= n; d++)
              () {
                final date = '$_month-${'$d'.padLeft(2, '0')}';
                final a = rows[date];
                final tone = a == null ? null : _att[a['status']];
                return Container(
                  decoration: BoxDecoration(color: tone?.bg ?? C.slate50, borderRadius: BorderRadius.circular(10), border: date == todayIso() ? Border.all(color: C.primary, width: 1.5) : null),
                  child: Stack(children: [
                    Center(child: Text('$d', style: TextStyle(fontWeight: FontWeight.w800, color: tone?.fg ?? C.slate400))),
                    if (a?['breakfast'] == true || a?['lunch'] == true) const Positioned(bottom: 2, left: 0, right: 0, child: Icon(Icons.restaurant, size: 10, color: C.fg3)),
                    if (ot[date] != null) const Positioned(top: 2, right: 3, child: Icon(Icons.bolt, size: 11, color: C.primary)),
                  ]),
                );
              }(),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in _att.keys) Pill('${tr(s)} ${count(s)}', tone: _att[s]!),
        Pill(tr('overtime'), icon: Icons.bolt, tone: Tone.blue),
        Pill(tr('meals'), icon: Icons.restaurant),
      ]),
      const SizedBox(height: 10),
      if (rows.isEmpty) CardBox(child: EmptyState(tr('noData'))),
      for (final a in rows.values.toList()..sort((x, y) => str(y['date']).compareTo(str(x['date']))))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(backgroundColor: _att[a['status']]?.bg, child: Text(str(a['date']).substring(8), style: TextStyle(color: _att[a['status']]?.fg, fontWeight: FontWeight.w800))),
          title: Text(tr(str(a['status']))),
          subtitle: Text([if (a['breakfast'] == true) tr('breakfast'), if (a['lunch'] == true) tr('lunch'), if (ot[a['date']] != null) '${tr('overtime')} ${fmtNum(toNum(ot[a['date']]!['hours']))} ${tr('h')}'].join(' · ')),
          trailing: Text(wDate(str(a['date'])), style: const TextStyle(color: C.fg3)),
        ),
    ]);
  }
}

// ---------------- Pay: payslips, overtime, deductions, advances ----------------

class _Pay extends StatefulWidget {
  const _Pay();
  @override
  State<_Pay> createState() => _PayState();
}

class _PayState extends State<_Pay> {
  String _v = 'slips';
  @override
  Widget build(BuildContext context) {
    final paid = _paidOt;
    final ot = [...store.myOt]..sort((a, b) => str(b['date']).compareTo(str(a['date'])));
    final ded = [...store.myDed]..sort((a, b) => str(b['date']).compareTo(str(a['date'])));
    return ListView(padding: const EdgeInsets.all(16), children: [
      FilterChips(items: [('slips', tr('payslips')), ('ot', tr('overtime')), ('ded', tr('deductions')), ('adv', tr('advances'))], value: _v, onChanged: (v) => setState(() => _v = v)),
      const SizedBox(height: 12),
      if (_v == 'slips') ...[
        if (store.mySlips.isEmpty) CardBox(child: EmptyState(tr('noPayslips'))),
        for (final s in store.mySlips) _SlipTile(s),
      ],
      if (_v == 'ot') ...[
        if (ot.isEmpty) CardBox(child: EmptyState(tr('noData'))),
        for (final e in ot)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CardBox(
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(wDate(str(e['date']), year: true), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${fmtNum(toNum(e['hours']))} ${tr('h')} × ${fmtNum(toNum(e['rate']))}', style: const TextStyle(color: C.fg3)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(sar(otAmount(e)), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Pill(paid.contains(e['id']) ? tr('paid') : tr(str(e['status'])), tone: paid.contains(e['id']) ? Tone.blue : _st(str(e['status']))),
                ]),
              ]),
            ),
          ),
      ],
      if (_v == 'ded') ...[
        if (ded.isEmpty) CardBox(child: EmptyState(tr('noData'))),
        for (final d in ded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CardBox(
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(str(d['reason']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${wDate(str(d['date']), year: true)}${d['kind'] == 'hours' ? ' · ${fmtNum(toNum(d['hours']))} ${tr('h')}' : ''}', style: const TextStyle(color: C.fg3)),
                ])),
                Text('− ${sar(toNum(d['amount']))}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.danger)),
              ]),
            ),
          ),
      ],
      if (_v == 'adv') ...[
        if (store.myAdv.isEmpty) CardBox(child: EmptyState(tr('noData'))),
        for (final a in store.myAdv)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CardBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(sar(toNum(a['amount'])), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                  Text('${tr('remaining')}: ${sar(toNum(a['amount']) - toNum(a['repaid']))}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                ProgressBar(toNum(a['amount']) > 0 ? toNum(a['repaid']) / toNum(a['amount']) * 100 : 0),
                const SizedBox(height: 6),
                Text('${tr('installment')}: ${sar(toNum(a['installment']))} · ${tr('repaid')}: ${sar(toNum(a['repaid']))}', style: const TextStyle(color: C.fg3, fontSize: 12.5)),
              ]),
            ),
          ),
      ],
    ]);
  }
}

// ---------------- Requests ----------------

class _Requests extends StatelessWidget {
  const _Requests();
  @override
  Widget build(BuildContext context) {
    final list = [...store.myReq]..sort((a, b) => str(b['created_at']).compareTo(str(a['created_at'])));
    const kinds = {'leave': Icons.luggage_outlined, 'advance': Icons.payments_outlined, 'objection': Icons.feedback_outlined, 'other': Icons.chat_outlined};
    return Stack(children: [
      ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
        if (list.isEmpty) CardBox(child: EmptyState(tr('noData'))),
        for (final r in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CardBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(kinds[r['kind']], color: C.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr('kind${str(r['kind'])[0].toUpperCase()}${str(r['kind']).substring(1)}'), style: const TextStyle(fontWeight: FontWeight.w800))),
                  Pill(r['status'] == 'pending' ? tr('waiting') : tr(str(r['status'])), tone: _st(str(r['status']))),
                ]),
                const SizedBox(height: 6),
                if (r['kind'] == 'leave') Text('${wDate(str(r['date_from']))} – ${wDate(str(r['date_to']), year: true)}'),
                if (r['kind'] == 'advance') Text('${sar(toNum(r['amount']))} · ${r['installments'] ?? 1} ${tr('installments')}'),
                if (str(r['text']).isNotEmpty) Text(str(r['text']), style: const TextStyle(color: C.fg2)),
                if (str(r['reply']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${tr('reply')}: ${r['reply']}', style: const TextStyle(color: C.primary700, fontWeight: FontWeight.w600))),
                if (r['status'] == 'pending')
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: C.danger),
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(tr('cancelReq')),
                      onPressed: () async {
                        final err = await store.cancelRequest(str(r['id']));
                        if (context.mounted) toast(context, err == null ? tr('cancelled') : tr('error'), bad: err != null);
                      },
                    ),
                  ),
              ]),
            ),
          ),
      ]),
      PositionedDirectional(
        end: 16, bottom: 16,
        child: FloatingActionButton.extended(
          onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const _RequestForm()),
          icon: const Icon(Icons.add),
          label: Text(tr('newRequest')),
        ),
      ),
    ]);
  }
}

class _RequestForm extends StatefulWidget {
  const _RequestForm();
  @override
  State<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<_RequestForm> {
  String _kind = 'leave';
  DateTimeRange? _range;
  String? _ref;
  final _amount = TextEditingController(), _text = TextEditingController();
  int _inst = 2;
  bool _busy = false;

  // Recent records a worker may object to: absences, deductions, rejected overtime (last 60 days).
  List<(String, String)> get _refs {
    final since = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 60)));
    return [
      for (final a in store.myAtt) if (a['status'] == 'absent' && str(a['date']).compareTo(since) >= 0) ('attendance:${a['id']}', '${tr('absent')} — ${wDate(str(a['date']))}'),
      for (final d in store.myDed) if (str(d['date']).compareTo(since) >= 0) ('deductions:${d['id']}', '${tr('deductions')} ${sar(toNum(d['amount']))} — ${wDate(str(d['date']))}'),
      for (final e in store.myOt) if (e['status'] == 'rejected' && str(e['date']).compareTo(since) >= 0) ('overtime:${e['id']}', '${tr('overtime')} ${tr('rejected')} — ${wDate(str(e['date']))}'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bad = _kind == 'leave' && _range == null ? tr('needDates') : _kind == 'advance' && toNum(_amount.text) <= 0 ? tr('needAmount') : (_kind == 'objection' || _kind == 'other') && _text.text.trim().isEmpty ? tr('needText') : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(tr('newRequest'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final k in ['leave', 'advance', 'objection', 'other'])
              ChoiceChip(label: Text(tr('kind${k[0].toUpperCase()}${k.substring(1)}')), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
          ]),
          const SizedBox(height: 12),
          if (_kind == 'leave')
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(_range == null ? '${tr('from')} — ${tr('to')}' : '${wDate(DateFormat('yyyy-MM-dd').format(_range!.start))} – ${wDate(DateFormat('yyyy-MM-dd').format(_range!.end), year: true)}'),
              onPressed: () async {
                final r = await showDateRangePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (r != null) setState(() => _range = r);
              },
            ),
          if (_kind == 'advance') ...[
            TextField(controller: _amount, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: '${tr('amount')} (${tr('sar')})')),
            const SizedBox(height: 10),
            Row(children: [
              Text(tr('installments')),
              const Spacer(),
              IconButton(onPressed: _inst > 1 ? () => setState(() => _inst--) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$_inst', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              IconButton(onPressed: _inst < 12 ? () => setState(() => _inst++) : null, icon: const Icon(Icons.add_circle_outline)),
            ]),
          ],
          if (_kind == 'objection' && _refs.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _ref,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('objectionOn')),
              items: [for (final (v, l) in _refs) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _ref = v),
            ),
          const SizedBox(height: 10),
          TextField(controller: _text, maxLines: 3, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: tr('details'))),
          const SizedBox(height: 14),
          if (bad != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(bad, style: const TextStyle(color: C.fg3))),
          FilledButton.icon(
            onPressed: bad != null || _busy ? null : () async {
              setState(() => _busy = true);
              final f = DateFormat('yyyy-MM-dd');
              final err = await store.sendRequest({
                'kind': _kind,
                if (_kind == 'leave') ...{'date_from': f.format(_range!.start), 'date_to': f.format(_range!.end)},
                if (_kind == 'advance') ...{'amount': toNum(_amount.text), 'installments': _inst},
                if (_kind == 'objection' && _ref != null) ...{'ref_table': _ref!.split(':').first, 'ref_id': _ref!.split(':').last},
                'text': _text.text.trim(),
              });
              if (!context.mounted) return;
              setState(() => _busy = false);
              toast(context, err == null ? tr('sent') : tr('error'), bad: err != null);
              if (err == null) Navigator.pop(context);
            },
            icon: const Icon(Icons.send),
            label: Text(tr('send')),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Account ----------------

class _Account extends StatelessWidget {
  const _Account();
  @override
  Widget build(BuildContext context) {
    final w = store.myWorker;
    final files = [for (final f in (w['files'] as List?) ?? const []) Map<String, dynamic>.from(f as Map)];
    final project = str((store.mine['project'] as Map?)?['name']);
    final car = store.mine['vehicle'] as Map?;
    final carFiles = [for (final f in (car?['files'] as List?) ?? const []) Map<String, dynamic>.from(f as Map)];
    Widget info(IconData icon, String k, String v, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: C.primary50, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 20, color: C.primary700)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(k), style: const TextStyle(fontSize: 12, color: C.fg3)),
              Text(v.isEmpty ? '—' : v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ])),
            if (trailing != null) Flexible(child: trailing),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd, colors: [C.ink, C.navy]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: C.ink.withValues(alpha: .25), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Column(children: [
          GestureDetector(
            onTap: str(w['photo']).isEmpty ? null : () => _view(context, str(w['photo']), str(w['name'])),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [C.gold, C.goldLight])),
              child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(shape: BoxShape.circle, color: C.ink), child: WorkerPhoto(w['photo'], size: 108)),
            ),
          ),
          const SizedBox(height: 14),
          Text(str(w['name']), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text([str(w['trade']), str(w['id'])].where((x) => x.isNotEmpty).join(' · '), style: TextStyle(color: Colors.white.withValues(alpha: .75))),
          if (project.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.apartment_outlined, size: 16, color: C.goldLight),
                const SizedBox(width: 6),
                Flexible(child: Text(project, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
              ]),
            ),
          ],
        ]),
      ),
      SectionTitle(tr('myData')),
      CardBox(
        child: Column(children: [
          info(Icons.badge_outlined, 'iqama', str(w['iqama']), trailing: _expiry(str(w['iqamaExpiry']))),
          info(Icons.public, 'nationality', str(w['nat'])),
          info(Icons.event_available_outlined, 'joined', str(w['joined']).isEmpty ? '' : wDate(str(w['joined']), year: true)),
          info(Icons.phone_outlined, 'phone', str(w['phone'])),
        ]),
      ),
      SectionTitle('${tr('myDocs')} (${files.length})'),
      if (files.isEmpty) CardBox(child: EmptyState(tr('noDocs'), icon: Icons.folder_open_outlined)),
      if (files.isNotEmpty)
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .78,
          children: [for (final f in files) _DocCard(f, onOpen: () => _open(context, f))],
        ),
      if (car != null) ...[
        SectionTitle(tr('myVehicle')),
        CardBox(
          child: Column(children: [
            info(Icons.directions_car_outlined, 'vehicle', [str(car['plate']), str(car['make']), str(car['model']), str(car['year'])].where((x) => x.isNotEmpty).join(' · ')),
            for (final (k, icon) in [('regExpiry', Icons.article_outlined), ('insExpiry', Icons.verified_user_outlined), ('inspExpiry', Icons.build_circle_outlined)])
              if (str(car[k]).isNotEmpty) info(icon, k, wDate(str(car[k]), year: true), trailing: _expiry(str(car[k]))),
          ]),
        ),
        if (carFiles.isNotEmpty) ...[
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: .78,
            children: [for (final f in carFiles) _DocCard(f, onOpen: () => _open(context, f))],
          ),
        ],
      ],
      // A supervisor opens this portal from their staff profile, which already has these account settings.
      if (store.isWorker) ...[
      SectionTitle(tr('email')),
      const EmailCard(),
      SectionTitle(tr('language')),
      CardBox(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          for (final e in workerLangs.entries)
            ListTile(
              dense: true,
              title: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: lang == e.key ? const Icon(Icons.check_circle, color: C.primary) : null,
              onTap: () async {
                final err = await store.setLang(e.key);
                if (err != null && context.mounted) toast(context, err, bad: true);
              },
            ),
        ]),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(icon: const Icon(Icons.lock_reset), label: Text(tr('changePassword')), onPressed: () => _password(context)),
      const SizedBox(height: 8),
      OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: C.danger), icon: const Icon(Icons.logout), label: Text(tr('signOut')), onPressed: () => store.signOut()),
      ],
    ]);
  }

  /// Images open full screen, other files in the phone's viewer.
  void _open(BuildContext context, Json f) =>
      str(f['type']).startsWith('image/') ? _view(context, str(f['id']), str(f['cat']).isEmpty ? str(f['name']) : str(f['cat'])) : openStoredFile(context, f);

  /// Full-screen, zoomable view of a stored image.
  void _view(BuildContext context, String id, String title) => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
        body: FutureBuilder<String?>(
          future: store.fileUrl(id),
          builder: (c, u) => u.data == null
              ? const Center(child: CircularProgressIndicator())
              : InteractiveViewer(maxScale: 5, child: Center(child: Image.network(u.data!, fit: BoxFit.contain))),
        ),
      )));

  Future<void> _password(BuildContext context) async {
    final cur = TextEditingController(), next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('changePassword')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: cur, obscureText: true, decoration: InputDecoration(labelText: tr('currentPassword'))),
          TextField(controller: next, obscureText: true, decoration: InputDecoration(labelText: tr('newPassword'), helperText: tr('passwordRule'))),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('cancel'))), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('save')))],
      ),
    );
    if (ok != true || !context.mounted) return;
    final n = next.text;
    if (n.length < 8 || !RegExp(r'\d').hasMatch(n) || !RegExp(r'[^\d\s]').hasMatch(n)) return toast(context, tr('passwordRule'), bad: true);
    final err = await store.changePassword(cur.text, n);
    if (context.mounted) toast(context, err == null ? tr('passwordChanged') : tr('error'), bad: err != null);
  }
}

/// Valid / due soon / expired, in the worker's language.
Widget? _expiry(String date) {
  if (date.isEmpty) return null;
  final n = daysLeft(date);
  return n < 0 ? Pill(tr('expired'), tone: Tone.red) : n <= 30 ? Pill(tr('expiresIn', n), tone: Tone.orange) : Pill(tr('validUntil', wDate(date, year: true)), tone: Tone.green);
}

/// One of the worker's documents: a preview of the image (or the PDF icon), its type, number and expiry.
class _DocCard extends StatelessWidget {
  final Json f;
  final VoidCallback onOpen;
  const _DocCard(this.f, {required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final image = str(f['type']).startsWith('image/');
    final icon = Center(child: Icon(image ? Icons.image_outlined : Icons.picture_as_pdf_outlined, size: 40, color: image ? C.slate400 : C.danger));
    return CardBox(
      padding: EdgeInsets.zero,
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Container(
              color: C.slate100,
              child: !image
                  ? icon
                  : FutureBuilder<String?>(
                      future: store.fileUrl(str(f['id'])),
                      builder: (c, u) => u.data == null ? icon : Image.network(u.data!, fit: BoxFit.cover, errorBuilder: (_, _, _) => icon),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(str(f['cat']).isEmpty ? str(f['name']) : str(f['cat']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (str(f['number']).isNotEmpty) Text('# ${f['number']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.fg3)),
            if (_expiry(str(f['expiry'])) != null) Padding(padding: const EdgeInsets.only(top: 6), child: _expiry(str(f['expiry']))),
          ]),
        ),
      ]),
    );
  }
}
