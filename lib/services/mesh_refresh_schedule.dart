import 'dart:async';

const meshObservationInterval = Duration(seconds: 1);
const meshPeriodicHeartbeatInterval = Duration(seconds: 3);
const meshEventHeartbeatDelay = Duration(milliseconds: 200);

class MeshRefreshSchedule {
  const MeshRefreshSchedule({
    this.observationInterval = meshObservationInterval,
    this.periodicHeartbeatInterval = meshPeriodicHeartbeatInterval,
    this.eventHeartbeatDelay = meshEventHeartbeatDelay,
  });

  final Duration observationInterval;
  final Duration periodicHeartbeatInterval;
  final Duration eventHeartbeatDelay;

  bool shouldPublishPeriodicHeartbeat(int pollCount) {
    if (pollCount <= 0) return false;
    final elapsedMilliseconds = pollCount * observationInterval.inMilliseconds;
    final previousElapsedMilliseconds =
        (pollCount - 1) * observationInterval.inMilliseconds;
    return elapsedMilliseconds ~/ periodicHeartbeatInterval.inMilliseconds >
        previousElapsedMilliseconds ~/ periodicHeartbeatInterval.inMilliseconds;
  }
}

const defaultMeshRefreshSchedule = MeshRefreshSchedule();

class MeshHeartbeatDebouncer {
  MeshHeartbeatDebouncer({
    this.delay = meshEventHeartbeatDelay,
  });

  final Duration delay;
  Timer? _timer;

  void schedule(void Function() publish) {
    _timer?.cancel();
    _timer = Timer(delay, publish);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
