import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/mesh_peer_status.dart';
import '../models/user_presence.dart';
import 'database_reset.dart';
import 'device_identity.dart';
import 'mesh_refresh_schedule.dart';
import 'mesh_status_resolver.dart';

enum SyncState { connecting, authenticating, connected, saving, error }

class PresenceController extends ChangeNotifier {
  static const _collection = 'user_presence';
  static const _webDevelopmentProvider = '__playgroundProvider';

  Ditto? _ditto;
  StoreObserver? _observer;
  SyncSubscription? _subscription;
  PresenceObserver? _presenceObserver;
  PresenceGraph? _presenceGraph;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _connectivityPoller;
  final MeshHeartbeatDebouncer _heartbeatDebouncer = MeshHeartbeatDebouncer();
  final MeshTopologyUpdateTracker _topologyUpdateTracker =
      MeshTopologyUpdateTracker();
  int _connectivityPollCount = 0;
  DeviceConnectivity _localConnectivity = const DeviceConnectivity.unknown();
  MeshPeerStatus? _localMeshStatus;
  Map<String, MeshPeerStatus> _directMeshStatusByDeviceId = const {};
  bool _refreshingConnectivity = false;
  bool _publishingConnectionHeartbeat = false;
  String? _deviceId;
  String? _originStoredDeviceId;
  SharedPreferences? _preferences;

  SyncState syncState = SyncState.connecting;
  String? errorMessage;
  List<UserPresence> people = const [];
  Map<String, MeshPeerStatus> meshStatusByDeviceId = const {};
  DateTime? get meshTopologyUpdatedAt => _topologyUpdateTracker.lastUpdatedAt;

  bool get isAuthenticated => _ditto?.auth.status.isAuthenticated ?? false;

  bool get canResetDatabase =>
      _ditto != null &&
      isAuthenticated &&
      (_ditto?.sync.isActive ?? false) &&
      syncState != SyncState.saving;

  bool get canRemovePresence => canResetDatabase;

  UserPresence? get currentUser {
    final id = _deviceId;
    if (id == null) return null;
    for (final person in people) {
      if (person.id == id) return person;
    }
    return null;
  }

  String? validateUsername(String? value) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) return 'Enter a username';
    final normalized = username.toLowerCase();
    final duplicate = people.any(
      (person) =>
          person.id != _deviceId &&
          person.username.trim().toLowerCase() == normalized,
    );
    return duplicate ? 'That username is already in use' : null;
  }

  Future<void> initialize() async {
    syncState = SyncState.connecting;
    errorMessage = null;
    notifyListeners();

    try {
      await _closeDitto();

      final preferences = await SharedPreferences.getInstance();
      _preferences = preferences;
      final identity = await loadDeviceIdentitySeed(preferences);
      _deviceId = identity.deviceId;
      _originStoredDeviceId = identity.originStoredId;

      await _requestPermissions();
      final appConfig = await AppConfig.load();

      await Ditto.init();
      if (kDebugMode) {
        DittoLogger.minimumLogLevel = LogLevel.debug;
        DittoLogger.customLogCallback = (level, message) {
          debugPrint('[Ditto ${level.name}] $message');
        };
      }

      final config = DittoConfig(
        databaseID: appConfig.databaseId,
        connect: DittoConfigConnectServer(url: appConfig.serverUrl),
      );
      final ditto = await Ditto.open(config);
      _ditto = ditto;
      ditto.deviceName = 'DraperTAK-${_deviceId!.substring(0, 8)}';
      await _startConnectivityMonitoring(ditto);
      _presenceObserver = ditto.presence.observe(_handlePresenceGraph);

      syncState = SyncState.authenticating;
      notifyListeners();
      await _authenticate(ditto, appConfig.playgroundToken);

      await ditto.auth.setExpirationHandler((activeDitto, _) {
        unawaited(
          _authenticate(activeDitto, appConfig.playgroundToken).catchError((
            Object error,
          ) {
            if (identical(_ditto, activeDitto)) {
              syncState = SyncState.error;
              errorMessage = 'Ditto authentication failed: $error';
              notifyListeners();
            }
          }),
        );
      });

      await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = false');
      _subscription = ditto.sync.registerSubscription(
        'SELECT * FROM $_collection',
      );
      _observer = ditto.store.registerObserver(
        'SELECT * FROM $_collection',
        onChange: _handlePresenceChange,
      );
      ditto.sync.start();

      syncState = SyncState.connected;
      notifyListeners();
    } catch (error) {
      syncState = SyncState.error;
      errorMessage = 'Ditto setup failed: $error';
      notifyListeners();
    }
  }

  Future<void> save({
    required String username,
    required double latitude,
    required double longitude,
    required String status,
  }) async {
    final ditto = _ditto;
    final deviceId = _deviceId;
    if (ditto == null ||
        deviceId == null ||
        !ditto.auth.status.isAuthenticated ||
        !ditto.sync.isActive) {
      throw StateError('Ditto is not authenticated and syncing yet.');
    }

    final cleanUsername = username.trim();
    final usernameError = validateUsername(cleanUsername);
    if (usernameError != null) {
      errorMessage = usernameError;
      notifyListeners();
      throw StateError(usernameError);
    }
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      const message = 'Enter a latitude between -90 and 90.';
      errorMessage = message;
      notifyListeners();
      throw StateError(message);
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      const message = 'Enter a longitude between -180 and 180.';
      errorMessage = message;
      notifyListeners();
      throw StateError(message);
    }

    final latest = await ditto.store.execute('SELECT * FROM $_collection');
    final normalizedUsername = cleanUsername.toLowerCase();
    final duplicate = latest.items.any((item) {
      final value = item.value;
      return value['isDeleted'] != true &&
          value['_id']?.toString() != deviceId &&
          (value['username'] as String?)?.trim().toLowerCase() ==
              normalizedUsername;
    });
    if (duplicate) {
      const message = 'That username is already in use.';
      errorMessage = message;
      notifyListeners();
      throw StateError(message);
    }

    syncState = SyncState.saving;
    errorMessage = null;
    notifyListeners();
    try {
      final presence = UserPresence(
        id: deviceId,
        username: cleanUsername,
        latitude: latitude,
        longitude: longitude,
        status: status.trim(),
        updatedAt: DateTime.now().toUtc(),
        liveMeshStatus: _localMeshStatus?.observed(DateTime.now().toUtc()),
      );
      await ditto.store.execute(
        '''
        INSERT INTO $_collection DOCUMENTS (:presence)
        ON ID CONFLICT DO UPDATE_LOCAL_DIFF
        ''',
        arguments: {'presence': presence.toJson()},
      );
      syncState = SyncState.connected;
      notifyListeners();
    } catch (error) {
      syncState = SyncState.error;
      errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removePresence(String id) async {
    final ditto = _ditto;
    final cleanId = id.trim();
    if (ditto == null ||
        !ditto.auth.status.isAuthenticated ||
        !ditto.sync.isActive) {
      throw StateError('Ditto is not authenticated and syncing yet.');
    }
    if (cleanId.isEmpty) throw ArgumentError.value(id, 'id');

    syncState = SyncState.saving;
    errorMessage = null;
    notifyListeners();
    try {
      await ditto.store.execute(
        '''
        UPDATE $_collection
        SET isDeleted = true, updatedAt = :updatedAt
        WHERE _id = :id
        ''',
        arguments: {
          'id': cleanId,
          'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
      );
      syncState = SyncState.connected;
      notifyListeners();
    } catch (error) {
      syncState = SyncState.error;
      errorMessage = 'Unable to remove the waypoint from Live Mesh: $error';
      notifyListeners();
      rethrow;
    }
  }

  Future<int> resetDatabase() async {
    final ditto = _ditto;
    if (ditto == null ||
        !ditto.auth.status.isAuthenticated ||
        !ditto.sync.isActive) {
      throw StateError('Ditto is not authenticated and syncing yet.');
    }

    syncState = SyncState.saving;
    errorMessage = null;
    notifyListeners();
    try {
      final deleted = await deleteAllPresenceDocuments(
        loadIds: () async {
          final result = await ditto.store.execute(
            'SELECT _id FROM $_collection',
          );
          return result.items.map((item) => item.value['_id']?.toString());
        },
        deleteById: (id) async {
          await ditto.store.execute(
            'DELETE FROM $_collection WHERE _id = :id',
            arguments: {'id': id},
          );
        },
      );
      syncState = SyncState.connected;
      notifyListeners();
      return deleted;
    } catch (error) {
      syncState = SyncState.error;
      errorMessage = 'Unable to reset the Ditto database: $error';
      notifyListeners();
      rethrow;
    }
  }

  void _handlePresenceChange(QueryResult result) {
    final synchronizedPeople =
        result.items.map((item) => UserPresence.fromJson(item.value)).toList();
    _recoverSynchronizedIdentity(synchronizedPeople);
    people = synchronizedPeople.where((person) => !person.isDeleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final graph = _presenceGraph;
    if (graph != null) {
      _handlePresenceGraph(graph);
    } else {
      _refreshResolvedMeshStatuses();
      notifyListeners();
    }
  }

  void _recoverSynchronizedIdentity(List<UserPresence> synchronizedPeople) {
    final currentId = _deviceId;
    if (currentId == null) return;
    final activeDeviceIds = synchronizedPeople
        .where((person) => !person.isDeleted)
        .map((person) => person.id)
        .toSet();
    final recoveredId = recoverSyncedDeviceIdentity(
      currentId: currentId,
      originStoredId: _originStoredDeviceId,
      activeDeviceIds: activeDeviceIds,
    );
    if (recoveredId == currentId) {
      if (activeDeviceIds.contains(currentId) &&
          _originStoredDeviceId != currentId) {
        _originStoredDeviceId = currentId;
        final preferences = _preferences;
        if (preferences != null) {
          unawaited(persistDeviceIdentity(preferences, currentId));
        }
      }
      return;
    }

    _deviceId = recoveredId;
    _originStoredDeviceId = recoveredId;
    final preferences = _preferences;
    if (preferences != null) {
      unawaited(persistDeviceIdentity(preferences, recoveredId));
    }
    final ditto = _ditto;
    if (ditto != null) {
      ditto.deviceName = 'DraperTAK-${recoveredId.substring(0, 8)}';
      ditto.presence.peerMetadata = withDraperTakPeerMetadata(
        existing: Map<String, dynamic>.from(ditto.presence.peerMetadata),
        deviceId: recoveredId,
        connectivity: _localConnectivity,
      );
    }
  }

  Future<void> _startConnectivityMonitoring(Ditto ditto) async {
    await _publishLocalConnectivity(ditto);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
          (_) => unawaited(_handleConnectivitySignal(ditto)),
        );
    _connectivityPoller = Timer.periodic(
      defaultMeshRefreshSchedule.observationInterval,
      (_) {
        _connectivityPollCount += 1;
        unawaited(
          _refreshConnectivityCycle(
            ditto,
            publishHeartbeat: defaultMeshRefreshSchedule
                .shouldPublishPeriodicHeartbeat(_connectivityPollCount),
          ),
        );
      },
    );
  }

  Future<void> _handleConnectivitySignal(Ditto ditto) async {
    await _publishLocalConnectivity(ditto);
    _refreshPresenceGraph(ditto);
  }

  Future<void> _refreshConnectivityCycle(
    Ditto ditto, {
    required bool publishHeartbeat,
  }) async {
    await _publishLocalConnectivity(ditto);
    _refreshPresenceGraph(ditto);
    if (publishHeartbeat) {
      await _publishConnectionHeartbeat(ditto);
    }
  }

  Future<bool> _publishLocalConnectivity(Ditto ditto) async {
    if (_refreshingConnectivity || !identical(_ditto, ditto)) return false;
    _refreshingConnectivity = true;
    try {
      bool? wifi;
      bool? cellular;
      try {
        final links = await Connectivity().checkConnectivity();
        wifi = links.contains(ConnectivityResult.wifi);
        cellular = links.contains(ConnectivityResult.mobile);
      } catch (_) {
        wifi = null;
        cellular = null;
      }

      bool? bluetooth;
      final platform = Ditto.currentPlatform;
      if (platform == SupportedPlatform.android ||
          platform == SupportedPlatform.ios) {
        try {
          final serviceStatus = await Permission.bluetooth.serviceStatus;
          bluetooth =
              serviceStatus.isNotApplicable ? null : serviceStatus.isEnabled;
        } catch (_) {
          bluetooth = null;
        }
      }

      final next = DeviceConnectivity(
        wifi: wifi,
        bluetooth: bluetooth,
        cellular: cellular,
        observedAt: DateTime.now().toUtc(),
      );
      if (_localConnectivity.hasSameLinks(next)) return false;
      _localConnectivity = next;

      ditto.presence.peerMetadata = withDraperTakPeerMetadata(
        existing: Map<String, dynamic>.from(ditto.presence.peerMetadata),
        deviceId: _deviceId!,
        connectivity: next,
      );
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Connectivity] Unable to publish device status: $error');
      }
      return false;
    } finally {
      _refreshingConnectivity = false;
    }
  }

  void _handlePresenceGraph(PresenceGraph graph) {
    _presenceGraph = graph;
    final previousDirectStatuses = _directMeshStatusByDeviceId;
    final statuses = <String, MeshPeerStatus>{};
    final peers = [graph.localPeer, ...graph.remotePeers];
    final topologyPeersByKey = <String, MeshTopologyPeerDescriptor>{};
    for (final peer in peers) {
      if (peer.peerKey.isEmpty) continue;
      topologyPeersByKey[peer.peerKey] = MeshTopologyPeerDescriptor(
        peerKey: peer.peerKey,
        deviceName: peer.deviceName,
        os: peer.os,
        dittoSdkVersion: peer.dittoSdkVersion,
        connectedToDittoServer: peer.isConnectedToDittoServer,
      );
    }
    final topologyPeers = topologyPeersByKey.values.toList(growable: false);

    for (final peer in peers) {
      final deviceId = _deviceIdForPeer(peer);
      if (deviceId == null) continue;
      final appMetadata = peer.peerMetadata['draperTak'];
      final metadata = appMetadata is Map
          ? appMetadata.map<String, dynamic>(
              (key, value) => MapEntry(key.toString(), value),
            )
          : const <String, dynamic>{};
      final connectivity = connectivityFromPeerMetadata(metadata);

      final status = MeshPeerStatus(
        deviceId: deviceId,
        deviceName: peer.deviceName,
        os: peer.os,
        dittoSdkVersion: peer.dittoSdkVersion,
        connectedToDittoServer: peer.isConnectedToDittoServer,
        connections: peer.connections
            .map((connection) => _meshConnectionKind(connection.connectionType))
            .toSet(),
        connectivity: connectivity,
        peerKey: peer.peerKey,
        topologyConnections: peer.connections
            .map(
              (connection) => MeshTopologyConnection(
                id: connection.id,
                peer1: connection.peer1,
                peer2: connection.peer2,
                kind: _meshConnectionKind(connection.connectionType),
              ),
            )
            .toList(),
        topologyPeers: topologyPeers,
        observedAt: DateTime.now().toUtc(),
      );
      statuses[deviceId] = _preferConnectedStatus(statuses[deviceId], status);
      if (identical(peer, graph.localPeer)) _localMeshStatus = status;
    }
    _directMeshStatusByDeviceId = statuses;
    final displayedTopologyChanged =
        !meshStatusMapsHaveSameDisplayedState(previousDirectStatuses, statuses);
    _refreshResolvedMeshStatuses();
    notifyListeners();
    final ditto = _ditto;
    if (displayedTopologyChanged && ditto != null) {
      _scheduleConnectionHeartbeat(ditto);
    }
  }

  MeshPeerStatus _preferConnectedStatus(
    MeshPeerStatus? existing,
    MeshPeerStatus candidate,
  ) {
    if (existing == null) return candidate;
    final existingScore = (existing.connectedToDittoServer ? 1 : 0) +
        (existing.hasPeerToPeerConnection ? 1 : 0);
    final candidateScore = (candidate.connectedToDittoServer ? 1 : 0) +
        (candidate.hasPeerToPeerConnection ? 1 : 0);
    return candidateScore >= existingScore ? candidate : existing;
  }

  void _refreshResolvedMeshStatuses() {
    final now = DateTime.now().toUtc();
    final next = resolveMeshStatuses(
      people: people,
      directStatuses: _directMeshStatusByDeviceId,
      now: now,
    );
    _topologyUpdateTracker.record(next, receivedAt: now);
    if (!meshStatusMapsMatch(meshStatusByDeviceId, next)) {
      meshStatusByDeviceId = next;
    }
  }

  void _refreshPresenceGraph(Ditto ditto) {
    if (!identical(_ditto, ditto)) return;
    try {
      _handlePresenceGraph(ditto.presence.graph);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Presence] Unable to refresh the live mesh graph: $error');
      }
    }
  }

  Future<void> _publishConnectionHeartbeat(Ditto ditto) async {
    final localStatus = _localMeshStatus;
    final deviceId = _deviceId;
    if (_publishingConnectionHeartbeat ||
        !identical(_ditto, ditto) ||
        localStatus == null ||
        deviceId == null ||
        currentUser == null ||
        !ditto.auth.status.isAuthenticated ||
        !ditto.sync.isActive) {
      return;
    }

    _publishingConnectionHeartbeat = true;
    try {
      final heartbeat = localStatus.observed(DateTime.now().toUtc());
      _localMeshStatus = heartbeat;
      await ditto.store.execute(
        '''
        UPDATE $_collection
        SET liveMeshStatus = :liveMeshStatus
        WHERE _id = :id
        ''',
        arguments: {
          'id': deviceId,
          'liveMeshStatus': heartbeat.toTelemetryJson(),
        },
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Presence] Unable to publish connection heartbeat: $error');
      }
    } finally {
      _publishingConnectionHeartbeat = false;
    }
  }

  void _scheduleConnectionHeartbeat(Ditto ditto) {
    _heartbeatDebouncer.schedule(
      () => unawaited(_publishConnectionHeartbeat(ditto)),
    );
  }

  String? _deviceIdForPeer(Peer peer) {
    final appMetadata = peer.peerMetadata['draperTak'];
    if (appMetadata is Map) {
      final id = appMetadata['deviceId'];
      if (id is String && id.isNotEmpty) return id;
    }

    const prefix = 'DraperTAK-';
    if (!peer.deviceName.startsWith(prefix)) return null;
    final shortId = peer.deviceName.substring(prefix.length);
    if (_deviceId?.startsWith(shortId) ?? false) return _deviceId;
    for (final person in people) {
      if (person.id.startsWith(shortId)) return person.id;
    }
    return null;
  }

  MeshConnectionKind _meshConnectionKind(ConnectionType type) => switch (type) {
        ConnectionType.bluetooth => MeshConnectionKind.bluetooth,
        ConnectionType.accessPoint => MeshConnectionKind.accessPoint,
        ConnectionType.p2pWifi => MeshConnectionKind.p2pWifi,
        ConnectionType.webSocket => MeshConnectionKind.webSocket,
      };

  Future<void> _authenticate(Ditto ditto, String token) async {
    final response = await ditto.auth.login(
      token: token,
      // ditto_live 5.0.2's web binding incorrectly converts the SDK's static
      // const provider string as an owned C string. Use the equivalent provider
      // identifier on web until that binding is corrected upstream.
      provider:
          kIsWeb ? _webDevelopmentProvider : Authenticator.developmentProvider,
    );
    if (response.exception != null) throw response.exception!;
    if (!ditto.auth.status.isAuthenticated) {
      throw StateError('Ditto login completed without authentication.');
    }
    if (kDebugMode) {
      debugPrint(
        '[Ditto auth] Authenticated as ${ditto.auth.status.userID ?? 'unknown user'}',
      );
    }
  }

  Future<void> _closeDitto() async {
    _connectivityPoller?.cancel();
    _connectivityPoller = null;
    _heartbeatDebouncer.cancel();
    _connectivityPollCount = 0;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _presenceObserver?.stop();
    _presenceObserver = null;
    _presenceGraph = null;
    _directMeshStatusByDeviceId = const {};
    _localMeshStatus = null;
    meshStatusByDeviceId = const {};
    _topologyUpdateTracker.reset();
    _localConnectivity = const DeviceConnectivity.unknown();
    _refreshingConnectivity = false;
    _publishingConnectionHeartbeat = false;
    _observer?.cancel();
    _observer = null;
    _subscription?.cancel();
    _subscription = null;

    final ditto = _ditto;
    _ditto = null;
    if (ditto == null) return;

    ditto.sync.stop();
    await ditto.auth.setExpirationHandler(null);
    await ditto.close();
  }

  Future<void> _requestPermissions() async {
    final platform = Ditto.currentPlatform;
    if (platform == SupportedPlatform.android ||
        platform == SupportedPlatform.ios) {
      await [
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.bluetoothScan,
        Permission.nearbyWifiDevices,
      ].request();
    }
  }

  @override
  void dispose() {
    unawaited(_closeDitto());
    super.dispose();
  }
}
