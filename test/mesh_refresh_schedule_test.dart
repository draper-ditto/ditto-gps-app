import 'package:ditto_gps/services/mesh_refresh_schedule.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('default mesh refresh timing', () {
    test('observes connectivity within one second', () {
      expect(
        defaultMeshRefreshSchedule.observationInterval,
        const Duration(seconds: 1),
      );
      expect(
        defaultMeshRefreshSchedule.observationInterval,
        lessThan(defaultMeshRefreshSchedule.periodicHeartbeatInterval),
      );
    });

    test('publishes a steady heartbeat every three observation ticks', () {
      final heartbeatTicks = [
        for (var tick = 1; tick <= 12; tick++)
          if (defaultMeshRefreshSchedule.shouldPublishPeriodicHeartbeat(tick))
            tick,
      ];

      expect(heartbeatTicks, [3, 6, 9, 12]);
      expect(
        defaultMeshRefreshSchedule.periodicHeartbeatInterval,
        const Duration(seconds: 3),
      );
    });

    test('never publishes a periodic heartbeat before the first poll', () {
      expect(
        defaultMeshRefreshSchedule.shouldPublishPeriodicHeartbeat(-1),
        isFalse,
      );
      expect(
        defaultMeshRefreshSchedule.shouldPublishPeriodicHeartbeat(0),
        isFalse,
      );
    });

    test('supports heartbeat intervals that are not exact poll multiples', () {
      const schedule = MeshRefreshSchedule(
        observationInterval: Duration(milliseconds: 700),
        periodicHeartbeatInterval: Duration(seconds: 2),
      );
      final heartbeatTicks = [
        for (var tick = 1; tick <= 9; tick++)
          if (schedule.shouldPublishPeriodicHeartbeat(tick)) tick,
      ];

      expect(heartbeatTicks, [3, 6, 9]);
    });
  });

  group('topology-change heartbeat debounce', () {
    test('publishes 200 milliseconds after a topology change', () {
      fakeAsync((async) {
        var publications = 0;
        final debouncer = MeshHeartbeatDebouncer();

        debouncer.schedule(() => publications += 1);
        async.elapse(const Duration(milliseconds: 199));
        expect(publications, 0);

        async.elapse(const Duration(milliseconds: 1));
        expect(publications, 1);
      });
    });

    test('coalesces rapid graph changes into one heartbeat', () {
      fakeAsync((async) {
        var publications = 0;
        final debouncer = MeshHeartbeatDebouncer();

        debouncer.schedule(() => publications += 1);
        async.elapse(const Duration(milliseconds: 100));
        debouncer.schedule(() => publications += 1);
        async.elapse(const Duration(milliseconds: 100));
        debouncer.schedule(() => publications += 1);

        async.elapse(const Duration(milliseconds: 199));
        expect(publications, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(publications, 1);
      });
    });

    test('cancel prevents a pending heartbeat after shutdown', () {
      fakeAsync((async) {
        var publications = 0;
        final debouncer = MeshHeartbeatDebouncer();

        debouncer.schedule(() => publications += 1);
        debouncer.cancel();
        async.elapse(const Duration(seconds: 1));

        expect(publications, 0);
      });
    });
  });
}
