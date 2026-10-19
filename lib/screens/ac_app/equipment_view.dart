import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Equipment View page — mirrors the web's /equipments-view page.
/// Shows all equipment grouped by their system type, with real-time status.
class EquipmentViewPage extends StatefulWidget {
  final void Function(String equipmentId, String name, String systemId,
      String systemShortId)? onEquipmentTap;
  final void Function(int count)? onCountChanged;

  const EquipmentViewPage({super.key, this.onEquipmentTap, this.onCountChanged});

  @override
  State<EquipmentViewPage> createState() => EquipmentViewPageState();
}

class EquipmentViewPageState extends State<EquipmentViewPage> {
  List<Map<String, dynamic>> _allEquipments = [];
  Map<String, List<Map<String, dynamic>>> _groupedBySystem = {};
  Map<String, String> _systemNames = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchEquipments();
  }

  Future<void> _fetchEquipments() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';

      // 1. Fetch all AC equipments
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
      final url =
          '${AppConfig.provisionBaseUrl}/equipments$queryString';

      debugPrint('🌐 [EquipmentView] Fetching equipments: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        debugPrint(
            '⚠️ [EquipmentView] HTTP ${response.statusCode}: ${response.body}');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final body = jsonDecode(response.body);
      if (body['status'] != 1 || body['data'] == null) {
        debugPrint('⚠️ [EquipmentView] No data: status=${body['status']}');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final List<dynamic> rawList = body['data'];
      final allEquips =
          rawList.map((e) => Map<String, dynamic>.from(e)).toList();
      debugPrint(
          '✅ [EquipmentView] Fetched ${allEquips.length} equipments');

      // 2. Fetch systems map (for system names)
      Map<String, String> sysNames = {};
      try {
        final hasCompanyId = companyId.isNotEmpty &&
            companyId != 'null' &&
            companyId != 'undefined';
        final systemsUrl = hasCompanyId
            ? '${AppConfig.provisionBaseUrl}/systems/$companyId?siteId=$siteId'
            : '${AppConfig.provisionBaseUrl}/systems?companyId=$companyId&siteId=$siteId';

        final sysResponse = await http.get(
          Uri.parse(systemsUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Cookie': 'auth_token=$token',
            'Content-Type': 'application/json',
          },
        );

        if (sysResponse.statusCode == 200) {
          final sBody = jsonDecode(sysResponse.body);
          if (sBody['status'] == 1 && sBody['data'] != null) {
            for (var s in sBody['data']) {
              final sId =
                  (s['systemId'] ?? s['SystemId'] ?? s['id'] ?? s['Id'])
                      ?.toString();
              final sName = (s['name'] ??
                      s['Name'] ??
                      s['systemName'] ??
                      s['SystemName']) as String? ??
                  'Unknown System';
              if (sId != null) {
                sysNames[sId] = sName;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ [EquipmentView] Error fetching systems: $e');
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
            final eImei = (e['imei'] ?? e['Imei'] ?? e['deviceId'] ?? e['DeviceId'] ?? '').toString();
            final localImei = (localMap['imei'] ?? localMap['deviceId'] ?? '').toString();
            return (localId.isNotEmpty && eId == localId) ||
                (localImei.isNotEmpty && eImei == localImei);
          });
          if (!exists) {
            allEquips.add(localMap);
            sysNames['local_system'] = 'Local Devices';
            debugPrint('➕ [EquipmentView] Added locally provisioned device to equipment list: ${localMap['name']}');
          }
        }
      } catch (e) {
        debugPrint('⚠️ [EquipmentView] Error loading local provisioned devices: $e');
      }

      // 3. Group equipments by systemId
      final List<Map<String, dynamic>> filteredEquips = [];
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var eq in allEquips) {
        var sysId = (eq['systemId'] ?? eq['SystemId'] ?? '').toString();
        if (sysId.isEmpty || sysId == 'local_system') continue;

        filteredEquips.add(eq);
        grouped.putIfAbsent(sysId, () => []);
        grouped[sysId]!.add(eq);
      }

      if (mounted) {
        widget.onCountChanged?.call(filteredEquips.length);
        setState(() {
          _allEquipments = filteredEquips;
          _groupedBySystem = grouped;
          _systemNames = sysNames;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [EquipmentView] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> refreshData() async {
    await _fetchEquipments();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AppColors.backgroundDark : AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading
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
                    onRefresh: _fetchEquipments,
                    child: _allEquipments.isEmpty
                        ? _buildEmptyState(isDark)
                        : _buildEquipmentGrid(isDark),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Center(
          child: Column(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 56,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.1)),
              const SizedBox(height: 16),
              Text(
                'No Equipment Found',
                style: GoogleFonts.outfit(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pull down to refresh',
                style: GoogleFonts.inter(
                  color: isDark
                      ? Colors.white24
                      : Colors.black26,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEquipmentGrid(bool isDark) {
    final systemIds = _groupedBySystem.keys.toList();
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark ? AppColors.dividerDark : AppColors.divider;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subtitleColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: systemIds.length,
      itemBuilder: (context, sysIndex) {
        final sysId = systemIds[sysIndex];
        final equipments = _groupedBySystem[sysId]!;
        final systemName = _systemNames[sysId] ?? 'AC Monitoring System';

        // Determine system icon based on system name
        IconData systemIcon = Icons.ac_unit_rounded;
        Color systemIconColor = AppColors.primary;
        if (systemName.toLowerCase().contains('light')) {
          systemIcon = Icons.lightbulb_outline_rounded;
          systemIconColor = const Color(0xFFFBBF24);
        } else if (systemName.toLowerCase().contains('energy') ||
            systemName.toLowerCase().contains('ems')) {
          systemIcon = Icons.bolt_rounded;
          systemIconColor = AppColors.coolBlue;
        } else if (systemName.toLowerCase().contains('diesel') ||
            systemName.toLowerCase().contains('dg')) {
          systemIcon = Icons.local_gas_station_rounded;
          systemIconColor = AppColors.heatOrange;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // System Header
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: systemIconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(systemIcon,
                          color: systemIconColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        systemName,
                        style: GoogleFonts.outfit(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Equipments: ${equipments.length}',
                        style: GoogleFonts.inter(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Equipment Cards Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount =
                      constraints.maxWidth > 600 ? 3 : 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: equipments.map((eq) {
                      final name =
                          (eq['name'] ?? eq['Name'] ?? 'Unknown').toString();
                      final imei = (eq['imei'] ??
                                  eq['Imei'] ??
                                  eq['deviceId'] ??
                                  eq['DeviceId'] ??
                                  '')
                              .toString();
                      final equipmentId =
                          (eq['equipmentId'] ?? eq['EquipmentId'] ?? '')
                              .toString();
                      final acType =
                          (eq['acType'] ?? eq['AcType'] ?? '').toString();

                      // Status
                      final statusObj =
                          eq['onOffStatus'] ?? eq['OnOffStatus'];
                      final isOnlineVal = statusObj != null
                          ? (statusObj['isOnline'] ??
                              statusObj['IsOnline'])
                          : null;
                      final bool isOnline = isOnlineVal == true ||
                          isOnlineVal == 1 ||
                          isOnlineVal.toString().toLowerCase() == 'true';
                      final acStatusVal = statusObj != null
                          ? (statusObj['acStatus'] ??
                              statusObj['AcStatus'] ??
                              'OFF')
                          : 'OFF';
                      final bool isRunning = isOnline &&
                          acStatusVal.toString().toUpperCase() == 'ON';

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

                      final cardWidth =
                          (constraints.maxWidth - (crossAxisCount - 1) * 12) /
                              crossAxisCount;

                      return GestureDetector(
                        onTap: () {
                          widget.onEquipmentTap?.call(
                            equipmentId,
                            name,
                            sysId,
                            imei,
                          );
                        },
                        child: Container(
                          width: cardWidth,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border:
                                Border.all(color: borderColor, width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top row: icon + status
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: systemIconColor
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      border: Border.all(
                                        color: systemIconColor
                                            .withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: Icon(systemIcon,
                                        color: systemIconColor, size: 20),
                                  ),
                                  const Spacer(),
                                  // Status dot
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: statusColor
                                              .withValues(alpha: 0.5),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              // Equipment name
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // ID badge
                              if (imei.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.backgroundDark
                                        : Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white
                                              .withValues(alpha: 0.06)
                                          : Colors.black
                                              .withValues(alpha: 0.08),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'IMEI: ',
                                        style: GoogleFonts.inter(
                                          color: subtitleColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Flexible(
                                        child: Text(
                                          imei,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.jetBrainsMono(
                                            color: AppColors.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 8),
                              // Status pill
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor
                                          .withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(6),
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
                                  if (acType.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        acType,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          color: subtitleColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
