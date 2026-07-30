import '../models/mesh_peer_status.dart';
import '../models/user_presence.dart';

const liveMeshStatusMaxAge = Duration(seconds: 15);

class MeshTopologyUpdateTracker {
  Map<String, MeshPeerStatus> _displayedStatuses = const {};

  DateTime? lastUpdatedAt;

  bool record(
    Map<String, MeshPeerStatus> statuses, {
    required DateTime receivedAt,
  }) {
    if (meshStatusMapsHaveSameDisplayedState(_displayedStatuses, statuses)) {
      _displayedStatuses = Map.unmodifiable(statuses);
      return false;
    }
    _displayedStatuses = Map.unmodifiable(statuses);
    lastUpdatedAt = receivedAt;
    return true;
  }

  void reset() {
    _displayedStatuses = const {};
    lastUpdatedAt = null;
  }
}

Map<String, MeshPeerStatus> resolveMeshStatuses({
  required Iterable<UserPresence> people,
  required Map<String, MeshPeerStatus> directStatuses,
  required DateTime now,
  Duration maxAge = liveMeshStatusMaxAge,
}) {
  final resolved = <String, MeshPeerStatus>{...directStatuses};
  for (final person in people) {
    if (person.isDeleted || resolved.containsKey(person.id)) continue;
    final reported = person.liveMeshStatus;
    final observedAt = reported?.observedAt;
    if (reported == null ||
        observedAt == null ||
        reported.deviceId != person.id ||
        now.difference(observedAt.toUtc()) > maxAge ||
        observedAt.toUtc().isAfter(now.add(const Duration(seconds: 5)))) {
      continue;
    }
    resolved[person.id] = reported;
  }
  return resolved;
}

bool meshStatusMapsMatch(
  Map<String, MeshPeerStatus> first,
  Map<String, MeshPeerStatus> second,
) {
  if (first.length != second.length) return false;
  for (final entry in first.entries) {
    final other = second[entry.key];
    if (other == null || !entry.value.hasSameState(other)) return false;
  }
  return true;
}

bool meshStatusMapsHaveSameDisplayedState(
  Map<String, MeshPeerStatus> first,
  Map<String, MeshPeerStatus> second,
) {
  if (first.length != second.length) return false;
  for (final entry in first.entries) {
    final other = second[entry.key];
    if (other == null || !entry.value.hasSameDisplayedState(other)) {
      return false;
    }
  }
  return true;
}
