import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';

/// Holds MQTT credentials fetched from the ProvisionService API.
class MqttCredentials {
  final String topic;
  final String username;
  final String password;
  final String? host;
  final int? port;
  final bool? oem;
  final bool? ems;
  final String? type;

  const MqttCredentials({
    required this.topic,
    required this.username,
    required this.password,
    this.host,
    this.port,
    this.oem,
    this.ems,
    this.type,
  });

  factory MqttCredentials.fromJson(Map<String, dynamic> json) {
    int? parsedPort;
    final rawPort = json['port'] ?? json['Port'];
    if (rawPort != null) {
      parsedPort = int.tryParse(rawPort.toString());
    }
    final rawHost = json['ip'] ??
        json['IP'] ??
        json['host'] ??
        json['Host'] ??
        json['broker'] ??
        json['Broker'];
    return MqttCredentials(
      topic: (json['topic'] ?? json['Topic'] ?? '').toString(),
      username: (json['username'] ?? json['Username'] ?? '').toString(),
      password: (json['password'] ?? json['Password'] ?? '').toString(),
      host: rawHost?.toString(),
      port: parsedPort,
      oem: json['oem'] ?? json['OEM'],
      ems: json['ems'] ?? json['EMS'],
      type: (json['type'] ?? json['Type'])?.toString(),
    );
  }

  @override
  String toString() =>
      'MqttCredentials(topic: $topic, username: $username, host: $host, port: $port, type: $type)';
}

/// Service that fetches MQTT configuration (username, password, topic)
/// from the ProvisionService API instead of using hardcoded values.
///
/// API: GET /provisionservice/v1/companies/{companyId}/mqtt-configs
class MqttConfigService {
  MqttConfigService._();

  /// Cached credentials — avoids repeated API calls.
  static MqttCredentials? _cached;

  /// Whether a fetch is currently in progress (prevents duplicate calls).
  static bool _isFetching = false;

  /// Returns the cached credentials, or null if not yet fetched.
  static MqttCredentials? get cached => _cached;

  /// Clears the cached credentials (e.g. on logout or company switch).
  static void clearCache() {
    _cached = null;
    debugPrint('🔧 [MqttConfigService] Cache cleared');
  }

  /// Manually update or override the cached MQTT credentials (e.g. from user config screen)
  static void updateCachedCredentials({
    required String topic,
    required String username,
    required String password,
    String? host,
    int? port,
    String? type,
  }) {
    _cached = MqttCredentials(
      topic: topic,
      username: username,
      password: password,
      host: host,
      port: port,
      type: type ?? 'AC',
    );
    debugPrint('💾 [MqttConfigService] Updated cached credentials: $_cached');
  }

  /// Fetches MQTT credentials from the API for the logged-in user's company.
  ///
  /// If [type] is provided (e.g. "AC"), only the config matching that type
  /// is returned. Otherwise the first config in the list is used.
  ///
  /// Returns cached credentials on subsequent calls unless [forceRefresh]
  /// is true.
  static Future<MqttCredentials?> fetchMqttConfig({
    String? companyId,
    String? type,
    bool forceRefresh = false,
  }) async {
    // Return cache if available and not forcing refresh
    if (_cached != null && !forceRefresh) {
      debugPrint('✅ [MqttConfigService] Returning cached credentials');
      return _cached;
    }

    // Prevent duplicate simultaneous fetches
    if (_isFetching) {
      debugPrint('⏳ [MqttConfigService] Fetch already in progress, waiting...');
      // Wait for the ongoing fetch to complete
      for (int i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!_isFetching) break;
      }
      return _cached;
    }

    _isFetching = true;

    try {
      // Get company ID from parameter or stored session
      final cId = companyId ?? await AuthService.getCompanyId();
      if (cId == null || cId.isEmpty) {
        debugPrint('⚠️ [MqttConfigService] No company ID available — cannot fetch MQTT config');
        return null;
      }

      // Get auth token
      final token = await AuthService.getCookieHeader();

      final url =
          '${AppConfig.provisionBaseUrl}/companies/$cId/mqtt-configs';
      debugPrint('📡 [MqttConfigService] GET $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          if (token != null && token.isNotEmpty) ...{
            'Authorization': 'Bearer $token',
            'Cookie': 'auth_token=$token',
          },
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint(
          '📡 [MqttConfigService] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);

        if (body['status'] == 1 && body['data'] != null) {
          final List<dynamic> configs = body['data'] is List
              ? body['data']
              : [body['data']];

          if (configs.isEmpty) {
            debugPrint('⚠️ [MqttConfigService] API returned empty configs list');
            return null;
          }

          // Find matching type if specified, otherwise use the first one
          Map<String, dynamic>? matchedConfig;
          if (type != null && type.isNotEmpty) {
            final searchType = type.toLowerCase();
            for (final config in configs) {
              final configType =
                  (config['type'] ?? config['Type'] ?? '').toString().toLowerCase();
              // Match exactly, or via contains (e.g. "ac" matches "ac_compressor")
              if (configType == searchType ||
                  configType.contains(searchType) ||
                  searchType.contains(configType)) {
                matchedConfig = Map<String, dynamic>.from(config);
                debugPrint('🎯 [MqttConfigService] Matched type "$configType" for filter "$searchType"');
                break;
              }
            }
            if (matchedConfig == null) {
              final availableTypes = configs
                  .map((c) => (c['type'] ?? c['Type'] ?? 'null').toString())
                  .toList();
              debugPrint('⚠️ [MqttConfigService] No type match for "$type". Available: $availableTypes. Using first config.');
            }
          }

          // Fallback to first config if no type match
          matchedConfig ??= Map<String, dynamic>.from(configs.first);

          _cached = MqttCredentials.fromJson(matchedConfig);
          debugPrint('✅ [MqttConfigService] Fetched MQTT config: $_cached');
          return _cached;
        } else {
          debugPrint(
              '⚠️ [MqttConfigService] API returned status=${body['status']}, message=${body['message']}');
          return null;
        }
      } else if (response.statusCode == 404) {
        debugPrint(
            '⚠️ [MqttConfigService] No MQTT config found for company $cId');
        return null;
      } else {
        debugPrint(
            '❌ [MqttConfigService] API error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ [MqttConfigService] Fetch error: $e');
      return null;
    } finally {
      _isFetching = false;
    }
  }
}
