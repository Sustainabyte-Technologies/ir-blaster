import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/core/services/mqtt_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';
import 'package:ir_blaster_ac/screens/bluetooth_scanner_page.dart';
import 'package:ir_blaster_ac/screens/widgets/wifi_management_dialog.dart';
import 'package:ir_blaster_ac/screens/ac_app/ac_control/widgets/top_message_bar.dart';
import 'package:ir_blaster_ac/screens/ac_app/ac_control/dialogs/sse_info_dialog.dart';
import 'package:ir_blaster_ac/screens/ac_app/ac_control/dialogs/weekly_days_selector.dart';

part 'ac_control/dialogs/edit_schedule_dialog.dart';
part 'ac_control/dialogs/schedules_sheet.dart';
part 'ac_control/dialogs/automation_dialog.dart';
part 'ac_control/widgets/ac_control_sections.dart';

class ACControlPage extends StatefulWidget {
  final String? deviceName;
  final String? systemId;
  final String? systemShortId;
  final String? equipmentId;
  final String? companyId;

  const ACControlPage({
    super.key,
    this.deviceName,
    this.systemId,
    this.systemShortId,
    this.equipmentId,
    this.companyId,
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
  bool get _isControlAvailable => true; // Always allow user interactions and commands
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
  String _activeDeviceId = ''; // Target MQTT device ID (IMEI)
  String _activeDeviceImei = ''; // Target physical IMEI

  String _schOn1 = 'DISABLED', _schOff1 = 'DISABLED';
  String _schOn2 = 'DISABLED', _schOff2 = 'DISABLED';
  String _schOn3 = 'DISABLED', _schOff3 = 'DISABLED';
  String _schOn4 = 'DISABLED', _schOff4 = 'DISABLED';
  String _schOn5 = 'DISABLED', _schOff5 = 'DISABLED';
  String _lunchOn = 'DISABLED', _lunchOff = 'DISABLED';

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

  bool _isPlaceholderId(String? id) => MqttService.isPlaceholderId(id);

  String get _effectiveDeviceId {
    if (!_isPlaceholderId(_activeDeviceImei) && _activeDeviceImei.isNotEmpty) {
      return _activeDeviceImei;
    }
    if (!_isPlaceholderId(_activeDeviceId) && _activeDeviceId.isNotEmpty) {
      return _activeDeviceId;
    }
    if (_selectedEquipmentId.isNotEmpty) return _selectedEquipmentId;
    if (widget.systemShortId != null &&
        widget.systemShortId!.isNotEmpty &&
        !_isPlaceholderId(widget.systemShortId)) {
      return widget.systemShortId!;
    }
    return '';
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
    final equipId = _selectedEquipmentId.toLowerCase().trim();

    final bool isStateImeiPlaceholder = _isPlaceholderId(sImei);
    final bool isActiveImeiPlaceholder = _isPlaceholderId(activeImei);

    // Primary: match hardware device_id / IMEI
    final bool devMatches = sDevId.isNotEmpty && (
        (activeId.isNotEmpty && sDevId == activeId) ||
        (activeImei.isNotEmpty && sDevId == activeImei) ||
        (equipId.isNotEmpty && sDevId == equipId) ||
        (activeId.isNotEmpty &&
            sDevId.replaceAll('_', '').replaceAll('-', '') ==
                activeId.replaceAll('_', '').replaceAll('-', ''))
    );
    if (devMatches) return true;

    // Secondary: IMEI match ONLY if neither is a placeholder like 'numberIMEI'
    if (!isStateImeiPlaceholder && !isActiveImeiPlaceholder) {
      if (sImei == activeImei || (activeId.isNotEmpty && sImei == activeId)) {
        return true;
      }
    }

    for (var eq in _equipmentsData) {
      final eqId = (eq['id'] ?? eq['Id'] ?? eq['equipmentId'] ?? eq['EquipmentId'] ?? '').toString().toLowerCase().trim();
      final eqImei = (eq['imei'] ?? eq['Imei'] ?? '').toString().toLowerCase().trim();

      final isCurrentSelected = (equipId.isNotEmpty && eqId == equipId) ||
          (activeId.isNotEmpty && eqId == activeId) ||
          (activeImei.isNotEmpty && eqImei == activeImei);

      if (isCurrentSelected) {
        if (sDevId.isNotEmpty && (sDevId == eqId || (eqImei.isNotEmpty && sDevId == eqImei))) {
          return true;
        }
        if (!isStateImeiPlaceholder &&
            !_isPlaceholderId(eqImei) &&
            sImei == eqImei) {
          return true;
        }
      }
    }

    return false;
  }

  bool _isResponseForActiveDevice(SirisResponse resp) {
    if (resp.deviceId == null || resp.deviceId!.isEmpty) {
      // If we recently commanded power or temp on this active device, accept the acknowledgement
      if (_pendingPower || _pendingTemp) return true;
      return _activeDeviceId.isEmpty && _selectedEquipmentId.isEmpty;
    }
    final rId = resp.deviceId!.toLowerCase().trim();
    if (_isPlaceholderId(rId)) return false;

    final activeId = _activeDeviceId.toLowerCase().trim();
    final activeImei = _activeDeviceImei.toLowerCase().trim();
    final equipId = _selectedEquipmentId.toLowerCase().trim();
    final selectedName = _selectedEquipmentName.toLowerCase().trim();

    final bool isActiveImeiPlaceholder = _isPlaceholderId(activeImei);

    final cleanR = rId.replaceAll('_', '').replaceAll('-', '');
    final cleanActive = activeId.replaceAll('_', '').replaceAll('-', '');
    final cleanName = selectedName.replaceAll('_', '').replaceAll('-', '');

    if ((activeId.isNotEmpty && (rId == activeId || cleanR == cleanActive)) ||
        (!isActiveImeiPlaceholder && activeImei.isNotEmpty && rId == activeImei) ||
        (selectedName.isNotEmpty && (rId == selectedName || cleanR == cleanName)) ||
        (equipId.isNotEmpty && rId == equipId)) {
      return true;
    }

    for (var eq in _equipmentsData) {
      final eqId = (eq['id'] ?? eq['Id'] ?? eq['equipmentId'] ?? eq['EquipmentId'] ?? '').toString().toLowerCase().trim();
      final eqName = (eq['name'] ?? eq['Name'] ?? eq['equipmentName'] ?? '').toString().toLowerCase().trim();
      final eqImei = (eq['imei'] ?? eq['Imei'] ?? '').toString().toLowerCase().trim();

      final isCurrentSelected = (equipId.isNotEmpty && eqId == equipId) ||
          (selectedName.isNotEmpty && eqName == selectedName) ||
          (activeId.isNotEmpty && (eqId == activeId || eqName == activeId)) ||
          (activeImei.isNotEmpty && eqImei == activeImei);

      if (isCurrentSelected) {
        if (rId == eqId ||
            rId == eqName ||
            cleanR == eqName.replaceAll('_', '').replaceAll('-', '') ||
            (!_isPlaceholderId(eqImei) && rId == eqImei)) {
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
    _heartbeatTimer = Timer(const Duration(seconds: 120), () {
      if (mounted) {
        setState(() {
          _isActive = false;
        });
      }
    });
  }

  // Smart automation state
  bool _isAutomated = false;
  int _autoTemp = 22; // Smart automation temperature threshold (16–30°C)

  // Air Quality telemetry values
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

  // Equipment-scoped optimistic states to prevent cross-device lock leakage
  final Map<String, DateTime> _equipmentPowerToggleTimes = {};
  final Map<String, bool> _equipmentPendingPower = {};
  final Map<String, DateTime> _equipmentUserTempTimes = {};
  final Map<String, bool> _equipmentUserTempOverrides = {};
  Timer? _apiSyncTimer;
  Timer? _apiSyncSecondaryTimer;
  Timer? _apiSyncTertiaryTimer;
  Timer? _apiPollingTimer;
  OverlayEntry? _currentTopBanner;
  Timer? _topBannerTimer;

  StreamSubscription? _stateSub;
  StreamSubscription? _responseSub;
  StreamSubscription? _connSub;

  bool _isReconnectingWifi = false;
  final String _reconnectingWifiSsid = '';
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

  void updateUI([VoidCallback? fn]) {
    if (mounted) {
      setState(fn ?? () {});
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

    // Immediately bind identity from incoming navigation parameters before any async network call
    if (widget.equipmentId != null && widget.equipmentId!.isNotEmpty) {
      _selectedEquipmentId = widget.equipmentId!;
    }
    if (widget.deviceName != null && widget.deviceName!.isNotEmpty) {
      _selectedEquipmentName = widget.deviceName!;
    }
    final initialImei = (widget.systemShortId != null &&
            widget.systemShortId!.isNotEmpty &&
            !_isPlaceholderId(widget.systemShortId))
        ? widget.systemShortId!
        : '';
    if (initialImei.isNotEmpty) {
      _activeDeviceImei = initialImei;
      _activeDeviceId = initialImei;
      _mqtt.setDeviceId(initialImei, imei: initialImei);
    }

    _loadWifiSsid();
    _connectMqtt();
    _fetchEquipments();
    _loadCachedSchedules();
    _loadAutoTemp();
    _mqtt.addListener(_onMqttChanged);

    // Continuous live status retrieval via API as requested
    _apiPollingTimer?.cancel();
    _apiPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        _fetchStatusViaApi();
      }
    });
  }

  /// Fetches live equipment telemetry and on/off status directly from the REST API.
  Future<void> _fetchStatusViaApi() async {
    try {
      final companyId = widget.companyId ?? await AuthService.getCompanyId() ?? '';
      String siteId = await AuthService.getSiteId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';
      String zoneId = await AuthService.getZoneId() ?? '';

      // Fallback zoneId & siteId from loaded equipment metadata
      if ((zoneId.isEmpty || siteId.isEmpty) && _equipmentsData.isNotEmpty) {
        for (var e in _equipmentsData) {
          if (zoneId.isEmpty) {
            final z = (e['zoneId'] ?? e['ZoneId'] ?? '').toString();
            if (z.isNotEmpty && z != '00000000-0000-0000-0000-000000000000') {
              zoneId = z;
            }
          }
          if (siteId.isEmpty) {
            final s = (e['siteId'] ?? e['SiteId'] ?? '').toString();
            if (s.isNotEmpty && s != '00000000-0000-0000-0000-000000000000') {
              siteId = s;
            }
          }
          if (zoneId.isNotEmpty && siteId.isNotEmpty) break;
        }
      }

      if (companyId.isNotEmpty && siteId.isNotEmpty && zoneId.isNotEmpty) {
        final sysParam = widget.systemId != null && widget.systemId!.isNotEmpty
            ? '&systemId=${widget.systemId}'
            : '';
        final statusUrl =
            '${AppConfig.provisionBaseUrl}/mqtt/ac/status?companyId=$companyId&siteId=$siteId&zoneId=$zoneId$sysParam';
        final statusResponse = await http.get(
          Uri.parse(statusUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Cookie': 'auth_token=$token',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 4));

        if (statusResponse.statusCode == 200 && mounted) {
          final body = jsonDecode(statusResponse.body);
          List<dynamic> systemsData = body['systems'] ?? [];

          // If system-scoped query returned empty systems, fall back to zone-wide query
          if (systemsData.isEmpty && sysParam.isNotEmpty) {
            try {
              final fallbackUrl =
                  '${AppConfig.provisionBaseUrl}/mqtt/ac/status?companyId=$companyId&siteId=$siteId&zoneId=$zoneId';
              final fallbackResp = await http.get(
                Uri.parse(fallbackUrl),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Cookie': 'auth_token=$token',
                  'Content-Type': 'application/json',
                },
              ).timeout(const Duration(seconds: 4));
              if (fallbackResp.statusCode == 200) {
                final fbBody = jsonDecode(fallbackResp.body);
                systemsData = fbBody['systems'] ?? [];
              }
            } catch (_) {}
          }

          Map<String, dynamic>? activeMatch;

          final eqIdTarget = _selectedEquipmentId.toLowerCase().trim();
          final widgetEqId = (widget.equipmentId ?? '').toLowerCase().trim();
          final imeiTarget = _activeDeviceImei.toLowerCase().trim();
          final activeDevId = _activeDeviceId.toLowerCase().trim();
          final widgetShortId = (widget.systemShortId ?? '').toLowerCase().trim();
          final nameTarget = _selectedEquipmentName.toLowerCase().trim();
          final widgetDevName = (widget.deviceName ?? '').toLowerCase().trim();

          for (var sys in systemsData) {
            final List<dynamic> eqs = sys['equipments'] ?? [];
            for (var eq in eqs) {
              final eqMap = Map<String, dynamic>.from(eq);
              final eqId = (eqMap['equipmentId'] ??
                      eqMap['EquipmentId'] ??
                      eqMap['id'] ??
                      eqMap['Id'] ??
                      '')
                  .toString()
                  .toLowerCase()
                  .trim();
              final imei = (eqMap['imei'] ?? eqMap['Imei'] ?? '')
                  .toString()
                  .toLowerCase()
                  .trim();
              final shortId = (eqMap['shortId'] ?? eqMap['ShortId'] ?? '')
                  .toString()
                  .toLowerCase()
                  .trim();
              final name = (eqMap['name'] ?? eqMap['Name'] ?? '')
                  .toString()
                  .toLowerCase()
                  .trim();

              // Update each equipment in _equipmentsData so dropdown/indicators stay fresh
              for (var existingEq in _equipmentsData) {
                final exId = (existingEq['id'] ??
                        existingEq['Id'] ??
                        existingEq['equipmentId'] ??
                        existingEq['EquipmentId'] ??
                        '')
                    .toString()
                    .toLowerCase()
                    .trim();
                final exImei = (existingEq['imei'] ?? existingEq['Imei'] ?? '')
                    .toString()
                    .toLowerCase()
                    .trim();
                final exShortId = (existingEq['shortId'] ?? existingEq['ShortId'] ?? '')
                    .toString()
                    .toLowerCase()
                    .trim();
                final exName = (existingEq['name'] ?? existingEq['Name'] ?? '')
                    .toString()
                    .toLowerCase()
                    .trim();

                final bool matches = (exId.isNotEmpty && exId == eqId) ||
                    (exImei.isNotEmpty && !_isPlaceholderId(exImei) && exImei == imei) ||
                    (exShortId.isNotEmpty && !_isPlaceholderId(exShortId) && exShortId == shortId) ||
                    (exName.isNotEmpty && exName == name);

                if (matches) {
                  if (imei.isNotEmpty && !_isPlaceholderId(imei)) {
                    existingEq['imei'] = eqMap['imei'];
                  }
                  final statusStr = (eqMap['status'] ??
                          eqMap['Status'] ??
                          'DISCONNECTED')
                      .toString()
                      .toUpperCase()
                      .trim();
                  final bool isOnline = statusStr == 'ON' ||
                      statusStr == 'OFF' ||
                      statusStr == 'ONLINE' ||
                      statusStr == 'CONNECTED' ||
                      statusStr == 'ACTIVE';
                  existingEq['onOffStatus'] = {
                    'isOnline': isOnline,
                    'status': statusStr,
                  };
                  existingEq['isOnline'] = isOnline;
                  existingEq['isActive'] = isOnline;
                  if (eqMap['setTemp'] != null) {
                    existingEq['setTemp'] = eqMap['setTemp'];
                  }
                  if (eqMap['currentTemp'] != null) {
                    existingEq['currentTemp'] = eqMap['currentTemp'];
                  }
                  if (eqMap['hum'] != null) {
                    existingEq['humidity'] = eqMap['hum'];
                  }
                }
              }

              // Check if this equipment matches the currently active selection
              // 1. By Equipment ID
              if (eqId.isNotEmpty) {
                if ((eqIdTarget.isNotEmpty && eqId == eqIdTarget) ||
                    (widgetEqId.isNotEmpty && eqId == widgetEqId)) {
                  activeMatch = eqMap;
                  break;
                }
              }

              // 2. By Hardware IMEI
              if (imei.isNotEmpty && !_isPlaceholderId(imei)) {
                if ((imeiTarget.isNotEmpty && !_isPlaceholderId(imeiTarget) && imei == imeiTarget) ||
                    (activeDevId.isNotEmpty && !_isPlaceholderId(activeDevId) && imei == activeDevId) ||
                    (widgetShortId.isNotEmpty && !_isPlaceholderId(widgetShortId) && imei == widgetShortId)) {
                  activeMatch = eqMap;
                  continue;
                }
              }

              // 3. By Short ID
              if (shortId.isNotEmpty && !_isPlaceholderId(shortId)) {
                if ((imeiTarget.isNotEmpty && !_isPlaceholderId(imeiTarget) && shortId == imeiTarget) ||
                    (activeDevId.isNotEmpty && !_isPlaceholderId(activeDevId) && shortId == activeDevId) ||
                    (widgetShortId.isNotEmpty && !_isPlaceholderId(widgetShortId) && shortId == widgetShortId)) {
                  activeMatch = eqMap;
                  continue;
                }
              }

              // 4. By Equipment Name
              if (name.isNotEmpty) {
                final cleanName = name.replaceAll('_', '').replaceAll('-', '').replaceAll(' ', '');
                final cleanTarget = nameTarget.replaceAll('_', '').replaceAll('-', '').replaceAll(' ', '');
                final cleanWidgetName = widgetDevName.replaceAll('_', '').replaceAll('-', '').replaceAll(' ', '');
                if (name == nameTarget ||
                    (cleanTarget.isNotEmpty && cleanName == cleanTarget) ||
                    (cleanWidgetName.isNotEmpty && cleanName == cleanWidgetName)) {
                  activeMatch = eqMap;
                  continue;
                }
              }
            }
          }

          // Fallback: If only 1 equipment exists in the returned API system, match it
          if (activeMatch == null && systemsData.isNotEmpty) {
            final List<dynamic> firstEqs = systemsData.first['equipments'] ?? [];
            if (firstEqs.length == 1) {
              activeMatch = Map<String, dynamic>.from(firstEqs.first);
            }
          }

          if (activeMatch != null && mounted) {
            final statusStr = (activeMatch['status'] ??
                    activeMatch['Status'] ??
                    'DISCONNECTED')
                .toString()
                .toUpperCase()
                .trim();
            final bool isOnline = statusStr == 'ON' ||
                statusStr == 'OFF' ||
                statusStr == 'ONLINE' ||
                statusStr == 'CONNECTED' ||
                statusStr == 'ACTIVE';

            final String eqKey = _selectedEquipmentId.isNotEmpty
                ? _selectedEquipmentId
                : _effectiveDeviceId;
            final isLockActive = _lastPowerToggleTime != null &&
                DateTime.now().difference(_lastPowerToggleTime!).inSeconds < 10;
            final isTempLockActive = _lastUserTempChangeTime != null &&
                DateTime.now().difference(_lastUserTempChangeTime!).inSeconds < 8;

            final activeImeiVal = (activeMatch['imei'] ?? activeMatch['Imei'] ?? '')
                .toString()
                .trim();
            if (activeImeiVal.isNotEmpty && !_isPlaceholderId(activeImeiVal) && _activeDeviceImei != activeImeiVal) {
              _activeDeviceImei = activeImeiVal;
              _activeDeviceId = activeImeiVal;
              _mqtt.setDeviceId(activeImeiVal, imei: activeImeiVal);
            }

            setState(() {
              _isActive = isOnline;

              if (!isLockActive && !_pendingPower) {
                if (statusStr == 'ON') {
                  _isPowerOn = true;
                  _fanRotationCtrl.repeat();
                } else if (statusStr == 'OFF') {
                  _isPowerOn = false;
                  _fanRotationCtrl.stop();
                }
              } else {
                // If API status already confirms the optimistic user power command, release the lock early!
                if ((statusStr == 'ON' && _isPowerOn) || (statusStr == 'OFF' && !_isPowerOn)) {
                  _pendingPower = false;
                  _lastPowerToggleTime = null;
                  if (eqKey.isNotEmpty) {
                    _equipmentPowerToggleTimes.remove(eqKey);
                    _equipmentPendingPower[eqKey] = false;
                  }
                }
              }

              if (!isTempLockActive &&
                  !_pendingTemp &&
                  activeMatch!['setTemp'] != null) {
                final sTemp =
                    int.tryParse(activeMatch['setTemp'].toString());
                if (sTemp != null && sTemp >= 16 && sTemp <= 30) {
                  _setTemp = sTemp;
                }
              } else if (activeMatch!['setTemp'] != null) {
                final sTemp = int.tryParse(activeMatch['setTemp'].toString());
                if (sTemp != null && sTemp == _setTemp) {
                  _pendingTemp = false;
                  _userTempOverride = false;
                  if (eqKey.isNotEmpty) {
                    _equipmentUserTempOverrides[eqKey] = false;
                  }
                }
              }

              if (activeMatch['currentTemp'] != null) {
                final cTemp = (activeMatch['currentTemp'] as num?)?.toInt() ??
                    int.tryParse(activeMatch['currentTemp'].toString());
                if (cTemp != null && cTemp > 0) _currentTemp = cTemp;
              }
              if (activeMatch['hum'] != null) {
                final h = (activeMatch['hum'] as num?)?.round() ??
                    int.tryParse(activeMatch['hum'].toString());
                if (h != null && h > 0) _humidity = h;
              }
            });

            debugPrint(
                '📡 [API] Updated live status via API: online=$_isActive, power=$_isPowerOn, setTemp=$_setTemp, curTemp=$_currentTemp, imei=$_activeDeviceImei');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [API] Error fetching live status via API: $e');
    }
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

    final String eqKeyInit = _selectedEquipmentId.isNotEmpty ? _selectedEquipmentId : _effectiveDeviceId;
    final bool? savedPower = prefs.getBool('ac_power_$eqKeyInit') ??
        prefs.getBool('ac_power_$_effectiveDeviceId');

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
        final activeLower = _activeDeviceId.toLowerCase();
        final imeiLower = _activeDeviceImei.toLowerCase();
        final selectedLower = _selectedEquipmentId.toLowerCase();
        return (selectedLower.isNotEmpty && id == selectedLower) ||
            (activeLower.isNotEmpty && imei == activeLower) ||
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
      }
      if (savedPower != null) {
        _isPowerOn = savedPower;
        if (_isPowerOn) {
          _fanRotationCtrl.repeat();
        } else {
          _fanRotationCtrl.stop();
        }
      } else {
        _isPowerOn = initial.isPowerOn;
        if (_isPowerOn) {
          _fanRotationCtrl.repeat();
        } else {
          _fanRotationCtrl.stop();
        }
      }
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
        } else if (savedPower != null) {
          _isPowerOn = savedPower;
          if (_isPowerOn) {
            _fanRotationCtrl.repeat();
          } else {
            _fanRotationCtrl.stop();
          }
        }
      }
      if (!_isActive) {
        _heartbeatTimer?.cancel();
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

        // Dynamically bind to the physical device ID only if active device and selected equipment are unset.
        final fallbackId = AppConfig.mqttDeviceId.toLowerCase();
        if (_selectedEquipmentId.isEmpty &&
            (_activeDeviceId.isEmpty ||
                _activeDeviceId.toLowerCase() == fallbackId)) {
          if (state.deviceId.isNotEmpty &&
              state.deviceId.toLowerCase() != fallbackId) {
            debugPrint(
                '🔄 [UI] Binding active device ID to ${state.deviceId} from hardware telemetry');
            _activeDeviceId = state.deviceId;
            _loadCachedSchedules();
          }
        }

        // Power sync lock: ignore incoming telemetry power state
        // if we are waiting for an ACK (_pendingPower) or if the user explicitly commanded the state
        // (to avoid UI reversion lag from open-loop IR blaster telemetry which reports static OFF).
        final String eqKey = _selectedEquipmentId.isNotEmpty
            ? _selectedEquipmentId
            : _effectiveDeviceId;
        _lastPowerToggleTime = _equipmentPowerToggleTimes[eqKey];
        _pendingPower = _equipmentPendingPower[eqKey] ?? false;

        final secondsSinceToggle = _lastPowerToggleTime == null
            ? 100
            : DateTime.now().difference(_lastPowerToggleTime!).inSeconds;

        // Auto-expire power toggle lock after 12 seconds so stale lock never blocks real state forever
        if (secondsSinceToggle >= 12) {
          _lastPowerToggleTime = null;
          _equipmentPowerToggleTimes.remove(eqKey);
          _pendingPower = false;
          _equipmentPendingPower[eqKey] = false;
        }

        if (_pendingPower || _lastPowerToggleTime != null) {
          // If incoming hardware telemetry matches our intended optimistic state, release the pending lock!
          if (state.isPowerOn == _isPowerOn) {
            _pendingPower = false;
            _equipmentPendingPower[eqKey] = false;
          }
          // Retain the user's commanded power state and do not allow open-loop telemetry to revert it.
        } else {
          // Only adopt hardware power state if hardware explicitly reports ON.
          // Open-loop IR blaster telemetry reporting static 'OFF' must NEVER turn off
          // an AC that the user explicitly commanded ON!
          if (state.isPowerOn) {
            _isPowerOn = true;
            if (mounted) _fanRotationCtrl.repeat();
          }
          _pendingPower = false;
          _equipmentPendingPower[eqKey] = false;
        }

        // Temperature sync logic:
        _lastUserTempChangeTime = _equipmentUserTempTimes[eqKey];
        _userTempOverride = _equipmentUserTempOverrides[eqKey] ?? false;

        final secondsSinceTempChange = _lastUserTempChangeTime == null
            ? 100
            : DateTime.now().difference(_lastUserTempChangeTime!).inSeconds;

        if (_userTempOverride || secondsSinceTempChange < 8) {
          // While user override / lock window is active, protect against duplicate or stale MQTT packets
          if (state.setTemp == _setTemp && secondsSinceTempChange >= 4) {
            _userTempOverride = false;
            _equipmentUserTempOverrides[eqKey] = false;
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
        _fetchStatusViaApi();
      } else if (resp.type == SirisResponseType.acOffDone) {
        setState(() {
          _isPowerOn = false;
          _pendingPower = false;
          _fanRotationCtrl.stop();
        });
        _showSnack('AC turned OFF', AppColors.offline);
        _fetchStatusViaApi();
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
        _fetchStatusViaApi();
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
        _fetchStatusViaApi();
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

    final String resolvedCompanyId = (widget.companyId != null && widget.companyId!.isNotEmpty)
        ? widget.companyId!
        : (await AuthService.getCompanyId() ?? '');

    final connected = await _mqtt.connect(
      deviceId: _activeDeviceId,
      imei: _activeDeviceImei,
      companyId: resolvedCompanyId.isNotEmpty ? resolvedCompanyId : null,
    );
    if (mounted) setState(() => _isConnected = connected);
  }

  Future<void> _fetchEquipments() async {
    if (widget.systemId == null) {
      // Standalone mode - use default device ID
      setState(() {
        _activeDeviceId = AppConfig.mqttDeviceId;
        _activeDeviceImei = '';
        _selectedEquipmentName = widget.deviceName ?? 'AC Remote';
      });
      _connectMqtt();
      return;
    }

    setState(() => _isLoadingEquipments = true);

    List<Map<String, dynamic>> allEquips = [];

    final companyId = widget.companyId ?? await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';
    String zoneId = await AuthService.getZoneId() ?? '';

    // Dynamically retrieve MQTT configuration exclusively via API
    if (companyId.isNotEmpty) {
      await MqttConfigService.fetchMqttConfig(companyId: companyId, type: 'ac');
    }

    // 1. Fetch equipments for this system directly via GET /systems/equipment/${widget.systemId}
    try {
      final sysEqUrl =
          '${AppConfig.provisionBaseUrl}/systems/equipment/${widget.systemId}'
          '?companyId=$companyId&siteId=$siteId';
      debugPrint('🌐 [ACControl] Fetching equipments for system: $sysEqUrl');

      final response = await http.get(
        Uri.parse(sysEqUrl),
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
          allEquips = listData.map((e) => Map<String, dynamic>.from(e)).toList();
          debugPrint('✅ [ACControl] Successfully retrieved ${allEquips.length} equipments for system ${widget.systemId}');
        }
      } else {
        debugPrint('⚠️ [ACControl] System equipment API returned HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('⚠️ [ACControl] Error fetching system equipment: $e');
    }

    // Resolve zoneId from allEquips if not yet set
    if (zoneId.isEmpty && allEquips.isNotEmpty) {
      for (var e in allEquips) {
        final z = (e['zoneId'] ?? e['ZoneId'] ?? '').toString();
        if (z.isNotEmpty && z != '00000000-0000-0000-0000-000000000000') {
          zoneId = z;
          break;
        }
      }
    }

    // 2. Fetch live equipment status & IMEIs from /mqtt/ac/status for this system
    final Map<String, Map<String, dynamic>> statusByEquipmentId = {};
    final Map<String, Map<String, dynamic>> statusByDevId = {};

    try {
      if (companyId.isNotEmpty && siteId.isNotEmpty && zoneId.isNotEmpty) {
        final statusUrl =
            '${AppConfig.provisionBaseUrl}/mqtt/ac/status?companyId=$companyId&siteId=$siteId&zoneId=$zoneId&systemId=${widget.systemId}';
        debugPrint('🌐 [ACControl] Fetching system AC statuses: $statusUrl');

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
          for (var sys in systemsData) {
            final List<dynamic> eqs = sys['equipments'] ?? [];
            for (var eq in eqs) {
              final eqMap = Map<String, dynamic>.from(eq);
              final eqId = (eqMap['equipmentId'] ?? eqMap['EquipmentId'] ?? eqMap['id'] ?? eqMap['Id'] ?? '').toString().toLowerCase().trim();
              final imei = (eqMap['imei'] ?? eqMap['Imei'] ?? '').toString().toLowerCase().trim();
              final name = (eqMap['name'] ?? eqMap['Name'] ?? '').toString().toLowerCase().trim();
              final shortId = (eqMap['shortId'] ?? eqMap['ShortId'] ?? '').toString().toLowerCase().trim();

              if (eqId.isNotEmpty) statusByEquipmentId[eqId] = eqMap;
              if (imei.isNotEmpty && !_isPlaceholderId(imei)) statusByDevId[imei] = eqMap;
              if (shortId.isNotEmpty && !_isPlaceholderId(shortId)) statusByDevId[shortId] = eqMap;
              if (name.isNotEmpty) statusByDevId[name] = eqMap;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [ACControl] Live status fetch error: $e');
    }

    // 3. Fallback: If systems/equipment endpoint returned nothing, try statusByEquipmentId or local devices
    if (allEquips.isEmpty) {
      if (statusByEquipmentId.isNotEmpty) {
        allEquips = statusByEquipmentId.values.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        // Try local devices as a last resort
        try {
          final prefs = await SharedPreferences.getInstance();
          final localDevicesJson = prefs.getString('local_provisioned_devices') ?? '[]';
          final List<dynamic> localList = jsonDecode(localDevicesJson);
          for (var localDev in localList) {
            final localMap = Map<String, dynamic>.from(localDev);
            final sysId = (localMap['systemId'] ?? localMap['SystemId'] ?? '').toString();
            if (sysId.toLowerCase() == widget.systemId!.toLowerCase()) {
              allEquips.add(localMap);
            }
          }
        } catch (_) {}
      }
    }

    // 4. Enrich allEquips with live data (hardware IMEI, status, setTemp, currentTemp, humidity)
    for (var eq in allEquips) {
      final eqId = (eq['id'] ?? eq['Id'] ?? eq['equipmentId'] ?? eq['EquipmentId'] ?? '').toString().toLowerCase().trim();
      final currentImei = (eq['imei'] ?? eq['Imei'] ?? '').toString().trim();
      final shortId = (eq['shortId'] ?? eq['ShortId'] ?? '').toString().toLowerCase().trim();
      final name = (eq['name'] ?? eq['Name'] ?? '').toString().toLowerCase().trim();

      final liveInfo = statusByEquipmentId[eqId] ??
          (currentImei.isNotEmpty && !_isPlaceholderId(currentImei) ? statusByDevId[currentImei.toLowerCase()] : null) ??
          (shortId.isNotEmpty && !_isPlaceholderId(shortId) ? statusByDevId[shortId] : null) ??
          (name.isNotEmpty ? statusByDevId[name] : null);

      if (liveInfo != null) {
        final liveImei = (liveInfo['imei'] ?? liveInfo['Imei'] ?? '').toString().trim();
        if (liveImei.isNotEmpty && !_isPlaceholderId(liveImei)) {
          eq['imei'] = liveImei;
        }
        final statusStr = (liveInfo['status'] ?? liveInfo['Status'] ?? 'DISCONNECTED').toString().toUpperCase().trim();
        final bool isOnline = statusStr == 'ON' || statusStr == 'OFF' || statusStr == 'ONLINE' || statusStr == 'CONNECTED' || statusStr == 'ACTIVE';
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
      }

      // If IMEI is still missing or placeholder, fetch individual equipment detail
      final finalImei = (eq['imei'] ?? eq['Imei'] ?? '').toString().trim();
      if ((finalImei.isEmpty || _isPlaceholderId(finalImei)) && eqId.isNotEmpty) {
        final fetchedImei = await _fetchEquipmentImei(eqId);
        if (fetchedImei.isNotEmpty && !_isPlaceholderId(fetchedImei)) {
          eq['imei'] = fetchedImei;
        }
      }
    }

    final List<Map<String, dynamic>> filteredList = allEquips;

    if (mounted && filteredList.isNotEmpty) {
      setState(() {
        _equipmentsData = List<Map<String, dynamic>>.from(filteredList);
        _isLoadingEquipments = false;
      });

      // Find matching equipment
      Map<String, dynamic>? currentMatch;

      // 1. By passed widget.equipmentId
      if (widget.equipmentId != null && widget.equipmentId!.isNotEmpty) {
        for (var eq in filteredList) {
          final eqId = (eq['id'] ?? eq['Id'] ?? eq['equipmentId'] ?? eq['EquipmentId'] ?? '').toString();
          if (eqId.toLowerCase() == widget.equipmentId!.toLowerCase()) {
            currentMatch = eq;
            break;
          }
        }
      }

      // 2. By selected equipment ID if already set
      if (currentMatch == null && _selectedEquipmentId.isNotEmpty) {
        for (var eq in filteredList) {
          final eqId = (eq['id'] ?? eq['Id'] ?? eq['equipmentId'] ?? eq['EquipmentId'] ?? '').toString();
          if (eqId.toLowerCase() == _selectedEquipmentId.toLowerCase()) {
            currentMatch = eq;
            break;
          }
        }
      }

      // 3. By active hardware IMEI
      if (currentMatch == null) {
        final targetImei = _activeDeviceImei.isNotEmpty
            ? _activeDeviceImei
            : ((widget.systemShortId != null && !_isPlaceholderId(widget.systemShortId))
                ? widget.systemShortId!
                : '');
        if (targetImei.isNotEmpty) {
          for (var eq in filteredList) {
            final eqImei = (eq['imei'] ?? eq['Imei'] ?? eq['deviceId'] ?? eq['DeviceId'] ?? '').toString();
            if (eqImei.toLowerCase() == targetImei.toLowerCase()) {
              currentMatch = eq;
              break;
            }
          }
        }
      }

      // 4. Default to first equipment
      Map<String, dynamic> selected = currentMatch ?? filteredList.first;
      final selectedId = (selected['id'] ??
              selected['Id'] ??
              selected['equipmentId'] ??
              selected['EquipmentId'] ??
              '')
          .toString();

      // If we are already looking at this equipment, update live telemetry & power
      if (_selectedEquipmentId.isNotEmpty && _selectedEquipmentId == selectedId) {
        final eqImei = (selected['imei'] ??
                selected['Imei'] ??
                selected['deviceId'] ??
                selected['DeviceId'] ??
                selected['device_id'])
            ?.toString()
            .trim();
        if (eqImei != null && eqImei.isNotEmpty && !_isPlaceholderId(eqImei)) {
          _activeDeviceImei = eqImei;
          _activeDeviceId = eqImei;
          _mqtt.setDeviceId(eqImei, imei: eqImei);
        }
        if (selected['name'] != null && selected['name'].toString().isNotEmpty) {
          _selectedEquipmentName = selected['name'].toString();
        }
        final statusVal = selected['onOffStatus'] is Map
            ? selected['onOffStatus']['status']?.toString().toUpperCase()
            : selected['status']?.toString().toUpperCase();
        if (mounted) {
          setState(() {
            _isActive = selected['isOnline'] == true ||
                selected['isActive'] == true ||
                statusVal == 'ON' ||
                statusVal == 'OFF' ||
                statusVal == 'ACTIVE';

            if (_lastPowerToggleTime == null && !_pendingPower) {
              if (statusVal == 'ON') {
                _isPowerOn = true;
                _fanRotationCtrl.repeat();
              } else if (statusVal == 'OFF') {
                _isPowerOn = false;
                _fanRotationCtrl.stop();
              }
            }

            if (selected['setTemp'] != null && !_userTempOverride) {
              final sTemp = int.tryParse(selected['setTemp'].toString());
              if (sTemp != null && sTemp >= 16 && sTemp <= 30) {
                _setTemp = sTemp;
              }
            }
            if (selected['currentTemp'] != null) {
              final cTemp = (selected['currentTemp'] as num?)?.toInt() ??
                  int.tryParse(selected['currentTemp'].toString());
              if (cTemp != null && cTemp > 0) _currentTemp = cTemp;
            }
            if (selected['humidity'] != null) {
              final h = (selected['humidity'] as num?)?.round() ??
                  int.tryParse(selected['humidity'].toString());
              if (h != null && h > 0) _humidity = h;
            }
          });
        }
        _fetchStatusViaApi();
        return;
      }

      await _onEquipmentSelected(
        selectedId,
        selected['name']?.toString() ?? 'AC Unit',
      );
      _fetchStatusViaApi();
      return;
    }

    // Fallback if anything fails and list is empty
    if (mounted) {
      setState(() {
        _activeDeviceId = (widget.systemId != null && !_isPlaceholderId(widget.systemId))
            ? widget.systemId!
            : AppConfig.mqttDeviceId;
        _activeDeviceImei = '';
        _selectedEquipmentName = widget.deviceName ?? 'AC Remote';
        _isLoadingEquipments = false;
      });
      _connectMqtt();
    }
  }

  Future<String> _fetchEquipmentImei(String equipmentId) async {
    final companyId = widget.companyId ?? await AuthService.getCompanyId() ?? '';
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
                  first['deviceId'] ??
                  first['DeviceId'] ??
                  '')
              .toString();
        } else if (equipData is Map) {
          return (equipData['imei'] ??
                  equipData['Imei'] ??
                  equipData['deviceId'] ??
                  equipData['DeviceId'] ??
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
      foundImei = (match['imei'] ??
              match['Imei'] ??
              match['deviceId'] ??
              match['DeviceId'] ??
              match['device_id'])
          ?.toString()
          .trim();
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

    // Strictly resolve target hardware identity from IMEI and deviceId (never use shortId)
    String deviceId = '';
    if (foundImei != null && foundImei.isNotEmpty && !_isPlaceholderId(foundImei)) {
      deviceId = foundImei;
    } else {
      final fetchedImei = await _fetchEquipmentImei(equipmentId);
      if (fetchedImei.isNotEmpty && !_isPlaceholderId(fetchedImei)) {
        deviceId = fetchedImei;
      } else {
        final devIdFromData = (match != null
                ? (match['deviceId'] ??
                    match['DeviceId'] ??
                    match['device_id'] ??
                    match['imei'] ??
                    match['Imei'])
                : null)
            ?.toString()
            .trim();
        if (devIdFromData != null &&
            devIdFromData.isNotEmpty &&
            !_isPlaceholderId(devIdFromData)) {
          deviceId = devIdFromData;
        } else if (widget.systemShortId != null &&
            !_isPlaceholderId(widget.systemShortId)) {
          deviceId = widget.systemShortId!;
        } else if (widget.systemId != null && !_isPlaceholderId(widget.systemId)) {
          deviceId = widget.systemId!;
        } else {
          deviceId = equipmentId;
        }
      }
    }

    final String finalImei = (foundImei != null && foundImei.isNotEmpty && !_isPlaceholderId(foundImei))
        ? foundImei
        : (deviceId.isNotEmpty && !_isPlaceholderId(deviceId) ? deviceId : '');

    _heartbeatTimer?.cancel();

    final prefs = await SharedPreferences.getInstance();
    final savedPower = prefs.getBool('ac_power_$equipmentId') ??
        (deviceId.isNotEmpty ? prefs.getBool('ac_power_$deviceId') : null) ??
        _mqtt.getLastStateFor(deviceId)?.isPowerOn;

    final String newEqKey = equipmentId.isNotEmpty ? equipmentId : deviceId;
    _lastPowerToggleTime = _equipmentPowerToggleTimes[newEqKey];
    _pendingPower = _equipmentPendingPower[newEqKey] ?? false;
    _lastUserTempChangeTime = _equipmentUserTempTimes[newEqKey];
    _userTempOverride = _equipmentUserTempOverrides[newEqKey] ?? false;
    _pendingTemp = false;

    setState(() {
      _selectedEquipmentId = equipmentId;
      _selectedEquipmentName = name;
      _isLoadingEquipments = true;
      _isConnected = false;
      _isActive = isEqOnline;
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
        } else if (savedPower != null) {
          _isPowerOn = savedPower;
          if (_isPowerOn) {
            _fanRotationCtrl.repeat();
          } else {
            _fanRotationCtrl.stop();
          }
        }
      }
    });

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
        _activeDeviceImei = finalImei;
      });
      _mqtt.setDeviceId(deviceId, imei: finalImei.isNotEmpty ? finalImei : null);
      _connectMqtt();
      _fetchStatusViaApi();
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
      builder: (ctx) => TopMessageBarWidget(
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
    _apiPollingTimer?.cancel();
    _apiSyncTimer?.cancel();
    _apiSyncSecondaryTimer?.cancel();
    _apiSyncTertiaryTimer?.cancel();
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
      debugPrint('🔄 [Lifecycle] App resumed. Reconnecting MQTT, SSE and refreshing API status...');
      _connectMqtt();
      _fetchStatusViaApi();
    }
  }

  // ── MQTT Actions ──────────────────────────────────────────────────────

  void _togglePower() {
    if (!_isControlAvailable) {
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

    final String eqKey = _selectedEquipmentId.isNotEmpty
        ? _selectedEquipmentId
        : _effectiveDeviceId;

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
      // SIRIS v2 Spec Note 3: ON / OFF silently disable auto mode (autoMode=false, state HOLD)
      _isAutomated = false;
      if (_isPowerOn) {
        _fanRotationCtrl.repeat();
      } else {
        _fanRotationCtrl.stop();
      }

      if (eqKey.isNotEmpty) {
        _equipmentPowerToggleTimes[eqKey] = _lastPowerToggleTime!;
        _equipmentPendingPower[eqKey] = true;
        _equipmentUserTempTimes[eqKey] = _lastUserTempChangeTime!;
        _equipmentUserTempOverrides[eqKey] = _userTempOverride;
      }
    });

    SharedPreferences.getInstance().then((prefs) {
      if (_selectedEquipmentId.isNotEmpty) {
        prefs.setBool('ac_power_$_selectedEquipmentId', _isPowerOn);
      }
      prefs.setBool('auto_enabled', false);
    });

    if (wasPowerOn) {
      _mqtt.turnAcOff(
        targetDeviceId: _effectiveDeviceId,
        targetDeviceImei:
            _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
      );
    } else {
      _mqtt.turnAcOn(
        targetDeviceId: _effectiveDeviceId,
        targetDeviceImei:
            _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
      );
    }

    // Follow up by checking live equipment status via API
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _fetchStatusViaApi();
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) _fetchStatusViaApi();
    });
  }

  void _incrementTemp() {
    if (!_isPowerOn) {
      _showSnack('AC is OFF. Turn on AC to adjust temperature.',
          AppColors.offline,
          icon: Icons.power_settings_new_rounded);
      return;
    }
    if (!_isControlAvailable) {
      _showSnack('Device is offline. Connect to Wi-Fi to use controls.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded);
      return;
    }
    if (_setTemp >= 30) return;
    final String eqKey = _selectedEquipmentId.isNotEmpty
        ? _selectedEquipmentId
        : _effectiveDeviceId;
    setState(() {
      _setTemp++;
      _userTempOverride = true;
      _pendingTemp = true;
      _lastUserTempChangeTime = DateTime.now();
      if (eqKey.isNotEmpty) {
        _equipmentUserTempOverrides[eqKey] = true;
        _equipmentUserTempTimes[eqKey] = _lastUserTempChangeTime!;
      }
    });
    _addLog('Temperature set to $_setTemp°C (TEMP_UP / TEMP:$_setTemp)', AppColors.coolBlue);
    _mqtt.tempUp(
      targetDeviceId: _effectiveDeviceId,
      targetDeviceImei:
          _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
    );
    _mqtt.setTemperature(
      _setTemp,
      targetDeviceId: _effectiveDeviceId,
      targetDeviceImei:
          _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
    );
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _pendingTemp) {
        setState(() => _pendingTemp = false);
      }
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _fetchStatusViaApi();
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) _fetchStatusViaApi();
    });
  }

  void _decrementTemp() {
    if (!_isPowerOn) {
      _showSnack('AC is OFF. Turn on AC to adjust temperature.',
          AppColors.offline,
          icon: Icons.power_settings_new_rounded);
      return;
    }
    if (!_isControlAvailable) {
      _showSnack('Device is offline. Connect to Wi-Fi to use controls.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded);
      return;
    }
    if (_setTemp <= 16) return;
    final String eqKey = _selectedEquipmentId.isNotEmpty
        ? _selectedEquipmentId
        : _effectiveDeviceId;
    setState(() {
      _setTemp--;
      _userTempOverride = true;
      _pendingTemp = true;
      _lastUserTempChangeTime = DateTime.now();
      if (eqKey.isNotEmpty) {
        _equipmentUserTempOverrides[eqKey] = true;
        _equipmentUserTempTimes[eqKey] = _lastUserTempChangeTime!;
      }
    });
    _addLog('Temperature set to $_setTemp°C (TEMP_DOWN / TEMP:$_setTemp)', AppColors.coolBlue);
    _mqtt.tempDown(
      targetDeviceId: _effectiveDeviceId,
      targetDeviceImei:
          _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
    );
    _mqtt.setTemperature(
      _setTemp,
      targetDeviceId: _effectiveDeviceId,
      targetDeviceImei:
          _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
    );
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _pendingTemp) {
        setState(() => _pendingTemp = false);
      }
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _fetchStatusViaApi();
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) _fetchStatusViaApi();
    });
  }

  /// SIRIS v2 Spec Section 2: Reset setpoint to 24°C default via TEMP_CLEAR
  void _resetTempToDefault() {
    if (!_isPowerOn) {
      _showSnack('AC is OFF. Turn on AC to adjust temperature.',
          AppColors.offline,
          icon: Icons.power_settings_new_rounded);
      return;
    }
    if (!_isControlAvailable) {
      _showSnack('Device is offline. Connect to Wi-Fi to use controls.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded);
      return;
    }
    final String eqKey = _selectedEquipmentId.isNotEmpty
        ? _selectedEquipmentId
        : _effectiveDeviceId;
    setState(() {
      _setTemp = 24;
      _userTempOverride = true;
      _pendingTemp = true;
      _lastUserTempChangeTime = DateTime.now();
      if (eqKey.isNotEmpty) {
        _equipmentUserTempOverrides[eqKey] = true;
        _equipmentUserTempTimes[eqKey] = _lastUserTempChangeTime!;
      }
    });
    _addLog('Temperature reset to 24°C (TEMP_CLEAR)', AppColors.coolBlue);
    _mqtt.tempClear(
      targetDeviceId: _effectiveDeviceId,
      targetDeviceImei:
          _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
    );
    _mqtt.setTemperature(
      24,
      targetDeviceId: _effectiveDeviceId,
      targetDeviceImei:
          _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
    );
    _showSnack('Target setpoint reset to 24°C (TEMP_CLEAR)', AppColors.primary,
        icon: Icons.restart_alt_rounded);
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _fetchStatusViaApi();
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) _fetchStatusViaApi();
    });
  }

  /// SIRIS v2 Spec Section 2: Toggle Smart Automation Mode (`AUTO:<temp>` / `AUTO_OFF`)
  void _toggleAutoMode() {
    if (!_isPowerOn) {
      _showSnack('AC is OFF. Turn on AC to use smart automation.',
          AppColors.offline,
          icon: Icons.power_settings_new_rounded);
      return;
    }
    if (!_isControlAvailable) {
      _showSnack('Device is offline. Connect to Wi-Fi to use smart automation.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded);
      return;
    }
    final bool nextState = !_isAutomated;
    setState(() {
      _isAutomated = nextState;
    });
    _addLog(
        'Smart Automation ${nextState ? "ENABLED ($_autoTemp°C)" : "DISABLED"}',
        AppColors.primary);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('auto_enabled', nextState);
    });
    if (nextState) {
      _mqtt.enableAutomation(
        autoTemp: _autoTemp,
        targetDeviceId: _effectiveDeviceId,
        targetDeviceImei:
            _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
      );
    } else {
      _mqtt.disableAutomation(
        targetDeviceId: _effectiveDeviceId,
        targetDeviceImei:
            _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
      );
    }
    _showSnack(
      'Smart Automation ${nextState ? "Enabled ($_autoTemp°C)" : "Disabled"}',
      nextState ? AppColors.online : AppColors.offline,
      icon: Icons.smart_toy_rounded,
    );
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _fetchStatusViaApi();
    });
  }

  /// SIRIS v2 Spec Section 2 & 8: Request full telemetry snapshot via STATUS
  void _requestStatus() {
    _mqtt.sendStatus(
      targetDeviceId: _effectiveDeviceId,
      targetDeviceImei:
          _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
    );
    _showSnack('Requesting live status from device (STATUS)', AppColors.coolBlue,
        icon: Icons.sync_rounded);
    _fetchStatusViaApi();
  }

  String _formatLastSeen(DateTime dt) => formatLastSeen(dt);

  void _showSseInfoDialog(BuildContext context, bool isDark) {
    showSseInfoDialog(
      context: context,
      isDark: isDark,
      mqtt: _mqtt,
      activeDeviceId: _effectiveDeviceId,
      activeDeviceImei: _activeDeviceImei,
    );
  }

  Widget _buildWeeklyDaysSelector({
    required int slot,
    bool isEnabled = true,
    required bool isDark,
    required StateSetter setModalState,
  }) {
    final rawDays = _savedSchDays[slot] ?? 'ALL';
    return buildWeeklyDaysSelector(
      slot: slot,
      currentDays: rawDays,
      isEnabled: isEnabled,
      isDark: isDark,
      isControlAvailable: _isControlAvailable,
      isActive: _isActive,
      isBluetoothConnected: _mqtt.isBluetoothConnected,
      effectiveDeviceId: _effectiveDeviceId,
      mqtt: _mqtt,
      setModalState: setModalState,
      onDaysChanged: (s, formattedDays) {
        _userSchOverrideTime[s] = DateTime.now();
        setModalState(() {
          _savedSchDays[s] = formattedDays;
        });
        setState(() {
          _savedSchDays[s] = formattedDays;
        });
      },
      showSnack: _showSnack,
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
        final String imei = (equip['imei'] ??
                equip['Imei'] ??
                equip['deviceId'] ??
                equip['DeviceId'] ??
                equip['device_id'] ??
                '')
            .toString()
            .trim();
        final String display =
            imei.isNotEmpty && imei.toLowerCase() != name.toLowerCase()
                ? '$name ($imei)'
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
          'imei': imei,
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
                    ? _selectedEquipmentName
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
                        Map<String, dynamic>? selected;
                        try {
                          selected = _equipmentsData.firstWhere((e) =>
                              (e['id'] ??
                                      e['Id'] ??
                                      e['equipmentId'] ??
                                      e['EquipmentId'] ??
                                      '')
                                  .toString() ==
                              val);
                        } catch (_) {}
                        _onEquipmentSelected(
                          val,
                          selected?['name']?.toString() ?? 'AC Unit',
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
            onPressed: () async {
              _mqtt.sendStatus(
                targetDeviceId: _effectiveDeviceId,
                targetDeviceImei:
                    _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
              );
              await _fetchEquipments();
              await _fetchStatusViaApi();
              _showSnack('Reloaded equipment status', AppColors.primary,
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

                  return content;
                },
              ),
      ),
    );
  }
}
