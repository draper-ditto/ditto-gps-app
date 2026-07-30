import 'package:ditto_gps/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';

void main() {
  testWidgets('Draper TAK app starts', (tester) async {
    await tester.pumpWidget(const DittoGpsApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Observability'), findsOneWidget);
    expect(find.byIcon(Icons.monitor_heart_outlined), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const ValueKey('home-tab'))).dx,
      lessThan(
        tester.getCenter(find.byKey(const ValueKey('observability-tab'))).dx,
      ),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('observability-tab'))).dx,
      lessThan(tester.getCenter(find.byKey(const ValueKey('admin-tab'))).dx),
    );
  });

  testWidgets('Home, Observability, and Admin switch visible experiences', (
    tester,
  ) async {
    await tester.pumpWidget(const DittoGpsApp());

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('MESH TOPOLOGY'), findsNothing);
    expect(find.text('ADMIN CONTROLS'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('observability-tab')));
    await tester.pump();
    expect(find.text('MESH TOPOLOGY'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-mesh-topology-graph')),
      findsOneWidget,
    );
    expect(find.text('MESH DEVICE LIST'), findsNothing);
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('ADMIN CONTROLS'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('admin-tab')));
    await tester.pump();
    expect(find.text('ADMIN CONTROLS'), findsOneWidget);
    expect(find.text('MESH TOPOLOGY'), findsNothing);
    expect(find.byType(FlutterMap), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-tab')));
    await tester.pump();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('ADMIN CONTROLS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('three navigation tabs fit a 320 pixel viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DittoGpsApp());

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Observability'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('observability-tab')));
    await tester.pump();
    expect(find.text('MESH TOPOLOGY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status field accepts editable text without selection conflicts',
      (
    tester,
  ) async {
    await tester.pumpWidget(const DittoGpsApp());
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -650),
    );
    await tester.pump();

    final statusField = find.byKey(const ValueKey('status-field'));
    expect(statusField, findsOneWidget);
    await tester.enterText(statusField, 'Copied field status');
    await tester.pump();

    expect(find.text('Copied field status'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
