import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/i18n.dart' show defaultLang, tr;
import '../core/logic.dart';
import '../core/pay.dart';
import 'notices.dart';

const sbUrl = 'https://sxkmcctluvomwapwomwz.supabase.co';
const sbKey = 'sb_publishable_m6GNJRur4Apt7LfOD89U_g_FD63Ut7g';

/// Users without an email sign in with their 10-digit ID / iqama number (profiles.login_id); the DB function
/// login_email() turns it into the account's auth email (a placeholder until they add and confirm a real one).
/// Same as the web (src/auth.js)./// Temporary password of accounts created with a new worker (web: OT_DEFAULT_PW); changed at first sign-in.
const defaultPassword = '123456789';

/// The account's real email, or '' while it only has a placeholder.
String realEmail(String e) => RegExp(r'^(id-)?\d{10}@(workers\.)?alhemedy\.com$', caseSensitive: false).hasMatch(e) ? '' : e;
/// How the user signs in: ID number and/or real email.
String loginLabel(Json u) {
  final l = [str(u['login_id']), realEmail(str(u['email']))].where((s) => s.isNotEmpty).join(' · ');
  return l.isEmpty ? str(u['email']) : l;
}

typedef Query = PostgrestFilterBuilder<List<Map<String, dynamic>>>;

/// Friendly Arabic message for a failed database call (web: src/table.js otDbError).
String dbError(Object e) {
  if (e is PostgrestException) {
    if (e.code == '42501' || e.message.contains('row-level security')) return 'ليست لديك صلاحية لهذا الإجراء.';
    if (e.code == '55000' || e.message.contains('month_locked')) return 'هذا الشهر مقفل لأن مسيّر رواتبه معتمد.';
    if (e.code == '23505') return 'هذا السجل موجود مسبقًا.';
    if (e.code == '40001') return 'تم تنفيذ هذا الإجراء من مستخدم آخر للتو.';
    return e.message;
  }
  return 'تعذّر الاتصال بالخادم. تحقق من الإنترنت.';
}

/// Overtime row ⇄ the entry shape the screens use (web: otFromRow / otToRow).
Json otFromRow(Map r) => {
      'id': r['id'], 'workerId': r['worker_id'], 'projectId': r['project_id'], 'date': r['date'], 'hours': toNum(r['hours']),
      'dayType': r['day_type'], 'rate': toNum(r['rate']), 'reason': r['reason'], 'status': r['status'], 'note': r['note'],
      'by': r['by_name'], 'paidBy': r['paid_by'] ?? '', 'createdBy': r['created_by'],
    };
Json otToRow(Json e) => {
      'worker_id': e['workerId'], 'project_id': e['projectId'] ?? '', 'date': e['date'], 'hours': e['hours'], 'day_type': e['dayType'] ?? 'normal',
      'rate': e['rate'] ?? 0, 'reason': e['reason'] ?? '', 'status': e['status'] ?? 'pending', 'note': e['note'] ?? '', 'by_name': e['by'] ?? '',
    };

/// Single app-wide store: session, profiles, the shared app_state collections and the record tables
/// (same Supabase backend and rules as the web app — see docs/API.md).
class Store extends ChangeNotifier {
  SupabaseClient get sb => Supabase.instance.client;

  Json? me;
  List<Json> users = [];
  final Map<String, dynamic> _data = {};
  final Map<String, int> _ver = {};
  final List<RealtimeChannel> _channels = [], _myChannels = [];
  final Map<String, Future<String?>> _urls = {};
  List<Json> _ot = [];

  bool get signedIn => me != null;
  bool get isAdmin => me?['admin'] == true;
  /// A worker-app-only account. A staff account may also be linked to its own worker record ([hasWorker]):
  /// a supervisor on the payroll keeps the staff app and also gets the worker side (own data, requests, notices).
  bool get isWorker => hasWorker && !isAdmin && ((me?['perms'] as List?) ?? const []).isEmpty;
  bool get hasWorker => me?['worker_id'] != null;
  /// Open tab of the worker app. The shell is keyed by the language (tr() text in const widgets would otherwise
  /// keep the old language), so the tab lives here to survive that rebuild.
  int workerTab = 0;
  /// An added email still waiting for its confirmation link to be opened.
  String pendingEmail = '';
  /// Still on the temporary password it was created with: only the change-password screen is reachable (the DB blocks the rest).
  bool get mustChangePw => me?['must_change_pw'] == true;
  String get myName => str(me?['name']);

  List<Json> list(String k) => ((_data[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Json obj(String k) => Map<String, dynamic>.from((_data[k] as Map?) ?? const {});
  String text(String k) => _data[k] is String ? _data[k] as String : '';

  /// Supervisors limited to some projects see only those projects and the workers currently at them.
  List<String> get scope => ((me?['projects'] as List?) ?? const []).map((e) => '$e').toList();
  bool get scoped => !isAdmin && scope.isNotEmpty;
  PaySettings get pay => PaySettings.from(isWorker ? Map<String, dynamic>.from((mine['settings'] as Map?) ?? {}) : settings);

  List<Json> get entries => _ot;
  /// Every worker with the effective overtime rate in 'rate' (auto from salary or manual) — see pay.dart otRate.
  /// Cached until the workers or settings documents are replaced.
  List<Json>? _wCache;
  Object? _wKey, _sKey;
  List<Json> get allWorkers {
    if (_wCache == null || !identical(_wKey, _data['workers']) || !identical(_sKey, _data['settings'])) {
      final p = pay;
      _wKey = _data['workers'];
      _sKey = _data['settings'];
      _wCache = list('workers').map((w) => {...w, 'rate': otRate(w, p)}).toList();
    }
    return _wCache!;
  }
  List<Json> get workers => scoped ? allWorkers.where((w) => scope.contains(site(str(w['id'])))).toList() : allWorkers;

  /// Workers are not assigned to projects: each one is where their latest attendance/overtime record is
  /// (worker_sites in schema.sql). workerId → {project_id, date}; today's, kept fresh over Realtime.
  Map<String, Json> sites = {};
  String site(String workerId) => str(sites[workerId]?['project_id']);
  Future<Map<String, Json>> sitesAt(String date) async {
    try {
      final rows = await sb.rpc('worker_sites', params: {'p_date': date}) as List;
      return {for (final r in rows) str(r['worker_id']): Map<String, dynamic>.from(r as Map)};
    } catch (_) {
      return {};
    }
  }
  List<Json> get projects => scoped ? list('projects').where((p) => scope.contains(p['id'])).toList() : list('projects');
  List<Json> get trades => list('trades');
  List<Json> get docs => list('docs');
  List<Json> get vehicles => list('vehicles');
  List<Json> get payments => list('payments');
  Json get lookups => obj('lookups');
  Json get settings => obj('settings');
  Json get company => obj('company');
  String get aiKey => text('ai');
  int get alertDays => toNum(company['alertDays']).toInt() > 0 ? toNum(company['alertDays']).toInt() : 30;

  Json? worker(String? id) => allWorkers.cast<Json?>().firstWhere((w) => w!['id'] == id, orElse: () => null);
  Json? project(String? id) => list('projects').cast<Json?>().firstWhere((p) => p!['id'] == id, orElse: () => null);
  /// Overtime paid through an overtime payout or inside an approved salary payroll.
  Set<String> get paidIds => {...paidSet(payments), for (final e in _ot) if (str(e['paidBy']).isNotEmpty) str(e['id'])};

  /// Module permission (admins see everything; `users` is admin-only; advances ride on payroll).
  bool can(String module) {
    if (me == null || isWorker) return false;
    if (module == 'profile') return true;
    if (isAdmin) return true;
    if (module == 'users') return false;
    return ((me!['perms'] as List?) ?? []).contains(module == 'advances' ? 'payroll' : module);
  }

  /// Restores an existing session on startup. Returns an error message when access is refused.
  Future<String?> restore() async {
    if (sb.auth.currentSession == null) return null;
    return _enter(sb.auth.currentUser!.id);
  }

  Future<String?> signIn(String login, String password) async {
    try {
      var email = login.trim();
      if (RegExp(r'^\d{10}$').hasMatch(email)) {
        final e = await sb.rpc('login_email', params: {'p_login': email, 'p_password': password});
        if (e == null) return 'بيانات الدخول أو كلمة المرور غير صحيحة.';
        email = '$e';
      }
      final r = await sb.auth.signInWithPassword(email: email, password: password);
      final err = await _enter(r.user!.id);
      if (err == null) await sb.from('profiles').update({'last_login': DateTime.now().toUtc().toIso8601String()}).eq('id', r.user!.id);
      return err;
    } on PostgrestException catch (e) {
      return e.message.contains('too_many_attempts') ? 'محاولات خاطئة كثيرة لهذا الرقم، انتظر 15 دقيقة ثم حاول مجددًا.' : e.message;
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login')) return 'بيانات الدخول أو كلمة المرور غير صحيحة.';
      if (m.contains('rate') || m.contains('too many')) return 'محاولات كثيرة، انتظر قليلًا ثم حاول مجددًا.';
      return e.message;
    } catch (e) {
      return 'تعذّر الاتصال بالخادم. تحقق من الإنترنت.';
    }
  }

  Future<String?> _enter(String uid) async {
    try {
      users = (await sb.from('profiles').select().order('created_at')).map((e) => Map<String, dynamic>.from(e)).toList();
      final p = users.cast<Json?>().firstWhere((u) => u!['id'] == uid, orElse: () => null);
      if (p == null || p['active'] != true) {
        await sb.auth.signOut();
        return p == null ? 'لم يُعثر على ملف المستخدم.' : 'الحساب موقوف أو بانتظار التفعيل من مدير النظام.';
      }
      me = p;
      pendingEmail = sb.auth.currentUser?.newEmail ?? '';
      if (mustChangePw) {
        notifyListeners();
        return null;
      }
      if (!isWorker) await _loadState();
      if (hasWorker) {
        await _loadWorker();
        unawaited(Notices.register(sb, isWorker ? lang ?? defaultLang(myWorker) : 'ar'));
      }
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذّر تحميل البيانات: $e';
    }
  }

  // ---------- Reading tables ----------

  /// Every row of `table` the user may see (PostgREST returns at most 1000 per request, so read in pages).
  Future<List<Json>> fetchAll(String table, [Query Function(Query q)? where]) async {
    final out = <Json>[];
    for (var from = 0;; from += 1000) {
      Query q = sb.from(table).select();
      if (where != null) q = where(q);
      final rows = await q.order('id').range(from, from + 999);
      out.addAll(rows.map((e) => Map<String, dynamic>.from(e)));
      if (rows.length < 1000) return out;
    }
  }

  /// Staff live updates go to [_channels]; the worker side's (own rows only) to [_myChannels], so reloading
  /// one never drops the other for a supervisor who has both.
  void _watch(String table, void Function(PostgresChangePayload p) onChange, {bool mine = false}) {
    (mine ? _myChannels : _channels).add(sb.channel('$table-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: table, callback: onChange,
          filter: mine ? PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'worker_id', value: myWorkerId) : null,
        )
        .subscribe());
  }

  Future<void> _unwatch({bool mine = false}) async {
    final list = mine ? _myChannels : _channels;
    for (final c in list) {
      await c.unsubscribe();
    }
    list.clear();
  }

  Future<void> _loadState() async {
    final rows = await sb.from('app_state').select('key,value,version');
    _data.clear();
    _ver.clear();
    for (final r in rows) {
      _data[r['key'] as String] = r['value'];
      _ver[r['key'] as String] = (r['version'] as num).toInt();
    }
    _ot = (await fetchAll('overtime')).map(otFromRow).toList();
    sites = await sitesAt(todayIso());
    await _unwatch();
    _watch('app_state', (payload) {
      final r = payload.newRecord;
      final k = r['key'] as String?;
      final v = (r['version'] as num?)?.toInt() ?? 0;
      if (k == null || (_ver[k] ?? 0) >= v) return;
      _data[k] = r['value'];
      _ver[k] = v;
      notifyListeners();
    });
    // New attendance or overtime can move workers between sites.
    Timer? t;
    void resite() {
      t?.cancel();
      t = Timer(const Duration(milliseconds: 800), () async {
        sites = await sitesAt(todayIso());
        notifyListeners();
      });
    }
    _watch('overtime', (payload) {
      final id = payload.newRecord['id'] ?? payload.oldRecord['id'];
      _ot = [..._ot.where((e) => e['id'] != id), if (payload.eventType != PostgresChangeEvent.delete) otFromRow(payload.newRecord)];
      notifyListeners();
      resite();
    });
    _watch('attendance', (_) => resite());
  }

  Future<void> refresh() async {
    if (!isWorker) await _loadState();
    if (hasWorker) await _loadWorker();
    notifyListeners();
  }

  /// Versioned write through the save_state RPC. Returns an Arabic error message, or null on success.
  Future<String?> save(String key, dynamic value) async {
    try {
      final v = await sb.rpc('save_state', params: {'p_key': key, 'p_value': value, 'p_expected': _ver[key] ?? 0});
      _data[key] = value;
      _ver[key] = (v as num).toInt();
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      final row = await sb.from('app_state').select('value,version').eq('key', key).maybeSingle();
      if (row != null) {
        _data[key] = row['value'];
        _ver[key] = (row['version'] as num).toInt();
      }
      notifyListeners();
      if (e.code == '42501') return 'ليست لديك صلاحية لتعديل هذه البيانات.';
      if (e.code == '40001' || e.code == '23505') return 'عدّل مستخدم آخر هذه البيانات للتو، تم تحميل آخر نسخة. أعد المحاولة.';
      return 'تعذّر الحفظ: ${e.message}';
    } catch (e) {
      return 'تعذّر الاتصال بالخادم.';
    }
  }

  // ---------- Staff writes on the record tables ----------

  Future<String?> _run(Future<void> Function() fn) async {
    try {
      await fn();
      notifyListeners();
      return null;
    } catch (e) {
      return dbError(e);
    }
  }

  void _mergeOt(List rows) {
    final ids = {for (final r in rows) r['id']};
    _ot = [..._ot.where((e) => !ids.contains(e['id'])), for (final r in rows) otFromRow(r as Map)];
  }

  Future<String?> insertOt(List<Json> list) => _run(() async => _mergeOt(await sb.from('overtime').insert(list.map(otToRow).toList()).select()));
  Future<String?> decideOt(List<String> ids, String status, {String note = ''}) =>
      _run(() async => _mergeOt(await sb.from('overtime').update({'status': status, 'note': note}).inFilter('id', ids).select()));
  Future<String?> saveAttendance(List<Json> rows) => _run(() async => sb.from('attendance').upsert(rows, onConflict: 'worker_id,date'));
  Future<String?> addDeduction(Json d) => _run(() async => sb.from('deductions').insert(d));
  Future<String?> decideDeductions(List<String> ids, String status, {String note = ''}) =>
      _run(() async => sb.from('deductions').update({'status': status, 'note': note}).inFilter('id', ids));
  Future<String?> deleteRow(String table, String id) => _run(() async => sb.from(table).delete().eq('id', id));
  Future<String?> decideRequest(String id, bool approve, String reply) =>
      _run(() async => sb.rpc('decide_request', params: {'p_id': id, 'p_approve': approve, 'p_reply': reply}));
  Future<bool> monthLocked(String date) async {
    try {
      return await sb.rpc('month_locked', params: {'d': date}) == true;
    } catch (_) {
      return false;
    }
  }

  // ---------- Worker account (mobile portal): only the worker's own data ----------

  Json mine = {};
  /// The worker's own overtime (the staff app's [entries] hold everyone's in scope).
  List<Json> myOt = [];
  List<Json> myAtt = [], myDed = [], myAdv = [], myReq = [], mySlips = [];
  /// The worker's notifications, newest first (written by database triggers on every action — see docs/API.md).
  List<Json> myNotes = [];
  int get unread => myNotes.where((n) => n['read_at'] == null).length;
  Json get myWorker => Map<String, dynamic>.from((mine['worker'] as Map?) ?? {});
  String get myWorkerId => str(me?['worker_id']);

  /// Only the worker's own rows: a linked supervisor could read others' too, and deductions are shown to a
  /// worker once approved.
  Future<void> _loadWorker() async {
    mine = Map<String, dynamic>.from((await sb.rpc('my_worker')) as Map? ?? {});
    Query own(Query q) => q.eq('worker_id', myWorkerId);
    final res = await Future.wait([
      fetchAll('overtime', own), fetchAll('attendance', own), fetchAll('deductions', (q) => own(q).eq('status', 'approved')),
      fetchAll('advances', own), fetchAll('requests', own), fetchAll('payslips', own), fetchAll('notifications', own),
    ]);
    myOt = res[0].map(otFromRow).toList();
    myAtt = res[1];
    myDed = res[2];
    myAdv = res[3];
    myReq = res[4];
    mySlips = res[5]..sort((a, b) => str(b['month']).compareTo(str(a['month'])));
    myNotes = res[6]..sort((a, b) => str(b['created_at']).compareTo(str(a['created_at'])));
    await Notices.seen(myNotes);
    await _unwatch(mine: true);
    // Any change to the worker's rows (a decision, a new payslip, today's sheet) reloads the portal.
    Timer? t;
    for (final table in ['overtime', 'attendance', 'deductions', 'advances', 'requests', 'payslips']) {
      _watch(table, (_) {
        t?.cancel();
        t = Timer(const Duration(milliseconds: 600), () async {
          await _loadWorker();
          notifyListeners();
        });
      }, mine: true);
    }
    // A new notice pops up on the phone right away (and is not shown again by the background check).
    _watch('notifications', (payload) {
      final r = Map<String, dynamic>.from(payload.newRecord);
      if (r.isEmpty) return;
      myNotes = [r, ...myNotes.where((n) => n['id'] != r['id'])];
      if (r['read_at'] == null) Notices.show(r);
      notifyListeners();
    }, mine: true);
  }

  /// The app came back to the foreground: iOS drops the live connection while it is in the background,
  /// so show the notices that arrived meanwhile, then reload (which also reconnects the live updates).
  Future<void> resumeWorker() async {
    if (!hasWorker || mustChangePw) return;
    try {
      await Notices.poll();
      await _loadWorker();
      notifyListeners();
    } catch (_) {}
  }

  /// Marks every notification read (the bell was opened).
  Future<void> readNotes() async {
    if (unread == 0) return;
    final now = DateTime.now().toUtc().toIso8601String();
    myNotes = [for (final n in myNotes) n['read_at'] == null ? {...n, 'read_at': now} : n];
    notifyListeners();
    try {
      await sb.rpc('read_notifications');
    } catch (_) {}
  }

  Future<String?> sendRequest(Json r) => _run(() async {
        await sb.from('requests').insert(r);
        myReq = await fetchAll('requests');
      });
  Future<String?> cancelRequest(String id) => _run(() async {
        await sb.from('requests').delete().eq('id', id);
        myReq = myReq.where((r) => r['id'] != id).toList();
      });

  /// Worker app language, kept in the auth user's metadata so it follows the worker to any phone.
  String? get lang => sb.auth.currentUser?.userMetadata?['lang'] as String?;
  Future<String?> setLang(String code) async {
    try {
      await sb.auth.updateUser(UserAttributes(data: {'lang': code}));
    } catch (e) {
      return tr('error');
    }
    await Notices.setLang(code);
    notifyListeners();
    return null;
  }

  // ---------- Session ----------

  /// Signed URL for a private file (cached for the session; links last one hour).
  Future<String?> fileUrl(String id) => _urls.putIfAbsent(id, () => sb.storage.from('files').createSignedUrl(id, 3600).then<String?>((u) => u).catchError((_) => null));

  Future<void> signOut() async {
    workerTab = 0;
    await _unwatch();
    await _unwatch(mine: true);
    if (hasWorker) await Notices.unregister(sb);
    await sb.auth.signOut();
    me = null;
    users = [];
    _data.clear();
    _ver.clear();
    _urls.clear();
    _ot = [];
    myOt = [];
    mine = {};
    myAtt = myDed = myAdv = myReq = mySlips = myNotes = [];
    sites = {};
    notifyListeners();
  }

  /// Adds / changes the user's email: Supabase emails a confirmation link; it is used for sign-in only once confirmed.
  Future<String?> changeEmail(String email) async {
    try {
      await sb.auth.updateUser(UserAttributes(email: email.trim()), emailRedirectTo: 'https://overtime.alhemedy.com/');
      pendingEmail = email.trim();
      return null;
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      return m.contains('already') || m.contains('exists') ? tr('emailTaken') : m.contains('invalid') ? tr('emailInvalid') : e.message;
    }
  }

  /// First sign-in: replace the temporary password, then load the app (the DB clears must_change_pw itself).
  Future<String?> setFirstPassword(String next) async {
    if (next == defaultPassword) return tr('passwordSame');
    try {
      await sb.auth.updateUser(UserAttributes(password: next));
    } on AuthException catch (e) {
      return e.message;
    }
    return _enter(sb.auth.currentUser!.id);
  }

  Future<String?> changePassword(String current, String next) async {
    try {
      await sb.auth.signInWithPassword(email: me!['email'], password: current);
    } catch (_) {
      return 'كلمة المرور الحالية غير صحيحة';
    }
    try {
      await sb.auth.updateUser(UserAttributes(password: next));
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }
}

final store = Store();
