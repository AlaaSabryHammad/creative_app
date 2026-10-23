import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../core/custody.dart';
import '../../core/i18n.dart';
import '../../core/logic.dart';
import '../../core/pay.dart' show round2;
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets.dart';

/// "My custody": the cash the company gave this user, the invoices/expenses they brought back and what they returned,
/// with the balance (still with them, or owed to them). Read-only, and only ever the user's own records
/// (the my_custody() function returns nothing about anyone else). Shown in the worker app and in the staff menu.
String _sar(num v) => '${fmtNum(round2(v))} ${tr('sar')}';
String _date(String d) => d.isEmpty ? '—' : DateFormat('d MMM y', lang).format(DateTime.parse(d));

const _kinds = <String, (IconData, Tone, String)>{
  'give': (Icons.south_west, Tone.green, 'cuGive'),
  'expense': (Icons.receipt_long_outlined, Tone.orange, 'cuExpense'),
  'return': (Icons.undo, Tone.blue, 'cuReturn'),
  'open': (Icons.flag_outlined, Tone.slate, 'cuOpening'),
};

String _balanceLabel(double b) => b > 0.004 ? tr('cuHeld') : b < -0.004 ? tr('cuOwed') : tr('cuSettled');

class MyCustodyScreen extends StatefulWidget {
  const MyCustodyScreen({super.key});
  @override
  State<MyCustodyScreen> createState() => _MyCustodyScreenState();
}

class _MyCustodyScreenState extends State<MyCustodyScreen> {
  String _f = 'all';
  String? _holder;

  @override
  Widget build(BuildContext context) {
    final holders = store.custodyHolders;
    if (holders.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [CardBox(child: EmptyState(tr('cuEmpty'), icon: Icons.account_balance_wallet_outlined))]);
    }
    final hid = holders.any((h) => h['id'] == _holder) ? _holder! : str(holders.first['id']);
    final holder = holders.firstWhere((h) => h['id'] == hid);
    final txs = [for (final t in store.custodyTxs) if (t['holderId'] == hid) t];
    final tot = custodyTotals(txs);
    final bal = round2(tot.balance);
    final ledger = [for (final r in custodyLedger(txs).reversed) if (_f == 'all' || r.$1['type'] == _f) r];
    final archive = [for (final a in store.custodyArchive) if (a['holderId'] == hid) a]..sort((a, b) => toNum(b['year']).compareTo(toNum(a['year'])));

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (holders.length > 1) ...[
        FilterChips(items: [for (final h in holders) (str(h['id']), str(h['name']))], value: hid, onChanged: (v) => setState(() => _holder = v)),
        const SizedBox(height: 12),
      ],
      // Balance header.
      Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd, colors: [C.ink, C.navy]),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: C.ink.withValues(alpha: .25), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.account_balance_wallet_outlined, color: C.goldLight, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('${tr('cuTitle')} — ${str(holder['name'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .85), fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 14),
          Text(_balanceLabel(bal), style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 13)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(_sar(bal.abs()), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800))),
        ]),
      ),
      const SizedBox(height: 12),
      StatGrid([
        StatTile(tone: Tone.green, icon: Icons.south_west, label: tr('cuGiven'), value: _sar(tot.given)),
        StatTile(tone: Tone.orange, icon: Icons.receipt_long_outlined, label: tr('cuSpent'), value: _sar(tot.spent), sub: '${tr('cuProjects')} ${_sar(tot.spentProject)} · ${tr('cuOutsideShort')} ${_sar(tot.spentOutside)}'),
        StatTile(tone: Tone.blue, icon: Icons.undo, label: tr('cuReturned'), value: _sar(tot.returned)),
        if (tot.opening.abs() > 0.004) StatTile(tone: Tone.slate, icon: Icons.flag_outlined, label: tr('cuOpening'), value: _sar(tot.opening)),
      ]),
      const SizedBox(height: 14),
      FilterChips(
        items: [('all', tr('cuAll')), ('give', tr('cuGive')), ('expense', tr('cuExpense')), ('return', tr('cuReturn'))],
        value: _f,
        onChanged: (v) => setState(() => _f = v),
      ),
      const SizedBox(height: 12),
      if (ledger.isEmpty) CardBox(child: EmptyState(tr('cuEmpty'), icon: Icons.account_balance_wallet_outlined)),
      for (final (t, runBal) in ledger) _TxTile(t, runBal),
      if (archive.isNotEmpty) ...[
        SectionTitle(tr('cuArchive')),
        for (final a in archive)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CardBox(
              child: Row(children: [
                const Icon(Icons.archive_outlined, color: C.fg3),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${a['year']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Pill(a['mode'] == 'carry' ? tr('cuCarried') : tr('cuZeroed'), tone: a['mode'] == 'carry' ? Tone.blue : Tone.slate),
                ])),
                const SizedBox(width: 8),
                // Flexible: a long label (e.g. in Bengali) wraps instead of overflowing a narrow phone.
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(tr('cuClosedBal'), textAlign: TextAlign.end, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: C.fg3)),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(_sar(toNum(a['balance'])), style: const TextStyle(fontWeight: FontWeight.w800))),
                  ]),
                ),
              ]),
            ),
          ),
      ],
      const SizedBox(height: 10),
      Text(tr('cuOwnerNote'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: C.fg3)),
    ]);
  }
}

class _TxTile extends StatelessWidget {
  final Json t;
  final double runBal;
  const _TxTile(this.t, this.runBal);

  @override
  Widget build(BuildContext context) {
    final type = str(t['type']);
    final (icon, tone, key) = _kinds[type] ?? _kinds['give']!;
    final d = deltaOf(t);
    final expense = type == 'expense';
    final title = expense
        ? '${str(t['supplier']).isEmpty ? tr('cuExpense') : str(t['supplier'])}${str(t['number']).isEmpty ? '' : ' · #${t['number']}'}'
        : type == 'give' && str(t['method']).isNotEmpty ? '${tr(key)} — ${t['method']}' : tr(key);
    final project = str(t['projectId']);
    final st = statusOf(t);  // pending / rejected invoices are listed but not counted in the balance
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        onTap: expense ? () => _showInvoice(context, t) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(backgroundColor: tone.bg, child: Icon(icon, color: tone.fg, size: 20)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(_date(str(t['date'])), style: const TextStyle(fontSize: 12.5, color: C.fg3)),
            if (expense) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (st != 'approved') Pill(tr(st == 'rejected' ? 'cuRejected' : 'cuPending'), tone: st == 'rejected' ? Tone.red : Tone.orange),
                if (str(t['cat']).isNotEmpty) Pill(str(t['cat'])),
                project.isEmpty ? Pill(tr('cuOutside'), tone: Tone.orange) : Pill(store.custodyProject(project).isEmpty ? tr('cuProject') : store.custodyProject(project), tone: Tone.blue, icon: Icons.apartment_outlined),
                if (t['file'] is Map) const Icon(Icons.attach_file, size: 16, color: C.fg3),
              ]),
              if (st == 'rejected' && str(t['rejectReason']).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(str(t['rejectReason']), style: const TextStyle(fontSize: 12.5, color: C.danger)),
              ],
            ] else if (str(t['note']).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(str(t['note']), style: const TextStyle(fontSize: 12.5, color: C.fg2)),
            ],
          ])),
          const SizedBox(width: 8),
          // Flexible so a long currency word (e.g. Bengali) shrinks or wraps instead of overflowing a narrow phone.
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (st != 'approved')
                FittedBox(fit: BoxFit.scaleDown, child: Text('(${_sar(amountOf(t))})', style: const TextStyle(fontWeight: FontWeight.w700, color: C.fg3)))
              else ...[
                FittedBox(fit: BoxFit.scaleDown, child: Text('${d >= 0 ? '+' : '−'} ${_sar(d.abs())}', style: TextStyle(fontWeight: FontWeight.w800, color: d >= 0 ? C.success : C.danger))),
                const SizedBox(height: 2),
                Text('${tr('cuBalance')} ${_sar(runBal)}', textAlign: TextAlign.end, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: C.fg3)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// One invoice: supplier, number, date, category, project, the items with VAT and total, notes and the photo.
void _showInvoice(BuildContext context, Json t) {
  final v = invTotals(t);
  final items = [for (final i in (t['items'] as List?) ?? const []) Map<String, dynamic>.from(i as Map)];
  final project = str(t['projectId']);
  final file = t['file'] is Map ? Map<String, dynamic>.from(t['file'] as Map) : null;
  Widget row(String k, String val, {bool strong = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: strong ? C.fg1 : C.fg2, fontWeight: strong ? FontWeight.w800 : FontWeight.w500))),
          Text(val, style: TextStyle(fontWeight: FontWeight.w800, color: color ?? (strong ? C.primary700 : C.fg1), fontSize: strong ? 17 : 14)),
        ]),
      );
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      maxChildSize: .95,
      builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        Text(str(t['supplier']).isEmpty ? tr('cuInvoice') : str(t['supplier']), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (str(t['cat']).isNotEmpty) Pill(str(t['cat'])),
          project.isEmpty ? Pill(tr('cuOutside'), tone: Tone.orange) : Pill(store.custodyProject(project).isEmpty ? tr('cuProject') : store.custodyProject(project), tone: Tone.blue, icon: Icons.apartment_outlined),
        ]),
        const SizedBox(height: 8),
        KV(tr('cuInvNo'), str(t['number'])),
        KV(tr('cuDate'), _date(str(t['date']))),
        if (str(t['supplierVat']).isNotEmpty) KV('VAT No.', str(t['supplierVat'])),
        SectionTitle(tr('cuItems')),
        CardBox(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            if (items.isEmpty) Text(tr('cuNoItems'), style: const TextStyle(color: C.fg3)),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(str(i['desc']).isEmpty ? '—' : str(i['desc']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${fmtNum(toNum(i['qty']))} ${str(i['unit'])} × ${fmtNum(toNum(i['rate']))}', style: const TextStyle(fontSize: 12.5, color: C.fg3)),
                  ])),
                  Text(_sar(toNum(i['qty']) * toNum(i['rate'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            const Divider(height: 20),
            row(tr('cuSub'), _sar(v.sub)),
            if (v.disc > 0) row(tr('cuDisc'), '− ${_sar(v.disc)}', color: C.danger),
            row('${tr('cuVat')} (${fmtNum(v.rate)}%)', _sar(v.vat)),
            const Divider(height: 14),
            row(tr('cuTotal'), _sar(v.total), strong: true),
          ]),
        ),
        if (str(t['notes']).isNotEmpty) ...[SectionTitle(tr('cuNotes')), Text(str(t['notes']), style: const TextStyle(color: C.fg2))],
        if (file != null) ...[
          SectionTitle(tr('cuFile')),
          if (str(file['type']).startsWith('image/'))
            GestureDetector(
              onTap: () => _viewImage(ctx, str(file['id']), str(t['supplier'])),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: FutureBuilder<String?>(
                  future: store.fileUrl(str(file['id'])),
                  builder: (c, u) => u.data == null
                      ? Container(height: 160, color: C.slate100, alignment: Alignment.center, child: u.connectionState == ConnectionState.done ? const Icon(Icons.broken_image_outlined, size: 36, color: C.slate400) : const CircularProgressIndicator())
                      : Image.network(u.data!, height: 220, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(height: 160, color: C.slate100, alignment: Alignment.center, child: const Icon(Icons.broken_image_outlined, size: 36, color: C.slate400))),
                ),
              ),
            )
          else
            OutlinedButton.icon(icon: const Icon(Icons.picture_as_pdf_outlined), label: Text('${tr('cuFileOpen')} — ${str(file['name'])}', maxLines: 1, overflow: TextOverflow.ellipsis), onPressed: () => openStoredFile(ctx, file)),
        ],
      ]),
    ),
  );
}

/// Full-screen, zoomable view of a stored image.
void _viewImage(BuildContext context, String id, String title) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
          body: FutureBuilder<String?>(
            future: store.fileUrl(id),
            builder: (c, u) => u.data == null
                ? const Center(child: CircularProgressIndicator())
                : InteractiveViewer(maxScale: 5, child: Center(child: Image.network(u.data!, fit: BoxFit.contain))),
          ),
        ),
      ),
    );
