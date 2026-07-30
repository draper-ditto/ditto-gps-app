import 'mesh_peer_status.dart';

class UserPresence {
  const UserPresence({
    required this.id,
    required this.username,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.updatedAt,
    this.isDeleted = false,
    this.liveMeshStatus,
  });

  final String id;
  final String username;
  final double latitude;
  final double longitude;
  final String status;
  final DateTime updatedAt;
  final bool isDeleted;
  final MeshPeerStatus? liveMeshStatus;

  factory UserPresence.fromJson(Map<String, dynamic> json) {
    return UserPresence(
      id: json['_id'].toString(),
      username: json['username'] as String? ?? 'Unknown',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updatedAt'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
      isDeleted: json['isDeleted'] == true,
      liveMeshStatus: _meshStatusFromJson(json['liveMeshStatus']),
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'username': username,
        'latitude': latitude,
        'longitude': longitude,
        'status': status,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'isDeleted': isDeleted,
        if (liveMeshStatus != null)
          'liveMeshStatus': liveMeshStatus!.toTelemetryJson(),
      };

  static MeshPeerStatus? _meshStatusFromJson(Object? value) {
    if (value is! Map) return null;
    return MeshPeerStatus.fromTelemetryJson(
      value.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
  }
}
