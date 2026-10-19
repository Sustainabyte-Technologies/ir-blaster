import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'dart:async';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:ir_blaster_ac/widgets/trends_table.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/core/services/mqtt_config_service.dart';
import 'package:ir_blaster_ac/screens/ac_app/schedule_calendar_page.dart';

class DeviceDetailPage extends StatefulWidget {
  final String deviceName;
  final String systemId;
  final String systemShortId;

  const DeviceDetailPage({
    Key? key,
    required this.deviceName,
    required this.systemId,
    required this.systemShortId,
  }) : super(key: key);

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // UI State
  double _setTemperature = 24.0; // Fixed static value
  double _actualTemperature = 0.0;
  bool _isOnline = false; // Tracks WIFI/Online status (initialized to inactive)
  ScaffoldMessengerState? _messenger;
  int _humidity = 0;
  String _scheduleOn1 = '--:--';
  String _scheduleOff1 = '--:--';
  String _scheduleOn2 = '--:--';
  String _scheduleOff2 = '--:--';
  String _scheduleOn3 = '--:--';
  String _scheduleOff3 = '--:--';
  String _scheduleOn4 = '--:--';
  String _scheduleOff4 = '--:--';
  String _scheduleOn5 = '--:--';
  String _scheduleOff5 = '--:--';
  String _scheduleOn6 = '--:--';
  String _scheduleOff6 = '--:--';
  String _lunchOn = '--:--';
  String _lunchOff = '--:--';
  bool _isAuto = false;
  bool _isPowerOn = true; // Tracks the MQTT Power Status
  DateTime? _inactiveStartTime; // Track when device became inactive
  String _inactiveTimeString = 'N/A'; // Display string for inactive time
  String _lastMqttUpdateTime = 'Never'; // Tracks last MQTT message time
  String _savedSsid = ''; // Saved WiFi SSID
  final GlobalKey<TooltipState> _wifiTooltipKey = GlobalKey<TooltipState>();

  // Dynamic schedules list to support 6 schedules dynamically with intervals
  late final List<Map<String, String>> _dynamicSchedules = [
    {'on': _scheduleOn1, 'off': _scheduleOff1, 'interval': 'None'},
    {'on': _scheduleOn2, 'off': _scheduleOff2, 'interval': 'None'},
    {'on': _scheduleOn3, 'off': _scheduleOff3, 'interval': 'None'},
    {'on': _scheduleOn4, 'off': _scheduleOff4, 'interval': 'None'},
    {'on': _scheduleOn5, 'off': _scheduleOff5, 'interval': 'None'},
    {'on': _scheduleOn6, 'off': _scheduleOff6, 'interval': 'None'},
  ];

  void _syncDynamicSchedules() {
    if (_dynamicSchedules.isNotEmpty) {
      _dynamicSchedules[0]['on'] = _scheduleOn1;
      _dynamicSchedules[0]['off'] = _scheduleOff1;
    }
    if (_dynamicSchedules.length > 1) {
      _dynamicSchedules[1]['on'] = _scheduleOn2;
      _dynamicSchedules[1]['off'] = _scheduleOff2;
    }
    if (_dynamicSchedules.length > 2) {
      _dynamicSchedules[2]['on'] = _scheduleOn3;
      _dynamicSchedules[2]['off'] = _scheduleOff3;
    }
    if (_dynamicSchedules.length > 3) {
      _dynamicSchedules[3]['on'] = _scheduleOn4;
      _dynamicSchedules[3]['off'] = _scheduleOff4;
    }
    if (_dynamicSchedules.length > 4) {
      _dynamicSchedules[4]['on'] = _scheduleOn5;
      _dynamicSchedules[4]['off'] = _scheduleOff5;
    }
    if (_dynamicSchedules.length > 5) {
      _dynamicSchedules[5]['on'] = _scheduleOn6;
      _dynamicSchedules[5]['off'] = _scheduleOff6;
    }
  }

  // Chart & Log State
  final List<_ChartData> _tempHistory = [];
  final List<Map<String, dynamic>> _recentLogs = [];

  // Equipment State
  List<Map<String, dynamic>> _equipmentsData = [];
  List<String> _equipments = [];
  bool _isLoadingEquipments = true;
  bool _isTelemetryLoading = true;
  String _selectedEquipmentName = '';
  String _selectedEquipmentId = '';
  String _selectedEquipmentTypeId = '';
  String _selectedEquipmentShortId = '';
  String _deviceId = ''; // IMEI

  // Stream State
  StreamSubscription? _subscription;
  DateTime _lastUpdateTime = DateTime.now(); // For throttling UI updates
  DateTime _lastManualCommandTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isPowerCommandLock = false;
  DateTime _lastSetStateTime = DateTime.now(); // For throttling UI rebuilds

  // Animation State
  AnimationController? _pulseController;

  // Polling State
  Timer? _pollTimer;
  Timer? _inactiveTimeUpdateTimer; // Timer to update inactive time display
  Timer? _statusWatchdogTimer; // Timer to detect device disconnects
  MqttServerClient? _persistentMqttClient;
  String _subscribedDeviceId = '';
  DateTime _lastMessageReceivedTime =
      DateTime.now().subtract(const Duration(seconds: 20));
  bool _isAnalyzing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _selectedEquipmentName = widget.deviceName;
    _fetchEquipments();

    // Seed initial data for chart
    for (int i = 0; i < 10; i++) {
      _tempHistory.add(
        _ChartData(
          DateTime.now().subtract(Duration(minutes: 10 - i)),
          30 + math.Random().nextDouble() * 5,
        ),
      );
    }

    _setupPersistentMqtt();
    // WiFi status caching disabled to prevent stale data flickering
    // _loadCachedStatus();
    // _loadCachedEquipments(); // Disabled to prevent loading stale cached equipment list

    // Telemetry is no longer "loading" once we have the persistent connection active
    if (mounted) {
      setState(() => _isTelemetryLoading = false);
    }

    // Setup timer to update inactive time display every 10 seconds for performance
    _inactiveTimeUpdateTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && _inactiveStartTime != null) {
        _updateInactiveTimeString();
      }
    });

    // Efficient Watchdog: Periodically check if we haven't received a status JSON
    // 20-30 seconds: analyzing/checking state (still online)
    // > 30 seconds: confirmed offline/inactive
    _statusWatchdogTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        final elapsed = DateTime.now().difference(_lastMessageReceivedTime);

        if (elapsed > const Duration(seconds: 30)) {
          if (_isOnline || _isAnalyzing) {
            setState(() {
              _isOnline = false;
              _isAnalyzing = false;
              _inactiveStartTime = DateTime.now();
              debugPrint(
                  '⚠️ [Watchdog] No status JSON received for 30s. Setting WiFi to INACTIVE.');
            });
          }
        } else if (elapsed > const Duration(seconds: 20)) {
          if (!_isAnalyzing) {
            setState(() {
              _isAnalyzing = true;
              debugPrint(
                  '🔍 [Watchdog] No status JSON received for 20s. Setting WiFi to ANALYZING/CHECKING.');
            });
          }
        } else {
          if (!_isOnline || _isAnalyzing) {
            setState(() {
              _isOnline = true;
              _isAnalyzing = false;
              debugPrint('🟢 [Watchdog] Status JSON received. WiFi is ACTIVE.');
            });
          }
        }
      }
    });
    _loadSavedSsid();
  }

  Future<void> _loadSavedSsid() async {
    final creds = await LocalCacheService.getWifiCredentials();
    if (mounted) {
      setState(() {
        _savedSsid = creds['ssid'] ?? '';
      });
    }
  }

  Future<void> _loadCachedEquipments() async {
    // Disabled to guarantee only live data is used
    /*
    final cached = await LocalCacheService.getEquipmentList(widget.systemId);
    if (cached != null && mounted) {
      _applyEquipmentData(cached);
    }
    */
  }

  void _applyEquipmentData(List<dynamic> equipmentList) {
    if (!mounted) return;
    setState(() {
      try {
        _equipmentsData =
            equipmentList.map((e) => Map<String, dynamic>.from(e)).toList();
        _equipments = _equipmentsData
            .map((e) => e['name']?.toString() ?? 'Unknown')
            .toList();
        _isLoadingEquipments = false;

        if (_equipmentsData.isNotEmpty) {
          final initialIndex = _equipmentsData.indexWhere(
            (e) => e['name'] == widget.deviceName,
          );
          final targetIndex = initialIndex != -1 ? initialIndex : 0;
          final Map<String, dynamic> eData = _equipmentsData[targetIndex];

          _selectedEquipmentId = (eData['equipmentId'] ??
                      eData['EquipmentId'] ??
                      eData['id'] ??
                      eData['Id'])
                  ?.toString() ??
              '';
          _selectedEquipmentName =
              (eData['name'] ?? eData['Name'])?.toString() ?? '';
          _selectedEquipmentTypeId =
              (eData['equipmentTypeId'] ?? eData['EquipmentTypeId'])
                      ?.toString() ??
                  '';
          _selectedEquipmentShortId = (eData['shortId'] ??
                      eData['ShortId'] ??
                      eData['equipmentShortId'] ??
                      eData['SystemShortId'])
                  ?.toString() ??
              '';

          // Prioritize IMEI for MQTT communication as requested
          final imei = (eData['imei'] ?? eData['Imei'])?.toString() ?? '';
          _deviceId = imei.isNotEmpty
              ? imei
              : (_selectedEquipmentShortId.isNotEmpty
                  ? _selectedEquipmentShortId
                  : _selectedEquipmentId);

          debugPrint(
              '📡 [DeviceDetail] Active Device ID (Topic): $_deviceId (IMEI: $imei)');

          // Re-trigger MQTT setup with the new ID if it changed
          _setupPersistentMqtt();
        }
      } catch (e) {
        debugPrint('âš ï¸  Error mapping equipment data: $e');
      }
    });
  }

  Future<void> _loadCachedStatus() async {
    final cached =
        await LocalCacheService.getDeviceStatus(widget.systemShortId);
    if (cached != null && mounted) {
      final status = cached['status'];
      setState(() {
        if (status['temp'] != null)
          _actualTemperature = (status['temp'] as num).toDouble();
        if (status['hum'] != null) _humidity = (status['hum'] as num).toInt();
        if (status['power'] != null) _isPowerOn = status['power'] as bool;
        // WiFi Online status is no longer loaded from cache to ensure it always starts as INACTIVE
        // and only becomes ACTIVE when a fresh MQTT status JSON is received.
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeStream();
    _pulseController?.dispose();
    _pollTimer?.cancel();
    _inactiveTimeUpdateTimer?.cancel();
    _statusWatchdogTimer?.cancel();
    _persistentMqttClient?.disconnect();
    // Safely clear any active snackbars using the stored messenger reference
    _messenger?.clearSnackBars();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('📱 [Lifecycle] App State changed to: $state');
    if (state == AppLifecycleState.resumed) {
      debugPrint(
          '🔄 [Lifecycle] App resumed! Refreshing MQTT connection & fetching latest equipment data...');

      // Re-fetch the equipment data from the live HTTP API to get fresh configuration
      _fetchEquipments();

      // Verify/reconnect the MQTT connection silently in the background
      _setupPersistentMqtt();
    }
  }

  void _closeStream() {
    _subscription?.cancel();
    _subscription = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _showEquipmentSelectionPopup(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B172E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Grab handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Equipment',
                      style: GoogleFonts.outfit(
                        color: isDark ? Colors.white : const Color(0xFF1B172E),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Icon(
                        Icons.close_rounded,
                        color: isDark ? Colors.white30 : Colors.black26,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
              // Divider
              Container(
                height: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.black.withOpacity(0.06),
              ),
              // Equipment list
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _equipmentsData.length,
                  itemBuilder: (context, index) {
                    final e = _equipmentsData[index];
                    final String name = e['name']?.toString() ?? 'N/A';
                    final String id = e['equipmentId']?.toString() ?? '';
                    final bool isSelected = id == _selectedEquipmentId;

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _onEquipmentSelected(
                            id,
                            name,
                            e['equipmentTypeId']?.toString() ?? '',
                            (e['shortId'] ?? e['equipmentShortId'])
                                    ?.toString() ??
                                '',
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF6CC042).withOpacity(0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? const Color(0xFF6CC042)
                                      : (isDark
                                          ? Colors.white12
                                          : Colors.black12),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  name,
                                  style: GoogleFonts.outfit(
                                    color: isSelected
                                        ? (isDark
                                            ? Colors.white
                                            : const Color(0xFF1B172E))
                                        : (isDark
                                            ? Colors.white54
                                            : Colors.black45),
                                    fontSize: 15,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_rounded,
                                  color: const Color(0xFF6CC042),
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _fetchEquipments() async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    final queryParams = <String>[];
    if (companyId.isNotEmpty && companyId != 'null' && companyId != 'undefined') {
      queryParams.add('companyId=$companyId');
    }
    if (siteId.isNotEmpty && siteId != 'null' && siteId != 'undefined') {
      queryParams.add('siteId=$siteId');
    }
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final url =
        '${AppConfig.provisionBaseUrl}/equipments$queryString';

    bool fetchSuccess = false;
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final dynamic listData = data['data'];

        if (listData != null && listData is List) {
          final List<dynamic> filteredList = listData.where((e) {
            final sysId = (e['systemId'] ?? e['SystemId'] ?? '').toString();
            return sysId.toLowerCase() == widget.systemId.toLowerCase();
          }).toList();

          if (mounted && filteredList.isNotEmpty) {
            _applyEquipmentData(filteredList);
            fetchSuccess = true;
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching equipments: $e');
    }

    if (!fetchSuccess && widget.systemId.isNotEmpty) {
      debugPrint('🔄 Falling back to systems/equipment endpoint for system: ${widget.systemId}');
      try {
        final fallbackUrl = '${AppConfig.provisionBaseUrl}/systems/equipment/${widget.systemId}'
            '?companyId=$companyId&siteId=$siteId';
            
        final response = await http.get(
          Uri.parse(fallbackUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Cookie': 'auth_token=$token',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 4));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final dynamic listData = data['data'];
          if (listData != null && listData is List) {
            final List<dynamic> filteredList = listData.where((e) {
              final sysId = (e['systemId'] ?? e['SystemId'] ?? '').toString();
              return sysId.toLowerCase() == widget.systemId.toLowerCase() || sysId.isEmpty;
            }).toList();
            if (mounted && filteredList.isNotEmpty) {
              _applyEquipmentData(filteredList);
              fetchSuccess = true;
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('Error in fallback equipments fetch: $e');
      }
    }

    if (mounted) {
      setState(() => _isLoadingEquipments = false);
    }
  }

  Future<void> _onEquipmentSelected(
    String equipmentId,
    String name,
    String typeId,
    String shortId,
  ) async {
    debugPrint(
      '🔄 SWITCHING EQUIPMENT: ID=$equipmentId, Name=$name, ShortId=$shortId',
    );
    if (_selectedEquipmentId == equipmentId &&
        _selectedEquipmentShortId.isNotEmpty) return;

    _closeStream();

    // Resolve IMEI using the helper function to avoid redundancy
    final String resolvedDeviceId = await _fetchEquipmentImei(equipmentId);
    final String deviceId =
        resolvedDeviceId.isNotEmpty ? resolvedDeviceId : shortId;

    setState(() {
      _selectedEquipmentId = equipmentId;
      _selectedEquipmentName = name;
      _selectedEquipmentTypeId = typeId;
      _selectedEquipmentShortId = shortId;
      _deviceId = deviceId; // Set to IMEI if found, else fallback to shortId
      _isLoadingEquipments = true;
      _isOnline =
          false; // Reset to inactive until confirmed by new device status JSON
      _lastMessageReceivedTime =
          DateTime.now().subtract(const Duration(seconds: 20));
      _isTelemetryLoading = true;
      _tempHistory.clear();
      _recentLogs.clear();
    });

    // The deviceId is already resolved above

    if (mounted) {
      setState(() {
        _deviceId = deviceId;
        _isLoadingEquipments = false;
        _setupPersistentMqtt();
      });

      if (deviceId.isNotEmpty) {
        // Telemetry is now handled via the SSE stream initialized in _setupPersistentMqtt()
      } else {
        setState(() => _isTelemetryLoading = false);
      }
    }
  }

  Future<void> _togglePower(bool value) async {
    debugPrint('ðŸ”” [ACTION] POWER TOGGLE: IMEI=$_deviceId, NewValue=$value');
    final companyId = await AuthService.getCompanyId() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    // 1. Fetch MQTT Configs
    final configUrl =
        '${AppConfig.provisionBaseUrl}/companies/$companyId/mqtt-configs';
    Map<String, dynamic>? selectedConfig;

    try {
      final response = await http.get(
        Uri.parse(configUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> configs = data['data'] ?? [];

        // Find config with type 'ac_compressor'
        selectedConfig = configs.firstWhere(
          (c) => c['type'] == 'ac_compressor',
          orElse: () => null,
        );
      }
    } catch (e) {
      debugPrint('â Œ Error fetching MQTT configs: $e');
    }

    if (selectedConfig == null) {
      debugPrint('âš ï¸  No AC Compressor MQTT config found, using defaults.');
    }

    _publishMqttCommand(value ? 'ON' : 'OFF');

    if (mounted) {
      _messenger?.showSnackBar(
        SnackBar(
          content: Text(
              'Power ${value ? 'ON' : 'OFF'} for Device: ${_deviceId.isEmpty ? AppConfig.mqttDeviceId : _deviceId}'),
          backgroundColor: value ? Colors.green : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool _isConnectingMqtt = false;

  Future<void> _setupPersistentMqtt() async {
    // Start SSE stream listener immediately for getting data details
    if (_subscribedDeviceId != _deviceId) {
      _subscribedDeviceId = _deviceId;
      _connectToStream(_deviceId, "");
    }

    if (_isConnectingMqtt) return;
    if (_persistentMqttClient?.connectionStatus?.state ==
            MqttConnectionState.connected) {
      return;
    }

    // Disconnect existing client if we're switching devices
    if (_persistentMqttClient?.connectionStatus?.state ==
        MqttConnectionState.connected) {
      _persistentMqttClient!.disconnect();
    }

    _isConnectingMqtt = true;

    if (MqttConfigService.cached == null) {
      await MqttConfigService.fetchMqttConfig(type: 'ac');
    }

    final String broker = AppConfig.mqttBroker;
    final String username = AppConfig.mqttUsername;
    final String password = AppConfig.mqttPassword;

    _persistentMqttClient = MqttServerClient(
      broker,
      'flutter_live_${DateTime.now().millisecondsSinceEpoch}',
    );
    _persistentMqttClient!.port = 1883;
    _persistentMqttClient!.logging(on: false);
    _persistentMqttClient!.keepAlivePeriod = 60;
    _persistentMqttClient!.onDisconnected =
        () => debugPrint('🔌 [MQTT Live] Disconnected');

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(
            'flutter_live_${DateTime.now().millisecondsSinceEpoch}')
        .authenticateAs(username, password)
        .startClean();
    _persistentMqttClient!.connectionMessage = connMessage;

    try {
      debugPrint('📡 [MQTT Live] Connecting (Publish Only)...');
      await _persistentMqttClient!.connect();
      _isConnectingMqtt = false;
      if (_persistentMqttClient!.connectionStatus!.state ==
          MqttConnectionState.connected) {
        debugPrint(
            '✅ [MQTT Live] Connected (Publish Only). Telemetry is retrieved via SSE Stream.');
      }
    } catch (e) {
      _isConnectingMqtt = false;
      debugPrint('⚠️ [MQTT Live] Connection Error: $e');
      Future.delayed(const Duration(seconds: 5), () => _setupPersistentMqtt());
    }
  }

  void _handleMqttTelemetry(String topic, String payload) {
    final String statusTopic = _getDeviceTopic('status');
    final String onlineTopic = _getDeviceTopic('online');
    final bool isStatusTopic = topic == statusTopic;
    final bool isOnlineTopic = topic == onlineTopic;
    bool hasChanges = false;
    final String upperPayload = payload.trim().toUpperCase();

    // 0. Handle JSON Payload
    if (payload.trim().startsWith('{')) {
      try {
        // Fix potentially malformed JSON from device (e.g., "set_temp":,)
        String safePayload = payload;
        if (safePayload.contains('"set_temp":,')) {
          safePayload =
              safePayload.replaceAll('"set_temp":,', '"set_temp":null,');
        }

        final data = jsonDecode(safePayload);
        final Map<String, dynamic> p = (data['data'] != null)
            ? Map<String, dynamic>.from(data['data'])
            : Map<String, dynamic>.from(data);

        // Robust Device ID extraction from JSON
        final String incomingDeviceId =
            (p['device_id'] ?? p['deviceId'] ?? data['device_id'] ?? '')
                .toString();

        // Activation logic:
        // 1. Matches specific device topic
        // 2. Matches current device ID (IMEI/ShortId)
        // 3. Matches legacy/default fallback ID
        final bool isMatchingDevice = isStatusTopic ||
            (incomingDeviceId.isNotEmpty &&
                incomingDeviceId.toLowerCase() == _deviceId.toLowerCase()) ||
            incomingDeviceId == AppConfig.mqttDeviceId;

        if (isMatchingDevice) {
          // Dynamically bind to the physical device ID if they differ
          if (incomingDeviceId.isNotEmpty && _deviceId != incomingDeviceId) {
            debugPrint('🔄 Updating _deviceId from $_deviceId to $incomingDeviceId to match physical hardware');
            _deviceId = incomingDeviceId;
          }

          // Efficiently reset watchdog by simply updating the timestamp
          _lastMessageReceivedTime = DateTime.now();
          _lastMqttUpdateTime = (p['time'] ??
                  data['time'] ??
                  DateTime.now().toString().split('.').first.split(' ').last)
              .toString();
          hasChanges = true;

          if (p['temp'] != null || p['current_temp'] != null) {
            _actualTemperature =
                (p['temp'] ?? p['current_temp'] as num).toDouble();
            hasChanges = true;
          }
          if (p['set_temp'] != null || p['setTemp'] != null) {
            _setTemperature =
                (p['set_temp'] ?? p['setTemp'] as num).toDouble();
            hasChanges = true;
          }
          if (p['hum'] != null) {
            _humidity = (p['hum'] as num).toInt();
            hasChanges = true;
          }
          if (p['ac'] != null || p['ACStatus'] != null) {
            final acVal = (p['ac'] ?? p['ACStatus']).toString().toUpperCase();
            _isPowerCommandLock = false;
            _isPowerOn = (acVal == 'ON' || acVal == '1' || acVal == 'TRUE');
            hasChanges = true;
          }

          // WiFi/Online status is exclusively driven by the "status" field in this status topic JSON payload
          final String jsonStatus = (p['status'] ?? data['status'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
          final bool wasOnline = _isOnline;
          if (jsonStatus == 'ACTIVE' || jsonStatus == 'ON' || jsonStatus == 'OFF') {
            _isOnline = true;
            _inactiveStartTime = null;
            debugPrint(
                '📡 [MQTT status topic JSON] Status $jsonStatus received -> WiFi ON');
          } else {
            _isOnline = false;
            if (wasOnline) {
              _inactiveStartTime = DateTime.now();
            }
            debugPrint(
                '📡 [MQTT status topic JSON] Status is INACTIVE ($jsonStatus) -> WiFi OFF');
          }
          hasChanges = true;

          // Schedule parsing from JSON (now inside the device matching block)
          bool scheduleChanged = false;
          if (p['sch_on1'] != null) {
            _scheduleOn1 = p['sch_on1'].toString();
            scheduleChanged = true;
          }
          if (p['sch_off1'] != null) {
            _scheduleOff1 = p['sch_off1'].toString();
            scheduleChanged = true;
          }
          if (p['sch_int1'] != null) {
            _dynamicSchedules[0]['interval'] = p['sch_int1'].toString();
            scheduleChanged = true;
          }

          if (p['sch_on2'] != null) {
            _scheduleOn2 = p['sch_on2'].toString();
            scheduleChanged = true;
          }
          if (p['sch_off2'] != null) {
            _scheduleOff2 = p['sch_off2'].toString();
            scheduleChanged = true;
          }
          if (p['sch_int2'] != null) {
            _dynamicSchedules[1]['interval'] = p['sch_int2'].toString();
            scheduleChanged = true;
          }

          if (p['sch_on3'] != null) {
            _scheduleOn3 = p['sch_on3'].toString();
            scheduleChanged = true;
          }
          if (p['sch_off3'] != null) {
            _scheduleOff3 = p['sch_off3'].toString();
            scheduleChanged = true;
          }
          if (p['sch_int3'] != null) {
            _dynamicSchedules[2]['interval'] = p['sch_int3'].toString();
            scheduleChanged = true;
          }

          if (p['sch_on4'] != null) {
            _scheduleOn4 = p['sch_on4'].toString();
            scheduleChanged = true;
          }
          if (p['sch_off4'] != null) {
            _scheduleOff4 = p['sch_off4'].toString();
            scheduleChanged = true;
          }
          if (p['sch_int4'] != null) {
            _dynamicSchedules[3]['interval'] = p['sch_int4'].toString();
            scheduleChanged = true;
          }

          if (p['sch_on5'] != null) {
            _scheduleOn5 = p['sch_on5'].toString();
            scheduleChanged = true;
          }
          if (p['sch_off5'] != null) {
            _scheduleOff5 = p['sch_off5'].toString();
            scheduleChanged = true;
          }
          if (p['sch_int5'] != null) {
            _dynamicSchedules[4]['interval'] = p['sch_int5'].toString();
            scheduleChanged = true;
          }

          if (p['sch_on6'] != null) {
            _scheduleOn6 = p['sch_on6'].toString();
            scheduleChanged = true;
          }
          if (p['sch_off6'] != null) {
            _scheduleOff6 = p['sch_off6'].toString();
            scheduleChanged = true;
          }
          if (p['sch_int6'] != null) {
            _dynamicSchedules[5]['interval'] = p['sch_int6'].toString();
            scheduleChanged = true;
          }
          if (p['lunch_on'] != null) {
            _lunchOn = p['lunch_on'].toString();
            scheduleChanged = true;
          }
          if (p['lunch_off'] != null) {
            _lunchOff = p['lunch_off'].toString();
            scheduleChanged = true;
          }

          if (scheduleChanged) {
            hasChanges = true;
            debugPrint('✅ [MQTT JSON] Mapped Schedules for $incomingDeviceId');
          }
        } else {
          // Log background messages from other devices occasionally
          if (DateTime.now().second % 60 == 0) {
            debugPrint(
                'ℹ️ [MQTT] Background message for: $incomingDeviceId (Active: $_deviceId)');
          }
        }
      } catch (e) {
        debugPrint('❌ Error parsing MQTT JSON: $e');
      }
    } else {
      // 1. Explicit Schedule & Lunch Parsing
      if (upperPayload.contains('SCH_ON1')) {
        _scheduleOn1 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_ON2')) {
        _scheduleOn2 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_ON3')) {
        _scheduleOn3 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_ON4')) {
        _scheduleOn4 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_ON5')) {
        _scheduleOn5 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_ON6')) {
        _scheduleOn6 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_OFF1')) {
        _scheduleOff1 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_OFF2')) {
        _scheduleOff2 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_OFF3')) {
        _scheduleOff3 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_OFF4')) {
        _scheduleOff4 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_OFF5')) {
        _scheduleOff5 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_OFF6')) {
        _scheduleOff6 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('LUNCH_ON')) {
        _lunchOn = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('LUNCH_OFF')) {
        _lunchOff = _extractTime(payload);
        hasChanges = true;
      }

      // 2. Clearing Commands
      if (upperPayload.contains('SCH_CLEAR_LUNCH')) {
        // "This will clear all scedule"
        _scheduleOn1 = '--:--';
        _scheduleOff1 = '--:--';
        _scheduleOn2 = '--:--';
        _scheduleOff2 = '--:--';
        _scheduleOn3 = '--:--';
        _scheduleOff3 = '--:--';
        _scheduleOn4 = '--:--';
        _scheduleOff4 = '--:--';
        _scheduleOn5 = '--:--';
        _scheduleOff5 = '--:--';
        _scheduleOn6 = '--:--';
        _scheduleOff6 = '--:--';
        _lunchOn = '--:--';
        _lunchOff = '--:--';
        hasChanges = true;
      } else if (upperPayload.contains('SCH_CLEAR1')) {
        _scheduleOn1 = '--:--';
        _scheduleOff1 = '--:--';
        hasChanges = true;
      } else if (upperPayload.contains('SCH_CLEAR2')) {
        _scheduleOn2 = '--:--';
        _scheduleOff2 = '--:--';
        hasChanges = true;
      } else if (upperPayload.contains('SCH_CLEAR3')) {
        _scheduleOn3 = '--:--';
        _scheduleOff3 = '--:--';
        hasChanges = true;
      } else if (upperPayload.contains('SCH_CLEAR4')) {
        _scheduleOn4 = '--:--';
        _scheduleOff4 = '--:--';
        hasChanges = true;
      } else if (upperPayload.contains('SCH_CLEAR5')) {
        _scheduleOn5 = '--:--';
        _scheduleOff5 = '--:--';
        hasChanges = true;
      } else if (upperPayload.contains('SCH_CLEAR6')) {
        _scheduleOn6 = '--:--';
        _scheduleOff6 = '--:--';
        hasChanges = true;
      } else if (upperPayload == 'SCH_CLEAR' ||
          upperPayload.endsWith(':SCH_CLEAR')) {
        // "this one specific lunch clear"
        _lunchOn = '--:--';
        _lunchOff = '--:--';
        hasChanges = true;
      }

      // 3. Status & Power Matches
      final bool isTargetDeviceMessage = isStatusTopic ||
          isOnlineTopic ||
          (payload.contains(_deviceId) && _deviceId.isNotEmpty) ||
          payload.contains(AppConfig.mqttDeviceId);

      if (isTargetDeviceMessage) {
        _lastMessageReceivedTime = DateTime.now();
        if (upperPayload == 'ON_SUCCESS' ||
            upperPayload == 'STATUS_ON' ||
            upperPayload == 'AC_ON_DONE' ||
            upperPayload.contains('AC:ON')) {
          _isPowerCommandLock = false;
          _isPowerOn = true;
          hasChanges = true;
        } else if (upperPayload == 'OFF_SUCCESS' ||
            upperPayload == 'STATUS_OFF' ||
            upperPayload == 'AC_OFF_DONE' ||
            upperPayload.contains('AC:OFF')) {
          _isPowerCommandLock = false;
          _isPowerOn = false;
          hasChanges = true;
        } else if (upperPayload.startsWith('TEMP_SET')) {
          final valStr = upperPayload.replaceAll('TEMP_SET', '').replaceAll('_', '').replaceAll(':', '').trim();
          final val = double.tryParse(valStr);
          if (val != null) {
            _setTemperature = val;
            hasChanges = true;
          }
        } else if (upperPayload.contains('OFFLINE') ||
            upperPayload.contains('INACTIVE')) {
          final bool wasOnline = _isOnline;
          _isOnline = false;
          if (wasOnline != _isOnline) {
            _inactiveStartTime = DateTime.now();
            hasChanges = true;
            debugPrint(
                '📡 [MQTT String] Status Updated: $_isOnline (Payload: $payload)');
          }
        } else if (upperPayload.contains('ONLINE') ||
            upperPayload.contains('ACTIVE')) {
          final bool wasOnline = _isOnline;
          _isOnline = true;
          if (wasOnline != _isOnline) {
            _inactiveStartTime = null;
            hasChanges = true;
            debugPrint(
                '📡 [MQTT String] Status Updated: $_isOnline (Payload: $payload)');
          }
        }
      }

      if (upperPayload.startsWith('TEMP:')) {
        final valStr = upperPayload.split(':').last.trim();
        final val = double.tryParse(valStr);
        if (val != null) {
          _actualTemperature = val;
          hasChanges = true;
        }
      } else if (upperPayload.startsWith('HUM:')) {
        final valStr = upperPayload.split(':').last.trim();
        final val = double.tryParse(valStr);
        if (val != null) {
          _humidity = val.toInt();
          hasChanges = true;
        }
      }
    }

    if (hasChanges) {
      _syncDynamicSchedules();
      // Throttle UI updates, disk I/O, and data processing to avoid lag
      final now = DateTime.now();
      if (now.difference(_lastSetStateTime) >
          const Duration(milliseconds: 500)) {
        _lastSetStateTime = now;

        // 1. Process logs and history only when UI updates
        _tempHistory.add(_ChartData(now, _actualTemperature));
        if (_tempHistory.length > 20) _tempHistory.removeAt(0);

        _recentLogs.insert(0, {
          'time': now.toString().split('.').first.split(' ').last,
          'temp': _actualTemperature.toStringAsFixed(1),
          'hum': _humidity,
          'ac': _isPowerOn ? 'ON' : 'OFF',
          'online': _isOnline,
        });
        if (_recentLogs.length > 5) _recentLogs.removeLast();

        // 2. Save to cache disabled to prevent stale data persistence
        if (now.difference(_lastUpdateTime) > const Duration(seconds: 10)) {
          _lastUpdateTime = now;
          // LocalCacheService.saveDeviceStatus(widget.systemShortId, {
          //   'temp': _actualTemperature,
          //   'hum': _humidity,
          //   'power': _isPowerOn,
          // });
        }

        if (mounted) setState(() {});
      }
    }
  }

  String _extractTime(String payload) {
    if (payload.contains(":")) {
      final parts = payload.split(":");
      String potentialTime = "";
      if (parts.length >= 3) {
        potentialTime =
            '${parts[parts.length - 2].trim()}:${parts.last.trim()}';
      } else {
        potentialTime = parts.last.trim();
      }
      if (RegExp(r"^\d{1,2}:\d{2}$").hasMatch(potentialTime)) {
        return potentialTime;
      }
    }
    return "--:--";
  }

  void _updateInactiveTimeString() {
    if (_inactiveStartTime != null) {
      final duration = DateTime.now().difference(_inactiveStartTime!);
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      final seconds = duration.inSeconds.remainder(60);

      setState(() {
        if (hours > 0) {
          _inactiveTimeString = '${hours}h ${minutes}m ago';
        } else if (minutes > 0) {
          _inactiveTimeString = '${minutes}m ${seconds}s ago';
        } else {
          _inactiveTimeString = '${seconds}s ago';
        }
      });
    }
  }

  String _getDeviceTopic(String type) {
    // Dynamically construct topic based on the selected device ID (IMEI/ShortId)
    // Fallback to mqttDeviceId for compatibility with legacy hardware
    final String id = _deviceId.isEmpty ? AppConfig.mqttDeviceId : _deviceId;
    if (type == 'control') {
      return AppConfig.getMqttControlTopic(id);
    } else if (type == 'schedule') {
      return AppConfig.getMqttScheduleTopic(id);
    } else if (type == 'status') {
      return AppConfig.getMqttStatusTopic(id);
    } else if (type == 'temp') {
      return AppConfig.getMqttTempTopic(id);
    }
    // Fallback for online or other types
    return '${AppConfig.mqttTopic}/$id/$type';
  }

  Future<void> _publishMqttCommand(String message,
      {String? topic, bool allowOffline = false}) async {
    if (!_isOnline && !allowOffline) {
      _showOfflineWarning();
      return;
    }
    final String targetTopic = topic ?? _getDeviceTopic('control');
    debugPrint('📤 [MQTT Publish] Topic: $targetTopic, Message: $message');

    // Fast Path: Reuse existing persistent connection
    if (_persistentMqttClient != null &&
        _persistentMqttClient!.connectionStatus!.state ==
            MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      _persistentMqttClient!
          .publishMessage(targetTopic, MqttQos.atLeastOnce, builder.payload!);
      _handleOptimisticUpdate(message);
      return;
    }

    // Slow Path: Fallback to one-off connection
    if (MqttConfigService.cached == null) {
      await MqttConfigService.fetchMqttConfig(type: 'ac');
    }
    final String broker = AppConfig.mqttBroker;
    final String username = AppConfig.mqttUsername;
    final String password = AppConfig.mqttPassword;

    final client = MqttServerClient(
      broker,
      'flutter_cmd_${DateTime.now().millisecondsSinceEpoch}',
    );
    client.port = 1883;
    client.logging(on: false);
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(
            'flutter_cmd_${DateTime.now().millisecondsSinceEpoch}')
        .authenticateAs(username, password)
        .startClean();

    try {
      await client.connect();
      if (client.connectionStatus!.state == MqttConnectionState.connected) {
        final builder = MqttClientPayloadBuilder();
        builder.addString(message);
        client.publishMessage(
            targetTopic, MqttQos.atLeastOnce, builder.payload!);
        _handleOptimisticUpdate(message);
        await Future.delayed(const Duration(milliseconds: 500));
        client.disconnect();
      }
    } catch (e) {
      debugPrint('❌ [MQTT CMD] Error: $e');
    }
  }

  void _handleOptimisticUpdate(String message) {
    if (!mounted) return;
    setState(() {
      _lastManualCommandTime = DateTime.now();
      _isPowerCommandLock = true;
      if (message == 'ON') {
        _isPowerOn = true;
      } else if (message == 'OFF') {
        _isPowerOn = false;
      }
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _isPowerCommandLock) {
        setState(() => _isPowerCommandLock = false);
      }
    });
  }

  Future<String> _fetchEquipmentImei(String equipmentId) async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final bucket = await AuthService.getBucket() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    final url = '${AppConfig.provisionBaseUrl}/equipments/$equipmentId'
        '?companyId=$companyId&siteId=$siteId&bucket=$bucket';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Assuming IMEI is in data['data']['imei'] or similar field
        // Looking at the user's provided JSON, I don't see imei, but they said "take from the imei is an device_id"
        // Let's check the first equipment structure again
        final equipData = data['data'];
        if (equipData is List && equipData.isNotEmpty) {
          final first = equipData[0];
          return (first['imei'] ??
                      first['Imei'] ??
                      first['shortId'] ??
                      first['ShortId'] ??
                      '')
                  ?.toString() ??
              '';
        } else if (equipData is Map) {
          return (equipData['imei'] ??
                      equipData['Imei'] ??
                      equipData['shortId'] ??
                      equipData['ShortId'] ??
                      '')
                  ?.toString() ??
              '';
        }
      }
    } catch (e) {
      debugPrint('Error fetching IMEI: $e');
    }
    return '';
  }

  Future<void> _connectToStream(String deviceId, String imei) async {
    _subscription?.cancel();
    _subscription = null;

    final companyId = await AuthService.getCompanyId() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    final queryParams = <String>[];
    if (companyId.isNotEmpty) {
      queryParams.add('companyid=$companyId');
    }
    if (deviceId.isNotEmpty) {
      queryParams.add('deviceId=$deviceId');
    }
    if (imei.isNotEmpty) {
      queryParams.add('imei=$imei');
    }
    final url = '${AppConfig.provisionBaseUrl}/mqtt/stream?${queryParams.join('&')}';

    debugPrint('📡 [HTTP Stream] Connecting to: $url');

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Cookie'] = 'auth_token=$token';
      request.headers['Accept'] = 'text/event-stream';

      final response = await client.send(request);

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() => _isTelemetryLoading = false);
        }
        _subscription = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            if (line.trim().isEmpty) return;
            debugPrint('📥 [HTTP Stream] Data: $line');
            _parseAndMapData(line);
          },
          onError: (error) {
            debugPrint('❌ [HTTP Stream] Error: $error');
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && _deviceId == deviceId) {
                _connectToStream(deviceId, imei);
              }
            });
          },
          onDone: () {
            debugPrint('🔌 [HTTP Stream] Stream closed');
            client.close();
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && _deviceId == deviceId) {
                _connectToStream(deviceId, imei);
              }
            });
          },
        );
      } else {
        debugPrint('❌ [HTTP Stream] Connection failed: ${response.statusCode}');
        if (mounted) {
          setState(() => _isTelemetryLoading = false);
        }
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && _deviceId == deviceId) {
            _connectToStream(deviceId, imei);
          }
        });
      }
    } catch (e) {
      debugPrint('❌ [HTTP Stream] Connection Exception: $e');
      if (mounted) {
        setState(() => _isTelemetryLoading = false);
      }
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _deviceId == deviceId) {
          _connectToStream(deviceId, imei);
        }
      });
    }
  }

  void _parseAndMapData(String line) {
    try {
      // Remove "data: " prefix if it's SSE format
      String jsonStr = line;
      if (line.startsWith('data: ')) {
        jsonStr = line.substring(6).trim();
      } else {
        jsonStr = line.trim();
      }

      if (jsonStr.isEmpty) return;

      // 1. Decode JSON
      final data = jsonDecode(jsonStr);

      // Check if this is a stream control/connection handshake message (no telemetry data payload)
      if (data['data'] == null && (data['message'] != null || data['cacheStatus'] != null)) {
        debugPrint('ℹ️ [HTTP Stream] Control Message: ${data['message']} | Cache: ${data['cacheStatus']}');
        // Do NOT set _isOnline = false here. The SSE handshake message is just a stream
        // control message and does not reflect the physical device's WiFi/online state.
        // Online status is exclusively driven by actual telemetry data (status field)
        // and the 30-second watchdog timer.
        return;
      }

      Map<String, dynamic>? payload;

      if (data['data'] != null && data['data']['data'] != null) {
        payload = Map<String, dynamic>.from(data['data']['data']);
      } else if (data['data'] != null) {
        payload = Map<String, dynamic>.from(data['data']);
      }

      if (payload != null && mounted) {
        bool hasChanges = false;
        _lastMessageReceivedTime = DateTime.now();

        // Restore parsing of temperature, humidity, wifi, schedules, and active status
        // from the stream API as requested by the user.
        double newActualTemperature = _actualTemperature;
        if (payload['temp'] != null || payload['current_temp'] != null || payload['currentTemp'] != null) {
          final val = payload['temp'] ?? payload['current_temp'] ?? payload['currentTemp'];
          if (val is num) {
            newActualTemperature = val.toDouble();
            if (newActualTemperature != _actualTemperature) hasChanges = true;
          }
        }

        double newSetTemperature = _setTemperature;
        if (payload['set_temp'] != null || payload['setTemp'] != null) {
          final val = payload['set_temp'] ?? payload['setTemp'];
          if (val is num) {
            newSetTemperature = val.toDouble();
            if (newSetTemperature != _setTemperature) hasChanges = true;
          }
        }

        int newHumidity = _humidity;
        if (payload['hum'] != null || payload['humidity'] != null) {
          final val = payload['hum'] ?? payload['humidity'];
          if (val is num) {
            newHumidity = val.toInt();
            if (newHumidity != _humidity) hasChanges = true;
          }
        }

        bool newPowerOn = _isPowerOn;
        if ((payload['ac'] != null || payload['ACStatus'] != null) &&
            !_isPowerCommandLock) {
          newPowerOn =
              (payload['ac'] ?? payload['ACStatus']).toString() == 'ON';
          if (newPowerOn != _isPowerOn) hasChanges = true;
        }

        // Connection status updates from HTTP Stream
        bool newOnline = _isOnline;
        final String jsonStatus = (payload['status'] ?? data['status'] ?? '').toString().trim().toUpperCase();
        if (jsonStatus.isNotEmpty) {
          newOnline = (jsonStatus == 'ACTIVE' || jsonStatus == 'ON' || jsonStatus == 'OFF');
          if (newOnline != _isOnline) {
            hasChanges = true;
          }
        }

        if (payload['wifiSsid'] != null || payload['wifi_ssid'] != null) {
          final ssid = (payload['wifiSsid'] ?? payload['wifi_ssid']).toString();
          if (ssid.isNotEmpty && ssid != _savedSsid) {
            _savedSsid = ssid;
            hasChanges = true;
          }
        }

        // Schedules
        if (payload['sch_on1'] != null) _scheduleOn1 = payload['sch_on1'].toString();
        if (payload['sch_off1'] != null) _scheduleOff1 = payload['sch_off1'].toString();
        if (payload['sch_on2'] != null) _scheduleOn2 = payload['sch_on2'].toString();
        if (payload['sch_off2'] != null) _scheduleOff2 = payload['sch_off2'].toString();
        if (payload['sch_on3'] != null) _scheduleOn3 = payload['sch_on3'].toString();
        if (payload['sch_off3'] != null) _scheduleOff3 = payload['sch_off3'].toString();
        if (payload['sch_on4'] != null) _scheduleOn4 = payload['sch_on4'].toString();
        if (payload['sch_off4'] != null) _scheduleOff4 = payload['sch_off4'].toString();
        if (payload['sch_on5'] != null) _scheduleOn5 = payload['sch_on5'].toString();
        if (payload['sch_off5'] != null) _scheduleOff5 = payload['sch_off5'].toString();

        bool newAuto = _isAuto;
        if (payload['auto'] != null || payload['isAuto'] != null) {
          newAuto = (payload['auto'] ?? payload['isAuto']) == true;
          if (newAuto != _isAuto) hasChanges = true;
        }

        if (mounted) {
          setState(() {
            _isTelemetryLoading = false;
            _actualTemperature = newActualTemperature;
            _setTemperature = newSetTemperature;
            _humidity = newHumidity;

            if (hasChanges) {
              if (!_isPowerCommandLock) _isPowerOn = newPowerOn;
              _isOnline = newOnline;
              _isAuto = newAuto;
              _lastUpdateTime = DateTime.now();

              _recentLogs.insert(0, {
                'time': payload!['time'] ??
                    DateTime.now().toString().split('.').first.split(' ').last,
                'temp': _actualTemperature.toStringAsFixed(1),
                'hum': _humidity,
                'ac': _isPowerOn ? 'ON' : 'OFF',
              });
              if (_recentLogs.length > 5) _recentLogs.removeLast();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error parsing Stream data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Listener(
      onPointerDown: (_) => _messenger?.hideCurrentSnackBar(),
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF1B172E) : const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              color: isDark ? Colors.white : const Color(0xFF1B172E),
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: GestureDetector(
            onTap: () => _showEquipmentSelectionPopup(context, isDark),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF231F3F), const Color(0xFF1B172E)]
                      : [Colors.white, const Color(0xFFF1F5F9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF6CC042).withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6CC042).withOpacity(0.08),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.ac_unit_rounded,
                    color: const Color(0xFF6CC042),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedEquipmentName.toUpperCase(),
                    style: GoogleFonts.outfit(
                      color: isDark ? Colors.white : const Color(0xFF1B172E),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF6CC042),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (_pulseController != null)
              FadeTransition(
                opacity: Tween(begin: 0.3, end: 1.0).animate(
                  CurvedAnimation(
                    parent: _pulseController!,
                    curve: Curves.easeInOut,
                  ),
                ),
                child: IconButton(
                  onPressed: () => _showDataInsights(isDark),
                  icon: Icon(
                    Icons.analytics_outlined,
                    color: isDark
                        ? const Color(0xFF6CC042)
                        : const Color(0xFF10B981),
                    size: 24,
                  ),
                  tooltip: 'Trends',
                ),
              )
            else
              const SizedBox(width: 48),
            const SizedBox(width: 8),
          ],
          centerTitle: true,
        ),
        body: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 16),
                // Equipment selection moved to AppBar
                const SizedBox(height: 16), // Space between top and gauge
                RepaintBoundary(
                  child: _InteractiveThermostatGauge(
                    setTemp: _setTemperature,
                    actualTemp: _actualTemperature,
                    isDark: isDark,
                    isOnline: _isOnline,
                    isAnalyzing: _isAnalyzing,
                    colorScheme: colorScheme,
                    onTempChanged: (double val) {
                      setState(() => _setTemperature = val);
                      _publishMqttCommand('${val.toInt()}',
                          topic: _getDeviceTopic('temp'));
                    },
                    onClearTemp: () {
                      setState(() => _setTemperature = 24.0);
                      _publishMqttCommand('24',
                          topic: _getDeviceTopic('temp'));
                    },
                    onDisabledInteraction: _showOfflineWarning,
                  ),
                ),
                const SizedBox(height: 32), // Space below gauge
                _buildPrimaryControls(isDark),
                const SizedBox(height: 24), // Space below primary controls
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildScrollableStats(isDark, colorScheme),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_isLoadingEquipments || _isTelemetryLoading)
              Positioned.fill(child: _buildFullPageSkeleton(isDark)),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  Widget _buildFullPageSkeleton(bool isDark) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: isDark ? const Color(0xFF1B172E) : Colors.white,
      child: SingleChildScrollView(
        physics:
            const NeverScrollableScrollPhysics(), // Prevent scrolling while loading
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Tabs Skeleton
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: List.generate(
                  3,
                  (i) => Container(
                    width: 80,
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
            // Gauge Skeleton
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 50),
            // Stats Skeleton
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Schedule Skeleton
                  Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Lunch Skeleton
                  Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  const SizedBox(height: 100), // Ensure bottom is covered
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendsSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Temperature Trends',
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            child: SizedBox(
              height: 150,
              child: SfCartesianChart(
                margin: EdgeInsets.zero,
                primaryXAxis: DateTimeAxis(isVisible: false),
                primaryYAxis: NumericAxis(
                  isVisible: false,
                  minimum: 20,
                  maximum: 40,
                ),
                plotAreaBorderWidth: 0,
                series: <CartesianSeries<_ChartData, DateTime>>[
                  SplineAreaSeries<_ChartData, DateTime>(
                    dataSource: _tempHistory,
                    xValueMapper: (_ChartData data, _) => data.time,
                    yValueMapper: (_ChartData data, _) => data.temp,
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6CC042).withOpacity(0.3),
                        const Color(0xFF6CC042).withOpacity(0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderColor: const Color(0xFF6CC042),
                    borderWidth: 2,
                    animationDuration: 0,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity Log',
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                children: [
                  _tableHeader('TIME', isDark),
                  _tableHeader('TEMP', isDark),
                  _tableHeader('AC', isDark),
                ],
              ),
              ..._recentLogs.map(
                (log) => TableRow(
                  children: [
                    _tableCell(log['time'].toString().split(' ').last, isDark),
                    _tableCell('${log['temp']}°', isDark),
                    _tableCell(
                      log['ac']?.toString() ?? 'N/A',
                      isDark,
                      color: log['ac'] == 'ON'
                          ? const Color(0xFF6CC042)
                          : Colors.redAccent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String text, bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            color: Colors.white24,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _tableCell(String text, bool isDark, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            color: color ?? (isDark ? Colors.white70 : Colors.black87),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  void _showDataInsights(bool isDark) async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final bucket = await AuthService.getBucket() ?? '';

    // Find the current equipment data for debugging
    final selectedData = _equipmentsData.firstWhere(
      (e) => e['equipmentId']?.toString() == _selectedEquipmentId,
      orElse: () => {},
    );

    debugPrint('ðŸ”  DEBUGGING TRENDS NAVIGATION:');
    debugPrint('ðŸ†” Selected Equipment ID: $_selectedEquipmentId');
    debugPrint('ðŸ ·ï¸  Selected Short ID: $_selectedEquipmentShortId');
    debugPrint('ðŸ“± Device ID (IMEI): $_deviceId');
    debugPrint('ðŸ“¦ Full Equipment Data: $selectedData');

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _TrendsPage(
          isDark: isDark,
          systemId: widget.systemId,
          systemName: widget.deviceName, // This holds the system name
          systemShortId: widget.systemShortId,
          equipmentId: _selectedEquipmentId,
          equipmentName: _selectedEquipmentName,
          equipmentTypeId: _selectedEquipmentTypeId,
          equipmentShortId: _selectedEquipmentShortId,
          companyId: companyId,
          siteId: siteId,
          bucket: bucket,
        ),
      ),
    );
  }

  Widget _actionPill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryControls(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // WIFI Toggle with programmatic tooltip
        Tooltip(
          key: _wifiTooltipKey,
          richMessage: TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (_isAnalyzing
                            ? Colors.amber
                            : (_isOnline
                                ? const Color(0xFF6CC042)
                                : const Color(0xFFEF4444)))
                        .withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (_isAnalyzing
                              ? Colors.amber
                              : (_isOnline
                                  ? const Color(0xFF6CC042)
                                  : const Color(0xFFEF4444)))
                          .withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    _isAnalyzing
                        ? Icons.wifi_protected_setup_rounded
                        : (_isOnline
                            ? Icons.wifi_rounded
                            : Icons.wifi_off_rounded),
                    color: _isAnalyzing
                        ? Colors.amber
                        : (_isOnline
                            ? const Color(0xFF6CC042)
                            : const Color(0xFFEF4444)),
                    size: 14,
                  ),
                ),
              ),
              const WidgetSpan(child: SizedBox(width: 10)),
              TextSpan(
                text: _isAnalyzing
                    ? 'CHECKING WIFI...'
                    : (_isOnline ? 'CONNECTED WIFI' : 'WIFI OFFLINE'),
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
              const TextSpan(text: '\n\n'),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _isAnalyzing
                        ? Colors.amber
                        : (_isOnline
                            ? const Color(0xFF6CC042)
                            : const Color(0xFFEF4444)),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const WidgetSpan(child: SizedBox(width: 6)),
              TextSpan(
                text: _isAnalyzing
                    ? 'Analyzing connection stability...'
                    : (_isOnline
                        ? (_savedSsid.isNotEmpty
                            ? _savedSsid
                            : 'Active Connection')
                        : 'Disconnected'),
                style: GoogleFonts.poppins(
                  color: Colors.white60,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          preferBelow: false,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1E1B4B).withOpacity(0.95), // Deep indigo
                const Color(0xFF311042).withOpacity(0.95), // Deep violet/wine
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (_isAnalyzing
                      ? Colors.amber
                      : (_isOnline
                          ? const Color(0xFF6CC042)
                          : const Color(0xFFEF4444)))
                  .withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (_isAnalyzing
                        ? Colors.amber
                        : (_isOnline
                            ? const Color(0xFF6CC042)
                            : const Color(0xFFEF4444)))
                    .withOpacity(0.2),
                blurRadius: 16,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.symmetric(horizontal: 24),
          child: _buildActionButton(
            icon: _isAnalyzing
                ? Icons.wifi_protected_setup_rounded
                : (_isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded),
            label: 'WIFI',
            isActive: true,
            activeColor: _isAnalyzing
                ? Colors.amber
                : (_isOnline
                    ? const Color(0xFF6CC042)
                    : const Color(0xFFEF4444)),
            isDark: isDark,
            onTap: () {
              // Trigger elegant tooltip on single tap
              _wifiTooltipKey.currentState?.ensureTooltipVisible();

              if (!_isOnline) {
                debugPrint('🔄 [MQTT] User requested WiFi re-sync');
                _setupPersistentMqtt();
                _messenger?.showSnackBar(
                  const SnackBar(
                    content: Text('Re-syncing connection status...'),
                    duration: Duration(seconds: 3),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            onLongPress: () {
              // Trigger elegant tooltip on long press
              _wifiTooltipKey.currentState?.ensureTooltipVisible();
            },
          ),
        ),
        const SizedBox(width: 20),
        // ON Button
        _buildActionButton(
          icon: Icons.power_settings_new_rounded,
          label: 'ON',
          isActive: _isPowerOn,
          activeColor: const Color(0xFF6CC042),
          isDark: isDark,
          onTap: () {
            _publishMqttCommand('ON');
          },
        ),
        const SizedBox(width: 20),
        // OFF Button
        _buildActionButton(
          icon: Icons.power_off_rounded,
          label: 'OFF',
          isActive: !_isPowerOn,
          activeColor: const Color(0xFFEF4444),
          isDark: isDark,
          onTap: () {
            _publishMqttCommand('OFF');
          },
        ),
        const SizedBox(width: 20),
        // Schedule Control
        _buildActionButton(
          icon: Icons.calendar_month_rounded,
          label: 'SCHEDULE',
          isActive: true,
          activeColor: const Color(0xFF8B5CF6),
          isDark: isDark,
          onTap: () {
            if (_isOnline) {
              _showSchedulePicker(isDark);
            } else {
              _showOfflineWarning();
            }
          },
        ),
      ],
    );
  }

  Widget _buildScrollableStats(bool isDark, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // 2. Status and Humidity (Responsive Row/Column)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 340) {
                return Column(
                  children: [
                    _buildStatusCard(isDark),
                    if (_isOnline) const SizedBox(height: 12),
                    if (_isOnline) _buildHumidityCard(isDark),
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildStatusCard(isDark)),
                    if (_isOnline) const SizedBox(width: 12),
                    if (_isOnline) Expanded(child: _buildHumidityCard(isDark)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // 3. Schedule Visualization Sections
          if (_isOnline) ...[
            RepaintBoundary(child: _buildScheduleSection(isDark)),
            const SizedBox(height: 12),
            RepaintBoundary(child: _buildLunchSection(isDark)),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    required bool isDark,
  }) {
    final borderColor = isActive
        ? activeColor.withOpacity(0.4)
        : (isDark ? Colors.white12 : Colors.black12);
    final iconColor = isActive
        ? (isDark ? Colors.white : activeColor)
        : (isDark ? Colors.white38 : Colors.black38);

    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withOpacity(isDark ? 0.15 : 0.1)
                  : (isDark ? Colors.white.withOpacity(0.03) : Colors.white),
              shape: BoxShape.circle,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: activeColor.withOpacity(0.25),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [
                      if (!isDark)
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                    ],
              border: Border.all(
                color: borderColor,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Icon(
                icon,
                color: iconColor,
                size: 26,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: isActive
                ? (isDark ? Colors.white70 : activeColor)
                : (isDark ? Colors.white24 : Colors.black26),
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF26213A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'AC STATUS',
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white24 : Colors.black45,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _isAnalyzing
                          ? Colors.amber
                          : (_isOnline
                              ? const Color(0xFF6CC042)
                              : Colors.redAccent),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isAnalyzing
                                  ? Colors.amber
                                  : (_isOnline
                                      ? const Color(0xFF6CC042)
                                      : Colors.redAccent))
                              .withOpacity(0.4),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 2),
              _isAnalyzing
                  ? Text(
                      'ANALYZING',
                      style: GoogleFonts.poppins(
                        color: Colors.amber,
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : (_isOnline
                      ? Text(
                          'ONLINE',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF6CC042),
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : Text(
                          'OFFLINE',
                          style: GoogleFonts.poppins(
                            color: Colors.redAccent,
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                          ),
                        )),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _isOnline ? Icons.ac_unit_rounded : Icons.power_off_rounded,
                color: _isOnline ? const Color(0xFF6CC042) : Colors.white24,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isAnalyzing
                          ? 'ANALYZING'
                          : (_isOnline ? 'ACTIVE' : 'INACTIVE'),
                      style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!_isOnline && _inactiveTimeString != 'N/A')
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _inactiveTimeString,
                          style: GoogleFonts.poppins(
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            height: 1,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.history_toggle_off_rounded,
                size: 10,
                color: isDark ? Colors.white30 : Colors.black38,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _lastMqttUpdateTime.isEmpty
                      ? 'No Data Yet'
                      : 'Last Data: $_lastMqttUpdateTime',
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white30 : Colors.black45,
                    fontSize: 7.5,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHumidityCard(bool isDark) {
    String comfortText = 'Optimal Comfort';
    IconData comfortIcon = Icons.eco_rounded;
    Color comfortColor = const Color(0xFF6CC042);
    if (_humidity < 40) {
      comfortText = 'Dry Atmosphere';
      comfortIcon = Icons.wb_sunny_rounded;
      comfortColor = const Color(0xFFF59E0B);
    } else if (_humidity > 60) {
      comfortText = 'High Humidity';
      comfortIcon = Icons.water_drop_rounded;
      comfortColor = const Color(0xFF3B82F6);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF26213A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'HUMIDITY',
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white24 : Colors.black45,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: comfortColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: comfortColor.withOpacity(0.4),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 2),
              Text(
                'LIVE SENSOR',
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.white24 : Colors.black38,
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _humidity / 100,
                      strokeWidth: 3,
                      backgroundColor: isDark
                          ? Colors.white10
                          : Colors.black.withOpacity(0.05),
                      valueColor: AlwaysStoppedAnimation<Color>(comfortColor),
                    ),
                    Icon(
                      Icons.water_drop_rounded,
                      size: 9,
                      color: comfortColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_humidity%',
                      style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            height: 1,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                comfortIcon,
                size: 10,
                color: comfortColor.withOpacity(0.6),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  comfortText,
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white30 : Colors.black45,
                    fontSize: 7.5,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getScheduleColor(int index) {
    switch (index % 4) {
      case 0:
        return const Color(0xFF6CC042); // Green
      case 1:
        return const Color(0xFF3B82F6); // Blue
      case 2:
        return const Color(0xFFF59E0B); // Amber/Orange
      default:
        return const Color(0xFFEC4899); // Pink
    }
  }

  Widget _buildScheduleSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF26213A) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color:
              isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.schedule_rounded,
                    color: Color(0xFF8B5CF6), size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                'Daily Schedule',
                style: GoogleFonts.outfit(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_isAuto) _buildAutoBadge(),
            ],
          ),
          const SizedBox(height: 20),
          if (_dynamicSchedules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No schedules configured',
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white30 : Colors.black38,
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            Column(
              children:
                  List.generate(math.min(5, _dynamicSchedules.length), (index) {
                final schedule = _dynamicSchedules[index];
                final String onTime = schedule['on'] ?? '--:--';
                final String offTime = schedule['off'] ?? '--:--';

                // A routine is scheduled if it has a valid time setting
                final bool isScheduled = onTime != '--:--' &&
                    offTime != '--:--' &&
                    onTime.toUpperCase() != 'DISABLED' &&
                    offTime.toUpperCase() != 'DISABLED';

                final bool isLast =
                    index == math.min(5, _dynamicSchedules.length) - 1;

                // Use a single premium, consistent brand color for all active timeline elements
                const Color themeColor =
                    Color(0xFF3B82F6); // Gorgeous electric blue
                const Color activeOnColor =
                    Color(0xFF6CC042); // Premium green for ON
                const Color activeOffColor =
                    Color(0xFFEF4444); // Premium red for OFF

                // Check if previous schedule is scheduled to color the top connecting line segment
                bool isPrevScheduled = false;
                if (index > 0) {
                  final prevSchedule = _dynamicSchedules[index - 1];
                  final String prevOn = prevSchedule['on'] ?? '--:--';
                  final String prevOff = prevSchedule['off'] ?? '--:--';
                  isPrevScheduled = prevOn != '--:--' &&
                      prevOff != '--:--' &&
                      prevOn.toUpperCase() != 'DISABLED' &&
                      prevOff.toUpperCase() != 'DISABLED';
                }

                // Check if next schedule is scheduled to color the bottom connecting line segment
                bool isNextScheduled = false;
                if (index < math.min(5, _dynamicSchedules.length) - 1) {
                  final nextSchedule = _dynamicSchedules[index + 1];
                  final String nextOn = nextSchedule['on'] ?? '--:--';
                  final String nextOff = nextSchedule['off'] ?? '--:--';
                  isNextScheduled = nextOn != '--:--' &&
                      nextOff != '--:--' &&
                      nextOn.toUpperCase() != 'DISABLED' &&
                      nextOff.toUpperCase() != 'DISABLED';
                }

                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        // Left Connected Vertical Timeline Track Segment
                        SizedBox(
                          width: 32,
                          child: Column(
                            children: [
                              // Top connecting line segment (colored only if both nodes are scheduled)
                              Expanded(
                                child: Container(
                                  width: 2,
                                  color: index == 0
                                      ? Colors.transparent
                                      : ((isScheduled && isPrevScheduled)
                                          ? themeColor.withOpacity(0.5)
                                          : (isDark
                                              ? Colors.white.withOpacity(0.06)
                                              : Colors.black
                                                  .withOpacity(0.06))),
                                ),
                              ),
                              // Timeline Node (Outer ring + filled center dot)
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isScheduled
                                      ? themeColor.withOpacity(0.12)
                                      : (isDark
                                          ? Colors.white.withOpacity(0.02)
                                          : Colors.black.withOpacity(0.02)),
                                  border: Border.all(
                                    color: isScheduled
                                        ? themeColor
                                        : (isDark
                                            ? Colors.white12
                                            : Colors.black12),
                                    width: isScheduled ? 2 : 1.5,
                                  ),
                                  boxShadow: [
                                    if (isScheduled)
                                      BoxShadow(
                                        color: themeColor.withOpacity(0.2),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                  ],
                                ),
                                child: Center(
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isScheduled
                                          ? themeColor
                                          : (isDark
                                              ? Colors.white24
                                              : Colors.black26),
                                    ),
                                  ),
                                ),
                              ),
                              // Bottom connecting line segment (colored only if both nodes are scheduled)
                              Expanded(
                                child: Container(
                                  width: 2,
                                  color: isLast
                                      ? Colors.transparent
                                      : ((isScheduled && isNextScheduled)
                                          ? themeColor.withOpacity(0.5)
                                          : (isDark
                                              ? Colors.white.withOpacity(0.06)
                                              : Colors.black
                                                  .withOpacity(0.06))),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Right Side Schedule Details (Title, Badge, and side-by-side time chips)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Row 1: Label + Badge
                              Row(
                                children: [
                                  Text(
                                    'SCHEDULE ${index + 1}',
                                    style: GoogleFonts.outfit(
                                      color: isScheduled
                                          ? (isDark
                                              ? Colors.white
                                              : Colors.black87)
                                          : (isDark
                                              ? Colors.white30
                                              : Colors.black38),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isScheduled
                                          ? themeColor.withOpacity(0.1)
                                          : (isDark
                                              ? Colors.white.withOpacity(0.03)
                                              : Colors.black.withOpacity(0.03)),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: isScheduled
                                            ? themeColor.withOpacity(0.2)
                                            : Colors.transparent,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      isScheduled
                                          ? (schedule['interval'] != null &&
                                                  schedule['interval'] !=
                                                      'None' &&
                                                  schedule['interval']!
                                                      .isNotEmpty
                                              ? 'Interval: ${schedule['interval']!.replaceAll(' mins', 'm').replaceAll(' hour', 'h').replaceAll('s', '')}'
                                              : 'Interval')
                                          : 'Interval',
                                      style: GoogleFonts.outfit(
                                        color: isScheduled
                                            ? themeColor
                                            : (isDark
                                                ? Colors.white24
                                                : Colors.black26),
                                        fontSize: 7,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Row 2: Time chips side-by-side
                              Row(
                                children: [
                                  _timeChip(
                                      'ON',
                                      onTime,
                                      isScheduled ? activeOnColor : null,
                                      isDark),
                                  const SizedBox(width: 8),
                                  _timeChip(
                                      'OFF',
                                      offTime,
                                      isScheduled ? activeOffColor : null,
                                      isDark),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _timeChip(String label, String time, Color? activeColor, bool isDark) {
    final isActive = activeColor != null;
    final bool isActuallySet =
        time != '--:--' && time.toUpperCase() != 'DISABLED';

    final Color chipBgColor = isActive
        ? activeColor.withOpacity(0.08)
        : (isDark
            ? Colors.white.withOpacity(0.02)
            : Colors.black.withOpacity(0.02));
    final Color chipBorderColor = isActive
        ? activeColor.withOpacity(0.2)
        : (isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.03));
    final Color textColor =
        isActive ? activeColor : (isDark ? Colors.white30 : Colors.black38);

    final IconData icon =
        label == 'ON' ? Icons.play_arrow_rounded : Icons.stop_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: chipBorderColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isActive
                ? (label == 'ON'
                    ? const Color(0xFF6CC042)
                    : const Color(0xFFEF4444))
                : textColor.withOpacity(0.4),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: textColor.withOpacity(isActive ? 0.6 : 0.4),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isActuallySet ? time : '--:--',
            style: GoogleFonts.outfit(
              color: isActive
                  ? (isDark ? Colors.white : Colors.black87)
                  : textColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLunchSection(bool isDark) {
    final String start = _lunchOn;
    final String end = _lunchOff;
    final bool isScheduled = start != '--:--' &&
        end != '--:--' &&
        start.toUpperCase() != 'DISABLED' &&
        end.toUpperCase() != 'DISABLED';

    return GestureDetector(
      onTap: null, // Disabled as per user request
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF26213A) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Header with Orange Icon and 1H Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.restaurant_rounded,
                      color: Colors.orange, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  'Lunch Schedule',
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // 1H Duration Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '1H DURATION',
                    style: GoogleFonts.outfit(
                      color: Colors.orange,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // The Horizontal Timeline Bar Row (Yellow to Orange) with clearly visible play/stop icons
            Row(
              children: [
                // START Dot (Yellow) - Play Icon inside
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isScheduled
                        ? Colors.amber
                        : (isDark
                            ? Colors.white.withOpacity(0.04)
                            : Colors.black.withOpacity(0.04)),
                    border: Border.all(
                      color: isScheduled
                          ? Colors.amber
                          : (isDark ? Colors.white10 : Colors.black12),
                      width: 1.5,
                    ),
                    boxShadow: [
                      if (isScheduled)
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 12,
                      color: isScheduled
                          ? Colors.white
                          : (isDark ? Colors.white24 : Colors.black26),
                    ),
                  ),
                ),
                // Gradient Bar (Yellow to Orange)
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: isScheduled
                          ? LinearGradient(
                              colors: [
                                Colors.amber.withOpacity(0.8),
                                Colors.orange.withOpacity(0.8),
                              ],
                            )
                          : LinearGradient(
                              colors: [
                                isDark
                                    ? Colors.white.withOpacity(0.05)
                                    : Colors.black.withOpacity(0.05),
                                isDark
                                    ? Colors.white.withOpacity(0.03)
                                    : Colors.black.withOpacity(0.03),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // END Dot (Orange) - Stop Icon inside
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isScheduled
                        ? Colors.orange
                        : (isDark
                            ? Colors.white.withOpacity(0.04)
                            : Colors.black.withOpacity(0.04)),
                    border: Border.all(
                      color: isScheduled
                          ? Colors.orange
                          : (isDark ? Colors.white10 : Colors.black12),
                      width: 1.5,
                    ),
                    boxShadow: [
                      if (isScheduled)
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.stop_rounded,
                      size: 11,
                      color: isScheduled
                          ? Colors.white
                          : (isDark ? Colors.white24 : Colors.black26),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Time Labels Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isScheduled ? start : 'DISABLED',
                  style: GoogleFonts.outfit(
                    color: isScheduled
                        ? Colors.amber
                        : (isDark ? Colors.white24 : Colors.black26),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  isScheduled ? end : 'DISABLED',
                  style: GoogleFonts.outfit(
                    color: isScheduled
                        ? Colors.orange
                        : (isDark ? Colors.white24 : Colors.black26),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lunchTimeItem(String label, String time, bool isDark) {
    final bool isSet = time != '--:--' && time.toUpperCase() != 'DISABLED';
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            color: isDark ? Colors.white24 : Colors.black26,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isSet ? time : 'DISABLED',
          style: GoogleFonts.outfit(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildAutoBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF6CC042).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'AUTO',
        style: GoogleFonts.outfit(
          color: const Color(0xFF6CC042),
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showSchedulePicker(bool isDark) {
    // Navigate to the new SIRIS 2.0 Schedule Calendar Page with day-wise support
    final mqtt = MqttService();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduleCalendarPage(
          deviceName: _selectedEquipmentName,
          initialState: mqtt.lastState,
        ),
      ),
    );
  }

  Future<void> _publishMqttSchedule(
      String type, int index, String? time) async {
    if (mounted) {
      setState(() {
        if (type == 'SCH_ON') {
          if (index >= 1 && index <= _dynamicSchedules.length) {
            _dynamicSchedules[index - 1]['on'] = time!;
            if (index == 1) _scheduleOn1 = time;
            if (index == 2) _scheduleOn2 = time;
            if (index == 3) _scheduleOn3 = time;
          }
        }
        if (type == 'SCH_OFF') {
          if (index >= 1 && index <= _dynamicSchedules.length) {
            _dynamicSchedules[index - 1]['off'] = time!;
            if (index == 1) _scheduleOff1 = time;
            if (index == 2) _scheduleOff2 = time;
            if (index == 3) _scheduleOff3 = time;
          }
        }
        if (type == 'LUNCH_ON') _lunchOn = time!;
        if (type == 'LUNCH_OFF') _lunchOff = time!;
        if (type == 'SCH_CLEAR') {
          if (index >= 1 && index <= _dynamicSchedules.length) {
            _dynamicSchedules[index - 1]['on'] = '--:--';
            _dynamicSchedules[index - 1]['off'] = '--:--';
            if (index == 1) {
              _scheduleOn1 = '--:--';
              _scheduleOff1 = '--:--';
            }
            if (index == 2) {
              _scheduleOn2 = '--:--';
              _scheduleOff2 = '--:--';
            }
            if (index == 3) {
              _scheduleOn3 = '--:--';
              _scheduleOff3 = '--:--';
            }
          }
          if (index == 99) {
            _lunchOn = '--:--';
            _lunchOff = '--:--';
          }
        }
        if (type == 'SCH_CLEAR_ALL') {
          for (var s in _dynamicSchedules) {
            s['on'] = '--:--';
            s['off'] = '--:--';
          }
          _scheduleOn1 = '--:--';
          _scheduleOff1 = '--:--';
          _scheduleOn2 = '--:--';
          _scheduleOff2 = '--:--';
          _scheduleOn3 = '--:--';
          _scheduleOff3 = '--:--';
          _lunchOn = '--:--';
          _lunchOff = '--:--';
        }
      });
    }

    String payloadStr = '';
    if (type == 'SCH_CLEAR_ALL') {
      payloadStr = 'SCH_CLEAR';
    } else if (type == 'SCH_CLEAR') {
      payloadStr = index != 99 ? 'SCH_CLEAR$index' : 'SCH_CLEAR_LUNCH';
    } else {
      payloadStr =
          type.startsWith('LUNCH') ? '$type:$time' : '$type$index:$time';
    }

    // Publish to daily schedule topic using unified topic generator
    _publishMqttCommand(payloadStr,
        topic: _getDeviceTopic('schedule'), allowOffline: true);
  }

  void _showOfflineWarning() {
    if (!mounted) return;

    // Only show if this route is currently active to prevent it showing "outside"
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    _messenger?.hideCurrentSnackBar();
    _messenger?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  color: Color(0xFFEF4444), size: 18),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connection Lost',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      )),
                  Text('Device is currently unreachable',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white60,
                        fontWeight: FontWeight.w400,
                      )),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1B172E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
              color: const Color(0xFFEF4444).withOpacity(0.2), width: 1.5),
        ),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 30),
        action: SnackBarAction(
          label: 'RE-SYNC',
          textColor: const Color(0xFFEF4444),
          onPressed: () {
            _setupPersistentMqtt();
          },
        ),
      ),
    );
  }
}

class _ChartData {
  _ChartData(this.time, this.temp);
  final DateTime time;
  final double temp;
}

// Background parser for chart data to prevent UI thread blocking
List<_ChartData> _parseChartDataInBackground(String responseBody) {
  try {
    final data = jsonDecode(responseBody);
    final List<dynamic> params = data['data']?['parameters'] ?? [];
    List<dynamic> points = [];
    if (params.isNotEmpty) {
      points = params[0]['values'] ?? [];
    }

    int step = 1;
    if (points.length > 150) {
      step = points.length ~/ 150;
    }

    final List<_ChartData> result = [];
    for (int i = 0; i < points.length; i += step) {
      final p = points[i];
      final timeStr = p['time']?.toString() ?? DateTime.now().toString();
      final val = double.tryParse(p['value']?.toString() ?? '0.0') ?? 0.0;
      result.add(_ChartData(DateTime.parse(timeStr).toLocal(), val));
    }
    return result;
  } catch (e) {
    return [];
  }
}

class _TrendsPage extends StatefulWidget {
  final bool isDark;
  final String systemId;
  final String systemName;
  final String systemShortId;
  final String equipmentId;
  final String equipmentName;
  final String equipmentTypeId;
  final String equipmentShortId;
  final String companyId;
  final String siteId;
  final String bucket;

  const _TrendsPage({
    required this.isDark,
    required this.systemId,
    required this.systemName,
    required this.systemShortId,
    required this.equipmentId,
    required this.equipmentName,
    required this.equipmentTypeId,
    required this.equipmentShortId,
    required this.companyId,
    required this.siteId,
    required this.bucket,
  });

  @override
  State<_TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<_TrendsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<dynamic> _parameters = [];
  String? _selectedParamId;
  List<_ChartData> _chartData = [];
  bool _isLoading = true;
  bool _isChartLoading = false;
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ),
    end: DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ),
  );

  @override
  void initState() {
    super.initState();
    debugPrint(
      'ðŸ“Š TRENDS OPENED WITH: ID=${widget.equipmentId}, ShortId=${widget.equipmentShortId}, TypeId=${widget.equipmentTypeId}',
    );
    _fetchParameters();
  }

  Future<void> _fetchParameters() async {
    final token = await AuthService.getCookieHeader() ?? '';
    final url =
        '${AppConfig.provisionBaseUrl}/systems/parameters/${widget.equipmentTypeId}'
        '?companyId=${widget.companyId}&siteId=${widget.siteId}&bucket=${widget.bucket}';

    debugPrint('ðŸ“Š FETCH PARAMETERS URL: $url');
    debugPrint('ðŸ”‘ TOKEN STATUS: ${token.isNotEmpty ? "PRESET" : "MISSING"}');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
        },
      );
      debugPrint('ðŸ“¥ RESPONSE STATUS: ${response.statusCode}');
      debugPrint('ðŸ“¦ RESPONSE BODY: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _parameters = data['data'] ?? [];
          if (_parameters.isNotEmpty) {
            // Smart auto-select: Try to find a temperature or status parameter first
            final smartIndex = _parameters.indexWhere((p) {
              final name = p['name']?.toString().toLowerCase() ?? '';
              return name.contains('temp') ||
                  name.contains('status') ||
                  name.contains('on/off');
            });
            _selectedParamId = _parameters[smartIndex != -1 ? smartIndex : 0]
                    ['shortId']
                ?.toString();
            _fetchChartData();
          }
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('âŒ Error fetching parameters: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchChartData() async {
    if (_selectedParamId == null) return;

    setState(() => _isChartLoading = true);
    final token = await AuthService.getCookieHeader() ?? '';

    final startTime = DateTime(
      _dateRange.start.year,
      _dateRange.start.month,
      _dateRange.start.day,
      0,
      0,
      0,
    ).toUtc().toIso8601String();
    final endTime = DateTime(
      _dateRange.end.year,
      _dateRange.end.month,
      _dateRange.end.day,
      23,
      59,
      59,
    ).toUtc().toIso8601String();

    final url = '${AppConfig.provisionBaseUrl}/parameters/chart-data'
        '?startTime=$startTime&endTime=$endTime'
        '&parameterShortIds=$_selectedParamId'
        '&systemId=${widget.systemId}'
        '&equipmentShortId=${widget.equipmentShortId}'
        '&bucket=${widget.bucket}&companyId=${widget.companyId}&siteId=${widget.siteId}';

    debugPrint('ðŸ“ˆ FETCH CHART URL: $url');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
        },
      );
      debugPrint('ðŸ“Š CHART STATUS: ${response.statusCode}');

      if (response.statusCode == 200) {
        final points = _parseChartDataInBackground(response.body);

        if (mounted) {
          setState(() {
            _chartData = points;
            _isChartLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('âŒ Error fetching chart data: $e');
      if (mounted) setState(() => _isChartLoading = false);
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _dateRange,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: widget.isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Color(0xFF6CC042),
                    onPrimary: Colors.white,
                    surface: Color(0xFF1B172E),
                    onSurface: Colors.white,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFF6CC042),
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _dateRange = picked);
      _fetchChartData();
    }
  }

  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return DateFormat('MMM dd').format(date);
  }

  IconData _getPickerIcon() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final start = DateTime(
      _dateRange.start.year,
      _dateRange.start.month,
      _dateRange.start.day,
    );
    final end = DateTime(
      _dateRange.end.year,
      _dateRange.end.month,
      _dateRange.end.day,
    );

    if (start == end) {
      if (start == today) return Icons.today_rounded;
      if (start == yesterday) return Icons.history_rounded;
    }
    return Icons.calendar_today_rounded;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = widget.isDark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1B172E) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              'Analytics & Trends',
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.systemName,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF6CC042),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.white54 : Colors.black54,
                    size: 12,
                  ),
                ),
                Text(
                  widget.equipmentName,
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? _buildFullPageTrendsSkeleton(isDark)
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.05)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedParamId,
                              dropdownColor: isDark
                                  ? const Color(0xFF2D264D)
                                  : Colors.white,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Color(0xFF6CC042),
                              ),
                              style: GoogleFonts.poppins(
                                color: isDark ? Colors.white : Colors.black,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              items: _parameters
                                  .map(
                                    (p) => DropdownMenuItem<String>(
                                      value: p['shortId']?.toString(),
                                      child: Text(
                                        p['name']?.toString() ?? 'Unknown',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedParamId = val);
                                  _fetchChartData();
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _selectDateRange,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6CC042).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF6CC042).withOpacity(0.3),
                            ),
                          ),
                          child: Icon(
                            _getPickerIcon(),
                            color: const Color(0xFF6CC042),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    height: 300,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: _isChartLoading
                        ? _buildChartSkeleton(isDark)
                        : _chartData.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.query_stats_rounded,
                                      color: Colors.white.withOpacity(0.1),
                                      size: 48,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No Data Available',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white.withOpacity(0.2),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : SfCartesianChart(
                                margin: EdgeInsets.zero,
                                plotAreaBorderWidth: 0,
                                primaryXAxis: DateTimeAxis(
                                  dateFormat: DateFormat('h:mm a'),
                                  majorGridLines:
                                      const MajorGridLines(width: 0),
                                  axisLine: const AxisLine(width: 0),
                                  labelStyle: GoogleFonts.poppins(
                                    color: Colors.white24,
                                    fontSize: 9,
                                  ),
                                ),
                                primaryYAxis: NumericAxis(
                                  majorGridLines: MajorGridLines(
                                    width: 1,
                                    color: Colors.white.withOpacity(0.05),
                                    dashArray: const [5, 5],
                                  ),
                                  axisLine: const AxisLine(width: 0),
                                  labelStyle: GoogleFonts.poppins(
                                    color: Colors.white24,
                                    fontSize: 9,
                                  ),
                                ),
                                series: <CartesianSeries<_ChartData, DateTime>>[
                                  AreaSeries<_ChartData, DateTime>(
                                    dataSource: _chartData,
                                    xValueMapper: (_ChartData data, _) =>
                                        data.time,
                                    yValueMapper: (_ChartData data, _) =>
                                        data.temp,
                                    color: const Color(
                                      0xFFD4145A,
                                    ), // Pink/Magenta from image
                                    borderColor: const Color(0xFFFF2D55),
                                    borderWidth: 2,
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFFD4145A)
                                            .withOpacity(0.4),
                                        const Color(0xFFD4145A)
                                            .withOpacity(0.0),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    animationDuration: 0,
                                  ),
                                ],
                                trackballBehavior: TrackballBehavior(
                                  enable: true,
                                  activationMode: ActivationMode.singleTap,
                                  tooltipSettings: InteractiveTooltip(
                                    enable: true,
                                    format: 'point.x : point.y',
                                    color: const Color(0xFFD4145A),
                                    textStyle: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                  ),
                  const SizedBox(height: 24),
                  TrendsTable(
                    isDark: isDark,
                    systemId: widget.systemId,
                    systemShortId: widget.systemShortId,
                    equipmentShortId: widget.equipmentShortId,
                    companyId: widget.companyId,
                    siteId: widget.siteId,
                    bucket: widget.bucket,
                    dateRange: _dateRange,
                    parameters: _parameters,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _infoCard(String label, String val, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.03)
              : Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white24,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              val,
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullPageTrendsSkeleton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          // Dropdown Row Skeleton
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Chart Box Skeleton
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
              borderRadius: BorderRadius.circular(28),
            ),
            child: _buildChartSkeleton(isDark),
          ),
          const SizedBox(height: 24),
          // Info Cards Row Skeleton
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(isDark ? 0.03 : 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(isDark ? 0.03 : 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartSkeleton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              5,
              (index) => Container(
                width: 40,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceControlPage extends StatefulWidget {
  final String equipmentName;
  final double initialTemp;
  final double actualTemp;
  final bool isDark;
  final bool isOnline;

  const _DeviceControlPage({
    required this.equipmentName,
    required this.initialTemp,
    required this.actualTemp,
    required this.isDark,
    required this.isOnline,
  });

  @override
  State<_DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<_DeviceControlPage> {
  double _setTemp = 24.0;
  double _actualTemp = 0.0;
  double _humidity = 45.0;
  bool _isScheduleEnabled = true;
  bool _isLunchEnabled = true;

  // Unified Schedule Variables (Strings)
  String _scheduleOn1 = '--:--';
  String _scheduleOff1 = '--:--';
  String _lunchOn = '--:--';
  String _lunchOff = '--:--';

  @override
  void initState() {
    super.initState();
    _setTemp = widget.initialTemp;
    _actualTemp = widget.actualTemp;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = const Color(0xFF6CC042);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1B172E) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Controls - ${widget.equipmentName}',
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
        child: Column(
          children: [
            const SizedBox(height: 10),
            // Gauge Section
            _InteractiveThermostatGauge(
              setTemp: _setTemp,
              actualTemp: _actualTemp,
              isDark: isDark,
              isOnline: widget.isOnline,
              colorScheme: colorScheme,
              onTempChanged: (newTemp) {
                setState(() => _setTemp = newTemp);
                // In this sub-page, we still publish commands if interaction is enabled
                // _publishMqttCommand('TEMP_CN:${newTemp.toInt()}'); // Needs access to _publishMqttCommand or pass it
              },
              onClearTemp: () {
                setState(() => _setTemp = 24.0);
                // In this state, we don't have direct access to _publishMqttCommand
                // but we update the local state for consistency.
              },
              onDisabledInteraction: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Device is Offline - Check Connection'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            // Plus/Minus Buttons below gauge
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _circleButton(Icons.remove_rounded, isDark, () {
                  setState(() => _actualTemp = math.max(0, _actualTemp - 0.5));
                }, size: 56),
                const SizedBox(width: 40),
                _circleButton(Icons.add_rounded, isDark, () {
                  setState(() => _actualTemp = math.min(40, _actualTemp + 0.5));
                }, size: 56),
              ],
            ),
            const SizedBox(height: 25),

            // Humidity Control
            _buildControlCard(
              title: 'HUMIDITY',
              value: '${_humidity.toInt()}%',
              icon: Icons.water_drop_rounded,
              color: Colors.blueAccent,
              isDark: isDark,
              onIncrement: () =>
                  setState(() => _humidity = math.min(100, _humidity + 5)),
              onDecrement: () =>
                  setState(() => _humidity = math.max(0, _humidity - 5)),
            ),
            const SizedBox(height: 15),

            // Daily Schedule
            _buildTimeCard(
              title: 'DAILY SCHEDULE',
              startTime: _scheduleOn1,
              endTime: _scheduleOff1,
              isEnabled: _isScheduleEnabled,
              color: const Color(0xFFF59E0B),
              isDark: isDark,
              onToggle: (val) => setState(() => _isScheduleEnabled = val),
              onStartTimeTap: () {}, // Disabled as per user request
              onEndTimeTap: () {}, // Disabled as per user request
            ),
            const SizedBox(height: 15),

            // Lunch Break
            _buildTimeCard(
              title: 'LUNCH BREAK',
              startTime: _lunchOn,
              endTime: _lunchOff,
              isEnabled: _isLunchEnabled,
              color: primaryColor,
              isDark: isDark,
              onToggle: (val) => setState(() => _isLunchEnabled = val),
              onStartTimeTap: () {}, // Disabled as per user request
              onEndTimeTap: () {}, // Disabled as per user request
            ),
            const SizedBox(height: 25),

            // SET Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: Save to backend if needed
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'SET',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
  }) {
    final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color.withOpacity(0.6), size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: textColor.withOpacity(0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value,
                style: GoogleFonts.poppins(
                  color: textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Row(
                children: [
                  _circleButton(Icons.remove, isDark, onDecrement),
                  const SizedBox(width: 12),
                  _circleButton(Icons.add, isDark, onIncrement),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard({
    required String title,
    required String startTime,
    required String endTime,
    required bool isEnabled,
    required Color color,
    required bool isDark,
    required ValueChanged<bool> onToggle,
    required VoidCallback onStartTimeTap,
    required VoidCallback onEndTimeTap,
  }) {
    final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Switch.adaptive(
                value: isEnabled,
                onChanged: onToggle,
                activeColor: color,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _timePickerButton(
                  'START',
                  _formatDisplayTime(startTime),
                  isDark,
                  onStartTimeTap,
                ),
              ),
              Container(
                width: 1,
                height: 30,
                color: textColor.withOpacity(0.1),
                margin: const EdgeInsets.symmetric(horizontal: 20),
              ),
              Expanded(
                child: _timePickerButton(
                  'END',
                  _formatDisplayTime(endTime),
                  isDark,
                  onEndTimeTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timePickerButton(
    String label,
    String time,
    bool isDark,
    VoidCallback onTap,
  ) {
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: textColor.withOpacity(0.4),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            time,
            style: GoogleFonts.poppins(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(
    IconData icon,
    bool isDark,
    VoidCallback onTap, {
    double size = 40,
  }) {
    const themeGreen = Color(0xFF6CC042);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: themeGreen.withAlpha(30),
          shape: BoxShape.circle,
          border: Border.all(
            color: themeGreen.withAlpha(120),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: themeGreen.withAlpha(70),
              blurRadius: 14,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: themeGreen,
          size: size * 0.48,
        ),
      ),
    );
  }

  String _formatDisplayTime(String time) {
    if (time == '--:--' || time.isEmpty || !time.contains(':')) return '--:--';
    try {
      final parts = time.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      int displayHour = hour % 12;
      if (displayHour == 0) displayHour = 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return '--:--';
    }
  }
}

class _CustomTimePickerDialog extends StatefulWidget {
  final TimeOfDay initialTime;
  const _CustomTimePickerDialog({required this.initialTime});

  @override
  State<_CustomTimePickerDialog> createState() =>
      _CustomTimePickerDialogState();
}

class _CustomTimePickerDialogState extends State<_CustomTimePickerDialog> {
  late int _hour;
  late int _minute;
  late String _period;
  late final TextEditingController _hourController;
  late final TextEditingController _minuteController;
  final FocusNode _hourFocus = FocusNode();
  final FocusNode _minuteFocus = FocusNode();
  bool _showClock = false;
  bool _editingHour = true;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialTime.hourOfPeriod == 0
        ? 12
        : widget.initialTime.hourOfPeriod;
    _minute = widget.initialTime.minute;
    _period = widget.initialTime.period == DayPeriod.am ? 'AM' : 'PM';
    _hourController = TextEditingController(text: _hour.toString());
    _minuteController = TextEditingController(
      text: _minute.toString().padLeft(2, '0'),
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  void _setHour(int value) {
    _hour = value.clamp(1, 12);
    _hourController.text = _hour.toString();
  }

  void _setMinute(int value) {
    _minute = value.clamp(0, 59);
    _minuteController.text = _minute.toString().padLeft(2, '0');
  }

  void _handleHourInput(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    setState(() {
      _hour = parsed.clamp(1, 12);
      _editingHour = true;
    });
  }

  void _handleMinuteInput(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    setState(() {
      _minute = parsed.clamp(0, 59);
      _editingHour = false;
    });
  }

  void _normalizeInputs() {
    _setHour(int.tryParse(_hourController.text) ?? _hour);
    _setMinute(int.tryParse(_minuteController.text) ?? _minute);
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF2A2446);
    const panelColor = Color(0xFF1B172E);
    const accentColor = Color(0xFF6CC042);

    return Dialog(
      backgroundColor: bgColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Container(
        width: 360,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set Time',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _numberColumn(
                  controller: _hourController,
                  focusNode: _hourFocus,
                  label: 'Hour',
                  maxValue: 12,
                  onChanged: _handleHourInput,
                  onFocused: () => setState(() {
                    _editingHour = true;
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16, left: 8, right: 8),
                  child: Text(
                    ':',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 52,
                      fontWeight: FontWeight.w500,
                      height: 1,
                    ),
                  ),
                ),
                _numberColumn(
                  controller: _minuteController,
                  focusNode: _minuteFocus,
                  label: 'Minute',
                  maxValue: 59,
                  padOnBlur: true,
                  onChanged: _handleMinuteInput,
                  onFocused: () => setState(() {
                    _editingHour = false;
                  }),
                ),
                const SizedBox(width: 12),
                _periodToggle(accentColor),
              ],
            ),
            if (_showClock) ...[
              const SizedBox(height: 28),
              Center(
                child: _clockFace(panelColor, accentColor),
              ),
            ],
            SizedBox(height: _showClock ? 22 : 44),
            Row(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () => setState(() {
                    _showClock = !_showClock;
                    if (_showClock) _editingHour = true;
                  }),
                  icon: Icon(
                    _showClock ? Icons.keyboard : Icons.access_time,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const Spacer(),
                _dialogAction('Cancel', () => Navigator.pop(context)),
                const SizedBox(width: 28),
                _dialogAction('OK', () {
                  _normalizeInputs();
                  int finalHour = _hour % 12;
                  if (_period == 'PM') finalHour += 12;
                  Navigator.pop(
                    context,
                    TimeOfDay(hour: finalHour, minute: _minute),
                  );
                }),
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberColumn({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required int maxValue,
    required ValueChanged<String> onChanged,
    required VoidCallback onFocused,
    bool padOnBlur = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 84,
          height: 80,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1B172E),
            borderRadius: BorderRadius.circular(7),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 2,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              _TimeValueInputFormatter(maxValue: maxValue),
            ],
            onTap: onFocused,
            onChanged: onChanged,
            onEditingComplete: () {
              if (padOnBlur && controller.text.isNotEmpty) {
                final value = int.tryParse(controller.text) ?? 0;
                controller.text =
                    value.clamp(0, maxValue).toString().padLeft(2, '0');
              }
              focusNode.unfocus();
            },
            cursorColor: Colors.white,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w400,
              height: 1,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _periodToggle(Color accentColor) {
    return Container(
      width: 66,
      height: 82,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.16), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _periodButton('AM', accentColor),
          Container(height: 1, color: Colors.white.withOpacity(0.16)),
          _periodButton('PM', accentColor),
        ],
      ),
    );
  }

  Widget _periodButton(String period, Color accentColor) {
    final isSelected = _period == period;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _period = period),
        child: Container(
          alignment: Alignment.center,
          color: isSelected ? accentColor : Colors.transparent,
          child: Text(
            period,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _clockFace(Color panelColor, Color accentColor) {
    return RepaintBoundary(
      child: _ClockPicker(
        isHourMode: _editingHour,
        hour: _hour,
        minute: _minute,
        panelColor: panelColor,
        accentColor: accentColor,
        onModeChanged: (isHourMode) => setState(() {
          _editingHour = isHourMode;
        }),
        onValueChanged: (value) => setState(() {
          if (_editingHour) {
            _setHour(value);
            _editingHour = false;
            _minuteFocus.requestFocus();
          } else {
            _setMinute(value);
          }
        }),
      ),
    );
  }

  Widget _dialogAction(String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF6CC042),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TimeValueInputFormatter extends TextInputFormatter {
  final int maxValue;

  const _TimeValueInputFormatter({required this.maxValue});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final parsed = int.tryParse(newValue.text);
    if (parsed == null) return oldValue;
    if (parsed > maxValue) {
      final clamped = maxValue.toString().padLeft(maxValue == 59 ? 2 : 1, '0');
      return TextEditingValue(
        text: clamped,
        selection: TextSelection.collapsed(offset: clamped.length),
      );
    }
    return newValue;
  }
}

class _ClockPicker extends StatelessWidget {
  final bool isHourMode;
  final int hour;
  final int minute;
  final Color panelColor;
  final Color accentColor;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<int> onValueChanged;

  const _ClockPicker({
    required this.isHourMode,
    required this.hour,
    required this.minute,
    required this.panelColor,
    required this.accentColor,
    required this.onModeChanged,
    required this.onValueChanged,
  });

  void _selectFromOffset(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final delta = localPosition - center;
    if (delta.distance < size.width * 0.16) return;
    final rawDegrees =
        (math.atan2(delta.dy, delta.dx) * 180 / math.pi + 90) % 360;

    if (isHourMode) {
      final value = ((rawDegrees / 30).round() % 12);
      onValueChanged(value == 0 ? 12 : value);
    } else {
      final value = ((rawDegrees / 6).round() % 60);
      onValueChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 242.0,
          242.0,
        );
        final squareSize = Size(size, size);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _selectFromOffset(
            details.localPosition,
            squareSize,
          ),
          onPanStart: (details) => _selectFromOffset(
            details.localPosition,
            squareSize,
          ),
          onPanUpdate: (details) => _selectFromOffset(
            details.localPosition,
            squareSize,
          ),
          onLongPress: () => onModeChanged(!isHourMode),
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _ClockPainter(
                isHourMode: isHourMode,
                hour: hour,
                minute: minute,
                panelColor: panelColor,
                accentColor: accentColor,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ClockPainter extends CustomPainter {
  final bool isHourMode;
  final int hour;
  final int minute;
  final Color panelColor;
  final Color accentColor;

  const _ClockPainter({
    required this.isHourMode,
    required this.hour,
    required this.minute,
    required this.panelColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final labelRadius = radius * 0.78;
    final selectedValue = isHourMode ? hour : minute;
    final selectedStep = isHourMode ? hour % 12 : minute / 5;
    final selectedAngle = selectedStep * math.pi / 6 - math.pi / 2;
    final selectedCenter = Offset(
      center.dx + labelRadius * math.cos(selectedAngle),
      center.dy + labelRadius * math.sin(selectedAngle),
    );

    final bgPaint = Paint()..color = panelColor;
    canvas.drawCircle(center, radius, bgPaint);

    final handPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, selectedCenter, handPaint);
    canvas.drawCircle(center, 5, Paint()..color = accentColor);
    canvas.drawCircle(selectedCenter, 27, Paint()..color = accentColor);

    final values = isHourMode
        ? List.generate(12, (index) => index + 1)
        : List.generate(12, (index) => index * 5);

    for (final value in values) {
      final step = isHourMode ? value % 12 : value / 5;
      final angle = step * math.pi / 6 - math.pi / 2;
      final offset = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );
      final isSelected = value == selectedValue;
      final label =
          isHourMode ? value.toString() : value.toString().padLeft(2, '0');
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: isSelected ? 18 : 16,
            fontWeight: FontWeight.w400,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      painter.paint(
        canvas,
        offset - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ClockPainter oldDelegate) {
    return oldDelegate.isHourMode != isHourMode ||
        oldDelegate.hour != hour ||
        oldDelegate.minute != minute ||
        oldDelegate.panelColor != panelColor ||
        oldDelegate.accentColor != accentColor;
  }
}

class _InteractiveThermostatGauge extends StatefulWidget {
  final double setTemp;
  final double actualTemp;
  final bool isDark;
  final bool isOnline;
  final bool isAnalyzing;
  final ColorScheme colorScheme;
  final ValueChanged<double> onTempChanged;
  final VoidCallback? onClearTemp;
  final VoidCallback? onDisabledInteraction;

  const _InteractiveThermostatGauge({
    Key? key,
    required this.setTemp,
    required this.actualTemp,
    required this.isDark,
    required this.isOnline,
    required this.colorScheme,
    required this.onTempChanged,
    this.onClearTemp,
    this.onDisabledInteraction,
    this.isAnalyzing = false,
  }) : super(key: key);

  @override
  State<_InteractiveThermostatGauge> createState() =>
      _InteractiveThermostatGaugeState();
}

class _InteractiveThermostatGaugeState
    extends State<_InteractiveThermostatGauge> {
  Offset _dragStartOffset = Offset.zero;
  bool _hasPassedThreshold = false;
  Timer? _buttonPressTimer;
  DateTime? _lastTapTime;

  @override
  void dispose() {
    _buttonPressTimer?.cancel();
    super.dispose();
  }

  void _startButtonPressTimer(VoidCallback action) {
    _buttonPressTimer?.cancel();

    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 550)) {
      // Rapid-tap mode: consecutive clicks trigger instantly!
      _lastTapTime = now;
      action();
      return;
    }

    // First click: requires deliberate 180ms firm touch to trigger
    _buttonPressTimer = Timer(const Duration(milliseconds: 180), () {
      _lastTapTime = DateTime.now();
      action();
    });
  }

  void _cancelButtonPressTimer() {
    _buttonPressTimer?.cancel();
  }

  Color _getColorForTemp(double temp) {
    if (temp <= 19) return const Color(0xFFEF4444); // Blue
    if (temp <= 22) return const Color(0xFFF59E0B); // Cyan
    if (temp <= 26) return const Color(0xFF10B981); // Green
    if (temp <= 29) return const Color(0xFFF59E0B); // Orange
    return const Color(0xFFEF4444); // Red
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _getColorForTemp(widget.setTemp);
    // Calculate gauge size to fill available width
    final screenWidth = MediaQuery.of(context).size.width;
    const buttonSize = 44.0;
    const gap = 8.0;
    final gaugeSize =
        (screenWidth - buttonSize * 2 - gap * 2).clamp(240.0, 310.0);
    final fontSize = gaugeSize * 0.165; // scale font with gauge

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Minus Button
        _buildSideControl(
          icon: Icons.remove,
          onTap: () {
            if (widget.isOnline) {
              widget.onTempChanged((widget.setTemp - 1).clamp(16.0, 30.0));
            } else {
              widget.onDisabledInteraction?.call();
            }
          },
          color: widget.isOnline ? activeColor : Colors.grey,
          size: buttonSize,
        ),
        SizedBox(width: gap),
        Container(
          width: gaugeSize,
          height: gaugeSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              if (widget.isDark && widget.isOnline)
                BoxShadow(
                  color: activeColor.withOpacity(0.15),
                  blurRadius: 16,
                  spreadRadius: 4,
                ),
            ],
          ),
          child: CustomPaint(
            size: Size(gaugeSize, gaugeSize),
            painter: _InteractiveThermostatPainter(
              setTemp: widget.setTemp,
              actualTemp: widget.actualTemp,
              isDark: widget.isDark,
              isOnline: widget.isOnline,
              colorScheme: widget.colorScheme,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.isAnalyzing
                        ? 'CHECKING'
                        : (widget.isOnline ? 'ACTUAL' : 'OFFLINE'),
                    style: GoogleFonts.poppins(
                      color: (widget.isAnalyzing
                              ? Colors.amber
                              : (widget.isOnline
                                  ? (widget.isDark
                                      ? Colors.white
                                      : widget.colorScheme.primary)
                                  : Colors.redAccent))
                          .withOpacity(0.4),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.isOnline
                        ? '${widget.actualTemp.toStringAsFixed(1)}\u00b0C'
                        : '0.0\u00b0C',
                    style: GoogleFonts.poppins(
                      color: widget.isOnline
                          ? (widget.isDark
                              ? Colors.white
                              : const Color(0xFF1B172E))
                          : (widget.isDark ? Colors.white30 : Colors.black26),
                      fontSize: fontSize,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: (widget.isOnline ? activeColor : Colors.grey)
                          .withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (widget.isOnline ? activeColor : Colors.grey)
                            .withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SET TEMP',
                          style: GoogleFonts.poppins(
                            color: widget.isOnline ? activeColor : Colors.grey,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.isOnline
                              ? '${widget.setTemp.toInt()}\u00b0C'
                              : '0\u00b0C',
                          style: GoogleFonts.poppins(
                            color: widget.isOnline
                                ? (widget.isDark
                                    ? Colors.white
                                    : const Color(0xFF1B172E))
                                : (widget.isDark
                                    ? Colors.white30
                                    : Colors.black26),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (widget.onClearTemp != null && widget.isOnline) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: widget.onClearTemp,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: activeColor.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                color: activeColor,
                                size: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: gap),
        // Plus Button
        _buildSideControl(
          icon: Icons.add,
          onTap: () {
            if (widget.isOnline) {
              widget.onTempChanged((widget.setTemp + 1).clamp(16.0, 30.0));
            } else {
              widget.onDisabledInteraction?.call();
            }
          },
          color: widget.isOnline ? activeColor : Colors.grey,
          size: buttonSize,
        ),
      ],
    );
  }

  Widget _buildSideControl({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double size = 52,
  }) {
    // Auto-color: green for +, red for −
    final isPlus = icon == Icons.add || icon == Icons.add_rounded;
    final accentColor = widget.isOnline
        ? (isPlus ? const Color(0xFF6CC042) : const Color(0xFFEF4444))
        : Colors.grey;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1B172E),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.3),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Icon(
            icon,
            color: accentColor,
            size: size * 0.45,
          ),
        ),
      ),
    );
  }
}

class _InteractiveThermostatPainter extends CustomPainter {
  final double setTemp;
  final double actualTemp;
  final bool isDark;
  final bool isOnline;
  final ColorScheme colorScheme;

  _InteractiveThermostatPainter({
    required this.setTemp,
    required this.actualTemp,
    required this.isDark,
    required this.isOnline,
    required this.colorScheme,
  });

  Color _getColorForTemp(double temp) {
    if (temp <= 19) return const Color(0xFFEF4444); // Blue
    if (temp <= 22) return const Color(0xFFF59E0B); // Cyan
    if (temp <= 26) return const Color(0xFF10B981); // Green
    if (temp <= 29) return const Color(0xFFF59E0B); // Orange
    return const Color(0xFFEF4444); // Red
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    double tempToAngle(double temp) => (temp / 40) * sweepAngle + startAngle;

    final trackRect = Rect.fromCircle(center: center, radius: radius - 15);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    void drawTrackRange(double start, double end, Color color) {
      final sAngle = tempToAngle(start);
      final swAngle = ((end - start) / 40) * sweepAngle;
      trackPaint.color = color.withOpacity(0.15);
      canvas.drawArc(trackRect, sAngle, swAngle, false, trackPaint);
    }

    drawTrackRange(0, 19, const Color(0xFFEF4444));
    drawTrackRange(19, 22, const Color(0xFFF59E0B));
    drawTrackRange(22, 26, const Color(0xFF6CC042));
    drawTrackRange(26, 29, const Color(0xFFFBBF24));
    drawTrackRange(29, 40, const Color(0xFFEF4444));

    final fullTrackPaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.03)
          : Colors.black.withOpacity(0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    canvas.drawCircle(center, radius - 15, fullTrackPaint);

    // Draw the static gauge lines/arcs...
    final basePaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.05)
          : colorScheme.primary.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(trackRect, startAngle, sweepAngle, false, basePaint);

    // Active Arc for SET TEMP (Dynamic color based on temp when online, grey when offline)
    final activeColor = isOnline
        ? _getColorForTemp(setTemp)
        : (isDark ? Colors.white24 : Colors.black26);
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = isOnline
          ? activeColor.withOpacity(0.2)
          : Colors.transparent // no glow when offline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24 // wider to act as a soft edge
      ..strokeCap = StrokeCap.round;

    final double targetSetTemp = isOnline ? setTemp : 0.0;
    final setSweep = (targetSetTemp / 40) * sweepAngle;
    canvas.drawArc(trackRect, startAngle, setSweep, false, glowPaint);
    canvas.drawArc(trackRect, startAngle, setSweep, false, activePaint);

    // Handle for SET TEMP (Visual indicator only)
    final handleAngle = setSweep + startAngle;
    final handlePos = Offset(
      center.dx + (radius - 15) * math.cos(handleAngle),
      center.dy + (radius - 15) * math.sin(handleAngle),
    );

    // Simple shadow/border instead of expensive blur
    canvas.drawCircle(
      handlePos,
      12, // Handle dot size
      Paint()
        ..color = isOnline ? Colors.white.withOpacity(0.3) : Colors.transparent
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      handlePos,
      10,
      Paint()
        ..color = isOnline
            ? Colors.white
            : (isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1)),
    );
    canvas.drawCircle(handlePos, 6, Paint()..color = activeColor);

    // (Actual Temperature Indicator removed as requested)

    for (int i = 0; i <= 60; i++) {
      final angle = (i / 60) * sweepAngle + startAngle;
      final tickTemp = (i / 60) * 40;
      final isActive = isOnline && (tickTemp <= setTemp);
      final tickPaint = Paint()
        ..color = isActive
            ? activeColor
            : (isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1))
        ..strokeWidth = 1.5;
      final innerR = radius - 45;
      final outerR = radius - 30;
      canvas.drawLine(
        Offset(
          center.dx + innerR * math.cos(angle),
          center.dy + innerR * math.sin(angle),
        ),
        Offset(
          center.dx + outerR * math.cos(angle),
          center.dy + outerR * math.sin(angle),
        ),
        tickPaint,
      );
    }

    final labelPoints = [0, 19, 22, 26, 29, 40];
    for (final p in labelPoints) {
      final angle = tempToAngle(p.toDouble());
      final labelR = radius + 15;
      final textPos = Offset(
        center.dx + labelR * math.cos(angle),
        center.dy + labelR * math.sin(angle),
      );

      final textSpan = TextSpan(
        text: '$p',
        style: GoogleFonts.poppins(
          color: isOnline
              ? Colors.white60
              : (isDark ? Colors.white24 : Colors.black26),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          textPos.dx - textPainter.width / 2,
          textPos.dy - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _InteractiveThermostatPainter oldDelegate) {
    return oldDelegate.setTemp != setTemp ||
        oldDelegate.actualTemp != actualTemp ||
        oldDelegate.isDark != isDark ||
        oldDelegate.isOnline != isOnline;
  }
}

class ScheduleManagerPage extends StatefulWidget {
  final bool isDark;
  final List<Map<String, String>> schedules;
  final Map<String, String> lunch;
  final Function(List<Map<String, String>> updatedSchedules,
      Map<String, String> updatedLunch, bool hasClearedAll) onSave;

  const ScheduleManagerPage({
    super.key,
    required this.isDark,
    required this.schedules,
    required this.lunch,
    required this.onSave,
  });

  @override
  State<ScheduleManagerPage> createState() => _ScheduleManagerPageState();
}

class _ScheduleManagerPageState extends State<ScheduleManagerPage> {
  late List<Map<String, String>> _localSchedules;
  late Map<String, String> _localLunch;
  int _activeTab = 0; // 0: Daily, 1: Lunch
  bool _hasClearedAll = false;

  @override
  void initState() {
    super.initState();
    _localSchedules = widget.schedules
        .take(5)
        .map((s) => Map<String, String>.from(s))
        .toList();
    while (_localSchedules.length < 5) {
      _localSchedules.add({'on': '--:--', 'off': '--:--', 'interval': 'None'});
    }
    _localLunch = Map<String, String>.from(widget.lunch);
  }

  void _addNewSchedule() {
    setState(() {
      _localSchedules.add({'on': '--:--', 'off': '--:--'});
    });
  }

  void _deleteSchedule(int index) {
    setState(() {
      if (index >= 0 && index < _localSchedules.length) {
        _localSchedules.removeAt(index);
      }
    });
  }

  void _handleCommand(String type, int index, String time) {
    setState(() {
      if (type == 'SCH_ON' && index >= 1 && index <= _localSchedules.length) {
        _localSchedules[index - 1]['on'] = time;
      } else if (type == 'SCH_OFF' &&
          index >= 1 &&
          index <= _localSchedules.length) {
        _localSchedules[index - 1]['off'] = time;
      } else if (type == 'LUNCH_ON') {
        _localLunch['on'] = time;
      } else if (type == 'LUNCH_OFF') {
        _localLunch['off'] = time;
      } else if (type == 'SCH_CLEAR') {
        if (index >= 1 && index <= _localSchedules.length) {
          _localSchedules[index - 1]['on'] = '--:--';
          _localSchedules[index - 1]['off'] = '--:--';
        } else if (index == 99) {
          _localLunch['on'] = '--:--';
          _localLunch['off'] = '--:--';
        }
      }
    });
  }

  void _handleClearAll() {
    setState(() {
      _hasClearedAll = true;
      for (var s in _localSchedules) {
        s['on'] = '--:--';
        s['off'] = '--:--';
        s['interval'] = 'None';
      }
      _localLunch['on'] = '--:--';
      _localLunch['off'] = '--:--';
    });
  }

  void _confirmClearAllSchedules() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF131122),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 32,
                    color: Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Are you sure to delete all schedule and lunch break?",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(
                              color: Colors.white.withOpacity(0.06),
                              width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          "Cancel",
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _handleClearAll();
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded,
                                      color: Color(0xFF6CC042), size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "All schedules cleared! Tap SAVE to apply.",
                                      style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: const Color(0xFF131122),
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: const Color(0xFF6CC042)
                                        .withOpacity(0.3),
                                    width: 1.2),
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          "Yes",
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFEF4444),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1C111C),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: const Color(0xFFEF4444).withOpacity(0.3),
            width: 1.2,
          ),
        ),
        elevation: 6,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  bool _validateSchedules() {
    int? parseTimeToMinutes(String? timeStr) {
      if (timeStr == null ||
          timeStr == '--:--' ||
          timeStr.trim().isEmpty ||
          timeStr.toUpperCase() == 'DISABLED') {
        return null;
      }
      final parts = timeStr.split(':');
      if (parts.length != 2) return null;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return null;
      return hour * 60 + minute;
    }

    bool intervalsOverlap(int s1, int e1, int s2, int e2) {
      if (s1 < e1 && s2 < e2) {
        return math.max(s1, s2) < math.min(e1, e2);
      }
      List<List<int>> getSubIntervals(int start, int end) {
        if (start < end) {
          return [
            [start, end]
          ];
        } else {
          return [
            [start, 1440],
            [0, end]
          ];
        }
      }

      final list1 = getSubIntervals(s1, e1);
      final list2 = getSubIntervals(s2, e2);
      for (final i1 in list1) {
        for (final i2 in list2) {
          if (math.max(i1[0], i2[0]) < math.min(i1[1], i2[1])) {
            return true;
          }
        }
      }
      return false;
    }

    for (int i = 0; i < _localSchedules.length; i++) {
      final onStr = _localSchedules[i]['on'];
      final offStr = _localSchedules[i]['off'];

      final start = parseTimeToMinutes(onStr);
      final end = parseTimeToMinutes(offStr);

      if (start != null || end != null) {
        if (start == null || end == null) {
          _showValidationError(
              'Schedule ${i + 1} must have both start and end times set, or be completely cleared.');
          return false;
        }

        if (start == end) {
          _showValidationError(
              'Schedule ${i + 1} cannot start and end at the exact same time.');
          return false;
        }

        // Compare with other daily schedules
        for (int j = i + 1; j < _localSchedules.length; j++) {
          final otherOnStr = _localSchedules[j]['on'];
          final otherOffStr = _localSchedules[j]['off'];

          final startOther = parseTimeToMinutes(otherOnStr);
          final endOther = parseTimeToMinutes(otherOffStr);

          if (startOther != null && endOther != null) {
            if (intervalsOverlap(start, end, startOther, endOther)) {
              _showValidationError(
                  'Schedule ${i + 1} overlaps with Schedule ${j + 1}. Please adjust your timings.');
              return false;
            }
          }
        }
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C1B), // Premium dark background
      // (floatingActionButton removed as requested - exactly 5 schedules shown)
      body: SafeArea(
        child: Column(
          children: [
            // Full Page Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Schedule Manager",
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          "Optimize your device timings",
                          style: GoogleFonts.outfit(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _confirmClearAllSchedules,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFEF4444).withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.delete_outline_rounded,
                            color: Color(0xFFEF4444), size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Tab Selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  _buildTabButton("Schedule", 0),
                  const SizedBox(width: 8),
                  _buildTabButton("Lunch Breaks", 1),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Slots list
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    if (_activeTab == 0) ...[
                      // Daily Schedules
                      if (_localSchedules.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.calendar_today_rounded,
                                  color: Colors.white12, size: 48),
                              const SizedBox(height: 16),
                              Text(
                                "No daily schedules created",
                                style: GoogleFonts.poppins(
                                  color: Colors.white38,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Tap the + button to add a new slot",
                                style: GoogleFonts.poppins(
                                  color: Colors.white24,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        for (int i = 0; i < _localSchedules.length; i++)
                          _buildSlot(
                            context,
                            "DAILY SCHEDULE ${i + 1}",
                            _localSchedules[i]['on']!,
                            _localSchedules[i]['off']!,
                            i + 1,
                            false,
                            const Color(0xFF6CC042),
                          ),
                    ] else ...[
                      // Lunch Break
                      _buildSlot(
                        context,
                        "LUNCH BREAK",
                        _localLunch['on']!,
                        _localLunch['off']!,
                        99,
                        true,
                        const Color(0xFF6CC042),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer action bar
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.06),
                                width: 1.2),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            "CANCEL",
                            style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 0.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            if (!_validateSchedules()) return;

                            widget.onSave(
                                _localSchedules, _localLunch, _hasClearedAll);
                            Navigator.pop(context);

                            // 500ms safety guard check to force dismiss if still visible
                            Future.delayed(const Duration(milliseconds: 500),
                                () {
                              if (context.mounted &&
                                  Navigator.canPop(context)) {
                                Navigator.pop(context);
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6CC042),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            "SAVE",
                            style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final bool isActive = _activeTab == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _activeTab = index),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF6CC042)
                : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFF6CC042).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: isActive ? Colors.white : Colors.white60,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlot(
    BuildContext context,
    String label,
    String on,
    String off,
    int index,
    bool isLunch,
    Color color,
  ) {
    final bool isActive = on != '--:--' || off != '--:--';
    final String cuteLabel = isLunch ? "LUNCH BREAK" : "SCHEDULE $index";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B30).withOpacity(isActive ? 0.4 : 0.2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? const Color(0xFF6CC042).withOpacity(0.35)
              : Colors.white.withOpacity(0.06),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          // Cute status dot indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF6CC042) : Colors.white24,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),

          // Label
          Text(
            cuteLabel,
            style: GoogleFonts.outfit(
              color: isActive ? Colors.white : Colors.white30,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),

          // Start Time Chip
          _timelineItemChip(on, isLunch ? 'LUNCH_ON' : 'SCH_ON', index),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white12,
              size: 10,
            ),
          ),

          // End Time Chip
          _timelineItemChip(off, isLunch ? 'LUNCH_OFF' : 'SCH_OFF', index),

          if (isActive) ...[
            const SizedBox(width: 8),
            Container(
              width: 1.2,
              height: 18,
              color: Colors.white.withOpacity(0.06),
            ),
            const SizedBox(width: 8),
          ],

          // Compact Actions
          if (isActive) ...[
            GestureDetector(
              onTap: () => _handleCommand('SCH_CLEAR', index, ''),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white38,
                  size: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _timelineItemChip(String time, String type, int index) {
    final bool isSet = time != '--:--';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          TimeOfDay initialTime = TimeOfDay.now();
          if (time != '--:--' && time.isNotEmpty && time.contains(':')) {
            try {
              final parts = time.split(':');
              initialTime = TimeOfDay(
                hour: int.parse(parts[0]),
                minute: int.parse(parts[1]),
              );
            } catch (_) {}
          }
          try {
            final picked = await showDialog<TimeOfDay>(
              context: context,
              builder: (_) => _CustomTimePickerDialog(initialTime: initialTime),
            );
            if (picked != null) {
              final formatted =
                  "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
              _handleCommand(type, index, formatted);
            }
          } catch (e) {
            debugPrint("Error showing time picker: $e");
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: isSet
                ? const Color(0xFF6CC042).withOpacity(0.08)
                : Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSet
                  ? const Color(0xFF6CC042).withOpacity(0.3)
                  : Colors.white.withOpacity(0.06),
              width: 1.0,
            ),
          ),
          child: Text(
            _formatDisplayTime(time),
            style: GoogleFonts.outfit(
              color: isSet ? Colors.white : Colors.white30,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  String _formatDisplayTime(String time) {
    if (time == '--:--' || time.isEmpty || !time.contains(':')) return '--:--';
    try {
      final parts = time.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      int displayHour = hour % 12;
      if (displayHour == 0) displayHour = 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return '--:--';
    }
  }
}
