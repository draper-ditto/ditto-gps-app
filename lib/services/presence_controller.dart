import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/user_presence.dart';

enum SyncState { connecting, authenticating, connected, saving, error }

class PresenceController extends ChangeNotifier {
  static const _collection = 'user_presence';
  static const _deviceIdKey = 'presence_device_id';
  static const _webDevelopmentProvider = '__playgroundProvider';

  Ditto? _ditto;
  StoreObserver? _observer;
  SyncSubscription? _subscription;
  String? _deviceId;

  SyncState syncState = SyncState.connecting;
  String? errorMessage;
  List<UserPresence> people = const [];

  bool get isAuthenticated => _ditto?.auth.status.isAuthenticated ?? false;

  UserPresence? get currentUser {
    final id = _deviceId;
    if (id == null) return null;
    for (final person in people) {
      if (person.id == id) return person;
    }
    return null;
  }

  Future<void> initialize() async {
    syncState = SyncState.connecting;
    errorMessage = null;
    notifyListeners();

    try {
      await _closeDitto();

      final preferences = await SharedPreferences.getInstance();
      _deviceId = preferences.getString(_deviceIdKey);
      if (_deviceId == null) {
        _deviceId = const Uuid().v4();
        await preferences.setString(_deviceIdKey, _deviceId!);
      }

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
      ditto.deviceName = 'Waypoint-${_deviceId!.substring(0, 8)}';

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

    syncState = SyncState.saving;
    errorMessage = null;
    notifyListeners();
    try {
      final presence = UserPresence(
        id: deviceId,
        username: username.trim(),
        latitude: latitude,
        longitude: longitude,
        status: status.trim(),
        updatedAt: DateTime.now().toUtc(),
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

  void _handlePresenceChange(QueryResult result) {
    people = result.items
        .map((item) => UserPresence.fromJson(item.value))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
  }

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
