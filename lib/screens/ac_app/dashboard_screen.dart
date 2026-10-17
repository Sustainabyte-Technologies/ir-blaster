import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/core/services/admin_service.dart';

double _safeDouble(dynamic val) {
  if (val == null) return 0.0;
  if (val is num) return val.toDouble();
  return double.tryParse(val.toString()) ?? 0.0;
}

// Removed unused imports

// DashboardScreen manages its own tabs — no HomePage rebuild on tab switch
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _summary;
  List<dynamic> _equipments = [];
  Map<String, String> _systemsMap = {};
  Map<String, List<dynamic>> _groupedEquipments = {};

  bool _isLoadingHistory = true;
  List<double> _weeklyData = [];
  List<String> _weeklyLabels = [];
  List<double> _monthlyData = [];
  List<String> _monthlyLabels = [];

  StreamSubscription? _mqttStateSub;

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    _fetchSummaryData();

    _mqttStateSub = MqttService().stateStream.listen((state) {
      if (!mounted) return;
      bool updated = false;
      setState(() {
        for (var eq in _equipments) {
          final eqImei = eq['imei']?.toString().toLowerCase() ?? '';
          final eqShortId = eq['shortId']?.toString().toLowerCase() ?? '';
          final stateDeviceId = state.deviceId.toLowerCase();
          final stateImei = state.imei.toLowerCase();

          if ((eqImei.isNotEmpty &&
                  (eqImei == stateImei || eqImei == stateDeviceId)) ||
              (eqShortId.isNotEmpty &&
                  (eqShortId == stateImei || eqShortId == stateDeviceId))) {
            eq['onOffStatus'] = {
              'isOnline': state.isActive,
              'acStatus': state.isPowerOn ? 'ON' : 'OFF',
              'temperature':
                  (state.currentTemp > 0 ? state.currentTemp : state.setTemp)
                      .toDouble(),
              'humidity': state.humidity.toDouble(),
            };
            updated = true;
          }
        }
        if (updated) {
          _groupedEquipments = _processEquipments(_equipments, _systemsMap);
        }
      });
    });
  }

  @override
  void dispose() {
    _mqttStateSub?.cancel();
    super.dispose();
  }

  Future<void> _loadCachedData() async {
    final cached = await LocalCacheService.getDashboardData();
    if (cached != null && mounted) {
      final data = cached['data'];
      final timestamp = cached['timestamp'];
      final diff = DateTime.now().millisecondsSinceEpoch - (timestamp as int);

      // Only show cache if it's less than 24 hours old (optional)
      if (diff < 86400000 &&
          data['equipments'] != null &&
          (data['equipments'] as List).isNotEmpty) {
        setState(() {
          _summary = data['summary'];
          _equipments = data['equipments'];
          _groupedEquipments =
              _processEquipments(data['equipments'], data['systemsMap'] ?? {});
          // Keep _isLoading = true to show a fresh loading indicator on page entry
        });
      }
    }
  }

  Map<String, List<dynamic>> _processEquipments(
      List<dynamic> equipments, Map<String, dynamic> sMap) {
    final Map<String, List<dynamic>> gMap = {};
    for (var e in equipments) {
      final sId = e['systemId'];
      final sysName = (sId != null && sMap.containsKey(sId))
          ? sMap[sId]!
          : (e['acType'] ?? 'General System');
      gMap.putIfAbsent(sysName, () => []).add(e);
    }
    return gMap;
  }

  Future<void> _fetchSummaryData() async {
    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final zoneId = await AuthService.getZoneId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';

      final url =
          '${AppConfig.provisionBaseUrl}/mqtt/ac/status?companyId=$companyId&siteId=$siteId&zoneId=$zoneId';
      debugPrint('🌐 [Dashboard] Fetching live AC status: $url');

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

        final List<dynamic> allEquipments = [];
        final Map<String, String> sMap = {};
        final Map<String, List<dynamic>> gMap = {};

        final systemsList = body['systems'] as List<dynamic>? ?? [];
        for (var sys in systemsList) {
          final sysId = sys['systemId']?.toString() ?? '';
          final sysName = sys['systemName']?.toString() ?? 'Unknown';
          if (sysId.isNotEmpty) {
            sMap[sysId] = sysName;
          }

          final equips = sys['equipments'] as List<dynamic>? ?? [];
          for (var eq in equips) {
            final liveStatus =
                eq['status']?.toString().toUpperCase() ?? 'DISCONNECTED';
            final isOnline = liveStatus == 'ON' || liveStatus == 'OFF';

            final mappedEq = {
              'equipmentId': eq['equipmentId'],
              'name': eq['name'],
              'shortId': eq['shortId'],
              'imei': eq['imei'],
              'systemId': sysId,
              'acType': eq['acType'] ?? 'Split AC',
              'onOffStatus': {
                'isOnline': isOnline,
                'acStatus': liveStatus == 'ON' ? 'ON' : 'OFF',
                'temperature': _safeDouble(eq['currentTemp'] ?? eq['setTemp']),
                'humidity': _safeDouble(eq['hum']),
              }
            };
            allEquipments.add(mappedEq);
            gMap.putIfAbsent(sysName, () => []).add(mappedEq);
          }
        }



        // Calculate dynamic summary stats
        int totalCount = 0;
        int onCount = 0;
        int offCount = 0;
        int disconnectedCount = 0;

        for (var eq in allEquipments) {
          totalCount++;
          final statusObj = eq['onOffStatus'];
          final isOnline = statusObj?['isOnline'] == true;
          final acStatus = statusObj?['acStatus']?.toString().toUpperCase() ?? 'OFF';
          if (isOnline) {
            if (acStatus == 'ON') {
              onCount++;
            } else {
              offCount++;
            }
          } else {
            disconnectedCount++;
          }
        }

        final localSummary = {
          'total': totalCount,
          'on': onCount,
          'off': offCount,
          'notConnected': disconnectedCount,
        };

        if (body['totalAc'] == null || body['totalAc'] == 0) {
          await _fetchSummaryDataFallback(companyId, siteId, token);
          return;
        }

        if (mounted) {
          setState(() {
            _summary = localSummary;
            _equipments = allEquipments;
            _systemsMap = sMap;
            _groupedEquipments = gMap;
          });

          // Save to cache for next time
          LocalCacheService.saveDashboardData({
            'summary': localSummary,
            'equipments': allEquipments,
            'systemsMap': sMap,
          });

          // Fetch actual history and wait for it
          await _fetchHistoryData(companyId, token);

          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      } else {
        debugPrint('⚠️ [Dashboard] Status API returned HTTP ${response.statusCode}: ${response.body}');
        await _fetchSummaryDataFallback(companyId, siteId, token);
      }
    } catch (e) {
      debugPrint('❌ [Dashboard] Error: $e');
      try {
        final companyId = await AuthService.getCompanyId() ?? '';
        final siteId = await AuthService.getSiteId() ?? '';
        final token = await AuthService.getCookieHeader() ?? '';
        await _fetchSummaryDataFallback(companyId, siteId, token);
      } catch (_) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _fetchSummaryDataFallback(
      String companyId, String siteId, String token) async {
    debugPrint('🔄 [Dashboard] Falling back to systems/equipment APIs for dashboard data...');
    try {
      final List<dynamic> allEquipments = [];
      final Map<String, String> sMap = {};
      final Map<String, List<dynamic>> gMap = {};
      int total = 0;
      int onCount = 0;
      int offCount = 0;
      int disconnectedCount = 0;

      final systemsList = await AdminService.fetchSystems(companyId: companyId, siteId: siteId);
      debugPrint('🌐 [Dashboard] Fallback: fetched ${systemsList.length} systems');

      for (var sys in systemsList) {
        final sysId = (sys['systemId'] ?? sys['Id'] ?? sys['systemid'] ?? '').toString();
        final sysName = (sys['systemName'] ?? sys['Name'] ?? sys['name'] ?? 'System').toString();
        if (sysId.isNotEmpty) {
          sMap[sysId] = sysName;
          final equips = await _fetchEquipmentsForSystem(sysId, companyId, siteId, token);
          debugPrint('🌐 [Dashboard] Fallback: system $sysId has ${equips.length} equipments');

          for (var eq in equips) {
            final statusObj = eq['onOffStatus'] ?? eq['OnOffStatus'];
            final isOnlineVal = statusObj != null
                ? (statusObj['isOnline'] ?? statusObj['IsOnline'])
                : null;
            final bool isOnline = isOnlineVal == true ||
                isOnlineVal == 1 ||
                isOnlineVal.toString().toLowerCase() == 'true';
            
            final acStatus =
                (statusObj?['acStatus'] ?? statusObj?['AcStatus'] ?? 'OFF')
                    .toString()
                    .toUpperCase();
            
            final mappedEq = {
              'equipmentId': eq['equipmentId'] ?? eq['EquipmentId'] ?? eq['id'] ?? eq['Id'] ?? '',
              'name': eq['name'] ?? eq['Name'] ?? 'Smart AC Controller',
              'shortId': eq['shortId'] ?? eq['ShortId'] ?? '',
              'imei': eq['imei'] ?? eq['Imei'] ?? eq['shortId'] ?? '',
              'systemId': sysId,
              'acType': eq['acType'] ?? eq['AcType'] ?? 'Split AC',
              'onOffStatus': {
                'isOnline': isOnline,
                'acStatus': acStatus,
                'temperature': _safeDouble(statusObj?['temperature'] ?? statusObj?['Temperature']),
                'humidity': _safeDouble(statusObj?['humidity'] ?? statusObj?['Humidity']),
              }
            };
            allEquipments.add(mappedEq);
            gMap.putIfAbsent(sysName, () => []).add(mappedEq);
            
            total++;
            if (isOnline) {
              if (acStatus == 'ON') {
                onCount++;
              } else {
                offCount++;
              }
            } else {
              disconnectedCount++;
            }
          }
        }
      }



      if (total == 0) {
        if (mounted) {
          setState(() {
            _summary = {'total': 0, 'on': 0, 'off': 0, 'notConnected': 0};
            _equipments = [];
            _systemsMap = {};
            _groupedEquipments = {};
            _isLoading = false;
          });
        }
        return;
      }

      final localSummary = {
        'total': total,
        'on': onCount,
        'off': offCount,
        'notConnected': disconnectedCount,
      };

      if (mounted) {
        setState(() {
          _summary = localSummary;
          _equipments = allEquipments;
          _systemsMap = sMap;
          _groupedEquipments = gMap;
        });

        // Save to cache for next time
        LocalCacheService.saveDashboardData({
          'summary': localSummary,
          'equipments': allEquipments,
          'systemsMap': sMap,
        });

        // Fetch actual history and wait for it
        await _fetchHistoryData(companyId, token);

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [Dashboard] Error in fallback summary data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchEquipmentsForSystem(
      String systemId, String companyId, String siteId, String token) async {
    final url = '${AppConfig.provisionBaseUrl}/systems/equipment/$systemId'
        '?companyId=$companyId&siteId=$siteId';
    debugPrint('🌐 [Dashboard] Fetching Equipments for System: $url');
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
        debugPrint('⚠️ [Dashboard] Fallback system equipments API returned HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ [Dashboard] Error fetching system equipments: $e');
    }
    return [];
  }

  Future<void> _fetchHistoryData(String companyId, String token) async {
    if (companyId.isEmpty) return;
    try {
      final headers = {
        'Authorization': 'Bearer $token',
        'Cookie': 'auth_token=$token',
        'Content-Type': 'application/json',
      };

      final now = DateTime.now();

      // 1. Fetch Weekly Data (Last 7 Days)
      final List<Future<http.Response>> weeklyRequests = [];
      final List<String> tempLabels = [];
      final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dateStr =
            "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
        final url =
            '${AppConfig.provisionBaseUrl}/mqtt/ac/history?companyId=$companyId&from=$dateStr&to=$dateStr';
        weeklyRequests.add(http.get(Uri.parse(url), headers: headers));
        tempLabels.add(weekdays[date.weekday - 1]);
      }

      // 2. Fetch Monthly Data (Last 4 Weeks)
      final List<Future<http.Response>> monthlyRequests = [];
      final List<String> tempMonthlyLabels = ['Wk 1', 'Wk 2', 'Wk 3', 'Wk 4'];

      for (int i = 3; i >= 0; i--) {
        final start = now.subtract(Duration(days: (i * 7) + 6));
        final end = now.subtract(Duration(days: i * 7));
        final startStr =
            "${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}";
        final endStr =
            "${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}";
        final url =
            '${AppConfig.provisionBaseUrl}/mqtt/ac/history?companyId=$companyId&from=$startStr&to=$endStr';
        monthlyRequests.add(http.get(Uri.parse(url), headers: headers));
      }

      // Execute all in parallel
      final allResponses =
          await Future.wait([...weeklyRequests, ...monthlyRequests]);

      final weeklyResponses = allResponses.sublist(0, 7);
      final monthlyResponses = allResponses.sublist(7, 11);

      // Process Weekly
      final List<double> processedWeekly = [];
      for (var resp in weeklyResponses) {
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final devices = data['devices'] as List<dynamic>? ?? [];
          if (devices.isNotEmpty) {
            double sumHours = 0;
            for (var dev in devices) {
              sumHours += (dev['totalRunningHours'] ?? 0.0) as double;
            }
            processedWeekly.add(sumHours / devices.length);
          } else {
            processedWeekly.add(0.0);
          }
        } else {
          processedWeekly.add(0.0);
        }
      }

      // Process Monthly
      final List<double> processedMonthly = [];
      for (var resp in monthlyResponses) {
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final devices = data['devices'] as List<dynamic>? ?? [];
          if (devices.isNotEmpty) {
            double sumHours = 0;
            for (var dev in devices) {
              sumHours += (dev['totalRunningHours'] ?? 0.0) as double;
            }
            processedMonthly.add((sumHours / devices.length) / 7.0);
          } else {
            processedMonthly.add(0.0);
          }
        } else {
          processedMonthly.add(0.0);
        }
      }

      if (mounted) {
        setState(() {
          _weeklyData = processedWeekly;
          _weeklyLabels = tempLabels;
          _monthlyData = processedMonthly;
          _monthlyLabels = tempMonthlyLabels;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [DashboardScreen] Error fetching history: $e');
      if (mounted) {
        setState(() {
          _weeklyData = List.filled(7, 0.0);
          _weeklyLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          _monthlyData = List.filled(4, 0.0);
          _monthlyLabels = ['Wk 1', 'Wk 2', 'Wk 3', 'Wk 4'];
          _isLoadingHistory = false;
        });
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

    return _isLoading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.primary))
        : _StatusView(
            isDark: isDark,
            textColor: textColor,
            summary: _summary ?? {},
            equipments: _equipments,
            systemsMap: _systemsMap,
            groupedEquipments: _groupedEquipments,
            weeklyData: _weeklyData,
            weeklyLabels: _weeklyLabels,
            monthlyData: _monthlyData,
            monthlyLabels: _monthlyLabels,
            isLoadingHistory: _isLoadingHistory,
          );
  }
}

// ──────────────────────────────────────────────────────────────
// STATUS VIEW
// ──────────────────────────────────────────────────────────────
class _StatusView extends StatelessWidget {
  final bool isDark;
  final Color textColor;
  final Map<String, dynamic> summary;
  final List<dynamic> equipments;
  final Map<String, String> systemsMap;
  final Map<String, List<dynamic>> groupedEquipments;
  final List<double> weeklyData;
  final List<String> weeklyLabels;
  final List<double> monthlyData;
  final List<String> monthlyLabels;
  final bool isLoadingHistory;

  const _StatusView({
    required this.isDark,
    required this.textColor,
    required this.summary,
    required this.equipments,
    required this.systemsMap,
    required this.groupedEquipments,
    required this.weeklyData,
    required this.weeklyLabels,
    required this.monthlyData,
    required this.monthlyLabels,
    required this.isLoadingHistory,
  });

  Widget _smallMetricCard(
      String title, int value, Color color, IconData icon, Color cardColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.divider),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          Text('$value',
              style: GoogleFonts.outfit(
                  color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
          Text(title,
              style: GoogleFonts.inter(
                  color: textColor.withValues(alpha: 0.5),
                  fontSize: 9,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;

    final segments = [
      ChartSegment(
          'Running', (summary['on'] ?? 0).toDouble(), AppColors.online),
      ChartSegment(
          'Offline', (summary['off'] ?? 0).toDouble(), AppColors.offline),
      ChartSegment('Not Connected', (summary['notConnected'] ?? 0).toDouble(),
          AppColors.textHint),
    ];

    final int totalUnits = summary['total'] ?? 0;
    final int notConnUnits = summary['notConnected'] ?? 0;
    final int connectedUnits = totalUnits - notConnUnits;
    final int runningUnits = summary['on'] ?? 0;
    final String runningPercentage =
        totalUnits > 0 ? '${(runningUnits * 100 / totalUnits).round()}%' : '0%';

    // Group by systemName (Already pre-calculated in State)
    final grouped = groupedEquipments;

    final floors = grouped.entries.map((entry) {
      final list = entry.value;
      int running = 0, offline = 0, notConn = 0;
      for (var item in list) {
        final status = item['onOffStatus'];
        if (status != null && status['isOnline'] == true) {
          if (status['acStatus'] == 'ON') {
            running++;
          } else {
            offline++;
          }
        } else {
          notConn++;
        }
      }
      return _FloorData(entry.key, list.length, running, 0, offline + notConn);
    }).toList();

    // Map to popup data
    final allEquipment = equipments.map((e) {
      final statusObj = e['onOffStatus'];
      String status = 'Offline';
      if (statusObj != null && statusObj['isOnline'] == true) {
        status = statusObj['acStatus'] == 'ON' ? 'Running' : 'Offline';
      }
      return _EquipData(e['name'] ?? 'Unknown', e['systemId'] ?? '', status,
          e['acType'] ?? 'General AC');
    }).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header('Overview'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _smallMetricCard(
                      'Total AC',
                      totalUnits,
                      const Color(0xFF0EA5E9),
                      Icons.grid_view_rounded,
                      cardColor)),
              const SizedBox(width: 10),
              Expanded(
                  child: _smallMetricCard('Connected', connectedUnits,
                      const Color(0xFF8B5CF6), Icons.wifi_rounded, cardColor)),
              const SizedBox(width: 10),
              Expanded(
                  child: _smallMetricCard(
                      'Disconnected',
                      notConnUnits,
                      const Color(0xFF94A3B8),
                      Icons.wifi_off_rounded,
                      cardColor)),
            ],
          ),
          const SizedBox(height: 28),
          _header('AC Status Distribution'),
          const SizedBox(height: 12),
          // Doughnut Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: _cardDeco(isDark, cardColor),
            child: Row(
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      RepaintBoundary(
                        child: CustomPaint(
                          size: const Size(160, 160),
                          painter: DoughnutPainter(
                            segments: segments,
                            bgColor: isDark
                                ? textColor.withValues(alpha: 0.05)
                                : const Color(0xFFF3F4F6),
                            strokeWidth: 32,
                          ),
                        ),
                      ),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(runningPercentage,
                            style: GoogleFonts.poppins(
                                color: textColor,
                                fontSize: 32,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    children: segments
                        .map((seg) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(children: [
                                Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                        color: seg.color,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                              color: seg.color
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 6)
                                        ])),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(seg.label,
                                        style: GoogleFonts.poppins(
                                            color: textColor.withValues(
                                                alpha: 0.7),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500))),
                                Text('${seg.value.toInt()}',
                                    style: GoogleFonts.poppins(
                                        color: textColor,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                              ]),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          _UsageStatisticsCard(
            isDark: isDark,
            textColor: textColor,
            weeklyData: weeklyData,
            weeklyLabels: weeklyLabels,
            monthlyData: monthlyData,
            monthlyLabels: monthlyLabels,
            isLoading: isLoadingHistory,
          ),
          const SizedBox(height: 28),
          _header('AC Status by System'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: _cardDeco(isDark, cardColor),
            child: Column(
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Status by System',
                          style: GoogleFonts.poppins(
                              color: textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      GestureDetector(
                        onTap: () => _showEquipmentPopup(
                            context, allEquipment, isDark, systemsMap),
                        child: Text('View All',
                            style: GoogleFonts.poppins(
                                color: const Color(0xFF0EA5E9),
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                const SizedBox(height: 20),
                ...floors.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: _floorRow(f, textColor),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _floorRow(_FloorData f, Color textColor) {
    final total = f.running + f.alert + f.offline;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(f.name,
              style: GoogleFonts.poppins(
                  color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
          Text('${f.total} Units',
              style: GoogleFonts.poppins(
                  color: textColor.withValues(alpha: 0.4),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 8,
          child: Row(children: [
            Flexible(
                flex: (f.running * 100 / total).round(),
                child: Container(color: const Color(0xFF6CC042))),
            if (f.alert > 0)
              Flexible(
                  flex: (f.alert * 100 / total).round(),
                  child: Container(color: const Color(0xFFF43F5E))),
            if (f.offline > 0)
              Flexible(
                  flex: (f.offline * 100 / total).round(),
                  child: Container(color: const Color(0xFF94A3B8))),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        _statusIndicator('${f.running} Running', const Color(0xFF6CC042)),
        if (f.alert > 0) ...[
          const SizedBox(width: 16),
          _statusIndicator('${f.alert} Alert', const Color(0xFFF43F5E))
        ],
        if (f.offline > 0) ...[
          const SizedBox(width: 16),
          _statusIndicator('${f.offline} Offline', const Color(0xFF94A3B8))
        ],
      ]),
    ]);
  }

  Widget _statusIndicator(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.poppins(
                color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _header(String title) => Text(title.toUpperCase(),
      style: GoogleFonts.poppins(
          color: textColor.withValues(alpha: 0.4),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2));

  BoxDecoration _cardDeco(bool isDark, Color cardColor) => BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05)));
}

// ──────────────────────────────────────────────────────────────
// MODELS & PAINTERS
// ──────────────────────────────────────────────────────────────
class ChartSegment {
  final String label;
  final double value;
  final Color color;
  const ChartSegment(this.label, this.value, this.color);
}

class _FloorData {
  final String name;
  final int total, running, alert, offline;
  const _FloorData(
      this.name, this.total, this.running, this.alert, this.offline);
}

enum _PopupViewType { list, chart }

class _EquipData {
  final String id;
  final String systemId;
  final String status;
  final String acType;
  const _EquipData(this.id, this.systemId, this.status, this.acType);
}

void _showEquipmentPopup(BuildContext context, List<_EquipData> equipment,
    bool isDark, Map<String, String> systemsMap) {
  final bgColor = isDark ? const Color(0xFF1B172E) : const Color(0xFFF8FAFC);
  final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

  // Group by systemName
  final Map<String, List<_EquipData>> grouped = {};
  for (var e in equipment) {
    final name =
        systemsMap.containsKey(e.systemId) ? systemsMap[e.systemId]! : e.acType;
    grouped.putIfAbsent(name, () => []).add(e);
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 30,
                offset: const Offset(0, -10))
          ],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SYSTEM STATUS MAP',
                          style: GoogleFonts.poppins(
                              color: textColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _statusLegend(
                              'AC ON', const Color(0xFF6CC042), isDark),
                          const SizedBox(width: 16),
                          _statusLegend(
                              'AC OFF', const Color(0xFFF59E0B), isDark),
                          const SizedBox(width: 16),
                          _statusLegend(
                              'OFFLINE', const Color(0xFF94A3B8), isDark),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6CC042).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.hub_outlined,
                        color: const Color(0xFF6CC042), size: 24),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, indent: 32, endIndent: 32),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 80),
                child: Column(
                  children: grouped.entries.map((entry) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 48),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : Colors.black.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(entry.key.toUpperCase(),
                                style: GoogleFonts.poppins(
                                    color: textColor.withValues(alpha: 0.6),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5)),
                          ),
                          const SizedBox(height: 32),
                          _StatusCircuitHub(
                            units: entry.value,
                            isDark: isDark,
                            textColor: textColor,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _statusLegend(String label, Color color, bool isDark) {
  return Row(
    children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label,
          style: GoogleFonts.poppins(
              color: color.withValues(alpha: 0.8),
              fontSize: 9,
              fontWeight: FontWeight.w700)),
    ],
  );
}

class _StatusCircuitHub extends StatefulWidget {
  final List<_EquipData> units;
  final bool isDark;
  final Color textColor;

  const _StatusCircuitHub(
      {required this.units, required this.isDark, required this.textColor});

  @override
  State<_StatusCircuitHub> createState() => _StatusCircuitHubState();
}

class _StatusCircuitHubState extends State<_StatusCircuitHub>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return CustomPaint(
            size: const Size(double.infinity, 260),
            painter: _StatusCircuitPainter(
              units: widget.units,
              isDark: widget.isDark,
              textColor: widget.textColor,
              pulse: _pulseController.value,
            ),
          );
        },
      ),
    );
  }
}

class _StatusCircuitPainter extends CustomPainter {
  final List<_EquipData> units;
  final bool isDark;
  final Color textColor;
  final double pulse;

  _StatusCircuitPainter(
      {required this.units,
      required this.isDark,
      required this.textColor,
      required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final hubRadius = 45.0;
    final orbitRadius = 90.0;

    final onColor = const Color(0xFF6CC042);
    final offColor = const Color(0xFFF59E0B);
    final offlineColor = const Color(0xFF94A3B8);

    // 1. Draw Background Grid/Pattern
    final gridPaint = Paint()
      ..color = textColor.withValues(alpha: 0.03)
      ..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 30)
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    for (double i = 0; i < size.height; i += 30)
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);

    // 2. Draw Orbit Track
    canvas.drawCircle(
        center,
        orbitRadius,
        Paint()
          ..color = textColor.withValues(alpha: 0.05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);

    // 3. Draw Nodes and Connections
    for (int i = 0; i < units.length; i++) {
      final angle = (i / units.length) * 2 * math.pi - math.pi / 2;
      final nodePos = Offset(center.dx + orbitRadius * math.cos(angle),
          center.dy + orbitRadius * math.sin(angle));

      // Determine Status Color
      Color color = offlineColor;
      bool isPulse = false;
      if (units[i].status == 'Running') {
        color = onColor;
        isPulse = true;
      } else if (units[i].status == 'Offline') {
        color = offColor; // AC is OFF but connected
      } else {
        color = offlineColor; // Disconnected
      }

      // Connection Line (High-Tech Style)
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.1)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
          Offset(center.dx + hubRadius * math.cos(angle),
              center.dy + hubRadius * math.sin(angle)),
          nodePos,
          linePaint);

      // Node Glow
      if (isPulse) {
        final glowSize = 12 + (pulse * 8);
        canvas.drawCircle(
            nodePos,
            glowSize,
            Paint()
              ..color = color.withValues(alpha: 0.2 * (1 - pulse))
              ..style = PaintingStyle.fill);
      }

      // Node Circle
      canvas.drawCircle(
          nodePos,
          8,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          nodePos,
          8,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);

      // Label
      final labelPainter = TextPainter(
        text: TextSpan(
          text: units[i].id,
          style: GoogleFonts.poppins(
              color: textColor.withValues(alpha: 0.8),
              fontSize: 9,
              fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Label Positioning
      double lx = nodePos.dx + (18 * math.cos(angle));
      double ly = nodePos.dy + (18 * math.sin(angle));
      if (math.cos(angle).abs() < 0.1)
        lx -= labelPainter.width / 2;
      else if (math.cos(angle) < 0) lx -= labelPainter.width;
      labelPainter.paint(canvas, Offset(lx, ly));
    }

    // 4. Hub Node (Central Core)
    final hubPaint = Paint()
      ..color = isDark ? const Color(0xFF2A244D) : Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, hubRadius, hubPaint);
    canvas.drawCircle(
        center,
        hubRadius,
        Paint()
          ..color = onColor.withValues(alpha: 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);

    // Hub Stats
    final onCount = units.where((u) => u.status == 'Running').length;
    final totalCount = units.length;
    final hubTextPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
              text: '$onCount',
              style: GoogleFonts.poppins(
                  color: onColor, fontSize: 20, fontWeight: FontWeight.w900)),
          TextSpan(
              text: '/$totalCount\n',
              style: GoogleFonts.poppins(
                  color: textColor.withValues(alpha: 0.4),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          TextSpan(
              text: 'AC ACTIVE',
              style: GoogleFonts.poppins(
                  color: textColor.withValues(alpha: 0.3),
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    hubTextPainter.paint(canvas,
        center - Offset(hubTextPainter.width / 2, hubTextPainter.height / 2));
  }

  @override
  bool shouldRepaint(_StatusCircuitPainter old) =>
      old.pulse != pulse || old.units.length != units.length;
}

class DoughnutPainter extends CustomPainter {
  final List<ChartSegment> segments;
  final Color bgColor;
  final double strokeWidth;
  const DoughnutPainter(
      {required this.segments, required this.bgColor, this.strokeWidth = 24});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = bgColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt);
    double total = segments.fold(0, (s, e) => s + e.value);
    if (total == 0) return;
    double angle = -math.pi / 2;
    for (final seg in segments) {
      final sweep = (seg.value / total) * 2 * math.pi;
      if (sweep > 0)
        canvas.drawArc(
            rect,
            angle,
            sweep,
            false,
            Paint()
              ..color = seg.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..strokeCap = StrokeCap.butt);
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(DoughnutPainter old) =>
      old.bgColor != bgColor || old.segments.length != segments.length;
}



// ──────────────────────────────────────────────────────────────
// USAGE STATISTICS CARD (Weekly & Monthly Run Time)
// ──────────────────────────────────────────────────────────────
class _UsageStatisticsCard extends StatefulWidget {
  final bool isDark;
  final Color textColor;
  final List<double> weeklyData;
  final List<String> weeklyLabels;
  final List<double> monthlyData;
  final List<String> monthlyLabels;
  final bool isLoading;

  const _UsageStatisticsCard({
    required this.isDark,
    required this.textColor,
    required this.weeklyData,
    required this.weeklyLabels,
    required this.monthlyData,
    required this.monthlyLabels,
    required this.isLoading,
  });

  @override
  State<_UsageStatisticsCard> createState() => _UsageStatisticsCardState();
}

class _UsageStatisticsCardState extends State<_UsageStatisticsCard> {
  bool _isWeekly = true;

  @override
  Widget build(BuildContext context) {
    final cardColor = widget.isDark ? AppColors.surfaceDark : AppColors.surface;

    if (widget.isLoading) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final currentData = _isWeekly ? widget.weeklyData : widget.monthlyData;
    final currentLabels =
        _isWeekly ? widget.weeklyLabels : widget.monthlyLabels;

    if (currentData.isEmpty) {
      return const SizedBox.shrink();
    }

    final avgHours = currentData.reduce((a, b) => a + b) / currentData.length;
    final totalHours = _isWeekly
        ? currentData.reduce((a, b) => a + b)
        : currentData.reduce((a, b) => a + b) * 7.0;

    final avgWholeHours = avgHours.floor();
    final avgMinutes = ((avgHours - avgWholeHours) * 60).round();
    final avgText = avgWholeHours == 0
        ? '$avgMinutes m'
        : (avgMinutes == 0
            ? '$avgWholeHours h'
            : '$avgWholeHours h $avgMinutes m');

    final totalWholeHours = totalHours.floor();
    final totalMinutes = ((totalHours - totalWholeHours) * 60).round();
    final totalText = totalWholeHours == 0
        ? '$totalMinutes mins'
        : (totalMinutes == 0
            ? '$totalWholeHours hrs'
            : '$totalWholeHours hrs $totalMinutes mins');

    return Container(
      margin: const EdgeInsets.only(top: 28),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: widget.isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AC RUNNING TIME',
                style: GoogleFonts.poppins(
                  color: widget.textColor.withValues(alpha: 0.4),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              // Segmented Control
              Container(
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: [
                    _toggleTab('Weekly', true),
                    _toggleTab('Monthly', false),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                avgText,
                style: GoogleFonts.poppins(
                  color: widget.textColor,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Avg/Day',
                style: GoogleFonts.poppins(
                  color: widget.textColor.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                'Total: $totalText',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF6CC042),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 140,
            child: _BarChart(
              data: currentData,
              labels: currentLabels,
              color: const Color(0xFF6CC042),
              isDark: widget.isDark,
              textColor: widget.textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleTab(String label, bool isWeeklyOpt) {
    final active = _isWeekly == isWeeklyOpt;
    return GestureDetector(
      onTap: () => setState(() => _isWeekly = isWeeklyOpt),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? (widget.isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active && !widget.isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: active
                ? widget.textColor
                : widget.textColor.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _BarChart extends StatefulWidget {
  final List<double> data;
  final List<String> labels;
  final Color color;
  final bool isDark;
  final Color textColor;

  const _BarChart({
    required this.data,
    required this.labels,
    required this.color,
    required this.isDark,
    required this.textColor,
  });

  @override
  State<_BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<_BarChart> {
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => _handleTouch(d.localPosition, constraints),
          onPanEnd: (_) => setState(() => _hoverIndex = null),
          onTapDown: (d) => _handleTouch(d.localPosition, constraints),
          onTapUp: (_) => setState(() => _hoverIndex = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _BarChartPainter(
                    data: widget.data,
                    labels: widget.labels,
                    color: widget.color,
                    isDark: widget.isDark,
                    textColor: widget.textColor,
                    hoverIndex: _hoverIndex,
                  ),
                ),
              ),
              if (_hoverIndex != null && _hoverIndex! < widget.data.length)
                _tooltip(constraints, _hoverIndex!, widget.data[_hoverIndex!]),
            ],
          ),
        );
      },
    );
  }

  void _handleTouch(Offset localPos, BoxConstraints constraints) {
    final itemWidth = constraints.maxWidth / widget.data.length;
    final index =
        (localPos.dx / itemWidth).floor().clamp(0, widget.data.length - 1);
    if (_hoverIndex != index) {
      setState(() => _hoverIndex = index);
    }
  }

  Widget _tooltip(BoxConstraints c, int idx, double val) {
    final itemWidth = c.maxWidth / widget.data.length;
    double x = (idx * itemWidth) + (itemWidth / 2);
    x = x.clamp(45.0, c.maxWidth - 45.0);
    return Positioned(
      left: x - 45,
      top: -30,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1B172E) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: widget.color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Center(
          child: Text(
            '${val.toStringAsFixed(1)} h',
            style: GoogleFonts.poppins(
              color: widget.textColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final Color color;
  final bool isDark;
  final Color textColor;
  final int? hoverIndex;

  const _BarChartPainter({
    required this.data,
    required this.labels,
    required this.color,
    required this.isDark,
    required this.textColor,
    this.hoverIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxVal = data.isEmpty ? 1.0 : data.reduce(math.max);
    final limit = maxVal == 0 ? 1.0 : maxVal;

    final int count = data.length;
    final itemWidth = size.width / count;
    final barWidth = itemWidth * 0.55;

    // Draw background guide lines
    final linePaint = Paint()
      ..color = textColor.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    for (int i = 0; i < count; i++) {
      final val = data[i];
      final pct = val / limit;
      final barHeight = size.height * pct;
      final x = (i * itemWidth) + (itemWidth - barWidth) / 2;
      final y = size.height - barHeight;

      final isHovered = hoverIndex == i;

      // Draw Bar
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(8),
      );

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            isHovered ? color.withValues(alpha: 0.8) : color,
            color.withValues(alpha: 0.3),
          ],
        ).createShader(Rect.fromLTWH(x, y, barWidth, barHeight));

      canvas.drawRRect(rect, paint);

      // Draw active glow under hovered bar
      if (isHovered) {
        canvas.drawRRect(
          rect,
          Paint()
            ..color = color.withValues(alpha: 0.15)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
      }

      // Draw label
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: GoogleFonts.poppins(
            color: isHovered ? textColor : textColor.withValues(alpha: 0.4),
            fontSize: 10,
            fontWeight: isHovered ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          (i * itemWidth) + (itemWidth - textPainter.width) / 2,
          size.height + 6,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.hoverIndex != hoverIndex ||
      old.isDark != isDark ||
      old.data.length != data.length ||
      old.color != color;
}
