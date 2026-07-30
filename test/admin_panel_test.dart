import 'package:ditto_gps/screens/admin_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('admin panel shows database and worker controls', (tester) async {
    await _pumpAdmin(tester);

    expect(find.text('ADMIN CONTROLS'), findsOneWidget);
    expect(find.text('Application version'), findsOneWidget);
    expect(find.text('v0.19.0 · build 22'), findsOneWidget);
    expect(find.byKey(const ValueKey('application-version')), findsOneWidget);
    expect(find.text('Ditto demo database'), findsOneWidget);
    expect(find.text('Clear and reset database'), findsOneWidget);
    expect(find.text('Cloudflare Worker #1'), findsOneWidget);
    expect(find.text('Cloudflare Worker #2'), findsOneWidget);
    expect(find.text('Launch'), findsNWidgets(2));
    expect(find.byIcon(Icons.info_outline_rounded), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('database reset requires confirmation and can be cancelled', (
    tester,
  ) async {
    var resetCalls = 0;
    await _pumpAdmin(
      tester,
      onReset: () async {
        resetCalls += 1;
        return 2;
      },
    );

    await tester.tap(find.byKey(const ValueKey('reset-database-button')));
    await tester.pumpAndSettle();
    expect(find.text('Reset the Ditto database?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(resetCalls, 0);
    expect(find.text('Reset the Ditto database?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed reset invokes callback and reports deleted count', (
    tester,
  ) async {
    var resetCalls = 0;
    await _pumpAdmin(
      tester,
      onReset: () async {
        resetCalls += 1;
        return 3;
      },
    );

    await tester.tap(find.byKey(const ValueKey('reset-database-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-reset-database-button')),
    );
    await tester.pumpAndSettle();

    expect(resetCalls, 1);
    expect(
      find.text('Ditto demo database reset. 3 waypoints deleted.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker information explains the future headless agent', (
    tester,
  ) async {
    await _pumpAdmin(tester);

    await tester.tap(
      find.byKey(const ValueKey('info-Cloudflare Worker #1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cloudflare Worker #1'), findsNWidgets(2));
    expect(
      find.text(
        'In the future, this button will launch a headless Ditto agent that automatically fills in data and provides updates.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin controls fit a narrow mobile screen', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAdmin(tester);
    expect(find.text('Clear and reset database'), findsOneWidget);
    expect(find.text('Cloudflare Worker #2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset is disabled until Ditto is ready', (tester) async {
    await _pumpAdmin(tester, canReset: false);

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('reset-database-button')),
    );
    expect(button.onPressed, isNull);
  });
}

Future<void> _pumpAdmin(
  WidgetTester tester, {
  bool canReset = true,
  Future<int> Function()? onReset,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: AdminPanel(
            recordCount: 2,
            canResetDatabase: canReset,
            isResettingDatabase: false,
            onResetDatabase: onReset ?? () async => 2,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
