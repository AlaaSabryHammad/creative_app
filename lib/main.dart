import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme.dart';
import 'data/store.dart';
import 'ui/login.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await Supabase.initialize(url: sbUrl, publishableKey: sbKey);
  runApp(const CreativeApp());
}

class CreativeApp extends StatelessWidget {
  const CreativeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'CREATIVE',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: const _Gate(),
      );
}

/// Restores the session, then shows login or the app.
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
    return ListenableBuilder(listenable: store, builder: (c, _) => store.signedIn ? const Shell() : LoginScreen(notice: _notice));
  }
}
