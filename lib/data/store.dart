import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/logic.dart';

const sbUrl = 'https://sxkmcctluvomwapwomwz.supabase.co';
const sbKey = 'sb_publishable_m6GNJRur4Apt7LfOD89U_g_FD63Ut7g';

/// Single app-wide store: session, profiles and the shared app_state collections
/// (same Supabase backend and rules as the web app — see docs/API.md).
class Store extends ChangeNotifier {
  SupabaseClient get sb => Supabase.instance.client;

  Json? me;
  List<Json> users = [];
  final Map<String, dynamic> _data = {};
  final Map<String, int> _ver = {};
  RealtimeChannel? _channel;
  final Map<String, Future<String?>> _urls = {};

  bool get signedIn => me != null;
  bool get isAdmin => me?['admin'] == true;

  List<Json> list(String k) => ((_data[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Json obj(String k) => Map<String, dynamic>.from((_data[k] as Map?) ?? const {});
  String text(String k) => _data[k] is String ? _data[k] as String : '';

  List<Json> get entries => list('entries');
  List<Json> get workers => list('workers');
  List<Json> get projects => list('projects');
  List<Json> get trades => list('trades');
  List<Json> get docs => list('docs');
  List<Json> get vehicles => list('vehicles');
  Json get lookups => obj('lookups');
  Json get settings => obj('settings');
  Json get company => obj('company');
  String get aiKey => text('ai');
  int get alertDays => toNum(company['alertDays']).toInt() > 0 ? toNum(company['alertDays']).toInt() : 30;

  Json? worker(String? id) => workers.cast<Json?>().firstWhere((w) => w!['id'] == id, orElse: () => null);
  Json? project(String? id) => projects.cast<Json?>().firstWhere((p) => p!['id'] == id, orElse: () => null);

  /// Module permission (admins see everything; `users` is admin-only).
  bool can(String module) {
    if (me == null) return false;
    if (module == 'profile') return true;
    if (isAdmin) return true;
    if (module == 'users') return false;
    return ((me!['perms'] as List?) ?? []).contains(module);
  }

  /// Restores an existing session on startup. Returns an error message when access is refused.
  Future<String?> restore() async {
    if (sb.auth.currentSession == null) return null;
    return _enter(sb.auth.currentUser!.id);
  }

  Future<String?> signIn(String email, String password) async {
    try {
      final r = await sb.auth.signInWithPassword(email: email.trim(), password: password);
      final err = await _enter(r.user!.id);
      if (err == null) await sb.from('profiles').update({'last_login': DateTime.now().toUtc().toIso8601String()}).eq('id', r.user!.id);
      return err;
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login')) return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
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
      await _loadState();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذّر تحميل البيانات: $e';
    }
  }

  Future<void> _loadState() async {
    final rows = await sb.from('app_state').select('key,value,version');
    _data.clear();
    _ver.clear();
    for (final r in rows) {
      _data[r['key'] as String] = r['value'];
      _ver[r['key'] as String] = (r['version'] as num).toInt();
    }
    await _channel?.unsubscribe();
    _channel = sb
        .channel('app_state')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_state',
          callback: (payload) {
            final r = payload.newRecord;
            final k = r['key'] as String?;
            final v = (r['version'] as num?)?.toInt() ?? 0;
            if (k == null || (_ver[k] ?? 0) >= v) return;
            _data[k] = r['value'];
            _ver[k] = v;
            notifyListeners();
          },
        )
        .subscribe();
  }

  Future<void> refresh() async {
    await _loadState();
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

  /// Signed URL for a private file (cached for the session; links last one hour).
  Future<String?> fileUrl(String id) => _urls.putIfAbsent(id, () => sb.storage.from('files').createSignedUrl(id, 3600).then<String?>((u) => u).catchError((_) => null));

  Future<void> signOut() async {
    await _channel?.unsubscribe();
    _channel = null;
    await sb.auth.signOut();
    me = null;
    users = [];
    _data.clear();
    _ver.clear();
    _urls.clear();
    notifyListeners();
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
