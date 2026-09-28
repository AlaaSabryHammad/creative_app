import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/i18n.dart';
import 'core/theme.dart';
import 'data/store.dart';
import 'ui/login.dart';
import 'ui/shell.dart';
import 'ui/worker/worker_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();  // every locale: the worker app speaks several languages
  await Supabase.initialize(url: sbUrl, publishableKey: sbKey);
  runApp(const CreativeApp());
}

class CreativeApp extends StatelessWidget {
  const CreativeApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          // Staff use Arabic; a worker account uses its chosen language (or one matching its nationality).
          lang = store.isWorker ? (store.lang ?? defaultLang(store.myWorker)) : 'ar';
          return MaterialApp(
            title: 'CREATIVE',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            locale: Locale(lang),
            supportedLocales: [for (final l in workerLangs.keys) Locale(l)],
            localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
            home: const _Gate(),
          );
        },
      );
}

/// Restores the session, then shows login, the staff app, or the worker app.
class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool _ready = false;
  String? _notice;
  @override
  void initState() {
    super.initState();
    store.restore().then((err) { if (mounted) setState(() { _ready = true; _notice = err; }); });
  }
  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(backgroundColor: C.slate50, body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Image.asset('assets/logo.png', height: 90), const SizedBox(height: 18), const CircularProgressIndicator()])));
    }
    return ListenableBuilder(
      listenable: store,
      builder: (c, _) => !store.signedIn ? LoginScreen(notice: _notice) : store.isWorker ? const WorkerShell() : const Shell(),
    );
  }
}
