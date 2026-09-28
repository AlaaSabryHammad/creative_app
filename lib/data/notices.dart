import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import '../core/i18n.dart';
import '../core/logic.dart';
import 'store.dart' show sbUrl, sbKey;

/// Background check (Android WorkManager, about every 15 minutes while the app is closed).
@pragma('vm:entry-point')
void noticesDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await Notices.poll();
    } catch (_) {}
    return true;
  });
}

/// Phone notifications for worker accounts. The database writes a notification for every action on the
/// worker's records (docs/API.md › Notifications); the app shows each one on the phone — live over Realtime
/// while it runs (see Store), and from the background check, which has no session and asks
/// device_notifications() with a random secret registered for this phone.
class Notices {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _task = 'creative.notices';
  static const _kSecret = 'notices.secret', _kSince = 'notices.since', _kLang = 'notices.lang';
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('notices', 'Notifications', importance: Importance.high, priority: Priority.high),
    iOS: DarwinNotificationDetails(),
  );

  static bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Called once when the app starts.
  static Future<void> start() async {
    await init();
    if (!_supported || !Platform.isAndroid) return;
    try {
      await Workmanager().initialize(noticesDispatcher);
    } catch (_) {}
  }

  static Future<void> init() async {
    if (_ready || !_supported) return;
    try {
      await _plugin.initialize(settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ));
      _ready = true;
    } catch (_) {}
  }

  /// Shows one notification row on the phone (the same row id replaces its earlier notice).
  static Future<void> show(Json n) async {
    await init();
    if (!_ready) return;
    final (title, body) = noticeText(n);
    await _plugin.show(id: toNum(n['id']).toInt() & 0x7fffffff, title: title, body: body, notificationDetails: _details);
    await _since(str(n['created_at']));
  }

  /// Everything already in the app's list is not shown again by the background check.
  static Future<void> seen(List<Json> notes) async {
    if (!_supported || notes.isEmpty) return;
    await _since(str(notes.first['created_at']));
  }

  static Future<void> _since(String ts) async {
    final t = DateTime.tryParse(ts);
    if (t == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cur = DateTime.tryParse(prefs.getString(_kSince) ?? '');
      if (cur == null || t.isAfter(cur)) await prefs.setString(_kSince, t.toUtc().toIso8601String());
    } catch (_) {}
  }

  /// After a worker signs in: registers this phone, asks for notification permission and schedules the background check.
  static Future<void> register(SupabaseClient sb, String langCode) async {
    if (!_supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      var secret = prefs.getString(_kSecret);
      if (secret == null) {
        final r = Random.secure();
        secret = base64Url.encode(List<int>.generate(32, (_) => r.nextInt(256)));
        await prefs.setString(_kSecret, secret);
      }
      await prefs.setString(_kLang, langCode);
      await sb.rpc('register_device', params: {'p_secret': secret, 'p_platform': Platform.operatingSystem});
      await init();
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
      if (Platform.isAndroid) {
        await Workmanager().registerPeriodicTask(_task, _task,
            frequency: const Duration(minutes: 15),
            constraints: Constraints(networkType: NetworkType.connected),
            existingWorkPolicy: ExistingPeriodicWorkPolicy.keep);
      }
    } catch (_) {}
  }

  /// The worker changed the app language: background notices follow it.
  static Future<void> setLang(String code) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_kLang, code);
    } catch (_) {}
  }

  /// On sign-out: this phone stops receiving the worker's notices.
  static Future<void> unregister(SupabaseClient sb) async {
    if (!_supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final secret = prefs.getString(_kSecret);
      if (secret != null) await sb.rpc('unregister_device', params: {'p_secret': secret});
      await prefs.remove(_kSecret);
      await prefs.remove(_kSince);
      if (Platform.isAndroid) await Workmanager().cancelByUniqueName(_task);
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// The background check: new unread notices since the last one shown.
  static Future<void> poll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final secret = prefs.getString(_kSecret);
    if (secret == null) return;
    lang = prefs.getString(_kLang) ?? 'ar';
    await initializeDateFormatting();
    final res = await http.post(Uri.parse('$sbUrl/rest/v1/rpc/device_notifications'),
        headers: {'apikey': sbKey, 'Content-Type': 'application/json'},
        body: jsonEncode({'p_secret': secret, 'p_since': prefs.getString(_kSince)}));
    if (res.statusCode != 200) return;
    final list = jsonDecode(res.body);
    if (list == null) {
      // The phone was signed out elsewhere or the account was stopped.
      await prefs.remove(_kSecret);
      await Workmanager().cancelByUniqueName(_task);
      return;
    }
    for (final n in list as List) {
      await show(Map<String, dynamic>.from(n as Map));
    }
  }
}
