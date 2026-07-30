import 'package:flutter/material.dart';

import '../config/app_version.dart';

class AdminPanel extends StatelessWidget {
  const AdminPanel({
    required this.recordCount,
    required this.canResetDatabase,
    required this.isResettingDatabase,
    required this.onResetDatabase,
    super.key,
  });

  final int recordCount;
  final bool canResetDatabase;
  final bool isResettingDatabase;
  final Future<int> Function() onResetDatabase;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ADMIN CONTROLS',
          style: TextStyle(
            color: Color(0xFF8A94A4),
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        const _AdminCard(
          icon: Icons.system_update_alt_rounded,
          iconColor: Color(0xFF78F0C6),
          title: 'Application version',
          description: 'Installed Draper TAK release.',
          action: _VersionBadge(),
        ),
        const SizedBox(height: 14),
        _AdminCard(
          icon: Icons.delete_sweep_outlined,
          iconColor: const Color(0xFFFF7A86),
          title: 'Ditto demo database',
          description:
              '$recordCount ${recordCount == 1 ? 'waypoint' : 'waypoints'} currently synced. Reset permanently deletes every Draper TAK waypoint.',
          action: FilledButton.icon(
            key: const ValueKey('reset-database-button'),
            onPressed: canResetDatabase && !isResettingDatabase
                ? () => _confirmReset(context)
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B78),
              foregroundColor: const Color(0xFF23070B),
            ),
            icon: isResettingDatabase
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(
              isResettingDatabase ? 'Resetting…' : 'Clear and reset database',
            ),
          ),
        ),
        const SizedBox(height: 14),
        const _WorkerCard(workerName: 'Cloudflare Worker #1'),
        const SizedBox(height: 14),
        const _WorkerCard(workerName: 'Cloudflare Worker #2'),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset the Ditto database?'),
        content: Text(
          'This permanently deletes all $recordCount synced Draper TAK '
          '${recordCount == 1 ? 'waypoint' : 'waypoints'} from every device. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-reset-database-button'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B78),
              foregroundColor: const Color(0xFF23070B),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset database'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final deleted = await onResetDatabase();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ditto demo database reset. $deleted '
            '${deleted == 1 ? 'waypoint' : 'waypoints'} deleted.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      // PresenceController publishes the actionable error in the app UI.
    }
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Application version $appDisplayVersion, build $appBuildNumber',
      child: Container(
        key: const ValueKey('application-version'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0x1A78F0C6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x5578F0C6)),
        ),
        child: const Text(
          'v$appDisplayVersion · build $appBuildNumber',
          style: TextStyle(
            color: Color(0xFF78F0C6),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({required this.workerName});

  static const _description =
      'In the future, this button will launch a headless Ditto agent that automatically fills in data and provides updates.';

  final String workerName;

  @override
  Widget build(BuildContext context) {
    return _AdminCard(
      icon: Icons.cloud_outlined,
      iconColor: const Color(0xFF7AA8FF),
      title: workerName,
      description: 'Headless Ditto agent placeholder.',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            key: ValueKey('launch-$workerName'),
            onPressed: () => _showInformation(context),
            icon: const Icon(Icons.rocket_launch_outlined, size: 17),
            label: const Text('Launch'),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: ValueKey('info-$workerName'),
            tooltip: 'About $workerName',
            onPressed: () => _showInformation(context),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _showInformation(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(workerName),
        content: const Text(_description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x9911151C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF202731)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final details = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF778293),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [details, const SizedBox(height: 14), action],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 20),
              action,
            ],
          );
        },
      ),
    );
  }
}
