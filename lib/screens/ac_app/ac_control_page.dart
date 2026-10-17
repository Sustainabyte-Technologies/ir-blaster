import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:ui';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';
import 'package:ir_blaster_ac/screens/bluetooth_scanner_page.dart';
import 'package:ir_blaster_ac/screens/widgets/wifi_management_dialog.dart';

class ACControlPage extends StatefulWidget {
  final String? deviceName;
  final String? systemId;
  final String? systemShortId;

  const ACControlPage({
    super.key,
    this.deviceName,
    this.systemId,
    this.systemShortId,
  });

  @override
  State<ACControlPage> createState() => _ACControlPageState();
}

class _ACControlPageState extends State<ACControlPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final MqttService _mqtt = MqttService();
  late AnimationController _pulseCtrl;
  late AnimationController _fanRotationCtrl;

  // Local UI state (updated from MQTT snapshots)
  bool _isConnected = false;
  bool get _isControlAvailable => _isActive || _mqtt.isBluetoothConnected;
  bool _isActive = false;
  bool _isPowerOn = false;
  int _setTemp = 24;
  int _currentTemp = 0;
  int _humidity = 0;
  bool _irOnLearned = true;
  bool _irOffLearned = true;

  // Equipment selection state
  List<Map<String, dynamic>> _equipmentsData = [];
  bool _isLoadingEquipments = false;
  Timer? _loadingTimeoutTimer;
  String _selectedEquipmentName = '';
  String _selectedEquipmentId = '';
  String _selectedEquipmentShortId = '';
  String _activeDeviceId = ''; // Target MQTT device ID (IMEI)
  String _activeDeviceImei = ''; // Target physical IMEI

  String _schOn1 = 'DISABLED', _schOff1 = 'DISABLED';
  String _schOn2 = 'DISABLED', _schOff2 = 'DISABLED';
  String _schOn3 = 'DISABLED', _schOff3 = 'DISABLED';
  String _schOn4 = 'DISABLED', _schOff4 = 'DISABLED';
  String _schOn5 = 'DISABLED', _schOff5 = 'DISABLED';
  String _lunchOn = 'DISABLED', _lunchOff = 'DISABLED';
  List<int> _visibleSlots = [1, 2, 3];

  // Optimistic UI overrides for schedule switches (survives all rebuilds)
  final Map<int, bool> _schSwitchOverrides = {};
  final Map<int, Timer> _schOverrideTimers = {};

  // Schedule state cache & overrides for slow MQTT response protection
  final Map<int, bool> _schEnabled = {};
  final Map<int, String> _savedSchOn = {};
  final Map<int, String> _savedSchOff = {};
  final Map<int, String> _savedSchDays = {
    0: 'ALL',
    1: 'ALL',
    2: 'ALL',
    3: 'ALL',
    4: 'ALL',
    5: 'ALL',
  };
  final Map<int, DateTime> _userSchOverrideTime = {};

  String get _effectiveDeviceId {
    if (_activeDeviceId.isNotEmpty) return _activeDeviceId;
    if (widget.systemShortId != null && widget.systemShortId!.isNotEmpty) {
      return widget.systemShortId!;
    }
    return AppConfig.mqttDeviceId;
  }

  bool _isStateForActiveDevice(SirisDeviceState state) {
    if (_activeDeviceId.isEmpty && _selectedEquipmentId.isEmpty) return true;
    final sDevId = state.deviceId.toLowerCase().trim();
    final sImei = state.imei.toLowerCase().trim();

    // If telemetry payload has no device identifier, only accept if there is no active target or exactly 1 device
    if (sDevId.isEmpty && sImei.isEmpty) {
      return _activeDeviceId.isEmpty && _selectedEquipmentId.isEmpty;
    }

    final activeId = _activeDeviceId.toLowerCase().trim();
    final activeImei = _activeDeviceImei.toLowerCase().trim();
    final shortId = _selectedEquipmentShortId.toLowerCase().trim();
    final equipId = _selectedEquipmentId.toLowerCase().trim();
    final equipName = _selectedEquipmentName.toLowerCase().trim();
    final sysShort = (widget.systemShortId ?? '').toLowerCase().trim();

    final directMatch = (activeId.isNotEmpty && (sDevId == activeId || sImei == activeId)) ||
        (activeImei.isNotEmpty && (sDevId == activeImei || sImei == activeImei)) ||
        (shortId.isNotEmpty && (sDevId == shortId || sImei == shortId)) ||
        (equipId.isNotEmpty && (sDevId == equipId || sImei == equipId)) ||
        (equipName.isNotEmpty && (sDevId == equipName || sImei == equipName)) ||
        (sysShort.isNotEmpty && (sDevId == sysShort || sImei == sysShort));

    if (directMatch) return true;

    for (var eq in _equipmentsData) {
      final eqId = (eq['id'] ?? eq['Id'] ?? eq['equipmentId'] ?? eq['EquipmentId'] ?? '').toString().toLowerCase().trim();
      final eqShort = (eq['shortId'] ?? eq['ShortId'] ?? '').toString().toLowerCase().trim();
      final eqImei = (eq['imei'] ?? eq['Imei'] ?? '').toString().toLowerCase().trim();
      final eqName = (eq['equipmentName'] ?? eq['name'] ?? eq['EquipmentName'] ?? '').toString().toLowerCase().trim();

      final isCurrentSelected = (equipId.isNotEmpty && eqId == equipId) ||
          (shortId.isNotEmpty && eqShort == shortId) ||
          (activeId.isNotEmpty && (eqImei == activeId || eqShort == activeId || eqId == activeId));

      if (isCurrentSelected) {
        if ((sDevId.isNotEmpty && (sDevId == eqId || sDevId == eqShort || sDevId == eqImei || sDevId == eqName)) ||
            (sImei.isNotEmpty && (sImei == eqId || sImei == eqShort || sImei == eqImei || sImei == eqName))) {
          return true;
        }
      }
    }

    return false;
  }

  bool _isResponseForActiveDevice(SirisResponse resp) {
    if (resp.deviceId == null || resp.deviceId!.isEmpty) {
      return _activeDeviceId.isEmpty && _selectedEquipmentId.isEmpty;
    }
    final rId = resp.deviceId!.toLowerCase().trim();
    final activeId = _activeDeviceId.toLowerCase().trim();
    final activeImei = _activeDeviceImei.toLowerCase().trim();
    final shortId = _selectedEquipmentShortId.toLowerCase().trim();
    final equipId = _selectedEquipmentId.toLowerCase().trim();
    final equipName = _selectedEquipmentName.toLowerCase().trim();
    final sysShort = (widget.systemShortId ?? '').toLowerCase().trim();

    if ((activeId.isNotEmpty && rId == activeId) ||
        (activeImei.isNotEmpty && rId == activeImei) ||
        (shortId.isNotEmpty && rId == shortId) ||
        (equipId.isNotEmpty && rId == equipId) ||
        (equipName.isNotEmpty && rId == equipName) ||
        (sysShort.isNotEmpty && rId == sysShort)) {
      return true;
    }

    for (var eq in _equipmentsData) {
      final eqId = (eq['id'] ?? eq['Id'] ?? eq['equipmentId'] ?? eq['EquipmentId'] ?? '').toString().toLowerCase().trim();
      final eqShort = (eq['shortId'] ?? eq['ShortId'] ?? '').toString().toLowerCase().trim();
      final eqImei = (eq['imei'] ?? eq['Imei'] ?? '').toString().toLowerCase().trim();
      final eqName = (eq['equipmentName'] ?? eq['name'] ?? eq['EquipmentName'] ?? '').toString().toLowerCase().trim();

      final isCurrentSelected = (equipId.isNotEmpty && eqId == equipId) ||
          (shortId.isNotEmpty && eqShort == shortId) ||
          (activeId.isNotEmpty && (eqImei == activeId || eqShort == activeId || eqId == activeId));

      if (isCurrentSelected) {
        if (rId == eqId || rId == eqShort || rId == eqImei || rId == eqName) {
          return true;
        }
      }
    }

    return false;
  }

  Future<void> _loadCachedSchedules() async {
    final devId = _effectiveDeviceId;
    if (devId.isEmpty) return;
    for (int slot = 0; slot <= 5; slot++) {
      final cfg = await LocalCacheService.getScheduleSlotConfig(devId, slot);
      if (cfg != null) {
        if (cfg['isEnabled'] != null) {
          _schEnabled[slot] = cfg['isEnabled'] == true;
        }
        if (cfg['onTime'] != null &&
            cfg['onTime']!.isNotEmpty &&
            cfg['onTime'] != 'DISABLED' &&
            cfg['onTime'] != '--:--') {
          _savedSchOn[slot] = cfg['onTime']!;
        }
        if (cfg['offTime'] != null &&
            cfg['offTime']!.isNotEmpty &&
            cfg['offTime'] != 'DISABLED' &&
            cfg['offTime'] != '--:--') {
          _savedSchOff[slot] = cfg['offTime']!;
        }
        if (cfg['days'] != null &&
            cfg['days']!.isNotEmpty &&
            cfg['days'] != 'DISABLED') {
          _savedSchDays[slot] = cfg['days']!;
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _syncSavedScheduleTimes(SirisDeviceState state) {
    void syncSlot(int slot, String onTime, String offTime, [String? days]) {
      bool changed = false;
      final bool isHwActive = (onTime != 'DISABLED' &&
              onTime.isNotEmpty &&
              onTime != '--:--') ||
          (offTime != 'DISABLED' && offTime.isNotEmpty && offTime != '--:--');

      final overrideTime = _userSchOverrideTime[slot];
      final isOverrideActive = overrideTime != null &&
          DateTime.now().difference(overrideTime).inSeconds < 180;

      // Only adopt hardware onTime if no local user time exists yet, OR if hardware confirms the current saved time
      if (onTime != 'DISABLED' && onTime.isNotEmpty && onTime != '--:--') {
        final bool noLocalOn = _savedSchOn[slot] == null ||
            _savedSchOn[slot]!.isEmpty ||
            _savedSchOn[slot] == 'DISABLED' ||
            _savedSchOn[slot] == '--:--';
        if (noLocalOn || onTime == _savedSchOn[slot]) {
          if (_savedSchOn[slot] != onTime) {
            _savedSchOn[slot] = onTime;
            changed = true;
          }
        }
      }

      // Only adopt hardware offTime if no local user time exists yet, OR if hardware confirms the current saved time
      if (offTime != 'DISABLED' && offTime.isNotEmpty && offTime != '--:--') {
        final bool noLocalOff = _savedSchOff[slot] == null ||
            _savedSchOff[slot]!.isEmpty ||
            _savedSchOff[slot] == 'DISABLED' ||
            _savedSchOff[slot] == '--:--';
        if (noLocalOff || offTime == _savedSchOff[slot]) {
          if (_savedSchOff[slot] != offTime) {
            _savedSchOff[slot] = offTime;
            changed = true;
          }
        }
      }

      // Only sync days from hardware when hardware actually has an active schedule for this slot.
      // When a slot is disabled/cleared, hardware telemetry reports default 'ALL' which must NEVER
      // overwrite the user's custom configured days.
      if (isHwActive &&
          _schEnabled[slot] != false &&
          days != null &&
          days.isNotEmpty &&
          days != 'DISABLED') {
        final bool noLocalDays = _savedSchDays[slot] == null ||
            _savedSchDays[slot]!.isEmpty ||
            _savedSchDays[slot] == 'DISABLED';
        if (noLocalDays || days == _savedSchDays[slot]) {
          if (_savedSchDays[slot] != days) {
            _savedSchDays[slot] = days;
            changed = true;
          }
        }
      }

      // If hardware confirms the exact settings we requested, release the override
      if (isOverrideActive) {
        final bool onMatches =
            _savedSchOn[slot] == null || onTime == _savedSchOn[slot];
        final bool offMatches =
            _savedSchOff[slot] == null || offTime == _savedSchOff[slot];
        final bool daysMatches = days == null || days == _savedSchDays[slot];
        if (onMatches && offMatches && daysMatches) {
          _userSchOverrideTime.remove(slot);
        }
      }

      if (_schEnabled[slot] == null && isHwActive) {
        _schEnabled[slot] = true;
        changed = true;
      }
      if (changed && _effectiveDeviceId.isNotEmpty) {
        LocalCacheService.saveScheduleSlotConfig(
          _effectiveDeviceId,
          slot,
          isEnabled: _schEnabled[slot],
          onTime: _savedSchOn[slot],
          offTime: _savedSchOff[slot],
          days: _savedSchDays[slot],
        );
      }
    }

    syncSlot(1, state.schOn1, state.schOff1, state.schDays1);
    syncSlot(2, state.schOn2, state.schOff2, state.schDays2);
    syncSlot(3, state.schOn3, state.schOff3, state.schDays3);
    syncSlot(4, state.schOn4, state.schOff4, state.schDays4);
    syncSlot(5, state.schOn5, state.schOff5, state.schDays5);
    syncSlot(0, state.lunchOn, state.lunchOff, state.lunchDays);
  }

  Timer? _heartbeatTimer;

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() {
          _isActive = false;
        });
      }
    });
  }

  // Additional state for interactivity mapping to the new UI features
  String _mode = 'Cool';
  String _fanSpeed = 'Auto';
  bool _lightOn = true;
  bool _swingV = false;
  bool _swingH = false;
  bool _isAutomated = false;
  int _autoTemp = 22; // Smart automation temperature threshold (16–30°C)

  // Air Quality mocks (dynamically stable around premium look values)
  final int _tvoc = 0;
  final int _co2 = 0;
  final int _aqi = 0;
  final List<Map<String, dynamic>> _activityLogs = [];

  // Pending command feedback
  bool _pendingPower = false;
  bool _pendingTemp = false;
  bool _userTempOverride = false; // true when user has explicitly changed temp
  bool _hasReceivedInitialState = false;
  DateTime? _lastPowerToggleTime;
  DateTime? _lastUserTempChangeTime;
  Timer? _apiSyncTimer;
  Timer? _apiSyncSecondaryTimer;
  OverlayEntry? _currentTopBanner;
  Timer? _topBannerTimer;

  StreamSubscription? _stateSub;
  StreamSubscription? _responseSub;
  StreamSubscription? _connSub;

  bool _isReconnectingWifi = false;
  String _reconnectingWifiSsid = '';
  Timer? _reconnectingWifiTimeoutTimer;

  Future<void> _loadWifiSsid() async {
    try {
      final creds = await LocalCacheService.getWifiCredentials();
      if (creds['ssid'] != null && creds['ssid']!.isNotEmpty) {
        // SSID tracked via home-page WiFi dialog
      }
    } catch (_) {}
  }

  void _onMqttChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);

    _fanRotationCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();

    _loadWifiSsid();
    _fetchEquipments();
    _loadCachedSchedules();
    _loadAutoTemp();
    _mqtt.addListener(_onMqttChanged);
  }

  Future<void> _loadAutoTemp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _autoTemp = prefs.getInt('auto_temp') ?? 22;
        });
      }
    } catch (_) {}
  }

  Future<void> _connectMqtt() async {
    await _connSub?.cancel();
    await _stateSub?.cancel();
    await _responseSub?.cancel();
    _hasReceivedInitialState = false;
    _userTempOverride = false;
    _isConnected = _mqtt.isConnected;

    final prefs = await SharedPreferences.getInstance();
    final bool localAuto = prefs.getBool('auto_enabled') ?? false;
    _autoTemp = prefs.getInt('auto_temp') ?? 22;

    // Load initial values from the last known state of this device if available
    final initial = _mqtt.getLastStateFor(_activeDeviceId) ??
        (_activeDeviceImei.isNotEmpty
            ? _mqtt.getLastStateFor(_activeDeviceImei)
            : null);

    // Look up equipment in _equipmentsData to determine initial online status
    Map<String, dynamic>? currentEq;
    try {
      currentEq = _equipmentsData.firstWhere((e) {
        final id = (e['id'] ?? e['Id'] ?? e['equipmentId'] ?? e['EquipmentId'] ?? '')
            .toString()
            .toLowerCase();
        final imei = (e['imei'] ?? e['Imei'] ?? '').toString().toLowerCase();
        final sId =
            (e['shortId'] ?? e['ShortId'] ?? '').toString().toLowerCase();
        final activeLower = _activeDeviceId.toLowerCase();
        final imeiLower = _activeDeviceImei.toLowerCase();
        final selectedLower = _selectedEquipmentId.toLowerCase();
        return (selectedLower.isNotEmpty && id == selectedLower) ||
            (activeLower.isNotEmpty && (imei == activeLower || sId == activeLower)) ||
            (imeiLower.isNotEmpty && imei == imeiLower);
      });
    } catch (_) {}

    final bool eqOnlineFromApi = currentEq != null
        ? (currentEq['isOnline'] == true ||
            currentEq['isActive'] == true ||
            (currentEq['onOffStatus'] is Map &&
                (currentEq['onOffStatus']['isOnline'] == true ||
                    currentEq['onOffStatus']['status'] == 'ON' ||
                    currentEq['onOffStatus']['status'] == 'OFF' ||
                    currentEq['onOffStatus']['status'] == 'ACTIVE' ||
                    currentEq['onOffStatus']['status'] == 'ONLINE')))
        : false;

    if (initial != null &&
        (initial.deviceId.toLowerCase() == _activeDeviceId.toLowerCase() ||
            initial.imei.toLowerCase() == _activeDeviceId.toLowerCase() ||
            (_activeDeviceImei.isNotEmpty &&
                initial.imei.toLowerCase() ==
                    _activeDeviceImei.toLowerCase()))) {
      _isActive = initial.isActive;
      if (_isActive) {
        _startHeartbeatTimer();
      } else {
        _heartbeatTimer?.cancel();
        _isPowerOn = false;
        _fanRotationCtrl.stop();
      }
      _isPowerOn = initial.isPowerOn;
      if (initial.setTemp >= 16 && initial.setTemp <= 30) {
        _setTemp = initial.setTemp;
      }
      _currentTemp = initial.currentTemp;
      _humidity = initial.humidity;
      _irOnLearned = initial.irOnLearned;
      _irOffLearned = initial.irOffLearned;
      _isAutomated = localAuto || initial.automate;
      _schOn1 = initial.schOn1;
      _schOff1 = initial.schOff1;
      _schOn2 = initial.schOn2;
      _schOff2 = initial.schOff2;
      _schOn3 = initial.schOn3;
      _schOff3 = initial.schOff3;
      _schOn4 = initial.schOn4;
      _schOff4 = initial.schOff4;
      _schOn5 = initial.schOn5;
      _schOff5 = initial.schOff5;
      _lunchOn = initial.lunchOn;
      _lunchOff = initial.lunchOff;
      _hasReceivedInitialState = true;
    } else {
      // Offline / no telemetry snapshot exists for this specific equipment
      _isActive = eqOnlineFromApi;
      if (currentEq != null) {
        if (currentEq['setTemp'] != null) {
          final sTemp = int.tryParse(currentEq['setTemp'].toString());
          if (sTemp != null && sTemp >= 16 && sTemp <= 30) {
            _setTemp = sTemp;
          }
        }
        if (currentEq['currentTemp'] != null) {
          final cTemp = (currentEq['currentTemp'] as num?)?.toInt() ??
              int.tryParse(currentEq['currentTemp'].toString());
          if (cTemp != null && cTemp > 0) _currentTemp = cTemp;
        }
        if (currentEq['humidity'] != null) {
          final h = (currentEq['humidity'] as num?)?.round() ??
              int.tryParse(currentEq['humidity'].toString()) ??
              double.tryParse(currentEq['humidity'].toString())?.round();
          if (h != null && h > 0) _humidity = h;
        }
        final statusVal = currentEq['onOffStatus'] is Map
            ? currentEq['onOffStatus']['status']?.toString().toUpperCase()
            : currentEq['status']?.toString().toUpperCase();
        if (statusVal == 'ON') {
          _isPowerOn = true;
          _fanRotationCtrl.repeat();
        } else if (statusVal == 'OFF') {
          _isPowerOn = false;
          _fanRotationCtrl.stop();
        }
      }
      if (!_isActive) {
        _heartbeatTimer?.cancel();
        _isPowerOn = false;
        _fanRotationCtrl.stop();
      }
    }

    _connSub = _mqtt.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
      }
    });

    _stateSub = _mqtt.stateStream.listen((state) {
      if (!mounted) return;
      if (!_isStateForActiveDevice(state)) {
        return;
      }
      _startHeartbeatTimer();
      setState(() {
        if (_isLoadingEquipments) {
          _isLoadingEquipments = false;
          _loadingTimeoutTimer?.cancel();
        }
        _isActive = state.isActive;

        // If we are waiting for the device to connect to the new WiFi:
        if (_isReconnectingWifi && state.isActive && _isConnected) {
          if (state.wifiSsid == _reconnectingWifiSsid ||
              state.wifiSsid.isNotEmpty) {
            _isReconnectingWifi = false;
            _reconnectingWifiTimeoutTimer?.cancel();
            _showSnack(
                'Device successfully connected to $_reconnectingWifiSsid!',
                AppColors.online);
          }
        }

        // Dynamically bind to the physical device ID only if active device is unset or fallback.
        final fallbackId = AppConfig.mqttDeviceId.toLowerCase();
        if (_activeDeviceId.isEmpty ||
            _activeDeviceId.toLowerCase() == fallbackId) {
          if (state.deviceId.isNotEmpty &&
              state.deviceId.toLowerCase() != fallbackId) {
            debugPrint(
                '🔄 [UI] Binding active device ID to ${state.deviceId} from hardware telemetry');
            _activeDeviceId = state.deviceId;
            _loadCachedSchedules();
          }
        }

        // Power sync lock: ignore incoming telemetry power state
        // if we are waiting for an ACK (_pendingPower) or if we just toggled
        // the power in the last 6 seconds (to avoid UI reversion lag).
        final secondsSinceToggle = _lastPowerToggleTime == null
            ? 100
            : DateTime.now().difference(_lastPowerToggleTime!).inSeconds;

        if (!_pendingPower && secondsSinceToggle >= 6) {
          _isPowerOn = state.isPowerOn;
          _pendingPower = false;
        } else if (secondsSinceToggle >= 6) {
          _pendingPower = false;
        }

        // Temperature sync logic:
        final secondsSinceTempChange = _lastUserTempChangeTime == null
            ? 100
            : DateTime.now().difference(_lastUserTempChangeTime!).inSeconds;

        if (_userTempOverride || secondsSinceTempChange < 8) {
          // While user override / lock window is active, protect against duplicate or stale MQTT packets
          if (state.setTemp == _setTemp && secondsSinceTempChange >= 4) {
            _userTempOverride = false;
          }
        } else {
          // Sync UI temperature to the actual set temperature reported by the physical device / API
          if (state.setTemp >= 16 && state.setTemp <= 30) {
            _setTemp = state.setTemp;
          }
        }
        if (!_hasReceivedInitialState) {
          _hasReceivedInitialState = true;
        }
        debugPrint(
            '🌡️ [STATE] UI temp=$_setTemp | device set_temp=${state.setTemp} | override=$_userTempOverride | power=$_isPowerOn');
        _currentTemp = state.currentTemp;
        _humidity = state.humidity;
        _syncSavedScheduleTimes(state);
        _irOnLearned = state.irOnLearned;
        _irOffLearned = state.irOffLearned;
        // Keep automation active if either telemetry or local configuration states it's enabled
        _isAutomated =
            state.automate || (prefs.getBool('auto_enabled') ?? _isAutomated);

        if (_currentTemp > 0) {
          final logMsg =
              'Telemetry: Temp ${_currentTemp.toStringAsFixed(1)}°C, Hum ${_humidity.toStringAsFixed(1)}%';
          if (_activityLogs.isEmpty ||
              _activityLogs.first['message'] != logMsg) {
            _addLog(logMsg, AppColors.primary);
          }
        }

        // Sync schedules from state only if active, or retain user-saved times
        if (state.schOn1 != 'DISABLED' && state.schOn1.isNotEmpty) {
          _schOn1 = state.schOn1;
        } else if (_savedSchOn[1] != null && _savedSchOn[1] != 'DISABLED') {
          _schOn1 = _savedSchOn[1]!;
        }
        if (state.schOff1 != 'DISABLED' && state.schOff1.isNotEmpty) {
          _schOff1 = state.schOff1;
        } else if (_savedSchOff[1] != null && _savedSchOff[1] != 'DISABLED') {
          _schOff1 = _savedSchOff[1]!;
        }

        if (state.schOn2 != 'DISABLED' && state.schOn2.isNotEmpty) {
          _schOn2 = state.schOn2;
        } else if (_savedSchOn[2] != null && _savedSchOn[2] != 'DISABLED') {
          _schOn2 = _savedSchOn[2]!;
        }
        if (state.schOff2 != 'DISABLED' && state.schOff2.isNotEmpty) {
          _schOff2 = state.schOff2;
        } else if (_savedSchOff[2] != null && _savedSchOff[2] != 'DISABLED') {
          _schOff2 = _savedSchOff[2]!;
        }

        if (state.schOn3 != 'DISABLED' && state.schOn3.isNotEmpty) {
          _schOn3 = state.schOn3;
        } else if (_savedSchOn[3] != null && _savedSchOn[3] != 'DISABLED') {
          _schOn3 = _savedSchOn[3]!;
        }
        if (state.schOff3 != 'DISABLED' && state.schOff3.isNotEmpty) {
          _schOff3 = state.schOff3;
        } else if (_savedSchOff[3] != null && _savedSchOff[3] != 'DISABLED') {
          _schOff3 = _savedSchOff[3]!;
        }

        if (state.schOn4 != 'DISABLED' && state.schOn4.isNotEmpty) {
          _schOn4 = state.schOn4;
        } else if (_savedSchOn[4] != null && _savedSchOn[4] != 'DISABLED') {
          _schOn4 = _savedSchOn[4]!;
        }
        if (state.schOff4 != 'DISABLED' && state.schOff4.isNotEmpty) {
          _schOff4 = state.schOff4;
        } else if (_savedSchOff[4] != null && _savedSchOff[4] != 'DISABLED') {
          _schOff4 = _savedSchOff[4]!;
        }

        if (state.schOn5 != 'DISABLED' && state.schOn5.isNotEmpty) {
          _schOn5 = state.schOn5;
        } else if (_savedSchOn[5] != null && _savedSchOn[5] != 'DISABLED') {
          _schOn5 = _savedSchOn[5]!;
        }
        if (state.schOff5 != 'DISABLED' && state.schOff5.isNotEmpty) {
          _schOff5 = state.schOff5;
        } else if (_savedSchOff[5] != null && _savedSchOff[5] != 'DISABLED') {
          _schOff5 = _savedSchOff[5]!;
        }

        if (state.lunchOn != 'DISABLED' && state.lunchOn.isNotEmpty) {
          _lunchOn = state.lunchOn;
        } else if (_savedSchOn[0] != null && _savedSchOn[0] != 'DISABLED') {
          _lunchOn = _savedSchOn[0]!;
        }
        if (state.lunchOff != 'DISABLED' && state.lunchOff.isNotEmpty) {
          _lunchOff = state.lunchOff;
        } else if (_savedSchOff[0] != null && _savedSchOff[0] != 'DISABLED') {
          _lunchOff = _savedSchOff[0]!;
        }

        // Sync local animations/modes with MQTT state if online
        if (_isPowerOn) {
          if (_fanRotationCtrl.isAnimating == false) {
            _fanRotationCtrl.repeat();
          }
        } else {
          _fanRotationCtrl.stop();
        }
      });
    });

    _responseSub = _mqtt.responseStream.listen((resp) {
      if (!mounted) return;
      if (!_isResponseForActiveDevice(resp)) {
        debugPrint(
            '🛡️ [ACControl] Ignored response for other device: ${resp.deviceId} (active: $_activeDeviceId)');
        return;
      }
      if (resp.type == SirisResponseType.acOnDone) {
        setState(() {
          _isPowerOn = true;
          _pendingPower = false;
          _fanRotationCtrl.repeat();
        });
        _showSnack('AC turned ON', AppColors.online);
      } else if (resp.type == SirisResponseType.acOffDone) {
        setState(() {
          _isPowerOn = false;
          _pendingPower = false;
          _fanRotationCtrl.stop();
        });
        _showSnack('AC turned OFF', AppColors.offline);
      } else if (resp.type == SirisResponseType.tempSet) {
        final secondsSinceTempChange = _lastUserTempChangeTime == null
            ? 100
            : DateTime.now().difference(_lastUserTempChangeTime!).inSeconds;
        // Suppress stale MQTT string responses during lock window if they conflict with user target
        if (secondsSinceTempChange < 8 &&
            resp.detail != null &&
            resp.detail != '$_setTemp') {
          debugPrint(
              '🛡️ [ACControl] Suppressed stale MQTT tempSet: ${resp.detail} (current UI: $_setTemp)');
          return;
        }
        setState(() => _pendingTemp = false);
        _showSnack('Temperature set to ${resp.detail ?? _setTemp}°C',
            AppColors.coolBlue);
      } else if (resp.type == SirisResponseType.tempError) {
        setState(() => _pendingTemp = false);
        _showSnack('Temperature error: ${resp.detail}', AppColors.offline);
      } else if (resp.type == SirisResponseType.scheduleSet) {
        _showSnack('Schedule updated', AppColors.warning);
      } else if (resp.type == SirisResponseType.scheduleCleared) {
        _showSnack('Schedule cleared', AppColors.heatOrange);
      } else if (resp.type == SirisResponseType.scheduleError) {
        _showSnack('Schedule error: ${resp.detail}', AppColors.offline);
      } else if (resp.type == SirisResponseType.cmdRejected) {
        _showSnack('Command rejected: device not active', AppColors.offline);
      } else if (resp.type == SirisResponseType.cmdError) {
        _showSnack('Command error: ${resp.detail}', AppColors.offline);
      } else if (resp.type == SirisResponseType.automateSet) {
        final isAuto = resp.detail == 'ON';
        setState(() {
          _isAutomated = isAuto;
        });
        _showSnack('Automation turned ${resp.detail}',
            isAuto ? AppColors.online : AppColors.offline);
      } else if (resp.type == SirisResponseType.automateError) {
        _showSnack('Automation error: ${resp.detail}', AppColors.offline);
      } else if (resp.type == SirisResponseType.wifiPrimarySet) {
        _showSnack('Primary WiFi saved: ${resp.detail}', AppColors.online);
      } else if (resp.type == SirisResponseType.wifiSecondarySet) {
        _showSnack('Secondary WiFi saved: ${resp.detail}', AppColors.online);
      } else if (resp.type == SirisResponseType.wifiResetBtOpen) {
        _showSnack('WiFi reset complete!', AppColors.warning);
        final bool isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
        if (isCurrent && mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(
                'WiFi Reset Complete',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
              ),
              content: Text(
                'The device WiFi has been reset and the 60-second Bluetooth provisioning window has reopened.\n\nWould you like to open the Bluetooth scanner to provision it again?',
                style: GoogleFonts.inter(fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel',
                      style: GoogleFonts.inter(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx); // Close alert
                    Navigator.of(context).pop(); // Close WiFi dialog if open
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const BluetoothScannerPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Open Scanner',
                      style: GoogleFonts.inter(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          );
        }
      } else if (resp.type == SirisResponseType.wifiError) {
        _showSnack('WiFi Error: ${resp.detail}', AppColors.offline);
      }
    });

    final connected = await _mqtt.connect(
      deviceId: _activeDeviceId,
      imei: _activeDeviceImei,
    );
    if (mounted) setState(() => _isConnected = connected);
  }

  Future<void> _fetchEquipments() async {
    if (widget.systemId == null) {
      // Standalone mode - use default device ID
      setState(() {
        _activeDeviceId = widget.systemShortId ?? AppConfig.mqttDeviceId;
        _activeDeviceImei = '';
        _selectedEquipmentName = widget.deviceName ?? 'AC Remote';
      });
      _connectMqtt();
      return;
    }

    setState(() => _isLoadingEquipments = true);

    List<Map<String, dynamic>> allEquips = [];
    bool fetchSuccess = false;

    // 1. Try fetching from remote database
    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';

      final queryParams = <String>[];
      if (companyId.isNotEmpty &&
          companyId != 'null' &&
          companyId != 'undefined') {
        queryParams.add('companyId=$companyId');
      }
      if (siteId.isNotEmpty && siteId != 'null' && siteId != 'undefined') {
        queryParams.add('siteId=$siteId');
      }
      final queryString =
          queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
      final url = '${AppConfig.provisionBaseUrl}/equipments$queryString';

      final response = await http.get(
        Uri.parse(url),
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
          allEquips =
              listData.map((e) => Map<String, dynamic>.from(e)).toList();
          fetchSuccess = true;
        }
      } else {
        debugPrint(
            'Equipment API returned HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error fetching equipments from server: $e');
    }

    if (!fetchSuccess && widget.systemId != null) {
      debugPrint(
          '🔄 Falling back to systems/equipment endpoint for system: ${widget.systemId}');
      try {
        final companyId = await AuthService.getCompanyId() ?? '';
        final siteId = await AuthService.getSiteId() ?? '';
        final token = await AuthService.getCookieHeader() ?? '';

        final fallbackUrl =
            '${AppConfig.provisionBaseUrl}/systems/equipment/${widget.systemId}'
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
            allEquips =
                listData.map((e) => Map<String, dynamic>.from(e)).toList();
            fetchSuccess = true;
            debugPrint(
                '✅ Fallback successfully retrieved ${allEquips.length} equipments');
          }
        } else {
          debugPrint(
              'Fallback equipments API returned HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        debugPrint('Error in fallback equipments fetch: $e');
      }
    }

    // 2. Always load and merge locally provisioned devices
    try {
      final prefs = await SharedPreferences.getInstance();
      final localDevicesJson =
          prefs.getString('local_provisioned_devices') ?? '[]';
      final List<dynamic> localList = jsonDecode(localDevicesJson);
      for (var localDev in localList) {
        final localMap = Map<String, dynamic>.from(localDev);
        final String localId = (localMap['id'] ?? '').toString();
        final exists = allEquips.any((e) {
          final eId =
              (e['id'] ?? e['Id'] ?? e['equipmentId'] ?? e['EquipmentId'] ?? '')
                  .toString();
          final eShortId = (e['shortId'] ?? e['ShortId'] ?? '').toString();
          return eId == localId || eShortId == localMap['shortId'];
        });
        if (!exists) {
          allEquips.add(localMap);
        }
      }
    } catch (e) {
      debugPrint('Error loading local devices in ACControlPage: $e');
    }

    // 3. Filter equipments by systemId
    final List<Map<String, dynamic>> filteredList = allEquips.where((e) {
      final sysId = (e['systemId'] ?? e['SystemId'] ?? '').toString();
      return sysId.toLowerCase() == widget.systemId!.toLowerCase();
    }).toList();

    // 4. Fetch live AC statuses from /mqtt/ac/status (matching system_view.dart)
    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';
      String zoneId = await AuthService.getZoneId() ?? '';
      if (zoneId.isEmpty) {
        for (var e in allEquips) {
          final z = (e['zoneId'] ?? e['ZoneId'] ?? '').toString();
          if (z.isNotEmpty && z != '00000000-0000-0000-0000-000000000000') {
            zoneId = z;
            break;
          }
        }
      }
      if (companyId.isNotEmpty && siteId.isNotEmpty && zoneId.isNotEmpty) {
        final statusUrl =
            '${AppConfig.provisionBaseUrl}/mqtt/ac/status?companyId=$companyId&siteId=$siteId&zoneId=$zoneId';
        final statusResponse = await http.get(
          Uri.parse(statusUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Cookie': 'auth_token=$token',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 4));

        if (statusResponse.statusCode == 200) {
          final body = jsonDecode(statusResponse.body);
          final List<dynamic> systemsData = body['systems'] ?? [];
          final Map<String, Map<String, dynamic>> statusByEquipmentId = {};
          final Map<String, Map<String, dynamic>> statusByDevId = {};

          for (var sys in systemsData) {
            final List<dynamic> eqs = sys['equipments'] ?? [];
            for (var eq in eqs) {
              final eqMap = Map<String, dynamic>.from(eq);
              final eqId = (eq['equipmentId'] ??
                      eq['EquipmentId'] ??
                      eq['id'] ??
                      eq['Id'] ??
                      '')
                  .toString()
                  .toLowerCase()
                  .trim();
              final sId = (eq['shortId'] ?? eq['ShortId'] ?? '')
                  .toString()
                  .toLowerCase()
                  .trim();
              final imei = (eq['imei'] ?? eq['Imei'] ?? '')
                  .toString()
                  .toLowerCase()
                  .trim();
              final name = (eq['name'] ?? eq['Name'] ?? '')
                  .toString()
                  .toLowerCase()
                  .trim();

              if (eqId.isNotEmpty) statusByEquipmentId[eqId] = eqMap;
              if (sId.isNotEmpty) statusByDevId[sId] = eqMap;
              if (imei.isNotEmpty) statusByDevId[imei] = eqMap;
              if (name.isNotEmpty) statusByDevId[name] = eqMap;
            }
          }

          for (var eq in filteredList) {
            final eqId = (eq['id'] ??
                    eq['Id'] ??
                    eq['equipmentId'] ??
                    eq['EquipmentId'] ??
                    '')
                .toString()
                .toLowerCase()
                .trim();
            final sId = (eq['shortId'] ?? eq['ShortId'] ?? '')
                .toString()
                .toLowerCase()
                .trim();
            final imei = (eq['imei'] ?? eq['Imei'] ?? '')
                .toString()
                .toLowerCase()
                .trim();
            final name = (eq['name'] ?? eq['Name'] ?? '')
                .toString()
                .toLowerCase()
                .trim();

            final liveInfo = statusByEquipmentId[eqId] ??
                (sId.isNotEmpty ? statusByDevId[sId] : null) ??
                (imei.isNotEmpty ? statusByDevId[imei] : null) ??
                (name.isNotEmpty ? statusByDevId[name] : null);

            if (liveInfo != null) {
              final statusStr =
                  (liveInfo['status'] ?? liveInfo['Status'] ?? 'DISCONNECTED')
                      .toString()
                      .toUpperCase()
                      .trim();
              final bool isOnline = statusStr == 'ON' ||
                  statusStr == 'OFF' ||
                  statusStr == 'ONLINE' ||
                  statusStr == 'CONNECTED' ||
                  statusStr == 'ACTIVE';
              eq['onOffStatus'] = {
                'isOnline': isOnline,
                'status': statusStr,
              };
              eq['isOnline'] = isOnline;
              eq['isActive'] = isOnline;
              if (liveInfo['setTemp'] != null) {
                eq['setTemp'] = liveInfo['setTemp'];
              }
              if (liveInfo['currentTemp'] != null) {
                eq['currentTemp'] = liveInfo['currentTemp'];
              }
              if (liveInfo['hum'] != null) {
                eq['humidity'] = liveInfo['hum'];
              }
            } else {
              eq['onOffStatus'] = {
                'isOnline': false,
                'status': 'DISCONNECTED',
              };
              eq['isOnline'] = false;
              eq['isActive'] = false;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [ACControl] Live status fetch error: $e');
    }

    if (mounted && filteredList.isNotEmpty) {
      setState(() {
        _equipmentsData = List<Map<String, dynamic>>.from(filteredList);
        _isLoadingEquipments = false;
      });
      // Find matching equipment based on passed name or short ID, or fallback to first
      Map<String, dynamic> selected = filteredList.first;
      if (widget.deviceName != null || widget.systemShortId != null) {
        for (var eq in filteredList) {
          final eqName = (eq['name'] ?? eq['Name'] ?? '').toString();
          final eqShortId =
              (eq['shortId'] ?? eq['ShortId'] ?? eq['equipmentShortId'] ?? '')
                  .toString();
          final eqId = (eq['id'] ??
                  eq['Id'] ??
                  eq['equipmentId'] ??
                  eq['EquipmentId'] ??
                  '')
              .toString();
          final eqImei = (eq['imei'] ?? eq['Imei'] ?? '').toString();

          if ((widget.deviceName != null &&
                  eqName.toLowerCase() == widget.deviceName!.toLowerCase()) ||
              (widget.systemShortId != null &&
                  eqShortId.toLowerCase() ==
                      widget.systemShortId!.toLowerCase()) ||
              (widget.systemShortId != null &&
                  eqImei.toLowerCase() ==
                      widget.systemShortId!.toLowerCase()) ||
              (widget.systemShortId != null &&
                  eqId.toLowerCase() == widget.systemShortId!.toLowerCase())) {
            selected = eq;
            break;
          }
        }
      }
      await _onEquipmentSelected(
        (selected['id'] ??
                selected['Id'] ??
                selected['equipmentId'] ??
                selected['EquipmentId'] ??
                '')
            .toString(),
        selected['name']?.toString() ?? 'AC Unit',
        (selected['imei'] ??
                selected['Imei'] ??
                selected['shortId'] ??
                selected['ShortId'] ??
                '')
            .toString(),
      );
      return;
    }

    // Fallback if anything fails and list is empty
    if (mounted) {
      setState(() {
        _activeDeviceId = widget.systemShortId ?? AppConfig.mqttDeviceId;
        _activeDeviceImei = '';
        _selectedEquipmentName = widget.deviceName ?? 'AC Remote';
        _isLoadingEquipments = false;
      });
      _connectMqtt();
    }
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
        final equipData = data['data'];
        if (equipData is List && equipData.isNotEmpty) {
          final first = equipData[0];
          return (first['imei'] ??
                  first['Imei'] ??
                  first['shortId'] ??
                  first['ShortId'] ??
                  '')
              .toString();
        } else if (equipData is Map) {
          return (equipData['imei'] ??
                  equipData['Imei'] ??
                  equipData['shortId'] ??
                  equipData['ShortId'] ??
                  '')
              .toString();
        }
      }
    } catch (e) {
      debugPrint('Error fetching equipment IMEI: $e');
    }
    return '';
  }

  Future<void> _onEquipmentSelected(
    String equipmentId,
    String name,
    String shortId,
  ) async {
    if (_selectedEquipmentId == equipmentId && _activeDeviceId.isNotEmpty) {
      return;
    }

    String? foundImei;
    Map<String, dynamic>? match;
    try {
      match = _equipmentsData.firstWhere(
        (e) =>
            (e['id'] ?? e['Id'] ?? e['equipmentId'] ?? e['EquipmentId'] ?? '')
                .toString() ==
            equipmentId,
      );
      foundImei = (match['imei'] ?? match['Imei'])?.toString();
    } catch (_) {}

    final bool isEqOnline = match != null
        ? (match['isOnline'] == true ||
            match['isActive'] == true ||
            (match['onOffStatus'] is Map &&
                (match['onOffStatus']['isOnline'] == true ||
                    match['onOffStatus']['status'] == 'ON' ||
                    match['onOffStatus']['status'] == 'OFF' ||
                    match['onOffStatus']['status'] == 'ACTIVE' ||
                    match['onOffStatus']['status'] == 'ONLINE')))
        : false;

    _heartbeatTimer?.cancel();

    setState(() {
      _selectedEquipmentId = equipmentId;
      _selectedEquipmentName = name;
      _selectedEquipmentShortId = shortId;
      _isLoadingEquipments = true;
      _isConnected = false;
      _isActive = isEqOnline;
      _userTempOverride = false;
      _lastUserTempChangeTime = null;
      _pendingTemp = false;
      if (match != null) {
        if (match['setTemp'] != null) {
          final sTemp = int.tryParse(match['setTemp'].toString());
          if (sTemp != null && sTemp >= 16 && sTemp <= 30) {
            _setTemp = sTemp;
          }
        }
        if (match['currentTemp'] != null) {
          final cTemp = (match['currentTemp'] as num?)?.toInt() ??
              int.tryParse(match['currentTemp'].toString());
          if (cTemp != null && cTemp > 0) _currentTemp = cTemp;
        }
        if (match['humidity'] != null) {
          final h = (match['humidity'] as num?)?.round() ??
              int.tryParse(match['humidity'].toString()) ??
              double.tryParse(match['humidity'].toString())?.round();
          if (h != null && h > 0) _humidity = h;
        }
        final statusVal = match['onOffStatus'] is Map
            ? match['onOffStatus']['status']?.toString().toUpperCase()
            : match['status']?.toString().toUpperCase();
        if (statusVal == 'ON') {
          _isPowerOn = true;
          _fanRotationCtrl.repeat();
        } else if (statusVal == 'OFF') {
          _isPowerOn = false;
          _fanRotationCtrl.stop();
        }
      }
      if (!_isActive) {
        _isPowerOn = false;
        _fanRotationCtrl.stop();
      }
    });

    final String resolvedDeviceId = foundImei != null && foundImei.isNotEmpty
        ? foundImei
        : await _fetchEquipmentImei(equipmentId);
    String deviceId = resolvedDeviceId.isNotEmpty ? resolvedDeviceId : shortId;

    if (mounted) {
      _loadingTimeoutTimer?.cancel();
      _loadingTimeoutTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted && _isLoadingEquipments) {
          setState(() {
            _isLoadingEquipments = false;
          });
        }
      });

      setState(() {
        _activeDeviceId = deviceId;
        _activeDeviceImei = resolvedDeviceId;
      });
      _connectMqtt();
    }
  }

  String _timeOfDayTo24h(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTo12Hour(String time24) {
    if (time24 == 'DISABLED' || time24.isEmpty) return '08:00 AM';
    try {
      final parts = time24.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final ampm = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      final displayMinute = minute.toString().padLeft(2, '0');
      return '${displayHour.toString().padLeft(2, '0')}:$displayMinute $ampm';
    } catch (_) {
      return time24;
    }
  }

  void _showSnack(String msg, Color color, {IconData? icon}) {
    if (!mounted) return;
    try {
      ScaffoldMessenger.of(context).clearSnackBars();
    } catch (_) {}

    _topBannerTimer?.cancel();
    if (_currentTopBanner != null) {
      try {
        _currentTopBanner!.remove();
      } catch (_) {}
      _currentTopBanner = null;
    }

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final topPadding = MediaQuery.of(context).padding.top;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _TopMessageBarWidget(
        message: msg,
        color: color,
        icon: icon,
        topOffset: topPadding + 10,
        onDismiss: () {
          try {
            entry.remove();
          } catch (_) {}
          if (_currentTopBanner == entry) {
            _currentTopBanner = null;
          }
        },
      ),
    );

    _currentTopBanner = entry;
    overlay.insert(entry);
  }

  void _addLog(String message, Color color) {
    final now = DateTime.now();
    final String hourPart = now.hour > 12
        ? (now.hour - 12).toString()
        : (now.hour == 0 ? "12" : now.hour.toString());
    final String amPm = now.hour >= 12 ? "PM" : "AM";
    final String timeStr =
        "$hourPart:${now.minute.toString().padLeft(2, '0')} $amPm";
    setState(() {
      _activityLogs.insert(0, {
        'message': message,
        'time': timeStr,
        'color': color,
      });
      if (_activityLogs.length > 20) _activityLogs.removeLast();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _topBannerTimer?.cancel();
    if (_currentTopBanner != null) {
      try {
        _currentTopBanner!.remove();
      } catch (_) {}
      _currentTopBanner = null;
    }
    _apiSyncTimer?.cancel();
    _apiSyncSecondaryTimer?.cancel();
    _loadingTimeoutTimer?.cancel();
    _reconnectingWifiTimeoutTimer?.cancel();
    _heartbeatTimer?.cancel();
    _stateSub?.cancel();
    _responseSub?.cancel();
    _connSub?.cancel();
    _pulseCtrl.dispose();
    _fanRotationCtrl.dispose();
    _mqtt.removeListener(_onMqttChanged);
    _mqtt.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [Lifecycle] App resumed. Reconnecting MQTT and SSE...');
      _connectMqtt();
    }
  }

  // ── MQTT Actions ──────────────────────────────────────────────────────

  void _togglePower() {
    if (!_isControlAvailable || (!_isActive && !_mqtt.isBluetoothConnected)) {
      _showSnack('Device is offline. Connect to Wi-Fi to use controls.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded);
      return;
    }

    if (!_irOnLearned || !_irOffLearned) {
      _showSnack('IR signals not learned on device. Sending command...',
          AppColors.warning);
    }

    final wasPowerOn = _isPowerOn;
    _addLog('Power turned ${wasPowerOn ? "OFF" : "ON"}', AppColors.online);
    setState(() {
      _isPowerOn = !wasPowerOn;
      _pendingPower = true;
      _lastPowerToggleTime = DateTime.now();
      _lastUserTempChangeTime = DateTime.now();
      _setTemp = 24;
      // When turning ON: protect 24°C default from firmware's static set_temp:20
      // When turning OFF: allow reset since we force 24 anyway
      _userTempOverride =
          !wasPowerOn; // true when turning ON, false when turning OFF
      _pendingTemp = false;
      if (_isPowerOn) {
        _fanRotationCtrl.repeat();
      } else {
        _fanRotationCtrl.stop();
      }
    });

    if (wasPowerOn) {
      _mqtt.turnAcOff(targetDeviceId: _effectiveDeviceId);
    } else {
      _mqtt.turnAcOn(targetDeviceId: _effectiveDeviceId);
      Future.delayed(const Duration(milliseconds: 300), () {
        _mqtt.setTemperature(24, targetDeviceId: _effectiveDeviceId);
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchActiveEquipmentStatusFromApi() async {
    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';
      String zoneId = await AuthService.getZoneId() ?? '';
      if (zoneId.isEmpty) {
        for (var e in _equipmentsData) {
          final z = (e['zoneId'] ?? e['ZoneId'] ?? '').toString();
          if (z.isNotEmpty && z != '00000000-0000-0000-0000-000000000000') {
            zoneId = z;
            break;
          }
        }
      }
      if (companyId.isEmpty || siteId.isEmpty || zoneId.isEmpty) {
        return null;
      }

      final statusUrl =
          '${AppConfig.provisionBaseUrl}/mqtt/ac/status?companyId=$companyId&siteId=$siteId&zoneId=$zoneId';
      final response = await http.get(
        Uri.parse(statusUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> systemsData = body['systems'] ?? [];
        final targetId = _selectedEquipmentId.toLowerCase().trim();
        final devId = _effectiveDeviceId.toLowerCase().trim();
        final activeImei = _activeDeviceImei.toLowerCase().trim();
        final activeDevId = _activeDeviceId.toLowerCase().trim();
        final shortId = _selectedEquipmentShortId.toLowerCase().trim();
        final equipName = _selectedEquipmentName.toLowerCase().trim();

        for (var sys in systemsData) {
          final List<dynamic> eqs = sys['equipments'] ?? [];
          for (var eq in eqs) {
            final eqMap = Map<String, dynamic>.from(eq);
            final eqId = (eq['equipmentId'] ?? eq['EquipmentId'] ?? eq['id'] ?? eq['Id'] ?? '')
                .toString().toLowerCase().trim();
            final sId = (eq['shortId'] ?? eq['ShortId'] ?? '')
                .toString().toLowerCase().trim();
            final imei = (eq['imei'] ?? eq['Imei'] ?? '')
                .toString().toLowerCase().trim();
            final name = (eq['name'] ?? eq['Name'] ?? '')
                .toString().toLowerCase().trim();

            final bool matches = (targetId.isNotEmpty && (eqId == targetId || sId == targetId)) ||
                (devId.isNotEmpty && (sId == devId || imei == devId || name == devId || eqId == devId)) ||
                (activeDevId.isNotEmpty && (sId == activeDevId || imei == activeDevId || name == activeDevId || eqId == activeDevId)) ||
                (activeImei.isNotEmpty && imei == activeImei) ||
                (shortId.isNotEmpty && sId == shortId) ||
                (equipName.isNotEmpty && name == equipName);

            if (matches) {
              return eqMap;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [ACControl] API status query error: $e');
    }
    return null;
  }

  void _syncTemperatureViaApi() {
    _apiSyncTimer?.cancel();
    _apiSyncSecondaryTimer?.cancel();

    // Query API after brief propagation delay (1.2s) to verify response
    _apiSyncTimer = Timer(const Duration(milliseconds: 1200), () async {
      await _confirmTempFromApi(showFeedback: true);
    });

    // Secondary poll (3.0s) to catch any delayed Redis update from hardware telemetry
    _apiSyncSecondaryTimer = Timer(const Duration(milliseconds: 3000), () async {
      await _confirmTempFromApi(showFeedback: false);
    });
  }

  Future<void> _confirmTempFromApi({bool showFeedback = false}) async {
    final status = await _fetchActiveEquipmentStatusFromApi();
    if (status != null && mounted) {
      final sTempRaw = status['setTemp'];
      if (sTempRaw != null) {
        final apiTemp = int.tryParse(sTempRaw.toString());
        if (apiTemp != null && apiTemp >= 16 && apiTemp <= 30) {
          setState(() {
            _setTemp = apiTemp;
            _pendingTemp = false;
          });
          if (showFeedback) {
            _showSnack('API Response: Set Temp confirmed at $_setTemp°C', AppColors.coolBlue);
            _addLog('API Response: Temperature confirmed at $_setTemp°C', AppColors.coolBlue);
          }
        }
      }
      if (status['currentTemp'] != null) {
        final cTemp = (status['currentTemp'] as num?)?.toInt() ??
            int.tryParse(status['currentTemp'].toString());
        if (cTemp != null && cTemp > 0) {
          setState(() => _currentTemp = cTemp);
        }
      }
      if (status['hum'] != null) {
        final h = (status['hum'] as num?)?.round() ??
            int.tryParse(status['hum'].toString());
        if (h != null && h > 0) {
          setState(() => _humidity = h);
        }
      }
    }
  }

  void _incrementTemp() {
    if (!_isControlAvailable || (!_isActive && !_mqtt.isBluetoothConnected)) {
      _showSnack('Device is offline. Connect to Wi-Fi to use controls.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded);
      return;
    }
    if (_setTemp >= 30) return;
    setState(() {
      _setTemp++;
      _userTempOverride = true;
      _pendingTemp = true;
      _lastUserTempChangeTime = DateTime.now();
    });
    _addLog('Temperature set to $_setTemp°C (via MQTT)', AppColors.coolBlue);
    _mqtt.setTemperature(_setTemp, targetDeviceId: _effectiveDeviceId);
    _syncTemperatureViaApi();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _pendingTemp) {
        setState(() => _pendingTemp = false);
      }
    });
  }

  void _decrementTemp() {
    if (!_isControlAvailable || (!_isActive && !_mqtt.isBluetoothConnected)) {
      _showSnack('Device is offline. Connect to Wi-Fi to use controls.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded);
      return;
    }
    if (_setTemp <= 16) return;
    setState(() {
      _setTemp--;
      _userTempOverride = true;
      _pendingTemp = true;
      _lastUserTempChangeTime = DateTime.now();
    });
    _addLog('Temperature set to $_setTemp°C (via MQTT)', AppColors.coolBlue);
    _mqtt.setTemperature(_setTemp, targetDeviceId: _effectiveDeviceId);
    _syncTemperatureViaApi();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _pendingTemp) {
        setState(() => _pendingTemp = false);
      }
    });
  }

  void _cycleMode() {
    if (!_isControlAvailable || (!_isActive && !_mqtt.isBluetoothConnected)) {
      _showSnack('Device is offline. Connect to Wi-Fi to use controls.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded);
      return;
    }
    if (!_isPowerOn) return;
    final modes = ['Cool', 'Heat', 'Dry', 'Auto'];
    int idx = modes.indexOf(_mode);
    setState(() {
      _mode = modes[(idx + 1) % modes.length];
    });
    _addLog('Mode set to $_mode', AppColors.coolBlue);
    _mqtt.sendControlCommand('SEND:MODE', targetDeviceId: _effectiveDeviceId);
    _showSnack('Mode changed to $_mode', AppColors.primary);
  }

  void _cycleFanSpeed() {
    if (!_isControlAvailable || (!_isActive && !_mqtt.isBluetoothConnected)) {
      _showSnack('Device is offline. Connect to Wi-Fi to use controls.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded);
      return;
    }
    if (!_isPowerOn) return;
    setState(() {
      if (_fanSpeed == 'Auto') {
        _fanSpeed = 'Low';
        _fanRotationCtrl.duration = const Duration(seconds: 4);
        if (_isPowerOn) _fanRotationCtrl.repeat();
      } else if (_fanSpeed == 'Low') {
        _fanSpeed = 'Medium';
        _fanRotationCtrl.duration = const Duration(seconds: 2);
        if (_isPowerOn) _fanRotationCtrl.repeat();
      } else if (_fanSpeed == 'Medium') {
        _fanSpeed = 'High';
        _fanRotationCtrl.duration = const Duration(milliseconds: 800);
        if (_isPowerOn) _fanRotationCtrl.repeat();
      } else {
        _fanSpeed = 'Auto';
        _fanRotationCtrl.duration = const Duration(seconds: 2);
        if (_isPowerOn) _fanRotationCtrl.repeat();
      }
    });
    _addLog('Fan speed set to $_fanSpeed', AppColors.primary);
    _mqtt.sendControlCommand('SEND:MODE',
        targetDeviceId:
            _effectiveDeviceId); // fallback to Mode if Fan key isn't separate
    _showSnack('Fan speed set to $_fanSpeed', AppColors.primary);
  }

  void _toggleSwingV() {
    if (!_isControlAvailable || (!_isActive && !_mqtt.isBluetoothConnected)) {
      _showSnack('Device is offline. Connect to Wi-Fi to use controls.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded);
      return;
    }
    if (!_isPowerOn) return;
    setState(() => _swingV = !_swingV);
    _addLog('Vertical Swing ${_swingV ? 'ON' : 'OFF'}', AppColors.primary);
    _mqtt.sendControlCommand('SEND:SWING', targetDeviceId: _effectiveDeviceId);
    _showSnack('Vertical Swing ${_swingV ? 'On' : 'Off'}', AppColors.primary);
  }

  void _toggleSwingH() {
    if (!_isControlAvailable || (!_isActive && !_mqtt.isBluetoothConnected)) {
      _showSnack('Device is offline. Connect to Wi-Fi to use controls.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded);
      return;
    }
    if (!_isPowerOn) return;
    setState(() => _swingH = !_swingH);
    _addLog('Horizontal Swing ${_swingH ? 'ON' : 'OFF'}', AppColors.primary);
    _mqtt.sendControlCommand('SEND:SWING', targetDeviceId: _effectiveDeviceId);
    _showSnack('Horizontal Swing ${_swingH ? 'On' : 'Off'}', AppColors.primary);
  }

  void _toggleLight() {
    if (!_isControlAvailable || (!_isActive && !_mqtt.isBluetoothConnected)) {
      _showSnack('Device is offline. Connect to Wi-Fi to use controls.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded);
      return;
    }
    if (!_isPowerOn) return;
    setState(() => _lightOn = !_lightOn);
    _addLog('Light ${_lightOn ? 'ON' : 'OFF'}', AppColors.primary);
    _mqtt.sendControlCommand('SEND:LIGHT', targetDeviceId: _effectiveDeviceId);
    _showSnack('Light ${_lightOn ? 'On' : 'Off'}', AppColors.primary);
  }

  void _showTimerDialog(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set Auto-Off Timer',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose when to automatically turn off the AC.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _timerOption(context, '30 min'),
                  const SizedBox(width: 12),
                  _timerOption(context, '1 hour'),
                  const SizedBox(width: 12),
                  _timerOption(context, '2 hours'),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }


  bool _validateLunchSchedule(
      {String? pendingLunchOn, String? pendingLunchOff}) {
    return true;
  }

  void _showEditScheduleDialog(BuildContext context, int slot, String type,
      String currentTime, bool isDark, [StateSetter? setModalState]) {
    String default24h = '08:00';
    if (currentTime.contains('AM') || currentTime.contains('PM')) {
      try {
        final parts = currentTime.split(' ');
        final timePart = parts[0];
        final amPm = parts[1];
        final timeParts = timePart.split(':');
        int hour = int.parse(timeParts[0]);
        final int minute = int.parse(timeParts[1]);
        if (amPm == 'PM' && hour < 12) hour += 12;
        if (amPm == 'AM' && hour == 12) hour = 0;
        default24h =
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    } else {
      default24h = currentTime;
    }

    final timeController = TextEditingController(text: default24h);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final textCol = isDark ? Colors.white : AppColors.textPrimary;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            slot == 0
                ? "Configure Lunch ($type)"
                : "Configure Slot $slot ($type)",
            style:
                GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Time (HH:MM in 24h)",
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: timeController,
                      keyboardType: TextInputType.datetime,
                      style: TextStyle(color: textCol),
                      decoration: InputDecoration(
                        hintText: "e.g. 08:30 or 17:45",
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.access_time_rounded,
                        color: AppColors.primary),
                    onPressed: () async {
                      final TimeOfDay? picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (picked != null) {
                        final String formatted = _timeOfDayTo24h(picked);
                        timeController.text = formatted;
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                final String rawInput = timeController.text.trim().toUpperCase();
                final bool isPm = rawInput.contains('PM');
                final bool isAm = rawInput.contains('AM');
                final String clean = rawInput.replaceAll('AM', '').replaceAll('PM', '').trim();
                final regExp = RegExp(r'^([01]?[0-9]|2[0-3]):[0-5][0-9]$');
                if (!regExp.hasMatch(clean)) {
                  _showSnack(
                      "Invalid time format. Use HH:MM or HH:MM AM/PM", AppColors.offline);
                  return;
                }

                final parts = clean.split(':');
                int hour = int.parse(parts[0]);
                final int minute = int.parse(parts[1]);
                if (isPm && hour < 12) hour += 12;
                if (isAm && hour == 12) hour = 0;

                String time =
                    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

                // Check device connection before sending
                if (!_isControlAvailable || (!_isActive && !_mqtt.isBluetoothConnected)) {
                  _showSnack(
                      'Device is offline. Connect to Wi-Fi to configure schedules.',
                      AppColors.offline,
                      icon: Icons.wifi_off_rounded);
                  return;
                }

                if (slot == 0) {
                  final curLunchDays = _savedSchDays[0] ?? 'ALL';
                  _userSchOverrideTime[0] = DateTime.now();
                  _schEnabled[0] = true;
                  _schSwitchOverrides[0] = true;
                  if (type == 'ON') {
                    _savedSchOn[0] = time;
                    final curLunchOff = (_savedSchOff[0] != null &&
                            _savedSchOff[0] != 'DISABLED' &&
                            _savedSchOff[0]!.isNotEmpty &&
                            _savedSchOff[0] != '--:--')
                        ? _savedSchOff[0]!
                        : '13:00';
                    _savedSchOff[0] = curLunchOff;
                    LocalCacheService.saveScheduleSlotConfig(
                        _effectiveDeviceId, 0,
                        isEnabled: true,
                        onTime: time,
                        offTime: curLunchOff,
                        days: curLunchDays);
                    _mqtt.setLunchOn(time,
                        days: curLunchDays, targetDeviceId: _effectiveDeviceId);
                    _mqtt.publishScheduleJson({
                      'lunch_on': time,
                      'lunch_off': curLunchOff,
                      'lunch_days': curLunchDays,
                    }, targetDeviceId: _effectiveDeviceId);
                    _mqtt.updateLunchOptimistic(
                        lunchOn: time,
                        lunchOff: curLunchOff,
                        days: curLunchDays);
                    setState(() => _lunchOn = time);
                    if (setModalState != null) setModalState(() {});
                  } else {
                    _savedSchOff[0] = time;
                    final curLunchOn = (_savedSchOn[0] != null &&
                            _savedSchOn[0] != 'DISABLED' &&
                            _savedSchOn[0]!.isNotEmpty &&
                            _savedSchOn[0] != '--:--')
                        ? _savedSchOn[0]!
                        : '12:00';
                    _savedSchOn[0] = curLunchOn;
                    LocalCacheService.saveScheduleSlotConfig(
                        _effectiveDeviceId, 0,
                        isEnabled: true,
                        onTime: curLunchOn,
                        offTime: time,
                        days: curLunchDays);
                    _mqtt.setLunchOff(time,
                        days: curLunchDays, targetDeviceId: _effectiveDeviceId);
                    _mqtt.publishScheduleJson({
                      'lunch_on': curLunchOn,
                      'lunch_off': time,
                      'lunch_days': curLunchDays,
                    }, targetDeviceId: _effectiveDeviceId);
                    _mqtt.updateLunchOptimistic(
                        lunchOn: curLunchOn,
                        lunchOff: time,
                        days: curLunchDays);
                    setState(() => _lunchOff = time);
                    if (setModalState != null) setModalState(() {});
                  }
                  Navigator.pop(context);
                  _showSnack('Lunch $type set to ${_formatTo12Hour(time)}',
                      AppColors.primary);
                } else {
                  final fallbackOn = (slot == 2
                      ? '18:00'
                      : slot == 3
                          ? '09:00'
                          : slot == 4
                              ? '07:00'
                              : slot == 5
                                  ? '10:00'
                                  : '08:00');
                  final fallbackOff = (slot == 2
                      ? '23:00'
                      : slot == 3
                          ? '17:00'
                          : slot == 4
                              ? '15:00'
                              : slot == 5
                                  ? '19:00'
                                  : '13:00');
                  final curDays = _savedSchDays[slot] ?? 'ALL';
                  _userSchOverrideTime[slot] = DateTime.now();
                  _schEnabled[slot] = true;
                  if (type == 'ON') {
                    _savedSchOn[slot] = time;
                    final curOff = (_savedSchOff[slot] != null &&
                            _savedSchOff[slot] != 'DISABLED' &&
                            _savedSchOff[slot]!.isNotEmpty &&
                            _savedSchOff[slot] != '--:--')
                        ? _savedSchOff[slot]!
                        : fallbackOff;
                    _savedSchOff[slot] = curOff;
                    LocalCacheService.saveScheduleSlotConfig(
                        _effectiveDeviceId, slot,
                        isEnabled: true,
                        onTime: time,
                        offTime: curOff,
                        days: curDays);
                    _mqtt.setScheduleOn(slot, time,
                        days: curDays, targetDeviceId: _effectiveDeviceId);
                    _mqtt.publishScheduleJson({
                      'on$slot': time,
                      'off$slot': curOff,
                      'days$slot': curDays,
                    }, targetDeviceId: _effectiveDeviceId);
                    _mqtt.updateScheduleOptimistic(
                        slot: slot,
                        onTime: time,
                        offTime: curOff,
                        days: curDays);
                    setState(() {
                      if (slot == 1)
                        _schOn1 = time;
                      else if (slot == 2)
                        _schOn2 = time;
                      else if (slot == 3)
                        _schOn3 = time;
                      else if (slot == 4)
                        _schOn4 = time;
                      else if (slot == 5) _schOn5 = time;
                    });
                    if (setModalState != null) setModalState(() {});
                  } else {
                    _savedSchOff[slot] = time;
                    final curOn = (_savedSchOn[slot] != null &&
                            _savedSchOn[slot] != 'DISABLED' &&
                            _savedSchOn[slot]!.isNotEmpty &&
                            _savedSchOn[slot] != '--:--')
                        ? _savedSchOn[slot]!
                        : fallbackOn;
                    _savedSchOn[slot] = curOn;
                    LocalCacheService.saveScheduleSlotConfig(
                        _effectiveDeviceId, slot,
                        isEnabled: true,
                        onTime: curOn,
                        offTime: time,
                        days: curDays);
                    _mqtt.setScheduleOff(slot, time,
                        days: curDays, targetDeviceId: _effectiveDeviceId);
                    _mqtt.publishScheduleJson({
                      'on$slot': curOn,
                      'off$slot': time,
                      'days$slot': curDays,
                    }, targetDeviceId: _effectiveDeviceId);
                    _mqtt.updateScheduleOptimistic(
                        slot: slot,
                        onTime: curOn,
                        offTime: time,
                        days: curDays);
                    setState(() {
                      if (slot == 1)
                        _schOff1 = time;
                      else if (slot == 2)
                        _schOff2 = time;
                      else if (slot == 3)
                        _schOff3 = time;
                      else if (slot == 4)
                        _schOff4 = time;
                      else if (slot == 5) _schOff5 = time;
                    });
                    if (setModalState != null) setModalState(() {});
                  }
                  Navigator.pop(context);
                  _showSnack(
                      'Schedule $type set to ${_formatTo12Hour(time)} for Slot $slot',
                      AppColors.primary);
                }

                // Query status after a delay to confirm device received the command
                Future.delayed(const Duration(milliseconds: 800), () {
                  _mqtt.getScheduleStatus(targetDeviceId: _effectiveDeviceId);
                });
                // Second query for slower hardware
                Future.delayed(const Duration(milliseconds: 2500), () {
                  _mqtt.getScheduleStatus(targetDeviceId: _effectiveDeviceId);
                });
              },
              child: const Text("Save",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.green)),
            ),
          ],
        );
      },
    );
  }

  String _formatLastSeen(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showSseInfoDialog(BuildContext context, bool isDark) {
    final textCol = isDark ? Colors.white : AppColors.textPrimary;
    final subtextCol = isDark ? Colors.white54 : Colors.black54;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                _mqtt.isSseConnected
                    ? Icons.sensors_rounded
                    : Icons.sensors_off_rounded,
                color: _mqtt.isSseConnected ? Colors.green : Colors.red,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Stream Status',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: textCol,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sseInfoRow(
                  'Connection',
                  _mqtt.isSseConnected ? 'Connected' : 'Disconnected',
                  _mqtt.isSseConnected ? Colors.green : Colors.red,
                  isDark),
              const SizedBox(height: 12),
              _sseInfoRow(
                  'Endpoint', '/mqtt/stream', AppColors.primary, isDark),
              const SizedBox(height: 12),
              _sseInfoRow(
                'Last Data',
                _mqtt.sseLastDataTime != null
                    ? _formatLastSeen(_mqtt.sseLastDataTime!)
                    : 'No data received',
                subtextCol,
                isDark,
              ),
              const SizedBox(height: 12),
              _sseInfoRow(
                  'Device ID',
                  _activeDeviceId.isNotEmpty ? _activeDeviceId : '--',
                  subtextCol,
                  isDark),
              const SizedBox(height: 12),
              _sseInfoRow(
                  'IMEI',
                  _activeDeviceImei.isNotEmpty ? _activeDeviceImei : '--',
                  subtextCol,
                  isDark),
              if (_mqtt.sseLastPayload != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Last Payload',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: subtextCol),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Text(
                      _mqtt.sseLastPayload!,
                      style: GoogleFonts.robotoMono(
                        fontSize: 9,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        );
      },
    );
  }

  List<String> _parseScheduleDaysList(String? rawDays) {
    if (rawDays == null || rawDays.isEmpty || rawDays.toUpperCase() == 'ALL') {
      return ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    }
    if (rawDays.toUpperCase() == 'DISABLED') {
      return [];
    }
    final tokens =
        rawDays.toUpperCase().split(',').map((s) => s.trim()).toList();
    const allDays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final matched = allDays.where((d) => tokens.contains(d)).toList();
    return matched.isEmpty ? List.from(allDays) : matched;
  }

  String _formatScheduleDaysSummary(List<String> activeDays) {
    if (activeDays.length == 7) {
      return 'Everyday (All 7 Days)';
    }
    if (activeDays.length == 5 &&
        activeDays.contains('MON') &&
        activeDays.contains('TUE') &&
        activeDays.contains('WED') &&
        activeDays.contains('THU') &&
        activeDays.contains('FRI')) {
      return 'Weekdays (Mon - Fri)';
    }
    if (activeDays.length == 2 &&
        activeDays.contains('SAT') &&
        activeDays.contains('SUN')) {
      return 'Weekend (Sat, Sun)';
    }
    if (activeDays.isEmpty) {
      return 'No days selected';
    }
    const nameMap = {
      'MON': 'Mon',
      'TUE': 'Tue',
      'WED': 'Wed',
      'THU': 'Thu',
      'FRI': 'Fri',
      'SAT': 'Sat',
      'SUN': 'Sun'
    };
    return activeDays.map((d) => nameMap[d] ?? d).join(', ');
  }

  Widget _buildWeeklyDaysSelector({
    required int slot,
    bool isEnabled = true,
    required bool isDark,
    required StateSetter setModalState,
  }) {
    final rawDays = _savedSchDays[slot] ?? 'ALL';
    final List<String> activeDays = _parseScheduleDaysList(rawDays);
    final String summaryText = _formatScheduleDaysSummary(activeDays);

    const List<String> dayKeys = [
      'MON',
      'TUE',
      'WED',
      'THU',
      'FRI',
      'SAT',
      'SUN'
    ];
    const List<String> dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    void updateDays(List<String> newDays) {
      if (!isEnabled) {
        _showSnack(
          slot == 0
              ? 'Please turn on Lunch Period first'
              : 'Please turn on Schedule Slot $slot first',
          AppColors.warning,
        );
        return;
      }
      if (!_isControlAvailable || (!_isActive && !_mqtt.isBluetoothConnected)) {
        _showSnack(
            'Device is offline. Connect to Wi-Fi to update schedules.',
            AppColors.offline,
            icon: Icons.wifi_off_rounded);
        return;
      }
      final formattedDays = newDays.length == 7
          ? 'ALL'
          : (newDays.isEmpty ? 'DISABLED' : newDays.join(','));
      _userSchOverrideTime[slot] = DateTime.now();
      setModalState(() {
        _savedSchDays[slot] = formattedDays;
      });
      setState(() {
        _savedSchDays[slot] = formattedDays;
      });
      LocalCacheService.saveScheduleSlotConfig(
        _effectiveDeviceId,
        slot,
        days: formattedDays,
      );
      if (slot == 0) {
        _mqtt.publishScheduleJson({
          'lunch_days': formattedDays,
        }, targetDeviceId: _effectiveDeviceId);
        _mqtt.updateLunchOptimistic(days: formattedDays);
      } else {
        _mqtt.publishScheduleJson({
          'days$slot': formattedDays,
        }, targetDeviceId: _effectiveDeviceId);
        _mqtt.updateScheduleOptimistic(slot: slot, days: formattedDays);
      }
      _showSnack(
        slot == 0
            ? 'Lunch schedule days updated ($summaryText)'
            : 'Schedule Slot $slot days updated ($summaryText)',
        AppColors.online,
      );
    }

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 15,
                color: isEnabled
                    ? const Color(0xFF10B981)
                    : (isDark ? Colors.white30 : Colors.black26),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  summaryText,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isEnabled
                        ? (isDark ? Colors.white70 : AppColors.textPrimary)
                        : (isDark ? Colors.white38 : Colors.black38),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(7, (i) {
              final dayKey = dayKeys[i];
              final dayLabel = dayLabels[i];
              final bool isSelected = activeDays.contains(dayKey);

              Color chipBg;
              Color chipText;
              if (isEnabled) {
                chipBg = isSelected
                    ? const Color(0xFF10B981)
                    : (isDark
                        ? const Color(0xFF222B3D)
                        : const Color(0xFFE2E8F0));
                chipText = isSelected
                    ? Colors.white
                    : (isDark ? Colors.white38 : Colors.black38);
              } else {
                chipBg = isSelected
                    ? (isDark
                        ? const Color(0xFF133E32)
                        : const Color(0xFFD1FAE5))
                    : (isDark
                        ? const Color(0xFF161C28)
                        : const Color(0xFFF1F5F9));
                chipText = isSelected
                    ? (isDark
                        ? const Color(0xFF34D399)
                        : const Color(0xFF059669))
                    : (isDark
                        ? const Color(0xFF333E52)
                        : const Color(0xFFA0AEC0));
              }

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 6 ? 6.0 : 0.0),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (!isEnabled) {
                        _showSnack(
                          slot == 0
                              ? 'Please turn on Lunch Period first'
                              : 'Please turn on Schedule Slot $slot first',
                          AppColors.warning,
                        );
                        return;
                      }
                      final nextDays = List<String>.from(activeDays);
                      if (isSelected) {
                        if (nextDays.length > 1) {
                          nextDays.remove(dayKey);
                        } else {
                          _showSnack('At least one day must remain selected',
                              AppColors.warning);
                          return;
                        }
                      } else {
                        nextDays.add(dayKey);
                      }
                      updateDays(nextDays);
                    },
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        dayLabel,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: chipText,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _sseInfoRow(
      String label, String value, Color valueColor, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Future<void> _showSchedulesSheet(BuildContext context, bool isDark) async {
    await _loadCachedSchedules();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        int activeTab = 0;
        final cardBg =
            isDark ? AppColors.backgroundDark : const Color(0xFFF1F5F9);
        final textCol = isDark ? Colors.white : AppColors.textPrimary;
        final subtextCol = isDark ? Colors.white38 : Colors.black45;

        return StreamBuilder<SirisDeviceState>(
          stream: _mqtt.stateStream.where(_isStateForActiveDevice),
          initialData: _mqtt.getLastStateFor(_effectiveDeviceId) ??
              (_mqtt.lastState != null &&
                      _isStateForActiveDevice(_mqtt.lastState!)
                  ? _mqtt.lastState
                  : null),
          builder: (context, snapshot) {
            final state = snapshot.data;
            final String schOn1 = (_savedSchOn[1] != null &&
                    _savedSchOn[1] != 'DISABLED' &&
                    _savedSchOn[1]!.isNotEmpty)
                ? _savedSchOn[1]!
                : (state?.schOn1 ?? _schOn1);
            final String schOff1 = (_savedSchOff[1] != null &&
                    _savedSchOff[1] != 'DISABLED' &&
                    _savedSchOff[1]!.isNotEmpty)
                ? _savedSchOff[1]!
                : (state?.schOff1 ?? _schOff1);
            final String schOn2 = (_savedSchOn[2] != null &&
                    _savedSchOn[2] != 'DISABLED' &&
                    _savedSchOn[2]!.isNotEmpty)
                ? _savedSchOn[2]!
                : (state?.schOn2 ?? _schOn2);
            final String schOff2 = (_savedSchOff[2] != null &&
                    _savedSchOff[2] != 'DISABLED' &&
                    _savedSchOff[2]!.isNotEmpty)
                ? _savedSchOff[2]!
                : (state?.schOff2 ?? _schOff2);
            final String schOn3 = (_savedSchOn[3] != null &&
                    _savedSchOn[3] != 'DISABLED' &&
                    _savedSchOn[3]!.isNotEmpty)
                ? _savedSchOn[3]!
                : (state?.schOn3 ?? _schOn3);
            final String schOff3 = (_savedSchOff[3] != null &&
                    _savedSchOff[3] != 'DISABLED' &&
                    _savedSchOff[3]!.isNotEmpty)
                ? _savedSchOff[3]!
                : (state?.schOff3 ?? _schOff3);
            final String schOn4 = (_savedSchOn[4] != null &&
                    _savedSchOn[4] != 'DISABLED' &&
                    _savedSchOn[4]!.isNotEmpty)
                ? _savedSchOn[4]!
                : (state?.schOn4 ?? _schOn4);
            final String schOff4 = (_savedSchOff[4] != null &&
                    _savedSchOff[4] != 'DISABLED' &&
                    _savedSchOff[4]!.isNotEmpty)
                ? _savedSchOff[4]!
                : (state?.schOff4 ?? _schOff4);
            final String schOn5 = (_savedSchOn[5] != null &&
                    _savedSchOn[5] != 'DISABLED' &&
                    _savedSchOn[5]!.isNotEmpty)
                ? _savedSchOn[5]!
                : (state?.schOn5 ?? _schOn5);
            final String schOff5 = (_savedSchOff[5] != null &&
                    _savedSchOff[5] != 'DISABLED' &&
                    _savedSchOff[5]!.isNotEmpty)
                ? _savedSchOff[5]!
                : (state?.schOff5 ?? _schOff5);
            final String schOnLunch = (_savedSchOn[0] != null &&
                    _savedSchOn[0] != 'DISABLED' &&
                    _savedSchOn[0]!.isNotEmpty)
                ? _savedSchOn[0]!
                : (state?.lunchOn ?? _lunchOn);
            final String schOffLunch = (_savedSchOff[0] != null &&
                    _savedSchOff[0] != 'DISABLED' &&
                    _savedSchOff[0]!.isNotEmpty)
                ? _savedSchOff[0]!
                : (state?.lunchOff ?? _lunchOff);

            if (state != null) {
              _syncSavedScheduleTimes(state);
            }

            // Sync overrides with telemetry — clear override only when hardware confirms
            final Map<int, String> slotOnMap = {
              1: schOn1,
              2: schOn2,
              3: schOn3,
              4: schOn4,
              5: schOn5
            };
            final Map<int, String> slotOffMap = {
              1: schOff1,
              2: schOff2,
              3: schOff3,
              4: schOff4,
              5: schOff5
            };
            for (int slot in List.from(_schSwitchOverrides.keys)) {
              if (slot == 0) {
                final bool telemetryActive =
                    (schOnLunch != 'DISABLED' || schOffLunch != 'DISABLED');
                if (_schSwitchOverrides[0] == telemetryActive) {
                  _schSwitchOverrides.remove(0);
                  _schOverrideTimers[0]?.cancel();
                  _schOverrideTimers.remove(0);
                }
              } else {
                final bool telemetryActive = (slotOnMap[slot] != 'DISABLED' ||
                    slotOffMap[slot] != 'DISABLED');
                if (_schSwitchOverrides[slot] == telemetryActive) {
                  _schSwitchOverrides.remove(slot);
                  _schOverrideTimers[slot]?.cancel();
                  _schOverrideTimers.remove(slot);
                }
              }
            }

            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                return Container(
                  height: MediaQuery.of(context).size.height * 0.7,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white12 : Colors.black12,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Schedules',
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: textCol,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              _showSseInfoDialog(context, isDark);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _mqtt.isSseConnected
                                    ? Colors.green.withOpacity(0.1)
                                    : Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _mqtt.isSseConnected
                                      ? Colors.green.withOpacity(0.3)
                                      : Colors.red.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: _mqtt.isSseConnected
                                          ? Colors.green
                                          : Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _mqtt.isSseConnected ? 'Live' : 'Offline',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _mqtt.isSseConnected
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      // SSE Stream Status Banner
                      if (_mqtt.sseLastDataTime != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.04)
                                : const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.08)
                                  : const Color(0xFFD0DBFF),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.sensors_rounded,
                                size: 16,
                                color: _mqtt.isSseConnected
                                    ? AppColors.primary
                                    : (isDark
                                        ? Colors.white30
                                        : Colors.black26),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Last sync: ${_formatLastSeen(_mqtt.sseLastDataTime!)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  if (!_isControlAvailable ||
                                      (!_isActive && !_mqtt.isBluetoothConnected)) {
                                    _showSnack(
                                        'Device is offline. Connect to Wi-Fi to refresh schedules.',
                                        AppColors.offline,
                                        icon: Icons.wifi_off_rounded);
                                    return;
                                  }
                                  _mqtt.getScheduleStatus(
                                      targetDeviceId: _effectiveDeviceId);
                                  _showSnack('Refreshing schedules...',
                                      AppColors.primary);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Custom Tab Selector
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.05)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    activeTab = 0;
                                  });
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: activeTab == 0
                                        ? (isDark
                                            ? AppColors.surfaceDark
                                            : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: activeTab == 0
                                        ? [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : [],
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Daily Schedule',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: activeTab == 0
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: activeTab == 0
                                            ? textCol
                                            : subtextCol,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    activeTab = 1;
                                  });
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: activeTab == 1
                                        ? (isDark
                                            ? AppColors.surfaceDark
                                            : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: activeTab == 1
                                        ? [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : [],
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Lunch Period',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: activeTab == 1
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: activeTab == 1
                                            ? textCol
                                            : subtextCol,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                          child: activeTab == 0
                              ? ListView.builder(
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: 5,
                                  itemBuilder: (context, idx) {
                                    final int slot = idx + 1;
                                    String schOn;
                                    String schOff;
                                    String? schDays;
                                    if (slot == 1) {
                                      schOn = schOn1;
                                      schOff = schOff1;
                                      schDays = state?.schDays1;
                                    } else if (slot == 2) {
                                      schOn = schOn2;
                                      schOff = schOff2;
                                      schDays = state?.schDays2;
                                    } else if (slot == 3) {
                                      schOn = schOn3;
                                      schOff = schOff3;
                                      schDays = state?.schDays3;
                                    } else if (slot == 4) {
                                      schOn = schOn4;
                                      schOff = schOff4;
                                      schDays = state?.schDays4;
                                    } else {
                                      schOn = schOn5;
                                      schOff = schOff5;
                                      schDays = state?.schDays5;
                                    }

                                    final overrideTime =
                                        _userSchOverrideTime[slot];
                                    final bool isOverrideActive =
                                        overrideTime != null &&
                                            DateTime.now()
                                                    .difference(overrideTime)
                                                    .inSeconds <
                                                60;

                                    String defRawOn = '08:00';
                                    String defRawOff = '13:00';

                                    if (slot == 2) {
                                      defRawOn = '18:00';
                                      defRawOff = '23:00';
                                    } else if (slot == 3) {
                                      defRawOn = '09:00';
                                      defRawOff = '17:00';
                                    } else if (slot == 4) {
                                      defRawOn = '07:00';
                                      defRawOff = '15:00';
                                    } else if (slot == 5) {
                                      defRawOn = '10:00';
                                      defRawOff = '19:00';
                                    }

                                    final String rawOnTime =
                                        (isOverrideActive &&
                                                _savedSchOn[slot] != null)
                                            ? _savedSchOn[slot]!
                                            : (_savedSchOn[slot] ??
                                                (schOn != 'DISABLED' &&
                                                        schOn.isNotEmpty &&
                                                        schOn != '--:--'
                                                    ? schOn
                                                    : defRawOn));
                                    final String rawOffTime =
                                        (isOverrideActive &&
                                                _savedSchOff[slot] != null)
                                            ? _savedSchOff[slot]!
                                            : (_savedSchOff[slot] ??
                                                (schOff != 'DISABLED' &&
                                                        schOff.isNotEmpty &&
                                                        schOff != '--:--'
                                                    ? schOff
                                                    : defRawOff));

                                    final bool isSlotActive =
                                        _schEnabled[slot] ??
                                            (_schSwitchOverrides[slot] ??
                                                ((schOn != 'DISABLED' &&
                                                        schOn.isNotEmpty &&
                                                        schOn != '--:--') ||
                                                    (schOff != 'DISABLED' &&
                                                        schOff.isNotEmpty &&
                                                        schOff != '--:--')));

                                    final String onTimeDisplay =
                                        _formatTo12Hour(rawOnTime);
                                    final String offTimeDisplay =
                                        _formatTo12Hour(rawOffTime);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 18, vertical: 16),
                                      decoration: BoxDecoration(
                                        color: cardBg,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isDark
                                              ? AppColors.dividerDark
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Slot Title and Master Switch
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Schedule Slot $slot',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: textCol,
                                                ),
                                              ),
                                              Switch(
                                                value: isSlotActive,
                                                activeColor: AppColors.primary,
                                                onChanged: (val) {
                                                  if (!_isControlAvailable ||
                                                      (!_isActive &&
                                                          !_mqtt
                                                              .isBluetoothConnected)) {
                                                    _showSnack(
                                                        'Device is offline. Connect to Wi-Fi to change schedules.',
                                                        AppColors.offline,
                                                        icon: Icons.wifi_off_rounded);
                                                    return;
                                                  }
                                                  _userSchOverrideTime[slot] =
                                                      DateTime.now();
                                                  final daysToSend = _savedSchDays[
                                                          slot] ??
                                                      ((schDays != null &&
                                                              schDays !=
                                                                  'DISABLED' &&
                                                              schDays
                                                                  .isNotEmpty)
                                                          ? schDays
                                                          : 'ALL');
                                                  _savedSchDays[slot] =
                                                      daysToSend;
                                                  _savedSchOn[slot] = rawOnTime;
                                                  _savedSchOff[slot] =
                                                      rawOffTime;
                                                  _schEnabled[slot] = val;
                                                  setModalState(() {
                                                    _schSwitchOverrides[slot] =
                                                        val;
                                                  });
                                                  setState(() {
                                                    _schSwitchOverrides[slot] =
                                                        val;
                                                  });
                                                  LocalCacheService
                                                      .saveScheduleSlotConfig(
                                                    _effectiveDeviceId,
                                                    slot,
                                                    isEnabled: val,
                                                    onTime: rawOnTime,
                                                    offTime: rawOffTime,
                                                    days: daysToSend,
                                                  );

                                                  if (val) {
                                                    _mqtt.setScheduleOn(
                                                        slot, rawOnTime,
                                                        days: daysToSend,
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt.publishScheduleJson({
                                                      'on$slot': rawOnTime,
                                                      'off$slot': rawOffTime,
                                                      'days$slot': daysToSend,
                                                    },
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt
                                                        .updateScheduleOptimistic(
                                                            slot: slot,
                                                            onTime: rawOnTime,
                                                            offTime: rawOffTime,
                                                            days: daysToSend);
                                                    Future.delayed(
                                                        const Duration(
                                                            milliseconds: 400),
                                                        () {
                                                      _mqtt.setScheduleOff(
                                                          slot, rawOffTime,
                                                          days: daysToSend,
                                                          targetDeviceId:
                                                              _effectiveDeviceId);
                                                      _mqtt
                                                          .updateScheduleOptimistic(
                                                              slot: slot,
                                                              onTime: rawOnTime,
                                                              offTime:
                                                                  rawOffTime,
                                                              days: daysToSend);
                                                    });
                                                  } else {
                                                    _mqtt.clearScheduleSlot(
                                                        slot,
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt.publishScheduleJson({
                                                      'on$slot': 'DISABLED',
                                                      'off$slot': 'DISABLED',
                                                    },
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt
                                                        .updateScheduleOptimistic(
                                                            slot: slot,
                                                            clear: true);
                                                  }
                                                  Future.delayed(
                                                      const Duration(
                                                          milliseconds: 1500),
                                                      () {
                                                    _mqtt.getScheduleStatus(
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                  });
                                                  Future.delayed(
                                                      const Duration(
                                                          milliseconds: 4000),
                                                      () {
                                                    _mqtt.getScheduleStatus(
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),

                                          // ON and OFF Times Side-by-Side
                                          Row(
                                            children: [
                                              // ON Time block
                                              Expanded(
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () {
                                                    _showEditScheduleDialog(
                                                      context,
                                                      slot,
                                                      'ON',
                                                      onTimeDisplay,
                                                      isDark,
                                                      setModalState,
                                                    );
                                                  },
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'ON Time',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: subtextCol,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        onTimeDisplay,
                                                        style:
                                                            GoogleFonts.outfit(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: isSlotActive
                                                              ? textCol
                                                              : textCol
                                                                  .withOpacity(
                                                                      0.4),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              // Divider
                                              Container(
                                                height: 30,
                                                width: 1,
                                                color: isDark
                                                    ? Colors.white10
                                                    : Colors.black12,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 16),
                                              ),
                                              // OFF Time block
                                              Expanded(
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () {
                                                    _showEditScheduleDialog(
                                                      context,
                                                      slot,
                                                      'OFF',
                                                      offTimeDisplay,
                                                      isDark,
                                                      setModalState,
                                                    );
                                                  },
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'OFF Time',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: subtextCol,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        offTimeDisplay,
                                                        style:
                                                            GoogleFonts.outfit(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: isSlotActive
                                                              ? textCol
                                                              : textCol
                                                                  .withOpacity(
                                                                      0.4),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          _buildWeeklyDaysSelector(
                                            slot: slot,
                                            isEnabled: isSlotActive,
                                            isDark: isDark,
                                            setModalState: setModalState,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              : SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isDark
                                            ? AppColors.dividerDark
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: () {
                                      final lunchOverrideTime =
                                          _userSchOverrideTime[0];
                                      final bool isLunchOverrideActive =
                                          lunchOverrideTime != null &&
                                              DateTime.now()
                                                      .difference(
                                                          lunchOverrideTime)
                                                      .inSeconds <
                                                  60;

                                      final String rawLunchOn =
                                          (isLunchOverrideActive &&
                                                  _savedSchOn[0] != null)
                                              ? _savedSchOn[0]!
                                              : (_savedSchOn[0] ??
                                                  (schOnLunch != 'DISABLED' &&
                                                          schOnLunch
                                                              .isNotEmpty &&
                                                          schOnLunch != '--:--'
                                                      ? schOnLunch
                                                      : '12:00'));
                                      final String rawLunchOff =
                                          (isLunchOverrideActive &&
                                                  _savedSchOff[0] != null)
                                              ? _savedSchOff[0]!
                                              : (_savedSchOff[0] ??
                                                  (schOffLunch != 'DISABLED' &&
                                                          schOffLunch
                                                              .isNotEmpty &&
                                                          schOffLunch != '--:--'
                                                      ? schOffLunch
                                                      : '13:00'));

                                      final bool isLunchActive =
                                          _schEnabled[0] ??
                                              (_schSwitchOverrides[0] ??
                                                  (schOnLunch != 'DISABLED' ||
                                                      schOffLunch !=
                                                          'DISABLED'));

                                      final String lunchOnDisplay =
                                          _formatTo12Hour(rawLunchOn);
                                      final String lunchOffDisplay =
                                          _formatTo12Hour(rawLunchOff);

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Lunch Title and Switch
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Lunch Period',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: textCol,
                                                ),
                                              ),
                                              Switch(
                                                value: isLunchActive,
                                                activeColor: AppColors.primary,
                                                onChanged: (val) {
                                                  if (!_isControlAvailable ||
                                                      (!_isActive &&
                                                          !_mqtt
                                                              .isBluetoothConnected)) {
                                                    _showSnack(
                                                        'Device is offline. Connect to Wi-Fi to change schedules.',
                                                        AppColors.offline,
                                                        icon: Icons.wifi_off_rounded);
                                                    return;
                                                  }
                                                  _userSchOverrideTime[0] =
                                                      DateTime.now();
                                                  final lunchDaysToSend =
                                                      _savedSchDays[0] ?? 'ALL';
                                                  _savedSchDays[0] =
                                                      lunchDaysToSend;
                                                  _savedSchOn[0] = rawLunchOn;
                                                  _savedSchOff[0] = rawLunchOff;
                                                  _schEnabled[0] = val;
                                                  setModalState(() {
                                                    _schSwitchOverrides[0] =
                                                        val;
                                                  });
                                                  setState(() {
                                                    _schSwitchOverrides[0] =
                                                        val;
                                                  });
                                                  LocalCacheService
                                                      .saveScheduleSlotConfig(
                                                    _effectiveDeviceId,
                                                    0,
                                                    isEnabled: val,
                                                    onTime: rawLunchOn,
                                                    offTime: rawLunchOff,
                                                    days: lunchDaysToSend,
                                                  );

                                                  if (val) {
                                                    _mqtt.setLunchOn(rawLunchOn,
                                                        days: lunchDaysToSend,
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt.publishScheduleJson({
                                                      'lunch_on': rawLunchOn,
                                                      'lunch_off': rawLunchOff,
                                                      'lunch_days':
                                                          lunchDaysToSend,
                                                    },
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt.updateLunchOptimistic(
                                                        lunchOn: rawLunchOn,
                                                        lunchOff: rawLunchOff,
                                                        days: lunchDaysToSend);
                                                    Future.delayed(
                                                        const Duration(
                                                            milliseconds: 400),
                                                        () {
                                                      _mqtt.setLunchOff(
                                                          rawLunchOff,
                                                          days: lunchDaysToSend,
                                                          targetDeviceId:
                                                              _effectiveDeviceId);
                                                      _mqtt.updateLunchOptimistic(
                                                          lunchOn: rawLunchOn,
                                                          lunchOff: rawLunchOff,
                                                          days:
                                                              lunchDaysToSend);
                                                    });
                                                  } else {
                                                    _mqtt.clearLunchSlot(
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt.publishScheduleJson({
                                                      'lunch_on': 'DISABLED',
                                                      'lunch_off': 'DISABLED',
                                                    },
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt.updateLunchOptimistic(
                                                        clear: true);
                                                  }
                                                  _showSnack(
                                                      val
                                                          ? 'Lunch Period enabled'
                                                          : 'Lunch Period cleared',
                                                      val
                                                          ? AppColors.online
                                                          : AppColors.warning);
                                                  Future.delayed(
                                                      const Duration(
                                                          milliseconds: 1500),
                                                      () {
                                                    _mqtt.getScheduleStatus(
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                  });
                                                  Future.delayed(
                                                      const Duration(
                                                          milliseconds: 4000),
                                                      () {
                                                    _mqtt.getScheduleStatus(
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),

                                          // ON and OFF Times Side-by-Side
                                          Row(
                                            children: [
                                              // ON Time block
                                              Expanded(
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () {
                                                    _showEditScheduleDialog(
                                                      context,
                                                      0,
                                                      'ON',
                                                      lunchOnDisplay,
                                                      isDark,
                                                      setModalState,
                                                    );
                                                  },
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'ON Time',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: subtextCol,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        lunchOnDisplay,
                                                        style:
                                                            GoogleFonts.outfit(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: isLunchActive
                                                              ? textCol
                                                              : textCol
                                                                  .withOpacity(
                                                                      0.4),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              // Divider
                                              Container(
                                                height: 30,
                                                width: 1,
                                                color: isDark
                                                    ? Colors.white10
                                                    : Colors.black12,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 16),
                                              ),
                                              // OFF Time block
                                              Expanded(
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () {
                                                    _showEditScheduleDialog(
                                                      context,
                                                      0,
                                                      'OFF',
                                                      lunchOffDisplay,
                                                      isDark,
                                                      setModalState,
                                                    );
                                                  },
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'OFF Time',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: subtextCol,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        lunchOffDisplay,
                                                        style:
                                                            GoogleFonts.outfit(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: isLunchActive
                                                              ? textCol
                                                              : textCol
                                                                  .withOpacity(
                                                                      0.4),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          _buildWeeklyDaysSelector(
                                            slot: 0,
                                            isEnabled: isLunchActive,
                                            isDark: isDark,
                                            setModalState: setModalState,
                                          ),
                                        ],
                                      );
                                    }(),
                                  ),
                                )),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _timerOption(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          _showSnack('Auto-off timer set for $label', AppColors.primary);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.backgroundDark : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : Colors.transparent,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: isDark ? Colors.white70 : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showGraphsLogsDialog(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.45,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Device Log & Activity',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close_rounded,
                        color: isDark ? Colors.white30 : Colors.black26),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _activityLogs.isEmpty
                    ? Center(
                        child: Text(
                          'No activities recorded yet',
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white30 : Colors.black26,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: _activityLogs.length,
                        itemBuilder: (context, index) {
                          final log = _activityLogs[index];
                          return _buildLogItem(
                            log['message'].toString(),
                            log['time'].toString(),
                            log['color'] as Color,
                            isDark,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogItem(String title, String time, Color color, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppColors.dividerDark : Colors.grey[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? Colors.white.withOpacity(0.9)
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          Text(
            time,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.backgroundDark : const Color(0xFFF8FAFC);
    final cardColor = isDark ? AppColors.surfaceDark : Colors.white;
    final textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subtitleColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    // Build unique non-empty dropdown items safely to prevent duplicate value assertion errors
    final List<Map<String, String>> equipmentList = [];
    final Set<String> seenIds = {};
    for (final equip in _equipmentsData) {
      final String id = (equip['id'] ??
              equip['Id'] ??
              equip['equipmentId'] ??
              equip['EquipmentId'] ??
              '')
          .toString();
      if (id.isNotEmpty && !seenIds.contains(id)) {
        seenIds.add(id);
        final String name = equip['name']?.toString() ?? 'AC Unit';
        final String shortId = (equip['shortId'] ??
                equip['ShortId'] ??
                equip['imei'] ??
                equip['Imei'] ??
                '')
            .toString();
        final String display =
            (shortId.isNotEmpty && shortId.toLowerCase() != name.toLowerCase())
                ? '$name ($shortId)'
                : name;

        final bool isOnline = equip['isOnline'] == true ||
            (equip['onOffStatus'] != null &&
                equip['onOffStatus'] is Map &&
                (equip['onOffStatus']['isOnline'] == true ||
                    equip['onOffStatus']['status'] == 'ON' ||
                    equip['onOffStatus']['status'] == 'OFF'));

        equipmentList.add({
          'id': id,
          'name': name,
          'shortId': shortId,
          'display': display,
          'isOnline': isOnline.toString(),
        });
      }
    }

    final String? selectedId = seenIds.contains(_selectedEquipmentId)
        ? _selectedEquipmentId
        : (seenIds.isNotEmpty ? seenIds.first : null);

    final List<DropdownMenuItem<String>> dropdownItems =
        equipmentList.map((item) {
      final isSelected = item['id'] == selectedId;
      final bool isOnline = item['isOnline'] == 'true';
      return DropdownMenuItem<String>(
        value: item['id']!,
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isOnline ? AppColors.online : Colors.white38,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item['display']!,
                style: GoogleFonts.outfit(
                  color: isOnline ? Colors.white : Colors.white60,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isOnline
                    ? AppColors.online.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isOnline ? 'ONLINE' : 'OFFLINE',
                style: GoogleFonts.inter(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  color: isOnline ? AppColors.online : Colors.white60,
                ),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_rounded, size: 16, color: Colors.white),
            ],
          ],
        ),
      );
    }).toList();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _equipmentsData.length <= 1
            ? Text(
                _selectedEquipmentName.isNotEmpty
                    ? (_selectedEquipmentShortId.isNotEmpty &&
                            _selectedEquipmentShortId.toLowerCase() !=
                                _selectedEquipmentName.toLowerCase()
                        ? '$_selectedEquipmentName ($_selectedEquipmentShortId)'
                        : _selectedEquipmentName)
                    : 'Smart IR Blaster',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              )
            : Container(
                height: 38,
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedId,
                    isExpanded: true,
                    dropdownColor: AppColors.primaryDark,
                    borderRadius: BorderRadius.circular(16),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    selectedItemBuilder: (BuildContext context) {
                      return equipmentList.map<Widget>((item) {
                        return Container(
                          alignment: Alignment.center,
                          child: Text(
                            item['display']!,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList();
                    },
                    items: dropdownItems,
                    onChanged: (val) {
                      if (val != null) {
                        final selected = _equipmentsData.firstWhere((e) =>
                            (e['id'] ??
                                    e['Id'] ??
                                    e['equipmentId'] ??
                                    e['EquipmentId'] ??
                                    '')
                                .toString() ==
                            val);
                        _onEquipmentSelected(
                          val,
                          selected['name']?.toString() ?? 'AC Unit',
                          (selected['imei'] ??
                                  selected['Imei'] ??
                                  selected['shortId'] ??
                                  selected['ShortId'] ??
                                  '')
                              .toString(),
                        );
                      }
                    },
                  ),
                ),
              ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Reload Device Status',
            onPressed: () {
              _mqtt.sendStatus(targetDeviceId: _effectiveDeviceId);
              _fetchEquipments();
              _showSnack('Reloading equipment status...', AppColors.primary,
                  icon: Icons.refresh_rounded);
            },
          ),
          IconButton(
            icon: const Icon(Icons.wifi_rounded, color: Colors.white),
            tooltip: 'WiFi & Bluetooth Details',
            onPressed: _openWifiManagementDialog,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: (_isLoadingEquipments || _isReconnectingWifi)
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _isReconnectingWifi
                          ? 'Applying WiFi & reconnecting to $_reconnectingWifiSsid...'
                          : 'Connecting to ${_selectedEquipmentName.isNotEmpty ? _selectedEquipmentName : "device"}...',
                      style: GoogleFonts.outfit(
                        color: isDark ? Colors.white70 : AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isReconnectingWifi
                          ? 'Please wait, this may take up to 45 seconds'
                          : 'Please wait a moment',
                      style: GoogleFonts.inter(
                        color:
                            isDark ? Colors.white38 : AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final screenHeight = constraints.maxHeight;
                  // Determine vertical spacing based on available height to ensure it fits perfectly
                  final double cardSpacing = screenHeight > 750 ? 16.0 : 10.0;
                  final double innerPadding = screenHeight > 750 ? 20.0 : 14.0;

                  final isBluetooth = _mqtt.isBluetoothConnected;
                  final isDeviceOnline = _isActive || isBluetooth;

                  Widget content = Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: innerPadding, vertical: cardSpacing),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 1. Device Info Card
                        _buildDeviceInfoCard(
                            cardColor, textColor, subtitleColor, isDark),

                        // 2. Air Quality metrics (CO2 & AQI)
                        _buildAirQualityMetrics(
                            cardColor, textColor, subtitleColor, isDark),

                        // 3. Current Mode indicator (Cool & Auto)
                        _buildCurrentModeBanner(textColor),

                        // 4. Circular Temperature Controller (dial + increment/decrement)
                        _buildTemperatureDialRow(textColor, isDark),

                        // 5. Modes / Action Grid (5 horizontal items)
                        _buildActionGrid(cardColor, textColor, isDark),

                        // 6. Bottom Quick Actions (Timer, Schedule, Graphs & Logs)
                        _buildBottomQuickActions(textColor, isDark),
                      ],
                    ),
                  );

                  if (!isDeviceOnline) {
                    return Stack(
                      children: [
                        ImageFiltered(
                          imageFilter:
                              ImageFilter.blur(sigmaX: 5.5, sigmaY: 5.5),
                          child: Container(
                            color: Colors.transparent,
                            child: IgnorePointer(child: content),
                          ),
                        ),
                        _buildBlurOverlay(isDark),
                      ],
                    );
                  }

                  return content;
                },
              ),
      ),
    );
  }

  Widget _buildBlurOverlay(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.black : Colors.white).withOpacity(0.35),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.signal_wifi_off_rounded,
                  color: Colors.redAccent,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Device is Offline',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'The IR Blaster is disconnected from WiFi.\nPlease check your connection.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ──

  Widget _buildDeviceInfoCard(
      Color cardColor, Color textColor, Color subtitleColor, bool isDark) {
    final statusColor = _isPowerOn ? AppColors.online : AppColors.offline;
    final statusText = _isPowerOn ? 'On' : 'Off';
    final tempText =
        _currentTemp == 0 ? '--.-°' : '${_currentTemp.toStringAsFixed(1)}°';
    final humText = _humidity == 0 ? '--%' : '${_humidity.toStringAsFixed(1)}%';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Status: $statusText',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    tempText,
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.water_drop_rounded,
                        color: AppColors.coolBlue,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        humText,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: subtitleColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
              color: isDark ? AppColors.dividerDark : AppColors.divider,
              height: 1),
          const SizedBox(height: 12),
          _buildConnectivityRow(isDark),
        ],
      ),
    );
  }

  void _openWifiManagementDialog() {
    String? foundMac;
    try {
      final match = _equipmentsData.firstWhere(
        (e) =>
            (e['id'] ?? e['Id'] ?? e['equipmentId'] ?? e['EquipmentId'] ?? '')
                .toString() ==
            _selectedEquipmentId,
      );
      foundMac = (match['mac'] ??
              match['wifiMac'] ??
              match['Mac'] ??
              match['imei'] ??
              match['Imei'])
          ?.toString();
    } catch (_) {}

    showDialog(
      context: context,
      builder: (ctx) => WifiManagementDialog(
        mqtt: _mqtt,
        initialSsid: _mqtt.lastState?.primarySsid ?? '',
        deviceId:
            _activeDeviceId.isNotEmpty ? _activeDeviceId : _selectedEquipmentId,
        initialMac: foundMac,
        targetDeviceName: _selectedEquipmentName,
        isIndividualEquipment: true,
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _buildConnectivityRow(bool isDark) {
    final isBluetooth = _mqtt.isBluetoothConnected;
    final isDeviceOnline = _isActive || isBluetooth;
    final dotColor = isDeviceOnline ? AppColors.online : AppColors.offline;
    final connText = isBluetooth
        ? 'Bluetooth Connected'
        : (isDeviceOnline ? 'Connected' : 'OFFLINE');
    final iconData = isBluetooth ? Icons.bluetooth : Icons.wifi;
    final iconColor = isBluetooth
        ? Colors.blue
        : (isDeviceOnline ? AppColors.online : AppColors.offline);

    return GestureDetector(
      onTap: _openWifiManagementDialog,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, color: iconColor, size: 22),
          const SizedBox(width: 8),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            connText,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          if (!isDeviceOnline) ...[
            const SizedBox(width: 4),
            Text(
              '(Tap for WiFi/BT)',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.blueAccent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAirQualityMetrics(
      Color cardColor, Color textColor, Color subtitleColor, bool isDark) {
    return Row(
      children: [
        _buildAirMetricCard(
          icon: Icons.co2_rounded,
          title: 'CO₂',
          value: '$_co2 ppm',
          accentColor: const Color(0xFFD97706),
          bgLight: const Color(0xFFFFFBEB),
          bgDark: const Color(0xFF78350F),
          borderLight: const Color(0xFFFEF3C7),
          borderDark: const Color(0xFFB45309),
          activeSegments: 4,
          isDark: isDark,
        ),
        const SizedBox(width: 12),
        _buildAirMetricCard(
          icon: Icons.eco_rounded,
          title: 'AQI',
          value: '$_aqi',
          accentColor: const Color(0xFF65A30D),
          bgLight: const Color(0xFFF7FEE7),
          bgDark: const Color(0xFF3F6212),
          borderLight: const Color(0xFFECFCCB),
          borderDark: const Color(0xFF4D7C0F),
          activeSegments: 3,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildAirMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required Color accentColor,
    required Color bgLight,
    required Color bgDark,
    required Color borderLight,
    required Color borderDark,
    required int activeSegments,
    required bool isDark,
  }) {
    final bg = isDark ? bgDark.withOpacity(0.15) : bgLight;
    final borderCol = isDark ? borderDark.withOpacity(0.4) : borderLight;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderCol, width: 1),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: accentColor, size: 16),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                  5,
                  (index) => Container(
                        width: 12,
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: index < activeSegments
                              ? accentColor
                              : accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentModeBanner(Color textColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.ac_unit_rounded, color: AppColors.coolBlue, size: 16),
        const SizedBox(width: 6),
        Text(
          _mode,
          style: GoogleFonts.inter(
            color: textColor.withOpacity(0.7),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 20),
        RotationTransition(
          turns: _fanRotationCtrl,
          child: Image.asset(
            'assets/images/fan.png',
            width: 16,
            height: 16,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _fanSpeed,
          style: GoogleFonts.inter(
            color: textColor.withOpacity(0.7),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTemperatureDialRow(Color textColor, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDialButton(Icons.remove, _decrementTemp, textColor, isDark),
        const SizedBox(width: 20),
        _buildTempDial(textColor, isDark),
        const SizedBox(width: 20),
        _buildDialButton(Icons.add, _incrementTemp, textColor, isDark),
      ],
    );
  }

  Widget _buildTempDial(Color textColor, bool isDark) {
    final color = _isPowerOn ? AppColors.coolBlue : AppColors.textHint;
    return GestureDetector(
      onTap: _togglePower,
      child: SizedBox(
        width: 170,
        height: 170,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) {
            final double pulseVal = _isPowerOn ? _pulseCtrl.value : 0.0;
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Outer breathing aura ring (only when ON) - Positioned to prevent affecting layout flow
                if (_isPowerOn)
                  Positioned(
                    width: 170 + (pulseVal * 24),
                    height: 170 + (pulseVal * 24),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.withOpacity(0.25 * (1.0 - pulseVal)),
                          width: 1.5 + (pulseVal * 2.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.12 * (1.0 - pulseVal)),
                            blurRadius: 12 + (pulseVal * 12),
                            spreadRadius: 2 + (pulseVal * 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Main Dial Container
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    border: Border.all(
                      color: _isPowerOn
                          ? color.withOpacity(0.15 + pulseVal * 0.15)
                          : color.withOpacity(0.12),
                      width: 6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.08 + (pulseVal * 0.12)),
                        blurRadius: 16.0 + (pulseVal * 16.0),
                        spreadRadius: 2.0 + (pulseVal * 6.0),
                      ),
                      BoxShadow(
                        color: isDark
                            ? Colors.black38
                            : Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: child,
                ),
              ],
            );
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_setTemp°',
                style: GoogleFonts.outfit(
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isPowerOn ? 'TURN OFF' : 'TURN ON',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _isPowerOn ? AppColors.primary : AppColors.offline,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialButton(
      IconData icon, VoidCallback onTap, Color textColor, bool isDark) {
    final bool isEnabled = _isControlAvailable;
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? AppColors.surfaceDark : Colors.white,
          border: Border.all(
              color: isDark ? AppColors.dividerDark : AppColors.divider,
              width: 1),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: isEnabled ? AppColors.primary : AppColors.textHint,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildActionGrid(Color cardColor, Color textColor, bool isDark) {
    return Row(
      children: [
        _buildActionItem(
          icon: Icons.ac_unit_rounded,
          label: 'Mode',
          value: _mode,
          activeColor: AppColors.coolBlue,
          activeBg: const Color(0xFFEFF6FF),
          isActive: _isPowerOn,
          onTap: _cycleMode,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
        ),
        const SizedBox(width: 8),
        _buildActionItem(
          icon: Icons.mode_fan_off_rounded,
          label: 'Fan',
          value: _fanSpeed,
          activeColor: AppColors.primary,
          activeBg: const Color(0xFFECFDF5),
          isActive: _isPowerOn,
          onTap: _cycleFanSpeed,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
          customIcon: RotationTransition(
            turns: _fanRotationCtrl,
            child: Image.asset(
              'assets/images/fan.png',
              width: 22,
              height: 22,
              color: (_isPowerOn && _isControlAvailable)
                  ? AppColors.primary
                  : AppColors.textHint,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildActionItem(
          icon: Icons.lightbulb_rounded,
          label: 'Light',
          value: _lightOn ? 'On' : 'Off',
          activeColor: AppColors.warning,
          activeBg: const Color(0xFFFEFCE8),
          isActive: _isPowerOn && _lightOn,
          onTap: _toggleLight,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
        ),
        const SizedBox(width: 8),
        _buildActionItem(
          icon: Icons.swap_vert_rounded,
          label: 'Swing',
          value: _swingV ? 'On' : 'Off',
          activeColor: AppColors.fanPurple,
          activeBg: const Color(0xFFF5F3FF),
          isActive: _isPowerOn && _swingV,
          onTap: _toggleSwingV,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
        ),
        const SizedBox(width: 8),
        _buildActionItem(
          icon: Icons.swap_horiz_rounded,
          label: 'Swing',
          value: _swingH ? 'On' : 'Off',
          activeColor: AppColors.fanPurple,
          activeBg: const Color(0xFFF5F3FF),
          isActive: _isPowerOn && _swingH,
          onTap: _toggleSwingH,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String label,
    required String value,
    required Color activeColor,
    required Color activeBg,
    required bool isActive,
    required VoidCallback onTap,
    required Color cardColor,
    required Color textColor,
    required bool isDark,
    Widget? customIcon,
  }) {
    final bool isInteractable = _isControlAvailable && _isPowerOn;
    final bg = (isActive && isInteractable)
        ? (isDark ? activeColor.withOpacity(0.12) : activeBg)
        : cardColor;
    final borderCol = (isActive && isInteractable)
        ? activeColor.withOpacity(0.3)
        : (isDark ? AppColors.dividerDark : AppColors.divider);

    return Expanded(
      child: GestureDetector(
        onTap: isInteractable ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderCol, width: 1.2),
            boxShadow: [
              if (isActive && isInteractable)
                BoxShadow(
                  color: activeColor.withOpacity(isDark ? 0.1 : 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              customIcon ??
                  Icon(icon,
                      color: (isActive && isInteractable)
                          ? activeColor
                          : AppColors.textHint,
                      size: 22),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: (isActive && isInteractable)
                      ? activeColor
                      : AppColors.textHint,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomQuickActions(Color textColor, bool isDark) {
    return Row(
      children: [
        _buildBottomActionItem(
          icon:
              _isAutomated ? Icons.smart_toy_rounded : Icons.smart_toy_outlined,
          label: _isAutomated ? 'Auto ($_autoTemp°)' : 'Automate',
          color: _isAutomated ? AppColors.online : AppColors.coolBlue,
          bg: _isAutomated
              ? AppColors.online.withOpacity(0.12)
              : (isDark
                  ? AppColors.coolBlue.withOpacity(0.12)
                  : const Color(0xFFEFF6FF)),
          onTap: () => _showAutomationDialog(context, isDark),
          isDark: isDark,
        ),
        const SizedBox(width: 12),
        _buildBottomActionItem(
          icon: Icons.calendar_month_outlined,
          label: 'Schedule',
          color: AppColors.primary,
          bg: isDark
              ? AppColors.primary.withOpacity(0.12)
              : const Color(0xFFECFDF5),
          onTap: () => _showSchedulesSheet(context, isDark),
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildBottomActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.2), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAutomationDialog(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Smart Automation',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      Switch(
                        value: _isAutomated,
                        activeColor: AppColors.primary,
                        onChanged: (value) async {
                          if (!_isControlAvailable ||
                              (!_isActive && !_mqtt.isBluetoothConnected)) {
                            _showSnack(
                              'Device is offline. Connect to Wi-Fi to use smart automation.',
                              AppColors.offline,
                              icon: Icons.wifi_off_rounded,
                            );
                            return;
                          }
                          setModalState(() {
                            _isAutomated = value;
                          });
                          setState(() {
                            _isAutomated = value;
                          });
                          _addLog(
                              'Automation ${value ? 'ENABLED' : 'DISABLED'}',
                              AppColors.primary);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('auto_enabled', value);
                          if (value) {
                            _mqtt.enableAutomation(
                                autoTemp: _autoTemp,
                                targetDeviceId: _effectiveDeviceId);
                          } else {
                            _mqtt.disableAutomation(
                                targetDeviceId: _effectiveDeviceId);
                          }
                          _showSnack(
                            'Smart Automation ${value ? 'Enabled ($_autoTemp°C)' : 'Disabled'}',
                            value ? AppColors.online : AppColors.offline,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Let the IR Blaster adjust your AC settings intelligently based on room parameters to optimize comfort and save energy.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(
                      color:
                          isDark ? AppColors.dividerDark : AppColors.divider),
                  const SizedBox(height: 16),
                  Text(
                    'Automation Triggers',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTemperatureThresholdTriggerItem(
                    enabled: _isAutomated,
                    isDark: isDark,
                    setModalState: setModalState,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.03)
                          : Colors.black.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Automation threshold is independent from normal AC temperature ($_setTemp°C).',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateAutoTemp(int newTemp, [StateSetter? setModalState]) async {
    if (newTemp < 16 || newTemp > 30) return;
    if (setModalState != null) {
      setModalState(() {
        _autoTemp = newTemp;
      });
    }
    setState(() {
      _autoTemp = newTemp;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_temp', newTemp);

    _addLog('Smart Automation threshold set to $newTemp°C', AppColors.primary);

    if (_isAutomated) {
      if (!_isControlAvailable || (!_isActive && !_mqtt.isBluetoothConnected)) {
        _showSnack(
          'Device offline. Saved threshold $newTemp°C will apply when online.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded,
        );
      } else {
        _mqtt.setAutoTemperature(newTemp, targetDeviceId: _effectiveDeviceId);
        _showSnack(
          'Smart Automation target set to $newTemp°C',
          AppColors.primary,
          icon: Icons.thermostat_rounded,
        );
      }
    }
  }

  Widget _buildTemperatureThresholdTriggerItem({
    required bool enabled,
    required bool isDark,
    required StateSetter setModalState,
  }) {
    final titleColor = enabled
        ? (isDark ? Colors.white : AppColors.textPrimary)
        : (isDark ? Colors.white54 : Colors.black45);
    final descColor = enabled
        ? (isDark ? Colors.white60 : Colors.black54)
        : (isDark ? Colors.white24 : Colors.black26);
    final iconColor = enabled
        ? AppColors.primary
        : (isDark ? Colors.white24 : Colors.black26);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: enabled
            ? (isDark
                ? AppColors.primary.withOpacity(0.08)
                : AppColors.primary.withOpacity(0.05))
            : (isDark
                ? Colors.white.withOpacity(0.02)
                : Colors.black.withOpacity(0.02)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled
              ? AppColors.primary.withOpacity(0.25)
              : (isDark ? Colors.white10 : Colors.black12),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: enabled
                  ? AppColors.primary.withOpacity(0.12)
                  : (isDark
                      ? Colors.white.withOpacity(0.03)
                      : Colors.black.withOpacity(0.03)),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.thermostat_rounded,
                color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Temperature Threshold',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: enabled
                            ? AppColors.primary.withOpacity(0.2)
                            : (isDark
                                ? Colors.white10
                                : Colors.black.withOpacity(0.05)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$_autoTemp°C',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: enabled
                              ? AppColors.primary
                              : (isDark
                                  ? Colors.white38
                                  : Colors.black38),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Turn off AC when room temp drops below $_autoTemp°C',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: descColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Stepper: -  [Temp]  +
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E293B)
                  : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: enabled
                    ? AppColors.primary.withOpacity(0.4)
                    : (isDark ? Colors.white12 : Colors.black12),
                width: 1,
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Decrease button (-)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _autoTemp <= 16
                        ? null
                        : () => _updateAutoTemp(
                            _autoTemp - 1, setModalState),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(
                        Icons.remove_rounded,
                        size: 16,
                        color: _autoTemp <= 16
                            ? (isDark
                                ? Colors.white24
                                : Colors.black26)
                            : (enabled
                                ? (isDark
                                    ? Colors.white
                                    : AppColors.textPrimary)
                                : (isDark
                                    ? Colors.white38
                                    : Colors.black38)),
                      ),
                    ),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 28),
                  alignment: Alignment.center,
                  child: Text(
                    '$_autoTemp°',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: enabled
                          ? AppColors.primary
                          : (isDark
                              ? Colors.white54
                              : Colors.black45),
                    ),
                  ),
                ),
                // Increase button (+)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _autoTemp >= 30
                        ? null
                        : () => _updateAutoTemp(
                            _autoTemp + 1, setModalState),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: _autoTemp >= 30
                            ? (isDark
                                ? Colors.white24
                                : Colors.black26)
                            : (enabled
                                ? (isDark
                                    ? Colors.white
                                    : AppColors.textPrimary)
                                : (isDark
                                    ? Colors.white38
                                    : Colors.black38)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopMessageBarWidget extends StatefulWidget {
  final String message;
  final Color color;
  final IconData? icon;
  final double topOffset;
  final VoidCallback onDismiss;

  const _TopMessageBarWidget({
    required this.message,
    required this.color,
    this.icon,
    required this.topOffset,
    required this.onDismiss,
  });

  @override
  State<_TopMessageBarWidget> createState() => _TopMessageBarWidgetState();
}

class _TopMessageBarWidgetState extends State<_TopMessageBarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _slideAnimation = Tween<double>(begin: -40.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    _dismissTimer = Timer(const Duration(milliseconds: 2800), () {
      _dismiss();
    });
  }

  void _dismiss() {
    if (!mounted) return;
    _dismissTimer?.cancel();
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.topOffset,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _slideAnimation.value),
              child: Opacity(
                opacity: _fadeAnimation.value.clamp(0.0, 1.0),
                child: child,
              ),
            );
          },
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta != null && details.primaryDelta! < -4) {
                _dismiss();
              }
            },
            onTap: _dismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                  ] else ...[
                    const Icon(Icons.check_circle_outline_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      widget.message,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _dismiss,
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withOpacity(0.85),
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

