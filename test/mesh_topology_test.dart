import 'package:ditto_gps/models/mesh_peer_status.dart';
import 'package:ditto_gps/models/mesh_topology.dart';
import 'package:ditto_gps/models/user_presence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds Big Peer and BLE edges from SDK topology fields', () {
    final connection = _connection();
    final topology = buildMeshTopology(
      people: [_person('fire', 'Fire tablet'), _person('galaxy', 'Galaxy S20')],
      statuses: {
        'fire': _status(
          'fire',
          peerKey: 'peer-fire',
          connections: const {MeshConnectionKind.bluetooth},
          topologyConnections: [connection],
        ),
        'galaxy': _status(
          'galaxy',
          peerKey: 'peer-galaxy',
          server: true,
          connections: const {MeshConnectionKind.bluetooth},
          topologyConnections: [connection],
        ),
      },
    );

    expect(topology.nodes, hasLength(3));
    expect(
      topology.edges.where((edge) => edge.isBigPeer).single.toId,
      'galaxy',
    );
    final ble = topology.edges.where((edge) => !edge.isBigPeer).single;
    expect({ble.fromId, ble.toId}, {'fire', 'galaxy'});
    expect(ble.kind, MeshConnectionKind.bluetooth);
  });

  test('deduplicates an SDK connection reported by both endpoint peers', () {
    final connection = _connection();
    final topology = buildMeshTopology(
      people: [_person('fire', 'Fire tablet'), _person('galaxy', 'Galaxy S20')],
      statuses: {
        'fire': _status(
          'fire',
          peerKey: 'peer-fire',
          topologyConnections: [connection],
        ),
        'galaxy': _status(
          'galaxy',
          peerKey: 'peer-galaxy',
          topologyConnections: [connection],
        ),
      },
    );

    expect(topology.edges, hasLength(1));
  });

  test('preserves every connection when one node has multiple neighbors', () {
    const fireToGalaxy = MeshTopologyConnection(
      id: 'fire-galaxy',
      peer1: 'peer-fire',
      peer2: 'peer-galaxy',
      kind: MeshConnectionKind.bluetooth,
    );
    const fireToBackend = MeshTopologyConnection(
      id: 'fire-backend',
      peer1: 'peer-fire',
      peer2: 'peer-backend',
      kind: MeshConnectionKind.accessPoint,
    );
    final topology = buildMeshTopology(
      people: [_person('fire', 'Fire tablet'), _person('galaxy', 'Galaxy S20')],
      statuses: {
        'fire': _status(
          'fire',
          peerKey: 'peer-fire',
          topologyConnections: const [fireToGalaxy, fireToBackend],
          topologyPeers: const [
            MeshTopologyPeerDescriptor(
              peerKey: 'peer-backend',
              deviceName: 'Draper TAK Node backend',
              connectedToDittoServer: true,
            ),
          ],
        ),
        'galaxy': _status('galaxy', peerKey: 'peer-galaxy'),
      },
    );

    final peerEdges = topology.edges.where((edge) => !edge.isBigPeer).toList();
    expect(peerEdges, hasLength(2));
    expect(
      peerEdges.map((edge) => edge.id),
      containsAll(['fire-galaxy', 'fire-backend']),
    );
    expect(peerEdges.every((edge) => edge.fromId == 'fire'), isTrue);
  });

  test('keeps an offline device visible but removes its live edges', () {
    final topology = buildMeshTopology(
      people: [_person('fire', 'Fire tablet'), _person('galaxy', 'Galaxy S20')],
      statuses: {
        'galaxy': _status('galaxy', peerKey: 'peer-galaxy', server: true),
      },
    );

    expect(topology.nodes.map((node) => node.id), contains('fire'));
    expect(
        topology.nodes.singleWhere((node) => node.id == 'fire').status, isNull);
    expect(
      topology.edges
          .any((edge) => edge.fromId == 'fire' || edge.toId == 'fire'),
      isFalse,
    );
  });

  test('shows a named SDK peer and its Big Peer connection', () {
    final topology = buildMeshTopology(
      people: [_person('galaxy', 'Galaxy S20')],
      statuses: {
        'galaxy': _status(
          'galaxy',
          peerKey: 'peer-galaxy',
          topologyConnections: const [
            MeshTopologyConnection(
              id: 'unknown-edge',
              peer1: 'peer-galaxy',
              peer2: 'peer-not-in-live-mesh',
              kind: MeshConnectionKind.accessPoint,
            ),
          ],
          topologyPeers: const [
            MeshTopologyPeerDescriptor(
              peerKey: 'peer-not-in-live-mesh',
              deviceName: 'Draper TAK Node backend',
              os: 'macOS',
              dittoSdkVersion: '5.0.2',
              connectedToDittoServer: true,
            ),
          ],
        ),
      },
    );

    final sdkNode = topology.nodes.singleWhere((node) => node.isSdkPeer);
    expect(sdkNode.label, 'Draper TAK Node backend');
    expect(sdkNode.sdkPeer!.os, 'macOS');
    expect(
      topology.edges.any(
        (edge) =>
            !edge.isBigPeer &&
            {edge.fromId, edge.toId}.containsAll(
              {'galaxy', sdkPeerTopologyNodeId('peer-not-in-live-mesh')},
            ),
      ),
      isTrue,
    );
    expect(
      topology.edges.any(
        (edge) => edge.isBigPeer && edge.toId == sdkNode.id,
      ),
      isTrue,
    );
  });

  test('shows a generic SDK peer when its descriptor is unavailable', () {
    final topology = buildMeshTopology(
      people: [_person('galaxy', 'Galaxy S20')],
      statuses: {
        'galaxy': _status(
          'galaxy',
          peerKey: 'peer-galaxy',
          topologyConnections: const [
            MeshTopologyConnection(
              id: 'legacy-edge',
              peer1: 'peer-galaxy',
              peer2: '1234567890abcdef',
              kind: MeshConnectionKind.bluetooth,
            ),
          ],
        ),
      },
    );

    final sdkNode = topology.nodes.singleWhere((node) => node.isSdkPeer);
    expect(sdkNode.label, 'Unidentified SDK peer 90abcdef');
    expect(sdkNode.sdkPeer!.peerKey, '1234567890abcdef');
    expect(topology.edges.where((edge) => !edge.isBigPeer), hasLength(1));
    expect(topology.edges.where((edge) => edge.isBigPeer), isEmpty);
  });

  test('shows every SDK-reported peer even when it has no transport edge', () {
    final topology = buildMeshTopology(
      people: [_person('galaxy', 'Galaxy S20')],
      statuses: {
        'galaxy': _status(
          'galaxy',
          peerKey: 'peer-galaxy',
          topologyPeers: const [
            MeshTopologyPeerDescriptor(
              peerKey: 'peer-isolated',
              deviceName: '',
              connectedToDittoServer: false,
            ),
            MeshTopologyPeerDescriptor(
              peerKey: 'peer-headless-agent',
              deviceName: 'Headless Ditto agent',
              connectedToDittoServer: true,
            ),
          ],
        ),
      },
    );

    final sdkNodes = topology.nodes.where((node) => node.isSdkPeer).toList();
    expect(sdkNodes, hasLength(2));
    expect(
      sdkNodes.map((node) => node.label),
      containsAll(['Unidentified SDK peer isolated', 'Headless Ditto agent']),
    );
    expect(
      sdkNodes.every((node) => node.sdkPeer!.peerKey.isNotEmpty),
      isTrue,
    );
    expect(
      topology.edges.any(
        (edge) =>
            edge.isBigPeer &&
            edge.toId == sdkPeerTopologyNodeId('peer-headless-agent'),
      ),
      isTrue,
    );
    expect(
      topology.edges.any(
        (edge) =>
            edge.fromId == sdkPeerTopologyNodeId('peer-isolated') ||
            edge.toId == sdkPeerTopologyNodeId('peer-isolated'),
      ),
      isFalse,
    );
  });

  test('topology telemetry survives synchronization JSON round trip', () {
    final original = _status(
      'galaxy',
      peerKey: 'peer-galaxy',
      server: true,
      connections: const {MeshConnectionKind.bluetooth},
      topologyConnections: [_connection()],
      topologyPeers: const [
        MeshTopologyPeerDescriptor(
          peerKey: 'peer-backend',
          deviceName: 'Draper TAK Node backend',
          os: 'macOS',
          dittoSdkVersion: '5.0.2',
          connectedToDittoServer: true,
        ),
      ],
    );

    final restored =
        MeshPeerStatus.fromTelemetryJson(original.toTelemetryJson());

    expect(restored.hasSameState(original), isTrue);
    expect(restored.peerKey, 'peer-galaxy');
    expect(restored.topologyConnections.single.peer2, 'peer-galaxy');
    expect(restored.topologyPeers.single.deviceName, 'Draper TAK Node backend');
  });

  group('reconnecting topology edges', () {
    final observedAt = DateTime.utc(2026, 7, 23, 12);
    const nodes = [
      MeshTopologyNode(
        id: bigPeerTopologyNodeId,
        label: 'Big Peer',
        isBigPeer: true,
      ),
      MeshTopologyNode(id: 'fire', label: 'Fire tablet'),
      MeshTopologyNode(id: 'galaxy', label: 'Galaxy S20'),
      MeshTopologyNode(
        id: 'backend',
        label: 'Node backend',
        sdkPeer: MeshTopologyPeerDescriptor(
          peerKey: 'peer-backend',
          deviceName: 'Node backend',
          connectedToDittoServer: false,
        ),
      ),
    ];
    const edges = [
      MeshTopologyEdge(
        id: 'ble',
        fromId: 'fire',
        toId: 'galaxy',
        kind: MeshConnectionKind.bluetooth,
      ),
      MeshTopologyEdge(
        id: 'lan',
        fromId: 'galaxy',
        toId: 'backend',
        kind: MeshConnectionKind.accessPoint,
      ),
      MeshTopologyEdge(
        id: 'p2p',
        fromId: 'fire',
        toId: 'backend',
        kind: MeshConnectionKind.p2pWifi,
      ),
      MeshTopologyEdge(
        id: 'ws',
        fromId: 'galaxy',
        toId: 'fire',
        kind: MeshConnectionKind.webSocket,
      ),
      MeshTopologyEdge(
        id: 'cloud',
        fromId: bigPeerTopologyNodeId,
        toId: 'galaxy',
        isBigPeer: true,
      ),
    ];

    test('retains every protocol and endpoint during the grace period', () {
      final tracker = MeshTopologyReconnectTracker(
        gracePeriod: const Duration(seconds: 15),
      );
      final initial = tracker.update(
        const MeshTopology(nodes: nodes, edges: edges),
        now: observedAt,
      );
      expect(initial.edges.every((edge) => !edge.isReconnecting), isTrue);

      final reconnecting = tracker.update(
        const MeshTopology(nodes: [
          MeshTopologyNode(
            id: bigPeerTopologyNodeId,
            label: 'Big Peer',
            isBigPeer: true,
          ),
          MeshTopologyNode(id: 'fire', label: 'Fire tablet'),
          MeshTopologyNode(id: 'galaxy', label: 'Galaxy S20'),
        ], edges: []),
        now: observedAt.add(const Duration(seconds: 1)),
      );

      expect(reconnecting.edges, hasLength(edges.length));
      expect(reconnecting.edges.every((edge) => edge.isReconnecting), isTrue);
      expect(
        reconnecting.edges.map((edge) => edge.kind).toSet(),
        {
          null,
          MeshConnectionKind.bluetooth,
          MeshConnectionKind.accessPoint,
          MeshConnectionKind.p2pWifi,
          MeshConnectionKind.webSocket,
        },
      );
      expect(reconnecting.nodes.map((node) => node.id), contains('backend'));
      expect(
        tracker.nextExpiration,
        observedAt.add(const Duration(seconds: 16)),
      );
    });

    test('restores a solid edge immediately when it reappears', () {
      final tracker = MeshTopologyReconnectTracker();
      final connected = MeshTopology(nodes: nodes, edges: [edges.first]);
      tracker.update(connected, now: observedAt);
      tracker.update(
        const MeshTopology(nodes: nodes, edges: []),
        now: observedAt.add(const Duration(seconds: 1)),
      );

      final recovered = tracker.update(
        connected,
        now: observedAt.add(const Duration(seconds: 2)),
      );

      expect(recovered.edges, hasLength(1));
      expect(recovered.edges.single.isReconnecting, isFalse);
      expect(tracker.nextExpiration, isNull);
    });

    test('expires lost edges and SDK-only endpoint nodes at the boundary', () {
      final tracker = MeshTopologyReconnectTracker(
        gracePeriod: const Duration(seconds: 3),
      );
      final connected = MeshTopology(nodes: nodes, edges: [edges[1]]);
      tracker.update(connected, now: observedAt);
      final reconnecting = tracker.update(
        const MeshTopology(nodes: [
          MeshTopologyNode(
            id: bigPeerTopologyNodeId,
            label: 'Big Peer',
            isBigPeer: true,
          ),
          MeshTopologyNode(id: 'galaxy', label: 'Galaxy S20'),
        ], edges: []),
        now: observedAt.add(const Duration(seconds: 1)),
      );
      expect(reconnecting.nodes.map((node) => node.id), contains('backend'));

      final expired = tracker.update(
        const MeshTopology(nodes: [
          MeshTopologyNode(
            id: bigPeerTopologyNodeId,
            label: 'Big Peer',
            isBigPeer: true,
          ),
          MeshTopologyNode(id: 'galaxy', label: 'Galaxy S20'),
        ], edges: []),
        now: observedAt.add(const Duration(seconds: 4)),
      );

      expect(expired.edges, isEmpty);
      expect(expired.nodes.map((node) => node.id), isNot(contains('backend')));
      expect(tracker.nextExpiration, isNull);
    });

    test('can disable reconnect retention with a zero grace period', () {
      final tracker = MeshTopologyReconnectTracker(
        gracePeriod: Duration.zero,
      );
      tracker.update(
        MeshTopology(nodes: nodes, edges: [edges.first]),
        now: observedAt,
      );

      final disconnected = tracker.update(
        const MeshTopology(nodes: nodes, edges: []),
        now: observedAt.add(const Duration(seconds: 1)),
      );

      expect(disconnected.edges, isEmpty);
      expect(tracker.nextExpiration, isNull);
    });
  });
}

UserPresence _person(String id, String username) => UserPresence(
      id: id,
      username: username,
      latitude: 0,
      longitude: 0,
      status: '$username status',
      updatedAt: DateTime.utc(2026, 7, 22),
    );

MeshPeerStatus _status(
  String id, {
  required String peerKey,
  bool server = false,
  Set<MeshConnectionKind> connections = const {},
  List<MeshTopologyConnection> topologyConnections = const [],
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

MeshTopologyConnection _connection() => const MeshTopologyConnection(
      id: 'peer-fire<->peer-galaxy:Bluetooth',
      peer1: 'peer-fire',
      peer2: 'peer-galaxy',
      kind: MeshConnectionKind.bluetooth,
    );
