import 'package:ditto_gps/screens/presence_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inline error is selectable, copyable, and retryable', (
    tester,
  ) async {
    const error = 'Location permission was denied.\nDetailed diagnostics.';
    String? copiedText;
    var retries = 0;
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildErrorBannerForTesting(
            message: error,
            onRetry: () => retries += 1,
          ),
        ),
      ),
    );

    expect(find.byType(SelectableText), findsOneWidget);
    await tester.tap(find.text('Copy error'));
    await tester.pump();
    expect(copiedText, error);
    expect(find.text('Error copied to clipboard.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('location error can open settings from the inline guidance', (
    tester,
  ) async {
    var settingsOpens = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildErrorBannerForTesting(
            message: 'Turn on location services.',
            onRetry: () {},
            secondaryActionLabel: 'Location settings',
            onSecondaryAction: () => settingsOpens += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Location settings'));
    expect(settingsOpens, 1);
  });

  testWidgets('disabled location dialog provides an open settings action', (
    tester,
  ) async {
    var opens = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildLocationServicesDialogForTesting(
            instructions: 'Turn on Location and Wi-Fi.',
            canOpenSettings: true,
            onClose: () {},
            onOpenSettings: () => opens += 1,
          ),
        ),
      ),
    );

    expect(find.text('Turn on location services'), findsOneWidget);
    expect(find.text('Turn on Location and Wi-Fi.'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    expect(opens, 1);
  });

  testWidgets('web location dialog hides unsupported direct settings action', (
    tester,
  ) async {
    var closes = 0;
    var opens = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildLocationServicesDialogForTesting(
            instructions: 'Update your browser site settings.',
            canOpenSettings: false,
            onClose: () => closes += 1,
            onOpenSettings: () => opens += 1,
          ),
        ),
      ),
    );

    expect(find.text('Open settings'), findsNothing);
    expect(find.text('OK'), findsOneWidget);
    await tester.tap(find.text('OK'));
    expect(closes, 1);
    expect(opens, 0);
  });
}
