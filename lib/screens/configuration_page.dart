// ignore_for_file: unused_element, unused_field
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_scanner_page.dart';
import 'ac_app/ac_control_page.dart';
import 'widgets/wifi_section_widget.dart';
import '../core/services/local_cache_service.dart';
import '../core/config/app_config.dart';
import '../core/services/mqtt_config_service.dart';

class ConfigurationPage extends StatefulWidget {
  final BluetoothConnection connection;
  final BluetoothDevice device;

  const ConfigurationPage({
    super.key,
    required this.connection,
    required this.device,
  });

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  late BluetoothConnection _connection;
  late BluetoothDevice _device;
  String? _actualDeviceMac;

  // ====== Theme ======
  static const Color _themeGreen = Color.fromARGB(255, 123, 159, 71);
  static const Color _background = Color(0xFF1A1A2E);
  static const Color _cardBackground = Color(0xFF2D2D44);
  static const Color _green = Color.fromARGB(255, 123, 159, 71);
  static const Color _red = Colors.red;
  static const Color _orange = Colors.orange;
  static const Color _blue = Colors.blue;

  // ====== India AC brands list (dropdown master list) ======
  // (You can add/remove brands any time. This is only for UI dropdown choices.)
  static const List<String> kIndianAcBrands = [
    // Top / common
    "Samsung",
    "LG",
    "Voltas",
    "Daikin",
    "Blue Star",
    "Hitachi",
    "Panasonic",
    "Carrier",
    "Lloyd",
    "Godrej",
    "Whirlpool",
    "Haier",

    // Mid / also common
    "Toshiba",
    "Mitsubishi Electric",
    "Mitsubishi Heavy Industries",
    "O General",
    "General",
    "Fujitsu",
    "Trane",
    "York",
    "Hisense",
    "Sharp",
    "AUX",
    "Gree",
    "TCL",

    // India-focused / budget
    "Onida",
    "Sansui",
    "IFB",
    "Electrolux",
    "Kelvinator",
    "Videocon",
    "BPL",
    "Intex",
    "Micromax",
    "Karbonn",

    // Retail / private labels
    "Croma",
    "MarQ (Flipkart)",
    "Thomson",
    "Sanyo",
    "Midea",
  ];

  // ====== Connection Flags ======
  bool _isConnected = false;
  bool _isWifiConnected = false;
  bool _isGreenLedOn = false;
  bool _isYellowLedOn = false;
  bool _isBluetoothOn = false;
  bool _hasNavigatedAway = false;
  String _lastDisconnectReason = "N/A";
  String _lastDisconnectTime = "N/A";
  Timer? _bluetoothStateTimer;
  StreamSubscription<Uint8List>? _btStreamSub;

  // ====== WiFi Info ======
  String _wifiIP = "";
  String _wifiStatus = "WiFi not connected";
  bool _isConnectingWifi = false;
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _wifiPasswordController = TextEditingController();

  // ====== Temp / RTC ======
  String _temperatureText = "--";
  String _deviceTimeText = "--";

  // ====== Terminal ======
  bool _showTerminal = true;
  final TextEditingController _terminalController = TextEditingController();
  String _incomingBuffer = "";
  bool _needsUpdate = false;

  // ===================== MQTT =====================
  bool _showMqttDropdown = false;
  bool _isMqttConnected = false;
  String _mqttStatus = "MQTT not connected";

  final TextEditingController _mqttHostController =
      TextEditingController(text: AppConfig.mqttBroker);
  final TextEditingController _mqttPortController =
      TextEditingController(text: AppConfig.mqttPort.toString());
  final TextEditingController _mqttUserController =
      TextEditingController(text: AppConfig.mqttUsername);
  final TextEditingController _mqttPassController =
      TextEditingController(text: AppConfig.mqttPassword);
  final TextEditingController _mqttTopicController =
      TextEditingController(text: AppConfig.mqttTopic);

  // ===================== Auto control =====================
  bool _autoControlEnabled = false;
  final TextEditingController _autoOnController =
      TextEditingController(text: "28");
  final TextEditingController _autoOffController =
      TextEditingController(text: "25");

  // ===================== AC Remote dropdowns =====================

  // 1) DEFAULT REMOTE dropdown (hardcoded / default send)
  bool _showDefaultRemoteDropdown = true;
  String _defaultRemoteBrand =
      "Samsung"; // default remote brand selector (still no brand in title)

  // 2) REMOTE CONFIG dropdown (learning + save)
  bool _showRemoteConfigDropdown = true;
  String _configBrand = "LG"; // brand chosen for learning
  bool _configMode = false;

  // Config step tracking
  static const List<String> _cfgKeys = [
    "POWER_ON",
    "TEMPUP",
    "TEMPDOWN",
    "SWING",
    "MODE",
    "POWER_OFF",
  ];
  int _cfgStepIndex = 0;
  bool _waitingForIr = false;
  int _learningProgress = 0;
  String _cfgStatus = "Idle";

  // Save remote dialog
  final TextEditingController _saveBrandController = TextEditingController();

  // Schedules (optional)
  final TextEditingController _onTimeController = TextEditingController();
  final TextEditingController _offTimeController = TextEditingController();

  // ===================== Lifecycle =====================
  @override
  void initState() {
    super.initState();
    _connection = widget.connection;
    _device = widget.device;

    _isConnected = _connection.isConnected;
    _isYellowLedOn = _isConnected;

    _listenBluetooth();
    _startBluetoothStateMonitor();
    _initConfiguration();
  }

  Future<void> _initConfiguration() async {
    await _loadSavedState();
    await _loadMqttConfig();

    if (mounted && _connection.isConnected) {
      _sendCommand("GET_TEMP");
      _sendCommand("GET_TIME");
      _sendCommand("GET_WIFI"); // Ask device for actual WiFi status

      // Directly show unified WiFi & MQTT configure dialog if bluetooth is connected
      _showWifiSetupDialog();

      // Timeout for initial sync
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _wifiStatus.contains("Syncing")) {
          setState(() {
            _wifiStatus = "WiFi not connected"; // Fallback if no response
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _hasNavigatedAway = true;
    _bluetoothStateTimer?.cancel();
    _btStreamSub?.cancel();
    _btStreamSub = null;
    _ssidController.dispose();
    _wifiPasswordController.dispose();

    _terminalController.dispose();
    _onTimeController.dispose();
    _offTimeController.dispose();

    _mqttHostController.dispose();
    _mqttPortController.dispose();
    _mqttUserController.dispose();
    _mqttPassController.dispose();
    _mqttTopicController.dispose();

    _autoOnController.dispose();
    _autoOffController.dispose();

    _saveBrandController.dispose();

    super.dispose();
  }

  // ===================== Storage =====================
  Future<void> _loadSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || _hasNavigatedAway) return;

      setState(() {
        final wasConnected = prefs.getBool('wifi_connected') ?? false;
        _wifiIP = prefs.getString('wifi_ip') ?? "";

        // We start as 'not connected' until the device confirms status
        _isWifiConnected = false;
        if (wasConnected) {
          _wifiStatus = "Syncing WiFi status... ⏳";
        } else {
          _wifiStatus = "WiFi not connected";
        }

        _defaultRemoteBrand =
            prefs.getString('default_remote_brand') ?? "Samsung";
        _configBrand = prefs.getString('config_remote_brand') ?? "LG";
      });

      _autoControlEnabled = prefs.getBool('auto_enabled') ?? false;

      final aon = prefs.getDouble('auto_on');
      final aoff = prefs.getDouble('auto_off');
      if (aon != null) _autoOnController.text = aon.toString();
      if (aoff != null) _autoOffController.text = aoff.toString();

      // MQTT saved preferences
      final h = prefs.getString('mqtt_host');
      final p = prefs.getInt('mqtt_port');
      final u = prefs.getString('mqtt_user');
      final pw = prefs.getString('mqtt_pass');
      final t = prefs.getString('mqtt_topic');

      if (h != null && h.isNotEmpty) _mqttHostController.text = h;
      if (p != null && p > 0) _mqttPortController.text = p.toString();
      if (u != null && u.isNotEmpty) _mqttUserController.text = u;
      if (pw != null && pw.isNotEmpty) _mqttPassController.text = pw;
      if (t != null && t.isNotEmpty) _mqttTopicController.text = t;

      // Load WiFi credentials
      final wifiCreds = await LocalCacheService.getWifiCredentials();
      if (wifiCreds['ssid']!.isNotEmpty) {
        _ssidController.text = wifiCreds['ssid']!;
        _wifiPasswordController.text = wifiCreds['password']!;
      }
    } catch (_) {}
  }

  Future<void> _loadMqttConfig() async {
    try {
      final config = await MqttConfigService.fetchMqttConfig(type: 'AC');
      if (config != null && mounted) {
        setState(() {
          if (config.topic.isNotEmpty) {
            _mqttTopicController.text = config.topic;
          }
          if (config.port != null && config.port! > 0) {
            _mqttPortController.text = config.port.toString();
          } else if (_mqttPortController.text.isEmpty) {
            _mqttPortController.text = AppConfig.mqttPort.toString();
          }
          if (config.host != null && config.host!.isNotEmpty) {
            _mqttHostController.text = config.host!;
          } else if (_mqttHostController.text.isEmpty) {
            _mqttHostController.text = AppConfig.mqttBroker;
          }
          if (config.username.isNotEmpty) {
            _mqttUserController.text = config.username;
          }
          if (config.password.isNotEmpty) {
            _mqttPassController.text = config.password;
          }
        });
        debugPrint(
            '✅ [ConfigPage] Dynamic MQTT Config loaded: topic=${config.topic}, port=${_mqttPortController.text}, ip=${_mqttHostController.text}, user=${config.username}');
      } else if (mounted) {
        // Fallback to dynamic AppConfig getters
        if (_mqttTopicController.text.isEmpty) {
          _mqttTopicController.text = AppConfig.mqttTopic;
        }
        if (_mqttPortController.text.isEmpty) {
          _mqttPortController.text = AppConfig.mqttPort.toString();
        }
        if (_mqttHostController.text.isEmpty) {
          _mqttHostController.text = AppConfig.mqttBroker;
        }
        if (_mqttUserController.text.isEmpty) {
          _mqttUserController.text = AppConfig.mqttUsername;
        }
        if (_mqttPassController.text.isEmpty) {
          _mqttPassController.text = AppConfig.mqttPassword;
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading MQTT config: $e');
    }
  }

  Future<void> _saveWifiStatus(bool connected, {String ip = ""}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wifi_connected', connected);
      await prefs.setString('wifi_ip', ip);
    } catch (_) {}
  }

  Future<void> _saveMqttPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mqtt_host', _mqttHostController.text.trim());
      await prefs.setInt(
          'mqtt_port', int.tryParse(_mqttPortController.text.trim()) ?? 1883);
      await prefs.setString('mqtt_user', _mqttUserController.text.trim());
      await prefs.setString('mqtt_pass', _mqttPassController.text);
      await prefs.setString('mqtt_topic', _mqttTopicController.text.trim());
    } catch (_) {}
  }

  Future<void> _saveAutoPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_enabled', _autoControlEnabled);
      await prefs.setDouble(
          'auto_on', double.tryParse(_autoOnController.text.trim()) ?? 28.0);
      await prefs.setDouble(
          'auto_off', double.tryParse(_autoOffController.text.trim()) ?? 25.0);
    } catch (_) {}
  }

  Future<void> _saveDefaultBrand() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('default_remote_brand', _defaultRemoteBrand);
    } catch (_) {}
  }

  Future<void> _saveConfigBrand() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('config_remote_brand', _configBrand);
    } catch (_) {}
  }

  /// On ESP32 hardware, Base Wi-Fi Station MAC = Bluetooth Classic MAC - 2.
  String _getWifiMac(String btMac) {
    if (_actualDeviceMac != null && _actualDeviceMac!.isNotEmpty) {
      return _actualDeviceMac!;
    }
    final clean = btMac.replaceAll(':', '').replaceAll('-', '').trim();
    if (clean.length != 12) return btMac;
    try {
      final lastByte = int.parse(clean.substring(10, 12), radix: 16);
      final wifiLastByte = (lastByte - 2) & 0xFF;
      final hex = wifiLastByte.toRadixString(16).padLeft(2, '0').toUpperCase();
      final baseHex = clean.substring(0, 10).toUpperCase() + hex;
      final parts = <String>[];
      for (int i = 0; i < 12; i += 2) {
        parts.add(baseHex.substring(i, i + 2));
      }
      return parts.join(':');
    } catch (_) {
      return btMac;
    }
  }

  Future<void> _saveLocalDeviceToCache(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = prefs.getString('local_provisioned_devices') ?? '[]';
      final List<dynamic> list = jsonDecode(listJson);

      final wifiMac = _getWifiMac(_device.address);
      final mac = wifiMac.replaceAll(':', '').toUpperCase();
      final shortId = mac.length >= 8 ? mac.substring(mac.length - 8) : mac;

      final existingIndex = list.indexWhere((element) =>
          element['mac'] == wifiMac ||
          element['mac'] == _device.address ||
          element['id'] == mac);

      final deviceMap = {
        'id': mac,
        'name': _device.name ?? 'Smart AC Controller',
        'mac': wifiMac,
        'btMac': _device.address,
        'shortId': shortId,
        'systemId': 'local_system',
        'ip': ip,
        'ssid': _ssidController.text.trim(),
        'onOffStatus': {
          'isOnline': true,
          'acStatus': 'OFF',
          'temperature': 24.0,
          'humidity': 50.0,
        }
      };

      if (existingIndex != -1) {
        list[existingIndex] = deviceMap;
      } else {
        list.add(deviceMap);
      }

      await prefs.setString('local_provisioned_devices', jsonEncode(list));
      debugPrint('💾 Saved configured device locally (Wi-Fi MAC: $wifiMac, BT MAC: ${_device.address}, shortId: $shortId): $deviceMap');
    } catch (e) {
      debugPrint('⚠️ Error saving local device cache: $e');
    }
  }

  void _showWifiConnectedDialog(String ip) {
    if (!mounted || _hasNavigatedAway) return;
    _hideWifiLoadingDialog();
    _saveWifiStatus(true, ip: ip);
    _saveLocalDeviceToCache(ip);
    _routeToSystemPage();
  }

  void _startBluetoothStateMonitor() {
    _updateBluetoothState();
    _bluetoothStateTimer?.cancel();
    _bluetoothStateTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _updateBluetoothState(),
    );
  }

  Future<void> _updateBluetoothState() async {
    try {
      final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
      if (!mounted) return;
      setState(() => _isBluetoothOn = isEnabled ?? false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBluetoothOn = false);
    }
  }

  void _recordDisconnect(String reason) {
    if (_hasNavigatedAway || !mounted) return;

    if (_connection.isConnected) {
      _log("BT event: $reason (still connected, ignoring disconnect)");
      return;
    }

    final time = DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now());
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isYellowLedOn = false;
        _lastDisconnectReason = reason;
        _lastDisconnectTime = time;
      });
    }
    _log("BT disconnected: $reason @ $time");

    // If device disconnected Bluetooth while connecting WiFi or when WiFi credentials were sent (standard ESP32 radio switch)
    if (_isConnectingWifi || _isWifiConnected) {
      _hideWifiLoadingDialog();
      if (mounted) {
        setState(() {
          _isConnectingWifi = false;
          _isWifiConnected = true;
          _wifiStatus = "WiFi credentials applied. Device active on WiFi ✅";
          _isGreenLedOn = true;
          _showMqttDropdown = true;
        });
      }
      _saveWifiStatus(true, ip: _wifiIP);
      _saveLocalDeviceToCache(_wifiIP);
      _routeToSystemPage();
      return;
    }

    // Only show reconnect dialog if user is idle and NOT in WiFi configuration
    if (!_isWifiConnected && !_hasNavigatedAway && mounted) {
      _showReconnectDialog();
    }
  }

  String _disconnectHint(String reason) {
    final r = reason.toLowerCase();
    if (r.contains("remote")) {
      return "Device closed the link (idle timeout or reboot)";
    }
    if (r.contains("error")) {
      return "Bluetooth stack error (signal or OS)";
    }
    return "Unknown cause";
  }

  String _disconnectDisplayReason(String reason) {
    if (reason.toLowerCase().contains("remote")) {
      return "Device closed the connection";
    }
    return reason;
  }

  // ===================== BT Rx =====================
  void _listenBluetooth() {
    _btStreamSub?.cancel();
    _btStreamSub = _connection.input?.listen((Uint8List data) {
      if (!mounted || _hasNavigatedAway) return;
      final chunk = String.fromCharCodes(data);
      _log("RX: $chunk");
      _incomingBuffer += chunk;

      String line;
      while ((line = _extractLine()) != "") {
        if (!mounted || _hasNavigatedAway) return;
        _handleLine(line.trim());
      }
    }, onError: (error) {
      if (!mounted || _hasNavigatedAway) return;
      _recordDisconnect("Error: $error");
    });

    _btStreamSub?.onDone(() {
      if (!mounted || _hasNavigatedAway) return;
      if (_incomingBuffer.trim().isNotEmpty) {
        _handleLine(_incomingBuffer.trim());
        _incomingBuffer = "";
      }
      _recordDisconnect("Disconnected by remote");
    });
  }

  String _extractLine() {
    if (_incomingBuffer.isEmpty) return "";
    final nIdx = _incomingBuffer.indexOf('\n');
    final rIdx = _incomingBuffer.indexOf('\r');

    if (nIdx == -1 && rIdx == -1) return "";
    int idx;
    if (nIdx == -1) {
      idx = rIdx;
    } else if (rIdx == -1) {
      idx = nIdx;
    } else {
      idx = (nIdx < rIdx) ? nIdx : rIdx;
    }

    final line = _incomingBuffer.substring(0, idx);
    int cut = idx + 1;
    if (idx + 1 < _incomingBuffer.length) {
      final a = _incomingBuffer[idx];
      final b = _incomingBuffer[idx + 1];
      if (a == '\r' && b == '\n') cut = idx + 2;
    }
    _incomingBuffer = _incomingBuffer.substring(cut);
    return line;
  }

  void _handleLine(String line) {
    if (!mounted || line.isEmpty) return;

    // Device MAC response (if reported directly by ESP32 firmware)
    if (line.startsWith("MAC:") ||
        line.startsWith("WIFI_MAC:") ||
        line.startsWith("DEVICE_MAC:")) {
      final reported = line.split(":").sublist(1).join(":").trim();
      if (reported.isNotEmpty) {
        _actualDeviceMac = reported;
        debugPrint("📌 Received actual Wi-Fi MAC from ESP32: $_actualDeviceMac");
      }
      return;
    }

    // WiFi
    if (line.startsWith("WIFI_CONNECTED:")) {
      final payload = line.replaceFirst("WIFI_CONNECTED:", "").trim();
      String ip = payload;
      if (payload.contains(",")) {
        final parts = payload.split(",");
        ip = parts[0].trim();
        if (parts.length > 1 && parts[1].contains(":")) {
          _actualDeviceMac = parts[1].trim();
        }
      }
      setState(() {
        _isWifiConnected = true;
        _isConnectingWifi = false;
        _wifiIP = ip;
        _wifiStatus = "WiFi connected: $ip";
        _isGreenLedOn = true;
        _showMqttDropdown = true;
      });
      _saveWifiStatus(true, ip: ip);
      _saveLocalDeviceToCache(ip);
      _hideWifiLoadingDialog();
      _sendMqttSettingsToDevice(connect: true);
      _showWifiConnectedDialog(ip);
      return;
    }
    if (line.toLowerCase().contains("wifi_failed") ||
        line.toLowerCase().contains("wifi failed")) {
      _hideWifiLoadingDialog();

      setState(() {
        _isWifiConnected = false;
        _isConnectingWifi = false;
        _wifiIP = "";
        _wifiStatus = "WiFi connection failed ❌";
        _isGreenLedOn = false;

        _isMqttConnected = false;
        _mqttStatus = "MQTT not connected";
      });
      _saveWifiStatus(false, ip: "");
      _showSnack(
        "WiFi connection failed ❌",
        _red,
      );
      return;
    }

    // Status check response (custom handling for initial sync)
    if (line.contains("WIFI_STATUS:") || line.contains("WIFI_STATE:")) {
      final status = line.split(":").last.trim();
      final parts = status.split(",");
      final isConn = parts[0] == "1" ||
          parts[0].toLowerCase() == "true" ||
          parts[0].toLowerCase() == "connected";
      final ip = parts.length > 1 ? parts[1] : "";

      if (isConn) _hideWifiLoadingDialog();
      setState(() {
        _isWifiConnected = isConn;
        _wifiIP = ip;
        _wifiStatus = isConn ? "WiFi connected: $ip" : "WiFi not connected";
        _isGreenLedOn = isConn;
        if (isConn) _isConnectingWifi = false;
      });
      _saveWifiStatus(isConn, ip: ip);
      if (isConn) {
        _saveLocalDeviceToCache(ip);
        _showWifiConnectedDialog(ip);
      }
      return;
    }

    // Generic "connected" check if device uses non-standard format or prefixes
    if (line.toLowerCase().contains("wifi connected") ||
        line.toLowerCase().contains("connected to wifi") ||
        line.toLowerCase().contains("status_online") ||
        line.toLowerCase().contains("wifi_connected")) {
      _hideWifiLoadingDialog();
      setState(() {
        _isWifiConnected = true;
        _isConnectingWifi = false;
        _wifiStatus = "WiFi Connected ✅";
        _isGreenLedOn = true;
        _showMqttDropdown = true;

        // If the line contains an IP (e.g. "WIFI_CONNECTED:192.168.1.5")
        if (line.contains(":")) {
          final parts = line.split(":");
          for (var part in parts) {
            final trimmed = part.trim();
            if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')
                .hasMatch(trimmed)) {
              _wifiIP = trimmed;
              _wifiStatus = "WiFi Connected: $trimmed";
              break;
            }
          }
        }
      });
      _saveWifiStatus(true, ip: _wifiIP);
      _saveLocalDeviceToCache(_wifiIP);
      _showWifiConnectedDialog(_wifiIP);
      return;
    }

    // MQTT
    if (line.startsWith("MQTT_CONNECTED") || line.contains("STATUS_ONLINE")) {
      setState(() {
        _isMqttConnected = true;
        _mqttStatus = "MQTT connected ✅";
      });
      return;
    }
    if (line.startsWith("MQTT_FAILED")) {
      setState(() {
        _isMqttConnected = false;
        _mqttStatus = "MQTT failed ❌";
      });
      return;
    }
    if (line.startsWith("MQTT_PUB_OK")) {
      setState(() => _mqttStatus = "MQTT published ✅");
      return;
    }

    // Temp/Time
    if (line.startsWith("TEMP:")) {
      setState(() => _temperatureText = line.replaceFirst("TEMP:", "").trim());
      return;
    }
    if (line.startsWith("TIME:")) {
      final v = line.replaceFirst("TIME:", "").trim();
      if (v.isNotEmpty) setState(() => _deviceTimeText = v);
      return;
    }

    // ====== Remote config progress from ESP32 ======
    if (line.startsWith("APP_CFG:WAIT:")) {
      // example: APP_CFG:WAIT:POWER_ON
      final k = line.replaceFirst("APP_CFG:WAIT:", "").trim();
      setState(() {
        _waitingForIr = true;
        _cfgStatus = "Waiting IR for $k ...";
        _learningProgress = 0;
      });
      return;
    }
    if (line.startsWith("IR_LEARNING_PROGRESS:")) {
      final p =
          int.tryParse(line.replaceFirst("IR_LEARNING_PROGRESS:", "").trim()) ??
              0;
      setState(() {
        _learningProgress = p.clamp(0, 100);
      });
      return;
    }
    if (line.startsWith("APP_CFG:DONE:")) {
      // example: APP_CFG:DONE:POWER_ON
      final k = line.replaceFirst("APP_CFG:DONE:", "").trim();
      setState(() {
        _waitingForIr = false;
        _cfgStatus = "Captured: $k ✅";
        _learningProgress = 100;
      });

      // move to next step (auto)
      _nextConfigStep();
      return;
    }

    // Remote saved
    if (line.startsWith("REMOTE_SAVED:")) {
      final b = line.replaceFirst("REMOTE_SAVED:", "").trim();
      setState(() {
        _cfgStatus = "Remote Saved: $b ✅";
        _configMode = false;
        _waitingForIr = false;
        _cfgStepIndex = 0;
      });
      _showSnack("Remote saved: $b", _green);
      return;
    }

    // IR_SENT confirmation (default remote)
    if (line.startsWith("IR_SENT")) {
      _showSnack("IR sent ✅", _green);
      return;
    }

    if (line.startsWith("ERR:")) {
      // if timeout during learning, stop waiting
      if (line.contains("TIMEOUT")) {
        setState(() {
          _waitingForIr = false;
          _cfgStatus = "Timeout ❌ Try again";
          _learningProgress = 0;
        });
      }
      _log("DEVICE ERROR: $line");
      return;
    }
  }

  // ===================== Commands =====================
  Future<void> _sendCommand(String cmd) async {
    if (!mounted || _hasNavigatedAway) return;
    if (!_connection.isConnected) {
      if (mounted && !_hasNavigatedAway) {
        _showSnack("Bluetooth not connected", _red);
      }
      return;
    }
    try {
      _log("TX: $cmd");
      _connection.output.add(Uint8List.fromList(
          utf8.encode("$cmd\n"))); // Using standard \n to avoid corrupting passwords with \r
      await _connection.output.allSent;
    } catch (e) {
      if (mounted && !_hasNavigatedAway) {
        _showSnack("Send failed: $e", _red);
      }
    }
  }

  // ===================== WiFi & MQTT Setup Dialog =====================
  void _showWifiSetupDialog() {
    // Check if Bluetooth is connected
    if (!_isConnected) {
      _showSnack("Bluetooth not connected. Please connect first.", _red);
      return;
    }

    bool wifiPasswordVisible = false;
    bool mqttPasswordVisible = false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.settings_suggest_rounded, color: _themeGreen, size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Device Configuration",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Section 1: WiFi Network ──
                  Row(
                    children: const [
                      Icon(Icons.wifi, color: _themeGreen, size: 18),
                      SizedBox(width: 8),
                      Text(
                        "WiFi Network",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ssidController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "WiFi SSID",
                      hintText: "Enter WiFi Network Name",
                      hintStyle: TextStyle(color: Colors.white30),
                      labelStyle: TextStyle(color: Colors.white70),
                      prefixIcon: Icon(Icons.wifi_outlined, color: Colors.white54, size: 20),
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _themeGreen)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _wifiPasswordController,
                    obscureText: !wifiPasswordVisible,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "WiFi Password",
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.white54, size: 20),
                      border: const OutlineInputBorder(),
                      enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38)),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: _themeGreen)),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(
                          wifiPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.white70,
                          size: 20,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            wifiPasswordVisible = !wifiPasswordVisible;
                          });
                        },
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(color: Colors.white24),
                  ),

                  // ── Section 2: MQTT Broker Settings (Topic, Port, IP, User, Password) ──
                  Row(
                    children: const [
                      Icon(Icons.cloud_outlined, color: Colors.lightBlueAccent, size: 18),
                      SizedBox(width: 8),
                      Text(
                        "MQTT Configuration",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      "Format: MQTT:topic=${_mqttTopicController.text.trim()},port=${_mqttPortController.text.trim()},ip=${_mqttHostController.text.trim()},user=${_mqttUserController.text.trim()},password=***",
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // topic
                  TextField(
                    controller: _mqttTopicController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "topic",
                      hintText: "",
                      hintStyle: TextStyle(color: Colors.white30),
                      labelStyle: TextStyle(color: Colors.white70),
                      prefixIcon: Icon(Icons.tag_rounded, color: Colors.white54, size: 20),
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.lightBlueAccent)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // port & ip
                  Row(
                    children: [
                      // port
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _mqttPortController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: "port",
                            hintText: "1883",
                            hintStyle: TextStyle(color: Colors.white30),
                            labelStyle: TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white38)),
                            focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.lightBlueAccent)),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // ip
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _mqttHostController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: "ip",
                            hintText: "e.g. 192.168.1.100",
                            hintStyle: TextStyle(color: Colors.white30),
                            labelStyle: TextStyle(color: Colors.white70),
                            prefixIcon: Icon(Icons.dns_outlined, color: Colors.white54, size: 20),
                            border: OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white38)),
                            focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.lightBlueAccent)),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // user
                  TextField(
                    controller: _mqttUserController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "user",
                      hintText: "e.g. mqtt_user",
                      hintStyle: TextStyle(color: Colors.white30),
                      labelStyle: TextStyle(color: Colors.white70),
                      prefixIcon: Icon(Icons.person_outline, color: Colors.white54, size: 20),
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.lightBlueAccent)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // password
                  TextField(
                    controller: _mqttPassController,
                    obscureText: !mqttPasswordVisible,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "password",
                      hintText: "e.g. mqtt_password",
                      hintStyle: const TextStyle(color: Colors.white30),
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.key_outlined, color: Colors.white54, size: 20),
                      border: const OutlineInputBorder(),
                      enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38)),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.lightBlueAccent)),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(
                          mqttPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.white70,
                          size: 20,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            mqttPasswordVisible = !mqttPasswordVisible;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _themeGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text("Save & Connect", style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(context);
                _connectWifi();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectWifi() async {
    final ssid = _ssidController.text.trim();
    final pass = _wifiPasswordController.text.trim();
    if (ssid.isEmpty || pass.isEmpty) {
      _showSnack("Enter SSID and password", _red);
      return;
    }

    // Save primary credentials to local storage
    await LocalCacheService.saveWifiCredentials(ssid, pass);

    // Save MQTT preferences
    await _saveMqttPrefs();

    if (mounted) {
      setState(() {
        _isWifiConnected = false;
        _wifiStatus = "Configuring WiFi & MQTT...";
        _isConnectingWifi = true;
      });
    }

    // Pre-configure MQTT on device over Bluetooth in requested format: MQTT:topic=...,port=...,ip=...,user=...,password=...
    final host = _mqttHostController.text.trim();
    final port = int.tryParse(_mqttPortController.text.trim()) ?? 1883;
    final user = _mqttUserController.text.trim();
    final mPass = _mqttPassController.text.trim();
    final topic = _mqttTopicController.text.trim();

    if (host.isNotEmpty && topic.isNotEmpty) {
      // Dynamic in-memory cache update
      MqttConfigService.updateCachedCredentials(
        topic: topic,
        username: user,
        password: mPass,
        host: host,
        port: port,
      );

      final combinedMqtt =
          "MQTT:topic=$topic,port=$port,ip=$host,user=$user,password=$mPass";
      debugPrint("📡 Pre-configuring MQTT settings on device: $combinedMqtt");
      await _sendCommand(combinedMqtt);
      await Future.delayed(const Duration(milliseconds: 200));

      // Also send individual commands as fallback for older firmware support
      await _sendCommand("MQTT_HOST:$host");
      await Future.delayed(const Duration(milliseconds: 100));
      await _sendCommand("MQTT_PORT:$port");
      await Future.delayed(const Duration(milliseconds: 100));
      await _sendCommand("MQTT_USER:$user");
      await Future.delayed(const Duration(milliseconds: 100));
      await _sendCommand("MQTT_PASS:$mPass");
      await Future.delayed(const Duration(milliseconds: 100));
      await _sendCommand("MQTT_TOPIC:$topic");
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _showWifiLoadingDialog();

    // Send primary WiFi credentials (clean without trailing \r)
    await _sendCommand("WIFI:$ssid,$pass");

    // Optional follow-up connect trigger if device stays connected
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted && !_hasNavigatedAway && _connection.isConnected && _isConnectingWifi) {
      await _sendCommand("WIFI_CONNECT");
    }

    // Automatically route directly to AC Control page once credentials are sent
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && !_hasNavigatedAway) {
        _hideWifiLoadingDialog();
        if (mounted) {
          setState(() {
            _isConnectingWifi = false;
            _isWifiConnected = true;
            _wifiStatus = "WiFi credentials applied. Device active on WiFi ✅";
          });
        }
        _saveWifiStatus(true, ip: _wifiIP);
        _saveLocalDeviceToCache(_wifiIP);
        _routeToSystemPage();
      }
    });
  }

  // ===================== MQTT =====================
  Future<void> _sendMqttSettingsToDevice({bool connect = false}) async {
    if (!mounted || _hasNavigatedAway || !_isWifiConnected) return;

    final host = _mqttHostController.text.trim();
    final port = int.tryParse(_mqttPortController.text.trim()) ?? 1883;
    final user = _mqttUserController.text.trim();
    final pass = _mqttPassController.text;
    final topic = _mqttTopicController.text.trim();

    if (host.isEmpty || topic.isEmpty) return;

    await _saveMqttPrefs();

    MqttConfigService.updateCachedCredentials(
      topic: topic,
      username: user,
      password: pass,
      host: host,
      port: port,
    );

    final combinedMqtt =
        "MQTT:topic=$topic,port=$port,ip=$host,user=$user,password=$pass";
    debugPrint("📡 Sending MQTT settings to device: $combinedMqtt");
    await _sendCommand(combinedMqtt);
    await Future.delayed(const Duration(milliseconds: 200));

    await _sendCommand("MQTT_HOST:$host");
    await Future.delayed(const Duration(milliseconds: 100));
    await _sendCommand("MQTT_PORT:$port");
    await Future.delayed(const Duration(milliseconds: 100));
    await _sendCommand("MQTT_USER:$user");
    await Future.delayed(const Duration(milliseconds: 100));
    await _sendCommand("MQTT_PASS:$pass");
    await Future.delayed(const Duration(milliseconds: 100));
    await _sendCommand("MQTT_TOPIC:$topic");

    if (connect && mounted && !_hasNavigatedAway) {
      await Future.delayed(const Duration(milliseconds: 150));
      await _sendCommand("MQTT_CONNECT");
    }
  }

  // ===================== Auto control =====================
  Future<void> _sendAutoSetpointsToDevice() async {
    final onV = double.tryParse(_autoOnController.text.trim());
    final offV = double.tryParse(_autoOffController.text.trim());
    if (onV == null || offV == null) {
      _showSnack("Enter valid setpoints", _red);
      return;
    }
    await _saveAutoPrefs();

    if (_autoControlEnabled) {
      await _sendCommand(
          "AUTO_CFG:${onV.toStringAsFixed(1)},${offV.toStringAsFixed(1)},1");
      _showSnack("Auto enabled ✅", _green);
    } else {
      await _sendCommand("AUTO_DISABLE");
      _showSnack("Auto disabled", _orange);
    }
  }

  // ===================== Brand Dropdown Helpers =====================
  List<String> _brandDropdownItems() {
    final combined = <String>[...kIndianAcBrands];
    final seen = <String>{};
    final out = <String>[];

    for (final b in combined) {
      final name = b.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (seen.add(key)) out.add(name);
    }

    // keep Samsung always present
    if (!out.any((x) => x.toLowerCase() == "samsung")) out.insert(0, "Samsung");
    return out;
  }

  // ===================== DEFAULT REMOTE dropdown actions =====================
  Future<void> _setDefaultBrandOnDevice(String brand) async {
    final clean = brand.trim();
    if (clean.isEmpty) return;

    setState(() => _defaultRemoteBrand = clean);
    await _saveDefaultBrand();

    // set brand for sending
    await _sendCommand("BRAND:$clean");
  }

  Future<void> _sendDefaultRemoteKey(String key) async {
    // will use:
    // 1) spiffs learned raw for current brand
    // 2) hardcoded raw fallback
    // 3) protocol fallback
    await _sendCommand("SEND:$key");
  }

  // ===================== REMOTE CONFIG dropdown actions =====================
  Future<void> _setConfigBrandOnDevice(String brand) async {
    final clean = brand.trim();
    if (clean.isEmpty) return;

    setState(() => _configBrand = clean);
    await _saveConfigBrand();

    // only set brand; config starts when user clicks START CONFIG
    await _sendCommand("BRAND:$clean");
  }

  Future<void> _startConfigMode() async {
    // IMPORTANT: Your firmware needs START_CONFIG first, then BRAND, then CONFIG:key
    await _sendCommand("START_CONFIG");
    await _sendCommand("BRAND:$_configBrand");

    setState(() {
      _configMode = true;
      _cfgStepIndex = 0;
      _waitingForIr = false;
      _learningProgress = 0;
      _cfgStatus = "Config mode started ✅";
    });

    // start first step automatically
    await _triggerCurrentKeyConfig();
  }

  Future<void> _triggerCurrentKeyConfig() async {
    if (!_configMode) return;
    if (_cfgStepIndex < 0 || _cfgStepIndex >= _cfgKeys.length) return;

    final key = _cfgKeys[_cfgStepIndex];
    setState(() {
      _waitingForIr = true;
      _learningProgress = 0;
      _cfgStatus = "Requesting IR for $key ...";
    });

    await _sendCommand("CONFIG:$key");
  }

  void _nextConfigStep() {
    if (!_configMode) return;

    if (_cfgStepIndex < _cfgKeys.length - 1) {
      setState(() {
        _cfgStepIndex++;
        _waitingForIr = false;
        _learningProgress = 0;
      });
      // ask next key
      _triggerCurrentKeyConfig();
    } else {
      // all done -> show save dialog
      setState(() {
        _waitingForIr = false;
        _cfgStatus = "All keys captured ✅. Save Remote now.";
      });
      _showSaveRemoteDialog();
    }
  }

  void _showSaveRemoteDialog() {
    _saveBrandController.text = _configBrand;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Save Remote"),
        content: TextField(
          controller: _saveBrandController,
          decoration: const InputDecoration(
            labelText: "Brand name to save",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveRemoteToDevice();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRemoteToDevice() async {
    final name = _saveBrandController.text.trim();
    if (name.isEmpty) {
      _showSnack("Enter brand name", _red);
      return;
    }
    await _sendCommand("SAVE_REMOTE:$name");
  }

  // ===================== Scheduling =====================
  Future<void> _pickTime(
      TextEditingController controller, String cmdPrefix) async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: now,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF6CC042),
            onPrimary: Colors.white,
            surface: Color(0xFF131122),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF131122),
          timePickerTheme: const TimePickerThemeData(
            backgroundColor: Color(0xFF131122),
            dialBackgroundColor: Color(0xFF1B172E),
            dialHandColor: Color(0xFF6CC042),
            dialTextColor: Colors.white,
            entryModeIconColor: Colors.white,
            hourMinuteColor: Color(0xFF1B172E),
            hourMinuteTextColor: Colors.white,
            dayPeriodColor: Color(0xFF1B172E),
            dayPeriodTextColor: Colors.white,
            dayPeriodBorderSide: BorderSide.none,
            helpTextStyle: TextStyle(color: Colors.white),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    final timeStr = "$hh:$mm";
    setState(() => controller.text = timeStr);
    await _sendCommand("$cmdPrefix:$timeStr");
  }

  // ===================== UI =====================
  Widget _buildStatusCard() {
    final title = _isConnected
        ? "Connected: ${_device.name ?? 'Device'}"
        : "Bluetooth not connected";
    return Card(
      color: _cardBackground,
      elevation: 2,
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
                _isConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: _isConnected ? _blue : _red),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                    "Mobile Bluetooth: ${_isBluetoothOn ? 'ON' : 'OFF'}",
                    style: TextStyle(
                        fontSize: 12, color: _isBluetoothOn ? _green : _red),
                  ),
                  const Text(
                    "Status: Active",
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(children: [
                  Icon(Icons.circle,
                      size: 12,
                      color: _isYellowLedOn ? Colors.yellow : Colors.grey),
                  const SizedBox(width: 4),
                  const Text("BT", style: TextStyle(color: Colors.white)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.circle,
                      size: 12,
                      color: _isGreenLedOn ? _themeGreen : Colors.grey),
                  const SizedBox(width: 4),
                  const Text("WiFi", style: TextStyle(color: Colors.white)),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminal() {
    if (!_showTerminal) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => setState(() => _showTerminal = true),
          icon: const Icon(Icons.developer_mode, color: Colors.white70),
          label:
              const Text("Show Logs", style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Card(
      color: _cardBackground,
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                    child: Text("Terminal / Logs",
                        style: TextStyle(
                            fontWeight: FontWeight.w900, color: Colors.white))),
                IconButton(
                    onPressed: () => setState(() => _showTerminal = false),
                    icon: const Icon(Icons.close, color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 160,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.black, borderRadius: BorderRadius.circular(12)),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  _terminalController.text,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      color: _themeGreen,
                      fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== Helpers =====================
  void _log(String msg) {
    if (!mounted || _hasNavigatedAway) return;
    try {
      final t = DateFormat("HH:mm:ss").format(DateTime.now());
      _terminalController.text += "[$t] $msg\n";

      // Throttle UI updates for logs if they come in too fast
      if (!_needsUpdate) {
        _needsUpdate = true;
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && !_hasNavigatedAway && _needsUpdate) {
            setState(() {
              _needsUpdate = false;
            });
          }
        });
      }
    } catch (_) {}
  }

  void _showSnack(String msg, Color c) {
    if (!mounted || _hasNavigatedAway) return;
    try {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), backgroundColor: c));
    } catch (_) {}
  }

  void _showWifiLoadingDialog() {
    // Modal dialog removed per user request: "remove the dialoogue box wifii conncte wifi to route ac control page only"
    // Status is dynamically shown in the UI without blocking dialogues
  }

  void _hideWifiLoadingDialog() {
    if (mounted && !_hasNavigatedAway) {
      setState(() => _isConnectingWifi = false);
    }
  }

  void _showReconnectDialog() {
    if (!mounted || _hasNavigatedAway || _isWifiConnected || _isConnectingWifi) {
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: _cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.bluetooth_disabled, color: _red, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Bluetooth Disconnected",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Connection to ${_device.name ?? 'device'} lost.\nReason: ${_disconnectDisplayReason(_lastDisconnectReason)}\nTime: $_lastDisconnectTime",
                style: const TextStyle(fontSize: 15, color: Colors.white70),
              ),
              const SizedBox(height: 4),
              Text(
                "Hint: ${_disconnectHint(_lastDisconnectReason)}",
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white54,
                    fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _themeGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _themeGreen.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white70, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Device is still on. Ready to reconnect.",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                try {
                  Navigator.pop(context);
                } catch (_) {}
                _disconnectBluetooth();
              },
              child: const Text(
                "Go Back",
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _themeGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onPressed: () {
                try {
                  Navigator.pop(context);
                } catch (_) {}
                _attemptReconnect();
              },
              icon: const Icon(Icons.bluetooth_connected, size: 20),
              label: const Text(
                "Reconnect",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  Future<void> _attemptReconnect() async {
    _showLoadingDialog("Reconnecting...");

    try {
      try {
        await _connection.close();
      } catch (_) {}
      final connection = await BluetoothConnection.toAddress(_device.address);
      if (connection.isConnected && mounted && !_hasNavigatedAway) {
        _hideLoadingDialog();
        setState(() {
          _connection = connection;
          _isConnected = true;
          _isYellowLedOn = true;
        });
        _listenBluetooth();
        _showSnack("Reconnected successfully ✅", _green);
      }
    } catch (e) {
      if (mounted && !_hasNavigatedAway) {
        _hideLoadingDialog();
        _showSnack("Failed to reconnect. Try again.", _red);
      }
    }
  }

  void _showLoadingDialog(String message) {
    if (!mounted || _hasNavigatedAway) return;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: _cardBackground,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
                BoxShadow(
                  color: _themeGreen.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_themeGreen),
                strokeWidth: 4.5,
                strokeCap: StrokeCap.round,
              ),
            ),
          ),
        ),
      );
    } catch (_) {}
  }

  void _hideLoadingDialog() {
    if (mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
    }
  }

  void _disconnectBluetooth() {
    if (_hasNavigatedAway) return;
    _hasNavigatedAway = true;
    _bluetoothStateTimer?.cancel();
    _btStreamSub?.cancel();
    _btStreamSub = null;

    try {
      if (_connection.isConnected) _connection.close();
    } catch (_) {}

    if (!mounted) return;
    try {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const BluetoothScannerPage()),
        (_) => false,
      );
    } catch (_) {}
  }

  void _routeToSystemPage() {
    if (_hasNavigatedAway) return;
    _hasNavigatedAway = true;
    _hideWifiLoadingDialog();
    _bluetoothStateTimer?.cancel();
    _btStreamSub?.cancel();
    _btStreamSub = null;

    try {
      if (_connection.isConnected) {
        _connection.close();
      }
    } catch (_) {}

    if (!mounted) return;
    try {
      final wifiMac = _getWifiMac(_device.address);
      final mac = wifiMac.replaceAll(':', '').toUpperCase();
      final shortId = mac.length >= 8 ? mac.substring(mac.length - 8) : mac;
      final devName = _device.name ?? 'Smart AC Controller';

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => ACControlPage(
            deviceName: devName,
            systemId: mac,
            systemShortId: shortId,
          ),
        ),
        (_) => false,
      );
    } catch (_) {}
  }

  // ===================== Build =====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text("Configuration",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        backgroundColor: _themeGreen,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: _disconnectBluetooth),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            RepaintBoundary(child: _buildStatusCard()),
            RepaintBoundary(
                child: WifiSectionWidget(
              themeGreen: _themeGreen,
              isWifiConnected: _isWifiConnected,
              wifiStatus: _wifiStatus,
              wifiIP: _wifiIP,
              onShowWifiSetup: _showWifiSetupDialog,
              showMqttDropdown: _showMqttDropdown,
              onToggleMqttDropdown: () =>
                  setState(() => _showMqttDropdown = !_showMqttDropdown),
              mqttStatus: _mqttStatus,
              isMqttConnected: _isMqttConnected,
              mqttHostController: _mqttHostController,
              mqttPortController: _mqttPortController,
              mqttTopicController: _mqttTopicController,
              mqttUserController: _mqttUserController,
              mqttPassController: _mqttPassController,
              onSendMqttSettings: () =>
                  _sendMqttSettingsToDevice(connect: false),
              onConnectMqtt: () => _sendMqttSettingsToDevice(connect: true),
              autoControlEnabled: _autoControlEnabled,
              onAutoControlChanged: (v) async {
                setState(() => _autoControlEnabled = v);
                await _saveAutoPrefs();
                await _sendAutoSetpointsToDevice();
              },
              autoOnController: _autoOnController,
              autoOffController: _autoOffController,
              onApplyAutoConfig: _sendAutoSetpointsToDevice,
            )),
            // RepaintBoundary(child: _buildTerminal()), // Hidden as requested
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
