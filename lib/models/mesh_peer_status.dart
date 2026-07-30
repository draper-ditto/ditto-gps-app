enum MeshConnectionKind { bluetooth, accessPoint, p2pWifi, webSocket }

class MeshTopologyConnection {
  const MeshTopologyConnection({
    required this.id,
    required this.peer1,
    required this.peer2,
    required this.kind,
  });

  final String id;
  final String peer1;
  final String peer2;
  final MeshConnectionKind kind;

  Map<String, dynamic> toJson() => {
        'id': id,
        'peer1': peer1,
        'peer2': peer2,
        'kind': kind.name,
      };

  factory MeshTopologyConnection.fromJson(Map<String, dynamic> json) {
    final rawKind = json['kind'];
    final kind = MeshConnectionKind.values.firstWhere(
      (candidate) => candidate.name == rawKind,
      orElse: () => MeshConnectionKind.webSocket,
    );
    return MeshTopologyConnection(
      id: json['id'] as String? ?? '',
      peer1: json['peer1'] as String? ?? '',
      peer2: json['peer2'] as String? ?? '',
      kind: kind,
    );
  }

  bool hasSameState(MeshTopologyConnection other) =>
      id == other.id &&
      peer1 == other.peer1 &&
      peer2 == other.peer2 &&
      kind == other.kind;
}

class MeshTopologyPeerDescriptor {
  const MeshTopologyPeerDescriptor({
    required this.peerKey,
    required this.deviceName,
    required this.connectedToDittoServer,
    this.os,
    this.dittoSdkVersion,
  });

  final String peerKey;
  final String deviceName;
  final String? os;
  final String? dittoSdkVersion;
  final bool connectedToDittoServer;

  Map<String, dynamic> toJson() => {
        'peerKey': peerKey,
        'deviceName': deviceName,
        'os': os,
        'dittoSdkVersion': dittoSdkVersion,
        'connectedToDittoServer': connectedToDittoServer,
      };

  factory MeshTopologyPeerDescriptor.fromJson(Map<String, dynamic> json) =>
      MeshTopologyPeerDescriptor(
        peerKey: json['peerKey'] as String? ?? '',
        deviceName: json['deviceName'] as String? ?? '',
        os: json['os'] as String?,
        dittoSdkVersion: json['dittoSdkVersion'] as String?,
        connectedToDittoServer: json['connectedToDittoServer'] == true,
      );

  bool hasSameState(MeshTopologyPeerDescriptor other) =>
      peerKey == other.peerKey &&
      deviceName == other.deviceName &&
      os == other.os &&
      dittoSdkVersion == other.dittoSdkVersion &&
      connectedToDittoServer == other.connectedToDittoServer;
}

class DeviceConnectivity {
  const DeviceConnectivity({
    required this.wifi,
    required this.bluetooth,
    required this.cellular,
    required this.observedAt,
  });

  const DeviceConnectivity.unknown()
      : wifi = null,
        bluetooth = null,
        cellular = null,
        observedAt = null;

  final bool? wifi;
  final bool? bluetooth;
  final bool? cellular;
  final DateTime? observedAt;

  Map<String, dynamic> toJson() => {
        'wifi': wifi,
        'bluetooth': bluetooth,
        'cellular': cellular,
        'observedAt': observedAt?.millisecondsSinceEpoch,
      };

  factory DeviceConnectivity.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DeviceConnectivity.unknown();
    final observedValue = json['observedAt'];
    final observedAt = observedValue is num ? observedValue.toInt() : null;
    return DeviceConnectivity(
      wifi: _optionalBool(json['wifi']),
      bluetooth: _optionalBool(json['bluetooth']),
      cellular: _optionalBool(json['cellular']),
      observedAt: observedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(observedAt, isUtc: true),
    );
  }

  bool hasSameLinks(DeviceConnectivity other) =>
      wifi == other.wifi &&
      bluetooth == other.bluetooth &&
      cellular == other.cellular;

  static bool? _optionalBool(Object? value) => value is bool ? value : null;
}

Map<String, dynamic> withDraperTakPeerMetadata({
  required Map<String, dynamic> existing,
  required String deviceId,
  required DeviceConnectivity connectivity,
}) {
  return {
    ...existing,
    'draperTak': {
      'deviceId': deviceId,
      'connectivity': connectivity.toJson(),
    },
  };
}

DeviceConnectivity connectivityFromPeerMetadata(Object? appMetadata) {
  if (appMetadata is! Map) return const DeviceConnectivity.unknown();
  final connectivity = appMetadata['connectivity'];
  if (connectivity is! Map) return const DeviceConnectivity.unknown();
  return DeviceConnectivity.fromJson(
    connectivity.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    ),
  );
}

class MeshPeerStatus {
  const MeshPeerStatus({
    required this.deviceId,
    required this.deviceName,
    required this.os,
    required this.dittoSdkVersion,
    required this.connectedToDittoServer,
    required this.connections,
    required this.connectivity,
    this.peerKey = '',
    this.topologyConnections = const [],
    this.topologyPeers = const [],
    this.observedAt,
  });

  final String deviceId;
  final String deviceName;
  final String? os;
  final String? dittoSdkVersion;
  final bool connectedToDittoServer;
  final Set<MeshConnectionKind> connections;
  final DeviceConnectivity connectivity;
  final String peerKey;
  final List<MeshTopologyConnection> topologyConnections;
  final List<MeshTopologyPeerDescriptor> topologyPeers;
  final DateTime? observedAt;

  bool get hasPeerToPeerConnection => connections.any(
        (connection) =>
            connection == MeshConnectionKind.bluetooth ||
            connection == MeshConnectionKind.accessPoint ||
            connection == MeshConnectionKind.p2pWifi ||
            connection == MeshConnectionKind.webSocket,
      );

  Map<String, dynamic> toTelemetryJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'os': os,
        'dittoSdkVersion': dittoSdkVersion,
        'connectedToDittoServer': connectedToDittoServer,
        'connections':
            connections.map((connection) => connection.name).toList(),
        'connectivity': connectivity.toJson(),
        'peerKey': peerKey,
        'topologyConnections': topologyConnections
            .map((connection) => connection.toJson())
            .toList(),
        'topologyPeers': topologyPeers.map((peer) => peer.toJson()).toList(),
        'observedAt': observedAt?.millisecondsSinceEpoch,
      };

  factory MeshPeerStatus.fromTelemetryJson(Map<String, dynamic>? json) {
    if (json == null) return const MeshPeerStatus.unknown();
    final rawConnections = json['connections'];
    final connections = <MeshConnectionKind>{};
    if (rawConnections is Iterable) {
      for (final value in rawConnections) {
        for (final kind in MeshConnectionKind.values) {
          if (kind.name == value) connections.add(kind);
        }
      }
    }
    final rawConnectivity = json['connectivity'];
    final connectivity = rawConnectivity is Map
        ? DeviceConnectivity.fromJson(
            rawConnectivity.map<String, dynamic>(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : const DeviceConnectivity.unknown();
    final rawObservedAt = json['observedAt'];
    final topologyConnections = <MeshTopologyConnection>[];
    final rawTopologyConnections = json['topologyConnections'];
    if (rawTopologyConnections is Iterable) {
      for (final value in rawTopologyConnections) {
        if (value is Map) {
          final connection = MeshTopologyConnection.fromJson(
            value.map<String, dynamic>(
              (key, value) => MapEntry(key.toString(), value),
            ),
          );
          if (connection.id.isNotEmpty &&
              connection.peer1.isNotEmpty &&
              connection.peer2.isNotEmpty) {
            topologyConnections.add(connection);
          }
        }
      }
    }
    final topologyPeers = <MeshTopologyPeerDescriptor>[];
    final rawTopologyPeers = json['topologyPeers'];
    if (rawTopologyPeers is Iterable) {
      final seenPeerKeys = <String>{};
      for (final value in rawTopologyPeers) {
        if (value is Map) {
          final peer = MeshTopologyPeerDescriptor.fromJson(
            value.map<String, dynamic>(
              (key, value) => MapEntry(key.toString(), value),
            ),
          );
          if (peer.peerKey.isNotEmpty && seenPeerKeys.add(peer.peerKey)) {
            topologyPeers.add(peer);
          }
        }
      }
    }
    return MeshPeerStatus(
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Unknown device',
      os: json['os'] as String?,
      dittoSdkVersion: json['dittoSdkVersion'] as String?,
      connectedToDittoServer: json['connectedToDittoServer'] == true,
      connections: connections,
      connectivity: connectivity,
      peerKey: json['peerKey'] as String? ?? '',
      topologyConnections: topologyConnections,
      topologyPeers: topologyPeers,
      observedAt: rawObservedAt is num
          ? DateTime.fromMillisecondsSinceEpoch(
              rawObservedAt.toInt(),
              isUtc: true,
            )
          : null,
    );
  }

  const MeshPeerStatus.unknown()
      : deviceId = '',
        deviceName = 'Unknown device',
        os = null,
        dittoSdkVersion = null,
        connectedToDittoServer = false,
        connections = const {},
        connectivity = const DeviceConnectivity.unknown(),
        peerKey = '',
        topologyConnections = const [],
        topologyPeers = const [],
        observedAt = null;

  MeshPeerStatus observed(DateTime time) => MeshPeerStatus(
        deviceId: deviceId,
        deviceName: deviceName,
        os: os,
        dittoSdkVersion: dittoSdkVersion,
        connectedToDittoServer: connectedToDittoServer,
        connections: connections,
        connectivity: connectivity,
        peerKey: peerKey,
        topologyConnections: topologyConnections,
        topologyPeers: topologyPeers,
        observedAt: time,
      );

  bool hasSameDisplayedState(MeshPeerStatus other) =>
      deviceId == other.deviceId &&
      deviceName == other.deviceName &&
      os == other.os &&
      dittoSdkVersion == other.dittoSdkVersion &&
      connectedToDittoServer == other.connectedToDittoServer &&
      connections.length == other.connections.length &&
      connections.containsAll(other.connections) &&
      connectivity.hasSameLinks(other.connectivity) &&
      peerKey == other.peerKey &&
      _connectionsMatch(topologyConnections, other.topologyConnections) &&
      _peersMatch(topologyPeers, other.topologyPeers);

  bool hasSameState(MeshPeerStatus other) =>
      hasSameDisplayedState(other) && observedAt == other.observedAt;

  static bool _connectionsMatch(
    List<MeshTopologyConnection> first,
    List<MeshTopologyConnection> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!first[index].hasSameState(second[index])) return false;
    }
    return true;
  }

  static bool _peersMatch(
    List<MeshTopologyPeerDescriptor> first,
    List<MeshTopologyPeerDescriptor> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!first[index].hasSameState(second[index])) return false;
    }
    return true;
  }
}
