import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/core/services/admin_service.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';

class ResponseLogEntry {
  final DateTime timestamp;
  final SirisResponseType type;
  final String title;
  final String detail;
  final String rawPayload;

  ResponseLogEntry({
    required this.timestamp,
    required this.type,
    required this.title,
    required this.detail,
    required this.rawPayload,
  });
}

class CapturedSignalDetail {
  final String target;
  final String length;
  final DateTime timestamp;
  final String rawPayload;

  CapturedSignalDetail({
    required this.target,
    required this.length,
    required this.timestamp,
    required this.rawPayload,
  });
}

class IRLearningConfigPage extends StatefulWidget {
  final String? initialDeviceId;

  const IRLearningConfigPage({super.key, this.initialDeviceId});

  @override
  State<IRLearningConfigPage> createState() => _IRLearningConfigPageState();
}

class _IRLearningConfigPageState extends State<IRLearningConfigPage> {
  final MqttService _mqttService = MqttService();
  StreamSubscription<SirisResponse>? _responseSub;
  StreamSubscription<SirisDeviceState>? _stateSub;

  List<Map<String, dynamic>> _devices = [];
  String _selectedDeviceId = '';
  bool _isLoadingDevices = false;
  bool _isReloadingDevice = false;

  String _lastSavedTarget = '';
  String _lastSavedLength = '';
  String _lastSavedMessage = '';

  // Log terminal state & temperature control state
  final List<ResponseLogEntry> _responseLogs = [];
  bool _showOnlyCaptureLogs = false;
  int _controlSetTemp = 24;

  // Captured Signal Details & Latest Response Values
  final Map<String, CapturedSignalDetail> _signalDetailMap = {};
  CapturedSignalDetail? _latestResponseDetail;

  // Learned IR Signal Map (30 signals total: POWER ON, POWER OFF, 14 UP steps, 14 DOWN steps)
  final Map<String, bool> _learnedSignalMap = {
    'POWER_ON': false,
    'POWER_OFF': false,
    for (int t = 16; t <= 29; t++) 'UP_$t': false,
    for (int t = 17; t <= 30; t++) 'DOWN_$t': false,
  };

  void _storeSignalDetail(String target, CapturedSignalDetail detailObj) {
    _latestResponseDetail = detailObj;
    final upper = target.toUpperCase();
    if (upper.contains('POWER ON') ||
        upper.contains('POWER_ON') ||
        upper == 'ON') {
      _signalDetailMap['POWER_ON'] = detailObj;
      _signalDetailMap['ON'] = detailObj;
    } else if (upper.contains('POWER OFF') ||
        upper.contains('POWER_OFF') ||
        upper == 'OFF') {
      _signalDetailMap['POWER_OFF'] = detailObj;
      _signalDetailMap['OFF'] = detailObj;
    } else if (upper.contains('UP')) {
      final match = RegExp(r'(\d+)').firstMatch(upper);
      if (match != null) {
        final t = match.group(1)!;
        _signalDetailMap['UP_$t'] = detailObj;
        _signalDetailMap['TEMP_UP_$t'] = detailObj;
        _signalDetailMap['UP_$t°C'] = detailObj;
      }
    } else if (upper.contains('DOWN')) {
      final match = RegExp(r'(\d+)').firstMatch(upper);
      if (match != null) {
        final t = match.group(1)!;
        _signalDetailMap['DOWN_$t'] = detailObj;
        _signalDetailMap['TEMP_DOWN_$t'] = detailObj;
        _signalDetailMap['DOWN_$t°C'] = detailObj;
      }
    }
  }

  void _markLearnedSignalFromSave(String target) {
    final upper = target.toUpperCase();
    if (upper.contains('POWER ON') ||
        upper.contains('POWER_ON') ||
        upper == 'ON') {
      _learnedSignalMap['POWER_ON'] = true;
    } else if (upper.contains('POWER OFF') ||
        upper.contains('POWER_OFF') ||
        upper == 'OFF') {
      _learnedSignalMap['POWER_OFF'] = true;
    } else if (upper.contains('UP')) {
      final match = RegExp(r'(\d+)').firstMatch(upper);
      if (match != null) {
        final t = int.tryParse(match.group(1)!);
        if (t != null && t >= 16 && t <= 29) {
          _learnedSignalMap['UP_$t'] = true;
        }
      }
    } else if (upper.contains('DOWN')) {
      final match = RegExp(r'(\d+)').firstMatch(upper);
      if (match != null) {
        final t = int.tryParse(match.group(1)!);
        if (t != null && t >= 17 && t <= 30) {
          _learnedSignalMap['DOWN_$t'] = true;
        }
      }
    }
  }

  void _markLearnedSignalFromClear(String detail) {
    final upper = detail.toUpperCase();
    if (upper.contains('CLEAR_ALL') || upper.contains('ALL')) {
      for (var key in _learnedSignalMap.keys) {
        _learnedSignalMap[key] = false;
      }
      _signalDetailMap.clear();
    } else if (upper.contains('POWER ON') ||
        upper.contains('POWER_ON') ||
        upper.contains('CLEAR_ON') ||
        upper.contains('ON')) {
      _learnedSignalMap['POWER_ON'] = false;
      _signalDetailMap.remove('POWER_ON');
      _signalDetailMap.remove('ON');
    } else if (upper.contains('POWER OFF') ||
        upper.contains('POWER_OFF') ||
        upper.contains('CLEAR_OFF') ||
        upper.contains('OFF')) {
      _learnedSignalMap['POWER_OFF'] = false;
      _signalDetailMap.remove('POWER_OFF');
      _signalDetailMap.remove('OFF');
    } else if (upper.contains('UP')) {
      final match = RegExp(r'(\d+)').firstMatch(upper);
      if (match != null) {
        final t = int.tryParse(match.group(1)!);
        if (t != null && t >= 16 && t <= 29) {
          _learnedSignalMap['UP_$t'] = false;
          _signalDetailMap.remove('UP_$t');
          _signalDetailMap.remove('TEMP_UP_$t');
          _signalDetailMap.remove('UP_$t°C');
        }
      }
    } else if (upper.contains('DOWN')) {
      final match = RegExp(r'(\d+)').firstMatch(upper);
      if (match != null) {
        final t = int.tryParse(match.group(1)!);
        if (t != null && t >= 17 && t <= 30) {
          _learnedSignalMap['DOWN_$t'] = false;
          _signalDetailMap.remove('DOWN_$t');
          _signalDetailMap.remove('TEMP_DOWN_$t');
          _signalDetailMap.remove('DOWN_$t°C');
        }
      }
    }
  }

  void _parseStatusDetail(String detail) {
    final upper = detail.toUpperCase();

    // Check ON status
    if (upper.contains('ON=YES') || upper.contains('ON=1')) {
      _learnedSignalMap['POWER_ON'] = true;
    } else if (upper.contains('ON=NO') || upper.contains('ON=0')) {
      _learnedSignalMap['POWER_ON'] = false;
    }

    // Check OFF status
    if (upper.contains('OFF=YES') || upper.contains('OFF=1')) {
      _learnedSignalMap['POWER_OFF'] = true;
    } else if (upper.contains('OFF=NO') || upper.contains('OFF=0')) {
      _learnedSignalMap['POWER_OFF'] = false;
    }

    // Check MISSING_UP csv
    if (upper.contains('MISSING_UP=')) {
      final match = RegExp(r'MISSING_UP=([^:]*)').firstMatch(upper);
      if (match != null) {
        final missingCsv = match.group(1) ?? '';
        final missingList = missingCsv
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toSet();
        for (int t = 16; t <= 29; t++) {
          _learnedSignalMap['UP_$t'] = !missingList.contains(t);
        }
      }
    }

    // Check MISSING_DOWN csv
    if (upper.contains('MISSING_DOWN=')) {
      final match = RegExp(r'MISSING_DOWN=([^:]*)').firstMatch(upper);
      if (match != null) {
        final missingCsv = match.group(1) ?? '';
        final missingList = missingCsv
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toSet();
        for (int t = 17; t <= 30; t++) {
          _learnedSignalMap['DOWN_$t'] = !missingList.contains(t);
        }
      }
    }

    // Fallback key=val pair parsing
    final clean = detail.replaceAll(' ', '');
    final pairs = clean.split(RegExp(r'[,;\n]'));
    for (var pair in pairs) {
      final kv = pair.split(RegExp(r'[:=]'));
      if (kv.length == 2) {
        String k = kv[0].toUpperCase().trim();
        final v = kv[1].trim();
        final bool isLearned =
            (v == '1' || v.toLowerCase() == 'true' || v.toLowerCase() == 'yes');

        if (k == 'ON' || k == 'POWER_ON' || k == 'POWERON') k = 'POWER_ON';
        if (k == 'OFF' || k == 'POWER_OFF' || k == 'POWEROFF') k = 'POWER_OFF';
        if (k.startsWith('UP') && !k.startsWith('UP_')) {
          k = k.replaceFirst('UP', 'UP_');
        }
        if (k.startsWith('DOWN') && !k.startsWith('DOWN_')) {
          k = k.replaceFirst('DOWN', 'DOWN_');
        }

        if (_learnedSignalMap.containsKey(k)) {
          _learnedSignalMap[k] = isLearned;
        }
      }
    }
  }

  // Selected temperatures for step capture/erase
  int _selectedUpTemp = 24; // Range: 16-29
  int _selectedDownTemp = 24; // Range: 17-30

  @override
  void initState() {
    super.initState();
    _selectedDeviceId = widget.initialDeviceId ?? _mqttService.deviceId;
    _loadDevices();
    _subscribeToMqttResponses();

    // Query status on load if connected and device is online
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrentDeviceOnline) {
        _requestStatus();
      }
    });
  }

  @override
  void dispose() {
    _responseSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  String _getItemCategory(Map<String, dynamic> d) {
    if (d['itemType'] == 'system') return 'System';
    return 'Equipment';
  }

  String _getEquipmentName(Map<String, dynamic> d) {
    if (d['itemType'] == 'system') {
      return (d['name'] ?? d['systemName'] ?? d['Name'] ?? 'System')
          .toString()
          .trim();
    }
    final eqName = (d['equipmentName'] ??
            d['EquipmentName'] ??
            d['name'] ??
            d['Name'] ??
            '')
        .toString()
        .trim();
    if (eqName.isNotEmpty) return eqName;
    final shortId = _getEquipmentShortId(d);
    return shortId.isNotEmpty ? shortId : 'AC Equipment';
  }

  String _getSystemName(Map<String, dynamic> d) {
    final sysName =
        (d['systemName'] ?? d['SystemName'] ?? d['system_name'] ?? '')
            .toString()
            .trim();
    if (sysName.isNotEmpty) return sysName;
    if (d['itemType'] == 'system') {
      return (d['name'] ?? d['Name'] ?? d['systemName'] ?? '')
          .toString()
          .trim();
    }
    return '';
  }

  String _getPrimaryDeviceId(Map<String, dynamic> d) {
    final imei = (d['imei'] ?? d['Imei'] ?? '').toString().trim();
    if (imei.isNotEmpty) return imei;
    final eqName = (d['equipmentName'] ??
            d['EquipmentName'] ??
            d['name'] ??
            d['Name'] ??
            '')
        .toString()
        .trim();
    if (eqName.isNotEmpty && eqName != 'AC Equipment' && eqName != 'System') {
      return eqName;
    }
    final devId =
        (d['deviceId'] ?? d['equipmentId'] ?? d['id'] ?? d['Id'] ?? '')
            .toString()
            .trim();
    if (devId.isNotEmpty) return devId;
    final shortId = (d['shortId'] ??
            d['ShortId'] ??
            d['equipmentShortId'] ??
            d['systemShortId'] ??
            '')
        .toString()
        .trim();
    return shortId;
  }

  String _getEquipmentShortId(Map<String, dynamic> d) {
    final sId = (d['shortId'] ??
            d['ShortId'] ??
            d['equipmentShortId'] ??
            d['ShortID'] ??
            d['systemShortId'] ??
            '')
        .toString()
        .trim();
    if (sId.isNotEmpty) return sId;
    final id = (d['id'] ??
            d['Id'] ??
            d['deviceId'] ??
            d['equipmentId'] ??
            d['systemId'] ??
            '')
        .toString()
        .trim();
    if (id.length > 12) {
      return '${id.substring(0, 8)}...${id.substring(id.length - 4)}';
    }
    return id;
  }

  String _getDropdownLabel(Map<String, dynamic> d) {
    final isSystem = d['itemType'] == 'system';
    final equipName = _getEquipmentName(d);
    final sysName = _getSystemName(d);

    if (isSystem) {
      return sysName.isNotEmpty ? 'System: $sysName' : equipName;
    } else {
      if (sysName.isNotEmpty && sysName != equipName) {
        return '$equipName • System: $sysName';
      } else {
        return equipName;
      }
    }
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoadingDevices = true);
    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';

      // 1. Fetch equipments from primary endpoint
      List<Map<String, dynamic>> equipments = [];
      try {
        equipments = await AdminService.fetchEquipments(
            companyId: companyId, siteId: siteId);
      } catch (e) {
        debugPrint('⚠️ [IRLearningConfig] fetchEquipments error: $e');
      }

      // 2. Fetch systems to get system names & fallback equipment lists
      final systems =
          await AdminService.fetchSystems(companyId: companyId, siteId: siteId);

      // Build systemNameMap for lookup
      final Map<String, String> systemNameMap = {};
      for (var sys in systems) {
        final sysId =
            (sys['systemId'] ?? sys['Id'] ?? sys['systemid'] ?? '').toString();
        final sName =
            (sys['name'] ?? sys['systemName'] ?? sys['Name'] ?? '').toString();
        if (sysId.isNotEmpty && sName.isNotEmpty) {
          systemNameMap[sysId.toLowerCase()] = sName;
        }
      }

      if (equipments.isEmpty && systems.isNotEmpty) {
        for (var sys in systems) {
          final sysId = (sys['systemId'] ?? sys['Id'] ?? sys['systemid'] ?? '')
              .toString();
          if (sysId.isNotEmpty) {
            try {
              final url =
                  '${AppConfig.provisionBaseUrl}/systems/equipment/$sysId?companyId=$companyId&siteId=$siteId';
              final response = await http.get(
                Uri.parse(url),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Cookie': 'auth_token=$token',
                  'Content-Type': 'application/json',
                },
              );
              if (response.statusCode == 200) {
                final body = jsonDecode(response.body);
                if (body['status'] == 1 && body['data'] is List) {
                  final List<dynamic> list = body['data'];
                  equipments
                      .addAll(list.map((e) => Map<String, dynamic>.from(e)));
                }
              }
            } catch (_) {}
          }
        }
      }

      // 3. Merge local provisioned devices
      try {
        final prefs = await SharedPreferences.getInstance();
        final localDevicesJson =
            prefs.getString('local_provisioned_devices') ?? '[]';
        final List<dynamic> localList = jsonDecode(localDevicesJson);
        for (var localDev in localList) {
          final localMap = Map<String, dynamic>.from(localDev);
          final String localId =
              (localMap['id'] ?? localMap['shortId'] ?? '').toString();
          final exists = equipments.any((e) {
            final eId =
                (e['id'] ?? e['Id'] ?? e['shortId'] ?? e['ShortId'] ?? '')
                    .toString();
            return eId.toLowerCase() == localId.toLowerCase();
          });
          if (!exists) {
            equipments.add(localMap);
          }
        }
      } catch (_) {}

      final List<Map<String, dynamic>> deviceList = [];
      final Set<String> addedIds = {};

      // Add Equipments with itemType = 'equipment'
      for (var e in equipments) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(e);
        map['itemType'] = 'equipment';
        final sysId =
            (map['systemId'] ?? map['SystemId'] ?? '').toString().toLowerCase();
        if ((map['systemName'] == null ||
                map['systemName'].toString().trim().isEmpty) &&
            systemNameMap.containsKey(sysId)) {
          map['systemName'] = systemNameMap[sysId];
        }

        final id = _getPrimaryDeviceId(map);
        if (id.isNotEmpty && !addedIds.contains(id.toLowerCase())) {
          addedIds.add(id.toLowerCase());
          deviceList.add(map);
        }
      }

      // Add Systems with itemType = 'system' ONLY as fallback if no equipments exist
      if (deviceList.isEmpty) {
        for (var s in systems) {
          final Map<String, dynamic> map = Map<String, dynamic>.from(s);
          map['itemType'] = 'system';
          final id = _getPrimaryDeviceId(map);
          if (id.isNotEmpty && !addedIds.contains(id.toLowerCase())) {
            addedIds.add(id.toLowerCase());
            deviceList.add(map);
          }
        }
      }

      // 4. Fetch live AC statuses from /mqtt/ac/status (matching system_view.dart)
      try {
        String zoneId = await AuthService.getZoneId() ?? '';
        if (zoneId.isEmpty) {
          for (var e in equipments) {
            final z = (e['zoneId'] ?? e['ZoneId'] ?? '').toString();
            if (z.isNotEmpty && z != '00000000-0000-0000-0000-000000000000') {
              zoneId = z;
              break;
            }
          }
        }
        if (zoneId.isEmpty) {
          for (var s in systems) {
            final z = (s['zoneId'] ?? s['ZoneId'] ?? '').toString();
            if (z.isNotEmpty && z != '00000000-0000-0000-0000-000000000000') {
              zoneId = z;
              break;
            }
          }
        }
        if (zoneId.isEmpty) {
          try {
            final zones = await AdminService.fetchZones();
            if (zones.isNotEmpty) {
              zoneId = (zones.first['zoneId'] ?? zones.first['id'] ?? '')
                  .toString();
            }
          } catch (_) {}
        }

        final statusUrl =
            '${AppConfig.provisionBaseUrl}/mqtt/ac/status?companyId=$companyId&siteId=$siteId&zoneId=$zoneId';
        final statusResponse = await http.get(
          Uri.parse(statusUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Cookie': 'auth_token=$token',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 5));

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
              final devId = (eq['deviceId'] ??
                      eq['DeviceId'] ??
                      '')
                  .toString()
                  .toLowerCase()
                  .trim();
              final sId = (eq['shortId'] ??
                      eq['ShortId'] ??
                      '')
                  .toString()
                  .toLowerCase()
                  .trim();
              final imei = (eq['imei'] ??
                      eq['Imei'] ??
                      '')
                  .toString()
                  .toLowerCase()
                  .trim();
              final name = (eq['name'] ??
                      eq['Name'] ??
                      eq['equipmentName'] ??
                      '')
                  .toString()
                  .toLowerCase()
                  .trim();

              if (eqId.isNotEmpty) statusByEquipmentId[eqId] = eqMap;
              if (devId.isNotEmpty) statusByDevId[devId] = eqMap;
              if (sId.isNotEmpty) statusByDevId[sId] = eqMap;
              if (imei.isNotEmpty) statusByDevId[imei] = eqMap;
              if (name.isNotEmpty) statusByDevId[name] = eqMap;
            }
          }

          // Merge live status into deviceList items
          for (var map in deviceList) {
            final eqId = (map['id'] ??
                    map['Id'] ??
                    map['equipmentId'] ??
                    map['EquipmentId'] ??
                    '')
                .toString()
                .toLowerCase()
                .trim();
            final pId = _getPrimaryDeviceId(map).toLowerCase().trim();
            final sId = (map['shortId'] ?? map['ShortId'] ?? '')
                .toString()
                .toLowerCase()
                .trim();
            final imei = (map['imei'] ?? map['Imei'] ?? '')
                .toString()
                .toLowerCase()
                .trim();
            final name = _getEquipmentName(map).toLowerCase().trim();

            final liveInfo = statusByEquipmentId[eqId] ??
                (pId.isNotEmpty ? statusByDevId[pId] : null) ??
                (sId.isNotEmpty ? statusByDevId[sId] : null) ??
                (imei.isNotEmpty ? statusByDevId[imei] : null) ??
                (name.isNotEmpty ? statusByDevId[name] : null);

            if (liveInfo != null) {
              final statusStr =
                  (liveInfo['status'] ?? liveInfo['Status'] ?? 'DISCONNECTED')
                      .toString()
                      .toUpperCase()
                      .trim();
              // Live active device connected to WiFi reports 'ON' or 'OFF' in Redis
              final bool isOnline = statusStr == 'ON' ||
                  statusStr == 'OFF' ||
                  statusStr == 'CONNECTED' ||
                  statusStr == 'ACTIVE' ||
                  statusStr == 'ONLINE';
              map['onOffStatus'] = {
                'isOnline': isOnline,
                'status': statusStr,
                'acStatus': liveInfo['acStatus'] ??
                    liveInfo['ac'] ??
                    (statusStr == 'ON' ? 'ON' : 'OFF'),
                'setTemp': liveInfo['setTemp'] ?? liveInfo['temp'],
                'currentTemp': liveInfo['currentTemp'] ?? liveInfo['temp'],
                'humidity': liveInfo['hum'] ?? liveInfo['humidity'],
                'lastSeen': liveInfo['lastSeen'],
              };
              map['isOnline'] = isOnline;
              map['isActive'] = isOnline;
            } else {
              map['onOffStatus'] = {
                'isOnline': false,
                'status': 'DISCONNECTED',
              };
              map['isOnline'] = false;
              map['isActive'] = false;
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ [IRLearningConfig] Fetch live status error: $e');
      }

      if (mounted) {
        setState(() {
          _devices = deviceList;
          if (_selectedDeviceId.isEmpty && _devices.isNotEmpty) {
            final first = _devices.first;
            _selectedDeviceId = _getPrimaryDeviceId(first);
          }
          _isLoadingDevices = false;
        });

        if (_selectedDeviceId.isNotEmpty) {
          _onDeviceSelected(_selectedDeviceId);
        }
      }
    } catch (e) {
      debugPrint('❌ [IRLearningConfig] _loadDevices error: $e');
      if (mounted) {
        setState(() => _isLoadingDevices = false);
      }
    }
  }

  static bool _areDeviceIdsEquivalent(String a, String b) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty) return false;
    final cleanA = a.toLowerCase().trim();
    final cleanB = b.toLowerCase().trim();
    if (cleanA == cleanB) return true;

    // Both are Sustainabyte non-test devices (e.g. Sustainabyte_ITir and Sustainabyte_ir)
    final aIsTest = cleanA.contains('test');
    final bIsTest = cleanB.contains('test');
    if (aIsTest != bIsTest) {
      return false; // One is testir, one is not -> never equivalent!
    }
    if (!aIsTest && !bIsTest &&
        cleanA.contains('sustainabyte') &&
        cleanB.contains('sustainabyte')) {
      return true;
    }

    // Normalized match (ignore underscores, hyphens, spaces, "itir" vs "ir")
    final normA = cleanA
        .replaceAll('_', '')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .replaceAll('itir', 'ir');
    final normB = cleanB
        .replaceAll('_', '')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .replaceAll('itir', 'ir');
    if (normA == normB) return true;

    return false;
  }

  bool _isDeviceMatchingSelected(String? deviceId, [String? imei]) {
    final sel = _selectedDeviceId.toLowerCase().trim();
    if (sel.isEmpty) return true;

    final dId = (deviceId ?? '').toLowerCase().trim();
    final mImei = (imei ?? '').toLowerCase().trim();

    if (dId.isNotEmpty && _areDeviceIdsEquivalent(dId, sel)) return true;
    if (mImei.isNotEmpty && _areDeviceIdsEquivalent(mImei, sel)) return true;

    for (var d in _devices) {
      final pId = _getDropdownItemValue(d).toLowerCase().trim();
      final dImei =
          (d['imei'] ?? d['Imei'] ?? '').toString().toLowerCase().trim();
      final shortId = _getEquipmentShortId(d).toLowerCase().trim();
      final eqName = _getEquipmentName(d).toLowerCase().trim();
      final id = (d['deviceId'] ?? d['equipmentId'] ?? d['id'] ?? '')
          .toString()
          .toLowerCase()
          .trim();

      final isCurrentSelected = _areDeviceIdsEquivalent(sel, pId) ||
          _areDeviceIdsEquivalent(sel, dImei) ||
          _areDeviceIdsEquivalent(sel, shortId) ||
          _areDeviceIdsEquivalent(sel, eqName) ||
          _areDeviceIdsEquivalent(sel, id);
      if (isCurrentSelected) {
        if (dId.isNotEmpty &&
            (_areDeviceIdsEquivalent(dId, pId) ||
                _areDeviceIdsEquivalent(dId, dImei) ||
                _areDeviceIdsEquivalent(dId, shortId) ||
                _areDeviceIdsEquivalent(dId, eqName) ||
                _areDeviceIdsEquivalent(dId, id))) {
          return true;
        }
        if (mImei.isNotEmpty &&
            (_areDeviceIdsEquivalent(mImei, pId) ||
                _areDeviceIdsEquivalent(mImei, dImei) ||
                _areDeviceIdsEquivalent(mImei, shortId) ||
                _areDeviceIdsEquivalent(mImei, eqName) ||
                _areDeviceIdsEquivalent(mImei, id))) {
          return true;
        }
      }
    }
    return false;
  }

  String get _targetDeviceId =>
      _selectedDeviceId.isNotEmpty ? _selectedDeviceId : _mqttService.deviceId;

  void _onDeviceSelected(String newId) async {
    Map<String, dynamic>? selectedMap;
    for (var d in _devices) {
      final pId = _getPrimaryDeviceId(d);
      final sId = (d['shortId'] ?? d['ShortId'] ?? d['equipmentShortId'] ?? '')
          .toString();
      final eqName = _getEquipmentName(d);
      if (pId.toLowerCase() == newId.toLowerCase() ||
          sId.toLowerCase() == newId.toLowerCase() ||
          eqName.toLowerCase() == newId.toLowerCase()) {
        selectedMap = d;
        break;
      }
    }

    final String companyId =
        (selectedMap?['companyId'] ?? selectedMap?['CompanyId'] ?? '')
            .toString();
    final String imei =
        (selectedMap?['imei'] ?? selectedMap?['Imei'] ?? newId).toString();
    final String targetId =
        selectedMap != null ? _getPrimaryDeviceId(selectedMap) : newId;

    if (mounted) {
      setState(() {
        _selectedDeviceId = targetId;
        _isLoadingDevices = true;
        _isReloadingDevice = true;
        _responseLogs.clear();
        _lastSavedMessage = '';
        _lastSavedTarget = '';
        _lastSavedLength = '';
        _latestResponseDetail = null;
        _signalDetailMap.clear();
        for (var key in _learnedSignalMap.keys.toList()) {
          _learnedSignalMap[key] = false;
        }
        final cached = _mqttService.getLastStateFor(targetId);
        if (cached != null) {
          if (cached.irOnLearned) _learnedSignalMap['POWER_ON'] = true;
          if (cached.irOffLearned) _learnedSignalMap['POWER_OFF'] = true;
          if (cached.setTemp > 0) _controlSetTemp = cached.setTemp;
        }
      });
    }

    _mqttService.setDeviceId(targetId);
    debugPrint(
        '🌐 [IRLearningConfig] Connecting SSE stream for deviceId=$targetId, companyId=$companyId, imei=$imei');
    await _mqttService.connect(
      deviceId: targetId,
      companyId: companyId.isNotEmpty ? companyId : null,
      imei: imei.isNotEmpty ? imei : targetId,
    );

    _requestStatus(force: true);

    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      setState(() {
        _isLoadingDevices = false;
        _isReloadingDevice = false;
      });
    }
  }

  Future<void> _reloadCurrentDevice() async {
    if (_isReloadingDevice) return;
    final targetId = _targetDeviceId;
    if (targetId.isEmpty) return;

    if (mounted) {
      setState(() {
        _isReloadingDevice = true;
        _isLoadingDevices = true;
        _responseLogs.clear();
        _lastSavedMessage = '';
        _latestResponseDetail = null;
      });
    }

    try {
      await _loadDevices();

      Map<String, dynamic>? selectedMap;
      for (var d in _devices) {
        final pId = _getPrimaryDeviceId(d);
        final sId = (d['shortId'] ?? d['ShortId'] ?? d['equipmentShortId'] ?? '')
            .toString();
        final eqName = _getEquipmentName(d);
        if (pId.toLowerCase() == targetId.toLowerCase() ||
            sId.toLowerCase() == targetId.toLowerCase() ||
            eqName.toLowerCase() == targetId.toLowerCase()) {
          selectedMap = d;
          break;
        }
      }

      final String companyId =
          (selectedMap?['companyId'] ?? selectedMap?['CompanyId'] ?? '')
              .toString();
      final String imei =
          (selectedMap?['imei'] ?? selectedMap?['Imei'] ?? targetId).toString();

      _mqttService.setDeviceId(targetId);
      await _mqttService.connect(
        deviceId: targetId,
        companyId: companyId.isNotEmpty ? companyId : null,
        imei: imei.isNotEmpty ? imei : targetId,
      );

      _requestStatus(force: true);

      _showSnack('🔄 Reloaded configuration for $targetId', AppColors.primary,
          icon: Icons.refresh_rounded);
    } catch (e) {
      debugPrint('⚠️ [IRLearningConfig] Reload error: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() {
          _isReloadingDevice = false;
          _isLoadingDevices = false;
        });
      }
    }
  }

  void _subscribeToMqttResponses() {
    _stateSub = _mqttService.stateStream.listen((state) {
      if (mounted) {
        if (state.deviceId.isNotEmpty) {
          final sId = state.deviceId.toLowerCase().trim();
          for (var d in _devices) {
            final pId = _getPrimaryDeviceId(d).toLowerCase().trim();
            final dImei =
                (d['imei'] ?? d['Imei'] ?? '').toString().toLowerCase().trim();
            final shortId = _getEquipmentShortId(d).toLowerCase().trim();
            if (sId == pId || sId == dImei || sId == shortId) {
              d['isOnline'] = state.isActive;
              d['isActive'] = state.isActive;
            }
          }
        }
        if (!_isDeviceMatchingSelected(state.deviceId, state.imei)) return;
        if (state.setTemp > 0) {
          _controlSetTemp = state.setTemp;
        }
        if (state.irOnLearned) _learnedSignalMap['POWER_ON'] = true;
        if (state.irOffLearned) _learnedSignalMap['POWER_OFF'] = true;
        setState(() {});
      }
    });
    _mqttService.addListener(() {
      if (mounted) setState(() {});
    });

    _responseSub = _mqttService.responseStream.listen((response) {
      if (!mounted) return;
      if (response.deviceId != null && response.deviceId!.isNotEmpty) {
        if (!_isDeviceMatchingSelected(response.deviceId)) {
          debugPrint(
              '🛡️ [IRLearningConfig] Ignored response from other device: ${response.deviceId} (selected: $_selectedDeviceId)');
          return;
        }
      }

      final now = DateTime.now();
      String title = response.type.name;
      String detail = response.detail ?? response.rawPayload;

      switch (response.type) {
        case SirisResponseType.irLearnWaiting:
          title = 'IR Learning Receiver Armed';
          detail = response.detail?.isNotEmpty == true
              ? response.detail!
              : 'Waiting for remote signal...';
          break;

        case SirisResponseType.irLearnSaved:
          final rawDet = response.detail ?? response.rawPayload;
          final info = _parseSaveDetail(rawDet);
          final target = info['target']!;
          final length = info['length']!;
          title = 'IR Signal Captured & Saved';
          detail = '$target ($length)';

          final detailObj = CapturedSignalDetail(
            target: target,
            length: length,
            timestamp: now,
            rawPayload: rawDet,
          );
          _storeSignalDetail(target, detailObj);
          _markLearnedSignalFromSave(target);

          setState(() {
            _lastSavedTarget = target;
            _lastSavedLength = length;
            _lastSavedMessage = 'Capture Successful! $target ($length)';
          });

          // Direct instant Toast notification without modal dialog blocking
          _showSnack(
              '🎉 Capture Successful! $target ($length)', AppColors.online,
              icon: Icons.check_circle_rounded);
          break;

        case SirisResponseType.irLearnCleared:
          title = 'IR Signal Cleared';
          detail = response.detail ?? 'IR Signal file removed';
          _markLearnedSignalFromClear(response.detail ?? response.rawPayload);
          _showSnack(
              '🗑️ IR Signal Cleared Successfully (${response.detail ?? "Done"})',
              AppColors.online,
              icon: Icons.check_circle_rounded);
          break;

        case SirisResponseType.irLearnStopped:
          title = 'IR Capture Stopped';
          detail = 'Stopped by user command';
          _showSnack('IR Capture Stopped', AppColors.textSecondary);
          _requestStatus();
          break;

        case SirisResponseType.irLearnStatus:
          title = 'IR Learn Status Summary';
          detail = response.detail ?? response.rawPayload;
          _parseStatusDetail(detail);
          break;

        case SirisResponseType.irLearnError:
          title = 'IR Capture Error';
          detail = response.detail ?? response.rawPayload;
          _showSnack('ERROR: ${response.detail}', AppColors.offline);
          break;

        case SirisResponseType.acOnDone:
          title = 'AC Power ON';
          detail = 'AC Equipment turned ON';
          _showSnack('⚡ AC Power turned ON', AppColors.online,
              icon: Icons.power_rounded);
          break;

        case SirisResponseType.acOffDone:
          title = 'AC Power OFF';
          detail = 'AC Equipment turned OFF';
          _showSnack('🔌 AC Power turned OFF', AppColors.coolBlue,
              icon: Icons.power_off_rounded);
          break;

        case SirisResponseType.tempSet:
          title = 'Temperature Set';
          detail =
              'Target temperature updated to ${response.detail ?? _controlSetTemp}°C';
          break;

        case SirisResponseType.cmdRejected:
          title = 'Command Rejected';
          detail = response.detail ?? response.rawPayload;
          _showSnack('⚠️ Command Rejected', AppColors.offline);
          break;

        case SirisResponseType.cmdError:
          title = 'Command Error';
          detail = response.detail ?? response.rawPayload;
          _showSnack('❌ Command Error', AppColors.offline);
          break;

        default:
          title = response.type.name.toUpperCase();
          detail = response.detail ?? response.rawPayload;
          break;
      }

      if (response.type != SirisResponseType.jsonSnapshot) {
        setState(() {
          _responseLogs.insert(
            0,
            ResponseLogEntry(
              timestamp: now,
              type: response.type,
              title: title,
              detail: detail,
              rawPayload: response.rawPayload,
            ),
          );
          if (_responseLogs.length > 200) {
            _responseLogs.removeLast();
          }
        });
      }
    });
  }

  void _logAction(String title, String detail) {
    if (!mounted) return;
    setState(() {
      _responseLogs.insert(
        0,
        ResponseLogEntry(
          timestamp: DateTime.now(),
          type: SirisResponseType.unknown,
          title: title,
          detail: detail,
          rawPayload: 'CLIENT_ACTION: $detail',
        ),
      );
      if (_responseLogs.length > 200) {
        _responseLogs.removeLast();
      }
    });
  }

  bool get _isCurrentDeviceOnline {
    Map<String, dynamic>? selectedItem;
    for (var d in _devices) {
      final pId = _getPrimaryDeviceId(d);
      final sId = (d['shortId'] ?? d['ShortId'] ?? d['equipmentShortId'] ?? '')
          .toString();
      final eqName = _getEquipmentName(d);
      final val = _getDropdownItemValue(d);
      final devId =
          (d['deviceId'] ?? d['equipmentId'] ?? d['id'] ?? d['Id'] ?? '')
              .toString();
      final imei = (d['imei'] ?? d['Imei'] ?? '').toString();

      final sel = _selectedDeviceId.toLowerCase().trim();
      if (sel.isNotEmpty &&
          (pId.toLowerCase().trim() == sel ||
              sId.toLowerCase().trim() == sel ||
              eqName.toLowerCase().trim() == sel ||
              val.toLowerCase().trim() == sel ||
              devId.toLowerCase().trim() == sel ||
              imei.toLowerCase().trim() == sel)) {
        selectedItem = d;
        break;
      }
    }
    if (selectedItem != null) {
      return _isItemOnline(selectedItem);
    }
    if (_selectedDeviceId.isNotEmpty) {
      final state = _mqttService.getLastStateFor(_selectedDeviceId);
      if (state != null) return state.isActive;
    }
    return false;
  }

  bool _checkDeviceOnlineOrWarn({String actionName = 'perform this action'}) {
    if (!_isCurrentDeviceOnline) {
      _showSnack(
        'Device is OFFLINE. Cannot $actionName until it is connected to Wi-Fi.',
        AppColors.offline,
        icon: Icons.wifi_off_rounded,
      );
      return false;
    }
    return true;
  }

  void _triggerPowerOn() {
    if (!_checkDeviceOnlineOrWarn(actionName: 'send Power ON command')) return;
    _mqttService.turnAcOn(targetDeviceId: _targetDeviceId);
    _logAction('Power Command Sent', 'AC_ON');
    _showSnack('⚡ Sent AC Power ON Command', AppColors.online,
        icon: Icons.power_rounded);
  }

  void _triggerPowerOff() {
    if (!_checkDeviceOnlineOrWarn(actionName: 'send Power OFF command')) return;
    _mqttService.turnAcOff(targetDeviceId: _targetDeviceId);
    _logAction('Power Command Sent', 'AC_OFF');
    _showSnack('🔌 Sent AC Power OFF Command', AppColors.coolBlue,
        icon: Icons.power_off_rounded);
  }

  void _triggerTestSend(String cmd, String label) {
    if (!_checkDeviceOnlineOrWarn(actionName: 'transmit IR test signal')) return;
    _mqttService.sendControlCommand(cmd, targetDeviceId: _targetDeviceId);
    _logAction('Test Signal Transmitted', '$cmd ($label)');
    _showSnack('📡 Transmitted IR Signal: $label', AppColors.primary,
        icon: Icons.sensors_rounded);
  }

  void _requestStatus({bool force = false}) {
    if (!force && !_isCurrentDeviceOnline) {
      debugPrint(
          'ℹ️ [IRLearningConfig] Skipped _requestStatus: device $_targetDeviceId is offline.');
      return;
    }
    _mqttService.sendStatus(targetDeviceId: _targetDeviceId);
    _mqttService.getLearnStatus(targetDeviceId: _targetDeviceId);
    _logAction('Status Requested', 'STATUS & LEARN_STATUS');
  }

  void _showSnack(String msg, Color bg, {IconData? icon}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
                icon ??
                    (bg == AppColors.online
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded),
                color: Colors.white,
                size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: bg,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _triggerCaptureOn() {
    if (!_checkDeviceOnlineOrWarn(actionName: 'arm IR capture for POWER ON')) return;
    setState(() {
      _lastSavedMessage = '';
    });
    _mqttService.learnOn(targetDeviceId: _targetDeviceId);
    _logAction('Capture Command Sent', 'LEARN_ON (POWER ON)');
    _showSnack(
        '🎉 Capture Command Sent Successfully for POWER ON', AppColors.online);
  }

  void _triggerCaptureOff() {
    if (!_checkDeviceOnlineOrWarn(actionName: 'arm IR capture for POWER OFF')) return;
    setState(() {
      _lastSavedMessage = '';
    });
    _mqttService.learnOff(targetDeviceId: _targetDeviceId);
    _logAction('Capture Command Sent', 'LEARN_OFF (POWER OFF)');
    _showSnack(
        '🎉 Capture Command Sent Successfully for POWER OFF', AppColors.online);
  }

  void _triggerCaptureUp(int temp) {
    if (!_checkDeviceOnlineOrWarn(actionName: 'arm IR capture for TEMP UP $temp°C')) return;
    setState(() {
      _lastSavedMessage = '';
    });
    _mqttService.learnUp(temp, targetDeviceId: _targetDeviceId);
    _logAction('Capture Command Sent', 'IR_LEARN_TEMP_UP:$temp (TEMP UP $temp°C)');
    _showSnack('🎉 Capture Command Sent Successfully for TEMP UP $temp°C',
        AppColors.online);
  }

  void _triggerCaptureDown(int temp) {
    if (!_checkDeviceOnlineOrWarn(actionName: 'arm IR capture for TEMP DOWN $temp°C')) return;
    setState(() {
      _lastSavedMessage = '';
    });
    _mqttService.learnDown(temp, targetDeviceId: _targetDeviceId);
    _logAction(
        'Capture Command Sent', 'IR_LEARN_TEMP_DOWN:$temp (TEMP DOWN $temp°C)');
    _showSnack('🎉 Capture Command Sent Successfully for TEMP DOWN $temp°C',
        AppColors.online);
  }

  void _triggerClearOn() async {
    if (!_checkDeviceOnlineOrWarn(actionName: 'clear POWER ON signal')) return;
    if (await _confirmAction(
        'Clear POWER ON Signal', 'This will delete /ir/on.bin on device.')) {
      setState(() {
        _learnedSignalMap['POWER_ON'] = false;
        _signalDetailMap.remove('POWER_ON');
        _signalDetailMap.remove('ON');
      });
      _mqttService.clearOn(targetDeviceId: _targetDeviceId);
      _logAction('Clear Command Sent', 'CLEAR_ON (POWER ON)');
      _showSnack('🗑️ Clear Command Sent Successfully for POWER ON',
          AppColors.coolBlue,
          icon: Icons.delete_outline_rounded);
    }
  }

  void _triggerClearOff() async {
    if (!_checkDeviceOnlineOrWarn(actionName: 'clear POWER OFF signal')) return;
    if (await _confirmAction(
        'Clear POWER OFF Signal', 'This will delete /ir/off.bin on device.')) {
      setState(() {
        _learnedSignalMap['POWER_OFF'] = false;
        _signalDetailMap.remove('POWER_OFF');
        _signalDetailMap.remove('OFF');
      });
      _mqttService.clearOff(targetDeviceId: _targetDeviceId);
      _logAction('Clear Command Sent', 'CLEAR_OFF (POWER OFF)');
      _showSnack('🗑️ Clear Command Sent Successfully for POWER OFF',
          AppColors.coolBlue,
          icon: Icons.delete_outline_rounded);
    }
  }

  void _triggerClearUp(int temp) async {
    if (!_checkDeviceOnlineOrWarn(actionName: 'clear UP $temp°C signal')) return;
    if (await _confirmAction(
        'Clear UP $temp°C Signal', 'Deletes /ir/up_$temp.bin on device.')) {
      setState(() {
        _learnedSignalMap['UP_$temp'] = false;
        _signalDetailMap.remove('UP_$temp');
        _signalDetailMap.remove('TEMP_UP_$temp');
        _signalDetailMap.remove('UP_$temp°C');
      });
      _mqttService.clearUp(temp, targetDeviceId: _targetDeviceId);
      _logAction('Clear Command Sent', 'CLEAR_UP:$temp (TEMP UP $temp°C)');
      _showSnack('🗑️ Clear Command Sent Successfully for TEMP UP $temp°C',
          AppColors.coolBlue,
          icon: Icons.delete_outline_rounded);
    }
  }

  void _triggerClearDown(int temp) async {
    if (!_checkDeviceOnlineOrWarn(actionName: 'clear DOWN $temp°C signal')) return;
    if (await _confirmAction(
        'Clear DOWN $temp°C Signal', 'Deletes /ir/down_$temp.bin on device.')) {
      setState(() {
        _learnedSignalMap['DOWN_$temp'] = false;
        _signalDetailMap.remove('DOWN_$temp');
        _signalDetailMap.remove('TEMP_DOWN_$temp');
        _signalDetailMap.remove('DOWN_$temp°C');
      });
      _mqttService.clearDown(temp, targetDeviceId: _targetDeviceId);
      _logAction('Clear Command Sent', 'CLEAR_DOWN:$temp (TEMP DOWN $temp°C)');
      _showSnack('🗑️ Clear Command Sent Successfully for TEMP DOWN $temp°C',
          AppColors.coolBlue,
          icon: Icons.delete_outline_rounded);
    }
  }

  void _triggerClearAll() async {
    if (!_checkDeviceOnlineOrWarn(actionName: 'clear all stored IR signals')) return;
    if (await _confirmAction(
      'CLEAR ALL IR SIGNALS?',
      'WARNING: Destructive command (v5.1). Will delete ON/OFF, all 14 UP steps, and all 14 DOWN steps (30 files total) without further confirmation.',
    )) {
      setState(() {
        _learnedSignalMap.updateAll((key, value) => false);
        _signalDetailMap.clear();
      });
      _mqttService.clearAll(targetDeviceId: _targetDeviceId);
      _logAction('Clear All Command Sent', 'CLEAR_ALL (Delete 30 files)');
      _showSnack('🗑️ Erase All Command Sent Successfully: CLEAR_ALL',
          AppColors.coolBlue,
          icon: Icons.delete_forever_rounded);
    }
  }

  Future<bool> _confirmAction(String title, String content) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: Text(content, style: GoogleFonts.inter(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.offline,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Confirm Erase',
                style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Map<String, String> _parseSaveDetail(String detail) {
    String clean = detail
        .replaceFirst(
            RegExp(r'.*IR_LEARN_(SAVED|CAPTURED):?', caseSensitive: false), '')
        .trim();
    String target = clean;
    String lengthStr = '';

    final lenMatch =
        RegExp(r'LEN\s*[:=]\s*(\d+)', caseSensitive: false).firstMatch(clean);
    if (lenMatch != null) {
      lengthStr = '${lenMatch.group(1)} bytes';
      target = clean
          .split(RegExp(r'LEN\s*[:=]', caseSensitive: false))[0]
          .replaceAll(':', ' ')
          .trim();
    } else if (clean.contains('LEN=')) {
      final parts = clean.split('LEN=');
      target = parts[0].replaceAll(':', ' ').trim();
      lengthStr = '${parts[1].trim()} bytes';
    } else if (clean.contains('LEN:')) {
      final parts = clean.split('LEN:');
      target = parts[0].replaceAll(':', ' ').trim();
      lengthStr = '${parts[1].trim()} bytes';
    }

    final upperTarget = target.toUpperCase();
    if (upperTarget.contains('POWER_ON') ||
        upperTarget.contains('POWER ON') ||
        upperTarget == 'ON') {
      target = 'POWER ON';
    } else if (upperTarget.contains('POWER_OFF') ||
        upperTarget.contains('POWER OFF') ||
        upperTarget == 'OFF') {
      target = 'POWER OFF';
    } else if (upperTarget.contains('TEMP_UP') || upperTarget.contains('UP')) {
      final match = RegExp(r'(\d+)').firstMatch(upperTarget);
      final temp = match != null ? '${match.group(1)}°C' : '';
      target = 'TEMP UP $temp'.trim();
    } else if (upperTarget.contains('TEMP_DOWN') ||
        upperTarget.contains('DOWN')) {
      final match = RegExp(r'(\d+)').firstMatch(upperTarget);
      final temp = match != null ? '${match.group(1)}°C' : '';
      target = 'TEMP DOWN $temp'.trim();
    }

    return {
      'target': target.isNotEmpty ? target : 'IR Signal',
      'length': lengthStr.isNotEmpty ? lengthStr : clean,
      'raw': detail,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subtitleColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark ? AppColors.dividerDark : AppColors.divider;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'IR Remote Signal Config',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _isReloadingDevice
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Reload Device Configuration',
            onPressed: _isReloadingDevice ? null : _reloadCurrentDevice,
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device Picker
            _buildDevicePickerCard(
                isDark, cardColor, borderColor, textColor, subtitleColor),
            const SizedBox(height: 16),

            // Loading / Syncing Banner when device is switched or reloaded
            if (_isReloadingDevice) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Syncing configuration & status for $_targetDeviceId...',
                        style: GoogleFonts.inter(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Always Visible Latest Captured Response Values Card
            _buildLatestCapturedResponseCard(
                isDark, cardColor, borderColor, textColor, subtitleColor),
            const SizedBox(height: 16),

            // Captured Data Response Terminal Log Card
            _buildResponseLogCard(
                isDark, cardColor, borderColor, textColor, subtitleColor),
            const SizedBox(height: 16),

            // Capture Success Banner
            if (_lastSavedMessage.isNotEmpty) ...[
              _buildSuccessBanner(isDark),
              const SizedBox(height: 16),
            ],

            // Power Signals Card (ON / OFF)
            _buildPowerSignalsCard(
                isDark, cardColor, borderColor, textColor, subtitleColor),
            const SizedBox(height: 16),

            // Temp Step UP Signals Card (16 - 29°C)
            _buildTempUpCard(
                isDark, cardColor, borderColor, textColor, subtitleColor),
            const SizedBox(height: 16),

            // Temp Step DOWN Signals Card (17 - 30°C)
            _buildTempDownCard(
                isDark, cardColor, borderColor, textColor, subtitleColor),
            const SizedBox(height: 24),

            // Erase All & Global Actions
            _buildGlobalActionsCard(
                isDark, cardColor, borderColor, textColor, subtitleColor),
          ],
        ),
      ),
    );
  }

  bool _isItemOnline(Map<String, dynamic>? item) {
    if (item == null) return false;

    final primaryId = _getPrimaryDeviceId(item).trim();
    final imei = (item['imei'] ?? item['Imei'] ?? '').toString().trim();
    final devId = (item['deviceId'] ??
            item['equipmentId'] ??
            item['id'] ??
            item['Id'] ??
            '')
        .toString()
        .trim();
    final shortId =
        (item['shortId'] ?? item['ShortId'] ?? item['equipmentShortId'] ?? '')
            .toString()
            .trim();

    // 1. Check live telemetry from MqttService stream across candidate keys for THIS item ONLY
    for (final id in [
      primaryId,
      imei,
      shortId,
      devId,
    ]) {
      if (id.isNotEmpty) {
        final state = _mqttService.getLastStateFor(id);
        if (state != null) {
          return state.isActive;
        }
      }
    }

    // 2. Check live onOffStatus object from the live GET /mqtt/ac/status API payload
    final statusObj = item['onOffStatus'] ?? item['OnOffStatus'];
    if (statusObj != null && statusObj is Map) {
      final isOnlineVal = statusObj['isOnline'] ?? statusObj['IsOnline'];
      if (isOnlineVal == true ||
          isOnlineVal == 1 ||
          isOnlineVal.toString().toLowerCase() == 'true') {
        return true;
      }
      if (isOnlineVal == false ||
          isOnlineVal == 0 ||
          isOnlineVal.toString().toLowerCase() == 'false') {
        return false;
      }
      final statusStr = (statusObj['status'] ??
              statusObj['Status'] ??
              statusObj['acStatus'] ??
              '')
          .toString()
          .toUpperCase()
          .trim();
      if (statusStr == 'DISCONNECTED' || statusStr == 'OFFLINE') {
        return false;
      }
      if (statusStr == 'ON' ||
          statusStr == 'OFF' ||
          statusStr == 'ACTIVE' ||
          statusStr == 'ONLINE' ||
          statusStr == 'CONNECTED') {
        return true;
      }
    }

    // 3. Explicit isOnline or isActive booleans set from API
    if (item['isOnline'] == true || item['isActive'] == true) {
      return true;
    }

    return false;
  }

  Widget _buildDropdownItemWidget(Map<String, dynamic> d, Color textColor) {
    final bool itemOnline = _isItemOnline(d);
    final Color dotColor = itemOnline
        ? AppColors.online
        : (textColor == Colors.white ? Colors.white38 : Colors.grey.shade400);
    final String label = _getDropdownLabel(d);

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: itemOnline ? textColor : textColor.withValues(alpha: 0.6),
              fontWeight: itemOnline ? FontWeight.w600 : FontWeight.w400,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            softWrap: false,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: itemOnline
                ? AppColors.online.withValues(alpha: 0.15)
                : Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: itemOnline
                  ? AppColors.online.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.3),
              width: 0.8,
            ),
          ),
          child: Text(
            itemOnline ? 'ONLINE' : 'OFFLINE',
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: itemOnline ? FontWeight.w700 : FontWeight.w500,
              color: itemOnline ? AppColors.online : Colors.grey.shade400,
            ),
          ),
        ),
      ],
    );
  }

  String _getDropdownItemValue(Map<String, dynamic> d) {
    final primary = _getPrimaryDeviceId(d);
    if (primary.isNotEmpty) return primary;
    final eqName = _getEquipmentName(d);
    if (eqName.isNotEmpty) return eqName;
    return 'UNKNOWN_${d.hashCode}';
  }

  Widget _buildDevicePickerCard(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    // Find selected equipment details
    Map<String, dynamic>? selectedItem;
    for (var d in _devices) {
      final pId = _getDropdownItemValue(d);
      final sId = (d['shortId'] ?? d['ShortId'] ?? d['equipmentShortId'] ?? '')
          .toString();
      final eqName = _getEquipmentName(d);
      if (pId.toLowerCase() == _selectedDeviceId.toLowerCase() ||
          sId.toLowerCase() == _selectedDeviceId.toLowerCase() ||
          eqName.toLowerCase() == _selectedDeviceId.toLowerCase()) {
        selectedItem = d;
        break;
      }
    }

    final category =
        selectedItem != null ? _getItemCategory(selectedItem) : 'Equipment';
    final equipName = selectedItem != null
        ? _getEquipmentName(selectedItem)
        : (_selectedDeviceId.isNotEmpty
            ? _selectedDeviceId
            : 'Default AC Equipment');
    final sysName = selectedItem != null ? _getSystemName(selectedItem) : '';
    final shortId = selectedItem != null
        ? _getEquipmentShortId(selectedItem)
        : _selectedDeviceId;

    // Get true active online status matching system_view.dart
    final SirisDeviceState? liveState =
        _mqttService.getLastStateFor(_selectedDeviceId);
    final bool isOnline = _isItemOnline(selectedItem);
    final String statusText = isOnline ? 'ACTIVE' : 'INACTIVE';
    final Color statusColor = isOnline ? AppColors.online : AppColors.offline;

    // Safely compute valid dropdown item values and current selection
    final List<DropdownMenuItem<String>> dropdownItems = _devices.isEmpty
        ? [
            DropdownMenuItem<String>(
              value: _mqttService.deviceId.isNotEmpty
                  ? _mqttService.deviceId
                  : 'DEFAULT',
              child: Text(
                _mqttService.deviceId.isNotEmpty
                    ? 'Default Device (${_mqttService.deviceId})'
                    : 'Default MQTT Device',
                style: GoogleFonts.inter(color: textColor),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                softWrap: false,
              ),
            )
          ]
        : _devices.map((d) {
            final val = _getDropdownItemValue(d);
            return DropdownMenuItem<String>(
              value: val,
              child: _buildDropdownItemWidget(d, textColor),
            );
          }).toList();

    String? selectedDropdownValue;
    if (_devices.isNotEmpty) {
      final itemValues = _devices.map((d) => _getDropdownItemValue(d)).toList();
      if (itemValues.contains(_selectedDeviceId)) {
        selectedDropdownValue = _selectedDeviceId;
      } else if (selectedItem != null) {
        selectedDropdownValue = _getDropdownItemValue(selectedItem);
      } else {
        selectedDropdownValue = itemValues.first;
      }
    } else if (_mqttService.deviceId.isNotEmpty) {
      selectedDropdownValue = _mqttService.deviceId;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.router_rounded,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Target IR Blaster Device',
                    style: GoogleFonts.outfit(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 16),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Reload Option Button
                  InkWell(
                    onTap: _isReloadingDevice ? null : _reloadCurrentDevice,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _isReloadingDevice
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: AppColors.primary),
                                )
                              : const Icon(Icons.refresh_rounded,
                                  size: 13, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Reload',
                            style: GoogleFonts.inter(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Active Status Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: GoogleFonts.inter(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _isLoadingDevices
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Switching to target device & initializing stream...',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )
              : DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedDropdownValue,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? Colors.black12 : Colors.grey.shade50,
                  ),
                  dropdownColor: cardColor,
                  items: dropdownItems,
                  onChanged: (val) {
                    if (val != null) {
                      _onDeviceSelected(val);
                    }
                  },
                ),
          const SizedBox(height: 12),

          // Device Details & Active Status Footer
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                _buildInfoRow(
                    'Device Category', category, subtitleColor, textColor),
                const SizedBox(height: 6),
                _buildInfoRow(
                    'Equipment Name', equipName, subtitleColor, textColor),
                if (sysName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _buildInfoRow(
                      'System Name', sysName, subtitleColor, textColor),
                ],
                const SizedBox(height: 6),
                _buildInfoRow(
                    'Target ID / Short ID',
                    shortId.isNotEmpty ? shortId : _selectedDeviceId,
                    subtitleColor,
                    textColor),
                const SizedBox(height: 6),
                _buildInfoRow(
                    'Active Status', statusText, subtitleColor, statusColor,
                    isBold: true),
                if (liveState != null) ...[
                  const SizedBox(height: 6),
                  _buildInfoRow(
                      'AC Power State',
                      liveState.ac,
                      subtitleColor,
                      liveState.isPowerOn
                          ? AppColors.online
                          : AppColors.textSecondary),
                  if (liveState.setTemp > 0) ...[
                    const SizedBox(height: 6),
                    _buildInfoRow('Set Temperature', '${liveState.setTemp}°C',
                        subtitleColor, textColor),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.online.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.online),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: AppColors.online,
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.check_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Capture Successful!',
                      style: GoogleFonts.outfit(
                        color: AppColors.online,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.online.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'SAVED',
                        style: GoogleFonts.inter(
                            color: AppColors.online,
                            fontSize: 10,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Signal Target: $_lastSavedTarget • Value / Length: $_lastSavedLength',
                  style: GoogleFonts.inter(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                size: 20),
            tooltip: 'Dismiss Banner',
            onPressed: () {
              setState(() {
                _lastSavedMessage = '';
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResponseLogCard(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    final filteredLogs = _showOnlyCaptureLogs
        ? _responseLogs
            .where((l) =>
                l.type == SirisResponseType.irLearnSaved ||
                l.type == SirisResponseType.irLearnCleared ||
                l.type == SirisResponseType.irLearnWaiting ||
                l.type == SirisResponseType.irLearnError ||
                l.type == SirisResponseType.irLearnStatus)
            .toList()
        : _responseLogs;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.terminal_rounded,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Captured Data & Response Log',
                    style: GoogleFonts.outfit(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${filteredLogs.length}',
                      style: GoogleFonts.inter(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _showOnlyCaptureLogs
                          ? Icons.filter_alt_rounded
                          : Icons.filter_alt_outlined,
                      color: _showOnlyCaptureLogs
                          ? AppColors.primary
                          : subtitleColor,
                      size: 20,
                    ),
                    tooltip: _showOnlyCaptureLogs
                        ? 'Showing IR Capture Logs Only'
                        : 'Show All Logs',
                    onPressed: () {
                      setState(() {
                        _showOnlyCaptureLogs = !_showOnlyCaptureLogs;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                    tooltip: 'Clear Response Log',
                    onPressed: () {
                      setState(() {
                        _responseLogs.clear();
                      });
                      _showSnack(
                          'Response log cleared', AppColors.textSecondary);
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (filteredLogs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Icon(Icons.sensors_off_rounded,
                      color: subtitleColor, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'No responses captured yet',
                    style: GoogleFonts.inter(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Send a capture or control command to view live data output here.',
                    textAlign: TextAlign.center,
                    style:
                        GoogleFonts.inter(color: subtitleColor, fontSize: 11),
                  ),
                ],
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111622) : Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor.withValues(alpha: 0.6)),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.all(10),
                shrinkWrap: true,
                itemCount: filteredLogs.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 12, color: Colors.white12),
                itemBuilder: (ctx, idx) {
                  final log = filteredLogs[idx];
                  final timeStr =
                      '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';

                  Color badgeColor = AppColors.primary;
                  if (log.type == SirisResponseType.irLearnSaved ||
                      log.type == SirisResponseType.acOnDone) {
                    badgeColor = AppColors.online;
                  } else if (log.type == SirisResponseType.irLearnCleared ||
                      log.type == SirisResponseType.acOffDone) {
                    badgeColor = AppColors.coolBlue;
                  } else if (log.type == SirisResponseType.irLearnWaiting ||
                      log.type == SirisResponseType.tempSet) {
                    badgeColor = AppColors.heatOrange;
                  } else if (log.type == SirisResponseType.irLearnError ||
                      log.type == SirisResponseType.cmdError ||
                      log.type == SirisResponseType.cmdRejected) {
                    badgeColor = AppColors.offline;
                  }

                  return InkWell(
                    onTap: () => _showRawPayloadDialog(log),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            timeStr,
                            style: GoogleFonts.firaCode(
                                color: Colors.white54, fontSize: 11),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: badgeColor.withValues(alpha: 0.6),
                                  width: 0.8),
                            ),
                            child: Text(
                              log.type.name.replaceAll('irLearn', 'IR_'),
                              style: GoogleFonts.firaCode(
                                  color: badgeColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  log.title,
                                  style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  log.detail,
                                  style: GoogleFonts.firaCode(
                                      color: Colors.white70, fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: Colors.white38, size: 16),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _showRawPayloadDialog(ResponseLogEntry log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.code_rounded, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(log.title,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Parsed Detail:',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(log.detail, style: GoogleFonts.inter(fontSize: 13)),
            const SizedBox(height: 12),
            Text('Raw Response Payload:',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                log.rawPayload,
                style: GoogleFonts.firaCode(
                    color: Colors.greenAccent, fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text('Copy Raw',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: log.rawPayload));
              Navigator.pop(ctx);
              _showSnack('Raw payload copied to clipboard', AppColors.online);
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Close', style: GoogleFonts.inter(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildLatestCapturedResponseCard(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    final detailObj = _latestResponseDetail;
    final hasDetail = detailObj != null;
    final targetText = hasDetail
        ? detailObj.target
        : (_lastSavedTarget.isNotEmpty
            ? _lastSavedTarget
            : 'No Capture in Current Session');
    final lengthText = hasDetail
        ? detailObj.length
        : (_lastSavedLength.isNotEmpty ? _lastSavedLength : 'N/A');
    final rawText = hasDetail
        ? detailObj.rawPayload
        : (_lastSavedMessage.isNotEmpty
            ? _lastSavedMessage
            : 'Waiting for incoming IR capture signal...');
    final timeStr = hasDetail
        ? '${detailObj.timestamp.hour.toString().padLeft(2, '0')}:${detailObj.timestamp.minute.toString().padLeft(2, '0')}:${detailObj.timestamp.second.toString().padLeft(2, '0')}'
        : 'Live Monitor';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasDetail ? AppColors.online.withValues(alpha: 0.08) : cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: hasDetail
                ? AppColors.online.withValues(alpha: 0.5)
                : borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.sensors_rounded,
                      color: hasDetail ? AppColors.online : AppColors.primary,
                      size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Latest Captured IR Response Values',
                    style: GoogleFonts.outfit(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 16),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (hasDetail ? AppColors.online : AppColors.primary)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  timeStr,
                  style: GoogleFonts.firaCode(
                    color: hasDetail ? AppColors.online : AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black38 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                _buildInfoRow('Signal Target', targetText, subtitleColor,
                    hasDetail ? AppColors.online : textColor,
                    isBold: true),
                const SizedBox(height: 6),
                _buildInfoRow('Byte Length / Value', lengthText, subtitleColor,
                    textColor),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Raw Payload Data',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: subtitleColor,
                            fontWeight: FontWeight.w500)),
                    Flexible(
                      child: Text(
                        rawText,
                        style: GoogleFonts.firaCode(
                            fontSize: 11,
                            color: hasDetail
                                ? AppColors.online
                                : textColor.withValues(alpha: 0.7)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineNoticeBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.offline.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.offline.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              color: AppColors.offline, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Device is OFFLINE. Controls & IR signals are disabled.',
              style: GoogleFonts.inter(
                color: AppColors.offline,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerSignalsCard(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    final onDetail = _signalDetailMap['POWER_ON'] ?? _signalDetailMap['ON'];
    final offDetail = _signalDetailMap['POWER_OFF'] ?? _signalDetailMap['OFF'];

    final String onValueText = onDetail != null
        ? '${onDetail.length} (${onDetail.rawPayload})'
        : ((_learnedSignalMap['POWER_ON'] ?? false)
            ? 'Saved on device'
            : 'No signal stored');

    final String offValueText = offDetail != null
        ? '${offDetail.length} (${offDetail.rawPayload})'
        : ((_learnedSignalMap['POWER_OFF'] ?? false)
            ? 'Saved on device'
            : 'No signal stored');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.power_settings_new_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                'Power IR Signals (ON / OFF)',
                style: GoogleFonts.outfit(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_isCurrentDeviceOnline) _buildOfflineNoticeBanner(),

          // POWER ON Action Row
          _buildSignalActionRow(
            title: 'POWER ON',
            isCaptured: _learnedSignalMap['POWER_ON'] ?? false,
            onCapture: _triggerCaptureOn,
            onTestSend: _triggerPowerOn,
            onClear: _triggerClearOn,
            textColor: textColor,
            subtitleColor: subtitleColor,
          ),
          const SizedBox(height: 6),
          _buildResponseValueBox('Response Value', onValueText,
              onDetail != null, isDark, textColor, subtitleColor, borderColor),
          const Divider(height: 24),

          // POWER OFF Action Row
          _buildSignalActionRow(
            title: 'POWER OFF',
            isCaptured: _learnedSignalMap['POWER_OFF'] ?? false,
            onCapture: _triggerCaptureOff,
            onTestSend: _triggerPowerOff,
            onClear: _triggerClearOff,
            textColor: textColor,
            subtitleColor: subtitleColor,
          ),
          const SizedBox(height: 6),
          _buildResponseValueBox('Response Value', offValueText,
              offDetail != null, isDark, textColor, subtitleColor, borderColor),
        ],
      ),
    );
  }

  Widget _buildTempUpCard(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    final bool isCaptured = _learnedSignalMap['UP_$_selectedUpTemp'] ?? false;
    final upDetail = _signalDetailMap['UP_$_selectedUpTemp'] ??
        _signalDetailMap['TEMP_UP_$_selectedUpTemp'];
    final String upValueText = upDetail != null
        ? '${upDetail.length} (${upDetail.rawPayload})'
        : (isCaptured
            ? 'Saved on device'
            : 'No signal stored for $_selectedUpTemp°C');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.arrow_upward_rounded,
                      color: AppColors.heatOrange, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'TEMP UP Step IR Signals (16–29°C)',
                    style: GoogleFonts.outfit(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 16),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isCaptured ? AppColors.online : Colors.grey)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (isCaptured ? AppColors.online : Colors.grey)
                          .withValues(alpha: 0.4)),
                ),
                child: Text(
                  isCaptured ? 'UP $_selectedUpTemp°C ✓' : 'NOT SAVED',
                  style: GoogleFonts.inter(
                    color: isCaptured
                        ? AppColors.online
                        : textColor.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_isCurrentDeviceOnline) _buildOfflineNoticeBanner(),
          Row(
            children: [
              Text('Target Temperature: ',
                  style: GoogleFonts.inter(color: subtitleColor, fontSize: 14)),
              const Spacer(),
              DropdownButton<int>(
                value: _selectedUpTemp,
                dropdownColor: cardColor,
                items: List.generate(14, (i) => 16 + i).map((t) {
                  return DropdownMenuItem<int>(
                    value: t,
                    child: Text('$t°C',
                        style: GoogleFonts.inter(
                            color: textColor, fontWeight: FontWeight.w700)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedUpTemp = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildResponseValueBox('UP $_selectedUpTemp°C Response', upValueText,
              upDetail != null, isDark, textColor, subtitleColor, borderColor),
          const SizedBox(height: 12),
          Opacity(
            opacity: _isCurrentDeviceOnline ? 1.0 : 0.45,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _triggerCaptureUp(_selectedUpTemp),
                    icon: const Icon(Icons.sensors_rounded, size: 16),
                    label: Text('Capture UP $_selectedUpTemp°C',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.heatOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _triggerTestSend(
                      'SEND:UP_$_selectedUpTemp', 'TEMP UP $_selectedUpTemp°C'),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: Text('Test',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.heatOrange,
                    side: BorderSide(
                        color: AppColors.heatOrange.withValues(alpha: 0.6)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _triggerClearUp(_selectedUpTemp),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: Text('Clear',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.offline,
                    side: BorderSide(
                        color: AppColors.offline.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTempDownCard(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    final bool isCaptured =
        _learnedSignalMap['DOWN_$_selectedDownTemp'] ?? false;
    final downDetail = _signalDetailMap['DOWN_$_selectedDownTemp'] ??
        _signalDetailMap['TEMP_DOWN_$_selectedDownTemp'];
    final String downValueText = downDetail != null
        ? '${downDetail.length} (${downDetail.rawPayload})'
        : (isCaptured
            ? 'Saved on device'
            : 'No signal stored for $_selectedDownTemp°C');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.arrow_downward_rounded,
                      color: AppColors.coolBlue, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'TEMP DOWN Step IR Signals (17–30°C)',
                    style: GoogleFonts.outfit(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 16),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isCaptured ? AppColors.online : Colors.grey)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (isCaptured ? AppColors.online : Colors.grey)
                          .withValues(alpha: 0.4)),
                ),
                child: Text(
                  isCaptured ? 'DOWN $_selectedDownTemp°C ✓' : 'NOT SAVED',
                  style: GoogleFonts.inter(
                    color: isCaptured
                        ? AppColors.online
                        : textColor.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_isCurrentDeviceOnline) _buildOfflineNoticeBanner(),
          Row(
            children: [
              Text('Target Temperature: ',
                  style: GoogleFonts.inter(color: subtitleColor, fontSize: 14)),
              const Spacer(),
              DropdownButton<int>(
                value: _selectedDownTemp,
                dropdownColor: cardColor,
                items: List.generate(14, (i) => 17 + i).map((t) {
                  return DropdownMenuItem<int>(
                    value: t,
                    child: Text('$t°C',
                        style: GoogleFonts.inter(
                            color: textColor, fontWeight: FontWeight.w700)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedDownTemp = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildResponseValueBox(
              'DOWN $_selectedDownTemp°C Response',
              downValueText,
              downDetail != null,
              isDark,
              textColor,
              subtitleColor,
              borderColor),
          const SizedBox(height: 12),
          Opacity(
            opacity: _isCurrentDeviceOnline ? 1.0 : 0.45,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _triggerCaptureDown(_selectedDownTemp),
                    icon: const Icon(Icons.sensors_rounded, size: 16),
                    label: Text('Capture DOWN $_selectedDownTemp°C',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.coolBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _triggerTestSend(
                      'SEND:DOWN_$_selectedDownTemp',
                      'TEMP DOWN $_selectedDownTemp°C'),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: Text('Test',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.coolBlue,
                    side: BorderSide(
                        color: AppColors.coolBlue.withValues(alpha: 0.6)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _triggerClearDown(_selectedDownTemp),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: Text('Clear',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.offline,
                    side: BorderSide(
                        color: AppColors.offline.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalActionsCard(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cleaning_services_rounded,
                  color: AppColors.offline, size: 20),
              const SizedBox(width: 10),
              Text(
                'Bulk Actions & Controls',
                style: GoogleFonts.outfit(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_isCurrentDeviceOnline) _buildOfflineNoticeBanner(),
          Opacity(
            opacity: _isCurrentDeviceOnline ? 1.0 : 0.45,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (!_checkDeviceOnlineOrWarn(actionName: 'stop IR capture')) return;
                      _mqttService.learnStop(targetDeviceId: _targetDeviceId);
                      _logAction('Capture Stopped', 'IR_LEARN_STOP');
                      _showSnack('⏹️ IR Capture Stopped', AppColors.textSecondary);
                    },
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: Text('Stop Capture',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _triggerClearAll,
                    icon: const Icon(Icons.delete_forever_rounded, size: 18),
                    label: Text('Clear All (CLEAR_ALL)',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.offline,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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

  Widget _buildSignalActionRow({
    required String title,
    required bool isCaptured,
    required VoidCallback onCapture,
    required VoidCallback onTestSend,
    required VoidCallback onClear,
    required Color textColor,
    required Color subtitleColor,
  }) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor)),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isCaptured ? AppColors.online : Colors.grey)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: (isCaptured ? AppColors.online : Colors.grey)
                        .withValues(alpha: 0.4)),
              ),
              child: Text(
                isCaptured ? '✓ CAPTURED' : 'NOT CAPTURED',
                style: GoogleFonts.inter(
                  color: isCaptured
                      ? AppColors.online
                      : textColor.withValues(alpha: 0.6),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const Spacer(),
        Opacity(
          opacity: _isCurrentDeviceOnline ? 1.0 : 0.45,
          child: ElevatedButton.icon(
            onPressed: onCapture,
            icon: const Icon(Icons.sensors_rounded, size: 14),
            label: Text('Capture',
                style:
                    GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Opacity(
          opacity: _isCurrentDeviceOnline ? 1.0 : 0.45,
          child: OutlinedButton.icon(
            onPressed: onTestSend,
            icon: const Icon(Icons.send_rounded, size: 14),
            label: Text('Test',
                style:
                    GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.online,
              side: BorderSide(color: AppColors.online.withValues(alpha: 0.6)),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Opacity(
          opacity: _isCurrentDeviceOnline ? 1.0 : 0.45,
          child: OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: Text('Clear',
                style:
                    GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.offline,
              side: BorderSide(color: AppColors.offline.withValues(alpha: 0.5)),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResponseValueBox(
    String label,
    String value,
    bool isLive,
    bool isDark,
    Color textColor,
    Color subtitleColor,
    Color borderColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isLive
                ? AppColors.online.withValues(alpha: 0.4)
                : borderColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.data_object_rounded,
              size: 14, color: isLive ? AppColors.online : AppColors.primary),
          const SizedBox(width: 6),
          Text('$label: ',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  color: subtitleColor,
                  fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.firaCode(
                  fontSize: 11,
                  color: isLive ? AppColors.online : textColor,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
      String label, String value, Color labelColor, Color valueColor,
      {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
              fontSize: 12, color: labelColor, fontWeight: FontWeight.w500),
        ),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: valueColor,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}
