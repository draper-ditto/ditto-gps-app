import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_presence.dart';
import '../services/presence_controller.dart';

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
  bool _didHydrateForm = false;
  bool _isLocating = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
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

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError(
          'Location services are disabled. Enable them and try again.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw StateError('Location permission was denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw StateError(
          'Location permission is blocked. Allow location access in your browser or device settings, then try again.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;

      _latitude.text = position.latitude.toStringAsFixed(6);
      _longitude.text = position.longitude.toStringAsFixed(6);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current coordinates added to the form.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationError = 'Unable to use current location: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SelectionArea(
        child: Stack(
          children: [
            const Positioned.fill(child: _AmbientBackground()),
            SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 48),
                    sliver: SliverList.list(
                      children: [
                        _Header(
                          state: _controller.syncState,
                          peerCount: _controller.people.length,
                        ),
                        const SizedBox(height: 18),
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
                        _LiveMesh(people: _controller.people),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.peerCount});

  final SyncState state;
  final int peerCount;

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
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DRAPER TAK',
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Powered by Ditto',
              style: TextStyle(color: Color(0xFF747E8D), fontSize: 11),
            ),
          ],
        ),
        const Spacer(),
        Container(
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
                peerCount > 0 ? '$label · $peerCount' : label,
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

class _LiveMesh extends StatelessWidget {
  const _LiveMesh({required this.people});

  final List<UserPresence> people;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'LIVE MESH',
              style: TextStyle(
                color: Color(0xFF8A94A4),
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${people.length} ${people.length == 1 ? 'WAYPOINT' : 'WAYPOINTS'}',
              style: const TextStyle(color: Color(0xFF596272), fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
              'Your synced waypoints will appear here.',
              style: TextStyle(color: Color(0xFF717C8D), fontSize: 13),
            ),
          )
        else
          ...people.take(8).map(_PresenceTile.new),
      ],
    );
  }
}

class _PresenceTile extends StatelessWidget {
  const _PresenceTile(this.person);

  final UserPresence person;

  @override
  Widget build(BuildContext context) {
    final initials = person.username.trim().isEmpty
        ? '?'
        : person.username.trim().substring(0, 1).toUpperCase();
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x9911151C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF202731)),
      ),
      child: Row(
        children: [
          Container(
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        person.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFF78F0C6),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${person.latitude.toStringAsFixed(4)}, ${person.longitude.toStringAsFixed(4)}  ·  ${person.status}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Color(0xFF778293), fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.north_east_rounded,
              color: Color(0xFF4C5665), size: 16),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x22FF6B78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x44FF6B78)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFFF7A86), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFDCA0A6), fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Copy error',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: message));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error copied to clipboard.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ],
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
