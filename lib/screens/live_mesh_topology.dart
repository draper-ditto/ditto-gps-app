import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/mesh_peer_status.dart';
import '../models/mesh_topology.dart';
import '../models/user_presence.dart';

class LiveMeshTopology extends StatelessWidget {
  const LiveMeshTopology({
    required this.people,
    required this.statuses,
    this.lastUpdated,
    this.reconnectGracePeriod = meshReconnectGracePeriod,
    super.key,
  });

  final List<UserPresence> people;
  final Map<String, MeshPeerStatus> statuses;
  final DateTime? lastUpdated;
  final Duration reconnectGracePeriod;

  @override
  Widget build(BuildContext context) {
    final topology = buildMeshTopology(people: people, statuses: statuses);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TopologyGuideCard(),
        const SizedBox(height: 20),
        _LastUpdatedBadge(lastUpdated: lastUpdated),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) => _TopologyCanvas(
            topology: topology,
            width: constraints.maxWidth,
            reconnectGracePeriod: reconnectGracePeriod,
          ),
        ),
      ],
    );
  }
}

class _TopologyGuideCard extends StatelessWidget {
  const _TopologyGuideCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('topology-guide-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE611151C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3441)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GuideLabel('Description'),
          SizedBox(height: 7),
          Text(
            'Visualize real time connectivity updates to your Ditto mesh topology. Every SDK-reported peer is shown, including unidentified backend and infrastructure peers without Draper TAK records. Select a node to center it, highlight its paths, and inspect its connections.',
            style: TextStyle(
              color: Color(0xFFB4BDCA),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          SizedBox(height: 15),
          Divider(color: Color(0xFF2A3441), height: 1),
          SizedBox(height: 15),
          _GuideLabel('Legend'),
          SizedBox(height: 10),
          _TopologyLegend(),
        ],
      ),
    );
  }
}

class _GuideLabel extends StatelessWidget {
  const _GuideLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          color: Color(0xFFE4E9F0),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
        ),
      );
}

class _TopologyCanvas extends StatefulWidget {
  const _TopologyCanvas({
    required this.topology,
    required this.width,
    required this.reconnectGracePeriod,
  });

  final MeshTopology topology;
  final double width;
  final Duration reconnectGracePeriod;

  @override
  State<_TopologyCanvas> createState() => _TopologyCanvasState();
}

class _TopologyCanvasState extends State<_TopologyCanvas> {
  final TransformationController _transformationController =
      TransformationController();
  late MeshTopologyReconnectTracker _reconnectTracker;
  late MeshTopology _displayedTopology;
  Timer? _reconnectExpirationTimer;
  String? _selectedNodeId;

  @override
  void initState() {
    super.initState();
    _reconnectTracker = MeshTopologyReconnectTracker(
      gracePeriod: widget.reconnectGracePeriod,
    );
    _updateDisplayedTopology();
  }

  @override
  void didUpdateWidget(covariant _TopologyCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reconnectGracePeriod != widget.reconnectGracePeriod) {
      _reconnectTracker = MeshTopologyReconnectTracker(
        gracePeriod: widget.reconnectGracePeriod,
      );
    }
    _updateDisplayedTopology();
  }

  @override
  void dispose() {
    _reconnectExpirationTimer?.cancel();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topology = _displayedTopology;
    final width = widget.width;
    final deviceNodes =
        topology.nodes.where((node) => !node.isBigPeer).toList();
    final layout = topologyNodePositionsForTesting(
      nodes: deviceNodes,
      edges: topology.edges,
      width: width,
    );
    final positions = layout.positions;
    final viewportHeight = math.min(layout.height, width < 500 ? 520.0 : 640.0);
    final routes = topologyOrthogonalRoutesForTesting(
      edges: topology.edges,
      positions: positions,
      canvasSize: Size(width, layout.height),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: const ValueKey('live-mesh-topology-graph'),
          width: width,
          height: viewportHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: InteractiveViewer(
              key: const ValueKey('topology-interactive-viewer'),
              transformationController: _transformationController,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(60),
              minScale: .65,
              maxScale: 1.8,
              child: SizedBox(
                width: width,
                height: layout.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TopologyEdgePainter(
                          routes: routes,
                          selectedNodeId: _selectedNodeId,
                        ),
                      ),
                    ),
                    Positioned.fromRect(
                      rect: positions[bigPeerTopologyNodeId]!,
                      child: _BigPeerNode(
                        connectedDevices: topology.edges
                            .where(
                              (edge) => edge.isBigPeer && !edge.isReconnecting,
                            )
                            .length,
                        selected: _selectedNodeId == bigPeerTopologyNodeId,
                        onTap: () => _selectNode(
                          bigPeerTopologyNodeId,
                          positions[bigPeerTopologyNodeId]!,
                          Size(width, viewportHeight),
                        ),
                      ),
                    ),
                    if (layout.disconnectedLabelTop case final labelTop?)
                      Positioned(
                        key: const ValueKey(
                          'topology-disconnected-section',
                        ),
                        left: 0,
                        right: 0,
                        top: labelTop,
                        child: const _DisconnectedSectionLabel(),
                      ),
                    for (final node in deviceNodes)
                      Positioned.fromRect(
                        rect: positions[node.id]!,
                        child: _DeviceNode(
                          node: node,
                          selected: _selectedNodeId == node.id,
                          hasDisplayedConnection: topology.edges.any(
                            (edge) =>
                                edge.fromId == node.id || edge.toId == node.id,
                          ),
                          onTap: () => _selectNode(
                            node.id,
                            positions[node.id]!,
                            Size(width, viewportHeight),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_selectedNodeId case final selectedId?) ...[
          const SizedBox(height: 12),
          _SelectedNodeDetails(
            node: topology.nodes.firstWhere((node) => node.id == selectedId),
            topology: topology,
            onClose: () => setState(() => _selectedNodeId = null),
          ),
        ],
      ],
    );
  }

  void _selectNode(String nodeId, Rect nodeRect, Size viewportSize) {
    setState(() => _selectedNodeId = nodeId);
    _transformationController.value = topologyCenterTransformForTesting(
      viewportSize: viewportSize,
      nodeRect: nodeRect,
      scale: _transformationController.value.getMaxScaleOnAxis(),
    );
  }

  void _updateDisplayedTopology({DateTime? now}) {
    now ??= DateTime.now().toUtc();
    _displayedTopology = _reconnectTracker.update(widget.topology, now: now);
    final selectedNodeId = _selectedNodeId;
    if (selectedNodeId != null &&
        !_displayedTopology.nodes.any((node) => node.id == selectedNodeId)) {
      _selectedNodeId = null;
    }
    _reconnectExpirationTimer?.cancel();
    final expiration = _reconnectTracker.nextExpiration;
    if (expiration == null) return;
    final delay = expiration.difference(now);
    _reconnectExpirationTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        if (!mounted) return;
        setState(() => _updateDisplayedTopology(now: expiration));
      },
    );
  }
}

class _LastUpdatedBadge extends StatelessWidget {
  const _LastUpdatedBadge({required this.lastUpdated});

  final DateTime? lastUpdated;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('topology-last-updated'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE611151C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF34404E)),
      ),
      child: Text(
        formatTopologyLastUpdated(lastUpdated),
        style: const TextStyle(
          color: Color(0xFFC5CDD8),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

@visibleForTesting
String formatTopologyLastUpdated(DateTime? timestamp) {
  if (timestamp == null) return 'Last updated —';
  final local = timestamp.toLocal();
  final hour =
      local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return 'Last updated $hour:$minute:$second $period';
}

class _DisconnectedSectionLabel extends StatelessWidget {
  const _DisconnectedSectionLabel();

  @override
  Widget build(BuildContext context) => const Row(
        children: [
          Expanded(child: Divider(color: Color(0xFF3A2329), height: 1)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'DISCONNECTED',
              style: TextStyle(
                color: Color(0xFFFF7A86),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: .7,
              ),
            ),
          ),
          Expanded(child: Divider(color: Color(0xFF3A2329), height: 1)),
        ],
      );
}

class _BigPeerNode extends StatelessWidget {
  const _BigPeerNode({
    required this.connectedDevices,
    required this.selected,
    required this.onTap,
  });

  final int connectedDevices;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final connected = connectedDevices > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('topology-big-peer-node'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF203552) : const Color(0xFF142238),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  selected ? const Color(0xFFFFD166) : const Color(0xFF467AC4),
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_outlined,
                color: Color(0xFF7AA8FF),
                size: 24,
              ),
              const Text('BIG PEER',
                  style: TextStyle(
                      color: Color(0xFFE8F1FF),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .7)),
              Text(
                connected ? '$connectedDevices CONNECTED' : 'NO LIVE LINKS',
                style: const TextStyle(
                    color: Color(0xFF8EA8CB),
                    fontSize: 8,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceNode extends StatelessWidget {
  const _DeviceNode({
    required this.node,
    required this.hasDisplayedConnection,
    required this.selected,
    required this.onTap,
  });

  final MeshTopologyNode node;
  final bool hasDisplayedConnection;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final person = node.person;
    final status = node.status;
    final sdkPeer = node.sdkPeer;
    final route = sdkPeer == null
        ? _routeFor(status)
        : !sdkPeer.connectedToDittoServer && !hasDisplayedConnection
            ? (label: 'NOT CONNECTED', color: const Color(0xFFFF7A86))
            : (
                label: sdkPeer.connectedToDittoServer
                    ? 'SDK PEER + BIG PEER'
                    : 'SDK PEER',
                color: const Color(0xFF9FB3C8),
              );
    final detail = sdkPeer == null
        ? (person!.status.trim().isEmpty
            ? 'No status reported'
            : person.status.trim())
        : 'Ditto SDK peer without a Draper TAK record';
    final deviceDetail = sdkPeer == null
        ? status?.deviceName ?? 'Last known device'
        : [
            if (sdkPeer.os?.trim().isNotEmpty ?? false) sdkPeer.os!.trim(),
            if (sdkPeer.dittoSdkVersion?.trim().isNotEmpty ?? false)
              'Ditto ${sdkPeer.dittoSdkVersion!.trim()}',
          ].join(' • ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('topology-device-${node.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF252719) : const Color(0xF011151C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFD166)
                  : route.color.withValues(alpha: .65),
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (sdkPeer != null) ...[
                    const Icon(
                      Icons.dns_outlined,
                      color: Color(0xFF9FB3C8),
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      node.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFE7EBF1),
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                          color: route.color, shape: BoxShape.circle)),
                ],
              ),
              const SizedBox(height: 5),
              Text(route.label,
                  key: ValueKey('topology-route-${node.id}'),
                  style: TextStyle(
                      color: route.color,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5)),
              const Spacer(),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFFAAB3C0), fontSize: 11, height: 1.25),
              ),
              const SizedBox(height: 4),
              if (sdkPeer != null) ...[
                SelectableText(
                  'Peer ID: ${sdkPeer.peerKey}',
                  key: ValueKey('topology-peer-id-${sdkPeer.peerKey}'),
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFF8B98AA),
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 3),
              ],
              Text(
                deviceDetail.isEmpty
                    ? 'SDK peer details unavailable'
                    : deviceDetail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF657183), fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedNodeDetails extends StatelessWidget {
  const _SelectedNodeDetails({
    required this.node,
    required this.topology,
    required this.onClose,
  });

  final MeshTopologyNode node;
  final MeshTopology topology;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final connections = topology.edges
        .where((edge) => edge.fromId == node.id || edge.toId == node.id)
        .toList();
    String nodeLabel(String id) => topology.nodes
        .firstWhere(
          (candidate) => candidate.id == id,
          orElse: () => MeshTopologyNode(id: id, label: id),
        )
        .label;

    return Container(
      key: ValueKey('topology-selected-details-${node.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171A18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD166), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.center_focus_strong,
                color: Color(0xFFFFD166),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.label,
                  style: const TextStyle(
                    color: Color(0xFFF4F0DC),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('topology-clear-selection'),
                onPressed: onClose,
                tooltip: 'Clear topology selection',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const Text(
            'CONNECTIONS',
            style: TextStyle(
              color: Color(0xFF8A94A4),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 8),
          if (connections.isEmpty)
            const Text(
              'Not connected. No active topology path is reported.',
              style: TextStyle(color: Color(0xFFFF7A86), fontSize: 12),
            )
          else
            for (final edge in connections)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: edge.isBigPeer
                            ? const Color(0xFF7AA8FF)
                            : _transportColor(edge.kind!),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        _selectedConnectionLabel(
                          edge: edge,
                          selectedNode: node,
                          otherNodeLabel: nodeLabel(
                            edge.fromId == node.id ? edge.toId : edge.fromId,
                          ),
                        ),
                        style: const TextStyle(
                          color: Color(0xFFC8D0DB),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          if (node.person case final person?) ...[
            const SizedBox(height: 5),
            SelectableText(
              'Status: ${person.status.trim().isEmpty ? 'No status reported' : person.status.trim()}',
              style: const TextStyle(color: Color(0xFF9DA8B7), fontSize: 11),
            ),
            SelectableText(
              'Last location: ${person.latitude.toStringAsFixed(6)}, ${person.longitude.toStringAsFixed(6)}',
              style: const TextStyle(color: Color(0xFF9DA8B7), fontSize: 11),
            ),
          ],
          if (node.sdkPeer case final peer?) ...[
            const SizedBox(height: 5),
            SelectableText(
              'Peer ID: ${peer.peerKey}',
              style: const TextStyle(color: Color(0xFF9DA8B7), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class TopologyOrthogonalRoute {
  const TopologyOrthogonalRoute({required this.edge, required this.points});

  final MeshTopologyEdge edge;
  final List<Offset> points;
}

class _TopologyEdgePainter extends CustomPainter {
  const _TopologyEdgePainter({
    required this.routes,
    required this.selectedNodeId,
  });

  final List<TopologyOrthogonalRoute> routes;
  final String? selectedNodeId;

  @override
  void paint(Canvas canvas, Size size) {
    for (final route in routes) {
      final edge = route.edge;
      final selected = selectedNodeId == null ||
          edge.fromId == selectedNodeId ||
          edge.toId == selectedNodeId;
      final color = edge.isBigPeer
          ? const Color(0xFF7AA8FF)
          : _transportColor(edge.kind!);
      final paint = Paint()
        ..color = color.withValues(alpha: selected ? .9 : .22)
        ..strokeWidth = selectedNodeId != null && selected
            ? 3.4
            : edge.isBigPeer
                ? 2.4
                : 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(route.points.first.dx, route.points.first.dy);
      for (final point in route.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      if (edge.isReconnecting) {
        for (final segment in topologyDashedSegmentsForTesting(route.points)) {
          canvas.drawLine(segment.start, segment.end, paint);
        }
      } else {
        canvas.drawPath(path, paint);
      }
    }

    // Draw label plates last so crossing connections cannot cut through them.
    for (final route in routes) {
      final edge = route.edge;
      final selected = selectedNodeId == null ||
          edge.fromId == selectedNodeId ||
          edge.toId == selectedNodeId;
      final color = edge.isBigPeer
          ? const Color(0xFF7AA8FF)
          : _transportColor(edge.kind!);
      final label = topologyEdgeLabelForTesting(edge);
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelCenter = topologyPathMidpointForTesting(route.points);
      final plate = Rect.fromCenter(
        center: labelCenter,
        width: textPainter.width + 10,
        height: textPainter.height + 6,
      );
      final plateShape = RRect.fromRectAndRadius(
        plate,
        const Radius.circular(4),
      );
      canvas.drawRRect(
        plateShape,
        Paint()
          ..color = const Color(0xFF0B0F14).withValues(
            alpha: selected ? 1 : .72,
          )
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        plateShape,
        Paint()
          ..color = color.withValues(alpha: selected ? .55 : .2)
          ..strokeWidth = .75
          ..style = PaintingStyle.stroke,
      );
      textPainter.paint(
        canvas,
        labelCenter - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TopologyEdgePainter oldDelegate) =>
      oldDelegate.routes != routes ||
      oldDelegate.selectedNodeId != selectedNodeId;
}

@visibleForTesting
String topologyEdgeLabelForTesting(MeshTopologyEdge edge) {
  final protocol = edge.isBigPeer ? 'CLOUD' : _transportLabel(edge.kind!);
  return edge.isReconnecting ? '$protocol · RECONNECTING' : protocol;
}

@visibleForTesting
List<({Offset start, Offset end})> topologyDashedSegmentsForTesting(
  List<Offset> points, {
  double dashLength = 9,
  double gapLength = 6,
}) {
  final segments = <({Offset start, Offset end})>[];
  if (points.length < 2 || dashLength <= 0 || gapLength < 0) return segments;

  for (var index = 0; index < points.length - 1; index++) {
    final start = points[index];
    final delta = points[index + 1] - start;
    final length = delta.distance;
    if (length == 0) continue;
    final direction = delta / length;
    var distance = 0.0;
    while (distance < length) {
      final dashEnd = math.min(distance + dashLength, length);
      segments.add((
        start: start + direction * distance,
        end: start + direction * dashEnd,
      ));
      distance += dashLength + gapLength;
    }
  }
  return segments;
}

@visibleForTesting
Offset topologyEdgeLabelCenterForTesting({
  required Offset start,
  required Offset end,
}) =>
    Offset(
      (start.dx + end.dx) / 2,
      (start.dy + end.dy) / 2,
    );

@visibleForTesting
Offset topologyPathMidpointForTesting(List<Offset> points) {
  if (points.isEmpty) return Offset.zero;
  if (points.length == 1) return points.single;
  var total = 0.0;
  for (var index = 0; index < points.length - 1; index++) {
    total += (points[index + 1] - points[index]).distance;
  }
  var remaining = total / 2;
  for (var index = 0; index < points.length - 1; index++) {
    final delta = points[index + 1] - points[index];
    final length = delta.distance;
    if (remaining <= length) {
      return points[index] + delta * (length == 0 ? 0 : remaining / length);
    }
    remaining -= length;
  }
  return points.last;
}

@visibleForTesting
Matrix4 topologyCenterTransformForTesting({
  required Size viewportSize,
  required Rect nodeRect,
  required double scale,
}) {
  final safeScale = scale.clamp(.65, 1.8);
  final translation = viewportSize.center(Offset.zero) -
      Offset(nodeRect.center.dx * safeScale, nodeRect.center.dy * safeScale);
  return Matrix4.identity()
    ..setEntry(0, 0, safeScale)
    ..setEntry(1, 1, safeScale)
    ..setEntry(2, 2, safeScale)
    ..setTranslationRaw(translation.dx, translation.dy, 0);
}

@visibleForTesting
({Offset start, Offset end}) topologyVisibleEdgeSegmentForTesting({
  required Rect from,
  required Rect to,
}) {
  final delta = to.center - from.center;
  if (delta == Offset.zero) {
    return (start: from.center, end: to.center);
  }

  double boundaryScale(Rect rect) {
    final horizontal =
        delta.dx == 0 ? double.infinity : (rect.width / 2) / delta.dx.abs();
    final vertical =
        delta.dy == 0 ? double.infinity : (rect.height / 2) / delta.dy.abs();
    return math.min(horizontal, vertical);
  }

  return (
    start: from.center + delta * boundaryScale(from),
    end: to.center - delta * boundaryScale(to),
  );
}

enum _NodeSide { top, right, bottom, left }

({Offset port, Offset lead}) _nodePort(
  Rect rect,
  _NodeSide side,
  double fraction,
) {
  const leadDistance = 14.0;
  return switch (side) {
    _NodeSide.top => (
        port: Offset(rect.left + rect.width * fraction, rect.top),
        lead: Offset(
          rect.left + rect.width * fraction,
          rect.top - leadDistance,
        ),
      ),
    _NodeSide.right => (
        port: Offset(rect.right, rect.top + rect.height * fraction),
        lead: Offset(
          rect.right + leadDistance,
          rect.top + rect.height * fraction,
        ),
      ),
    _NodeSide.bottom => (
        port: Offset(rect.left + rect.width * fraction, rect.bottom),
        lead: Offset(
          rect.left + rect.width * fraction,
          rect.bottom + leadDistance,
        ),
      ),
    _NodeSide.left => (
        port: Offset(rect.left, rect.top + rect.height * fraction),
        lead: Offset(
          rect.left - leadDistance,
          rect.top + rect.height * fraction,
        ),
      ),
  };
}

@visibleForTesting
List<TopologyOrthogonalRoute> topologyOrthogonalRoutesForTesting({
  required List<MeshTopologyEdge> edges,
  required Map<String, Rect> positions,
  required Size canvasSize,
}) {
  final incidentEdges = <String, List<MeshTopologyEdge>>{};
  for (final edge in edges) {
    incidentEdges.putIfAbsent(edge.fromId, () => []).add(edge);
    incidentEdges.putIfAbsent(edge.toId, () => []).add(edge);
  }
  for (final nodeEdges in incidentEdges.values) {
    nodeEdges.sort((first, second) => first.id.compareTo(second.id));
  }

  final routes = <TopologyOrthogonalRoute>[];
  for (final edge in edges) {
    final fromRect = positions[edge.fromId];
    final toRect = positions[edge.toId];
    if (fromRect == null || toRect == null) continue;
    final fromEdges = incidentEdges[edge.fromId]!;
    final toEdges = incidentEdges[edge.toId]!;
    final fromFraction = (fromEdges.indexOf(edge) + 1) / (fromEdges.length + 1);
    final toFraction = (toEdges.indexOf(edge) + 1) / (toEdges.length + 1);
    final candidates = <List<Offset>>[];

    for (final fromSide in _NodeSide.values) {
      final from = _nodePort(fromRect, fromSide, fromFraction);
      for (final toSide in _NodeSide.values) {
        final to = _nodePort(toRect, toSide, toFraction);
        final middleX = (from.lead.dx + to.lead.dx) / 2;
        final middleY = (from.lead.dy + to.lead.dy) / 2;
        candidates.addAll([
          [
            from.port,
            from.lead,
            Offset(middleX, from.lead.dy),
            Offset(middleX, to.lead.dy),
            to.lead,
            to.port,
          ],
          [
            from.port,
            from.lead,
            Offset(from.lead.dx, middleY),
            Offset(to.lead.dx, middleY),
            to.lead,
            to.port,
          ],
          for (final laneX in [8.0, canvasSize.width - 8])
            [
              from.port,
              from.lead,
              Offset(laneX, from.lead.dy),
              Offset(laneX, to.lead.dy),
              to.lead,
              to.port,
            ],
          for (final laneY in [8.0, canvasSize.height - 8])
            [
              from.port,
              from.lead,
              Offset(from.lead.dx, laneY),
              Offset(to.lead.dx, laneY),
              to.lead,
              to.port,
            ],
        ]);
      }
    }

    final scoredCandidates = candidates.map(_normalizeOrthogonalPath).map(
      (points) {
        return (
          points: points,
          score: _routeScore(
            points,
            edge: edge,
            positions: positions,
            existingRoutes: routes,
            canvasSize: canvasSize,
          ),
        );
      },
    ).toList()
      ..sort((first, second) => first.score.compareTo(second.score));
    routes.add(
      TopologyOrthogonalRoute(
        edge: edge,
        points: scoredCandidates.first.points,
      ),
    );
  }
  return routes;
}

List<Offset> _normalizeOrthogonalPath(List<Offset> points) {
  final result = <Offset>[];
  for (final point in points) {
    if (result.isNotEmpty && result.last == point) continue;
    if (result.length >= 2) {
      final previous = result[result.length - 2];
      final current = result.last;
      final collinear = (previous.dx == current.dx && current.dx == point.dx) ||
          (previous.dy == current.dy && current.dy == point.dy);
      if (collinear) result.removeLast();
    }
    result.add(point);
  }
  return result;
}

double _routeScore(
  List<Offset> points, {
  required MeshTopologyEdge edge,
  required Map<String, Rect> positions,
  required List<TopologyOrthogonalRoute> existingRoutes,
  required Size canvasSize,
}) {
  var score = (points.length - 2) * 18.0;
  for (var index = 0; index < points.length - 1; index++) {
    final start = points[index];
    final end = points[index + 1];
    score += (end - start).distance;
    if (start.dx < 0 ||
        start.dy < 0 ||
        start.dx > canvasSize.width ||
        start.dy > canvasSize.height ||
        end.dx < 0 ||
        end.dy < 0 ||
        end.dx > canvasSize.width ||
        end.dy > canvasSize.height) {
      score += 500000;
    }
    for (final entry in positions.entries) {
      if (entry.key == edge.fromId || entry.key == edge.toId) continue;
      if (_orthogonalSegmentIntersectsRect(
        start,
        end,
        entry.value.inflate(7),
      )) {
        score += 1000000;
      }
    }
    for (final route in existingRoutes) {
      for (var routeIndex = 0;
          routeIndex < route.points.length - 1;
          routeIndex++) {
        score += _segmentConflictScore(
          start,
          end,
          route.points[routeIndex],
          route.points[routeIndex + 1],
        );
      }
    }
  }
  return score;
}

bool _orthogonalSegmentIntersectsRect(Offset start, Offset end, Rect rect) {
  if (start.dx == end.dx) {
    final top = math.min(start.dy, end.dy);
    final bottom = math.max(start.dy, end.dy);
    return start.dx > rect.left &&
        start.dx < rect.right &&
        bottom > rect.top &&
        top < rect.bottom;
  }
  final left = math.min(start.dx, end.dx);
  final right = math.max(start.dx, end.dx);
  return start.dy > rect.top &&
      start.dy < rect.bottom &&
      right > rect.left &&
      left < rect.right;
}

double _segmentConflictScore(
  Offset firstStart,
  Offset firstEnd,
  Offset secondStart,
  Offset secondEnd,
) {
  final firstVertical = firstStart.dx == firstEnd.dx;
  final secondVertical = secondStart.dx == secondEnd.dx;
  if (firstVertical == secondVertical) {
    final sameLane = firstVertical
        ? firstStart.dx == secondStart.dx
        : firstStart.dy == secondStart.dy;
    if (!sameLane) return 0;
    final firstMin = firstVertical
        ? math.min(firstStart.dy, firstEnd.dy)
        : math.min(firstStart.dx, firstEnd.dx);
    final firstMax = firstVertical
        ? math.max(firstStart.dy, firstEnd.dy)
        : math.max(firstStart.dx, firstEnd.dx);
    final secondMin = secondVertical
        ? math.min(secondStart.dy, secondEnd.dy)
        : math.min(secondStart.dx, secondEnd.dx);
    final secondMax = secondVertical
        ? math.max(secondStart.dy, secondEnd.dy)
        : math.max(secondStart.dx, secondEnd.dx);
    final overlap =
        math.min(firstMax, secondMax) - math.max(firstMin, secondMin);
    return overlap > 0 ? 1500 + overlap * 25 : 0;
  }
  final verticalStart = firstVertical ? firstStart : secondStart;
  final verticalEnd = firstVertical ? firstEnd : secondEnd;
  final horizontalStart = firstVertical ? secondStart : firstStart;
  final horizontalEnd = firstVertical ? secondEnd : firstEnd;
  final crosses =
      verticalStart.dx >= math.min(horizontalStart.dx, horizontalEnd.dx) &&
          verticalStart.dx <= math.max(horizontalStart.dx, horizontalEnd.dx) &&
          horizontalStart.dy >= math.min(verticalStart.dy, verticalEnd.dy) &&
          horizontalStart.dy <= math.max(verticalStart.dy, verticalEnd.dy);
  return crosses ? 280 : 0;
}

class _TopologyLegend extends StatelessWidget {
  const _TopologyLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 18,
      runSpacing: 12,
      children: [
        _LegendItem(color: Color(0xFF7AA8FF), label: 'Big Peer'),
        _LegendItem(color: Color(0xFFB48CFF), label: 'Bluetooth'),
        _LegendItem(color: Color(0xFF78F0C6), label: 'LAN / Access Point'),
        _LegendItem(color: Color(0xFFFFC56F), label: 'P2P Wi-Fi'),
        _LegendItem(color: Color(0xFF65C9FF), label: 'Peer WebSocket'),
        _LegendItem(color: Color(0xFF9FB3C8), label: 'SDK peer'),
        _LegendItem(color: Color(0xFFFF7A86), label: 'Not connected'),
        _ReconnectLegendItem(),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: ValueKey('legend-marker-$label'),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFC3CBD6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

class _ReconnectLegendItem extends StatelessWidget {
  const _ReconnectLegendItem();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: const ValueKey('legend-marker-reconnecting'),
            width: 22,
            height: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var index = 0; index < 3; index++)
                  Container(
                    width: 5,
                    height: 2,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC3CBD6),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          const Text(
            'Reconnecting',
            style: TextStyle(
              color: Color(0xFFC3CBD6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

String _selectedConnectionLabel({
  required MeshTopologyEdge edge,
  required MeshTopologyNode selectedNode,
  required String otherNodeLabel,
}) {
  final reconnecting = edge.isReconnecting ? ' · Reconnecting' : '';
  if (edge.isBigPeer) {
    return selectedNode.isBigPeer
        ? 'Cloud$reconnecting → $otherNodeLabel'
        : 'Big Peer / Ditto Server$reconnecting';
  }
  return '${_transportName(edge.kind!)}$reconnecting → $otherNodeLabel';
}

({String label, Color color}) _routeFor(MeshPeerStatus? status) {
  if (status == null) {
    return (label: 'NOT CONNECTED', color: const Color(0xFFFF7A86));
  }
  if (status.connectedToDittoServer && status.hasPeerToPeerConnection) {
    return (label: 'BIG PEER + MESH', color: const Color(0xFF7AA8FF));
  }
  if (status.connectedToDittoServer) {
    return (label: 'BIG PEER', color: const Color(0xFF7AA8FF));
  }
  if (status.hasPeerToPeerConnection) {
    return (label: 'MESH ONLY', color: const Color(0xFF78F0C6));
  }
  return (label: 'NOT CONNECTED', color: const Color(0xFFFF7A86));
}

@visibleForTesting
({
  Map<String, Rect> positions,
  double height,
  double? disconnectedLabelTop,
}) topologyNodePositionsForTesting({
  required List<MeshTopologyNode> nodes,
  required List<MeshTopologyEdge> edges,
  required double width,
}) {
  const minimumNodeWidth = 190.0;
  const maximumNodeWidth = 280.0;
  const horizontalPadding = 16.0;
  const gap = 72.0;
  final usableWidth = math.max(0.0, width - horizontalPadding * 2);
  final columns = math.max(
    1,
    math.min(3, ((usableWidth + gap) / (minimumNodeWidth + gap)).floor()),
  );
  final cardWidth = math
      .max(
        minimumNodeWidth,
        (usableWidth - gap * (columns - 1)) / columns,
      )
      .clamp(minimumNodeWidth, maximumNodeWidth);
  final gridWidth = cardWidth * columns + gap * (columns - 1);
  final gridLeft = (width - gridWidth) / 2;
  const bigPeerWidth = 154.0;
  const bigPeerHeight = 76.0;
  const deviceHeight = 142.0;
  const topOffset = 160.0;
  const rowGap = 80.0;
  const disconnectedSectionGap = 112.0;

  final connectedNodeIds = <String>{};
  for (final edge in edges) {
    connectedNodeIds
      ..add(edge.fromId)
      ..add(edge.toId);
  }
  final connectedNodes = <MeshTopologyNode>[];
  final disconnectedNodes = <MeshTopologyNode>[];
  for (final node in nodes) {
    final statusHasConnection = node.status != null &&
        (node.status!.connectedToDittoServer ||
            node.status!.hasPeerToPeerConnection);
    final sdkPeerHasConnection = node.sdkPeer?.connectedToDittoServer ?? false;
    if (connectedNodeIds.contains(node.id) ||
        statusHasConnection ||
        sdkPeerHasConnection) {
      connectedNodes.add(node);
    } else {
      disconnectedNodes.add(node);
    }
  }

  int rowCount(int itemCount) => (itemCount / columns).ceil();

  double sectionHeight(int itemCount) {
    final rows = rowCount(itemCount);
    if (rows == 0) return 0;
    return rows * deviceHeight + (rows - 1) * rowGap;
  }

  final connectedHeight = sectionHeight(connectedNodes.length);
  final disconnectedTop = connectedNodes.isEmpty
      ? topOffset
      : topOffset + connectedHeight + disconnectedSectionGap;
  final disconnectedLabelTop =
      connectedNodes.isNotEmpty && disconnectedNodes.isNotEmpty
          ? topOffset + connectedHeight + 46
          : null;
  final positions = <String, Rect>{
    bigPeerTopologyNodeId: Rect.fromLTWH(
      (width - bigPeerWidth) / 2,
      0,
      bigPeerWidth,
      bigPeerHeight,
    ),
  };

  void positionSection(List<MeshTopologyNode> section, double sectionTop) {
    for (var index = 0; index < section.length; index++) {
      final row = index ~/ columns;
      final column = index % columns;
      positions[section[index].id] = Rect.fromLTWH(
        gridLeft + column * (cardWidth + gap),
        sectionTop + row * (deviceHeight + rowGap),
        cardWidth,
        deviceHeight,
      );
    }
  }

  positionSection(connectedNodes, topOffset);
  positionSection(disconnectedNodes, disconnectedTop);

  final devicesBottom = disconnectedNodes.isNotEmpty
      ? disconnectedTop + sectionHeight(disconnectedNodes.length)
      : connectedNodes.isNotEmpty
          ? topOffset + connectedHeight
          : bigPeerHeight;
  return (
    positions: positions,
    height: math.max(bigPeerHeight, devicesBottom),
    disconnectedLabelTop: disconnectedLabelTop,
  );
}

Color _transportColor(MeshConnectionKind kind) => switch (kind) {
      MeshConnectionKind.bluetooth => const Color(0xFFB48CFF),
      MeshConnectionKind.accessPoint => const Color(0xFF78F0C6),
      MeshConnectionKind.p2pWifi => const Color(0xFFFFC56F),
      MeshConnectionKind.webSocket => const Color(0xFF65C9FF),
    };

String _transportLabel(MeshConnectionKind kind) => switch (kind) {
      MeshConnectionKind.bluetooth => 'BLE',
      MeshConnectionKind.accessPoint => 'LAN',
      MeshConnectionKind.p2pWifi => 'P2P',
      MeshConnectionKind.webSocket => 'WS',
    };

String _transportName(MeshConnectionKind kind) => switch (kind) {
      MeshConnectionKind.bluetooth => 'Bluetooth',
      MeshConnectionKind.accessPoint => 'LAN / Access Point',
      MeshConnectionKind.p2pWifi => 'P2P Wi-Fi',
      MeshConnectionKind.webSocket => 'Peer WebSocket',
    };
