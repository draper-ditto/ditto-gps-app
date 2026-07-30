import 'package:ditto_gps/models/mesh_peer_status.dart';
import 'package:ditto_gps/models/user_presence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presence documents round-trip through Ditto-shaped JSON', () {
    final updatedAt = DateTime.utc(2026, 7, 20, 18, 0);
    final presence = UserPresence(
      id: 'device-1',
      username: 'Ada',
      latitude: 37.7749,
      longitude: -122.4194,
      status: 'Exploring',
      updatedAt: updatedAt,
    );

    final decoded = UserPresence.fromJson(presence.toJson());

    expect(decoded.id, 'device-1');
    expect(decoded.username, 'Ada');
    expect(decoded.latitude, 37.7749);
    expect(decoded.longitude, -122.4194);
    expect(decoded.status, 'Exploring');
    expect(decoded.isDeleted, isFalse);
    expect(
      decoded.updatedAt.millisecondsSinceEpoch,
      updatedAt.millisecondsSinceEpoch,
    );
  });

  test('soft-deleted presence is hidden until the device republishes', () {
    final removed = UserPresence.fromJson({
      '_id': 'device-1',
      'username': 'Ada',
      'latitude': 37.7749,
      'longitude': -122.4194,
      'status': 'Exploring',
      'updatedAt': 1,
      'isDeleted': true,
    });
    final legacy = UserPresence.fromJson({
      '_id': 'legacy-device',
      'username': 'Grace',
    });
    final republished = UserPresence(
      id: removed.id,
      username: removed.username,
      latitude: removed.latitude,
      longitude: removed.longitude,
      status: 'Rejoined',
      updatedAt: DateTime.utc(2026, 7, 22),
    );

    expect(removed.isDeleted, isTrue);
    expect(legacy.isDeleted, isFalse);
    expect(republished.toJson()['isDeleted'], isFalse);
  });

  test('device connectivity round-trips through peer metadata', () {
    final observedAt = DateTime.utc(2026, 7, 22, 16, 30);
    final connectivity = DeviceConnectivity(
      wifi: true,
      bluetooth: false,
      cellular: false,
      observedAt: observedAt,
    );

    final decoded = DeviceConnectivity.fromJson(connectivity.toJson());

    expect(decoded.wifi, isTrue);
    expect(decoded.bluetooth, isFalse);
    expect(decoded.cellular, isFalse);
    expect(decoded.observedAt, observedAt);
    expect(decoded.hasSameLinks(connectivity), isTrue);
  });

  test('connectivity parsing tolerates missing and malformed metadata', () {
    final decoded = DeviceConnectivity.fromJson({
      'wifi': 'yes',
      'bluetooth': 1,
      'cellular': true,
      'observedAt': 'not-a-timestamp',
    });

    expect(decoded.wifi, isNull);
    expect(decoded.bluetooth, isNull);
    expect(decoded.cellular, isTrue);
    expect(decoded.observedAt, isNull);
    expect(DeviceConnectivity.fromJson(null).wifi, isNull);
  });

  test('link comparison intentionally ignores observation time', () {
    final first = DeviceConnectivity(
      wifi: true,
      bluetooth: false,
      cellular: null,
      observedAt: DateTime.utc(2026, 7, 22, 10),
    );
    final later = DeviceConnectivity(
      wifi: true,
      bluetooth: false,
      cellular: null,
      observedAt: DateTime.utc(2026, 7, 22, 11),
    );

    expect(first.hasSameLinks(later), isTrue);
  });

  test('Draper TAK metadata preserves unrelated peer metadata', () {
    final connectivity = DeviceConnectivity(
      wifi: true,
      bluetooth: false,
      cellular: true,
      observedAt: DateTime.utc(2026, 7, 22, 16, 30),
    );

    final metadata = withDraperTakPeerMetadata(
      existing: {
        'otherApp': {'enabled': true},
        'draperTak': {'stale': true},
      },
      deviceId: 'device-1',
      connectivity: connectivity,
    );

    expect(metadata['otherApp'], {'enabled': true});
    expect(metadata['draperTak'], {
      'deviceId': 'device-1',
      'connectivity': connectivity.toJson(),
    });
    expect(
      connectivityFromPeerMetadata(metadata['draperTak']).hasSameLinks(
        connectivity,
      ),
      isTrue,
    );
  });

  test('missing peer connectivity metadata produces unknown state', () {
    expect(connectivityFromPeerMetadata(null).wifi, isNull);
    expect(connectivityFromPeerMetadata({'other': true}).bluetooth, isNull);
  });

  test('mesh status distinguishes Big Peer and peer-to-peer links', () {
    const meshOnly = MeshPeerStatus(
      deviceId: 'device-1',
      deviceName: 'DraperTAK-device-1',
      os: 'android',
      dittoSdkVersion: '5.0.2',
      connectedToDittoServer: false,
      connections: {MeshConnectionKind.bluetooth},
      connectivity: DeviceConnectivity.unknown(),
    );
    const serverOnly = MeshPeerStatus(
      deviceId: 'device-2',
      deviceName: 'DraperTAK-device-2',
      os: 'web',
      dittoSdkVersion: '5.0.2',
      connectedToDittoServer: true,
      connections: {},
      connectivity: DeviceConnectivity.unknown(),
    );

    expect(meshOnly.hasPeerToPeerConnection, isTrue);
    expect(meshOnly.connectedToDittoServer, isFalse);
    expect(serverOnly.hasPeerToPeerConnection, isFalse);
    expect(serverOnly.connectedToDittoServer, isTrue);
  });

  test('live mesh telemetry round-trips with a presence document', () {
    final observedAt = DateTime.utc(2026, 7, 22, 20, 15);
    final presence = UserPresence(
      id: 'galaxy-device',
      username: 'Samsung Galaxy S20',
      latitude: 33.749,
      longitude: -84.388,
      status: 'Patrolling',
      updatedAt: DateTime.utc(2026, 7, 22, 20),
      liveMeshStatus: MeshPeerStatus(
        deviceId: 'galaxy-device',
        deviceName: 'DraperTAK-galaxy',
        os: 'Android',
        dittoSdkVersion: '5.0.2',
        connectedToDittoServer: true,
        connections: const {
          MeshConnectionKind.accessPoint,
          MeshConnectionKind.bluetooth,
        },
        connectivity: DeviceConnectivity(
          wifi: true,
          bluetooth: true,
          cellular: false,
          observedAt: observedAt,
        ),
        peerKey: 'peer-galaxy',
        topologyConnections: const [
          MeshTopologyConnection(
            id: 'galaxy-backend',
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
        observedAt: observedAt,
      ),
    );

    final decoded = UserPresence.fromJson(presence.toJson());

    expect(decoded.liveMeshStatus, isNotNull);
    expect(decoded.liveMeshStatus!.deviceId, 'galaxy-device');
    expect(decoded.liveMeshStatus!.connectedToDittoServer, isTrue);
    expect(
      decoded.liveMeshStatus!.connections,
      {
        MeshConnectionKind.accessPoint,
        MeshConnectionKind.bluetooth,
      },
    );
    expect(decoded.liveMeshStatus!.connectivity.wifi, isTrue);
    expect(decoded.liveMeshStatus!.topologyConnections, hasLength(1));
    expect(
      decoded.liveMeshStatus!.topologyPeers.single.deviceName,
      'Draper TAK Node backend',
    );
    expect(decoded.liveMeshStatus!.observedAt, observedAt);
    expect(decoded.updatedAt, presence.updatedAt);
  });

  test('malformed live telemetry is safely treated as disconnected', () {
    final decoded = UserPresence.fromJson({
      '_id': 'device-1',
      'liveMeshStatus': {
        'deviceId': 'device-1',
        'connections': ['not-a-transport', 4],
        'topologyPeers': [
          {'peerKey': '', 'deviceName': 'Missing identity'},
          'not-an-object',
        ],
        'observedAt': 'recent',
      },
    });

    expect(decoded.liveMeshStatus, isNotNull);
    expect(decoded.liveMeshStatus!.connections, isEmpty);
    expect(decoded.liveMeshStatus!.topologyPeers, isEmpty);
    expect(decoded.liveMeshStatus!.observedAt, isNull);
  });
}
