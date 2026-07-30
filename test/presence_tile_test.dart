import 'package:ditto_gps/models/mesh_peer_status.dart';
import 'package:ditto_gps/models/user_presence.dart';
import 'package:ditto_gps/screens/presence_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final presence = UserPresence(
    id: 'device-12345678',
    username: 'Galaxy S20',
    latitude: 33.749,
    longitude: -84.388,
    status: 'Holding position',
    updatedAt: _updatedAt,
  );

  final fullyConnected = MeshPeerStatus(
    deviceId: presence.id,
    deviceName: 'DraperTAK-device-1',
    os: 'android',
    dittoSdkVersion: '5.0.2',
    connectedToDittoServer: true,
    connections: const {
      MeshConnectionKind.bluetooth,
      MeshConnectionKind.accessPoint,
      MeshConnectionKind.p2pWifi,
      MeshConnectionKind.webSocket,
    },
    connectivity: DeviceConnectivity(
      wifi: true,
      bluetooth: false,
      cellular: null,
      observedAt: DateTime.utc(2026, 7, 22, 16, 45),
    ),
  );

  testWidgets('collapsed row shows last status, GPS, and live route', (
    tester,
  ) async {
    await _pumpTile(tester, presence: presence, status: fullyConnected);

    expect(find.text('Galaxy S20'), findsOneWidget);
    expect(find.text('Holding position'), findsOneWidget);
    expect(find.text('33.749000, -84.388000'), findsOneWidget);
    expect(find.text('BIG PEER + MESH'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('connection-status-dot'))),
      const Size(12, 12),
    );
    final nameRight = tester.getTopRight(find.text('Galaxy S20')).dx;
    final badgeLeft = tester
        .getTopLeft(find.byKey(const ValueKey('overview-connection-badge')))
        .dx;
    expect(badgeLeft - nameRight, closeTo(8, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('online expansion shows all saved and live peer data', (
    tester,
  ) async {
    await _pumpTile(tester, presence: presence, status: fullyConnected);
    await _expand(tester);

    expect(find.text('CURRENT CONNECTION'), findsOneWidget);
    expect(find.text('NETWORK AVAILABILITY'), findsOneWidget);
    expect(find.text('DITTO SYNC TRANSPORTS'), findsOneWidget);
    expect(find.text('LAST KNOWN WAYPOINT'), findsOneWidget);
    expect(find.text('DEVICE'), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.text('LOCATION'), findsOneWidget);
    expect(find.text('UPDATED'), findsOneWidget);
    expect(find.text('OBSERVED'), findsOneWidget);
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('OS'), findsOneWidget);
    expect(find.text('DITTO SDK'), findsOneWidget);
    expect(find.text('DEVICE ID'), findsOneWidget);
    expect(find.text('Wi-Fi ON'), findsOneWidget);
    expect(find.text('Bluetooth OFF'), findsOneWidget);
    expect(find.text('Cellular UNKNOWN'), findsOneWidget);
    expect(find.text('Big Peer ON'), findsOneWidget);
    expect(find.text('Bluetooth mesh ON'), findsOneWidget);
    expect(find.text('LAN mesh ON'), findsOneWidget);
    expect(find.text('P2P Wi-Fi ON'), findsOneWidget);
    expect(find.text('Peer WebSocket ON'), findsOneWidget);
    expect(find.text('DraperTAK-device-1'), findsOneWidget);
    expect(find.text('android'), findsOneWidget);
    expect(find.text('5.0.2'), findsOneWidget);
    expect(find.text('DEVICE CONNECTIVITY'), findsNothing);
    expect(find.text('DITTO SYNC PATH'), findsNothing);
    expect(
      find.text(
        'The status and GPS location below are the last values synced by this device.',
      ),
      findsNothing,
    );
    expect(
      tester.getTopLeft(find.text('CURRENT CONNECTION')).dy,
      lessThan(tester.getTopLeft(find.text('NETWORK AVAILABILITY')).dy),
    );
    expect(
      tester.getTopLeft(find.text('NETWORK AVAILABILITY')).dy,
      lessThan(tester.getTopLeft(find.text('DITTO SYNC TRANSPORTS')).dy),
    );
    expect(
      tester.getTopLeft(find.text('DITTO SYNC TRANSPORTS')).dy,
      lessThan(tester.getTopLeft(find.text('LAST KNOWN WAYPOINT')).dy),
    );
    expect(
      tester.getTopLeft(find.text('LAST KNOWN WAYPOINT')).dy,
      lessThan(tester.getTopLeft(find.text('DEVICE')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline expansion keeps saved data and shows disconnected', (
    tester,
  ) async {
    await _pumpTile(tester, presence: presence);

    expect(find.text('33.749000, -84.388000'), findsOneWidget);
    expect(find.text('NOT CONNECTED'), findsOneWidget);
    await _expand(tester);

    expect(find.text('Holding position'), findsNWidgets(2));
    expect(find.text('33.749000, -84.388000'), findsNWidgets(2));
    expect(find.text('CURRENT CONNECTION'), findsOneWidget);
    expect(
      find.text('This device is not currently connected.'),
      findsOneWidget,
    );
    expect(find.text('LAST KNOWN WAYPOINT'), findsOneWidget);
    expect(find.text('DEVICE'), findsOneWidget);
    expect(find.text('NETWORK AVAILABILITY'), findsNothing);
    expect(find.text('DITTO SYNC TRANSPORTS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blank status has an explicit fallback in both row states', (
    tester,
  ) async {
    final blankStatus = UserPresence(
      id: 'device-empty-status',
      username: 'Offline tablet',
      latitude: 0,
      longitude: 0,
      status: '   ',
      updatedAt: _updatedAt,
    );
    await _pumpTile(tester, presence: blankStatus);

    expect(find.text('No status reported'), findsOneWidget);
    expect(find.text('0.000000, 0.000000'), findsOneWidget);
    expect(find.text('NOT CONNECTED'), findsOneWidget);
    await _expand(tester);

    expect(find.text('No status reported'), findsNWidgets(2));
    expect(find.text('0.000000, 0.000000'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen and long values expand without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final longPresence = UserPresence(
      id: 'device-with-a-very-long-identifier-that-must-remain-selectable',
      username: 'A very long field-device display name for a narrow phone',
      latitude: -89.999999,
      longitude: 179.999999,
      status:
          'A long last-known status that should truncate in the overview but remain available in the expanded details.',
      updatedAt: _updatedAt,
    );
    await _pumpTile(tester, presence: longPresence);
    await _expand(tester);

    expect(find.byType(SelectableText), findsNWidgets(4));
    expect(
      find.text(
        'A long last-known status that should truncate in the overview but remain available in the expanded details.',
      ),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded live row can become offline without an exception', (
    tester,
  ) async {
    final status = ValueNotifier<MeshPeerStatus?>(fullyConnected);
    addTearDown(status.dispose);
    await tester.pumpWidget(
      _TileHarness(
        child: ValueListenableBuilder<MeshPeerStatus?>(
          valueListenable: status,
          builder: (_, value, __) => buildPresenceTileForTesting(
            person: presence,
            meshStatus: value,
          ),
        ),
      ),
    );
    await _expand(tester);
    expect(find.text('NETWORK AVAILABILITY'), findsOneWidget);

    status.value = null;
    await tester.pumpAndSettle();

    expect(find.text('CURRENT CONNECTION'), findsOneWidget);
    expect(
      find.text('This device is not currently connected.'),
      findsOneWidget,
    );
    expect(find.text('Holding position'), findsNWidgets(2));
    expect(find.text('33.749000, -84.388000'), findsNWidgets(2));
    expect(find.text('NETWORK AVAILABILITY'), findsNothing);
    expect(find.text('DITTO SYNC TRANSPORTS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a waypoint requires confirmation and explains rejoin', (
    tester,
  ) async {
    var removalCalls = 0;
    UserPresence? removedPresence;
    await _pumpTile(
      tester,
      presence: presence,
      status: fullyConnected,
      onRemove: (person) async {
        removalCalls += 1;
        removedPresence = person;
      },
    );
    await _expand(tester);

    expect(find.text('REMOVE FROM LIVE MESH'), findsOneWidget);
    final removeButton = find.byKey(
      const ValueKey('remove-presence-device-12345678'),
    );
    await tester.ensureVisible(removeButton);
    await tester.pumpAndSettle();
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    expect(
      find.text('Remove Galaxy S20 from Live Mesh?'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
          'will hide the waypoint on every connected mesh device'),
      findsOneWidget,
    );
    expect(
      find.textContaining('can rejoin by saving its status or location again'),
      findsOneWidget,
    );

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(removalCalls, 0);

    await tester.ensureVisible(removeButton);
    await tester.pumpAndSettle();
    await tester.tap(removeButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-remove-presence')));
    await tester.pumpAndSettle();

    expect(removalCalls, 1);
    expect(removedPresence, same(presence));
    expect(
      find.text(
        'Galaxy S20 removed. The change is syncing across the mesh.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('removal button is disabled while that waypoint is removing', (
    tester,
  ) async {
    await _pumpTile(
      tester,
      presence: presence,
      onRemove: (_) async {},
      isRemoving: true,
    );
    await tester.tap(find.byType(ExpansionTile));
    await tester.pump(const Duration(seconds: 1));

    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('remove-presence-device-12345678')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('REMOVING…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removal remains visible but disabled while sync is unavailable',
      (
    tester,
  ) async {
    await _pumpTile(
      tester,
      presence: presence,
      onRemove: (_) async {},
      canRemove: false,
    );
    await _expand(tester);

    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('remove-presence-device-12345678')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('REMOVE FROM LIVE MESH'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route summaries distinguish server, mesh, and no link', (
    tester,
  ) async {
    for (final scenario in <(MeshPeerStatus, String)>[
      (_status(server: true), 'BIG PEER'),
      (
        _status(connections: const {MeshConnectionKind.bluetooth}),
        'MESH ONLY',
      ),
      (_status(), 'NO ACTIVE LINK'),
    ]) {
      await _pumpTile(tester, presence: presence, status: scenario.$1);
      expect(find.text('33.749000, -84.388000'), findsOneWidget);
      expect(find.text(scenario.$2), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

final DateTime _updatedAt = DateTime.utc(2026, 7, 22, 16, 30);

MeshPeerStatus _status({
  bool server = false,
  Set<MeshConnectionKind> connections = const {},
}) =>
    MeshPeerStatus(
      deviceId: 'device-12345678',
      deviceName: 'DraperTAK-device-1',
      os: 'web',
      dittoSdkVersion: '5.0.2',
      connectedToDittoServer: server,
      connections: connections,
      connectivity: const DeviceConnectivity.unknown(),
    );

Future<void> _pumpTile(
  WidgetTester tester, {
  required UserPresence presence,
  MeshPeerStatus? status,
  Future<void> Function(UserPresence person)? onRemove,
  bool canRemove = true,
  bool isRemoving = false,
}) async {
  await tester.pumpWidget(
    _TileHarness(
      child: buildPresenceTileForTesting(
        person: presence,
        meshStatus: status,
        onRemove: onRemove,
        canRemove: canRemove,
        isRemoving: isRemoving,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.byType(ExpansionTile));
  await tester.pumpAndSettle();
}

class _TileHarness extends StatelessWidget {
  const _TileHarness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    );
  }
}
