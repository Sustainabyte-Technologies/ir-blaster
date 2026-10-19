import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ir_blaster_ac/core/services/admin_service.dart';

/// System View page showing list of AC monitoring systems with their equipments
class SystemViewPage extends StatefulWidget {
  final void Function(
    String systemId,
    String systemName,
    String systemShortId, {
    String? equipmentId,
    String? imei,
  })? onViewPressed;
  final void Function(int count)? onCountChanged;

  const SystemViewPage({super.key, this.onViewPressed, this.onCountChanged});

  @override
  State<SystemViewPage> createState() => SystemViewPageState();
}

class SystemViewPageState extends State<SystemViewPage> {
  List<SystemItem> systems = [];
  bool isLoading = true;

  /// Map of systemId -> list of equipment data from the equipments API
  Map<String, List<Map<String, dynamic>>> _equipmentsBySystem = {};

  // Quick metrics
  int _totalAcs = 0;
  int _onlineCount = 0;
  int _runningCount = 0;
  final Map<String, StreamSubscription> _sseSubscriptions = {};

  @override
  void initState() {
    super.initState();
    _fetchSystemsAndEquipments();
  }

  /// Fetches equipments from the working /equipments/ac/by-company endpoint,
  /// then derives systems by grouping equipments by systemId.
  /// Bypasses proxy-safe endpoint with fallback if not found on production.
  Future<void> _fetchSystemsAndEquipments() async {
    if (mounted) setState(() => isLoading = true);

    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';

      // Pre-fetch all systems to resolve real names and support fallback
      final realSystemsNames = <String, String>{};
      List<dynamic> systemsList = [];
      try {
        systemsList = await AdminService.fetchSystems(companyId: companyId, siteId: siteId);
        for (var sys in systemsList) {
          final sysId = (sys['systemId'] ?? sys['Id'] ?? sys['systemid'] ?? '').toString();
          final sysName = (sys['name'] ?? sys['Name'] ?? sys['systemName'] ?? '').toString();
          if (sysId.isNotEmpty && sysName.isNotEmpty) {
            realSystemsNames[sysId] = sysName;
          }
        }
      } catch (e) {
        debugPrint('⚠️ [SystemView] Error pre-fetching systems: $e');
      }

      // Fetch all equipments from the primary endpoint
      List<Map<String, dynamic>>? allEquips = await _fetchAllEquipments(companyId, siteId, token);

      if (allEquips == null || allEquips.isEmpty) {
        debugPrint('🔄 [SystemView] Falling back to systems and equipment APIs...');
        allEquips = [];
        try {
          debugPrint('🌐 [SystemView] Fallback: using ${systemsList.length} systems');
          for (var sys in systemsList) {
            final sysId = (sys['systemId'] ?? sys['Id'] ?? sys['systemid'] ?? '').toString();
            if (sysId.isNotEmpty) {
              final equips = await _fetchEquipmentsForSystem(sysId, companyId, siteId, token);
              debugPrint('🌐 [SystemView] Fallback: system $sysId has ${equips.length} equipments');
              allEquips.addAll(equips);
            }
          }
        } catch (sysErr) {
          debugPrint('❌ [SystemView] Fallback systems fetch failed: $sysErr');
        }
      } else {
        debugPrint('🌐 [SystemView] Fetched ${allEquips.length} total equipments from by-company endpoint');
      }

      // Load local provisioned devices from SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final localDevicesJson = prefs.getString('local_provisioned_devices') ?? '[]';
        final List<dynamic> localList = jsonDecode(localDevicesJson);
        for (var localDev in localList) {
          final localMap = Map<String, dynamic>.from(localDev);
          final String localId = (localMap['id'] ?? '').toString();
          final exists = allEquips.any((e) {
            final eId = (e['id'] ?? e['Id'] ?? '').toString();
            final eShortId = (e['shortId'] ?? e['ShortId'] ?? '').toString();
            return eId == localId || eShortId == localMap['shortId'];
          });
          if (!exists) {
            allEquips.add(localMap);
            debugPrint('➕ [SystemView] Added locally provisioned device to equipment list: ${localMap['name']}');
          }
        }
      } catch (e) {
        debugPrint('⚠️ [SystemView] Error loading local provisioned devices: $e');
      }

      // Group equipments by systemId and derive system list
      final Map<String, List<Map<String, dynamic>>> equipMap = {};
      final Map<String, SystemItem> systemMap = {};

      // Initialize systemMap with the systems fetched from the API
      for (var sys in systemsList) {
        final sysId = (sys['systemId'] ?? sys['Id'] ?? sys['systemid'] ?? '').toString();
        final sysName = (sys['name'] ?? sys['Name'] ?? sys['systemName'] ?? '').toString();
        final sysShortId = (sys['shortId'] ?? sys['ShortId'] ?? '').toString();
        if (sysId.isNotEmpty) {
          systemMap[sysId] = SystemItem(
            title: 'AC MONITORING SYSTEM',
            originalName: 'AC Monitoring System',
            equipment: sysName.isNotEmpty ? sysName : 'System',
            systemId: sysId,
            systemShortId: sysShortId.isNotEmpty ? sysShortId : (sysId.length >= 8 ? sysId.substring(0, 8) : sysId),
            iconColor: AppColors.primary,
          );
          equipMap[sysId] = []; // Initialize empty list for this system
        }
      }

      int totalAcs = 0;
      int onlineCount = 0;
      int runningCount = 0;

      for (var eq in allEquips) {
        var sysId = (eq['systemId'] ?? eq['SystemId'] ?? '').toString();
        if (sysId.isEmpty || sysId == 'local_system') continue;

        // Calculate metrics
        final statusObj = eq['onOffStatus'] ?? eq['OnOffStatus'];
        final isOnlineVal = statusObj != null
            ? (statusObj['isOnline'] ?? statusObj['IsOnline'])
            : null;
        final bool isOnline = isOnlineVal == true ||
            isOnlineVal == 1 ||
            isOnlineVal.toString().toLowerCase() == 'true';

        equipMap.putIfAbsent(sysId, () => []);
        equipMap[sysId]!.add(eq);

        totalAcs++;

        if (isOnline) {
          onlineCount++;

          final acStatus =
              (statusObj?['acStatus'] ?? statusObj?['AcStatus'] ?? 'OFF')
                  .toString()
                  .toUpperCase();
          if (acStatus == 'ON') runningCount++;

        }

        if (!systemMap.containsKey(sysId)) {
          final String name = realSystemsNames[sysId] ?? 'System ${systemMap.length + 1}';
          systemMap[sysId] = SystemItem(
            title: 'AC MONITORING SYSTEM',
            originalName: 'AC Monitoring System',
            equipment: name,
            systemId: sysId,
            systemShortId: sysId.length >= 8 ? sysId.substring(0, 8) : sysId,
            iconColor: AppColors.primary,
          );
        }
      }

      final fetchedSystems = systemMap.values.toList();
      debugPrint('✅ [SystemView] Derived ${fetchedSystems.length} systems from $totalAcs equipments');
      if (mounted) {
        widget.onCountChanged?.call(fetchedSystems.length);
        setState(() {
          systems = fetchedSystems;
          _equipmentsBySystem = equipMap;
          _totalAcs = totalAcs;
          _onlineCount = onlineCount;
          _runningCount = runningCount;
          isLoading = false;
        });

        // Cancel any existing SSE streams before starting new ones
        for (var sub in _sseSubscriptions.values) {
          sub.cancel();
        }
        _sseSubscriptions.clear();

        // Fetch live statuses from cached Redis API, then subscribe to SSE stream
        _fetchLiveStatuses(companyId, siteId, token).then((_) {
          for (var eq in allEquips ?? []) {
            final imei = (eq['imei'] ?? eq['Imei'] ?? eq['deviceId'] ?? eq['DeviceId'] ?? '').toString();
            final devId = imei.isNotEmpty ? imei : (eq['id'] ?? eq['Id'] ?? '').toString();
            if (devId.isNotEmpty) {
              _startSseForEquipment(companyId, devId, imei);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('❌ [SystemView] Error in _fetchSystemsAndEquipments: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// Fetches all AC equipments for the company/site using the proxy-safe endpoint
  Future<List<Map<String, dynamic>>?> _fetchAllEquipments(
      String companyId, String siteId, String token) async {
    final queryParams = <String>[];
    if (companyId.isNotEmpty && companyId != 'null' && companyId != 'undefined') {
      queryParams.add('companyId=$companyId');
    }
    if (siteId.isNotEmpty && siteId != 'null' && siteId != 'undefined') {
      queryParams.add('siteId=$siteId');
    }
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final url = '${AppConfig.provisionBaseUrl}/equipments$queryString';

    debugPrint('🌐 [SystemView] Fetching All Equipments: $url');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('🌐 [SystemView] Equipments response code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 1 && body['data'] != null) {
          final List<dynamic> list = body['data'];
          debugPrint('✅ [SystemView] Equipment API returned ${list.length} items');
          return list.map((e) => Map<String, dynamic>.from(e)).toList();
        } else {
          debugPrint('⚠️ [SystemView] Equipment API returned status=${body['status']}, data is null: ${body['data'] == null}');
        }
      } else {
        debugPrint('⚠️ [SystemView] Equipment API returned HTTP ${response.statusCode}: ${response.body}');
        if (response.statusCode == 404) {
          return null; // Return null so we fall back
        }
      }
    } catch (e) {
      debugPrint('❌ [SystemView] Error fetching equipments: $e');
    }
    return [];
  }

  /// Fetches equipment for a single system as a fallback
  Future<List<Map<String, dynamic>>> _fetchEquipmentsForSystem(
      String systemId, String companyId, String siteId, String token) async {
    final url = '${AppConfig.provisionBaseUrl}/systems/equipment/$systemId'
        '?companyId=$companyId&siteId=$siteId';
    debugPrint('🌐 [SystemView] Fetching Equipments for System: $url');
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
        final body = jsonDecode(response.body);
        if (body['status'] == 1 && body['data'] != null) {
          final List<dynamic> list = body['data'];
          return list.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } else {
        debugPrint('⚠️ [SystemView] Fallback system equipments API returned HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ [SystemView] Error fetching system equipments: $e');
    }
    return [];
  }

  @override
  void dispose() {
    for (var sub in _sseSubscriptions.values) {
      sub.cancel();
    }
    _sseSubscriptions.clear();
    super.dispose();
  }

  void _startSseForEquipment(String companyId, String deviceId, String? imei) {
    if (deviceId.isEmpty) return;
    final key = deviceId.toLowerCase();
    if (_sseSubscriptions.containsKey(key)) return; // Already listening

    _connectSse(companyId, deviceId, imei);
  }

  Future<void> _connectSse(String companyId, String deviceId, String? imei) async {
    final key = deviceId.toLowerCase();
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
      final uri = Uri.parse('${AppConfig.provisionBaseUrl}/mqtt/stream?${queryParams.join('&')}');
      
      debugPrint('🌐 [SystemView SSE] Connecting for $deviceId: $uri');
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
        debugPrint('🟢 [SystemView SSE] Connected successfully for $deviceId');
        
        final sub = response
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (line.startsWith('data:')) {
            final dataContent = line.substring(5).trim();
            if (dataContent.isNotEmpty && dataContent.startsWith('{')) {
              debugPrint('📩 [SystemView SSE] Received data for $deviceId: $dataContent');
              _handleSseMessage(deviceId, dataContent);
            }
          }
        }, onError: (e) {
          debugPrint('❌ [SystemView SSE] Error in stream for $deviceId: $e');
          _reconnectSse(companyId, deviceId, imei);
        }, onDone: () {
          debugPrint('⚠️ [SystemView SSE] Stream closed for $deviceId. Reconnecting...');
          _reconnectSse(companyId, deviceId, imei);
        });
        
        _sseSubscriptions[key] = sub;
      } else {
        debugPrint('❌ [SystemView SSE] Connection failed for $deviceId status: ${response.statusCode}');
        _reconnectSse(companyId, deviceId, imei);
      }
    } catch (e) {
      debugPrint('❌ [SystemView SSE] Exception for $deviceId: $e');
      _reconnectSse(companyId, deviceId, imei);
    }
  }

  void _reconnectSse(String companyId, String deviceId, String? imei) {
    final key = deviceId.toLowerCase();
    _sseSubscriptions[key]?.cancel();
    _sseSubscriptions.remove(key);
    
    // Retry after 5 seconds if widget is still mounted
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _connectSse(companyId, deviceId, imei);
      }
    });
  }

  void _handleSseMessage(String deviceId, String jsonStr) {
    try {
      final json = jsonDecode(jsonStr);
      // Check if it's a handshake / control message
      if (json['data'] == null && json['message'] != null) {
        return;
      }
      
      // Resolve data
      var data = json['data'] ?? json;
      
      final String? ac = data['ac']?.toString().toUpperCase();
      final double? temp = data['temp'] is num ? (data['temp'] as num).toDouble() : double.tryParse(data['temp']?.toString() ?? '');
      final double? hum = data['hum'] is num ? (data['hum'] as num).toDouble() : double.tryParse(data['hum']?.toString() ?? '');
      final String? status = (json['status'] ?? data['status'])?.toString().toUpperCase();
      
      final bool isOnline = status == 'ACTIVE' || status == 'ON' || status == 'OFF';
      
      // Update in our _equipmentsBySystem map
      bool updated = false;
      
      final Map<String, List<Map<String, dynamic>>> newEquipmentsMap = {};
      
      _equipmentsBySystem.forEach((sysId, list) {
        final List<Map<String, dynamic>> newList = [];
        for (final eq in list) {
          final eqShortId = (eq['shortId'] ?? eq['ShortId'] ?? '').toString();
          final eqImei = (eq['imei'] ?? eq['Imei'] ?? '').toString();
          
          if (eqShortId.toLowerCase() == deviceId.toLowerCase() || eqImei.toLowerCase() == deviceId.toLowerCase()) {
            final Map<String, dynamic> newEq = Map<String, dynamic>.from(eq);
            
            // Build new onOffStatus
            newEq['onOffStatus'] = {
              'isOnline': isOnline,
              'acStatus': ac ?? 'OFF',
              'temperature': temp ?? 0.0,
              'humidity': hum ?? 0.0,
            };
            newList.add(newEq);
            updated = true;
          } else {
            newList.add(eq);
          }
        }
        newEquipmentsMap[sysId] = newList;
      });
      
      if (updated && mounted) {
        setState(() {
          _equipmentsBySystem = newEquipmentsMap;
          
          int onlineCount = 0;
          int runningCount = 0;
          
          for (var list in _equipmentsBySystem.values) {
            for (var eq in list) {
              final statusObj = eq['onOffStatus'];
              if (statusObj != null) {
                final isOnlineVal = statusObj['isOnline'];
                final bool isOnline = isOnlineVal == true ||
                    isOnlineVal == 1 ||
                    isOnlineVal.toString().toLowerCase() == 'true';
                
                if (isOnline) {
                  onlineCount++;
                  final acStatus = statusObj['acStatus']?.toString().toUpperCase() ?? 'OFF';
                  if (acStatus == 'ON') {
                    runningCount++;
                  }
                  
                 }
              }
            }
          }
          
          _onlineCount = onlineCount;
          _runningCount = runningCount;
        });
      }
    } catch (e) {
      debugPrint('❌ [SystemView SSE] Error parsing json: $e');
    }
  }

  Future<void> _fetchLiveStatuses(String companyId, String siteId, String token) async {
    try {
      final zoneId = await AuthService.getZoneId() ?? '';
      final url = '${AppConfig.provisionBaseUrl}/mqtt/ac/status?companyId=$companyId&siteId=$siteId&zoneId=$zoneId';
      debugPrint('🌐 [SystemView] Fetching live AC statuses: $url');
      
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
        final List<dynamic> systemsData = body['systems'] ?? [];
        
        final Map<String, Map<String, dynamic>> statusByEquipmentId = {};
        for (var sys in systemsData) {
          final List<dynamic> eqs = sys['equipments'] ?? [];
          for (var eq in eqs) {
            final eqId = (eq['equipmentId'] ?? eq['EquipmentId'] ?? '').toString();
            if (eqId.isNotEmpty) {
              statusByEquipmentId[eqId] = eq;
            }
          }
        }
        
        // Merge into _equipmentsBySystem
        bool updated = false;
        final Map<String, List<Map<String, dynamic>>> newEquipmentsMap = {};
        
        _equipmentsBySystem.forEach((sysId, list) {
          final List<Map<String, dynamic>> newList = [];
          for (var eq in list) {
            final eqId = (eq['id'] ?? eq['Id'] ?? eq['equipmentId'] ?? eq['EquipmentId'] ?? '').toString();
            final statusData = statusByEquipmentId[eqId];
            if (statusData != null) {
              final Map<String, dynamic> newEq = Map<String, dynamic>.from(eq);
              final status = (statusData['status'] ?? 'DISCONNECTED').toString().toUpperCase();
              final isOnline = status == 'ON' || status == 'OFF';
              
              newEq['onOffStatus'] = {
                'isOnline': isOnline,
                'acStatus': status,
                'temperature': statusData['currentTemp'] ?? 0.0,
                'humidity': statusData['hum'] ?? 0.0,
              };
              newList.add(newEq);
              updated = true;
            } else {
              newList.add(eq);
            }
          }
          newEquipmentsMap[sysId] = newList;
        });
        
        if (updated && mounted) {
          setState(() {
            _equipmentsBySystem = newEquipmentsMap;
            
            int onlineCount = 0;
            int runningCount = 0;
            
            for (var list in _equipmentsBySystem.values) {
              for (var eq in list) {
                final statusObj = eq['onOffStatus'];
                if (statusObj != null) {
                  final isOnlineVal = statusObj['isOnline'];
                  final bool isOnline = isOnlineVal == true ||
                      isOnlineVal == 1 ||
                      isOnlineVal.toString().toLowerCase() == 'true';
                  
                  if (isOnline) {
                    onlineCount++;
                    final acStatus = statusObj['acStatus']?.toString().toUpperCase() ?? 'OFF';
                    if (acStatus == 'ON') {
                      runningCount++;
                    }
                    
                 }
                }
              }
            }
            
            _onlineCount = onlineCount;
            _runningCount = runningCount;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [SystemView] Error fetching live statuses: $e');
    }
  }

  Future<void> refreshData() async {
    await _fetchSystemsAndEquipments();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark ? AppColors.dividerDark : AppColors.divider;

    return Container(
      color: isDark ? AppColors.backgroundDark : AppColors.background,
      child: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Loading equipments...',
                    style: GoogleFonts.outfit(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _fetchSystemsAndEquipments,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  // ── Quick Metrics Summary ──
                  _buildQuickMetrics(isDark, cardColor, borderColor),
                  const SizedBox(height: 20),

                  // ── System Cards ──
                  ...systems.map((system) {
                    final equipments =
                        _equipmentsBySystem[system.systemId] ?? [];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _SystemCardWithEquipments(
                        system: system,
                        equipments: equipments,
                        onViewPressed: (String id, String name, String shortId,
                            {String? equipmentId, String? imei}) {
                          if (widget.onViewPressed != null) {
                            widget.onViewPressed!(id, name, shortId,
                                equipmentId: equipmentId, imei: imei);
                          }
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }

  Widget _buildQuickMetrics(bool isDark, Color cardColor, Color borderColor) {
    return SizedBox(
      height: 88,
      child: Row(
        children: [
          Expanded(
            child: _MetricChip(
              icon: Icons.power_settings_new_rounded,
              label: 'Active ACs',
              value: '$_runningCount',
              color: AppColors.online,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MetricChip(
              icon: Icons.wifi_rounded,
              label: 'Online',
              value: '$_onlineCount/$_totalAcs',
              color: AppColors.accent,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.divider,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class SystemItem {
  final String title;
  final String originalName;
  final String equipment;
  final String systemId;
  final String systemShortId;
  final Color iconColor;

  SystemItem({
    required this.title,
    required this.originalName,
    required this.equipment,
    required this.systemId,
    required this.systemShortId,
    required this.iconColor,
  });
}

/// A system card that shows the system header + its equipment items below
class _SystemCardWithEquipments extends StatelessWidget {
  final SystemItem system;
  final List<Map<String, dynamic>> equipments;
  final void Function(
    String systemId,
    String systemName,
    String systemShortId, {
    String? equipmentId,
    String? imei,
  }) onViewPressed;

  const _SystemCardWithEquipments({
    required this.system,
    required this.equipments,
    required this.onViewPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark ? AppColors.dividerDark : AppColors.divider;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subtitleColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return GestureDetector(
      onTap: () {
        final firstEq = equipments.isNotEmpty ? equipments.first : null;
        final eqId = firstEq != null
            ? (firstEq['id'] ?? firstEq['Id'] ?? firstEq['equipmentId'] ?? '')
                .toString()
            : null;
        final eqName = firstEq != null
            ? (firstEq['name'] ?? firstEq['Name'] ?? system.equipment).toString()
            : system.equipment;
        final eqImei = firstEq != null
            ? (firstEq['imei'] ??
                    firstEq['Imei'] ??
                    firstEq['deviceId'] ??
                    firstEq['DeviceId'] ??
                    '')
                .toString()
            : null;
        onViewPressed(
          system.systemId,
          eqName,
          (eqImei != null && eqImei.isNotEmpty) ? eqImei : system.systemShortId,
          equipmentId: eqId,
          imei: eqImei,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── System Header ──
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          system.equipment,
                          style: GoogleFonts.outfit(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          system.originalName,
                          style: GoogleFonts.inter(
                            color: subtitleColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Equipment count + Chevron
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (equipments.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${equipments.length}',
                            style: GoogleFonts.outfit(
                              color: AppColors.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: subtitleColor,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Equipment List ──
            if (equipments.isNotEmpty) ...[
              Container(
                height: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                color: borderColor,
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.ac_unit_rounded,
                        size: 12,
                        color: AppColors.primary.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Text(
                      '${equipments.length} Equipment${equipments.length == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(
                        color: subtitleColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              ...equipments.map((e) => _buildEquipmentRow(e, isDark, textColor, subtitleColor)),
              const SizedBox(height: 8),
            ],

            if (equipments.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: subtitleColor),
                    const SizedBox(width: 6),
                    Text(
                      'No equipments found',
                      style: GoogleFonts.inter(
                        color: subtitleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEquipmentRow(
    Map<String, dynamic> e,
    bool isDark,
    Color textColor,
    Color subtitleColor,
  ) {
    final name =
        (e['name'] ?? e['Name'] ?? 'Unknown Equipment').toString();
    final acType =
        (e['acType'] ?? e['AcType'] ?? '').toString();
    final statusObj = e['onOffStatus'] ?? e['OnOffStatus'];

    final isOnlineVal = statusObj != null
        ? (statusObj['isOnline'] ?? statusObj['IsOnline'])
        : null;
    final bool isOnline = isOnlineVal == true ||
        isOnlineVal == 1 ||
        isOnlineVal.toString().toLowerCase() == 'true';

    final acStatusVal = statusObj != null
        ? (statusObj['acStatus'] ?? statusObj['AcStatus'] ?? 'OFF')
        : 'OFF';
    final String acStatus = isOnline ? acStatusVal.toString() : '';
    final bool isRunning = isOnline && acStatus.toUpperCase() == 'ON';

    // Status color and label
    Color statusColor;
    String statusLabel;
    if (!isOnline) {
      statusColor = AppColors.textHint;
      statusLabel = 'Offline';
    } else if (isRunning) {
      statusColor = AppColors.online;
      statusLabel = 'Running';
    } else {
      statusColor = AppColors.offline;
      statusLabel = 'OFF';
    }

    // Temperature & Humidity
    final temp = statusObj != null
        ? (statusObj['temperature'] ?? statusObj['Temperature'])
        : null;
    final hum = statusObj != null
        ? (statusObj['humidity'] ?? statusObj['Humidity'])
        : null;

    double? tempVal;
    if (temp != null) {
      if (temp is num) {
        tempVal = temp.toDouble();
      } else {
        tempVal = double.tryParse(temp.toString());
      }
    }

    double? humVal;
    if (hum != null) {
      if (hum is num) {
        humVal = hum.toDouble();
      } else {
        humVal = double.tryParse(hum.toString());
      }
    }

    final sysId = (e['systemId'] ?? e['SystemId'] ?? '').toString();
    final eqId = (e['id'] ?? e['Id'] ?? e['equipmentId'] ?? e['EquipmentId'] ?? '').toString();
    final imei = (e['imei'] ?? e['Imei'] ?? e['deviceId'] ?? e['DeviceId'] ?? '').toString();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onViewPressed(
          sysId.isNotEmpty ? sysId : system.systemId,
          name,
          imei.isNotEmpty ? imei : system.systemShortId,
          equipmentId: eqId.isNotEmpty ? eqId : null,
          imei: imei.isNotEmpty ? imei : null,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : AppColors.background.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Pulsating status dot
              _StatusDot(color: statusColor, isOnline: isOnline && isRunning),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (acType.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        acType,
                        style: GoogleFonts.inter(
                          color: subtitleColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isOnline && tempVal != null) ...[
                _TelemetryChip(
                  value: '${tempVal.toStringAsFixed(1)}°C',
                  icon: Icons.thermostat_rounded,
                  color: AppColors.coolBlue,
                  isDark: isDark,
                ),
                const SizedBox(width: 6),
              ],
              if (isOnline && humVal != null) ...[
                _TelemetryChip(
                  value: '${humVal.toStringAsFixed(0)}%',
                  icon: Icons.water_drop_rounded,
                  color: AppColors.fanPurple,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
              ],
              // Status pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.inter(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pulsating status dot for online devices
class _StatusDot extends StatefulWidget {
  final Color color;
  final bool isOnline;
  const _StatusDot({required this.color, required this.isOnline});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isOnline) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isOnline && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOnline) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _animation.value * 0.5),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TelemetryChip extends StatelessWidget {
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;

  const _TelemetryChip({
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            value,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
