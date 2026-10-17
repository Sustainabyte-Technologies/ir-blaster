import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class LocalCacheService {
  static const String _dashboardCacheKey = 'cache_dashboard_summary';
  static const String _devicePrefix = 'cache_device_';
  static const String _wifiSsidKey = 'wifi_ssid';
  static const String _wifiPasswordKey = 'wifi_password';
  static const String _wifiSsid2Key = 'wifi_ssid_2';
  static const String _wifiPassword2Key = 'wifi_password_2';

  /// Save dashboard data to local storage
  static Future<void> saveDashboardData(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _dashboardCacheKey,
          jsonEncode({
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'data': data,
          }));
    } catch (e) {
      debugPrint('⚠️ [Cache] Error saving dashboard: $e');
    }
  }

  /// Retrieve dashboard data from local storage
  static Future<Map<String, dynamic>?> getDashboardData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString(_dashboardCacheKey);
      if (cached != null) {
        return jsonDecode(cached) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('⚠️ [Cache] Error reading dashboard: $e');
    }
    return null;
  }

  /// Save specific device data (Temp, Hum, Power)
  static Future<void> saveDeviceStatus(
      String deviceId, Map<String, dynamic> status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          '$_devicePrefix$deviceId',
          jsonEncode({
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'status': status,
          }));
    } catch (e) {
      debugPrint('⚠️ [Cache] Error saving device status: $e');
    }
  }

  /// Retrieve specific device data
  static Future<Map<String, dynamic>?> getDeviceStatus(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString('$_devicePrefix$deviceId');
      if (cached != null) {
        return jsonDecode(cached) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('⚠️ [Cache] Error reading device status: $e');
    }
    return null;
  }

  /// Save equipment list for a specific system
  static Future<void> saveEquipmentList(
      String systemId, List<dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'equip_list_$systemId',
          jsonEncode({
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'data': data,
          }));
    } catch (e) {
      debugPrint('⚠️ [Cache] Error saving equip list: $e');
    }
  }

  /// Retrieve equipment list for a specific system
  static Future<List<dynamic>?> getEquipmentList(String systemId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString('equip_list_$systemId');
      if (cached != null) {
        final decoded = jsonDecode(cached);
        return decoded['data'] as List<dynamic>;
      }
    } catch (e) {
      debugPrint('⚠️ [Cache] Error reading equip list: $e');
    }
    return null;
  }

  /// Save WiFi credentials (primary)
  static Future<void> saveWifiCredentials(String ssid, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_wifiSsidKey, ssid);
      await prefs.setString(_wifiPasswordKey, password);
      debugPrint('✅ [Cache] WiFi credentials saved.');
    } catch (e) {
      debugPrint('⚠️ [Cache] Error saving WiFi credentials: $e');
    }
  }

  /// Save secondary WiFi credentials (fallback)
  static Future<void> saveSecondaryWifiCredentials(
      String ssid, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_wifiSsid2Key, ssid);
      await prefs.setString(_wifiPassword2Key, password);
      debugPrint('✅ [Cache] Secondary WiFi credentials saved.');
    } catch (e) {
      debugPrint('⚠️ [Cache] Error saving secondary WiFi credentials: $e');
    }
  }

  /// Retrieve WiFi credentials (primary)
  static Future<Map<String, String>> getWifiCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'ssid': prefs.getString(_wifiSsidKey) ?? '',
        'password': prefs.getString(_wifiPasswordKey) ?? '',
      };
    } catch (e) {
      debugPrint('⚠️ [Cache] Error reading WiFi credentials: $e');
      return {'ssid': '', 'password': ''};
    }
  }

  /// Retrieve secondary WiFi credentials (fallback)
  static Future<Map<String, String>> getSecondaryWifiCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'ssid': prefs.getString(_wifiSsid2Key) ?? '',
        'password': prefs.getString(_wifiPassword2Key) ?? '',
      };
    } catch (e) {
      debugPrint('⚠️ [Cache] Error reading secondary WiFi credentials: $e');
      return {'ssid': '', 'password': ''};
    }
  }

  /// Clear WiFi credentials (primary)
  static Future<void> clearWifiCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_wifiSsidKey);
      await prefs.remove(_wifiPasswordKey);
      debugPrint('🧹 [Cache] Primary WiFi credentials cleared.');
    } catch (e) {
      debugPrint('⚠️ [Cache] Error clearing WiFi credentials: $e');
    }
  }

  /// Clear secondary WiFi credentials (fallback)
  static Future<void> clearSecondaryWifiCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_wifiSsid2Key);
      await prefs.remove(_wifiPassword2Key);
      debugPrint('🧹 [Cache] Secondary WiFi credentials cleared.');
    } catch (e) {
      debugPrint('⚠️ [Cache] Error clearing secondary WiFi credentials: $e');
    }
  }

  /// Save configured schedule slot time & days for a device
  static Future<void> saveScheduleSlotConfig(
      String deviceId, int slot, {String? onTime, String? offTime, String? days, bool? isEnabled}) async {
    if (deviceId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final normKey = 'sched_cfg_${deviceId.trim().toLowerCase()}_$slot';
      final rawKey = 'sched_cfg_${deviceId}_$slot';
      final existingStr = prefs.getString(normKey) ?? prefs.getString(rawKey);
      Map<String, dynamic> data = {};
      if (existingStr != null) {
        try {
          data = jsonDecode(existingStr) as Map<String, dynamic>;
        } catch (_) {}
      }
      if (isEnabled != null) {
        data['isEnabled'] = isEnabled;
      }
      if (onTime != null && onTime != 'DISABLED' && onTime.isNotEmpty && onTime != '--:--') {
        data['onTime'] = onTime;
      }
      if (offTime != null && offTime != 'DISABLED' && offTime.isNotEmpty && offTime != '--:--') {
        data['offTime'] = offTime;
      }
      if (days != null && days != 'DISABLED' && days.isNotEmpty) {
        data['days'] = days;
      }
      await prefs.setString(normKey, jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ [Cache] Error saving schedule slot $slot for $deviceId: $e');
    }
  }

  /// Retrieve configured schedule slot time & days for a device
  static Future<Map<String, dynamic>?> getScheduleSlotConfig(String deviceId, int slot) async {
    if (deviceId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final normKey = 'sched_cfg_${deviceId.trim().toLowerCase()}_$slot';
      final rawKey = 'sched_cfg_${deviceId}_$slot';
      final existingStr = prefs.getString(normKey) ?? prefs.getString(rawKey);
      if (existingStr != null) {
        final data = jsonDecode(existingStr) as Map<String, dynamic>;
        final String? onT = data['onTime']?.toString();
        final String? offT = data['offTime']?.toString();
        final String? d = data['days']?.toString();
        final bool? en = data['isEnabled'] is bool ? data['isEnabled'] as bool : (data['isEnabled']?.toString() == 'true');
        return {
          if (en != null) 'isEnabled': en,
          if (onT != null && onT != 'DISABLED' && onT.isNotEmpty && onT != '--:--') 'onTime': onT,
          if (offT != null && offT != 'DISABLED' && offT.isNotEmpty && offT != '--:--') 'offTime': offT,
          if (d != null && d != 'DISABLED' && d.isNotEmpty) 'days': d,
        };
      }
    } catch (e) {
      debugPrint('⚠️ [Cache] Error reading schedule slot $slot for $deviceId: $e');
    }
    return null;
  }

  /// Clear all cached data (used during logout)
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      debugPrint('🧹 [Cache] All local storage cleared.');
    } catch (e) {
      debugPrint('⚠️ [Cache] Error clearing cache: $e');
    }
  }
}

