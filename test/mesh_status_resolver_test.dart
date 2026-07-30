import 'package:ditto_gps/models/mesh_peer_status.dart';
import 'package:ditto_gps/models/user_presence.dart';
import 'package:ditto_gps/services/mesh_status_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 22, 20, 30);

  test('multiple directly visible mesh devices remain independently connected',
      () {
    final galaxy = _status(
      'galaxy',
      observedAt: now,
      server: true,
      connections: const {MeshConnectionKind.accessPoint},
    );
    final tablet = _status(
      'tablet',
      observedAt: now,
      connections: const {MeshConnectionKind.bluetooth},
    );
    final laptop = _status('laptop', observedAt: now, server: true);

    final resolved = resolveMeshStatuses(
      people: [
        _person('galaxy'),
        _person('tablet'),
        _person('laptop'),
      ],
      directStatuses: {
        'galaxy': galaxy,
        'tablet': tablet,
        'laptop': laptop,
      },
      now: now,
    );

    expect(resolved, hasLength(3));
    expect(resolved['galaxy']!.connectedToDittoServer, isTrue);
    expect(resolved['galaxy']!.hasPeerToPeerConnection, isTrue);
    expect(resolved['tablet']!.connectedToDittoServer, isFalse);
    expect(resolved['tablet']!.hasPeerToPeerConnection, isTrue);
    expect(resolved['laptop']!.connectedToDittoServer, isTrue);
  });

  test('fresh synchronized heartbeat fills a peer absent from the web graph',
      () {
    final galaxyHeartbeat = _status(
      'galaxy',
      observedAt: now.subtract(const Duration(seconds: 4)),
      server: true,
      connections: const {MeshConnectionKind.accessPoint},
    );

    final resolved = resolveMeshStatuses(
      people: [
        _person('galaxy', liveMeshStatus: galaxyHeartbeat),
        _person('laptop'),
      ],
      directStatuses: {
        'laptop': _status('laptop', observedAt: now, server: true),
      },
      now: now,
    );

    expect(resolved, hasLength(2));
    expect(resolved['galaxy'], same(galaxyHeartbeat));
    expect(resolved['galaxy']!.connectedToDittoServer, isTrue);
    expect(resolved['galaxy']!.hasPeerToPeerConnection, isTrue);
  });

  test('direct presence wins over synchronized telemetry for the same device',
      () {
    final direct = _status(
      'galaxy',
      observedAt: now,
      connections: const {MeshConnectionKind.bluetooth},
    );
    final heartbeat = _status(
      'galaxy',
      observedAt: now,
      server: true,
      connections: const {MeshConnectionKind.accessPoint},
    );

    final resolved = resolveMeshStatuses(
      people: [_person('galaxy', liveMeshStatus: heartbeat)],
      directStatuses: {'galaxy': direct},
      now: now,
    );

    expect(resolved['galaxy'], same(direct));
    expect(resolved['galaxy']!.connectedToDittoServer, isFalse);
    expect(
      resolved['galaxy']!.connections,
      {MeshConnectionKind.bluetooth},
    );
  });

  test('stale, future, mismatched, and deleted heartbeats stay disconnected',
      () {
    final resolved = resolveMeshStatuses(
      people: [
        _person(
          'stale',
          liveMeshStatus: _status(
            'stale',
            observedAt: now.subtract(const Duration(seconds: 16)),
            server: true,
          ),
        ),
        _person(
          'future',
          liveMeshStatus: _status(
            'future',
            observedAt: now.add(const Duration(seconds: 6)),
            server: true,
          ),
        ),
        _person(
          'expected-id',
          liveMeshStatus: _status(
            'different-id',
            observedAt: now,
            server: true,
          ),
        ),
        _person(
          'deleted',
          liveMeshStatus: _status('deleted', observedAt: now, server: true),
          isDeleted: true,
        ),
        _person(
          'fresh',
          liveMeshStatus: _status(
            'fresh',
            observedAt: now.subtract(const Duration(seconds: 15)),
            connections: const {MeshConnectionKind.p2pWifi},
          ),
        ),
      ],
      directStatuses: const {},
      now: now,
    );

    expect(resolved.keys, {'fresh'});
    expect(resolved['fresh']!.hasPeerToPeerConnection, isTrue);
  });

  test('status map comparison detects changes across multiple devices', () {
    final first = {
      'galaxy': _status('galaxy', observedAt: now, server: true),
      'tablet': _status(
        'tablet',
        observedAt: now,
        connections: const {MeshConnectionKind.bluetooth},
      ),
    };
    final equivalent = {
      'tablet': _status(
        'tablet',
        observedAt: now,
        connections: const {MeshConnectionKind.bluetooth},
      ),
      'galaxy': _status('galaxy', observedAt: now, server: true),
    };
    final changed = {
      ...equivalent,
      'galaxy': _status('galaxy', observedAt: now, server: false),
    };

    expect(meshStatusMapsMatch(first, equivalent), isTrue);
    expect(meshStatusMapsMatch(first, changed), isFalse);
  });

  test('display comparison ignores heartbeat time but detects topology changes',
      () {
    final first = {
      'galaxy': _status('galaxy', observedAt: now, server: true),
    };
    final refreshed = {
      'galaxy': _status(
        'galaxy',
        observedAt: now.add(const Duration(seconds: 3)),
        server: true,
      ),
    };
    final disconnected = {
      'galaxy': _status(
        'galaxy',
        observedAt: now.add(const Duration(seconds: 3)),
        server: false,
      ),
    };

    expect(meshStatusMapsMatch(first, refreshed), isFalse);
    expect(meshStatusMapsHaveSameDisplayedState(first, refreshed), isTrue);
    expect(
      meshStatusMapsHaveSameDisplayedState(first, disconnected),
      isFalse,
    );
  });

  test('heartbeat is accepted at the freshness boundary', () {
    final heartbeat = _status(
      'tablet',
      observedAt: now.subtract(liveMeshStatusMaxAge),
      connections: const {MeshConnectionKind.bluetooth},
    );

    final resolved = resolveMeshStatuses(
      people: [_person('tablet', liveMeshStatus: heartbeat)],
      directStatuses: const {},
      now: now,
    );

    expect(resolved['tablet'], same(heartbeat));
  });

  test('heartbeat expires immediately after the freshness boundary', () {
    final heartbeat = _status(
      'tablet',
      observedAt: now
          .subtract(liveMeshStatusMaxAge)
          .subtract(const Duration(milliseconds: 1)),
      connections: const {MeshConnectionKind.bluetooth},
    );

    final resolved = resolveMeshStatuses(
      people: [_person('tablet', liveMeshStatus: heartbeat)],
      directStatuses: const {},
      now: now,
    );

    expect(resolved, isEmpty);
  });

  group('topology update timestamp', () {
    test('starts empty and records the first displayed topology', () {
      final tracker = MeshTopologyUpdateTracker();
      final firstUpdate = now.add(const Duration(seconds: 1));

      expect(tracker.lastUpdatedAt, isNull);
      expect(
        tracker.record(
          {'galaxy': _status('galaxy', observedAt: now, server: true)},
          receivedAt: firstUpdate,
        ),
        isTrue,
      );
      expect(tracker.lastUpdatedAt, firstUpdate);
    });

    test('does not move for unchanged periodic heartbeats', () {
      final tracker = MeshTopologyUpdateTracker();
      final firstUpdate = now.add(const Duration(seconds: 1));
      tracker.record(
        {'galaxy': _status('galaxy', observedAt: now, server: true)},
        receivedAt: firstUpdate,
      );

      final changed = tracker.record(
        {
          'galaxy': _status(
            'galaxy',
            observedAt: now.add(const Duration(seconds: 3)),
            server: true,
          ),
        },
        receivedAt: now.add(const Duration(seconds: 4)),
      );

      expect(changed, isFalse);
      expect(tracker.lastUpdatedAt, firstUpdate);
    });

    test('moves for disconnect, reconnect, and multi-device changes', () {
      final tracker = MeshTopologyUpdateTracker();
      final connectedAt = now.add(const Duration(seconds: 1));
      final disconnectedAt = now.add(const Duration(seconds: 2));
      final reconnectedAt = now.add(const Duration(seconds: 3));
      final tabletJoinedAt = now.add(const Duration(seconds: 4));

      tracker.record(
        {'galaxy': _status('galaxy', observedAt: now, server: true)},
        receivedAt: connectedAt,
      );
      expect(
        tracker.record(
          {'galaxy': _status('galaxy', observedAt: now, server: false)},
          receivedAt: disconnectedAt,
        ),
        isTrue,
      );
      expect(tracker.lastUpdatedAt, disconnectedAt);

      expect(
        tracker.record(
          {'galaxy': _status('galaxy', observedAt: now, server: true)},
          receivedAt: reconnectedAt,
        ),
        isTrue,
      );
      expect(tracker.lastUpdatedAt, reconnectedAt);

      expect(
        tracker.record(
          {
            'galaxy': _status('galaxy', observedAt: now, server: true),
            'tablet': _status(
              'tablet',
              observedAt: now,
              connections: const {MeshConnectionKind.bluetooth},
            ),
          },
          receivedAt: tabletJoinedAt,
        ),
        isTrue,
      );
      expect(tracker.lastUpdatedAt, tabletJoinedAt);
    });

    test('reset clears the timestamp and tracked topology', () {
      final tracker = MeshTopologyUpdateTracker();
      tracker.record(
        {'galaxy': _status('galaxy', observedAt: now, server: true)},
        receivedAt: now,
      );

      tracker.reset();

      expect(tracker.lastUpdatedAt, isNull);
      expect(
        tracker
            .record(const {}, receivedAt: now.add(const Duration(seconds: 1))),
        isFalse,
      );
    });
  });
}

UserPresence _person(
  String id, {
  MeshPeerStatus? liveMeshStatus,
  bool isDeleted = false,
}) =>
    UserPresence(
      id: id,
      username: id,
      latitude: 0,
      longitude: 0,
      status: '',
      updatedAt: DateTime.utc(2026, 7, 22),
      liveMeshStatus: liveMeshStatus,
      isDeleted: isDeleted,
    );

MeshPeerStatus _status(
  String id, {
  required DateTime observedAt,
  bool server = false,
  Set<MeshConnectionKind> connections = const {},
}) =>
    MeshPeerStatus(
      deviceId: id,
      deviceName: 'DraperTAK-$id',
      os: 'test',
      dittoSdkVersion: '5.0.2',
      connectedToDittoServer: server,
      connections: connections,
      connectivity: const DeviceConnectivity.unknown(),
      observedAt: observedAt,
    );
