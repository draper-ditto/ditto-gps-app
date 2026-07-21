import 'dart:convert';

import 'package:http/http.dart' as http;

class AppConfig {
  const AppConfig({
    required this.databaseId,
    required this.serverUrl,
    required this.playgroundToken,
  });

  final String databaseId;
  final String serverUrl;
  final String playgroundToken;

  static const _databaseId = String.fromEnvironment('DITTO_DATABASE_ID');
  static const _serverUrl = String.fromEnvironment('DITTO_SERVER_URL');
  static const _token = String.fromEnvironment('DITTO_PLAYGROUND_TOKEN');
  static const _backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:8080',
  );

  static Future<AppConfig> load() async {
    if (_databaseId.isNotEmpty && _serverUrl.isNotEmpty && _token.isNotEmpty) {
      return const AppConfig(
        databaseId: _databaseId,
        serverUrl: _serverUrl,
        playgroundToken: _token,
      );
    }

    final response = await http
        .get(Uri.parse('$_backendUrl/api/ditto-config'))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError(
        'The backend returned ${response.statusCode} while loading Ditto config.',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final config = AppConfig(
      databaseId: json['databaseId'] as String? ?? '',
      serverUrl: json['serverUrl'] as String? ?? '',
      playgroundToken: json['playgroundToken'] as String? ?? '',
    );
    if (config.databaseId.isEmpty ||
        config.serverUrl.isEmpty ||
        config.playgroundToken.isEmpty) {
      throw StateError('The backend Ditto configuration is incomplete.');
    }
    return config;
  }
}

