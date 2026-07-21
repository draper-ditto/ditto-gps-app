import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/presence_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DittoGpsApp());
}

class DittoGpsApp extends StatelessWidget {
  const DittoGpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF090B0F);
    const surface = Color(0xFF11151C);
    const accent = Color(0xFF78F0C6);

    final baseTheme = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'Waypoint',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          secondary: Color(0xFF7AA8FF),
          surface: surface,
          error: Color(0xFFFF6B78),
        ),
        textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme).apply(
          bodyColor: const Color(0xFFE9EDF5),
          displayColor: const Color(0xFFF7F9FC),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0D1117),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          hintStyle: const TextStyle(color: Color(0xFF626B7A)),
          labelStyle: const TextStyle(color: Color(0xFF9BA5B5)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF252B35)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF252B35)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: accent, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFFF6B78)),
          ),
        ),
      ),
      home: const PresencePage(),
    );
  }
}

