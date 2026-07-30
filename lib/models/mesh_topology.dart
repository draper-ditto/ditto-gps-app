import 'mesh_peer_status.dart';
import 'user_presence.dart';

const bigPeerTopologyNodeId = '__ditto_big_peer__';
const sdkPeerTopologyNodePrefix = '__ditto_sdk_peer__:';
const meshReconnectGracePeriod = Duration(seconds: 15);

String sdkPeerTopologyNodeId(String peerKey) =>
    '$sdkPeerTopologyNodePrefix$peerKey';

class MeshTopologyNode {
  const MeshTopologyNode({
    required this.id,
    required this.label,
    this.person,
    this.status,
    this.sdkPeer,
    this.isBigPeer = false,
  });

  final String id;
  final String label;
  final UserPresence? person;
  final MeshPeerStatus? status;
  final MeshTopologyPeerDescriptor? sdkPeer;
  final bool isBigPeer;

  bool get isSdkPeer => sdkPeer != null && person == null;
}

class MeshTopologyEdge {
  const MeshTopologyEdge({
    required this.id,
    required this.fromId,
    required this.toId,
    this.kind,
    this.isBigPeer = false,
    this.isReconnecting = false,
  });

  final String id;
  final String fromId;
  final String toId;
  final MeshConnectionKind? kind;
  final bool isBigPeer;
  final bool isReconnecting;

  MeshTopologyEdge reconnecting() => MeshTopologyEdge(
        id: id,
        fromId: fromId,
        toId: toId,
        kind: kind,
        isBigPeer: isBigPeer,
        isReconnecting: true,
      );
}

class MeshTopology {
  const MeshTopology({required this.nodes, required this.edges});

  final List<MeshTopologyNode> nodes;
  final List<MeshTopologyEdge> edges;
}

class MeshTopologyReconnectTracker {
  MeshTopologyReconnectTracker({
    this.gracePeriod = meshReconnectGracePeriod,
  });

  final Duration gracePeriod;
  Map<String, MeshTopologyEdge> _activeEdges = const {};
  Map<String, MeshTopologyNode> _knownNodes = const {};
  final Map<String, _ReconnectingEdge> _reconnectingEdges = {};

  DateTime? get nextExpiration {
    DateTime? earliest;
    for (final retained in _reconnectingEdges.values) {
      if (earliest == null || retained.expiresAt.isBefore(earliest)) {
        earliest = retained.expiresAt;
      }
    }
    return earliest;
  }

  MeshTopology update(MeshTopology current, {required DateTime now}) {
    final currentEdges = {for (final edge in current.edges) edge.id: edge};
    final currentNodes = {for (final node in current.nodes) node.id: node};

    if (gracePeriod > Duration.zero) {
      for (final entry in _activeEdges.entries) {
        if (currentEdges.containsKey(entry.key)) continue;
        _reconnectingEdges.putIfAbsent(
          entry.key,
          () => _ReconnectingEdge(
            edge: entry.value.reconnecting(),
            expiresAt: now.add(gracePeriod),
          ),
        );
      }
    }

    for (final edgeId in currentEdges.keys) {
      _reconnectingEdges.remove(edgeId);
    }
    _reconnectingEdges.removeWhere(
      (_, retained) => !retained.expiresAt.isAfter(now),
    );

    final displayedNodes = <String, MeshTopologyNode>{...currentNodes};
    for (final retained in _reconnectingEdges.values) {
      for (final nodeId in [retained.edge.fromId, retained.edge.toId]) {
        final knownNode = _knownNodes[nodeId];
        if (knownNode != null) {
          displayedNodes.putIfAbsent(nodeId, () => knownNode);
        }
      }
    }

    _activeEdges = currentEdges;
    _knownNodes = {..._knownNodes, ...currentNodes};
    return MeshTopology(
      nodes: displayedNodes.values.toList(growable: false),
      edges: [
        ...current.edges,
        ..._reconnectingEdges.values.map((retained) => retained.edge),
      ],
    );
  }

  void reset() {
    _activeEdges = const {};
    _knownNodes = const {};
    _reconnectingEdges.clear();
  }
}

class _ReconnectingEdge {
  const _ReconnectingEdge({required this.edge, required this.expiresAt});

  final MeshTopologyEdge edge;
  final DateTime expiresAt;
}

MeshTopology buildMeshTopology({
  required List<UserPresence> people,
  required Map<String, MeshPeerStatus> statuses,
}) {
  final nodes = <MeshTopologyNode>[
    const MeshTopologyNode(
      id: bigPeerTopologyNodeId,
      label: 'Big Peer',
      isBigPeer: true,
    ),
    ...people.map(
      (person) => MeshTopologyNode(
        id: person.id,
        label: person.username,
        person: person,
        status: statuses[person.id],
      ),
    ),
  ];
  final knownDeviceIds = people.map((person) => person.id).toSet();
  final deviceIdByPeerKey = <String, String>{};
  for (final entry in statuses.entries) {
    if (knownDeviceIds.contains(entry.key) && entry.value.peerKey.isNotEmpty) {
      deviceIdByPeerKey[entry.value.peerKey] = entry.key;
    }
  }

  final descriptorsByPeerKey = <String, MeshTopologyPeerDescriptor>{};
  for (final status in statuses.values) {
    for (final peer in status.topologyPeers) {
      if (peer.peerKey.isEmpty) continue;
      final existing = descriptorsByPeerKey[peer.peerKey];
      if (existing == null ||
          (!existing.connectedToDittoServer && peer.connectedToDittoServer) ||
          (existing.deviceName.isEmpty && peer.deviceName.isNotEmpty)) {
        descriptorsByPeerKey[peer.peerKey] = peer;
      }
    }
  }

  final externalPeerKeys = descriptorsByPeerKey.keys
      .where((peerKey) => !deviceIdByPeerKey.containsKey(peerKey))
      .toSet();
  for (final status in statuses.values) {
    for (final connection in status.topologyConnections) {
      for (final peerKey in [connection.peer1, connection.peer2]) {
        if (peerKey.isNotEmpty && !deviceIdByPeerKey.containsKey(peerKey)) {
          externalPeerKeys.add(peerKey);
        }
      }
    }
  }
  final orderedExternalPeerKeys = externalPeerKeys.toList()
    ..sort((first, second) => first.compareTo(second));
  for (final peerKey in orderedExternalPeerKeys) {
    final descriptor = descriptorsByPeerKey[peerKey] ??
        MeshTopologyPeerDescriptor(
          peerKey: peerKey,
          deviceName: _fallbackSdkPeerLabel(peerKey),
          connectedToDittoServer: false,
        );
    nodes.add(
      MeshTopologyNode(
        id: sdkPeerTopologyNodeId(peerKey),
        label: descriptor.deviceName.isEmpty
            ? _fallbackSdkPeerLabel(peerKey)
            : descriptor.deviceName,
        sdkPeer: descriptor,
      ),
    );
  }

  final edges = <MeshTopologyEdge>[];
  for (final entry in statuses.entries) {
    if (knownDeviceIds.contains(entry.key) &&
        entry.value.connectedToDittoServer) {
      edges.add(
        MeshTopologyEdge(
          id: 'big-peer:${entry.key}',
          fromId: bigPeerTopologyNodeId,
          toId: entry.key,
          isBigPeer: true,
        ),
      );
    }
  }
  for (final peerKey in orderedExternalPeerKeys) {
    final descriptor = descriptorsByPeerKey[peerKey];
    if (descriptor?.connectedToDittoServer ?? false) {
      edges.add(
        MeshTopologyEdge(
          id: 'big-peer:${sdkPeerTopologyNodeId(peerKey)}',
          fromId: bigPeerTopologyNodeId,
          toId: sdkPeerTopologyNodeId(peerKey),
          isBigPeer: true,
        ),
      );
    }
  }

  final seenConnectionIds = <String>{};
  for (final status in statuses.values) {
    for (final connection in status.topologyConnections) {
      if (connection.peer1.isEmpty || connection.peer2.isEmpty) continue;
      final fromId = deviceIdByPeerKey[connection.peer1] ??
          sdkPeerTopologyNodeId(connection.peer1);
      final toId = deviceIdByPeerKey[connection.peer2] ??
          sdkPeerTopologyNodeId(connection.peer2);
      if (fromId == toId) continue;
      final normalizedId = connection.id.isNotEmpty
          ? connection.id
          : '${connection.peer1}:${connection.peer2}:${connection.kind.name}';
      if (!seenConnectionIds.add(normalizedId)) continue;
      edges.add(
        MeshTopologyEdge(
          id: normalizedId,
          fromId: fromId,
          toId: toId,
          kind: connection.kind,
        ),
      );
    }
  }

  return MeshTopology(nodes: nodes, edges: edges);
}

String _fallbackSdkPeerLabel(String peerKey) {
  final suffix =
      peerKey.length <= 8 ? peerKey : peerKey.substring(peerKey.length - 8);
  return 'Unidentified SDK peer $suffix';
}
