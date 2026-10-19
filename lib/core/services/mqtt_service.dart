import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/core/services/mqtt_config_service.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// Represents the live device state parsed from the SIRIS JSON snapshot.
class SirisDeviceState {
  final String deviceId;
  final String imei;
  final String wifiMac;
  final String ac; // "ON" or "OFF"
  final int setTemp;
  final int currentTemp;
  final int humidity;
  final bool irOnLearned;
  final bool irOffLearned;
  final String status; // "ACTIVE" or "INACTIVE"
  final String wifiSsid;
  final String wifiIp;
  final String wifiNetwork; // PRIMARY or SECONDARY
  final int wifiRssi;
  final String time;
  final String primarySsid;
  final String secondarySsid;
  final bool automate; // Smart Automation state

  // Schedule slots
  final String schOn1;
  final String schOff1;
  final String schDays1;
  final String schOn2;
  final String schOff2;
  final String schDays2;
  final String schOn3;
  final String schOff3;
  final String schDays3;
  final String schOn4;
  final String schOff4;
  final String schDays4;
  final String schOn5;
  final String schOff5;
  final String schDays5;
  final String lunchOn;
  final String lunchOff;
  final String lunchDays;

  SirisDeviceState({
    required this.deviceId,
    required this.imei,
    this.wifiMac = '',
    required this.ac,
    required this.setTemp,
    required this.currentTemp,
    required this.humidity,
    required this.irOnLearned,
    required this.irOffLearned,
    required this.status,
    required this.wifiSsid,
    required this.wifiIp,
    required this.wifiNetwork,
    required this.wifiRssi,
    required this.time,
    required this.schOn1,
    required this.schOff1,
    this.schDays1 = 'ALL',
    required this.schOn2,
    required this.schOff2,
    this.schDays2 = 'ALL',
    required this.schOn3,
    required this.schOff3,
    this.schDays3 = 'ALL',
    required this.schOn4,
    required this.schOff4,
    this.schDays4 = 'ALL',
    required this.schOn5,
    required this.schOff5,
    this.schDays5 = 'ALL',
    required this.lunchOn,
    required this.lunchOff,
    this.lunchDays = 'ALL',
    this.primarySsid = '',
    this.secondarySsid = '',
    this.automate = false,
  });

  SirisDeviceState copyWith({
    String? deviceId,
    String? imei,
    String? wifiMac,
    String? ac,
    int? setTemp,
    int? currentTemp,
    int? humidity,
    bool? irOnLearned,
    bool? irOffLearned,
    String? status,
    String? wifiSsid,
    String? wifiIp,
    String? wifiNetwork,
    int? wifiRssi,
    String? time,
    String? primarySsid,
    String? secondarySsid,
    String? schOn1,
    String? schOff1,
    String? schDays1,
    String? schOn2,
    String? schOff2,
    String? schDays2,
    String? schOn3,
    String? schOff3,
    String? schDays3,
    String? schOn4,
    String? schOff4,
    String? schDays4,
    String? schOn5,
    String? schOff5,
    String? schDays5,
    String? lunchOn,
    String? lunchOff,
    String? lunchDays,
    bool? automate,
  }) {
    return SirisDeviceState(
      deviceId: deviceId ?? this.deviceId,
      imei: imei ?? this.imei,
      wifiMac: wifiMac ?? this.wifiMac,
      ac: ac ?? this.ac,
      setTemp: setTemp ?? this.setTemp,
      currentTemp: currentTemp ?? this.currentTemp,
      humidity: humidity ?? this.humidity,
      irOnLearned: irOnLearned ?? this.irOnLearned,
      irOffLearned: irOffLearned ?? this.irOffLearned,
      status: status ?? this.status,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      wifiIp: wifiIp ?? this.wifiIp,
      wifiNetwork: wifiNetwork ?? this.wifiNetwork,
      wifiRssi: wifiRssi ?? this.wifiRssi,
      time: time ?? this.time,
      primarySsid: primarySsid ?? this.primarySsid,
      secondarySsid: secondarySsid ?? this.secondarySsid,
      schOn1: schOn1 ?? this.schOn1,
      schOff1: schOff1 ?? this.schOff1,
      schDays1: schDays1 ?? this.schDays1,
      schOn2: schOn2 ?? this.schOn2,
      schOff2: schOff2 ?? this.schOff2,
      schDays2: schDays2 ?? this.schDays2,
      schOn3: schOn3 ?? this.schOn3,
      schOff3: schOff3 ?? this.schOff3,
      schDays3: schDays3 ?? this.schDays3,
      schOn4: schOn4 ?? this.schOn4,
      schOff4: schOff4 ?? this.schOff4,
      schDays4: schDays4 ?? this.schDays4,
      schOn5: schOn5 ?? this.schOn5,
      schOff5: schOff5 ?? this.schOff5,
      schDays5: schDays5 ?? this.schDays5,
      lunchOn: lunchOn ?? this.lunchOn,
      lunchOff: lunchOff ?? this.lunchOff,
      lunchDays: lunchDays ?? this.lunchDays,
      automate: automate ?? this.automate,
    );
  }

  bool get isActive =>
      status.toUpperCase() == 'ACTIVE' ||
      status.toUpperCase() == 'ON' ||
      status.toUpperCase() == 'OFF';
  bool get isPowerOn => ac.toUpperCase() == 'ON';

  factory SirisDeviceState.fromJson(Map<String, dynamic> json,
      [SirisDeviceState? previousState]) {
    // Resolve the root object containing the device metadata.
    Map<String, dynamic> root = json;
    if (json['data'] is Map<String, dynamic>) {
      final innerData = json['data'] as Map<String, dynamic>;
      if (innerData.containsKey('device_id') ||
          innerData.containsKey('deviceId')) {
        root = innerData;
      }
    }

    // Resolve the payload object containing telemetry values.
    Map<String, dynamic> payload = root;
    if (root['data'] is Map<String, dynamic>) {
      payload = root['data'] as Map<String, dynamic>;
    }

    // Extract fields from raw_payload if present (e.g. from backend SSE wrapping)
    Map<String, dynamic> rawObj = {};
    final dynamic rawPayloadField =
        root['raw_payload'] ?? json['raw_payload'] ?? payload['raw_payload'];
    if (rawPayloadField is String && rawPayloadField.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawPayloadField);
        if (parsed is Map<String, dynamic>) {
          rawObj = parsed;
          if (rawObj['data'] is Map<String, dynamic>) {
            rawObj.addAll(rawObj['data'] as Map<String, dynamic>);
          }
        }
      } catch (_) {}
    }

    String getSch(String key,
        [String? previousVal, String fallback = 'DISABLED', String? altKey]) {
      final v = root[key] ??
          payload[key] ??
          rawObj[key] ??
          (altKey != null
              ? (root[altKey] ?? payload[altKey] ?? rawObj[altKey])
              : null);
      if (v == null) return previousVal ?? fallback;
      final str = v.toString().trim();
      return str.isEmpty ? (previousVal ?? fallback) : str;
    }

    return SirisDeviceState(
      deviceId:
          (root['device_id'] ?? root['deviceId'] ?? rawObj['device_id'] ?? '')
              .toString(),
      imei: (root['imei'] ?? rawObj['imei'] ?? '').toString(),
      wifiMac: (root['mac'] ??
              root['wifi_mac'] ??
              root['mac_id'] ??
              root['mac_address'] ??
              root['macAddress'] ??
              root['bssid'] ??
              payload['mac'] ??
              payload['wifi_mac'] ??
              payload['mac_id'] ??
              payload['mac_address'] ??
              payload['macAddress'] ??
              payload['bssid'] ??
              rawObj['mac'] ??
              rawObj['wifi_mac'] ??
              rawObj['mac_id'] ??
              '')
          .toString(),
      ac: (payload['ac'] ?? root['ac'] ?? rawObj['ac'] ?? 'OFF')
          .toString()
          .toUpperCase(),
      setTemp: _toInt(
          root['set_temp'] ??
              payload['set_temp'] ??
              rawObj['set_temp'] ??
              root['setTemp'] ??
              payload['setTemp'],
          24),
      currentTemp: () {
        int parsed = _toInt(
            root['current_temp'] ??
                payload['temp'] ??
                payload['current_temp'] ??
                rawObj['current_temp'] ??
                rawObj['temp'] ??
                root['currentTemp'] ??
                payload['currentTemp'],
            0);

        final bool isOffsetApplied = (root['temp_offset_applied'] == true) ||
            (payload['temp_offset_applied'] == true) ||
            (rawObj['temp_offset_applied'] == true);

        if (!isOffsetApplied && parsed > 0) {
          final double offset = MqttConfigService.cached?.tempOffset ?? 0.0;
          if (offset != 0.0) {
            parsed = (parsed + offset).round().clamp(0, 50);
          }
        }
        return parsed;
      }(),
      humidity: _toInt(
          root['hum'] ??
              payload['hum'] ??
              rawObj['hum'] ??
              root['humidity'] ??
              payload['humidity'],
          0),
      irOnLearned: (root['ir_on_learned'] ??
              payload['ir_on_learned'] ??
              rawObj['ir_on_learned'] ??
              root['irOnLearned'] ??
              payload['irOnLearned']) ==
          true,
      irOffLearned: (root['ir_off_learned'] ??
              payload['ir_off_learned'] ??
              rawObj['ir_off_learned'] ??
              root['irOffLearned'] ??
              payload['irOffLearned']) ==
          true,
      status:
          (root['status'] ?? payload['status'] ?? rawObj['status'] ?? 'ACTIVE')
              .toString()
              .toUpperCase(),
      wifiSsid: (root['wifi_ssid'] ??
              payload['wifi_ssid'] ??
              rawObj['wifi_ssid'] ??
              root['wifiSsid'] ??
              payload['wifiSsid'] ??
              '')
          .toString(),
      wifiIp: (root['wifi_ip'] ??
              payload['wifi_ip'] ??
              rawObj['wifi_ip'] ??
              root['wifiIp'] ??
              payload['wifiIp'] ??
              '')
          .toString(),
      wifiNetwork: (root['wifi_network'] ??
              payload['wifi_network'] ??
              rawObj['wifi_network'] ??
              root['wifiNetwork'] ??
              payload['wifiNetwork'] ??
              '')
          .toString(),
      wifiRssi: _toInt(
          root['wifi_rssi'] ??
              payload['wifi_rssi'] ??
              rawObj['wifi_rssi'] ??
              root['wifiRssi'] ??
              payload['wifiRssi'],
          0),
      time:
          (payload['time'] ?? root['time'] ?? rawObj['time'] ?? '').toString(),
      schOn1: getSch('sch_on1', previousState?.schOn1, 'DISABLED', 'on1'),
      schOff1: getSch('sch_off1', previousState?.schOff1, 'DISABLED', 'off1'),
      schDays1: getSch('sch_days1', previousState?.schDays1, 'ALL', 'days1'),
      schOn2: getSch('sch_on2', previousState?.schOn2, 'DISABLED', 'on2'),
      schOff2: getSch('sch_off2', previousState?.schOff2, 'DISABLED', 'off2'),
      schDays2: getSch('sch_days2', previousState?.schDays2, 'ALL', 'days2'),
      schOn3: getSch('sch_on3', previousState?.schOn3, 'DISABLED', 'on3'),
      schOff3: getSch('sch_off3', previousState?.schOff3, 'DISABLED', 'off3'),
      schDays3: getSch('sch_days3', previousState?.schDays3, 'ALL', 'days3'),
      schOn4: getSch('sch_on4', previousState?.schOn4, 'DISABLED', 'on4'),
      schOff4: getSch('sch_off4', previousState?.schOff4, 'DISABLED', 'off4'),
      schDays4: getSch('sch_days4', previousState?.schDays4, 'ALL', 'days4'),
      schOn5: getSch('sch_on5', previousState?.schOn5, 'DISABLED', 'on5'),
      schOff5: getSch('sch_off5', previousState?.schOff5, 'DISABLED', 'off5'),
      schDays5: getSch('sch_days5', previousState?.schDays5, 'ALL', 'days5'),
      lunchOn: getSch('lunch_on', previousState?.lunchOn, 'DISABLED', 'lunchOn'),
      lunchOff: getSch('lunch_off', previousState?.lunchOff, 'DISABLED', 'lunchOff'),
      lunchDays: getSch('lunch_days', previousState?.lunchDays, 'ALL', 'lunchDays'),
      primarySsid: (root['wifi_primary_ssid'] ??
              root['primary_ssid'] ??
              payload['wifi_primary_ssid'] ??
              payload['primary_ssid'] ??
              '')
          .toString(),
      secondarySsid: (root['wifi_secondary_ssid'] ??
              root['secondary_ssid'] ??
              payload['wifi_secondary_ssid'] ??
              payload['secondary_ssid'] ??
              '')
          .toString(),
      automate:
          (root['automate'] ?? payload['automate'] ?? rawObj['automate']) ==
              true,
    );
  }

  static int _toInt(dynamic val, int fallback) {
    if (val == null) return fallback;
    if (val is int) return val;
    if (val is double) return val.toInt();
    return int.tryParse(val.toString()) ?? fallback;
  }
}

/// MQTT response types from the SIRIS device.
enum SirisResponseType {
  acOnDone,
  acOffDone,
  tempSet,
  tempError,
  scheduleSet,
  scheduleCleared,
  scheduleError,
  scheduleUpdated,
  scheduleUpdatedWithErrors,
  cmdRejected,
  cmdError,
  unknown,
  jsonSnapshot,
  wifiPrimarySet,
  wifiSecondarySet,
  wifiResetBtOpen,
  wifiInfo,
  wifiError,
  wifiRollback,
  automateSet,
  automateError,
  irLearnWaiting,
  irLearnSaved,
  irLearnCleared,
  irLearnStopped,
  irLearnStatus,
  irLearnError,
}

/// Parsed command response from the device.
class SirisResponse {
  final SirisResponseType type;
  final String rawPayload;
  final String? detail;
  final String? deviceId;

  SirisResponse({
    required this.type,
    required this.rawPayload,
    this.detail,
    this.deviceId,
  });
}

/// ─── MqttService ─────────────────────────────────────────────────────────
/// Singleton MQTT service for SIRIS IR Blaster communication.
///
/// CRITICAL RULES (from spec):
/// 1. retain = false on every publish
/// 2. Plain text only to command topics — never JSON
/// 3. Never send DISABLED — use SCH_CLEARx commands
/// 4. Never echo back values from JSON
/// 5. Subscribe to
/// /data before sending any command
/// 6. Send STATUS on startup
/// 7. Only publish on explicit user action
/// 8. Wait for ack before confirming UI update
/// 9. If status = INACTIVE → disable controls
/// 10. If ir_on_learned = false → warn user
/// 11. Time format: HH:MM (24hr, zero padded)
/// 12. Temperature: integer only
class MqttService extends ChangeNotifier {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? _client;
  bool _isConnecting = false;
  int _connectionAttempt = 0;
  bool _isConnected = false;
  String _deviceId = '';
  String get deviceId => _deviceId;

  void setDeviceId(String id, {String? imei}) {
    if (id.isNotEmpty && (id != _deviceId || imei != _imei)) {
      _deviceId = id;
      _imei = (imei != null && !isPlaceholderId(imei)) ? imei : null;
      AppConfig.mqttDeviceId = id;
      _subscribeToDataTopic();
      _startSseStream(_companyId, _deviceId, _imei);
    }
  }

  /// Public accessor to publish raw message to any topic.
  Future<bool> publishToTopic(String topic, String message) async {
    return await _publish(topic, message);
  }

  String _companyId = '';
  Timer? _sseWatchdogTimer;
  BluetoothConnection? _bluetoothConnection;
  BluetoothConnection? get bluetoothConnection => _bluetoothConnection;
  set bluetoothConnection(BluetoothConnection? conn) {
    _bluetoothConnection = conn;
    if (conn != null && conn.isConnected) {
      _listenBluetoothConnection(conn);
    }
  }

  BluetoothDevice? bluetoothDevice;
  bool get isBluetoothConnected => _bluetoothConnection?.isConnected == true;
  String? _imei;
  StreamSubscription? _sseSub;

  bool _isSseConnected = false;
  bool get isSseConnected => _isSseConnected;

  DateTime? _sseLastDataTime;
  DateTime? get sseLastDataTime => _sseLastDataTime;

  String? _sseLastPayload;
  String? get sseLastPayload => _sseLastPayload;

  String get sseStreamUrl {
    final queryParams = <String>[];
    if (_companyId.isNotEmpty) {
      queryParams.add('companyid=$_companyId');
    }
    if (_deviceId.isNotEmpty) {
      queryParams.add('deviceId=$_deviceId');
    }
    if (_imei != null && _imei!.isNotEmpty) {
      queryParams.add('imei=$_imei');
    }
    return '${AppConfig.provisionBaseUrl}/mqtt/stream?${queryParams.join('&')}';
  }

  String _incomingBtBuffer = '';
  void _listenBluetoothConnection(BluetoothConnection conn) {
    conn.input?.listen((Uint8List data) {
      final chunk = String.fromCharCodes(data);
      _incomingBtBuffer += chunk;

      String line;
      while ((line = _extractBtLine()) != "") {
        _handleBtLine(line.trim());
      }
    }, onError: (err) {
      debugPrint('❌ [Bluetooth] Rx Error: $err');
    }, onDone: () {
      debugPrint('📡 [Bluetooth] Connection closed by remote');
      _bluetoothConnection = null;
      bluetoothDevice = null;
      notifyListeners();
    });
  }

  String _extractBtLine() {
    if (_incomingBtBuffer.isEmpty) return "";
    final nIdx = _incomingBtBuffer.indexOf('\n');
    final rIdx = _incomingBtBuffer.indexOf('\r');

    if (nIdx == -1 && rIdx == -1) return "";
    int idx;
    if (nIdx == -1) {
      idx = rIdx;
    } else if (rIdx == -1) {
      idx = nIdx;
    } else {
      idx = (nIdx < rIdx) ? nIdx : rIdx;
    }

    final line = _incomingBtBuffer.substring(0, idx);
    int cut = idx + 1;
    if (idx + 1 < _incomingBtBuffer.length) {
      final a = _incomingBtBuffer[idx];
      final b = _incomingBtBuffer[idx + 1];
      if (a == '\r' && b == '\n') cut = idx + 2;
    }
    _incomingBtBuffer = _incomingBtBuffer.substring(cut);
    return line;
  }

  void _handleBtLine(String line) {
    if (line.isEmpty) return;
    debugPrint('📡 [Bluetooth] RX: $line');

    if (line.startsWith("TEMP:")) {
      final valStr = line.replaceFirst("TEMP:", "").trim();
      final val = int.tryParse(valStr);
      if (val != null) {
        _updateLocalBluetoothState(currentTemp: val);
      }
    } else if (line.startsWith("STATUS:") || line.startsWith("STATE:")) {
      final parts = line.split(":");
      if (parts.length > 1) {
        final subParts = parts[1].split(",");
        if (subParts.isNotEmpty) {
          final pwr = subParts[0].toUpperCase() == "ON" ? "ON" : "OFF";
          int? temp;
          if (subParts.length > 1) {
            temp = int.tryParse(subParts[1]);
          }
          _updateLocalBluetoothState(ac: pwr, setTemp: temp);
        }
      }
    }
  }

  void _updateLocalBluetoothState(
      {String? ac, int? setTemp, int? currentTemp, bool? automate}) {
    if (_deviceId.isEmpty) return;
    final lowerId = _deviceId.toLowerCase();
    final existingState = _deviceStates[lowerId] ??
        lastState ??
        SirisDeviceState(
          deviceId: _deviceId,
          imei: _imei ?? _deviceId,
          ac: 'OFF',
          setTemp: 24,
          currentTemp: 24,
          humidity: 50,
          irOnLearned: true,
          irOffLearned: true,
          status: 'ACTIVE',
          wifiSsid: '',
          wifiIp: '',
          wifiNetwork: 'PRIMARY',
          wifiRssi: -50,
          time: '12:00',
          schOn1: 'DISABLED',
          schOff1: 'DISABLED',
          schOn2: 'DISABLED',
          schOff2: 'DISABLED',
          schOn3: 'DISABLED',
          schOff3: 'DISABLED',
          schOn4: 'DISABLED',
          schOff4: 'DISABLED',
          schOn5: 'DISABLED',
          schOff5: 'DISABLED',
          lunchOn: 'DISABLED',
          lunchOff: 'DISABLED',
          automate: false,
        );
    final newState = existingState.copyWith(
      ac: ac,
      setTemp: setTemp,
      currentTemp: currentTemp,
      automate: automate,
    );
    _deviceStates[lowerId] = newState;
    _recordLastReceivedTime(lowerId);
    _lastState = newState;
    _stateController.add(newState);
    notifyListeners();
  }

  Future<void> sendBluetoothCommand(String cmd) async {
    if (_bluetoothConnection == null || !_bluetoothConnection!.isConnected) {
      debugPrint('⚠️ [Bluetooth] Connection is not active.');
      return;
    }
    try {
      debugPrint('📡 [Bluetooth] TX: $cmd');
      _bluetoothConnection!.output
          .add(Uint8List.fromList(utf8.encode("$cmd\r\n")));
      await _bluetoothConnection!.output.allSent;

      if (cmd == 'SEND:ON') {
        _updateLocalBluetoothState(ac: 'ON');
      } else if (cmd == 'SEND:OFF') {
        _updateLocalBluetoothState(ac: 'OFF');
      } else if (cmd.startsWith('SEND:TEMP_')) {
        final tStr = cmd.replaceFirst('SEND:TEMP_', '');
        final t = int.tryParse(tStr);
        if (t != null) {
          _updateLocalBluetoothState(setTemp: t);
        }
      } else if (cmd == 'TEMP_UP') {
        final cur = lastState?.setTemp ?? 24;
        if (cur < 30) {
          _updateLocalBluetoothState(setTemp: cur + 1);
        }
      } else if (cmd == 'TEMP_DOWN') {
        final cur = lastState?.setTemp ?? 24;
        if (cur > 16) {
          _updateLocalBluetoothState(setTemp: cur - 1);
        }
      }

      if (!cmd.startsWith("GET_") && !cmd.startsWith("STATUS")) {
        sendBluetoothCommand("STATUS");
      }
    } catch (e) {
      debugPrint('❌ [Bluetooth] Failed to send command: $e');
    }
  }

  // ── State ──────────────────────────────────────────────────────────────
  final Map<String, SirisDeviceState> _deviceStates = {};
  final Map<String, DateTime> _deviceLastReceivedTime = {};

  /// Checks if an identifier is a dummy/placeholder string rather than a unique hardware ID.
  static bool isPlaceholderId(String? id) {
    if (id == null) return true;
    final clean = id.trim().toLowerCase();
    return clean.isEmpty ||
        clean == 'numberimei' ||
        clean == 'imei' ||
        clean == 'unknown' ||
        clean == 'null' ||
        clean == 'default' ||
        clean == 'control';
  }

  void _recordLastReceivedTime(String id) {
    if (id.isEmpty || isPlaceholderId(id)) return;
    _deviceLastReceivedTime[id.toLowerCase()] = DateTime.now();
  }

  SirisDeviceState? _lastState;
  SirisDeviceState? get lastState => _lastState;
  bool get isConnected => _isConnected;

  SirisDeviceState? getLastStateFor(String id) {
    if (id.isEmpty || isPlaceholderId(id)) return null;
    final lowerId = id.toLowerCase().trim();

    SirisDeviceState? state;
    if (_deviceStates.containsKey(lowerId)) {
      state = _deviceStates[lowerId];
    } else {
      final normId =
          lowerId.replaceAll('_', '').replaceAll('-', '').replaceAll(' ', '');
      for (var entry in _deviceStates.entries) {
        final st = entry.value;
        final stDevLower = st.deviceId.toLowerCase().trim();
        final stImeiLower = st.imei.toLowerCase().trim();

        final isExactMatch = stDevLower == lowerId ||
            (!isPlaceholderId(stImeiLower) && stImeiLower == lowerId);
        final isNormMatch = (stDevLower.isNotEmpty &&
                stDevLower
                        .replaceAll('_', '')
                        .replaceAll('-', '')
                        .replaceAll(' ', '') ==
                    normId) ||
            (!isPlaceholderId(stImeiLower) &&
                stImeiLower.isNotEmpty &&
                stImeiLower
                        .replaceAll('_', '')
                        .replaceAll('-', '')
                        .replaceAll(' ', '') ==
                    normId);

        if (isExactMatch || isNormMatch) {
          state = st;
          break;
        }
      }
    }

    if (state != null) {
      final lastTime = _deviceLastReceivedTime[state.deviceId.toLowerCase()] ??
          (!isPlaceholderId(state.imei)
              ? _deviceLastReceivedTime[state.imei.toLowerCase()]
              : null);
      if (lastTime == null ||
          DateTime.now().difference(lastTime) > const Duration(seconds: 30)) {
        return state.copyWith(status: 'INACTIVE');
      }
      return state;
    }
    return null;
  }

  // ── Streams ────────────────────────────────────────────────────────────
  final StreamController<SirisDeviceState> _stateController =
      StreamController<SirisDeviceState>.broadcast();
  Stream<SirisDeviceState> get stateStream => _stateController.stream;

  final StreamController<SirisResponse> _responseController =
      StreamController<SirisResponse>.broadcast();
  Stream<SirisResponse> get responseStream => _responseController.stream;

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  /// Connect to the MQTT broker and subscribe to data.
  /// [deviceId] — the SIRIS device identifier.
  /// [companyId] — optional company ID to fetch MQTT credentials for.
  /// [imei] — the physical IMEI or unique identifier of the device for status matching.
  Future<bool> connect(
      {String? deviceId, String? companyId, String? imei}) async {
    if (_client != null &&
        _client!.connectionStatus?.state == MqttConnectionState.connected) {
      debugPrint('🟢 [MQTT] Already connected. Reusing active connection.');
      final cId = (companyId != null && companyId.isNotEmpty)
          ? companyId
          : _companyId;
      if (cId.isNotEmpty) {
        _companyId = cId;
      }
      if (deviceId != null &&
          deviceId.isNotEmpty &&
          (deviceId != _deviceId || imei != _imei)) {
        final oldDeviceId = _deviceId;
        _deviceId = deviceId;
        _imei = imei;
        AppConfig.mqttDeviceId = deviceId;
        _subscribeToDataTopic();

        // Restart SSE stream for the new device so telemetry targets the switched device
        if (_companyId.isNotEmpty) {
          debugPrint(
              '🔄 [MQTT] Device switched from $oldDeviceId to $deviceId — restarting SSE stream');
          _startSseStream(_companyId, _deviceId, _imei);
        }

        // Immediately request STATUS for the switched device
        Future.delayed(const Duration(milliseconds: 300), () {
          sendStatus(targetDeviceId: _deviceId, targetDeviceImei: _imei);
        });
      }
      return true;
    }
    if (_isConnecting) {
      debugPrint(
          '⏳ [MQTT] Connection attempt already in progress. Waiting for it to finish...');
      for (int i = 0; i < 40; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_client != null &&
            _client!.connectionStatus?.state == MqttConnectionState.connected) {
          return true;
        }
        if (!_isConnecting) break;
      }
      return _isConnected;
    }

    final currentAttempt = ++_connectionAttempt;
    _isConnecting = true;
    _isConnected = false;

    _deviceId = deviceId ?? AppConfig.mqttDeviceId;
    _imei = imei;

    _companyId = (companyId != null && companyId.isNotEmpty)
        ? companyId
        : await AuthService.getCompanyId() ?? '';

    // Start SSE stream in background as HTTP real-time update fallback
    _startSseStream(_companyId, _deviceId, _imei);

    // Disconnect existing client and clean up
    if (_client != null) {
      _client!.autoReconnect = false;
      try {
        _client!.disconnect();
      } catch (_) {}
      _client = null;
    }

    // Dynamically retrieve MQTT configuration exclusively via API (MqttConfigService)
    try {
      final configCompanyId = _companyId.isNotEmpty
          ? _companyId
          : await AuthService.getCompanyId();
      await MqttConfigService.fetchMqttConfig(
        companyId: configCompanyId,
        type: 'ac',
      );
    } catch (e) {
      debugPrint('⚠️ [MQTT] Error fetching dynamic MQTT config from API: $e');
    }

    final broker = AppConfig.mqttBroker;
    final port = AppConfig.mqttPort;
    final username = AppConfig.mqttUsername;
    final password = AppConfig.mqttPassword;
    final clientId = 'siris_flutter_${DateTime.now().millisecondsSinceEpoch}';

    debugPrint(
        '🔑 [MQTT] Using API-resolved credentials: user=$username on broker=$broker:$port (root: ${AppConfig.mqttRoot})');

    _client = MqttServerClient(broker, clientId);
    _client!.port = port;
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 60;
    _client!.autoReconnect = true;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onAutoReconnect = () {
      debugPrint('🔄 [MQTT] Auto-reconnecting...');
      _isConnected = false;
      _connectionController.add(false);
      notifyListeners();
    };
    _client!.onAutoReconnected = () {
      debugPrint('✅ [MQTT] Auto-reconnected');
      _isConnected = true;
      _connectionController.add(true);
      notifyListeners();
      if (_companyId.isNotEmpty) {
        debugPrint('🔄 [MQTT] Auto-reconnected -> restarting SSE stream...');
        _startSseStream(_companyId, _deviceId, _imei);
      }
      Future.delayed(const Duration(milliseconds: 500), () {
        sendStatus();
      });
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(username, password)
        .startClean();
    _client!.connectionMessage = connMessage;

    try {
      debugPrint(
          '📡 [MQTT] Connecting attempt $currentAttempt to $broker:$port for $_deviceId...');
      await _client!.connect();

      // Discard if a newer connection attempt was started in the meantime
      if (currentAttempt != _connectionAttempt) {
        debugPrint(
            '🚫 [MQTT] Discarding outdated connection attempt $currentAttempt');
        return false;
      }

      if (_client != null &&
          _client!.connectionStatus!.state == MqttConnectionState.connected) {
        _isConnected = true;
        _isConnecting = false;

        // Attach listener for incoming MQTT messages on socket
        try {
          _client!.updates!.listen(_onMessage);
          debugPrint(
              '🎧 [MQTT] Attached incoming message listener (_onMessage)');
        } catch (e) {
          debugPrint('⚠️ [MQTT] Error attaching updates listener: $e');
        }

        // Subscribe to all required data and status topics
        _subscribeToDataTopic();

        // RULE 6: Send STATUS on startup
        Future.delayed(const Duration(milliseconds: 500), () {
          sendStatus();
        });

        _connectionController.add(true);
        notifyListeners();
        debugPrint(
            '✅ [MQTT] Connected & Subscribed to telemetry and status topics.');
        return true;
      }
    } catch (e) {
      debugPrint('❌ [MQTT] Connection error for attempt $currentAttempt: $e');
    }

    // Only update state if this is still the active attempt
    if (currentAttempt == _connectionAttempt) {
      _isConnecting = false;
      _isConnected = false;
      _connectionController.add(false);
      notifyListeners();
    }
    return false;
  }

  void _subscribeToDataTopic() {
    if (_client == null ||
        _client!.connectionStatus?.state != MqttConnectionState.connected) {
      debugPrint(
          '⚠️ [MQTT] Skipping subscribe: socket client is not connected.');
      return;
    }
    try {
      final rootTopic = AppConfig.mqttTopic;
      final Set<String> topicsToSubscribe = {};

      // 1. SPECIFIC UPLINK TOPICS ONLY (Never subscribe to downlink control/wifi/ota topics)
      if (rootTopic.isNotEmpty) {
        topicsToSubscribe.add('$rootTopic/data');
        topicsToSubscribe.add('$rootTopic/status');
        topicsToSubscribe.add('$rootTopic/online');
        topicsToSubscribe.add('$rootTopic/weather');
      }

      // 2. Specific target device / system ID subscriptions
      if (_deviceId.isNotEmpty && !isPlaceholderId(_deviceId)) {
        if (rootTopic.isNotEmpty) {
          topicsToSubscribe.add('$rootTopic/$_deviceId/data');
          topicsToSubscribe.add('$rootTopic/$_deviceId/status');
          topicsToSubscribe.add('$rootTopic/$_deviceId/ir_learn');
          topicsToSubscribe.add('$rootTopic/$_deviceId/schedule');
          topicsToSubscribe.add('$rootTopic/$_deviceId/online');
        }
        topicsToSubscribe.add('$_deviceId/data');
        topicsToSubscribe.add('$_deviceId/status');
        topicsToSubscribe.add('$_deviceId/ir_learn');
      }

      // 3. IMEI-specific subscriptions if distinct from deviceId
      if (_imei != null && _imei!.isNotEmpty && !isPlaceholderId(_imei!) && _imei != _deviceId) {
        if (rootTopic.isNotEmpty) {
          topicsToSubscribe.add('$rootTopic/$_imei/data');
          topicsToSubscribe.add('$rootTopic/$_imei/status');
          topicsToSubscribe.add('$rootTopic/$_imei/ir_learn');
          topicsToSubscribe.add('$rootTopic/$_imei/schedule');
          topicsToSubscribe.add('$rootTopic/$_imei/online');
        }
        topicsToSubscribe.add('$_imei/data');
        topicsToSubscribe.add('$_imei/status');
        topicsToSubscribe.add('$_imei/ir_learn');
      }

      for (final topic in topicsToSubscribe) {
        _client!.subscribe(topic, MqttQos.atLeastOnce);
        debugPrint('📨 [MQTT] Subscribed specifically to: $topic');
      }
      debugPrint(
          '📨 [MQTT] Subscribed dynamically to ${topicsToSubscribe.length} topics');
    } catch (e) {
      debugPrint('⚠️ [MQTT] Subscription error: $e');
    }
  }

  /// Dynamically subscribe to a specific device's topics (status, ir_learn, schedule).
  void subscribeToDevice(String deviceId, {String? topicRoot, String? imei}) {
    if (_client == null ||
        _client!.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    if (deviceId.isEmpty) return;

    final root = (topicRoot != null && topicRoot.isNotEmpty)
        ? topicRoot
        : AppConfig.mqttTopic;

    final topics = <String>{
      '$root/$deviceId/status',
      '$root/$deviceId/ir_learn',
      '$root/$deviceId/schedule',
      '$deviceId/status',
      '$deviceId/ir_learn',
    };

    if (imei != null && imei.isNotEmpty && imei != deviceId) {
      topics.add('$root/$imei/status');
      topics.add('$root/$imei/ir_learn');
      topics.add('$imei/status');
      topics.add('$imei/ir_learn');
    }

    for (final topic in topics) {
      try {
        _client!.subscribe(topic, MqttQos.atLeastOnce);
        debugPrint('📨 [MQTT] Subscribed to device topic: $topic');
      } catch (e) {
        debugPrint('⚠️ [MQTT] Error subscribing to $topic: $e');
      }
    }
  }

  void _onConnected() {
    debugPrint('🟢 [MQTT] Connected callback');
    _isConnected = true;
    _connectionController.add(true);
    notifyListeners();
  }

  void _onDisconnected() {
    debugPrint('🔌 [MQTT] Disconnected');
    _isConnected = false;
    _connectionController.add(false);
    notifyListeners();
  }

  String? _extractDeviceIdFromTopic(String topic) {
    if (topic.isEmpty) return null;
    final cleanTopic = topic.trim();
    final segments = cleanTopic.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    final knownKeywords = {
      'data',
      'status',
      'online',
      'schedule',
      'control',
      'wifi',
      'ota',
      'set_temp',
      'ir_learn',
      'ir',
    };

    final root = AppConfig.mqttRoot.toLowerCase();

    for (int i = segments.length - 1; i >= 0; i--) {
      final seg = segments[i];
      final lower = seg.toLowerCase();
      if (!knownKeywords.contains(lower) && (root.isEmpty || lower != root)) {
        return seg;
      }
    }
    return null;
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage?>>? messages) {
    if (messages == null || messages.isEmpty) return;

    for (final msg in messages) {
      final recMess = msg.payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      final topic = msg.topic;

      debugPrint(
          '📩 [MQTT] Topic: $topic | Payload: ${payload.length > 200 ? "${payload.substring(0, 200)}..." : payload}');

      // Ignore echoed downlink messages on command topics (e.g. app commands reflected by broker)
      final topicLower = topic.toLowerCase();
      if (topicLower.endsWith('/control') ||
          topicLower.contains('/control/') ||
          topicLower.endsWith('/set_temp') ||
          topicLower.endsWith('/schedule') ||
          topicLower.contains('/schedule/') ||
          topicLower.endsWith('/wifi') ||
          topicLower.contains('/wifi/') ||
          topicLower.endsWith('/ota') ||
          topicLower.contains('/ota/')) {
        debugPrint(
            '🛡️ [MQTT] Ignoring echoed downlink command on topic: $topic');
        continue;
      }

      final topicDeviceId = _extractDeviceIdFromTopic(topic);

      // Try parsing as JSON (device snapshot published every 5s)
      if (payload.trim().startsWith('{')) {
        _handleJsonPayload(payload,
            topic: topic, topicDeviceId: topicDeviceId);
      } else {
        _handleStringResponse(payload.trim(),
            topic: topic, explicitDeviceId: topicDeviceId);
      }
    }
  }

  String? _extractEmbeddedIrResponse(dynamic obj) {
    if (obj == null) return null;
    if (obj is String) {
      if (obj.toUpperCase().contains('IR_LEARN_')) {
        return obj;
      }
      return null;
    }
    if (obj is Map) {
      for (final value in obj.values) {
        final res = _extractEmbeddedIrResponse(value);
        if (res != null) return res;
      }
    } else if (obj is List) {
      for (final item in obj) {
        final res = _extractEmbeddedIrResponse(item);
        if (res != null) return res;
      }
    }
    return null;
  }

  void _handleJsonPayload(String payload,
      {String? topic, String? topicDeviceId}) {
    try {
      // Fix malformed JSON
      String safePayload = payload;
      if (safePayload.contains('"set_temp":,')) {
        safePayload =
            safePayload.replaceAll('"set_temp":,', '"set_temp":null,');
      }

      final json = jsonDecode(safePayload);

      final String? jsonDeviceId = (json['deviceId'] ??
              json['device_id'] ??
              json['imei'] ??
              json['targetId'] ??
              topicDeviceId)
          ?.toString();

      // Check if JSON contains an embedded IR Learn string response (e.g. from SSE/API bridge)
      final embeddedIr = _extractEmbeddedIrResponse(json);
      if (embeddedIr != null && embeddedIr.isNotEmpty) {
        debugPrint('📩 [MQTT/SSE] Extracted embedded IR response: $embeddedIr');
        _handleStringResponse(embeddedIr,
            topic: topic, explicitDeviceId: jsonDeviceId);
      }

      // Check if this is a stream control/connection handshake message (no telemetry data payload)
      if (json['data'] == null &&
          (json['message'] != null || json['cacheStatus'] != null)) {
        debugPrint(
            'ℹ️ [SSE] Stream control message: ${json['message']} (cacheStatus: ${json['cacheStatus']})');
        return;
      }

      // Verify that this is an actual device telemetry / status JSON snapshot.
      // Command payloads (e.g. {"days1":"..."}) should never be parsed as device states.
      final bool hasTelemetryFields = json['data'] != null ||
          json['device_id'] != null ||
          json['deviceId'] != null ||
          json['ac'] != null ||
          json['set_temp'] != null ||
          json['temp'] != null;

      if (!hasTelemetryFields) {
        debugPrint('🛡️ [MQTT] Ignoring non-telemetry JSON payload: $payload');
        return;
      }

      Map<String, dynamic> candidate = json;
      if (json['data'] is Map<String, dynamic>) {
        candidate = json['data'] as Map<String, dynamic>;
      }
      final devId = (candidate['device_id'] ??
              candidate['deviceId'] ??
              json['device_id'] ??
              json['deviceId'] ??
              '')
          .toString()
          .trim();
      final imei =
          (candidate['imei'] ?? json['imei'] ?? '').toString().trim();

      final SirisDeviceState? prev = (devId.isNotEmpty
              ? _deviceStates[devId.toLowerCase()]
              : null) ??
          (imei.isNotEmpty ? _deviceStates[imei.toLowerCase()] : null);

      final state = SirisDeviceState.fromJson(json, prev);

      // Cache state for all devices to support instantaneous UI updates on switch
      if (state.deviceId.isNotEmpty && !isPlaceholderId(state.deviceId)) {
        _deviceStates[state.deviceId.toLowerCase()] = state;
        if (state.isActive) {
          _recordLastReceivedTime(state.deviceId);
        }
      }
      if (state.imei.isNotEmpty && !isPlaceholderId(state.imei)) {
        _deviceStates[state.imei.toLowerCase()] = state;
        if (state.isActive) {
          _recordLastReceivedTime(state.imei);
        }
      }

      // Only accept messages from our target device.
      // Checks whether incoming state.deviceId or state.imei matches the active target _deviceId or _imei.
      bool isMatch = _deviceId.isEmpty;
      if (!isMatch) {
        final stateDevLower = state.deviceId.toLowerCase().trim();
        final stateImeiLower = state.imei.toLowerCase().trim();
        final targetDevLower = _deviceId.toLowerCase().trim();
        final targetImeiLower = (_imei ?? '').toLowerCase().trim();

        final bool isPlaceholderImei = stateImeiLower == 'numberimei' ||
            stateImeiLower == 'imei' ||
            stateImeiLower == 'unknown';

        final bool devMatchesTarget = stateDevLower.isNotEmpty &&
            (stateDevLower == targetDevLower ||
                (targetImeiLower.isNotEmpty && stateDevLower == targetImeiLower) ||
                stateDevLower.replaceAll('_', '').replaceAll('-', '') ==
                    targetDevLower.replaceAll('_', '').replaceAll('-', ''));

        final bool imeiMatchesTarget = !isPlaceholderImei &&
            stateImeiLower.isNotEmpty &&
            (stateImeiLower == targetDevLower ||
                (targetImeiLower.isNotEmpty && stateImeiLower == targetImeiLower) ||
                stateImeiLower.replaceAll('_', '').replaceAll('-', '') ==
                    targetDevLower.replaceAll('_', '').replaceAll('-', ''));

        isMatch = devMatchesTarget || imeiMatchesTarget;
      }

      if (isMatch) {
        if (_deviceId.isNotEmpty) {
          _deviceStates[_deviceId.toLowerCase()] = state;
          if (state.isActive) {
            _recordLastReceivedTime(_deviceId);
          }
        }
        // NOTE: Do NOT overwrite _deviceId from incoming telemetry.
        // The _deviceId is set explicitly by the user's device selection in the UI.
        // Overwriting it here caused cross-device command issues where commands
        // intended for the selected device were sent to a different device.
        if (state.deviceId.isNotEmpty && _deviceId != state.deviceId) {
          debugPrint(
              'ℹ️ [MQTT] Received data from ${state.deviceId} (current target: $_deviceId) — keeping target unchanged');
        }

        _lastState = state;
        _stateController.add(state);
        _responseController.add(SirisResponse(
          type: SirisResponseType.jsonSnapshot,
          rawPayload: payload,
          deviceId: state.deviceId.isNotEmpty ? state.deviceId : state.imei,
        ));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ [MQTT] JSON parse error: $e');
    }
  }

  void _resetSseWatchdog(String companyId, String deviceId, String? imei) {
    _sseWatchdogTimer?.cancel();
    _sseWatchdogTimer = Timer(const Duration(seconds: 25), () {
      debugPrint(
          '⚠️ [SSE] No data received for 25 seconds. Reconnecting SSE stream...');
      _startSseStream(companyId, deviceId, imei);
    });
  }

  Future<void> _startSseStream(
      String companyId, String deviceId, String? imei) async {
    _sseWatchdogTimer?.cancel();
    await _sseSub?.cancel();
    _isSseConnected = false;
    notifyListeners();
    if (companyId.isEmpty ||
        (deviceId.isEmpty && (imei == null || imei.isEmpty))) {
      return;
    }
    _resetSseWatchdog(companyId, deviceId, imei);

    try {
      final client = HttpClient();
      final queryParams = <String>[];
      if (companyId.isNotEmpty) {
        queryParams.add('companyid=$companyId');
      }
      if (deviceId.isNotEmpty) {
        queryParams.add('deviceId=$deviceId');
      }
      if (imei != null && imei.isNotEmpty) {
        queryParams.add('imei=$imei');
      }
      final uri = Uri.parse(
          '${AppConfig.provisionBaseUrl}/mqtt/stream?${queryParams.join('&')}');

      debugPrint('🌐 [SSE] Connecting to: $uri');
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'text/event-stream');
      request.headers.set('Cache-Control', 'no-cache');

      final token = await AuthService.getCookieHeader();
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
        request.headers.set('Cookie', 'auth_token=$token');
      }

      final response = await request.close();
      if (response.statusCode == 200) {
        debugPrint('🟢 [SSE] Connected successfully');
        _isSseConnected = true;
        notifyListeners();

        _sseSub = response
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          _resetSseWatchdog(companyId, deviceId, imei);
          if (line.startsWith('data:')) {
            final dataContent = line.substring(5).trim();
            if (dataContent.isNotEmpty) {
              debugPrint('📩 [SSE] Received data: $dataContent');
              _sseLastDataTime = DateTime.now();
              _sseLastPayload = dataContent;
              notifyListeners();
              if (dataContent.startsWith('{')) {
                _handleJsonPayload(dataContent, topicDeviceId: deviceId);
              } else {
                _handleStringResponse(dataContent, explicitDeviceId: deviceId);
              }
            }
          }
        }, onError: (e) {
          debugPrint('❌ [SSE] Error in stream: $e');
          _isSseConnected = false;
          notifyListeners();
          Future.delayed(const Duration(seconds: 5), () {
            if (_deviceId == deviceId) {
              _startSseStream(companyId, deviceId, imei);
            }
          });
        }, onDone: () {
          debugPrint('⚠️ [SSE] Stream closed. Reconnecting in 5 seconds...');
          _isSseConnected = false;
          notifyListeners();
          Future.delayed(const Duration(seconds: 5), () {
            if (_deviceId == deviceId) {
              _startSseStream(companyId, deviceId, imei);
            }
          });
        });
      } else {
        debugPrint(
            '❌ [SSE] Connection failed with status: ${response.statusCode}. Retrying in 5 seconds...');
        _isSseConnected = false;
        notifyListeners();
        Future.delayed(const Duration(seconds: 5), () {
          if (_deviceId == deviceId) {
            _startSseStream(companyId, deviceId, imei);
          }
        });
      }
    } catch (e) {
      debugPrint(
          '❌ [SSE] Exception starting stream: $e. Retrying in 5 seconds...');
      _isSseConnected = false;
      notifyListeners();
      Future.delayed(const Duration(seconds: 5), () {
        if (_deviceId == deviceId) {
          _startSseStream(companyId, deviceId, imei);
        }
      });
    }
  }

  void _updateCachedDeviceState(String deviceId,
      {String? ac, int? setTemp, int? currentTemp, bool? automate}) {
    if (deviceId.isEmpty) return;

    final String lookupId = deviceId.toLowerCase();
    final existing = _deviceStates[lookupId] ??
        (_deviceId.toLowerCase() == lookupId ? _lastState : null) ??
        SirisDeviceState(
          deviceId: deviceId,
          imei: '',
          ac: 'OFF',
          setTemp: 24,
          currentTemp: 0,
          humidity: 0,
          irOnLearned: true,
          irOffLearned: true,
          status: 'ACTIVE',
          wifiSsid: '',
          wifiIp: '',
          wifiNetwork: '',
          wifiRssi: 0,
          time: '',
          schOn1: 'DISABLED',
          schOff1: 'DISABLED',
          schOn2: 'DISABLED',
          schOff2: 'DISABLED',
          schOn3: 'DISABLED',
          schOff3: 'DISABLED',
          schOn4: 'DISABLED',
          schOff4: 'DISABLED',
          schOn5: 'DISABLED',
          schOff5: 'DISABLED',
          lunchOn: 'DISABLED',
          lunchOff: 'DISABLED',
          primarySsid: '',
          secondarySsid: '',
          automate: false,
        );

    final updated = existing.copyWith(
      deviceId: existing.deviceId.isNotEmpty ? existing.deviceId : deviceId,
      ac: ac ?? existing.ac,
      setTemp: setTemp ?? existing.setTemp,
      currentTemp: currentTemp ?? existing.currentTemp,
      automate: automate ?? existing.automate,
      status: 'ACTIVE',
      time: DateTime.now().toString(),
    );

    _deviceStates[lookupId] = updated;
    _recordLastReceivedTime(lookupId);
    if (updated.deviceId.isNotEmpty && !isPlaceholderId(updated.deviceId)) {
      _deviceStates[updated.deviceId.toLowerCase()] = updated;
      _recordLastReceivedTime(updated.deviceId);
    }
    if (updated.imei.isNotEmpty && !isPlaceholderId(updated.imei)) {
      _deviceStates[updated.imei.toLowerCase()] = updated;
      _recordLastReceivedTime(updated.imei);
    }

    final bool isActiveTarget = _deviceId.isEmpty ||
        lookupId == _deviceId.toLowerCase() ||
        (_imei != null &&
            !isPlaceholderId(_imei) &&
            lookupId == _imei!.toLowerCase()) ||
        (updated.deviceId.toLowerCase() == _deviceId.toLowerCase()) ||
        (_imei != null &&
            !isPlaceholderId(_imei) &&
            updated.imei.toLowerCase() == _imei!.toLowerCase());

    if (isActiveTarget) {
      _lastState = updated;
      _stateController.add(updated);
      notifyListeners();
    }
    debugPrint(
        '📝 [MQTT] Updated cached state for $deviceId: ac=${updated.ac}, setTemp=${updated.setTemp} (isActiveTarget=$isActiveTarget)');
  }

  void _handleStringResponse(String payload,
      {String? topic, String? explicitDeviceId}) {
    final upper = payload.toUpperCase();

    String? responseDeviceId = explicitDeviceId;
    final parts = payload.split(':');
    if (parts.isNotEmpty && parts[0].isNotEmpty) {
      final candidate = parts[0].trim();
      final candUpper = candidate.toUpperCase();
      final isNumeric = int.tryParse(candidate) != null;
      if (!candidate.contains(' ') &&
          !isNumeric &&
          candUpper != 'TEMP_SET' &&
          candUpper != 'TEMP_PARTIAL' &&
          candUpper != 'AC_ON_DONE' &&
          candUpper != 'AC_OFF_DONE' &&
          candUpper != 'SCH_SET' &&
          candUpper != 'SCH_CLEARED' &&
          candUpper != 'CMD_REJECTED' &&
          !candUpper.startsWith('IR_LEARN') &&
          !candUpper.startsWith('LEARN') &&
          !candUpper.startsWith('SEND') &&
          !candUpper.startsWith('WIFI') &&
          !candUpper.startsWith('CLEAR') &&
          !candUpper.startsWith('SET_')) {
        responseDeviceId = candidate;
      }
    }

    if (responseDeviceId == null && topic != null) {
      responseDeviceId = _extractDeviceIdFromTopic(topic);
    }
    responseDeviceId ??= _deviceId.isNotEmpty ? _deviceId : null;

    SirisResponse response;

    if (upper.contains('AC_ON_DONE')) {
      if (responseDeviceId != null) {
        _updateCachedDeviceState(responseDeviceId, ac: 'ON');
      }
      response = SirisResponse(
        type: SirisResponseType.acOnDone,
        rawPayload: payload,
        deviceId: responseDeviceId,
      );
    } else if (upper.contains('AC_OFF_DONE')) {
      if (responseDeviceId != null) {
        _updateCachedDeviceState(responseDeviceId, ac: 'OFF');
      }
      response = SirisResponse(
        type: SirisResponseType.acOffDone,
        rawPayload: payload,
        deviceId: responseDeviceId,
      );
    } else if (upper.contains('AUTO_OFF_DONE') ||
        upper.contains('AUTOMATE_OFF_DONE') ||
        upper.contains('AUTO_OFF') ||
        upper.contains('AUTOMATE_OFF') ||
        upper.contains('AUTOMATION_OFF') ||
        upper.contains('AUTO_DISABLE') ||
        upper.contains('AUTOMATE_DISABLE') ||
        upper.contains('AUTO:OFF') ||
        upper.contains('AUTOMATE:OFF') ||
        (upper.contains('AUTO') && upper.contains('OFF')) ||
        (upper.contains('AUTOMATE') && upper.contains('OFF'))) {
      if (responseDeviceId != null) {
        _updateCachedDeviceState(responseDeviceId, automate: false);
      }
      response = SirisResponse(
        type: SirisResponseType.automateSet,
        rawPayload: payload,
        detail: 'OFF',
      );
    } else if (upper.contains('AUTO_ON_DONE') ||
        upper.contains('AUTOMATE_ON_DONE') ||
        upper.contains('AUTO_ON') ||
        upper.contains('AUTOMATE_ON') ||
        upper.contains('AUTOMATION_ON') ||
        upper.contains('AUTO_ENABLE') ||
        upper.contains('AUTOMATE_ENABLE') ||
        upper.contains('AUTO_CFG') ||
        upper.contains('AUTO:') ||
        upper.contains('AUTOMATE:') ||
        upper == 'AUTO' ||
        upper == 'AUTOMATE') {
      if (responseDeviceId != null) {
        _updateCachedDeviceState(responseDeviceId, automate: true);
      }
      response = SirisResponse(
        type: SirisResponseType.automateSet,
        rawPayload: payload,
        detail: 'ON',
      );
    } else if (upper.contains('AUTO_ERR')) {
      response = SirisResponse(
        type: SirisResponseType.automateError,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('TEMP_SET')) {
      final detail =
          payload.split(':').length > 2 ? payload.split(':').last.trim() : null;
      if (responseDeviceId != null && detail != null) {
        final parsedTemp = int.tryParse(detail);
        if (parsedTemp != null) {
          _updateCachedDeviceState(responseDeviceId, setTemp: parsedTemp);
        }
      }
      response = SirisResponse(
        type: SirisResponseType.tempSet,
        rawPayload: payload,
        detail: detail,
      );
    } else if (upper.contains('TEMP_PARTIAL')) {
      final detail =
          payload.split(':').length > 2 ? payload.split(':').last.trim() : null;
      if (responseDeviceId != null && detail != null) {
        final parsedTemp = int.tryParse(detail);
        if (parsedTemp != null) {
          _updateCachedDeviceState(responseDeviceId, setTemp: parsedTemp);
        }
      }
      response = SirisResponse(
        type: SirisResponseType.tempSet,
        rawPayload: payload,
        detail: detail,
      );
    } else if (upper.contains('TEMP_ERR')) {
      response = SirisResponse(
        type: SirisResponseType.tempError,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('SCHEDULE_UPDATED_WITH_ERRORS')) {
      // SIRIS 2.0: JSON schedule was applied but some days fields had bad tokens
      final detail = payload
          .replaceFirst(
              RegExp(r'.*SCHEDULE_UPDATED_WITH_ERRORS:?', caseSensitive: false),
              '')
          .trim();
      response = SirisResponse(
        type: SirisResponseType.scheduleUpdatedWithErrors,
        rawPayload: payload,
        detail: detail.isNotEmpty ? detail : payload,
      );
    } else if (upper.contains('SCHEDULE_UPDATED')) {
      // SIRIS 2.0: JSON schedule was fully applied successfully
      response = SirisResponse(
        type: SirisResponseType.scheduleUpdated,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('SCHEDULE_ERR')) {
      // SIRIS 2.0: JSON schedule payload was not valid JSON
      response = SirisResponse(
        type: SirisResponseType.scheduleError,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('SCH_SET')) {
      response = SirisResponse(
        type: SirisResponseType.scheduleSet,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('SCH_CLEARED')) {
      response = SirisResponse(
        type: SirisResponseType.scheduleCleared,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('SCH_ERR')) {
      response = SirisResponse(
        type: SirisResponseType.scheduleError,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('CMD_REJECTED')) {
      response = SirisResponse(
        type: SirisResponseType.cmdRejected,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('CMD_ERR')) {
      response = SirisResponse(
        type: SirisResponseType.cmdError,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('WIFI_PRIMARY_SET')) {
      final detail = payload.split(':').last.trim();
      response = SirisResponse(
        type: SirisResponseType.wifiPrimarySet,
        rawPayload: payload,
        detail: detail,
      );
    } else if (upper.contains('WIFI_SECONDARY_SET')) {
      final detail = payload.split(':').last.trim();
      response = SirisResponse(
        type: SirisResponseType.wifiSecondarySet,
        rawPayload: payload,
        detail: detail,
      );
    } else if (upper.contains('WIFI_RESET_BT_OPEN')) {
      response = SirisResponse(
        type: SirisResponseType.wifiResetBtOpen,
        rawPayload: payload,
      );
    } else if (upper.contains('WIFI_INFO')) {
      final parts = payload.split(':');
      final detail = parts.length > 2 ? parts.sublist(2).join(':') : null;
      response = SirisResponse(
        type: SirisResponseType.wifiInfo,
        rawPayload: payload,
        detail: detail,
      );

      try {
        String? responseDeviceId;
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          final candidate = parts[0].trim();
          if (!candidate.contains(' ') &&
              candidate.toUpperCase() != 'WIFI_INFO') {
            responseDeviceId = candidate;
          }
        }

        String primarySsid = '';
        String secondarySsid = '';
        String active = 'PRIMARY';
        String wifiMac = '';
        int rssi = 0;

        for (final part in parts) {
          final kv = part.split('=');
          if (kv.length == 2) {
            final key = kv[0].trim().toLowerCase();
            final value = kv[1].trim();
            if (key == 'primary') {
              primarySsid = value;
            } else if (key == 'secondary') {
              secondarySsid = value;
            } else if (key == 'active') {
              active = value.toUpperCase();
            } else if (key == 'rssi') {
              rssi = int.tryParse(value) ?? 0;
            } else if (key == 'mac' ||
                key == 'wifi_mac' ||
                key == 'mac_id' ||
                key == 'bssid') {
              wifiMac = value;
            }
          }
        }

        final connectedSsid =
            (active == 'SECONDARY') ? secondarySsid : primarySsid;

        final lookupId = responseDeviceId ?? _deviceId;
        final baseState = _deviceStates[lookupId.toLowerCase()] ??
            _lastState ??
            SirisDeviceState(
              deviceId: lookupId,
              imei: '',
              ac: 'OFF',
              setTemp: 24,
              currentTemp: 0,
              humidity: 0,
              irOnLearned: true,
              irOffLearned: true,
              status: 'ACTIVE',
              wifiSsid: '',
              wifiIp: '',
              wifiNetwork: '',
              wifiRssi: 0,
              time: '',
              schOn1: 'DISABLED',
              schOff1: 'DISABLED',
              schOn2: 'DISABLED',
              schOff2: 'DISABLED',
              schOn3: 'DISABLED',
              schOff3: 'DISABLED',
              schOn4: 'DISABLED',
              schOff4: 'DISABLED',
              schOn5: 'DISABLED',
              schOff5: 'DISABLED',
              lunchOn: 'DISABLED',
              lunchOff: 'DISABLED',
              primarySsid: '',
              secondarySsid: '',
              automate: false,
            );

        final newState = baseState.copyWith(
          deviceId:
              baseState.deviceId.isNotEmpty ? baseState.deviceId : lookupId,
          status: 'ACTIVE',
          wifiSsid: connectedSsid,
          wifiNetwork: active,
          wifiRssi: rssi,
          primarySsid: primarySsid,
          secondarySsid: secondarySsid,
          wifiMac: wifiMac.isNotEmpty ? wifiMac : baseState.wifiMac,
        );

        if (lookupId.isNotEmpty) {
          _deviceStates[lookupId.toLowerCase()] = newState;
          _recordLastReceivedTime(lookupId);
          if (newState.deviceId.isNotEmpty) {
            _deviceStates[newState.deviceId.toLowerCase()] = newState;
            _recordLastReceivedTime(newState.deviceId);
          }
          if (newState.imei.isNotEmpty) {
            _deviceStates[newState.imei.toLowerCase()] = newState;
            _recordLastReceivedTime(newState.imei);
          }
        }

        _lastState = newState;
        _stateController.add(newState);
        notifyListeners();
      } catch (e) {
        debugPrint('❌ Error parsing WIFI_INFO: $e');
      }
    } else if (upper.contains('IR_LEARN_WAITING')) {
      final detail = payload
          .replaceFirst(
              RegExp(r'.*IR_LEARN_WAITING:?', caseSensitive: false), '')
          .trim();
      response = SirisResponse(
        type: SirisResponseType.irLearnWaiting,
        rawPayload: payload,
        detail: detail.isNotEmpty ? detail : payload,
      );
    } else if (upper.contains('IR_LEARN_SAVED') ||
        upper.contains('IR_LEARN_CAPTURED')) {
      final detail = payload
          .replaceFirst(
              RegExp(r'.*IR_LEARN_(SAVED|CAPTURED):?', caseSensitive: false),
              '')
          .trim();
      response = SirisResponse(
        type: SirisResponseType.irLearnSaved,
        rawPayload: payload,
        detail: detail.isNotEmpty ? detail : payload,
      );
    } else if (upper.contains('IR_LEARN_CLEARED')) {
      final detail = payload
          .replaceFirst(
              RegExp(r'.*IR_LEARN_CLEARED:?', caseSensitive: false), '')
          .trim();
      response = SirisResponse(
        type: SirisResponseType.irLearnCleared,
        rawPayload: payload,
        detail: detail.isNotEmpty ? detail : payload,
      );
    } else if (upper.contains('IR_LEARN_STOPPED')) {
      response = SirisResponse(
        type: SirisResponseType.irLearnStopped,
        rawPayload: payload,
        detail: 'STOPPED',
      );
    } else if (upper.contains('IR_LEARN_STATUS')) {
      final detail = payload
          .replaceFirst(
              RegExp(r'.*IR_LEARN_STATUS:?', caseSensitive: false), '')
          .trim();
      response = SirisResponse(
        type: SirisResponseType.irLearnStatus,
        rawPayload: payload,
        detail: detail.isNotEmpty ? detail : payload,
      );
    } else if (upper.contains('IR_LEARN_CAPTURE_FAILED') ||
        upper.contains('IR_LEARN_TIMEOUT') ||
        upper.contains('IR_LEARN_ERR')) {
      final detail = payload
          .replaceFirst(
              RegExp(r'.*IR_LEARN_(CAPTURE_FAILED|TIMEOUT|ERR):?',
                  caseSensitive: false),
              '')
          .trim();
      response = SirisResponse(
        type: SirisResponseType.irLearnError,
        rawPayload: payload,
        detail: detail.isNotEmpty ? detail : payload,
      );
    } else if (upper.contains('WIFI_ROLLBACK')) {
      final detail = payload.split(':').last.trim();
      response = SirisResponse(
        type: SirisResponseType.wifiRollback,
        rawPayload: payload,
        detail: detail,
      );
    } else if (upper.contains('WIFI_ERR')) {
      final detail = payload.split(':').last.trim();
      response = SirisResponse(
        type: SirisResponseType.wifiError,
        rawPayload: payload,
        detail: detail,
      );
    } else {
      response = SirisResponse(
        type: SirisResponseType.unknown,
        rawPayload: payload,
      );
    }

    final taggedResponse = response.deviceId != null
        ? response
        : SirisResponse(
            type: response.type,
            rawPayload: response.rawPayload,
            detail: response.detail,
            deviceId: responseDeviceId,
          );

    _responseController.add(taggedResponse);
  }

  // ── Publish Methods (RULE 1: retain=false, RULE 2: plain text only) ──

  String? _lastPublishedTopic;
  String? _lastPublishedMessage;
  DateTime? _lastPublishedTime;

  /// Publish a raw message to a topic. Retain is ALWAYS false.
  /// Uses MqttQos.atLeastOnce (QoS 1) to ensure the message is acknowledged by the broker.
  Future<bool> _publish(String topic, String message) async {
    final now = DateTime.now();
    final isSteppingCmd = message == 'TEMP_UP' || message == 'TEMP_DOWN';
    if (!isSteppingCmd &&
        _lastPublishedTopic == topic &&
        _lastPublishedMessage == message &&
        _lastPublishedTime != null &&
        now.difference(_lastPublishedTime!).inMilliseconds < 300) {
      debugPrint(
          '🛡️ [MQTT] Suppressed duplicate publish within 300ms to $topic: $message');
      return true;
    }
    if (_client == null ||
        _client!.connectionStatus?.state != MqttConnectionState.connected) {
      debugPrint(
          '📡 [MQTT] Socket client not connected (${_client?.connectionStatus?.state}). Reconnecting before publish...');
      await connect(deviceId: _deviceId.isNotEmpty ? _deviceId : '', imei: _imei);
    }

    bool published = false;
    if (_client != null &&
        _client!.connectionStatus?.state == MqttConnectionState.connected) {
      try {
        final builder = MqttClientPayloadBuilder();
        builder.addString(message);
        _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!,
            retain: false);
        debugPrint(
            '📤 [MQTT] Published via socket to $topic: $message (QoS 1, retain: false)');
        published = true;
        _lastPublishedTopic = topic;
        _lastPublishedMessage = message;
        _lastPublishedTime = now;
      } catch (e) {
        debugPrint('⚠️ [MQTT] Socket publish error on $topic: $e');
      }
    } else {
      debugPrint(
          '❌ [MQTT] Publish failed: socket not connected to broker (${_client?.connectionStatus?.state}) for topic: $topic, message: $message');
    }

    return published;
  }

  /// Send a custom control command to the control topic.
  /// Commands are published to the hardware root topics (`<root>/control`, `control`)
  /// as required by SIRIS v2 firmware (SIRIS_v2.ino) as well as per-device topics
  /// for backend telemetry tracking.
  Future<void> sendControlCommand(String command,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) async {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint(
        '📡 [MQTT] Sending Control command: $command for device: $devId (imei: $targetDeviceImei, shortId: $targetDeviceShortId, name: $targetDeviceName)');
    if (isBluetoothConnected) {
      sendBluetoothCommand(command);
      return;
    }

    final bool isLearnCmd = command.startsWith('LEARN_') ||
        command.startsWith('IR_LEARN_') ||
        command.startsWith('CLEAR_');

    // SIRIS v2 Spec:
    // Control topic strictly accepts: IR_LEARN_ON, IR_LEARN_OFF, IR_LEARN_TEMP_UP:<16-29>, IR_LEARN_TEMP_DOWN:<17-30>, IR_LEARN_STOP, LEARN_STATUS, CLEAR_*
    // /ir_learn topic strictly accepts: LEARN_ON, LEARN_OFF, LEARN_UP:<16-29>, LEARN_DOWN:<17-30>, LEARN_STOP, LEARN_STATUS, CLEAR_*
    // (Note: IR_LEARN_ON on /ir_learn returns IR_LEARN_ERR:UNKNOWN_CMD!)
    String controlPayload = command;
    String learnPayload = command;

    if (isLearnCmd) {
      if (command == 'LEARN_ON' || command == 'IR_LEARN_ON') {
        controlPayload = 'IR_LEARN_ON';
        learnPayload = 'LEARN_ON';
      } else if (command == 'LEARN_OFF' || command == 'IR_LEARN_OFF') {
        controlPayload = 'IR_LEARN_OFF';
        learnPayload = 'LEARN_OFF';
      } else if (command.startsWith('LEARN_UP:') || command.startsWith('IR_LEARN_TEMP_UP:')) {
        final t = command.contains(':') ? command.split(':')[1] : '24';
        controlPayload = 'IR_LEARN_TEMP_UP:$t';
        learnPayload = 'LEARN_UP:$t';
      } else if (command.startsWith('LEARN_DOWN:') || command.startsWith('IR_LEARN_TEMP_DOWN:')) {
        final t = command.contains(':') ? command.split(':')[1] : '24';
        controlPayload = 'IR_LEARN_TEMP_DOWN:$t';
        learnPayload = 'LEARN_DOWN:$t';
      } else if (command == 'LEARN_STOP' || command == 'IR_LEARN_STOP') {
        controlPayload = 'IR_LEARN_STOP';
        learnPayload = 'LEARN_STOP';
      } else if (command == 'LEARN_STATUS') {
        controlPayload = 'LEARN_STATUS';
        learnPayload = 'LEARN_STATUS';
      }
    }

    final Set<String> specificIds = {};
    if (targetDeviceImei != null &&
        targetDeviceImei.isNotEmpty &&
        !isPlaceholderId(targetDeviceImei)) {
      // ONLY target the specific physical hardware IMEI. Do NOT append devId or root.
      specificIds.add(targetDeviceImei.trim());
    } else if (devId.isNotEmpty &&
        !isPlaceholderId(devId) &&
        devId.toLowerCase() != AppConfig.mqttRoot.toLowerCase() &&
        devId.toLowerCase() != _companyId.toLowerCase()) {
      specificIds.add(devId.trim());
    }

    final Set<String> controlTopics = {};
    final Set<String> learnTopics = {};

    if (specificIds.isNotEmpty) {
      // 1. Device-wise control: Publish strictly to targeted device topics.
      // Do NOT publish to root broadcast (<root>/control), which triggers all devices simultaneously.
      for (final id in specificIds) {
        if (id.toLowerCase() == AppConfig.mqttRoot.toLowerCase() ||
            id.toLowerCase() == _companyId.toLowerCase()) {
          continue;
        }
        if (AppConfig.mqttRoot.isNotEmpty) {
          controlTopics.add('${AppConfig.mqttRoot}/$id/control');
          if (isLearnCmd) {
            learnTopics.add('${AppConfig.mqttRoot}/$id/ir_learn');
          }
        }
        controlTopics.add('$id/control');
        if (isLearnCmd) {
          learnTopics.add('$id/ir_learn');
        }
      }
    } else {
      // 2. Broadcast fallback ONLY when no specific device is targeted
      if (AppConfig.mqttRoot.isNotEmpty) {
        controlTopics.add('${AppConfig.mqttRoot}/control');
        if (isLearnCmd) {
          learnTopics.add('${AppConfig.mqttRoot}/ir_learn');
        }
      } else {
        controlTopics.add('control');
        if (isLearnCmd) {
          learnTopics.add('ir_learn');
        }
      }
    }

    // 3. Publish exact plaintext payload
    for (final topic in controlTopics) {
      await _publish(topic, controlPayload);
    }

    if (isLearnCmd) {
      for (final topic in learnTopics) {
        await _publish(topic, learnPayload);
      }
    }
  }

  // ── AC Power Control (Spec Section 2) ─────────────────────────────────

  /// Turn AC ON.
  /// Spec Section 2: Topic `<root>/control`, Payload: ON
  void turnAcOn(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('⚡ [MQTT] Turn AC ON for device: $devId (imei: $targetDeviceImei)');
    sendControlCommand('ON',
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
    if (devId.isNotEmpty) {
      _updateCachedDeviceState(devId, ac: 'ON');
    }
    if (targetDeviceImei != null && targetDeviceImei.isNotEmpty) {
      _updateCachedDeviceState(targetDeviceImei, ac: 'ON');
    }
    if (targetDeviceShortId != null && targetDeviceShortId.isNotEmpty) {
      _updateCachedDeviceState(targetDeviceShortId, ac: 'ON');
    }
    // Follow up with STATUS after 800ms to immediately fetch fresh hardware telemetry
    Future.delayed(const Duration(milliseconds: 800), () {
      sendStatus(
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName,
      );
    });
  }

  /// Turn AC OFF.
  /// Spec Section 2: Topic `<root>/control`, Payload: OFF
  void turnAcOff(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('🔌 [MQTT] Turn AC OFF for device: $devId (imei: $targetDeviceImei)');
    sendControlCommand('OFF',
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
    if (devId.isNotEmpty) {
      _updateCachedDeviceState(devId, ac: 'OFF');
    }
    if (targetDeviceImei != null && targetDeviceImei.isNotEmpty) {
      _updateCachedDeviceState(targetDeviceImei, ac: 'OFF');
    }
    if (targetDeviceShortId != null && targetDeviceShortId.isNotEmpty) {
      _updateCachedDeviceState(targetDeviceShortId, ac: 'OFF');
    }
    // Follow up with STATUS after 800ms to immediately fetch fresh hardware telemetry
    Future.delayed(const Duration(milliseconds: 800), () {
      sendStatus(
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName,
      );
    });
  }

  /// Request device STATUS.
  /// Spec Section 2: Topic `<root>/control`, Payload: STATUS
  void sendStatus(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('📡 [MQTT] Requesting STATUS for device: $devId (imei: $targetDeviceImei)');
    sendControlCommand('STATUS',
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  // ── Automate Commands (SIRIS v2 Spec Section 2) ─────────────────────

  /// Enable smart automation with target temperature (Range: 16–30°C).
  /// Payloads: `AUTO:<temp>`, `AUTO`, and JSON {"command":"SET_AC_AUTO","auto":true,"required_temperature":24}
  void enableAutomation(
      {int? autoTemp,
      String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    final devId = targetDeviceId ?? _deviceId;
    final int target = (autoTemp != null && autoTemp >= 16 && autoTemp <= 30) ? autoTemp : 24;
    final cmd = 'AUTO:$target';
    debugPrint(
        '🤖 [MQTT] Enabling automation: $cmd (device: $devId)');
    sendControlCommand(cmd,
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
    if (devId.isNotEmpty) {
      _updateCachedDeviceState(devId, automate: true);
    }
    if (targetDeviceImei != null && targetDeviceImei.isNotEmpty) {
      _updateCachedDeviceState(targetDeviceImei, automate: true);
    }
  }

  /// Set or update dynamic Auto Mode temperature threshold (e.g. AUTO:22).
  void setAutoTemperature(int temp,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    enableAutomation(
        autoTemp: temp,
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  /// Disable smart automation.
  /// Payloads: `AUTO_OFF`
  void disableAutomation(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint(
        '🤖 [MQTT] Disabling automation: AUTO_OFF (device: $devId)');
    sendControlCommand('AUTO_OFF',
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
    if (devId.isNotEmpty) {
      _updateCachedDeviceState(devId, automate: false);
    }
    if (targetDeviceImei != null && targetDeviceImei.isNotEmpty) {
      _updateCachedDeviceState(targetDeviceImei, automate: false);
    }
  }

  // ── Temperature Control (SIRIS v2 Spec Section 2 & 3) ──────────────────

  /// Set temperature (Range: 16 to 30 C).
  /// Publishes `TEMP:<temp>` to `<root>/control` and `<temp>` (bare integer) to `<root>/control/set_temp`.
  Future<void> setTemperature(int temp,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) async {
    if (temp < 16 || temp > 30) {
      debugPrint('⚠️ Temperature out of range (16-30): $temp');
      return;
    }

    final devId = targetDeviceId ?? _deviceId;
    if (isBluetoothConnected) {
      sendBluetoothCommand('SEND:TEMP_$temp');
      return;
    }

    final Set<String> specificIds = {};
    if (targetDeviceImei != null &&
        targetDeviceImei.isNotEmpty &&
        !isPlaceholderId(targetDeviceImei)) {
      // ONLY target the specific physical hardware IMEI. Do NOT append devId or root.
      specificIds.add(targetDeviceImei.trim());
    } else if (devId.isNotEmpty &&
        !isPlaceholderId(devId) &&
        devId.toLowerCase() != AppConfig.mqttRoot.toLowerCase() &&
        devId.toLowerCase() != _companyId.toLowerCase()) {
      specificIds.add(devId.trim());
    }

    final Set<String> tempSetTopics = {};
    final Set<String> tempControlTopics = {};

    if (specificIds.isNotEmpty) {
      // 1. Device-wise temperature control: Publish strictly to targeted device topics.
      // Do NOT publish to root broadcast (<root>/control/set_temp or <root>/control).
      for (final id in specificIds) {
        if (id.toLowerCase() == AppConfig.mqttRoot.toLowerCase() ||
            id.toLowerCase() == _companyId.toLowerCase()) {
          continue;
        }
        if (AppConfig.mqttRoot.isNotEmpty) {
          tempSetTopics.add('${AppConfig.mqttRoot}/$id/control/set_temp');
          tempControlTopics.add('${AppConfig.mqttRoot}/$id/control');
        }
        tempSetTopics.add('$id/control/set_temp');
        tempControlTopics.add('$id/control');
      }
    } else {
      // 2. Broadcast fallback ONLY when no specific device is targeted
      if (AppConfig.mqttRoot.isNotEmpty) {
        tempSetTopics.add('${AppConfig.mqttRoot}/control/set_temp');
        tempControlTopics.add('${AppConfig.mqttRoot}/control');
      } else {
        tempSetTopics.add('control/set_temp');
        tempControlTopics.add('control');
      }
    }

    // Publish bare integer string to set_temp topics (e.g. "24")
    for (final topic in tempSetTopics) {
      await _publish(topic, '$temp');
    }

    // Publish TEMP:<temp> to control topics (e.g. "TEMP:24")
    for (final topic in tempControlTopics) {
      await _publish(topic, 'TEMP:$temp');
    }

    if (devId.isNotEmpty) {
      _updateCachedDeviceState(devId, setTemp: temp);
    }
    if (targetDeviceImei != null && targetDeviceImei.isNotEmpty) {
      _updateCachedDeviceState(targetDeviceImei, setTemp: temp);
    }

    // Follow up with STATUS after 800ms to immediately fetch fresh hardware telemetry
    Future.delayed(const Duration(milliseconds: 800), () {
      sendStatus(
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName,
      );
    });

    debugPrint('🌡️ [MQTT] Temperature $temp sent for $devId');
  }

  /// Send TEMPERATURE UP command (Spec Section 2: TEMP_UP).
  void tempUp(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('🌡️ [MQTT] Temperature UP (device: $devId)');
    final currentState = getLastStateFor(devId) ?? _lastState;
    final int nextTemp = (currentState != null && currentState.setTemp < 30)
        ? currentState.setTemp + 1
        : 25;
    _updateCachedDeviceState(devId, setTemp: nextTemp);
    if (targetDeviceShortId != null && targetDeviceShortId.isNotEmpty) {
      _updateCachedDeviceState(targetDeviceShortId, setTemp: nextTemp);
    }
    sendControlCommand('TEMP_UP',
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
    // Follow up with STATUS after 800ms to immediately fetch fresh hardware telemetry
    Future.delayed(const Duration(milliseconds: 800), () {
      sendStatus(
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName,
      );
    });
  }

  /// Send TEMPERATURE DOWN command (Spec Section 2: TEMP_DOWN).
  void tempDown(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('🌡️ [MQTT] Temperature DOWN (device: $devId)');
    final currentState = getLastStateFor(devId) ?? _lastState;
    final int nextTemp = (currentState != null && currentState.setTemp > 16)
        ? currentState.setTemp - 1
        : 23;
    _updateCachedDeviceState(devId, setTemp: nextTemp);
    if (targetDeviceShortId != null && targetDeviceShortId.isNotEmpty) {
      _updateCachedDeviceState(targetDeviceShortId, setTemp: nextTemp);
    }
    sendControlCommand('TEMP_DOWN',
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
    // Follow up with STATUS after 800ms to immediately fetch fresh hardware telemetry
    Future.delayed(const Duration(milliseconds: 800), () {
      sendStatus(
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName,
      );
    });
  }

  /// Reset / Clear temperature to 24°C default (Spec Section 2: TEMP_CLEAR).
  void tempClear(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('🌡️ [MQTT] Temperature CLEAR to 24°C (device: $devId)');
    _updateCachedDeviceState(devId, setTemp: 24);
    if (targetDeviceShortId != null && targetDeviceShortId.isNotEmpty) {
      _updateCachedDeviceState(targetDeviceShortId, setTemp: 24);
    }
    sendControlCommand('TEMP_CLEAR',
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
    // Follow up with STATUS after 800ms to immediately fetch fresh hardware telemetry
    Future.delayed(const Duration(milliseconds: 800), () {
      sendStatus(
        targetDeviceId: devId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName,
      );
    });
  }

  // ── IR Test Commands (SIRIS v2 Spec Section 2) ─────────────────────────

  /// Send IR test UP command (Spec Section 2: SEND:UP_<16-29>).
  void sendIrTestUp(int temp,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    if (temp < 16 || temp > 29) {
      debugPrint('⚠️ [MQTT] IR test UP out of range (16-29): $temp');
      return;
    }
    sendControlCommand('SEND:UP_$temp',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  /// Send IR test DOWN command (Spec Section 2: SEND:DOWN_<17-30>).
  void sendIrTestDown(int temp,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    if (temp < 17 || temp > 30) {
      debugPrint('⚠️ [MQTT] IR test DOWN out of range (17-30): $temp');
      return;
    }
    sendControlCommand('SEND:DOWN_$temp',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  // ── Schedule Control (RULE 11: HH:MM format, RULE 3: never send DISABLED) ─

  static const List<String> supportedScheduleDays = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN'
  ];

  String _formatScheduleDays(String? days) {
    if (days == null || days.trim().isEmpty) {
      return supportedScheduleDays.join(',');
    }
    final upper = days.toUpperCase().trim();
    if (upper == 'ALL' || upper == 'DAILY' || upper == 'EVERYDAY') {
      return supportedScheduleDays.join(',');
    }
    final tokens = upper.split(',').map((t) => t.trim()).toSet();
    final valid =
        supportedScheduleDays.where((d) => tokens.contains(d)).toList();
    if (valid.isEmpty || valid.length == 7) {
      return supportedScheduleDays.join(',');
    }
    return valid.join(',');
  }

  String _resolveScheduleDeviceId(String? targetDeviceId) {
    if (targetDeviceId != null && targetDeviceId.isNotEmpty) {
      return targetDeviceId;
    }
    if (_deviceId.isNotEmpty) return _deviceId;
    return AppConfig.mqttDeviceId;
  }

  void _publishToScheduleTopics(String devId, String command) {
    if (devId.isNotEmpty &&
        !isPlaceholderId(devId) &&
        devId.toLowerCase() != AppConfig.mqttRoot.toLowerCase()) {
      final primaryTopic = AppConfig.getMqttScheduleTopic(devId);
      _publish(primaryTopic, command);

      final directTopic = '$devId/schedule';
      if (directTopic.toLowerCase() != primaryTopic.toLowerCase()) {
        _publish(directTopic, command);
      }

      final root = AppConfig.mqttTopic;
      if (root.isNotEmpty && root.toLowerCase() != devId.toLowerCase()) {
        final rootDevTopic = '$root/$devId/schedule';
        if (rootDevTopic.toLowerCase() != primaryTopic.toLowerCase() &&
            rootDevTopic.toLowerCase() != directTopic.toLowerCase()) {
          _publish(rootDevTopic, command);
        }
        if (_companyId.isNotEmpty &&
            _companyId.toLowerCase() != root.toLowerCase() &&
            _companyId.toLowerCase() != devId.toLowerCase()) {
          _publish('$_companyId/$devId/schedule', command);
        }
      }
    } else {
      final root = AppConfig.mqttTopic;
      if (root.isNotEmpty) {
        _publish('$root/schedule', command);
      }
    }
  }

  /// Optimistically update a schedule slot in local state and emit to stream.
  /// This ensures the UI reflects the change immediately without waiting for
  /// the device's STATUS response via SSE.
  void updateScheduleOptimistic({
    int? slot,
    String? onTime,
    String? offTime,
    String? days,
    bool clear = false,
  }) {
    if (_lastState == null) return;

    final Map<String, String?> updates = {};
    if (slot != null) {
      if (clear) {
        updates['schOn$slot'] = 'DISABLED';
        updates['schOff$slot'] = 'DISABLED';
      } else {
        if (onTime != null) updates['schOn$slot'] = onTime;
        if (offTime != null) updates['schOff$slot'] = offTime;
        if (days != null) updates['schDays$slot'] = days;
      }
    }

    final updated = _lastState!.copyWith(
      schOn1: updates['schOn1'],
      schOff1: updates['schOff1'],
      schDays1: updates['schDays1'],
      schOn2: updates['schOn2'],
      schOff2: updates['schOff2'],
      schDays2: updates['schDays2'],
      schOn3: updates['schOn3'],
      schOff3: updates['schOff3'],
      schDays3: updates['schDays3'],
      schOn4: updates['schOn4'],
      schOff4: updates['schOff4'],
      schDays4: updates['schDays4'],
      schOn5: updates['schOn5'],
      schOff5: updates['schOff5'],
      schDays5: updates['schDays5'],
    );

    _lastState = updated;
    final lookupId = updated.deviceId.toLowerCase();
    if (lookupId.isNotEmpty) {
      _deviceStates[lookupId] = updated;
    }
    _stateController.add(updated);
    notifyListeners();
    debugPrint('📅 [MQTT] Optimistic schedule update emitted for slot $slot');
  }

  void updateLunchOptimistic({
    String? lunchOn,
    String? lunchOff,
    String? days,
    bool clear = false,
  }) {
    if (_lastState == null) return;

    final updated = _lastState!.copyWith(
      lunchOn: clear ? 'DISABLED' : (lunchOn ?? _lastState!.lunchOn),
      lunchOff: clear ? 'DISABLED' : (lunchOff ?? _lastState!.lunchOff),
      lunchDays: clear ? 'ALL' : (days ?? _lastState!.lunchDays),
    );

    _lastState = updated;
    final lookupId = updated.deviceId.toLowerCase();
    if (lookupId.isNotEmpty) {
      _deviceStates[lookupId] = updated;
    }
    _stateController.add(updated);
    notifyListeners();
    debugPrint('📅 [MQTT] Optimistic lunch update emitted');
  }

  /// SIRIS 2.0 — Publish a JSON schedule payload to <root>/<deviceId>/schedule.
  /// Only sends fields that have changed. Supports on1..on5, off1..off5, days1..days5,
  /// lunch_on, lunch_off, lunch_days, and set_temp.
  ///
  /// Example payload: {"on1":"08:30","off1":"18:00","days1":"MON,TUE,WED,THU,FRI"}
  ///
  /// IMPORTANT: field name typos are silently dropped by firmware with zero feedback.
  /// This method validates and normalizes field names and values before publishing.
  Future<bool> publishScheduleJson(Map<String, dynamic> schedulePayload,
      {String? targetDeviceId}) async {
    if (schedulePayload.isEmpty) {
      debugPrint('⚠️ [MQTT] Empty schedule payload — nothing to publish');
      return false;
    }

    // Validate field names client-side (firmware silently ignores typos)
    const validFields = {
      'set_temp',
      'on1',
      'off1',
      'days1',
      'on2',
      'off2',
      'days2',
      'on3',
      'off3',
      'days3',
      'on4',
      'off4',
      'days4',
      'on5',
      'off5',
      'days5',
      'lunch_on',
      'lunch_off',
      'lunch_days',
    };

    final invalidFields =
        schedulePayload.keys.where((k) => !validFields.contains(k)).toList();
    if (invalidFields.isNotEmpty) {
      debugPrint(
          '⚠️ [MQTT] WARNING: Invalid field names detected and removed: $invalidFields');
      for (final f in invalidFields) {
        schedulePayload.remove(f);
      }
    }

    // Spec Section 3.5: set_temp (int, 16–30°C)
    if (schedulePayload.containsKey('set_temp')) {
      final val = int.tryParse(schedulePayload['set_temp'].toString());
      if (val != null) {
        schedulePayload['set_temp'] = val.clamp(16, 30);
      }
    }

    // Spec Section 3.5: on1..on5, off1..off5, lunch_on, lunch_off (string HH:MM)
    const timeKeys = [
      'on1',
      'off1',
      'on2',
      'off2',
      'on3',
      'off3',
      'on4',
      'off4',
      'on5',
      'off5',
      'lunch_on',
      'lunch_off'
    ];
    for (final timeKey in timeKeys) {
      if (schedulePayload.containsKey(timeKey)) {
        final val = schedulePayload[timeKey]?.toString().trim();
        if (val != null && val != 'DISABLED' && val != '--:--') {
          final normalized = _normalizeTime(val);
          if (normalized != null) {
            schedulePayload[timeKey] = normalized;
          }
        }
      }
    }

    // Spec Section 3.5: days1..days5, lunch_days (comma-separated days or ALL)
    const dayKeys = ['days1', 'days2', 'days3', 'days4', 'days5', 'lunch_days'];
    for (final dayKey in dayKeys) {
      if (schedulePayload.containsKey(dayKey)) {
        final val = schedulePayload[dayKey]?.toString().trim().toUpperCase();
        if (val == 'ALL' || val == 'DAILY' || val == 'EVERYDAY') {
          schedulePayload[dayKey] = 'ALL';
        } else if (val != null && val != 'DISABLED') {
          schedulePayload[dayKey] = _formatScheduleDays(val);
        }
      }
    }

    if (schedulePayload.isEmpty) {
      debugPrint('⚠️ [MQTT] All fields were invalid — nothing to publish');
      return false;
    }

    final devId = _resolveScheduleDeviceId(targetDeviceId);
    final jsonStr = jsonEncode(schedulePayload);

    // Section 3.5 Spec: Primary topic for SIRIS 2.0 JSON mode is <root>/<deviceId>/schedule
    final primaryJsonTopic = AppConfig.getMqttJsonScheduleTopic(devId);
    debugPrint(
        '📅 [MQTT] Publishing SIRIS 2.0 schedule JSON to $primaryJsonTopic: $jsonStr');
    final ok = await _publish(primaryJsonTopic, jsonStr);

    final directTopic = '$devId/schedule';
    if (directTopic.toLowerCase() != primaryJsonTopic.toLowerCase()) {
      _publish(directTopic, jsonStr);
    }

    final rootTopic = AppConfig.getMqttScheduleTopic(devId);
    if (rootTopic.toLowerCase() != primaryJsonTopic.toLowerCase() &&
        rootTopic.toLowerCase() != directTopic.toLowerCase()) {
      _publish(rootTopic, jsonStr);
    }

    final root = AppConfig.mqttTopic;
    if (root.isNotEmpty) {
      if (devId.isEmpty || isPlaceholderId(devId) || devId.toLowerCase() == root.toLowerCase()) {
        final rootSchedule = '$root/schedule';
        if (rootSchedule.toLowerCase() != primaryJsonTopic.toLowerCase() &&
            rootSchedule.toLowerCase() != directTopic.toLowerCase() &&
            rootSchedule.toLowerCase() != rootTopic.toLowerCase()) {
          _publish(rootSchedule, jsonStr);
        }
      } else {
        final rootDevSchedule = '$root/$devId/schedule';
        if (rootDevSchedule.toLowerCase() != primaryJsonTopic.toLowerCase() &&
            rootDevSchedule.toLowerCase() != directTopic.toLowerCase() &&
            rootDevSchedule.toLowerCase() != rootTopic.toLowerCase()) {
          _publish(rootDevSchedule, jsonStr);
        }
        if (_companyId.isNotEmpty &&
            _companyId.toLowerCase() != root.toLowerCase() &&
            _companyId.toLowerCase() != devId.toLowerCase()) {
          _publish('$_companyId/$devId/schedule', jsonStr);
        }
      }
    }

    return ok;
  }

  /// Optimistically update all schedule and lunch slots at once (for the new Calendar page).
  void updateFullScheduleOptimistic({
    String? schOn1,
    String? schOff1,
    String? schDays1,
    String? schOn2,
    String? schOff2,
    String? schDays2,
    String? schOn3,
    String? schOff3,
    String? schDays3,
    String? schOn4,
    String? schOff4,
    String? schDays4,
    String? schOn5,
    String? schOff5,
    String? schDays5,
    String? lunchOn,
    String? lunchOff,
    String? lunchDays,
  }) {
    if (_lastState == null) return;

    final updated = _lastState!.copyWith(
      schOn1: schOn1,
      schOff1: schOff1,
      schDays1: schDays1,
      schOn2: schOn2,
      schOff2: schOff2,
      schDays2: schDays2,
      schOn3: schOn3,
      schOff3: schOff3,
      schDays3: schDays3,
      schOn4: schOn4,
      schOff4: schOff4,
      schDays4: schDays4,
      schOn5: schOn5,
      schOff5: schOff5,
      schDays5: schDays5,
      lunchOn: lunchOn,
      lunchOff: lunchOff,
      lunchDays: lunchDays,
    );

    _lastState = updated;
    final lookupId = updated.deviceId.toLowerCase();
    if (lookupId.isNotEmpty) {
      _deviceStates[lookupId] = updated;
    }
    _stateController.add(updated);
    notifyListeners();
    debugPrint('📅 [MQTT] Full optimistic schedule update emitted');
  }

  String? _normalizeTime(String time) {
    // Allow single-digit hour e.g. '8:00' -> '08:00'
    final regex = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$');
    final match = regex.firstMatch(time);
    if (match == null) {
      debugPrint('⚠️ [MQTT] Invalid time format: $time (expected HH:MM)');
      return null;
    }
    final hour = match.group(1)!.padLeft(2, '0');
    final minute = match.group(2)!.padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Set a schedule ON time. [slot] is 1–5, [time] is "HH:MM" (24hr, zero-padded).
  /// Supports:
  ///   - Daily Schedule: SCH_ON<slot>:<HH:MM> (Spec Section 6)
  ///   - One-Time Date Schedule: SCH_ON<slot>:<YYYY-MM-DD>,<HH:MM> (Spec Section 7)
  ///   - Weekly Schedule: SCH_ON<slot>:<DAYS>,<HH:MM> (Spec Section 8)
  void setScheduleOn(int slot, String time,
      {String? days, String? date, String? targetDeviceId}) {
    final normalized = _normalizeTime(time);
    if (normalized == null) return;
    String cmd;
    if (date != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      cmd = 'SCH_ON$slot:$date,$normalized';
    } else if (days != null && days.isNotEmpty && days != 'ALL') {
      final formattedDays = _formatScheduleDays(days);
      cmd = 'SCH_ON$slot:$formattedDays,$normalized';
    } else {
      cmd = 'SCH_ON$slot:$normalized';
    }
    final devId = _resolveScheduleDeviceId(targetDeviceId);
    debugPrint(
        '📅 [MQTT] Setting Schedule ON slot $slot -> $cmd (device: $devId)');
    if (isBluetoothConnected) {
      sendBluetoothCommand(cmd);
    } else {
      _publishToScheduleTopics(devId, cmd);
    }
  }

  /// Set a schedule OFF time. [slot] is 1–5, [time] is "HH:MM".
  /// Supports:
  ///   - Daily Schedule: SCH_OFF<slot>:<HH:MM> (Spec Section 6)
  ///   - One-Time Date Schedule: SCH_OFF<slot>:<YYYY-MM-DD>,<HH:MM> (Spec Section 7)
  ///   - Weekly Schedule: SCH_OFF<slot>:<DAYS>,<HH:MM> (Spec Section 8)
  void setScheduleOff(int slot, String time,
      {String? days, String? date, String? targetDeviceId}) {
    final normalized = _normalizeTime(time);
    if (normalized == null) return;
    String cmd;
    if (date != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      cmd = 'SCH_OFF$slot:$date,$normalized';
    } else if (days != null && days.isNotEmpty && days != 'ALL') {
      final formattedDays = _formatScheduleDays(days);
      cmd = 'SCH_OFF$slot:$formattedDays,$normalized';
    } else {
      cmd = 'SCH_OFF$slot:$normalized';
    }
    final devId = _resolveScheduleDeviceId(targetDeviceId);
    debugPrint(
        '📅 [MQTT] Setting Schedule OFF slot $slot -> $cmd (device: $devId)');
    if (isBluetoothConnected) {
      sendBluetoothCommand(cmd);
    } else {
      _publishToScheduleTopics(devId, cmd);
    }
  }

  /// Set lunch ON time.
  /// Spec Section 9: LUNCH_ON:13:00 or LUNCH_ON:MON,WED,FRI,13:00
  void setLunchOn(String time, {String? days, String? targetDeviceId}) {
    final normalized = _normalizeTime(time);
    if (normalized == null) return;
    String cmd;
    if (days != null && days.isNotEmpty && days != 'ALL') {
      final formattedDays = _formatScheduleDays(days);
      cmd = 'LUNCH_ON:$formattedDays,$normalized';
    } else {
      cmd = 'LUNCH_ON:$normalized';
    }
    final devId = _resolveScheduleDeviceId(targetDeviceId);
    debugPrint('📅 [MQTT] Setting Lunch ON -> $cmd (device: $devId)');
    if (isBluetoothConnected) {
      sendBluetoothCommand(cmd);
    } else {
      _publishToScheduleTopics(devId, cmd);
    }
  }

  /// Set lunch OFF time.
  /// Spec Section 9: LUNCH_OFF:14:00 or LUNCH_OFF:MON,WED,FRI,14:00
  void setLunchOff(String time, {String? days, String? targetDeviceId}) {
    final normalized = _normalizeTime(time);
    if (normalized == null) return;
    String cmd;
    if (days != null && days.isNotEmpty && days != 'ALL') {
      final formattedDays = _formatScheduleDays(days);
      cmd = 'LUNCH_OFF:$formattedDays,$normalized';
    } else {
      cmd = 'LUNCH_OFF:$normalized';
    }
    final devId = _resolveScheduleDeviceId(targetDeviceId);
    debugPrint('📅 [MQTT] Setting Lunch OFF -> $cmd (device: $devId)');
    if (isBluetoothConnected) {
      sendBluetoothCommand(cmd);
    } else {
      _publishToScheduleTopics(devId, cmd);
    }
  }

  // ── Schedule Clear (Spec Section 10) ──────────────────────────────────

  /// Clear ALL schedule slots at once.
  /// Spec Section 10: Payload SCH_CLEAR
  void clearAllSchedules({String? targetDeviceId}) {
    final devId = _resolveScheduleDeviceId(targetDeviceId);
    debugPrint('📅 [MQTT] Clearing ALL schedules (device: $devId)');
    if (isBluetoothConnected) {
      sendBluetoothCommand('SCH_CLEAR');
    } else {
      _publishToScheduleTopics(devId, 'SCH_CLEAR');
    }
  }

  /// Clear a specific schedule slot (1–5).
  /// Spec Section 10: Payload SCH_CLEAR1 .. SCH_CLEAR5
  void clearScheduleSlot(int slot, {String? targetDeviceId}) {
    final devId = _resolveScheduleDeviceId(targetDeviceId);
    debugPrint('📅 [MQTT] Clearing schedule slot $slot (device: $devId)');
    if (isBluetoothConnected) {
      sendBluetoothCommand('SCH_CLEAR$slot');
    } else {
      _publishToScheduleTopics(devId, 'SCH_CLEAR$slot');
    }
  }

  /// Clear the lunch slot.
  /// Spec Section 10: Payload SCH_CLEAR_LUNCH
  void clearLunchSlot({String? targetDeviceId}) {
    final devId = _resolveScheduleDeviceId(targetDeviceId);
    debugPrint('📅 [MQTT] Clearing lunch slot (device: $devId)');
    if (isBluetoothConnected) {
      sendBluetoothCommand('SCH_CLEAR_LUNCH');
    } else {
      _publishToScheduleTopics(devId, 'SCH_CLEAR_LUNCH');
    }
  }

  /// Get current schedule state.
  /// Spec Section 10: Payload STATUS
  void getScheduleStatus({String? targetDeviceId}) {
    final devId = _resolveScheduleDeviceId(targetDeviceId);
    debugPrint('📅 [MQTT] Requesting schedule STATUS (device: $devId)');
    if (isBluetoothConnected) {
      sendBluetoothCommand('SCH_STATUS');
    } else {
      _publishToScheduleTopics(devId, 'STATUS');
    }
  }

  // ── WiFi Configuration & Commands (Spec Section 11) ───────────────────

  /// Internal router for WiFi MQTT commands to ensure commands route strictly
  /// to the intended device without cross-talk or root broadcasts.
  Future<void> _publishWifiCommand(String payload,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceName}) async {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('📡 [MQTT] Sending WiFi command: $payload for device: $devId');

    if (devId.isNotEmpty) {
      final devWifiTopic = AppConfig.getMqttWifiTopic(devId);
      await _publish(devWifiTopic, payload);

      final directTopic = '$devId/wifi';
      if (directTopic.toLowerCase() != devWifiTopic.toLowerCase()) {
        await _publish(directTopic, payload);
      }

      if (targetDeviceImei != null &&
          targetDeviceImei.isNotEmpty &&
          !isPlaceholderId(targetDeviceImei) &&
          targetDeviceImei.toLowerCase() != devId.toLowerCase()) {
        final imeiWifiTopic = AppConfig.getMqttWifiTopic(targetDeviceImei);
        if (imeiWifiTopic.toLowerCase() != devWifiTopic.toLowerCase()) {
          await _publish(imeiWifiTopic, payload);
        }
        final directImeiWifi = '$targetDeviceImei/wifi';
        if (directImeiWifi.toLowerCase() != imeiWifiTopic.toLowerCase() &&
            directImeiWifi.toLowerCase() != directTopic.toLowerCase()) {
          await _publish(directImeiWifi, payload);
        }
      }

    } else {
      final root = AppConfig.mqttRoot;
      final rootWifiTopic = root.isNotEmpty ? '$root/wifi' : 'wifi';
      await _publish(rootWifiTopic, payload);
    }
  }

  /// Send a WiFi reset command to reopen the 60s Bluetooth provisioning window.
  /// Spec Section 11: Topic <root>/<deviceId>/wifi, Payload: WIFI_RESET
  void sendWifiReset(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceName}) {
    _publishWifiCommand('WIFI_RESET',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceName: targetDeviceName);
  }

  /// Request WiFi info via MQTT.
  /// Spec Section 11: Topic <root>/<deviceId>/wifi, Payload: STATUS
  void requestWifiStatus(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceName}) {
    _publishWifiCommand('STATUS',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceName: targetDeviceName);
  }

  /// Set WiFi credentials via MQTT.
  /// Spec Section 11: Topic <root>/<deviceId>/wifi, Payload: SET:SSID,PASSWORD
  void setWifiMqtt(String ssid, String password,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceName}) {
    _publishWifiCommand('SET:$ssid,$password',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceName: targetDeviceName);
    _publishWifiCommand('PRIMARY:$ssid,$password',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceName: targetDeviceName);
  }

  /// Set primary WiFi credentials via MQTT.
  /// Spec Section 11: Topic <root>/<deviceId>/wifi, Payload: PRIMARY:SSID,PASSWORD
  void setPrimaryWifiMqtt(String ssid, String password,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceName}) {
    _publishWifiCommand('PRIMARY:$ssid,$password',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceName: targetDeviceName);
    _publishWifiCommand('SET:$ssid,$password',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceName: targetDeviceName);
  }

  /// Erase WiFi credentials via MQTT.
  /// Spec Section 11: Topic <root>/<deviceId>/wifi, Payload: ERASE
  void eraseWifiMqtt(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceName}) {
    _publishWifiCommand('ERASE',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceName: targetDeviceName);
  }

  /// Send a WiFi connect command to switch to/connect to the configured WiFi.
  void sendWifiConnect(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceName}) {
    _publishWifiCommand('WIFI_CONNECT',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceName: targetDeviceName);
  }

  /// Set secondary WiFi credentials via MQTT.
  void setSecondaryWifiMqtt(String ssid, String password,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceName}) {
    _publishWifiCommand('SECONDARY:$ssid,$password',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceName: targetDeviceName);
  }

  // ── OTA Commands (Spec Section 12) ────────────────────────────────────

  /// Check for OTA update via MQTT.
  /// Spec Section 12: Topic <root>/ota, Payload: CHECK
  void checkOta({String? targetDeviceId}) {
    final devId = targetDeviceId ?? _deviceId;
    final otaTopic = AppConfig.getMqttOtaTopic(devId);
    debugPrint('🔄 [MQTT] Checking OTA update (device: $devId)');
    _publish(otaTopic, 'CHECK');
  }

  /// Trigger OTA firmware update via MQTT.
  /// Spec Section 12: Topic <root>/ota, Payload: URL:http://<server>/<firmware>.bin
  void updateOta(String url, {String? targetDeviceId}) {
    final devId = targetDeviceId ?? _deviceId;
    final otaTopic = AppConfig.getMqttOtaTopic(devId);
    debugPrint('🔄 [MQTT] Triggering OTA update -> URL:$url (device: $devId)');
    _publish(otaTopic, 'URL:$url');
  }

  // ── IR Learn Control (Spec Section 5) ─────────────────────────────────

  /// Send LEARN_ON (and IR_LEARN_ON) to arm IR receiver for next AC ON signal.
  void learnOn(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    sendControlCommand('LEARN_ON',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  /// Send LEARN_OFF (and IR_LEARN_OFF) to arm IR receiver for next AC OFF signal.
  void learnOff(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    sendControlCommand('LEARN_OFF',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  /// Send LEARN_UP:<temp> to arm IR receiver for UP step.
  void learnTempUp(int temp,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    if (temp < 16 || temp > 29) {
      debugPrint(
          '⚠️ [MQTT] IR_LEARN_TEMP_UP temperature out of range (16-29): $temp');
      return;
    }
    sendControlCommand('LEARN_UP:$temp',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  /// Send LEARN_DOWN:<temp> to arm IR receiver for DOWN step.
  void learnTempDown(int temp,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    if (temp < 17 || temp > 30) {
      debugPrint(
          '⚠️ [MQTT] IR_LEARN_TEMP_DOWN temperature out of range (17-30): $temp');
      return;
    }
    sendControlCommand('LEARN_DOWN:$temp',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  /// Alias for learnTempUp
  void learnUp(int temp,
          {String? targetDeviceId,
          String? targetDeviceImei,
          String? targetDeviceShortId,
          String? targetDeviceName}) =>
      learnTempUp(temp,
          targetDeviceId: targetDeviceId,
          targetDeviceImei: targetDeviceImei,
          targetDeviceShortId: targetDeviceShortId,
          targetDeviceName: targetDeviceName);

  /// Alias for learnTempDown
  void learnDown(int temp,
          {String? targetDeviceId,
          String? targetDeviceImei,
          String? targetDeviceShortId,
          String? targetDeviceName}) =>
      learnTempDown(temp,
          targetDeviceId: targetDeviceId,
          targetDeviceImei: targetDeviceImei,
          targetDeviceShortId: targetDeviceShortId,
          targetDeviceName: targetDeviceName);

  /// Send LEARN_STOP (and IR_LEARN_STOP) to cancel any in-progress IR capture.
  void learnStop(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    sendControlCommand('LEARN_STOP',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  /// Request LEARN status.
  void getLearnStatus(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    sendControlCommand('LEARN_STATUS',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  /// Send CLEAR_ON to free RAM + delete /ir/on.bin.
  void clearOn(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    sendControlCommand('CLEAR_ON',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  /// Send CLEAR_OFF to free RAM + delete /ir/off.bin.
  void clearOff(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    sendControlCommand('CLEAR_OFF',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  /// Send CLEAR_UP:<16-29> to delete that UP step file.
  void clearUp(int temp,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    if (temp < 16 || temp > 29) {
      debugPrint('⚠️ [MQTT] CLEAR_UP temperature out of range (16-29): $temp');
      return;
    }
    sendControlCommand('CLEAR_UP:$temp',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  /// Send CLEAR_DOWN:<17-30> to delete that DOWN step file.
  void clearDown(int temp,
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    if (temp < 17 || temp > 30) {
      debugPrint(
          '⚠️ [MQTT] CLEAR_DOWN temperature out of range (17-30): $temp');
      return;
    }
    sendControlCommand('CLEAR_DOWN:$temp',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  /// Send CLEAR_ALL to delete all learned IR files.
  void clearAll(
      {String? targetDeviceId,
      String? targetDeviceImei,
      String? targetDeviceShortId,
      String? targetDeviceName}) {
    sendControlCommand('CLEAR_ALL',
        targetDeviceId: targetDeviceId,
        targetDeviceImei: targetDeviceImei,
        targetDeviceShortId: targetDeviceShortId,
        targetDeviceName: targetDeviceName);
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Validate HH:MM format (24hr, zero-padded).
  static bool isValidTime(String time) {
    final regex = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    if (!regex.hasMatch(time)) {
      debugPrint('⚠️ [MQTT] Invalid time format: $time (expected HH:MM)');
      return false;
    }
    return true;
  }

  /// Disconnect from broker.
  void disconnect() {
    try {
      _client?.disconnect();
    } catch (_) {}
    _sseWatchdogTimer?.cancel();
    _sseWatchdogTimer = null;
    _sseSub?.cancel();
    _sseSub = null;
    _isConnected = false;
    _connectionController.add(false);
    notifyListeners();
  }

  /// Dispose all resources.
  @override
  void dispose() {
    disconnect();
    _stateController.close();
    _responseController.close();
    _connectionController.close();
    super.dispose();
  }
}
