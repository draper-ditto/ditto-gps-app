import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                        const SizedBox(height: 34),
                        const Text(
                          'Set your point.\nStay in sync.',
                          style: TextStyle(
                            fontSize: 40,
                            height: 1.05,
                            letterSpacing: -1.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Share a manual location and a quick status with every device in your Ditto mesh.',
                          style: TextStyle(
                            color: Color(0xFF8E98A8),
                            height: 1.5,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 30),
                        _EditorCard(
                          formKey: _formKey,
                          username: _username,
                          latitude: _latitude,
                          longitude: _longitude,
                          status: _status,
                          state: _controller.syncState,
                          onSave: _save,
                        ),
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
              'WAYPOINT',
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
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController username;
  final TextEditingController latitude;
  final TextEditingController longitude;
  final TextEditingController status;
  final SyncState state;
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
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a username'
                  : null,
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
