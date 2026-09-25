import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens mirrored from the web app (src/styles/tokens.css).
class C {
  static const primary = Color(0xFF2563EB);
  static const primary700 = Color(0xFF1D4ED8);
  static const primary50 = Color(0xFFEFF6FF);
  static const primary100 = Color(0xFFDBEAFE);
  static const pink = Color(0xFFFF3D7F);
  static const success = Color(0xFF10B981);
  static const success800 = Color(0xFF065F46);
  static const success50 = Color(0xFFECFDF5);
  static const warning = Color(0xFFEA580C);
  static const warning800 = Color(0xFF9A3412);
  static const warning50 = Color(0xFFFFF7ED);
  static const danger = Color(0xFFDC2626);
  static const danger800 = Color(0xFF991B1B);
  static const danger50 = Color(0xFFFEF2F2);
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate400 = Color(0xFF94A3B8);
  static const fg1 = Color(0xFF0F172A);
  static const fg2 = Color(0xFF334155);
  static const fg3 = Color(0xFF64748B);
  // Landing/login palette
  static const ink = Color(0xFF0F2240);
  static const navy = Color(0xFF15325C);
  static const gold = Color(0xFFB98A3E);
  static const goldLight = Color(0xFFF3E7CF);
  static const cream = Color(0xFFFBFAF7);

  static const brandGradient = LinearGradient(colors: [primary, pink]);
  static const primaryGradient = LinearGradient(colors: [primary, primary700]);
}

enum Tone { blue, green, orange, red, slate }

extension ToneColors on Tone {
  Color get fg => switch (this) {
        Tone.blue => C.primary700,
        Tone.green => C.success800,
        Tone.orange => C.warning800,
        Tone.red => C.danger800,
        Tone.slate => C.fg3,
      };
  Color get bg => switch (this) {
        Tone.blue => C.primary50,
        Tone.green => C.success50,
        Tone.orange => C.warning50,
        Tone.red => C.danger50,
        Tone.slate => C.slate100,
      };
  Color get solid => switch (this) {
        Tone.blue => C.primary,
        Tone.green => C.success,
        Tone.orange => C.warning,
        Tone.red => C.danger,
        Tone.slate => C.slate400,
      };
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.primary, primary: C.primary, surface: Colors.white),
    scaffoldBackgroundColor: C.slate50,
  );
  final text = GoogleFonts.tajawalTextTheme(base.textTheme).apply(bodyColor: C.fg1, displayColor: C.fg1);
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      foregroundColor: C.fg1,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.tajawal(fontSize: 19, fontWeight: FontWeight.w800, color: C.fg1),
      shape: const Border(bottom: BorderSide(color: C.slate100)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.slate200)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.slate200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.primary, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.primary,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.tajawal(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.fg1,
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: C.slate200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, contentTextStyle: GoogleFonts.tajawal(fontSize: 14)),
  );
}
