import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/presence_page.dart';

final appError = ValueNotifier<String?>(null);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _reportError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _reportError(error, stack);
    return true;
  };
  runApp(const DittoGpsApp());
}

void _reportError(Object error, StackTrace? stack) {
  final message = _formatError(error, stack);
  void publish() {
    if (appError.value != message) appError.value = message;
  }

  final scheduler = SchedulerBinding.instance;
  if (scheduler.schedulerPhase == SchedulerPhase.idle) {
    publish();
    return;
  }
  scheduler.addPostFrameCallback((_) => publish());
  scheduler.scheduleFrame();
}

@visibleForTesting
void reportAppErrorForTesting(Object error, [StackTrace? stack]) {
  _reportError(error, stack);
}

@visibleForTesting
Widget buildAppErrorReportForTesting(String error) {
  return _GlobalErrorReport(error: error);
}

String _formatError(Object error, StackTrace? stack) {
  final details = StringBuffer(error);
  if (stack != null) {
    details
      ..writeln()
      ..writeln(stack);
  }
  return details.toString().trim();
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
      title: 'Draper TAK',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          child ?? const SizedBox.shrink(),
          ValueListenableBuilder<String?>(
            valueListenable: appError,
            builder: (context, error, _) {
              if (error == null) return const SizedBox.shrink();
              return _GlobalErrorReport(error: error);
            },
          ),
        ],
      ),
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

class _GlobalErrorReport extends StatelessWidget {
  const _GlobalErrorReport({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: SafeArea(
        top: false,
        child: Material(
          color: const Color(0xFF35151B),
          elevation: 12,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'APPLICATION ERROR',
                    style: TextStyle(
                      color: Color(0xFFFF7A86),
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        error,
                        style: const TextStyle(
                          color: Color(0xFFFFD5DA),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: error));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Error copied to clipboard.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy error'),
                      ),
                      TextButton(
                        onPressed: () => appError.value = null,
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
