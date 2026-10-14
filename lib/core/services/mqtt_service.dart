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
        int parsedCurrentTemp = _toInt(
            root['current_temp'] ??
                payload['temp'] ??
                payload['current_temp'] ??
                rawObj['current_temp'] ??
                rawObj['temp'] ??
                root['currentTemp'] ??
                payload['currentTemp'],
            0);

        final bool isOffsetApplied = root['temp_offset_applied'] == true ||
            payload['temp_offset_applied'] == true ||
            rawObj['temp_offset_applied'] == true;

        final String rawDevId = (root['device_id'] ??
                root['deviceId'] ??
                payload['device_id'] ??
                payload['deviceId'] ??
                rawObj['device_id'] ??
                '')
            .toString();

        final String rawImei = (root['imei'] ?? payload['imei'] ?? rawObj['imei'] ?? '').toString();

        if (!isOffsetApplied &&
            parsedCurrentTemp > 0 &&
            (rawDevId.toLowerCase().contains('bluestar') || rawImei.toLowerCase().contains('bluestar'))) {
          parsedCurrentTemp = (parsedCurrentTemp - 6).clamp(0, 50);
        }

        return parsedCurrentTemp;
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

  void setDeviceId(String id) {
    if (id.isNotEmpty && id != _deviceId) {
      _deviceId = id;
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

  void _recordLastReceivedTime(String id) {
    if (id.isEmpty) return;
    _deviceLastReceivedTime[id.toLowerCase()] = DateTime.now();
  }

  SirisDeviceState? _lastState;
  SirisDeviceState? get lastState => _lastState;
  bool get isConnected => _isConnected;

  SirisDeviceState? getLastStateFor(String id) {
    if (id.isEmpty) return null;
    final lowerId = id.toLowerCase();

    SirisDeviceState? state;
    if (_deviceStates.containsKey(lowerId)) {
      state = _deviceStates[lowerId];
    } else {
      for (var entry in _deviceStates.entries) {
        final st = entry.value;
        final stDevLower = st.deviceId.toLowerCase();
        final isDevMatch = stDevLower == lowerId ||
            st.imei.toLowerCase() == lowerId ||
            stDevLower.contains(lowerId) ||
            lowerId.contains(stDevLower) ||
            st.imei.toLowerCase().contains(lowerId) ||
            lowerId.contains(st.imei.toLowerCase()) ||
            (!lowerId.contains('test') &&
                !stDevLower.contains('test') &&
                lowerId.contains('sustainabyte') &&
                stDevLower.contains('sustainabyte'));
        if (isDevMatch) {
          state = st;
          break;
        }
      }
    }

    if (state != null) {
      final lastTime = _deviceLastReceivedTime[state.deviceId.toLowerCase()] ??
          _deviceLastReceivedTime[state.imei.toLowerCase()];
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
      if (deviceId != null && deviceId.isNotEmpty && deviceId != _deviceId) {
        final oldDeviceId = _deviceId;
        _deviceId = deviceId;
        _imei = imei;
        AppConfig.mqttDeviceId = deviceId;
        _subscribeToDataTopic();

        // Restart SSE stream for the new device so telemetry targets the switched device
        final cId = (companyId != null && companyId.isNotEmpty)
            ? companyId
            : _companyId;
        if (cId.isNotEmpty) {
          _companyId = cId;
          debugPrint(
              '🔄 [MQTT] Device switched from $oldDeviceId to $deviceId — restarting SSE stream');
          _startSseStream(_companyId, _deviceId, _imei);
        }
      }
      return true;
    }
    if (_isConnecting) {
      debugPrint(
          '⏳ [MQTT] Connection attempt already in progress. Skipping new connect call.');
      return false;
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

    // ── Fetch MQTT credentials from API ──────────────────────────────
    // Calls GET /provisionservice/v1/companies/{companyId}/mqtt-configs
    // Falls back to .env / AppConfig defaults if the API is unreachable.
    final mqttCreds = await MqttConfigService.fetchMqttConfig(
      companyId: companyId,
      type: 'AC',
    );

    final broker = (mqttCreds?.host != null && mqttCreds!.host!.isNotEmpty)
        ? mqttCreds.host!
        : AppConfig.mqttBroker;
    final port = (mqttCreds?.port != null && mqttCreds!.port! > 0)
        ? mqttCreds.port!
        : AppConfig.mqttPort;
    final username = mqttCreds?.username.isNotEmpty == true
        ? mqttCreds!.username
        : AppConfig.mqttUsername;
    final password = mqttCreds?.password.isNotEmpty == true
        ? mqttCreds!.password
        : AppConfig.mqttPassword;
    final clientId = 'siris_flutter_${DateTime.now().millisecondsSinceEpoch}';

    debugPrint(
        '🔑 [MQTT] Using credentials: user=$username (source: ${mqttCreds != null ? "API" : ".env/fallback"})');

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
      final user = AppConfig.mqttUsername;
      final dataTopic = AppConfig.mqttDataTopic;

      final Set<String> topicsToSubscribe = {};

      // 1. SIRIS Spec Section 1 & 13 topics
      if (rootTopic.isNotEmpty) {
        topicsToSubscribe.add('$rootTopic/#');
        topicsToSubscribe.add('$rootTopic/data');
        topicsToSubscribe.add('$rootTopic/status');
        topicsToSubscribe.add('$rootTopic/online');
        topicsToSubscribe.add('$rootTopic/schedule');
        topicsToSubscribe.add('$rootTopic/control');
        topicsToSubscribe.add('$rootTopic/wifi');
        topicsToSubscribe.add('$rootTopic/ota');
      }

      // 2. Data telemetry fallback topics
      if (dataTopic.isNotEmpty) {
        topicsToSubscribe.add(dataTopic);
      }
      if (user.isNotEmpty && user != rootTopic) {
        topicsToSubscribe.add('$user/data');
        topicsToSubscribe.add('$user/status');
        topicsToSubscribe.add('$user/online');
      }
      topicsToSubscribe.add('+/data');
      topicsToSubscribe.add('+/status');
      topicsToSubscribe.add('+/online');
      topicsToSubscribe.add('+/schedule');

      // 3. Dynamic target device subscriptions
      if (_deviceId.isNotEmpty) {
        topicsToSubscribe.add(AppConfig.getMqttStatusTopic(_deviceId));
        topicsToSubscribe.add(AppConfig.getMqttIrLearnTopic(_deviceId));
        topicsToSubscribe.add(AppConfig.getMqttScheduleTopic(_deviceId));
        topicsToSubscribe.add('$_deviceId/status');
        topicsToSubscribe.add('$_deviceId/ir_learn');
      }

      // 4. IMEI-specific topics if different from deviceId
      if (_imei != null && _imei!.isNotEmpty && _imei != _deviceId) {
        topicsToSubscribe.add(AppConfig.getMqttStatusTopic(_imei!));
        topicsToSubscribe.add(AppConfig.getMqttIrLearnTopic(_imei!));
        topicsToSubscribe.add('$_imei/status');
        topicsToSubscribe.add('$_imei/ir_learn');
      }

      for (final topic in topicsToSubscribe) {
        _client!.subscribe(topic, MqttQos.atLeastOnce);
        debugPrint('📨 [MQTT] Subscribed to: $topic');
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
          topicLower.endsWith('/schedule') ||
          topicLower.endsWith('/wifi') ||
          topicLower.endsWith('/ota')) {
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
          (imei.isNotEmpty ? _deviceStates[imei.toLowerCase()] : null) ??
          (_deviceId.isNotEmpty
              ? _deviceStates[_deviceId.toLowerCase()]
              : null) ??
          _lastState;

      final state = SirisDeviceState.fromJson(json, prev);

      // Cache state for all devices to support instantaneous UI updates on switch
      if (state.deviceId.isNotEmpty) {
        _deviceStates[state.deviceId.toLowerCase()] = state;
        if (state.isActive) {
          _recordLastReceivedTime(state.deviceId);
        }
      }
      if (state.imei.isNotEmpty) {
        _deviceStates[state.imei.toLowerCase()] = state;
        if (state.isActive) {
          _recordLastReceivedTime(state.imei);
        }
      }

      // Only accept messages from our target device.
      // Prioritize device_id matching; IMEI matching is a fallback only when
      // the incoming device_id is empty or when IMEIs are truly unique identifiers.
      bool isMatch = _deviceId.isEmpty;
      if (!isMatch) {
        final stateDevLower = state.deviceId.toLowerCase();
        final targetLower = _deviceId.toLowerCase();

        // Primary: exact device_id match (or normalized match)
        isMatch = stateDevLower == targetLower ||
            stateDevLower.replaceAll('_', '').replaceAll('-', '') ==
                targetLower.replaceAll('_', '').replaceAll('-', '');

        // Fallback: IMEI match, but ONLY if device_id is empty in the incoming
        // state (i.e. we can't distinguish by device_id) AND the IMEI looks
        // like a real identifier (not a placeholder like "numberIMEI").
        if (!isMatch && state.deviceId.isEmpty && state.imei.isNotEmpty) {
          final stateImei = state.imei.toLowerCase();
          final isPlaceholderImei = stateImei == 'numberimei' ||
              stateImei == 'imei' ||
              stateImei == 'unknown';
          if (!isPlaceholderImei) {
            isMatch = stateImei == targetLower ||
                (_imei != null &&
                    _imei!.isNotEmpty &&
                    stateImei == _imei!.toLowerCase());
          }
        }
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
        _lastState ??
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
    if (updated.deviceId.isNotEmpty) {
      _deviceStates[updated.deviceId.toLowerCase()] = updated;
      _recordLastReceivedTime(updated.deviceId);
    }
    if (updated.imei.isNotEmpty) {
      _deviceStates[updated.imei.toLowerCase()] = updated;
      _recordLastReceivedTime(updated.imei);
    }

    _lastState = updated;
    _stateController.add(updated);
    notifyListeners();
    debugPrint(
        '📝 [MQTT] Updated cached state for $deviceId: ac=${updated.ac}, setTemp=${updated.setTemp}');
  }

  void _handleStringResponse(String payload,
      {String? topic, String? explicitDeviceId}) {
    final upper = payload.toUpperCase();

    String? responseDeviceId = explicitDeviceId;
    final parts = payload.split(':');
    if (parts.isNotEmpty && parts[0].isNotEmpty) {
      final candidate = parts[0].trim();
      final candUpper = candidate.toUpperCase();
      if (!candidate.contains(' ') &&
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
      );
    } else if (upper.contains('AC_OFF_DONE')) {
      if (responseDeviceId != null) {
        _updateCachedDeviceState(responseDeviceId, ac: 'OFF');
      }
      response = SirisResponse(
        type: SirisResponseType.acOffDone,
        rawPayload: payload,
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
  /// Uses MqttQos.atMostOnce (QoS 0) to guarantee the packet is delivered strictly ONCE without duplicates.
  Future<bool> _publish(String topic, String message) async {
    final now = DateTime.now();
    final isSteppingCmd = message == 'TEMP_UP' || message == 'TEMP_DOWN';
    if (!isSteppingCmd &&
        _lastPublishedTopic == topic &&
        _lastPublishedMessage == message &&
        _lastPublishedTime != null &&
        now.difference(_lastPublishedTime!).inMilliseconds < 1500) {
      debugPrint(
          '🛡️ [MQTT] Suppressed duplicate publish within 1500ms to $topic: $message');
      return true;
    }
    _lastPublishedTopic = topic;
    _lastPublishedMessage = message;
    _lastPublishedTime = now;

    if (_client == null ||
        _client!.connectionStatus?.state != MqttConnectionState.connected) {
      debugPrint(
          '📡 [MQTT] Socket client not connected. Attempting auto-reconnect before publish...');
      await connect(deviceId: _deviceId.isNotEmpty ? _deviceId : '');
    }

    bool published = false;
    if (_client != null &&
        _client!.connectionStatus?.state == MqttConnectionState.connected) {
      try {
        final builder = MqttClientPayloadBuilder();
        builder.addString(message);
        _client!.publishMessage(topic, MqttQos.atMostOnce, builder.payload!,
            retain: false);
        debugPrint(
            '📤 [MQTT] Published via socket to $topic: $message (QoS 0, 1 time only)');
        published = true;
      } catch (e) {
        debugPrint('⚠️ [MQTT] Socket publish error: $e');
      }
    }

    return published;
  }

  /// Send a custom control command to the control topic.
  /// Intelligently routes commands:
  /// - For sub-devices (e.g. Sustainabyte_testir): publishes ONLY to dedicated sub-device topics.
  /// - For root/primary devices (e.g. Sustainabyte_ITir / Sustainabyte_ir): publishes to root topic and device aliases.
  Future<void> sendControlCommand(String command,
      {String? targetDeviceId}) async {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint(
        '📡 [MQTT] Sending Control command: $command for device: $devId');
    if (isBluetoothConnected) {
      sendBluetoothCommand(command);
    } else {
      final rootControlTopic = AppConfig.mqttRoot.isNotEmpty
          ? '${AppConfig.mqttRoot}/control'
          : 'control';
      final devControlTopic = AppConfig.getMqttControlTopic(devId);
      final directTopic = '$devId/control';

      final lowerDev = devId.toLowerCase().trim();
      final isSubDevice = lowerDev.contains('test');

      if (isSubDevice) {
        // Dedicated sub-device (e.g. Sustainabyte_testir):
        // Only publish to its device-specific control topic so the root device (ITir) does NOT execute it!
        await _publish(devControlTopic, command);
        if (directTopic.toLowerCase() != devControlTopic.toLowerCase()) {
          await _publish(directTopic, command);
        }
      } else {
        // Root / primary device (e.g. Sustainabyte_ITir / Sustainabyte_ir):
        // Publish to root control topic (firmware listens here) AND device-specific topics!
        await _publish(rootControlTopic, command);
        if (devControlTopic.toLowerCase() != rootControlTopic.toLowerCase()) {
          await _publish(devControlTopic, command);
        }
        if (directTopic.toLowerCase() != rootControlTopic.toLowerCase() &&
            directTopic.toLowerCase() != devControlTopic.toLowerCase()) {
          await _publish(directTopic, command);
        }
        // Also publish to alias with "IT" if devId is Sustainabyte_ir or shortId
        if (lowerDev == 'sustainabyte_ir' || lowerDev == 'acacsustai') {
          final itTopic = AppConfig.mqttRoot.isNotEmpty
              ? '${AppConfig.mqttRoot}/Sustainabyte_ITir/control'
              : 'Sustainabyte_ITir/control';
          await _publish(itTopic, command);
          await _publish('Sustainabyte_ITir/control', command);
        }
      }
    }
  }

  // ── AC Power Control (Spec Section 2) ─────────────────────────────────

  /// Turn AC ON.
  /// Spec Section 2: Topic <root>/<deviceId>/control, Payload: ON
  void turnAcOn({String? targetDeviceId}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('⚡ [MQTT] Turn AC ON for device: $devId');
    sendControlCommand('ON', targetDeviceId: devId);
  }

  /// Turn AC OFF.
  /// Spec Section 2: Topic <root>/<deviceId>/control, Payload: OFF
  void turnAcOff({String? targetDeviceId}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('🔌 [MQTT] Turn AC OFF for device: $devId');
    sendControlCommand('OFF', targetDeviceId: devId);
  }

  /// Request device STATUS.
  /// Spec Section 2: Topic <root>/<deviceId>/control, Payload: STATUS
  void sendStatus({String? targetDeviceId}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('📡 [MQTT] Requesting STATUS for device: $devId');
    sendControlCommand('STATUS', targetDeviceId: devId);
  }

  // ── Automate Commands (Spec Section 4) ────────────────────────────────

  /// Enable smart automation with target temperature (Range: 16–30°C).
  void enableAutomation({int? autoTemp, String? targetDeviceId}) {
    final devId = targetDeviceId ?? _deviceId;
    final cmd = (autoTemp != null && autoTemp >= 16 && autoTemp <= 30)
        ? 'AUTO:$autoTemp'
        : 'AUTO';
    debugPrint(
        '🤖 [MQTT] Enabling automation: $cmd (device: $devId)');
    sendControlCommand(cmd, targetDeviceId: devId);
    if (devId.isNotEmpty) {
      _updateCachedDeviceState(devId, automate: true);
    }
  }

  /// Set or update dynamic Auto Mode temperature threshold (e.g. AUTO:22).
  void setAutoTemperature(int temp, {String? targetDeviceId}) {
    enableAutomation(autoTemp: temp, targetDeviceId: targetDeviceId);
  }

  /// Disable smart automation.
  void disableAutomation({String? targetDeviceId}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint(
        '🤖 [MQTT] Disabling automation: AUTO_OFF (device: $devId)');
    sendControlCommand('AUTO_OFF', targetDeviceId: devId);
    if (devId.isNotEmpty) {
      _updateCachedDeviceState(devId, automate: false);
    }
  }

  // ── Temperature Control (Spec Section 3) ──────────────────────────────

  /// Set temperature (Range: 16 to 30 C).
  void setTemperature(int temp, {String? targetDeviceId}) {
    if (temp < 16 || temp > 30) {
      debugPrint('⚠️ Temperature out of range (16-30): $temp');
      return;
    }

    final devId = targetDeviceId ?? _deviceId;
    if (isBluetoothConnected) {
      sendBluetoothCommand('SEND:TEMP_$temp');
    } else {
      sendControlCommand('TEMP:$temp', targetDeviceId: devId);

      final rootTempTopic = AppConfig.mqttRoot.isNotEmpty
          ? '${AppConfig.mqttRoot}/control/set_temp'
          : 'control/set_temp';
      final devTempTopic = AppConfig.getMqttTempTopic(devId);
      final directTempTopic = '$devId/control/set_temp';

      final lowerDev = devId.toLowerCase().trim();
      final isSubDevice = lowerDev.contains('test');

      if (isSubDevice) {
        _publish(devTempTopic, '$temp');
        if (directTempTopic.toLowerCase() != devTempTopic.toLowerCase()) {
          _publish(directTempTopic, '$temp');
        }
      } else {
        _publish(rootTempTopic, '$temp');
        if (devTempTopic.toLowerCase() != rootTempTopic.toLowerCase()) {
          _publish(devTempTopic, '$temp');
        }
        if (directTempTopic.toLowerCase() != rootTempTopic.toLowerCase() &&
            directTempTopic.toLowerCase() != devTempTopic.toLowerCase()) {
          _publish(directTempTopic, '$temp');
        }
        if (lowerDev == 'sustainabyte_ir' || lowerDev == 'acacsustai') {
          final itTempTopic = AppConfig.mqttRoot.isNotEmpty
              ? '${AppConfig.mqttRoot}/Sustainabyte_ITir/control/set_temp'
              : 'Sustainabyte_ITir/control/set_temp';
          _publish(itTempTopic, '$temp');
          _publish('Sustainabyte_ITir/control/set_temp', '$temp');
        }
      }

      debugPrint('🌡️ [MQTT] Temperature $temp sent for $devId');
    }
  }

  /// Send TEMPERATURE UP command.
  void tempUp({String? targetDeviceId}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('🌡️ [MQTT] Temperature UP (device: $devId)');
    final currentState = getLastStateFor(devId) ?? _lastState;
    if (currentState != null && currentState.setTemp < 30) {
      _updateCachedDeviceState(devId, setTemp: currentState.setTemp + 1);
    }
    sendControlCommand('TEMP_UP', targetDeviceId: devId);
  }

  /// Send TEMPERATURE DOWN command.
  void tempDown({String? targetDeviceId}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('🌡️ [MQTT] Temperature DOWN (device: $devId)');
    final currentState = getLastStateFor(devId) ?? _lastState;
    if (currentState != null && currentState.setTemp > 16) {
      _updateCachedDeviceState(devId, setTemp: currentState.setTemp - 1);
    }
    sendControlCommand('TEMP_DOWN', targetDeviceId: devId);
  }

  /// Reset / Clear temperature to 24°C default.
  void tempClear({String? targetDeviceId}) {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('🌡️ [MQTT] Temperature CLEAR to 24°C (device: $devId)');
    sendControlCommand('TEMP_CLEAR', targetDeviceId: devId);
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
    if (targetDeviceId != null && targetDeviceId.isNotEmpty)
      return targetDeviceId;
    if (_deviceId.isNotEmpty) return _deviceId;
    return AppConfig.mqttDeviceId;
  }

  void _publishToScheduleTopics(String devId, String command) {
    final primaryTopic = AppConfig.getMqttScheduleTopic(devId);
    _publish(primaryTopic, command);

    final directTopic = '$devId/schedule';
    if (directTopic.toLowerCase() != primaryTopic.toLowerCase()) {
      _publish(directTopic, command);
    }

    final root = AppConfig.mqttTopic;
    if (root.isNotEmpty && devId.isNotEmpty) {
      final rootDevTopic = '$root/$devId/schedule';
      if (rootDevTopic.toLowerCase() != primaryTopic.toLowerCase() &&
          rootDevTopic.toLowerCase() != directTopic.toLowerCase()) {
        _publish(rootDevTopic, command);
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
  /// to the intended sub-device or root device without cross-talk.
  Future<void> _publishWifiCommand(String payload, {String? targetDeviceId}) async {
    final devId = targetDeviceId ?? _deviceId;
    debugPrint('📡 [MQTT] Sending WiFi command: $payload for device: $devId');
    final root = AppConfig.mqttRoot;
    final rootWifiTopic = root.isNotEmpty ? '$root/wifi' : 'wifi';
    final devWifiTopic = AppConfig.getMqttWifiTopic(devId);
    final directTopic = '$devId/wifi';

    final lowerDev = devId.toLowerCase().trim();
    final isSubDevice = lowerDev.contains('test');

    if (isSubDevice) {
      // Sub-device (e.g. Sustainabyte_testir): strictly isolated
      await _publish(devWifiTopic, payload);
      if (directTopic.toLowerCase() != devWifiTopic.toLowerCase()) {
        await _publish(directTopic, payload);
      }
    } else {
      // Root / primary device (e.g. Sustainabyte_ITir / Sustainabyte_ir / acacsustai)
      await _publish(rootWifiTopic, payload);
      if (devWifiTopic.toLowerCase() != rootWifiTopic.toLowerCase()) {
        await _publish(devWifiTopic, payload);
      }
      if (directTopic.toLowerCase() != rootWifiTopic.toLowerCase() &&
          directTopic.toLowerCase() != devWifiTopic.toLowerCase()) {
        await _publish(directTopic, payload);
      }
      if (lowerDev == 'sustainabyte_ir' || lowerDev == 'acacsustai') {
        final itTopic = root.isNotEmpty
            ? '$root/Sustainabyte_ITir/wifi'
            : 'Sustainabyte_ITir/wifi';
        await _publish(itTopic, payload);
        await _publish('Sustainabyte_ITir/wifi', payload);
      }
    }
  }

  /// Send a WiFi reset command to reopen the 60s Bluetooth provisioning window.
  /// Spec Section 11: Topic <root>/wifi, Payload: WIFI_RESET
  void sendWifiReset({String? targetDeviceId}) {
    _publishWifiCommand('WIFI_RESET', targetDeviceId: targetDeviceId);
  }

  /// Request WiFi info via MQTT.
  /// Spec Section 11: Topic <root>/wifi, Payload: STATUS
  void requestWifiStatus({String? targetDeviceId}) {
    _publishWifiCommand('STATUS', targetDeviceId: targetDeviceId);
  }

  /// Set WiFi credentials via MQTT.
  /// Spec Section 11: Topic <root>/wifi, Payload: SET:SSID,PASSWORD
  void setWifiMqtt(String ssid, String password, {String? targetDeviceId}) {
    _publishWifiCommand('SET:$ssid,$password', targetDeviceId: targetDeviceId);
    _publishWifiCommand('PRIMARY:$ssid,$password', targetDeviceId: targetDeviceId);
  }

  /// Set primary WiFi credentials via MQTT.
  /// Spec Section 11: Topic <root>/wifi, Payload: PRIMARY:SSID,PASSWORD
  void setPrimaryWifiMqtt(String ssid, String password,
      {String? targetDeviceId}) {
    _publishWifiCommand('PRIMARY:$ssid,$password', targetDeviceId: targetDeviceId);
    _publishWifiCommand('SET:$ssid,$password', targetDeviceId: targetDeviceId);
  }

  /// Erase WiFi credentials via MQTT.
  /// Spec Section 11: Topic <root>/wifi, Payload: ERASE
  void eraseWifiMqtt({String? targetDeviceId}) {
    _publishWifiCommand('ERASE', targetDeviceId: targetDeviceId);
  }

  /// Send a WiFi connect command to switch to/connect to the configured WiFi.
  void sendWifiConnect({String? targetDeviceId}) {
    _publishWifiCommand('WIFI_CONNECT', targetDeviceId: targetDeviceId);
  }

  /// Set secondary WiFi credentials via MQTT.
  void setSecondaryWifiMqtt(String ssid, String password,
      {String? targetDeviceId}) {
    _publishWifiCommand('SECONDARY:$ssid,$password', targetDeviceId: targetDeviceId);
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

  /// Send IR_LEARN_ON to arm IR receiver for next AC ON signal.
  /// Spec Section 5: Topic <root>/control, Payload: IR_LEARN_ON
  void learnOn({String? targetDeviceId}) {
    sendControlCommand('IR_LEARN_ON', targetDeviceId: targetDeviceId);
  }

  /// Send IR_LEARN_OFF to arm IR receiver for next AC OFF signal.
  /// Spec Section 5: Topic <root>/control, Payload: IR_LEARN_OFF
  void learnOff({String? targetDeviceId}) {
    sendControlCommand('IR_LEARN_OFF', targetDeviceId: targetDeviceId);
  }

  /// Send IR_LEARN_TEMP_UP:<temperature> (Range: 16–29°C) to arm IR receiver for UP step.
  /// Spec Section 3.6: Topic <root>/control, Payload: IR_LEARN_TEMP_UP:<16-29>
  void learnTempUp(int temp, {String? targetDeviceId}) {
    if (temp < 16 || temp > 29) {
      debugPrint(
          '⚠️ [MQTT] IR_LEARN_TEMP_UP temperature out of range (16-29): $temp');
      return;
    }
    sendControlCommand('IR_LEARN_TEMP_UP:$temp',
        targetDeviceId: targetDeviceId);
  }

  /// Send IR_LEARN_TEMP_DOWN:<temperature> (Range: 17–30°C) to arm IR receiver for DOWN step.
  /// Spec Section 3.6: Topic <root>/control, Payload: IR_LEARN_TEMP_DOWN:<17-30>
  void learnTempDown(int temp, {String? targetDeviceId}) {
    if (temp < 17 || temp > 30) {
      debugPrint(
          '⚠️ [MQTT] IR_LEARN_TEMP_DOWN temperature out of range (17-30): $temp');
      return;
    }
    sendControlCommand('IR_LEARN_TEMP_DOWN:$temp',
        targetDeviceId: targetDeviceId);
  }

  /// Alias for learnTempUp
  void learnUp(int temp, {String? targetDeviceId}) =>
      learnTempUp(temp, targetDeviceId: targetDeviceId);

  /// Alias for learnTempDown
  void learnDown(int temp, {String? targetDeviceId}) =>
      learnTempDown(temp, targetDeviceId: targetDeviceId);

  /// Send IR_LEARN_STOP to cancel any in-progress IR capture.
  /// Spec Section 5: Topic <root>/control, Payload: IR_LEARN_STOP
  void learnStop({String? targetDeviceId}) {
    sendControlCommand('IR_LEARN_STOP', targetDeviceId: targetDeviceId);
  }

  /// Request LEARN status.
  void getLearnStatus({String? targetDeviceId}) {
    sendControlCommand('LEARN_STATUS', targetDeviceId: targetDeviceId);
  }

  /// Send CLEAR_ON to free RAM + delete /ir/on.bin.
  void clearOn({String? targetDeviceId}) {
    sendControlCommand('CLEAR_ON', targetDeviceId: targetDeviceId);
  }

  /// Send CLEAR_OFF to free RAM + delete /ir/off.bin.
  void clearOff({String? targetDeviceId}) {
    sendControlCommand('CLEAR_OFF', targetDeviceId: targetDeviceId);
  }

  /// Send CLEAR_UP:<16-29> to delete that UP step file.
  void clearUp(int temp, {String? targetDeviceId}) {
    if (temp < 16 || temp > 29) {
      debugPrint('⚠️ [MQTT] CLEAR_UP temperature out of range (16-29): $temp');
      return;
    }
    sendControlCommand('CLEAR_UP:$temp', targetDeviceId: targetDeviceId);
  }

  /// Send CLEAR_DOWN:<17-30> to delete that DOWN step file.
  void clearDown(int temp, {String? targetDeviceId}) {
    if (temp < 17 || temp > 30) {
      debugPrint(
          '⚠️ [MQTT] CLEAR_DOWN temperature out of range (17-30): $temp');
      return;
    }
    sendControlCommand('CLEAR_DOWN:$temp', targetDeviceId: targetDeviceId);
  }

  /// Send CLEAR_ALL to delete all learned IR files.
  void clearAll({String? targetDeviceId}) {
    sendControlCommand('CLEAR_ALL', targetDeviceId: targetDeviceId);
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
