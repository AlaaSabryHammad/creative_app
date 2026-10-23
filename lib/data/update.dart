import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/i18n.dart';
import '../core/theme.dart';

/// Forced update. The office sets a minimum build number (web app → Settings → Mobile app, stored behind
/// app_update_info() in the database). A build below it gets a blocking screen with the update link and nothing else
/// works until the app is updated. The answer is asked on start-up and every time the app comes back to the foreground,
/// and the last answer is remembered so an offline phone with an old build stays blocked. If the server cannot be
/// reached and nothing is remembered, the app is NOT blocked (an outage must not lock everybody out).
class Updater extends ChangeNotifier {
  Updater({Future<int> Function()? build, Future<Map<String, dynamic>?> Function()? fetch, TargetPlatform? platform})
      : _build = build ?? _installedBuild,
        _fetch = fetch ?? _fromServer,
        // ignore: prefer_initializing_formals
        _platform = platform;

  final Future<int> Function() _build;
  final Future<Map<String, dynamic>?> Function() _fetch;
  final TargetPlatform? _platform;

  bool required = false;
  String url = '';
  String message = '';

  static Future<int> _installedBuild() async => int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  static Future<Map<String, dynamic>?> _fromServer() async {
    final r = await Supabase.instance.client.rpc('app_update_info').timeout(const Duration(seconds: 5));
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<void> check() async {
    Map<String, dynamic>? info;
    SharedPreferences? prefs;
    try { prefs = await SharedPreferences.getInstance(); } catch (_) {}
    try {
      info = await _fetch();
      if (info != null && prefs != null) await prefs.setString('update.info', _encode(info));
    } catch (_) {
      final saved = prefs?.getString('update.info');  // offline: use the last answer
      info = saved == null ? null : _decode(saved);
    }
    final min = (info?['min_build'] as num?)?.toInt() ?? 0;
    final build = await _build();
    final ios = (_platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
    final now = min > 0 && build < min;
    final link = '${info?[ios ? 'url_ios' : 'url_android'] ?? ''}'.trim();
    final msg = '${info?['message'] ?? ''}'.trim();
    if (now != required || link != url || msg != message) {
      required = now; url = link; message = msg;
      notifyListeners();
    }
  }

  static String _encode(Map<String, dynamic> m) => '${m['min_build'] ?? 0}\u0001${m['url_android'] ?? ''}\u0001${m['url_ios'] ?? ''}\u0001${m['message'] ?? ''}';
  static Map<String, dynamic> _decode(String s) {
    final p = s.split('\u0001');
    String at(int i) => i < p.length ? p[i] : '';
    return {'min_build': int.tryParse(at(0)) ?? 0, 'url_android': at(1), 'url_ios': at(2), 'message': at(3)};
  }
}

final updater = Updater();

/// Wraps the whole app: while an update is required, it covers everything (dialogs included) and swallows the back button.
class UpdateGuard extends StatelessWidget {
  final Widget child;
  final Updater u;
  UpdateGuard({super.key, required this.child, Updater? updater}) : u = updater ?? _default;
  static final _default = updater;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: u,
        builder: (context, _) => PopScope(
          canPop: !u.required,
          child: Stack(children: [
            child,
            if (u.required) Positioned.fill(child: _UpdateScreen(u)),
          ]),
        ),
      );
}

class _UpdateScreen extends StatelessWidget {
  final Updater u;
  const _UpdateScreen(this.u);

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: lang == 'ar' || lang == 'ur' ? TextDirection.rtl : TextDirection.ltr,
        child: Material(
          color: C.slate50,
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Image.asset('assets/logo.png', height: 84),
                  const SizedBox(height: 26),
                  const Icon(Icons.system_update, size: 46, color: C.primary700),
                  const SizedBox(height: 14),
                  Text(tr('updTitle'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(u.message.isEmpty ? tr('updBody') : u.message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: C.fg2, height: 1.6)),
                  const SizedBox(height: 26),
                  if (u.url.isEmpty)
                    Text(tr('updNoLink'), textAlign: TextAlign.center, style: const TextStyle(color: C.danger))
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.download),
                        label: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(tr('updNow'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                        onPressed: () => launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      );
}
