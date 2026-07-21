class UserPresence {
  const UserPresence({
    required this.id,
    required this.username,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.updatedAt,
  });

  final String id;
  final String username;
  final double latitude;
  final double longitude;
  final String status;
  final DateTime updatedAt;

  factory UserPresence.fromJson(Map<String, dynamic> json) {
    return UserPresence(
      id: json['_id'].toString(),
      username: json['username'] as String? ?? 'Unknown',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'username': username,
        'latitude': latitude,
        'longitude': longitude,
        'status': status,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };
}

