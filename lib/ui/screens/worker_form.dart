import 'package:flutter/material.dart';
import '../../core/logic.dart';
import '../../core/pay.dart';
import '../../core/theme.dart';
import '../../data/extract.dart';
import '../../data/store.dart';
import '../doc_pick.dart';
import '../widgets.dart';

bool _isDate(String v) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v);

/// Reads a worker's document with the AI. Returns the uploaded file entry (typed, numbered, dated) and the
/// worker fields it found; null when cancelled. Same prompt and rules as the web's worker form.
Future<(Json file, Json found, String summary)?> readWorkerDoc(BuildContext context) async {
  final d = await pickDoc(context, title: 'مستند العامل');
  if (d == null) return null;
  final meta = await store.uploadFile(d.bytes, d.name, d.mime);
  final types = store.workerDocTypes;
  final r = await extractDoc('worker', d.bytes, d.mime, {'docTypes': types, 'nationalities': store.nationalities, 'trades': store.trades.map((t) => t['name']).toList()});
  String v(String k) => str(r[k]).trim();
  final iqama = v('iqama').replaceAll(RegExp(r'\D'), '');
  final phone = v('phone').replaceAll(RegExp(r'\D'), '');
  final found = {
    'name': v('name'), 'nat': v('nat'), 'trade': v('trade'),
    'iqama': iqama.length == 10 ? iqama : '',
    'phone': RegExp(r'^05\d{8}$').hasMatch(phone) ? phone : '',
    'iqamaExpiry': _isDate(v('iqamaExpiry')) ? v('iqamaExpiry') : '',
  };
  final cat = types.contains(v('docType')) ? v('docType') : '';
  final expiry = _isDate(v('docExpiry')) ? v('docExpiry') : cat == types.first ? found['iqamaExpiry']! : '';
  return ({...meta, 'cat': cat, 'number': v('docNumber'), 'expiry': expiry}, found, v('summary'));
}

/// Adds a document to an existing worker from its details: the AI types and dates it, and a later iqama expiry
/// found on it updates the worker (nothing else typed by hand is overwritten).
Future<void> addWorkerDoc(BuildContext context, String workerId) async {
  try {
    final res = await readWorkerDoc(context);
    if (res == null || !context.mounted) return;
    final (file, found, summary) = res;
    final w = {...?store.list('workers').cast<Json?>().firstWhere((x) => x!['id'] == workerId, orElse: () => null)};
    if (w.isEmpty) return;
    final patch = <String, dynamic>{};
    for (final e in found.entries) {
      if (str(e.value).isEmpty || e.value == w[e.key]) continue;
      if (str(w[e.key]).trim().isEmpty || (e.key == 'iqamaExpiry' && str(e.value).compareTo(str(w[e.key])) > 0)) patch[e.key] = e.value;
    }
    final (err, _) = await store.saveWorker({...w, ...patch, 'files': [file, ...((w['files'] as List?) ?? const [])]});
    if (!context.mounted) return;
    toast(context, err ?? 'حُفظ «${str(file['cat']).isEmpty ? file['name'] : file['cat']}»${patch.isEmpty ? '' : ' وحُدّث ${patch.length} حقل'}${summary.isEmpty ? '' : ' — $summary'}', bad: err != null);
  } catch (e) {
    if (context.mounted) toast(context, '$e', bad: true);
  }
}

/// New worker from the phone: a photo of the iqama / passport / licence fills the form through the AI, and the
/// document is kept in the worker's file. Admins can create the worker's app login at the same time.
class WorkerForm extends StatefulWidget {
  const WorkerForm({super.key});
  @override
  State<WorkerForm> createState() => _WorkerFormState();
}

class _WorkerFormState extends State<WorkerForm> {
  final _ctl = {for (final k in ['name', 'iqama', 'phone', 'salary', 'rate']) k: TextEditingController()};
  String _nat = '', _trade = '', _iqamaExpiry = '', _joined = todayIso();
  final List<Json> _files = [];
  final Set<String> _ai = {};
  bool _busy = false, _account = store.isAdmin;
  String? _summary;

  Future<void> _read() async {
    setState(() => _busy = true);
    try {
      final res = await readWorkerDoc(context);
      if (res != null) {
        final (file, found, summary) = res;
        _files.insert(0, file);
        for (final k in ['name', 'iqama', 'phone']) {
          if (str(found[k]).isNotEmpty && _ctl[k]!.text.trim().isEmpty) { _ctl[k]!.text = found[k]; _ai.add(k); }
        }
        if (str(found['nat']).isNotEmpty && _nat.isEmpty) { _nat = found['nat']; _ai.add('nat'); }
        if (store.trades.any((t) => t['name'] == found['trade']) && _trade.isEmpty) { _trade = found['trade']; _ai.add('trade'); _fillRate(); }
        if (str(found['iqamaExpiry']).compareTo(_iqamaExpiry) > 0) { _iqamaExpiry = found['iqamaExpiry']; _ai.add('iqamaExpiry'); }
        _summary = summary;
      }
    } catch (e) {
      if (mounted) toast(context, '$e', bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _fillRate() {
    final r = toNum(store.trades.cast<Json?>().firstWhere((t) => t!['name'] == _trade, orElse: () => null)?['rate']);
    if (_ctl['rate']!.text.isEmpty && r > 0) _ctl['rate']!.text = fmtNum(r);
  }

  Future<void> _save() async {
    final name = _ctl['name']!.text.trim(), iqama = _ctl['iqama']!.text.trim(), phone = _ctl['phone']!.text.trim();
    final salary = toNum(_ctl['salary']!.text), rate = toNum(_ctl['rate']!.text);
    final err = name.isEmpty ? 'أدخل اسم العامل'
        : _trade.isEmpty ? 'اختر المهنة'
        : !RegExp(r'^\d{10}$').hasMatch(iqama) ? 'رقم الهوية / الإقامة 10 أرقام'
        : store.list('workers').any((w) => w['iqama'] == iqama) ? 'رقم الهوية مسجّل لعامل آخر'
        : phone.isNotEmpty && !RegExp(r'^05\d{8}$').hasMatch(phone) ? 'رقم الجوال يبدأ بـ 05 ويتكون من 10 أرقام'
        : salary <= 0 && rate <= 0 ? 'أدخل الراتب الشهري أو أجر ساعة الإضافي' : null;
    if (err != null) return toast(context, err, bad: true);
    setState(() => _busy = true);
    // With a salary the overtime rate follows it (Labor Law art. 107), as the web's "automatic" mode.
    final w = <String, dynamic>{
      'name': name, 'trade': _trade, 'nat': _nat, 'iqama': iqama, 'iqamaExpiry': _iqamaExpiry, 'phone': phone, 'joined': _joined,
      'salary': salary, 'rateMode': salary > 0 ? 'auto' : 'manual', 'active': true, 'photo': '', 'files': _files, 'leaveOpening': 0, 'leaveFrom': '',
    };
    w['rate'] = salary > 0 ? otRate(w, store.pay) : rate;
    final (e1, id) = await store.saveWorker(w);
    String? e2;
    if (e1 == null && _account) e2 = await store.createWorkerAccount({...w, 'id': id});
    if (!mounted) return;
    setState(() => _busy = false);
    if (e1 != null) return toast(context, e1, bad: true);
    toast(context, e2 != null ? 'أُضيف العامل لكن تعذّر إنشاء حسابه: $e2' : 'تمت إضافة $name ($id)${_account ? ' — اسم الدخول $iqama وكلمة المرور المؤقتة $defaultPassword' : ''}', bad: e2 != null);
    Navigator.pop(context);
  }

  InputDecoration _dec(String k, String label, {String? help, String? suffix}) =>
      InputDecoration(labelText: label, helperText: help, suffixText: suffix, prefixIcon: _ai.contains(k) ? const Icon(Icons.auto_awesome, color: C.violet, size: 18) : null);

  @override
  Widget build(BuildContext context) {
    final trades = store.trades.map((t) => str(t['name'])).toList();
    final nats = {...store.nationalities, if (_nat.isNotEmpty) _nat}.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة عامل')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        CardBox(
          onTap: _busy ? null : _read,
          child: Row(children: [
            _busy ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.auto_awesome, color: C.violet, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_busy ? 'يقرأ الذكاء الاصطناعي المستند…' : 'صوّر الإقامة أو الجواز أو الرخصة', style: const TextStyle(fontWeight: FontWeight.w800)),
              const Text('تُعبّأ البيانات تلقائيًا ويُحفظ المستند في ملف العامل مع تاريخ انتهائه', style: TextStyle(fontSize: 12.5, color: C.fg3)),
            ])),
          ]),
        ),
        if (_summary != null && _summary!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: AiNote(_summary!)),
        const SizedBox(height: 14),
        TextField(controller: _ctl['name'], decoration: _dec('name', 'الاسم الكامل')),
        const SizedBox(height: 12),
        TextField(controller: _ctl['iqama'], keyboardType: TextInputType.number, maxLength: 10, decoration: _dec('iqama', 'رقم الهوية / الإقامة', help: 'هو اسم دخول العامل في التطبيق')),
        const SizedBox(height: 4),
        DateField('انتهاء الإقامة', _iqamaExpiry, (v) => setState(() => _iqamaExpiry = v), future: true),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _nat.isEmpty ? null : _nat,
          decoration: _dec('nat', 'الجنسية'),
          items: [for (final n in nats) DropdownMenuItem(value: n, child: Text(n))],
          onChanged: (v) => setState(() => _nat = v ?? ''),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _trade.isEmpty ? null : _trade,
          decoration: _dec('trade', 'المهنة'),
          items: [for (final t in trades) DropdownMenuItem(value: t, child: Text(t))],
          onChanged: (v) => setState(() { _trade = v ?? ''; _fillRate(); }),
        ),
        const SizedBox(height: 12),
        TextField(controller: _ctl['phone'], keyboardType: TextInputType.phone, decoration: _dec('phone', 'رقم الجوال (اختياري)')),
        const SizedBox(height: 12),
        DateField('تاريخ الالتحاق', _joined, (v) => setState(() => _joined = v)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _ctl['salary'], keyboardType: TextInputType.number, decoration: _dec('salary', 'الراتب الشهري', suffix: 'ر.س'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _ctl['rate'], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _dec('rate', 'أجر ساعة الإضافي', suffix: 'ر.س', help: 'يُحسب من الراتب إن أُدخل'))),
        ]),
        if (_files.isNotEmpty) ...[
          const SectionTitle('المستندات'),
          CardBox(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Column(children: [for (final f in _files) FileTile(f)])),
        ],
        if (store.isAdmin)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _account,
            onChanged: (v) => setState(() => _account = v),
            title: const Text('إنشاء حساب دخول للعامل', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('اسم الدخول رقم الإقامة وكلمة المرور المؤقتة $defaultPassword، ويغيّرها عند أول دخول'),
          ),
        const SizedBox(height: 10),
        FilledButton.icon(icon: const Icon(Icons.person_add_alt_1_outlined), label: const Text('إضافة العامل'), onPressed: _busy ? null : _save),
      ]),
    );
  }
}
