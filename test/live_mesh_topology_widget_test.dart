import 'dart:math' as math;

import 'package:ditto_gps/models/mesh_peer_status.dart';
import 'package:ditto_gps/models/mesh_topology.dart';
import 'package:ditto_gps/models/user_presence.dart';
import 'package:ditto_gps/screens/live_mesh_topology.dart';
import 'package:ditto_gps/screens/presence_page.dart';
import 'package:ditto_gps/services/presence_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('authenticated header shows status without a device count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: buildHeaderForTesting(state: SyncState.connected),
        ),
      ),
    );

    final status = find.byKey(const ValueKey('header-device-status'));
    expect(status, findsOneWidget);
    final statusText = find.descendant(of: status, matching: find.byType(Text));
    expect(statusText, findsOneWidget);
    expect(tester.widget<Text>(statusText).data, 'AUTHENTICATED');
  });

  test('edge labels use the exact midpoint of the visible connection line', () {
    final center = topologyEdgeLabelCenterForTesting(
      start: const Offset(100, 0),
      end: const Offset(100, 100),
    );

    expect(center, const Offset(100, 50));
  });

  test('connection lines stop at node boundaries', () {
    final segment = topologyVisibleEdgeSegmentForTesting(
      from: const Rect.fromLTWH(0, 0, 100, 100),
      to: const Rect.fromLTWH(200, 0, 100, 100),
    );

    expect(segment.start, const Offset(100, 50));
    expect(segment.end, const Offset(200, 50));
    expect(
      topologyEdgeLabelCenterForTesting(
        start: segment.start,
        end: segment.end,
      ),
      const Offset(150, 50),
    );
  });

  test('responsive topology nodes stay within readable width bounds', () {
    const nodes = [
      MeshTopologyNode(id: 'one', label: 'One'),
      MeshTopologyNode(id: 'two', label: 'Two'),
      MeshTopologyNode(id: 'three', label: 'Three'),
    ];

    for (final width in [500.0, 760.0, 1200.0]) {
      final layout = topologyNodePositionsForTesting(
        nodes: nodes,
        edges: const [],
        width: width,
      );
      for (final node in nodes) {
        expect(layout.positions[node.id]!.width, greaterThanOrEqualTo(190));
        expect(layout.positions[node.id]!.width, lessThanOrEqualTo(280));
      }
    }
  });

  test('orthogonal routes avoid unrelated nodes and do not share line lanes',
      () {
    const positions = {
      'a': Rect.fromLTWH(20, 140, 200, 142),
      'b': Rect.fromLTWH(300, 140, 200, 142),
      'c': Rect.fromLTWH(580, 140, 200, 142),
      'd': Rect.fromLTWH(300, 380, 200, 142),
    };
    const edges = [
      MeshTopologyEdge(
        id: 'a-b',
        fromId: 'a',
        toId: 'b',
        kind: MeshConnectionKind.bluetooth,
      ),
      MeshTopologyEdge(
        id: 'a-c',
        fromId: 'a',
        toId: 'c',
        kind: MeshConnectionKind.accessPoint,
      ),
      MeshTopologyEdge(
        id: 'a-d',
        fromId: 'a',
        toId: 'd',
        kind: MeshConnectionKind.p2pWifi,
      ),
      MeshTopologyEdge(
        id: 'c-d',
        fromId: 'c',
        toId: 'd',
        kind: MeshConnectionKind.webSocket,
      ),
    ];
    final routes = topologyOrthogonalRoutesForTesting(
      edges: edges,
      positions: positions,
      canvasSize: const Size(800, 600),
    );

    expect(routes, hasLength(edges.length));
    for (final route in routes) {
      for (var index = 0; index < route.points.length - 1; index++) {
        final start = route.points[index];
        final end = route.points[index + 1];
        expect(start.dx == end.dx || start.dy == end.dy, isTrue);
        for (final entry in positions.entries) {
          if (entry.key == route.edge.fromId || entry.key == route.edge.toId) {
            continue;
          }
          expect(
            _segmentIntersectsRect(start, end, entry.value),
            isFalse,
            reason: '${route.edge.id} crosses node ${entry.key}',
          );
        }
      }
    }
    for (var first = 0; first < routes.length; first++) {
      for (var second = first + 1; second < routes.length; second++) {
        expect(
          _sharedLaneLength(routes[first].points, routes[second].points),
          0,
          reason: '${routes[first].edge.id} overlaps ${routes[second].edge.id}',
        );
      }
    }
  });

  test('path labels use the midpoint of the full orthogonal route', () {
    final midpoint = topologyPathMidpointForTesting(const [
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, 40),
    ]);

    expect(midpoint, const Offset(70, 0));
  });

  test('reconnecting labels preserve every transport protocol name', () {
    for (final expectation in {
      MeshConnectionKind.bluetooth: 'BLE · RECONNECTING',
      MeshConnectionKind.accessPoint: 'LAN · RECONNECTING',
      MeshConnectionKind.p2pWifi: 'P2P · RECONNECTING',
      MeshConnectionKind.webSocket: 'WS · RECONNECTING',
    }.entries) {
      expect(
        topologyEdgeLabelForTesting(
          MeshTopologyEdge(
            id: expectation.key.name,
            fromId: 'one',
            toId: 'two',
            kind: expectation.key,
            isReconnecting: true,
          ),
        ),
        expectation.value,
      );
    }
    expect(
      topologyEdgeLabelForTesting(
        const MeshTopologyEdge(
          id: 'cloud',
          fromId: bigPeerTopologyNodeId,
          toId: 'one',
          isBigPeer: true,
          isReconnecting: true,
        ),
      ),
      'CLOUD · RECONNECTING',
    );
  });

  test('reconnecting paths are split into visible dashes and gaps', () {
    final segments = topologyDashedSegmentsForTesting(
      const [Offset(0, 0), Offset(30, 0)],
      dashLength: 6,
      gapLength: 4,
    );

    expect(segments, hasLength(3));
    expect(segments.first, (start: Offset.zero, end: const Offset(6, 0)));
    expect(segments[1].start, const Offset(10, 0));
    expect(segments[1].end, const Offset(16, 0));
    expect(segments.last.start, const Offset(20, 0));
    expect(segments.last.end, const Offset(26, 0));
  });

  test('center transform maps the selected node to the viewport center', () {
    final transform = topologyCenterTransformForTesting(
      viewportSize: const Size(600, 400),
      nodeRect: const Rect.fromLTWH(700, 500, 200, 100),
      scale: 1,
    );

    final transformed = MatrixUtils.transformPoint(
      transform,
      const Offset(800, 550),
    );
    expect(transformed.dx, closeTo(300, .001));
    expect(transformed.dy, closeTo(200, .001));
  });

  testWidgets('device list and observability topology are separate sections',
      (tester) async {
    await tester.pumpWidget(_app(statuses: _connectedStatuses));

    expect(find.text('MESH DEVICE LIST'), findsOneWidget);
    expect(find.text('2 DEVICES'), findsOneWidget);
    expect(find.byKey(const ValueKey('presence-fire')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-mesh-topology-graph')),
      findsNothing,
    );

    await tester.pumpWidget(_topologyApp(statuses: _connectedStatuses));
    await tester.pump();

    expect(find.text('MESH TOPOLOGY'), findsOneWidget);
    expect(find.text('3 NODES · 2 CONNECTIONS'), findsOneWidget);
    final topologyTitleRect = tester.getRect(find.text('MESH TOPOLOGY'));
    final topologyCountsRect = tester.getRect(
      find.byKey(const ValueKey('topology-counts')),
    );
    expect(topologyCountsRect.left - topologyTitleRect.right, closeTo(8, .01));
    expect(
        topologyCountsRect.center.dy, closeTo(topologyTitleRect.center.dy, 1));
    expect(find.byKey(const ValueKey('presence-fire')), findsNothing);
    expect(
        find.byKey(const ValueKey('live-mesh-topology-graph')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('topology-big-peer-node')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topology-last-updated')),
      findsOneWidget,
    );
    expect(find.text('Last updated —'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Legend'), findsOneWidget);
    expect(find.text('Reconnecting'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('legend-marker-reconnecting')),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Visualize real time connectivity updates to your Ditto mesh topology.',
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('topology-guide-card'))).dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('live-mesh-topology-graph')),
            )
            .dy,
      ),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('legend-marker-Bluetooth')),
      ),
      const Size(14, 14),
    );
    final legendMarker = tester.widget<Container>(
      find.byKey(const ValueKey('legend-marker-Bluetooth')),
    );
    expect(
      (legendMarker.decoration! as BoxDecoration).boxShadow,
      isNull,
    );
    expect(tester.widget<Text>(find.text('Bluetooth')).style!.fontSize, 12);
    expect(find.text('Fire tablet status'), findsOneWidget);
    expect(find.text('Galaxy S20 status'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topology-route-fire')),
      findsOneWidget,
    );
    final bigPeerRect = tester.getRect(
      find.byKey(const ValueKey('topology-big-peer-node')),
    );
    final fireRect = tester.getRect(
      find.byKey(const ValueKey('topology-device-fire')),
    );
    final galaxyRect = tester.getRect(
      find.byKey(const ValueKey('topology-device-galaxy')),
    );
    expect(fireRect.top - bigPeerRect.bottom, greaterThanOrEqualTo(64));
    expect(galaxyRect.left - fireRect.right, greaterThanOrEqualTo(64));
  });

  testWidgets('topology graph shows the latest update time', (tester) async {
    final updatedAt = DateTime(2026, 7, 23, 14, 5, 9);
    await tester.pumpWidget(
      _topologyApp(
        statuses: _connectedStatuses,
        lastUpdated: updatedAt,
      ),
    );

    expect(find.text('Last updated 2:05:09 PM'), findsOneWidget);
    final badgeRect = tester.getRect(
      find.byKey(const ValueKey('topology-last-updated')),
    );
    final graphRect = tester.getRect(
      find.byKey(const ValueKey('live-mesh-topology-graph')),
    );
    expect(badgeRect.left, graphRect.left);
    expect(badgeRect.bottom, lessThan(graphRect.top));
  });

  testWidgets('topology timestamp advances without disturbing graph nodes',
      (tester) async {
    await tester.pumpWidget(
      _topologyApp(
        statuses: _connectedStatuses,
        lastUpdated: DateTime(2026, 7, 23, 14, 5, 9),
      ),
    );
    final fireBefore = tester.getRect(
      find.byKey(const ValueKey('topology-device-fire')),
    );

    await tester.pumpWidget(
      _topologyApp(
        statuses: _connectedStatuses,
        lastUpdated: DateTime(2026, 7, 23, 14, 5, 10),
      ),
    );
    await tester.pump();

    expect(find.text('Last updated 2:05:09 PM'), findsNothing);
    expect(find.text('Last updated 2:05:10 PM'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('topology-device-fire'))),
      fireBefore,
    );
  });

  testWidgets('last updated badge stays outside the graph on mobile',
      (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _topologyApp(
        statuses: _connectedStatuses,
        lastUpdated: DateTime(2026, 7, 23, 14, 5, 9),
      ),
    );

    final graphRect = tester.getRect(
      find.byKey(const ValueKey('live-mesh-topology-graph')),
    );
    final badgeRect = tester.getRect(
      find.byKey(const ValueKey('topology-last-updated')),
    );
    expect(badgeRect.left, graphRect.left);
    expect(badgeRect.right, lessThanOrEqualTo(graphRect.right));
    expect(badgeRect.bottom, lessThan(graphRect.top));
    expect(badgeRect.overlaps(graphRect), isFalse);
  });

  test('last updated formatter handles midnight and noon', () {
    expect(
      formatTopologyLastUpdated(DateTime(2026, 7, 23)),
      'Last updated 12:00:00 AM',
    );
    expect(
      formatTopologyLastUpdated(DateTime(2026, 7, 23, 12)),
      'Last updated 12:00:00 PM',
    );
  });

  testWidgets('Fire tablet remains visible and becomes red when it drops off',
      (tester) async {
    await tester.pumpWidget(_topologyApp(statuses: _connectedStatuses));
    await tester.pump();
    expect(find.text('MESH ONLY'), findsOneWidget);

    await tester.pumpWidget(_topologyApp(statuses: {
      'galaxy': _connectedStatuses['galaxy']!,
    }));
    await tester.pump();

    expect(find.text('4 NODES · 2 CONNECTIONS'), findsOneWidget);
    expect(find.byKey(const ValueKey('topology-device-fire')), findsOneWidget);
    expect(find.text('NOT CONNECTED'), findsOneWidget);
    final route = tester.widget<Text>(
      find.byKey(const ValueKey('topology-route-fire')),
    );
    expect(route.style!.color, const Color(0xFFFF7A86));
    expect(
      find.byKey(const ValueKey('topology-disconnected-section')),
      findsOneWidget,
    );
    final fireRect = tester.getRect(
      find.byKey(const ValueKey('topology-device-fire')),
    );
    final galaxyRect = tester.getRect(
      find.byKey(const ValueKey('topology-device-galaxy')),
    );
    expect(fireRect.top, greaterThan(galaxyRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a node centers and shows its connection details',
      (tester) async {
    await tester.pumpWidget(_topologyApp(statuses: _connectedStatuses));
    await tester.pump();

    final galaxyNode = find.byKey(const ValueKey('topology-device-galaxy'));
    await tester.ensureVisible(galaxyNode);
    await tester.pump();
    await tester.tap(galaxyNode);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('topology-selected-details-galaxy')),
      findsOneWidget,
    );
    expect(find.text('Big Peer / Ditto Server'), findsOneWidget);
    expect(find.text('Bluetooth → Fire tablet'), findsOneWidget);
    final graphCenter = tester.getCenter(
      find.byKey(const ValueKey('live-mesh-topology-graph')),
    );
    final selectedCenter = tester.getCenter(
      find.byKey(const ValueKey('topology-device-galaxy')),
    );
    expect(selectedCenter.dx, closeTo(graphCenter.dx, 1));
    expect(selectedCenter.dy, closeTo(graphCenter.dy, 1));

    await tester.ensureVisible(
      find.byKey(const ValueKey('topology-clear-selection')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('topology-clear-selection')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('topology-selected-details-galaxy')),
      findsNothing,
    );
  });

  testWidgets('lost BLE edge shows reconnecting details, then expires',
      (tester) async {
    await tester.pumpWidget(
      _topologyApp(
        statuses: _connectedStatuses,
        reconnectGracePeriod: const Duration(seconds: 2),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('topology-device-galaxy')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('topology-device-galaxy')),
    );
    await tester.pump();

    await tester.pumpWidget(
      _topologyApp(
        statuses: {
          'fire': _status(
            'fire',
            'peer-fire',
            topologyConnections: const [],
          ),
          'galaxy': _status(
            'galaxy',
            'peer-galaxy',
            server: true,
            topologyConnections: const [],
          ),
        },
        reconnectGracePeriod: const Duration(seconds: 2),
      ),
    );
    await tester.pump();

    expect(
      find.text('Bluetooth · Reconnecting → Fire tablet'),
      findsOneWidget,
    );
    expect(find.text('Big Peer / Ditto Server'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(
      find.text('Bluetooth · Reconnecting → Fire tablet'),
      findsNothing,
    );
    expect(find.text('Big Peer / Ditto Server'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('disconnected nodes are below every connected edge', () {
    const topology = MeshTopology(
      nodes: [
        MeshTopologyNode(
          id: bigPeerTopologyNodeId,
          label: 'Big Peer',
          isBigPeer: true,
        ),
        MeshTopologyNode(id: 'galaxy', label: 'Galaxy S20'),
        MeshTopologyNode(id: 'backend', label: 'Node backend'),
        MeshTopologyNode(id: 'fire', label: 'Fire tablet'),
      ],
      edges: [
        MeshTopologyEdge(
          id: 'cloud-galaxy',
          fromId: bigPeerTopologyNodeId,
          toId: 'galaxy',
          isBigPeer: true,
        ),
        MeshTopologyEdge(
          id: 'galaxy-backend',
          fromId: 'galaxy',
          toId: 'backend',
          kind: MeshConnectionKind.accessPoint,
        ),
      ],
    );
    final layout = topologyNodePositionsForTesting(
      nodes: topology.nodes.where((node) => !node.isBigPeer).toList(),
      edges: topology.edges,
      width: 700,
    );
    final fireRect = layout.positions['fire']!;

    expect(layout.disconnectedLabelTop, isNotNull);
    expect(fireRect.top, greaterThan(layout.positions['galaxy']!.bottom));
    expect(fireRect.top, greaterThan(layout.positions['backend']!.bottom));
    for (final edge in topology.edges) {
      final segment = topologyVisibleEdgeSegmentForTesting(
        from: layout.positions[edge.fromId]!,
        to: layout.positions[edge.toId]!,
      );
      expect(
          math.max(segment.start.dy, segment.end.dy), lessThan(fireRect.top));
    }
  });

  testWidgets('empty device list uses device-focused copy', (tester) async {
    await tester.pumpWidget(_app(people: const [], statuses: const {}));

    expect(find.text('0 DEVICES'), findsOneWidget);
    expect(find.text('Synced Draper TAK devices will appear here.'),
        findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('empty topology counts the displayed Big Peer node',
      (tester) async {
    await tester.pumpWidget(
      _topologyApp(people: const [], statuses: const {}),
    );

    expect(find.text('1 NODE · 0 CONNECTIONS'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topology-big-peer-node')),
      findsOneWidget,
    );
  });

  testWidgets('topology fits a narrow mobile viewport without exceptions',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_topologyApp(statuses: _connectedStatuses));
    await tester.pump();

    expect(find.byKey(const ValueKey('topology-device-fire')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('topology-device-fire')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('topology-device-fire')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('topology-selected-details-fire')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a backend SDK peer on a narrow mobile topology',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backendStatuses = {
      'galaxy': _status(
        'galaxy',
        'peer-galaxy',
        server: true,
        connections: const {MeshConnectionKind.accessPoint},
        topologyConnections: const [
          MeshTopologyConnection(
            id: 'galaxy-backend-lan',
            peer1: 'peer-galaxy',
            peer2: 'peer-backend',
            kind: MeshConnectionKind.accessPoint,
          ),
        ],
        topologyPeers: const [
          MeshTopologyPeerDescriptor(
            peerKey: 'peer-backend',
            deviceName: 'Draper TAK Node backend',
            os: 'macOS',
            dittoSdkVersion: '5.0.2',
            connectedToDittoServer: true,
          ),
        ],
      ),
    };

    await tester.pumpWidget(_app(statuses: backendStatuses));

    expect(find.byKey(const ValueKey('presence-galaxy')), findsOneWidget);
    expect(find.text('Draper TAK Node backend'), findsNothing);
    expect(find.text('SDK PEER + BIG PEER'), findsNothing);

    await tester.pumpWidget(_topologyApp(statuses: backendStatuses));
    await tester.pump();

    expect(find.text('4 NODES · 3 CONNECTIONS'), findsOneWidget);
    expect(find.text('Draper TAK Node backend'), findsOneWidget);
    expect(find.text('SDK PEER + BIG PEER'), findsOneWidget);
    expect(
      find.text('Ditto SDK peer without a Draper TAK record'),
      findsOneWidget,
    );
    expect(find.text('Peer ID: peer-backend'), findsOneWidget);
    expect(find.text('macOS • Ditto 5.0.2'), findsOneWidget);
    expect(find.text('SDK peer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('identifies an isolated SDK peer without a mapped edge',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const peerKey = 'peer-unidentified-1234567890abcdef';
    final statuses = {
      'galaxy': _status(
        'galaxy',
        'peer-galaxy',
        topologyConnections: const [],
        topologyPeers: const [
          MeshTopologyPeerDescriptor(
            peerKey: peerKey,
            deviceName: '',
            connectedToDittoServer: false,
          ),
        ],
      ),
    };

    await tester.pumpWidget(_app(statuses: statuses));
    expect(find.textContaining('Unidentified SDK peer'), findsNothing);

    await tester.pumpWidget(_topologyApp(statuses: statuses));
    await tester.pump();

    expect(find.text('Unidentified SDK peer 90abcdef'), findsOneWidget);
    expect(find.text('Peer ID: $peerKey'), findsOneWidget);
    expect(find.text('NOT CONNECTED'), findsWidgets);
    final route = tester.widget<Text>(
      find.byKey(
        const ValueKey(
          'topology-route-__ditto_sdk_peer__:peer-unidentified-1234567890abcdef',
        ),
      ),
    );
    expect(route.style!.color, const Color(0xFFFF7A86));
    expect(tester.takeException(), isNull);
  });
}

bool _segmentIntersectsRect(Offset start, Offset end, Rect rect) {
  if (start.dx == end.dx) {
    return start.dx > rect.left &&
        start.dx < rect.right &&
        math.max(start.dy, end.dy) > rect.top &&
        math.min(start.dy, end.dy) < rect.bottom;
  }
  return start.dy > rect.top &&
      start.dy < rect.bottom &&
      math.max(start.dx, end.dx) > rect.left &&
      math.min(start.dx, end.dx) < rect.right;
}

double _sharedLaneLength(List<Offset> first, List<Offset> second) {
  var overlap = 0.0;
  for (var firstIndex = 0; firstIndex < first.length - 1; firstIndex++) {
    final firstStart = first[firstIndex];
    final firstEnd = first[firstIndex + 1];
    final firstVertical = firstStart.dx == firstEnd.dx;
    for (var secondIndex = 0; secondIndex < second.length - 1; secondIndex++) {
      final secondStart = second[secondIndex];
      final secondEnd = second[secondIndex + 1];
      final secondVertical = secondStart.dx == secondEnd.dx;
      if (firstVertical != secondVertical) continue;
      final sameLane = firstVertical
          ? firstStart.dx == secondStart.dx
          : firstStart.dy == secondStart.dy;
      if (!sameLane) continue;
      final firstMin = firstVertical
          ? math.min(firstStart.dy, firstEnd.dy)
          : math.min(firstStart.dx, firstEnd.dx);
      final firstMax = firstVertical
          ? math.max(firstStart.dy, firstEnd.dy)
          : math.max(firstStart.dx, firstEnd.dx);
      final secondMin = secondVertical
          ? math.min(secondStart.dy, secondEnd.dy)
          : math.min(secondStart.dx, secondEnd.dx);
      final secondMax = secondVertical
          ? math.max(secondStart.dy, secondEnd.dy)
          : math.max(secondStart.dx, secondEnd.dx);
      overlap += math.max(
        0,
        math.min(firstMax, secondMax) - math.max(firstMin, secondMin),
      );
    }
  }
  return overlap;
}

final _people = [
  UserPresence(
    id: 'fire',
    username: 'Fire tablet',
    latitude: 33.0,
    longitude: -84.0,
    status: 'Fire tablet status',
    updatedAt: DateTime.utc(2026, 7, 22),
  ),
  UserPresence(
    id: 'galaxy',
    username: 'Galaxy S20',
    latitude: 33.1,
    longitude: -84.1,
    status: 'Galaxy S20 status',
    updatedAt: DateTime.utc(2026, 7, 22),
  ),
];

const _bleConnection = MeshTopologyConnection(
  id: 'fire-galaxy-ble',
  peer1: 'peer-fire',
  peer2: 'peer-galaxy',
  kind: MeshConnectionKind.bluetooth,
);

final _connectedStatuses = {
  'fire': _status(
    'fire',
    'peer-fire',
    connections: const {MeshConnectionKind.bluetooth},
  ),
  'galaxy': _status(
    'galaxy',
    'peer-galaxy',
    server: true,
    connections: const {MeshConnectionKind.bluetooth},
  ),
};

MeshPeerStatus _status(
  String id,
  String peerKey, {
  bool server = false,
  Set<MeshConnectionKind> connections = const {},
  List<MeshTopologyConnection> topologyConnections = const [_bleConnection],
  List<MeshTopologyPeerDescriptor> topologyPeers = const [],
}) =>
    MeshPeerStatus(
      deviceId: id,
      deviceName: 'DraperTAK-$id',
      os: 'test',
      dittoSdkVersion: '5.0.2',
      connectedToDittoServer: server,
      connections: connections,
      connectivity: const DeviceConnectivity.unknown(),
      peerKey: peerKey,
      topologyConnections: topologyConnections,
      topologyPeers: topologyPeers,
      observedAt: DateTime.utc(2026, 7, 22),
    );

Widget _app({
  List<UserPresence>? people,
  required Map<String, MeshPeerStatus> statuses,
}) =>
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: buildLiveMeshForTesting(
            people: people ?? _people,
            statuses: statuses,
          ),
        ),
      ),
    );

Widget _topologyApp({
  List<UserPresence>? people,
  required Map<String, MeshPeerStatus> statuses,
  DateTime? lastUpdated,
  Duration reconnectGracePeriod = meshReconnectGracePeriod,
}) =>
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: buildObservabilityForTesting(
            people: people ?? _people,
            statuses: statuses,
            lastUpdated: lastUpdated,
            reconnectGracePeriod: reconnectGracePeriod,
          ),
        ),
      ),
    );
