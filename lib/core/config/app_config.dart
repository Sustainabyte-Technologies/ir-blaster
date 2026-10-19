import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ir_blaster_ac/core/services/mqtt_config_service.dart';

/// Centralised access to environment variables loaded from `.env`.
/// Always access config through this class — never hardcode URLs.
class AppConfig {
  AppConfig._(); // prevent instantiation

  /// Base URL for the authentication service.
  static String get authBaseUrl =>
      dotenv.env['AUTH_BASE_URL'] ?? 'https://optibyte.sustainabyte.ai';

  // ── Derived auth endpoints ────────────────────────────────────────────
  static String get loginEndpoint => '$authBaseUrl/authservice/v1/login';
  static String get verifyEndpoint => '$authBaseUrl/authservice/v1/verify';

  /// Base URL for the ProvisionService backend (equipment, systems, etc.)
  static String get provisionBaseUrl {
    final rawUrl = dotenv.env['PROVISION_BASE_URL'] ??
        'https://optibyte.sustainabyte.ai/provisionservice/v1';
    if (rawUrl.contains('optibyte.sustainabyte.ai') &&
        !rawUrl.contains('/provisionservice/v1')) {
      return '$rawUrl/provisionservice/v1';
    }
    return rawUrl;
  }

  /// Default company ID from environment if available
  static String get companyId => dotenv.env['COMPANY_ID'] ?? '';

  // ── MQTT (SIRIS IR Blaster) ──────────────────────────────────────────
  // Fetched dynamically from MqttConfigService (API) with .env fallbacks.
  // Never hardcode any broker, credentials, root, or device ID.
  static String get mqttBroker {
    final cachedHost = MqttConfigService.cached?.host;
    if (cachedHost != null && cachedHost.isNotEmpty) return cachedHost;
    final envVal = dotenv.env['MQTT_BROKER'];
    if (envVal != null && envVal.isNotEmpty) return envVal;
    return '13.66.130.236';
  }

  static int get mqttPort {
    final cachedPort = MqttConfigService.cached?.port;
    if (cachedPort != null && cachedPort > 0) return cachedPort;
    return int.tryParse(dotenv.env['MQTT_PORT'] ?? '') ?? 1883;
  }

  /// Dynamic MQTT username (strictly from MqttConfigService API cache)
  static String get mqttUsername {
    final cached = MqttConfigService.cached?.username;
    if (cached != null && cached.isNotEmpty) return cached;
    final envVal = dotenv.env['MQTT_USERNAME'];
    if (envVal != null && envVal.isNotEmpty) return envVal;
    return '';
  }

  /// Dynamic MQTT password (strictly from MqttConfigService API cache)
  static String get mqttPassword {
    final cached = MqttConfigService.cached?.password;
    if (cached != null && cached.isNotEmpty) return cached;
    final envVal = dotenv.env['MQTT_PASSWORD'];
    if (envVal != null && envVal.isNotEmpty) return envVal;
    return '';
  }

  /// Dynamic MQTT ROOT topic (strictly from MqttConfigService API cache)
  static String get mqttRoot {
    final cachedTopic = MqttConfigService.cached?.topic;
    if (cachedTopic != null && cachedTopic.isNotEmpty) return cachedTopic;
    final envRoot = dotenv.env['MQTT_ROOT'] ?? dotenv.env['MQTT_TOPIC'];
    if (envRoot != null && envRoot.isNotEmpty) return envRoot;
    final user = mqttUsername;
    if (user.isNotEmpty) return user;
    return '';
  }

  /// Alias for mqttRoot
  static String get mqttTopic => mqttRoot;

  /// Dynamic default data topic: <MQTT_ROOT>/data
  static String get mqttDataTopic =>
      dotenv.env['MQTT_DATA_TOPIC'] ??
      (mqttRoot.isNotEmpty ? '$mqttRoot/data' : 'data');

  static String _defaultMqttDeviceId = '';

  /// The dynamic device_id used in MQTT payloads & device resolution
  static String get mqttDeviceId => _defaultMqttDeviceId.isNotEmpty
      ? _defaultMqttDeviceId
      : (dotenv.env['MQTT_DEVICE_ID'] ?? '');

  static set mqttDeviceId(String value) {
    if (value.isNotEmpty) {
      _defaultMqttDeviceId = value;
    }
  }

  // ── Production Topic Structure (SIRIS Spec Section 15) ───────────────
  //
  // The application treats MQTT ROOT as configurable (e.g. "iaq" or "customer/site/device").
  // Rules from Spec Section 15:
  //   Control    : <MQTT_ROOT>/control
  //   Set Temp   : <MQTT_ROOT>/control/set_temp
  //   Status     : <MQTT_ROOT>/status
  //   Schedule   : <MQTT_ROOT>/schedule
  //   Online     : <MQTT_ROOT>/online
  //   OTA        : <MQTT_ROOT>/ota
  //   WiFi       : <MQTT_ROOT>/wifi
  //   Data       : <MQTT_ROOT>/data
  //
  // "Do NOT automatically append the Device ID to the MQTT ROOT."

  /// Helper to resolve root topic dynamically
  static String resolveRoot([String? customRootOrDevice]) {
    if (customRootOrDevice != null && customRootOrDevice.isNotEmpty) {
      if (customRootOrDevice.contains('/')) {
        return customRootOrDevice;
      }
    }
    return mqttRoot;
  }

  /// AC ON/OFF/STATUS control topic: <MQTT_ROOT>/<deviceId>/control
  static String getMqttControlTopic([String? deviceId]) {
    final root = mqttRoot;
    if (deviceId != null &&
        deviceId.isNotEmpty &&
        deviceId.toLowerCase() != root.toLowerCase()) {
      return root.isNotEmpty ? '$root/$deviceId/control' : '$deviceId/control';
    }
    return root.isNotEmpty ? '$root/control' : 'control';
  }

  /// Dedicated temperature set topic: <MQTT_ROOT>/<deviceId>/control/set_temp
  static String getMqttTempTopic([String? deviceId]) {
    final root = mqttRoot;
    if (deviceId != null &&
        deviceId.isNotEmpty &&
        deviceId.toLowerCase() != root.toLowerCase()) {
      return root.isNotEmpty
          ? '$root/$deviceId/control/set_temp'
          : '$deviceId/control/set_temp';
    }
    return root.isNotEmpty ? '$root/control/set_temp' : 'control/set_temp';
  }

  /// Schedule control topic (Plaintext Mode): <MQTT_ROOT>/<deviceId>/schedule
  static String getMqttScheduleTopic([String? deviceId]) {
    final root = mqttRoot;
    if (deviceId != null &&
        deviceId.isNotEmpty &&
        deviceId.toLowerCase() != root.toLowerCase()) {
      return root.isNotEmpty
          ? '$root/$deviceId/schedule'
          : '$deviceId/schedule';
    }
    return root.isNotEmpty ? '$root/schedule' : 'schedule';
  }

  /// Schedule control topic (SIRIS 2.0 JSON Mode): <MQTT_ROOT>/<deviceId>/schedule
  static String getMqttJsonScheduleTopic(String deviceId) {
    final root = mqttRoot;
    if (root.isNotEmpty &&
        deviceId.isNotEmpty &&
        deviceId.toLowerCase() != root.toLowerCase()) {
      return '$root/$deviceId/schedule';
    }
    return deviceId.isNotEmpty
        ? '$deviceId/schedule'
        : getMqttScheduleTopic(deviceId);
  }

  /// WiFi control and status topic: <MQTT_ROOT>/<deviceId>/wifi
  static String getMqttWifiTopic([String? deviceId]) {
    final root = mqttRoot;
    if (deviceId != null &&
        deviceId.isNotEmpty &&
        deviceId.toLowerCase() != root.toLowerCase()) {
      return root.isNotEmpty ? '$root/$deviceId/wifi' : '$deviceId/wifi';
    }
    return root.isNotEmpty ? '$root/wifi' : 'wifi';
  }

  /// OTA check & update topic: <MQTT_ROOT>/<deviceId>/ota
  static String getMqttOtaTopic([String? deviceId]) {
    final root = mqttRoot;
    if (deviceId != null &&
        deviceId.isNotEmpty &&
        deviceId.toLowerCase() != root.toLowerCase()) {
      return root.isNotEmpty ? '$root/$deviceId/ota' : '$deviceId/ota';
    }
    return root.isNotEmpty ? '$root/ota' : 'ota';
  }

  /// Status topic: <MQTT_ROOT>/<deviceId>/status
  static String getMqttStatusTopic([String? deviceId]) {
    final root = mqttRoot;
    if (deviceId != null &&
        deviceId.isNotEmpty &&
        deviceId.toLowerCase() != root.toLowerCase()) {
      return root.isNotEmpty ? '$root/$deviceId/status' : '$deviceId/status';
    }
    return root.isNotEmpty ? '$root/status' : 'status';
  }

  /// Data telemetry topic: <MQTT_ROOT>/<deviceId>/data
  static String getMqttDataTopic([String? deviceId]) {
    final root = mqttRoot;
    if (deviceId != null &&
        deviceId.isNotEmpty &&
        deviceId.toLowerCase() != root.toLowerCase()) {
      return root.isNotEmpty ? '$root/$deviceId/data' : '$deviceId/data';
    }
    return root.isNotEmpty ? '$root/data' : 'data';
  }

  /// Online status topic: <MQTT_ROOT>/<deviceId>/online
  static String getMqttOnlineTopic([String? deviceId]) {
    final root = mqttRoot;
    if (deviceId != null &&
        deviceId.isNotEmpty &&
        deviceId.toLowerCase() != root.toLowerCase()) {
      return root.isNotEmpty ? '$root/$deviceId/online' : '$deviceId/online';
    }
    return root.isNotEmpty ? '$root/online' : 'online';
  }

  /// IR learn control topic: <MQTT_ROOT>/<deviceId>/control
  static String getMqttIrLearnTopic([String? deviceId]) {
    return getMqttControlTopic(deviceId);
  }

  /// Dedicated IR learn topic: <MQTT_ROOT>/<deviceId>/ir_learn or <MQTT_ROOT>/ir_learn
  static String getMqttLearnTopic([String? deviceId]) {
    final root = mqttRoot;
    if (deviceId != null &&
        deviceId.isNotEmpty &&
        deviceId.toLowerCase() != root.toLowerCase()) {
      return root.isNotEmpty
          ? '$root/$deviceId/ir_learn'
          : '$deviceId/ir_learn';
    }
    return root.isNotEmpty ? '$root/ir_learn' : 'ir_learn';
  }

  // Legacy getters
  static String get mqttControlTopic => getMqttControlTopic();
  static String get mqttScheduleTopic => getMqttScheduleTopic();
  static String get mqttStatusTopic => getMqttStatusTopic();

  /// Prefix used in MQTT payloads, e.g. ":STATUS_OFFLINE"
  static String get mqttPayloadPrefix =>
      dotenv.env['MQTT_PAYLOAD_PREFIX'] ?? mqttDeviceId;

  /// Default starting set temperature for AC control (24°C).
  static const double defaultSetTemp = 24.0;
}
