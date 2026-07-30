import 'package:ditto_gps/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appError.value = null);
  tearDown(() => appError.value = null);

  testWidgets('error report is selectable, copyable, and dismissible', (
    tester,
  ) async {
    const error = 'Example failure\n#0 Example.stack';
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    appError.value = error;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(children: [buildAppErrorReportForTesting(error)]),
        ),
      ),
    );

    expect(find.text('APPLICATION ERROR'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);

    await tester.tap(find.text('Copy error'));
    await tester.pump();
    expect(copiedText, error);
    expect(find.text('Error copied to clipboard.'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(appError.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reporting an error during build defers notifier publication', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<String?>(
          valueListenable: appError,
          builder: (_, __, ___) => const _ReportErrorDuringBuild(),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(appError.value, contains('build-time failure'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reported stack trace is retained for copying', (tester) async {
    final stack = StackTrace.fromString('#0 importantCall (app.dart:42)');

    reportAppErrorForTesting(StateError('broken'), stack);

    expect(appError.value, contains('Bad state: broken'));
    expect(appError.value, contains('importantCall'));
  });
}

class _ReportErrorDuringBuild extends StatelessWidget {
  const _ReportErrorDuringBuild();

  @override
  Widget build(BuildContext context) {
    reportAppErrorForTesting(StateError('build-time failure'));
    return const SizedBox.shrink();
  }
}
