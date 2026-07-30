import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mesh_peer_status.dart';
import '../models/mesh_topology.dart';
import '../models/user_presence.dart';
import '../services/current_location_service.dart';
import '../services/location_permission_flow.dart';
import '../services/presence_controller.dart';
import 'admin_panel.dart';
import 'live_mesh_topology.dart';

class PresencePage extends StatefulWidget {
  const PresencePage({super.key});

  @override
  State<PresencePage> createState() => _PresencePageState();
}

class _PresencePageState extends State<PresencePage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _status = TextEditingController();
  late final PresenceController _controller;
  late final LocationPermissionFlow _locationPermissionFlow;
  late final CurrentLocationService _currentLocationService;
  bool _didHydrateForm = false;
  bool _isLocating = false;
  bool _isResettingDatabase = false;
  final Set<String> _deletingPresenceIds = {};
  _AppTab _selectedTab = _AppTab.home;
  String? _locationError;
  _LocationRecoveryTarget? _locationRecoveryTarget;

  @override
  void initState() {
    super.initState();
    _locationPermissionFlow = LocationPermissionFlow.geolocator();
    _currentLocationService = CurrentLocationService.geolocator();
    _controller = PresenceController()..addListener(_onControllerChanged);
    _controller.initialize();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final currentUser = _controller.currentUser;
    if (!_didHydrateForm && currentUser != null) {
      _username.text = currentUser.username;
      _latitude.text = currentUser.latitude.toStringAsFixed(6);
      _longitude.text = currentUser.longitude.toStringAsFixed(6);
      _status.text = currentUser.status;
      _didHydrateForm = true;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _username.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _status.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;
    try {
      await _controller.save(
        username: _username.text,
        latitude: double.parse(_latitude.text),
        longitude: double.parse(_longitude.text),
        status: _status.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Waypoint saved. Ditto sync is active.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // The controller exposes the useful error inline.
    }
  }

  Future<int> _resetDatabase() async {
    setState(() => _isResettingDatabase = true);
    try {
      final deleted = await _controller.resetDatabase();
      _username.clear();
      _latitude.clear();
      _longitude.clear();
      _status.clear();
      _didHydrateForm = false;
      _locationError = null;
      _locationRecoveryTarget = null;
      return deleted;
    } finally {
      if (mounted) setState(() => _isResettingDatabase = false);
    }
  }

  Future<void> _removePresence(UserPresence person) async {
    setState(() => _deletingPresenceIds.add(person.id));
    try {
      await _controller.removePresence(person.id);
    } finally {
      if (mounted) {
        setState(() => _deletingPresenceIds.remove(person.id));
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
      _locationRecoveryTarget = null;
    });

    try {
      final permission = await _requestLocationPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationError =
              'Location permission was not granted. Tap Retry to ask again, '
              'or enter coordinates manually.';
          _locationRecoveryTarget = null;
        });
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = _blockedLocationInstructions;
          _locationRecoveryTarget = _LocationRecoveryTarget.appPermission;
        });
        return;
      }

      final fix = await _currentLocationService.locate();
      if (!mounted) return;

      _latitude.text = fix.position.latitude.toStringAsFixed(6);
      _longitude.text = fix.position.longitude.toStringAsFixed(6);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fix.isLastKnown
                ? 'A last-known location was added. Verify it before saving.'
                : 'Current coordinates added to the form.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on CurrentLocationUnavailableException catch (error) {
      if (!mounted) return;
      if (!error.serviceReportedEnabled) {
        final instructions = locationServicesDisabledInstructions(
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
        );
        setState(() {
          _locationError = instructions;
          _locationRecoveryTarget = _LocationRecoveryTarget.locationServices;
        });
        await _showLocationServicesDisabledDialog(instructions);
      } else {
        setState(() {
          _locationError = locationUnavailableInstructions(
            isWeb: kIsWeb,
            platform: defaultTargetPlatform,
            error: error,
          );
          _locationRecoveryTarget = _LocationRecoveryTarget.locationServices;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationError = locationUnavailableInstructions(
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
          error: error,
        );
        _locationRecoveryTarget = _LocationRecoveryTarget.locationServices;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  Future<LocationPermission> _requestLocationPermission() async {
    return _locationPermissionFlow.request(
      onDenied: _showLocationPermissionDeniedDialog,
      onBlocked: _showLocationPermissionBlockedDialog,
    );
  }

  Future<bool> _showLocationPermissionDeniedDialog() async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Allow location access?'),
            content: const Text(
              'Draper TAK uses your location only when you ask it to fill in '
              'your current coordinates.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Try again'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showLocationPermissionBlockedDialog() async {
    if (!mounted) return;
    final canOpenAppSettings = canOpenLocationAppSettings(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location access is blocked'),
        content: Text(_blockedLocationInstructions),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(canOpenAppSettings ? 'Not now' : 'OK'),
          ),
          if (canOpenAppSettings)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open settings'),
            ),
        ],
      ),
    );

    if (openSettings == true) {
      await _openLocationAppSettings();
    }
  }

  Future<void> _showLocationServicesDisabledDialog(String instructions) async {
    if (!mounted) return;
    final canOpenSettings = canOpenLocationServiceSettings(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => buildLocationServicesDialogForTesting(
        instructions: instructions,
        canOpenSettings: canOpenSettings,
        onClose: () => Navigator.pop(context, false),
        onOpenSettings: () => Navigator.pop(context, true),
      ),
    );
    if (openSettings == true) await _openLocationServiceSettings();
  }

  Future<void> _openLocationAppSettings() async {
    final opened = await Geolocator.openAppSettings();
    if (!opened && mounted) {
      setState(() {
        _locationError =
            'Unable to open app settings automatically. Open Settings > Apps '
            '> Draper TAK > Permissions and allow Location.';
        _locationRecoveryTarget = _LocationRecoveryTarget.appPermission;
      });
    }
  }

  Future<void> _openLocationServiceSettings() async {
    final opened = await Geolocator.openLocationSettings();
    if (!opened && mounted) {
      setState(() {
        _locationError =
            'Unable to open Location settings automatically. Open device '
            'Settings, turn on Location, and keep Wi-Fi enabled on Fire tablets.';
        _locationRecoveryTarget = _LocationRecoveryTarget.locationServices;
      });
    }
  }

  Future<void> _openLocationRecoverySettings() async {
    switch (_locationRecoveryTarget) {
      case _LocationRecoveryTarget.appPermission:
        await _openLocationAppSettings();
      case _LocationRecoveryTarget.locationServices:
        await _openLocationServiceSettings();
      case null:
        return;
    }
  }

  String get _blockedLocationInstructions => blockedLocationInstructions(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _AmbientBackground()),
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 48),
                  sliver: SliverList.list(
                    children: [
                      _Header(state: _controller.syncState),
                      const SizedBox(height: 18),
                      _NavigationTabs(
                        selected: _selectedTab,
                        onSelected: (tab) => setState(() {
                          _selectedTab = tab;
                        }),
                      ),
                      const SizedBox(height: 24),
                      if (_selectedTab == _AppTab.home) ...[
                        _WaypointMap(people: _controller.people),
                        const SizedBox(height: 24),
                        _EditorCard(
                          formKey: _formKey,
                          username: _username,
                          latitude: _latitude,
                          longitude: _longitude,
                          status: _status,
                          state: _controller.syncState,
                          usernameValidator: _controller.validateUsername,
                          isLocating: _isLocating,
                          onUseCurrentLocation: _useCurrentLocation,
                          onSave: _save,
                        ),
                        if (_locationError != null) ...[
                          const SizedBox(height: 14),
                          _ErrorBanner(
                            message: _locationError!,
                            onRetry: _useCurrentLocation,
                            secondaryActionLabel: switch (
                                _locationRecoveryTarget) {
                              _LocationRecoveryTarget.appPermission =>
                                'App settings',
                              _LocationRecoveryTarget.locationServices =>
                                'Location settings',
                              null => null,
                            },
                            onSecondaryAction: _locationRecoveryTarget == null
                                ? null
                                : _openLocationRecoverySettings,
                          ),
                        ],
                        if (_controller.errorMessage != null) ...[
                          const SizedBox(height: 14),
                          _ErrorBanner(
                            message: _controller.errorMessage!,
                            onRetry: _controller.initialize,
                          ),
                        ],
                        const SizedBox(height: 34),
                        _MeshDeviceList(
                          people: _controller.people,
                          statuses: _controller.meshStatusByDeviceId,
                          canRemove: _controller.canRemovePresence,
                          deletingIds: _deletingPresenceIds,
                          onRemove: _removePresence,
                        ),
                      ] else if (_selectedTab == _AppTab.observability) ...[
                        _ObservabilityPanel(
                          people: _controller.people,
                          statuses: _controller.meshStatusByDeviceId,
                          lastUpdated: _controller.meshTopologyUpdatedAt,
                        ),
                        if (_controller.errorMessage != null) ...[
                          const SizedBox(height: 14),
                          _ErrorBanner(
                            message: _controller.errorMessage!,
                            onRetry: _controller.initialize,
                          ),
                        ],
                      ] else ...[
                        AdminPanel(
                          recordCount: _controller.people.length,
                          canResetDatabase: _controller.canResetDatabase,
                          isResettingDatabase: _isResettingDatabase,
                          onResetDatabase: _resetDatabase,
                        ),
                        if (_controller.errorMessage != null) ...[
                          const SizedBox(height: 14),
                          _ErrorBanner(
                            message: _controller.errorMessage!,
                            onRetry: _controller.initialize,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _AppTab { home, observability, admin }

enum _LocationRecoveryTarget { appPermission, locationServices }

class _NavigationTabs extends StatelessWidget {
  const _NavigationTabs({required this.selected, required this.onSelected});

  final _AppTab selected;
  final ValueChanged<_AppTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF252D38)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _NavigationTab(
              key: const ValueKey('home-tab'),
              label: 'Home',
              icon: Icons.home_outlined,
              selected: selected == _AppTab.home,
              onTap: () => onSelected(_AppTab.home),
            ),
          ),
          Expanded(
            child: _NavigationTab(
              key: const ValueKey('observability-tab'),
              label: 'Observability',
              icon: Icons.monitor_heart_outlined,
              selected: selected == _AppTab.observability,
              onTap: () => onSelected(_AppTab.observability),
            ),
          ),
          Expanded(
            child: _NavigationTab(
              key: const ValueKey('admin-tab'),
              label: 'Admin',
              icon: Icons.admin_panel_settings_outlined,
              selected: selected == _AppTab.admin,
              onTap: () => onSelected(_AppTab.admin),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationTab extends StatelessWidget {
  const _NavigationTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? const Color(0xFF1D2927) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected
                        ? const Color(0xFF78F0C6)
                        : const Color(0xFF778293),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFFE9EDF5)
                          : const Color(0xFF778293),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      SyncState.connecting => 'CONNECTING',
      SyncState.authenticating => 'AUTHENTICATING',
      SyncState.connected => 'AUTHENTICATED',
      SyncState.saving => 'SAVING',
      SyncState.error => 'OFFLINE',
    };
    final color = switch (state) {
      SyncState.connected || SyncState.saving => const Color(0xFF78F0C6),
      SyncState.error => const Color(0xFFFF7A86),
      SyncState.connecting || SyncState.authenticating => const Color(
          0xFFFFA76C,
        ),
    };

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF141A22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF252D38)),
          ),
          child: const Icon(Icons.near_me_rounded, size: 19),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DRAPER TAK',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Powered by Ditto',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Color(0xFF747E8D), fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          key: const ValueKey('header-device-status'),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditorCard extends StatelessWidget {
  const _EditorCard({
    required this.formKey,
    required this.username,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.state,
    required this.usernameValidator,
    required this.isLocating,
    required this.onUseCurrentLocation,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController username;
  final TextEditingController latitude;
  final TextEditingController longitude;
  final TextEditingController status;
  final SyncState state;
  final FormFieldValidator<String> usernameValidator;
  final bool isLocating;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final busy = state == SyncState.connecting ||
        state == SyncState.authenticating ||
        state == SyncState.saving;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xE611151C),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF222A35)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 44,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FieldLabel(icon: Icons.person_outline, label: 'IDENTITY'),
            const SizedBox(height: 10),
            TextFormField(
              controller: username,
              textInputAction: TextInputAction.next,
              maxLength: 48,
              decoration: const InputDecoration(
                hintText: 'Your name',
                counterText: '',
              ),
              validator: usernameValidator,
            ),
            const SizedBox(height: 22),
            const _FieldLabel(
                icon: Icons.gps_fixed_rounded, label: 'COORDINATES'),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CoordinateField(
                    controller: latitude,
                    hint: '37.7749',
                    suffix: 'LAT',
                    min: -90,
                    max: 90,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CoordinateField(
                    controller: longitude,
                    hint: '-122.4194',
                    suffix: 'LNG',
                    min: -180,
                    max: 180,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isLocating ? null : onUseCurrentLocation,
                icon: isLocating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded, size: 17),
                label: Text(
                  isLocating
                      ? 'Finding your location…'
                      : 'Use current location',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF78F0C6),
                  side: const BorderSide(color: Color(0xFF31433F)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const _FieldLabel(icon: Icons.bolt_rounded, label: 'STATUS'),
            const SizedBox(height: 10),
            TextFormField(
              key: const ValueKey('status-field'),
              controller: status,
              textInputAction: TextInputAction.done,
              maxLength: 120,
              onFieldSubmitted: (_) => onSave(),
              decoration: const InputDecoration(
                hintText: 'What are you up to?',
                counterText: '',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Add a short status'
                  : null,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: busy ? null : onSave,
                style: FilledButton.styleFrom(
                  foregroundColor: const Color(0xFF07110E),
                  disabledBackgroundColor: const Color(0xFF28322F),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                child: busy
                    ? const SizedBox.square(
                        dimension: 19,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Update waypoint'),
                          SizedBox(width: 9),
                          Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordinateField extends StatelessWidget {
  const _CoordinateField({
    required this.controller,
    required this.hint,
    required this.suffix,
    required this.min,
    required this.max,
  });

  final TextEditingController controller;
  final String hint;
  final String suffix;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
      decoration: InputDecoration(
        hintText: hint,
        suffixText: suffix,
        suffixStyle: const TextStyle(
          color: Color(0xFF667181),
          fontSize: 10,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
      validator: (value) {
        final number = double.tryParse(value ?? '');
        if (number == null) return 'Required';
        if (number < min || number > max) return '$min to $max';
        return null;
      },
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF78F0C6)),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFA8B1BF),
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _WaypointMap extends StatefulWidget {
  const _WaypointMap({required this.people});

  final List<UserPresence> people;

  @override
  State<_WaypointMap> createState() => _WaypointMapState();
}

class _WaypointMapState extends State<_WaypointMap> {
  static const _fallbackCenter = LatLng(39.8283, -98.5795);
  final _mapController = MapController();
  bool _mapReady = false;

  List<LatLng> get _points => widget.people
      .map((person) => LatLng(person.latitude, person.longitude))
      .toList(growable: false);

  @override
  void didUpdateWidget(covariant _WaypointMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_locationSignature(oldWidget.people) !=
        _locationSignature(widget.people)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitWaypoints());
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  String _locationSignature(List<UserPresence> people) => people
      .map(
        (person) =>
            '${person.id}:${person.latitude}:${person.longitude}:${person.username}',
      )
      .join('|');

  void _fitWaypoints() {
    if (!_mapReady || !mounted) return;
    final points = _points;
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.single, 13);
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.fromLTRB(54, 72, 54, 48),
        maxZoom: 13,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF11151C),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF252D38)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 32,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: 3.2,
              minZoom: 2,
              maxZoom: 18,
              backgroundColor: const Color(0xFF11151C),
              onMapReady: () {
                _mapReady = true;
                _fitWaypoints();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'live.ditto.demo.ditto_gps',
                tileBuilder: darkModeTileBuilder,
              ),
              MarkerLayer(
                markers: widget.people
                    .map(
                      (person) => Marker(
                        key: ValueKey(person.id),
                        point: LatLng(person.latitude, person.longitude),
                        width: 150,
                        height: 52,
                        alignment: Alignment.topCenter,
                        child: _WaypointMarker(person: person),
                      ),
                    )
                    .toList(growable: false),
              ),
              RichAttributionWidget(
                showFlutterMapAttribution: false,
                popupBackgroundColor: const Color(0xEE11151C),
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    textStyle: const TextStyle(
                      color: Color(0xFFB8C1CE),
                      fontSize: 11,
                      decoration: TextDecoration.underline,
                    ),
                    onTap: () => launchUrl(
                      Uri.parse('https://www.openstreetmap.org/copyright'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xE611151C),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFF2B3542)),
              ),
              child: Text(
                widget.people.isEmpty
                    ? 'LIVE LOCATIONS'
                    : 'LIVE LOCATIONS  ·  ${widget.people.length}',
                style: const TextStyle(
                  color: Color(0xFFD1D8E2),
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (widget.people.isEmpty)
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xE611151C),
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'Add a waypoint to place it on the map.',
                    style: TextStyle(color: Color(0xFF9AA5B5), fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaypointMarker extends StatelessWidget {
  const _WaypointMarker({required this.person});

  final UserPresence person;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 145),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xF211151C),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0x6678F0C6)),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 8),
            ],
          ),
          child: Text(
            person.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFE9FFF8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: const Color(0xFF78F0C6),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF07110E), width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0xAA78F0C6), blurRadius: 10),
            ],
          ),
        ),
      ],
    );
  }
}

class _MeshDeviceList extends StatelessWidget {
  const _MeshDeviceList({
    required this.people,
    required this.statuses,
    required this.canRemove,
    required this.deletingIds,
    required this.onRemove,
  });

  final List<UserPresence> people;
  final Map<String, MeshPeerStatus> statuses;
  final bool canRemove;
  final Set<String> deletingIds;
  final Future<void> Function(UserPresence person) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.hub_outlined, size: 15, color: Color(0xFF78F0C6)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'MESH DEVICE LIST',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF8A94A4),
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${people.length} ${people.length == 1 ? 'DEVICE' : 'DEVICES'}',
              style: const TextStyle(color: Color(0xFF596272), fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (people.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0x8811151C),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF202731)),
            ),
            child: const Text(
              'Synced Draper TAK devices will appear here.',
              style: TextStyle(color: Color(0xFF717C8D), fontSize: 13),
            ),
          )
        else
          ...people.map(
            (person) => _PresenceTile(
              key: ValueKey('presence-${person.id}'),
              person: person,
              meshStatus: statuses[person.id],
              onRemove: onRemove,
              canRemove: canRemove,
              isRemoving: deletingIds.contains(person.id),
            ),
          ),
      ],
    );
  }
}

class _ObservabilityPanel extends StatelessWidget {
  const _ObservabilityPanel({
    required this.people,
    required this.statuses,
    this.lastUpdated,
    this.reconnectGracePeriod = meshReconnectGracePeriod,
  });

  final List<UserPresence> people;
  final Map<String, MeshPeerStatus> statuses;
  final DateTime? lastUpdated;
  final Duration reconnectGracePeriod;

  @override
  Widget build(BuildContext context) {
    final topology = buildMeshTopology(people: people, statuses: statuses);
    final nodeCount = topology.nodes.length;
    final connectionCount = topology.edges.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.monitor_heart_outlined,
              size: 15,
              color: Color(0xFF78F0C6),
            ),
            const SizedBox(width: 8),
            const Text(
              'MESH TOPOLOGY',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFF8A94A4),
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                key: const ValueKey('topology-counts'),
                '$nodeCount ${nodeCount == 1 ? 'NODE' : 'NODES'} · '
                '$connectionCount '
                '${connectionCount == 1 ? 'CONNECTION' : 'CONNECTIONS'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF596272),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LiveMeshTopology(
          people: people,
          statuses: statuses,
          lastUpdated: lastUpdated,
          reconnectGracePeriod: reconnectGracePeriod,
        ),
      ],
    );
  }
}

@visibleForTesting
Widget buildLiveMeshForTesting({
  required List<UserPresence> people,
  required Map<String, MeshPeerStatus> statuses,
}) =>
    _MeshDeviceList(
      people: people,
      statuses: statuses,
      canRemove: true,
      deletingIds: const {},
      onRemove: (_) async {},
    );

@visibleForTesting
Widget buildObservabilityForTesting({
  required List<UserPresence> people,
  required Map<String, MeshPeerStatus> statuses,
  DateTime? lastUpdated,
  Duration reconnectGracePeriod = meshReconnectGracePeriod,
}) =>
    _ObservabilityPanel(
      people: people,
      statuses: statuses,
      lastUpdated: lastUpdated,
      reconnectGracePeriod: reconnectGracePeriod,
    );

@visibleForTesting
Widget buildHeaderForTesting({required SyncState state}) =>
    _Header(state: state);

@visibleForTesting
Widget buildPresenceTileForTesting({
  required UserPresence person,
  MeshPeerStatus? meshStatus,
  Future<void> Function(UserPresence person)? onRemove,
  bool canRemove = true,
  bool isRemoving = false,
}) =>
    _PresenceTile(
      person: person,
      meshStatus: meshStatus,
      onRemove: onRemove,
      canRemove: canRemove,
      isRemoving: isRemoving,
    );

class _PresenceTile extends StatelessWidget {
  const _PresenceTile({
    required this.person,
    required this.meshStatus,
    required this.onRemove,
    required this.canRemove,
    required this.isRemoving,
    super.key,
  });

  final UserPresence person;
  final MeshPeerStatus? meshStatus;
  final Future<void> Function(UserPresence person)? onRemove;
  final bool canRemove;
  final bool isRemoving;

  @override
  Widget build(BuildContext context) {
    final initials = person.username.trim().isEmpty
        ? '?'
        : person.username.trim().substring(0, 1).toUpperCase();
    final route = _routeSummary(meshStatus);
    final status = _displayStatus(person.status);
    final coordinates = _formatCoordinates(person);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: const Color(0x9911151C),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF202731)),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.fromLTRB(14, 7, 10, 7),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            leading: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF1D2927),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                initials,
                style: const TextStyle(
                  color: Color(0xFF78F0C6),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            title: LayoutBuilder(
              builder: (context, constraints) {
                final name = Text(
                  person.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                );
                final badge = _ConnectionBadge(
                  key: const ValueKey('overview-connection-badge'),
                  summary: route,
                );
                if (constraints.maxWidth < 210) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [name, const SizedBox(height: 4), badge],
                  );
                }
                return Row(
                  children: [
                    Flexible(child: name),
                    const SizedBox(width: 8),
                    badge,
                  ],
                );
              },
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9AA4B3),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    coordinates,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF778293),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            iconColor: const Color(0xFF78F0C6),
            collapsedIconColor: const Color(0xFF697484),
            children: [
              const Divider(color: Color(0xFF252D38), height: 18),
              const _DetailHeading('CURRENT CONNECTION'),
              const SizedBox(height: 8),
              _CurrentConnectionState(
                summary: route,
                isConnected: meshStatus != null,
              ),
              if (meshStatus != null) ...[
                const SizedBox(height: 16),
                const _DetailHeading('NETWORK AVAILABILITY'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _ConnectivityPill(
                      icon: Icons.wifi_rounded,
                      label: 'Wi-Fi',
                      active: meshStatus!.connectivity.wifi,
                    ),
                    _ConnectivityPill(
                      icon: Icons.bluetooth_rounded,
                      label: 'Bluetooth',
                      active: meshStatus!.connectivity.bluetooth,
                    ),
                    _ConnectivityPill(
                      icon: Icons.signal_cellular_alt_rounded,
                      label: 'Cellular',
                      active: meshStatus!.connectivity.cellular,
                    ),
                  ],
                ),
                if (meshStatus!.connectivity.observedAt != null) ...[
                  const SizedBox(height: 9),
                  _PresenceDetail(
                    label: 'Observed',
                    value: _formatTimestamp(
                      meshStatus!.connectivity.observedAt!,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const _DetailHeading('DITTO SYNC TRANSPORTS'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _ConnectivityPill(
                      icon: Icons.cloud_outlined,
                      label: 'Big Peer',
                      active: meshStatus!.connectedToDittoServer,
                    ),
                    ...meshStatus!.connections.map(_transportPill),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              const _DetailHeading('LAST KNOWN WAYPOINT'),
              const SizedBox(height: 8),
              _PresenceDetail(label: 'Status', value: status),
              _PresenceDetail(
                label: 'Location',
                value: coordinates,
              ),
              _PresenceDetail(
                label: 'Updated',
                value: _formatTimestamp(person.updatedAt),
              ),
              const SizedBox(height: 8),
              const _DetailHeading('DEVICE'),
              const SizedBox(height: 8),
              if (meshStatus != null) ...[
                _PresenceDetail(
                  label: 'Name',
                  value: meshStatus!.deviceName,
                ),
                if (meshStatus!.os != null)
                  _PresenceDetail(label: 'OS', value: meshStatus!.os!),
                if (meshStatus!.dittoSdkVersion != null)
                  _PresenceDetail(
                    label: 'Ditto SDK',
                    value: meshStatus!.dittoSdkVersion!,
                  ),
              ],
              _PresenceDetail(label: 'Device ID', value: person.id),
              if (onRemove != null) ...[
                const SizedBox(height: 6),
                const Divider(color: Color(0xFF252D38), height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: ValueKey('remove-presence-${person.id}'),
                    onPressed: isRemoving || !canRemove
                        ? null
                        : () => _confirmRemove(context),
                    icon: isRemoving
                        ? const SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(
                      isRemoving ? 'REMOVING…' : 'REMOVE FROM LIVE MESH',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF8F99),
                      side: const BorderSide(color: Color(0x665B3138)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final callback = onRemove;
    if (callback == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${person.username} from Live Mesh?'),
        content: Text(
          'This synchronized removal will hide the waypoint on every '
          'connected mesh device. ${person.username} can rejoin by saving '
          'its status or location again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            key: const ValueKey('confirm-remove-presence'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB94855),
            ),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await callback(person);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${person.username} removed. The change is syncing across the mesh.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to remove the waypoint. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static _RouteSummary _routeSummary(MeshPeerStatus? status) {
    if (status == null) {
      return const _RouteSummary('NOT CONNECTED', Color(0xFFFF7A86));
    }
    if (status.connectedToDittoServer && status.hasPeerToPeerConnection) {
      return const _RouteSummary('BIG PEER + MESH', Color(0xFF7AA8FF));
    }
    if (status.connectedToDittoServer) {
      return const _RouteSummary('BIG PEER', Color(0xFF7AA8FF));
    }
    if (status.hasPeerToPeerConnection) {
      return const _RouteSummary('MESH ONLY', Color(0xFF78F0C6));
    }
    return const _RouteSummary('NO ACTIVE LINK', Color(0xFFFFA76C));
  }

  static Widget _transportPill(MeshConnectionKind connection) {
    return switch (connection) {
      MeshConnectionKind.bluetooth => const _ConnectivityPill(
          icon: Icons.bluetooth_connected_rounded,
          label: 'Bluetooth mesh',
          active: true,
        ),
      MeshConnectionKind.accessPoint => const _ConnectivityPill(
          icon: Icons.router_outlined,
          label: 'LAN mesh',
          active: true,
        ),
      MeshConnectionKind.p2pWifi => const _ConnectivityPill(
          icon: Icons.wifi_tethering_rounded,
          label: 'P2P Wi-Fi',
          active: true,
        ),
      MeshConnectionKind.webSocket => const _ConnectivityPill(
          icon: Icons.cable_rounded,
          label: 'Peer WebSocket',
          active: true,
        ),
    };
  }

  static String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
  }

  static String _formatCoordinates(UserPresence person) =>
      '${person.latitude.toStringAsFixed(6)}, '
      '${person.longitude.toStringAsFixed(6)}';

  static String _displayStatus(String value) {
    final status = value.trim();
    return status.isEmpty ? 'No status reported' : status;
  }
}

class _RouteSummary {
  const _RouteSummary(this.label, this.color);

  final String label;
  final Color color;
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.summary, super.key});

  final _RouteSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: summary.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: summary.color.withValues(alpha: 0.34)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('connection-status-dot'),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: summary.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: summary.color.withValues(alpha: 0.40),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              summary.label,
              style: TextStyle(
                color: summary.color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresenceDetail extends StatelessWidget {
  const _PresenceDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF596272),
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: Color(0xFFB8C1CE), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailHeading extends StatelessWidget {
  const _DetailHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF8A94A4),
        fontSize: 9,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _CurrentConnectionState extends StatelessWidget {
  const _CurrentConnectionState({
    required this.summary,
    required this.isConnected,
  });

  final _RouteSummary summary;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: summary.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: summary.color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ConnectionBadge(summary: summary),
          if (!isConnected) ...[
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'This device is not currently connected.',
                style: TextStyle(
                  color: Color(0xFFFFB4BC),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectivityPill extends StatelessWidget {
  const _ConnectivityPill({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool? active;

  @override
  Widget build(BuildContext context) {
    final color = switch (active) {
      true => const Color(0xFF78F0C6),
      false => const Color(0xFFFF7A86),
      null => const Color(0xFF778293),
    };
    final state = switch (active) {
      true => 'ON',
      false => 'OFF',
      null => 'UNKNOWN',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            '$label $state',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
Widget buildErrorBannerForTesting({
  required String message,
  required VoidCallback onRetry,
  String? secondaryActionLabel,
  VoidCallback? onSecondaryAction,
}) =>
    _ErrorBanner(
      message: message,
      onRetry: onRetry,
      secondaryActionLabel: secondaryActionLabel,
      onSecondaryAction: onSecondaryAction,
    );

@visibleForTesting
Widget buildLocationServicesDialogForTesting({
  required String instructions,
  required bool canOpenSettings,
  required VoidCallback onClose,
  required VoidCallback onOpenSettings,
}) =>
    AlertDialog(
      title: const Text('Turn on location services'),
      content: Text(instructions),
      actions: [
        TextButton(
          onPressed: onClose,
          child: Text(canOpenSettings ? 'Not now' : 'OK'),
        ),
        if (canOpenSettings)
          FilledButton(
            onPressed: onOpenSettings,
            child: const Text('Open settings'),
          ),
      ],
    );

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onRetry,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final String message;
  final VoidCallback onRetry;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x22FF6B78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x44FF6B78)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFFF7A86),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(
                  message,
                  style: const TextStyle(
                    color: Color(0xFFDCA0A6),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            children: [
              TextButton.icon(
                onPressed: () => _copyError(context),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy error'),
              ),
              if (secondaryActionLabel != null && onSecondaryAction != null)
                TextButton(
                  onPressed: onSecondaryAction,
                  child: Text(secondaryActionLabel!),
                ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copyError(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Error copied to clipboard.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.9, -0.85),
          radius: 1.15,
          colors: [Color(0x2B276E62), Color(0x00090B0F)],
          stops: [0, 0.72],
        ),
      ),
      child: CustomPaint(painter: _GridPainter()),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0B9FB3C7)
      ..strokeWidth = 0.5;
    const gap = 34.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
