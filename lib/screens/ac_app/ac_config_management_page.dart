import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/ac_config_api_service.dart';
import 'package:ir_blaster_ac/core/services/admin_service.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';

class AcConfigManagementPage extends StatefulWidget {
  const AcConfigManagementPage({super.key});

  @override
  State<AcConfigManagementPage> createState() => _AcConfigManagementPageState();
}

class _AcConfigManagementPageState extends State<AcConfigManagementPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MqttService _mqttService = MqttService();
  StreamSubscription<SirisResponse>? _responseSub;

  // Data lists
  List<Map<String, dynamic>> _brands = [];
  List<Map<String, dynamic>> _models = [];
  List<Map<String, dynamic>> _commands = [];
  List<Map<String, dynamic>> _addresses = [];
  List<Map<String, dynamic>> _systems = [];
  List<Map<String, dynamic>> _equipments = [];

  bool _isLoading = true;

  // Brand Form
  final _brandNameCtrl = TextEditingController();
  final _brandDescCtrl = TextEditingController();

  // Model Form
  final _modelNameCtrl = TextEditingController();
  final _modelDescCtrl = TextEditingController();
  int? _selectedBrandForModel;

  // Command Form & Capture State
  String? _selectedPresetName;
  String? _selectedPresetType;
  int? _selectedBrandForCmd;
  int? _selectedModelForCmd;
  String? _selectedSystemForCmd;
  String? _selectedEquipmentForCmd;
  String? _capturedRawData;
  String? _capturedHexCode;
  String? _capturedAddrCode;
  String? _capturedLenVal;
  String _cmdCaptureStatus = 'Select a command preset above to arm receiver & capture IR data';
  bool _cmdIsCapturing = false;
  StateSetter? _activeDialogSetState;
  String? _modalNotificationMessage;
  bool _modalNotificationIsError = false;

  // Mapping Form
  int? _selectedBrandForMap;
  int? _selectedModelForMap;
  String? _selectedSystemForMap;
  String? _selectedEquipmentForMap;

  // Address Form
  final _addressCodeCtrl = TextEditingController();
  final _addressRawCtrl = TextEditingController();
  final _addressHexCtrl = TextEditingController();
  final _addressDescCtrl = TextEditingController();
  int? _selectedBrandForAddr;
  int? _selectedModelForAddr;
  String? _selectedSystemForAddr;
  String? _selectedEquipmentForAddr;

  // Active Capture State
  Map<String, dynamic>? _activeCaptureCommand;
  TextEditingController? _dialogRawCtrl;
  TextEditingController? _dialogHexCtrl;
  TextEditingController? _dialogAddrCtrl;
  String _captureStatusMessage = '';
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadAllData();
    _subscribeToMqtt();
    _ensureMqttConnected();
  }

  Future<void> _ensureMqttConnected() async {
    final devId = _getTargetDeviceId();
    await _mqttService.connect(deviceId: devId);
  }

  @override
  void dispose() {
    _responseSub?.cancel();
    _tabController.dispose();
    _brandNameCtrl.dispose();
    _brandDescCtrl.dispose();
    _modelNameCtrl.dispose();
    _modelDescCtrl.dispose();
    _addressCodeCtrl.dispose();
    _addressRawCtrl.dispose();
    _addressHexCtrl.dispose();
    _addressDescCtrl.dispose();
    _dialogRawCtrl?.dispose();
    _dialogHexCtrl?.dispose();
    _dialogAddrCtrl?.dispose();
    super.dispose();
  }

  String _lastCapturedTimestampStr = '';
  String _lastResponsePayload = '';
  DateTime? _lastResponseTime;

  void _subscribeToMqtt() {
    _responseSub = _mqttService.responseStream.listen((response) {
      if (!mounted) return;
      final rawDet = response.detail ?? response.rawPayload;
      final now = DateTime.now();

      // Suppress duplicate events within 2.0 seconds
      if (_lastResponsePayload == rawDet &&
          _lastResponseTime != null &&
          now.difference(_lastResponseTime!) < const Duration(milliseconds: 2000)) {
        debugPrint('⚠️ [UI] Suppressed duplicate IR response: $rawDet');
        return;
      }
      _lastResponsePayload = rawDet;
      _lastResponseTime = now;

      final formattedTime = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

      if (response.type == SirisResponseType.irLearnSaved) {
        final lenMatch = RegExp(r'LEN=(\d+)', caseSensitive: false).firstMatch(rawDet) ??
                         RegExp(r'LEN=(\d+)', caseSensitive: false).firstMatch(response.rawPayload);
        final lenVal = lenMatch != null ? lenMatch.group(1) : null;

        _showSnack('🎉 IR Captured at $formattedTime! ${lenVal != null ? "(LEN: $lenVal)" : ""}');
        setState(() {
          _capturedLenVal = lenVal;
          _capturedRawData = rawDet;
          _capturedHexCode = lenVal != null
              ? '0x${rawDet.hashCode.toRadixString(16).toUpperCase()} (LEN=$lenVal)'
              : '0x${rawDet.hashCode.toRadixString(16).toUpperCase()}';
          if (lenVal != null && lenVal.isNotEmpty) {
            _capturedAddrCode = 'LEN=$lenVal';
          } else if (_capturedAddrCode == null || _capturedAddrCode!.isEmpty) {
            final brandObj = _brands.firstWhere((b) => _getId(b) == _selectedBrandForCmd, orElse: () => {});
            final brandName = _getBrandName(brandObj);
            _capturedAddrCode = 'ADDR_${_selectedPresetName ?? "CMD"}_${brandName.isNotEmpty ? brandName : "GENERIC"}';
          }
          _cmdCaptureStatus = '✅ Captured IR Signal Received! ${lenVal != null ? "LEN=$lenVal pulses" : ""}';
          _cmdIsCapturing = false;
        });

        if (_activeCaptureCommand != null && _dialogRawCtrl != null) {
          _dialogRawCtrl?.text = rawDet;
          _dialogHexCtrl?.text = '0x${rawDet.hashCode.toRadixString(16).toUpperCase()}';
          _lastCapturedTimestampStr = formattedTime;
          _captureStatusMessage = '✅ Captured IR Data Received at $formattedTime!\nPayload: $rawDet';
          _isCapturing = false;
        }
      } else if (response.type == SirisResponseType.irLearnWaiting) {
        setState(() {
          _cmdCaptureStatus = '📡 Armed & Waiting for Remote Signal...\n$rawDet';
          _cmdIsCapturing = true;
        });
        if (_activeCaptureCommand != null) {
          _captureStatusMessage = '📡 Armed & Waiting for Remote Signal...\n$rawDet';
          _isCapturing = true;
        }
      } else if (response.type == SirisResponseType.irLearnStatus) {
        setState(() {
          _cmdCaptureStatus = '📊 IR Status Received';
        });
        _showIrStatusDialog(rawDet);
      } else if (response.type == SirisResponseType.irLearnStopped) {
        setState(() {
          _cmdCaptureStatus = '⏹️ In-progress capture stopped';
          _cmdIsCapturing = false;
        });
        _showSnack('⏹️ Capture Cancelled');
      } else if (response.type == SirisResponseType.irLearnCleared) {
        setState(() {
          _capturedRawData = null;
          _capturedHexCode = null;
          _capturedLenVal = null;
          _capturedAddrCode = null;
          _cmdCaptureStatus = '🗑️ IR Learned File Cleared ($rawDet)';
          _cmdIsCapturing = false;
        });
        _showClearAllSuccessDialog(rawDet);
      } else if (response.type == SirisResponseType.irLearnError) {
        setState(() {
          _cmdCaptureStatus = '⚠️ IR Learn Error: $rawDet';
          _cmdIsCapturing = false;
        });
        _showSnack('⚠️ IR Learn Error: $rawDet', isError: true);
      }
      _activeDialogSetState?.call(() {});
    });
  }

  List<Map<String, dynamic>> _devices = [];
  String _selectedDeviceId = '';

  String _getPrimaryDeviceId(Map<String, dynamic> d) {
    final imei = (d['imei'] ?? d['Imei'] ?? '').toString().trim();
    if (imei.isNotEmpty) return imei;
    final eqName = (d['equipmentName'] ?? d['EquipmentName'] ?? d['name'] ?? d['Name'] ?? '').toString().trim();
    if (eqName.isNotEmpty && eqName != 'AC Equipment' && eqName != 'System') return eqName;
    final devId = (d['deviceId'] ?? d['equipmentId'] ?? d['id'] ?? d['Id'] ?? '').toString().trim();
    if (devId.isNotEmpty) return devId;
    final shortId = (d['shortId'] ?? d['ShortId'] ?? d['equipmentShortId'] ?? d['systemShortId'] ?? '').toString().trim();
    return shortId;
  }

  Future<void> _loadDevicesAndConnectMqtt() async {
    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final equipments = await AdminService.fetchEquipments(companyId: companyId, siteId: siteId);

      if (mounted && equipments.isNotEmpty) {
        final deviceList = equipments.map((e) => Map<String, dynamic>.from(e)).toList();
        final firstDev = deviceList.first;
        final targetId = _getPrimaryDeviceId(firstDev);

        setState(() {
          _devices = deviceList;
          _selectedDeviceId = targetId;
        });

        if (targetId.isNotEmpty) {
          debugPrint('🌐 [AcConfigManagement] Connecting MQTT to deviceId=$targetId, companyId=$companyId');
          await _mqttService.connect(
            deviceId: targetId,
            companyId: companyId,
            imei: (firstDev['imei'] ?? firstDev['Imei'] ?? targetId).toString(),
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ [AcConfigManagement] Device load error: $e');
    }
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        AcConfigApiService.fetchBrands(),
        AcConfigApiService.fetchModels(),
        AcConfigApiService.fetchCommands(),
        AcConfigApiService.fetchCommandAddresses(),
      ]);

      // Run these in parallel and don't block loading
      _loadDevicesAndConnectMqtt();
      _loadSystemsAndEquipments();

      if (mounted) {
        setState(() {
          _brands = results[0];
          _models = results[1];
          _commands = results[2];
          _addresses = results[3];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ [AcConfigManagement] _loadAllData error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSystemsAndEquipments() async {
    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final zoneId = await AuthService.getZoneId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';
      if (companyId.isEmpty || siteId.isEmpty) return;

      final systemsList = await AdminService.fetchSystems(companyId: companyId, siteId: siteId);
      final equipmentsList = await AdminService.fetchEquipments(companyId: companyId, siteId: siteId);

      // Fetch live AC statuses to populate onOffStatus / isOnline
      try {
        final url = '${AppConfig.provisionBaseUrl}/mqtt/ac/status?companyId=$companyId&siteId=$siteId&zoneId=$zoneId';
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $token',
            'Cookie': 'auth_token=$token',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          final List<dynamic> systemsData = body['systems'] ?? [];
          final Map<String, Map<String, dynamic>> statusByEquipmentId = {};
          for (var sys in systemsData) {
            final List<dynamic> eqs = sys['equipments'] ?? [];
            for (var eq in eqs) {
              final eqId = (eq['equipmentId'] ?? eq['EquipmentId'] ?? '').toString();
              if (eqId.isNotEmpty) {
                statusByEquipmentId[eqId] = Map<String, dynamic>.from(eq);
              }
            }
          }

          for (var eq in equipmentsList) {
            final eqId = (eq['equipmentId'] ?? eq['EquipmentId'] ?? eq['id'] ?? eq['Id'] ?? '').toString();
            final statusData = statusByEquipmentId[eqId];
            if (statusData != null) {
              final status = (statusData['status'] ?? 'DISCONNECTED').toString().toUpperCase();
              final isOnline = status == 'ON' || status == 'OFF' || status == 'ACTIVE' || status == 'ONLINE';
              eq['onOffStatus'] = {
                'isOnline': isOnline,
                'acStatus': status,
                'temperature': statusData['currentTemp'] ?? 0.0,
                'humidity': statusData['hum'] ?? 0.0,
              };
              eq['isOnline'] = isOnline;
              eq['isActive'] = isOnline;
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ [AcConfigManagement] Error fetching live AC status: $e');
      }

      if (mounted) {
        setState(() {
          _systems = systemsList;
          _equipments = equipmentsList;
        });
      }
    } catch (e) {
      debugPrint('⚠️ [AcConfigManagement] Error loading systems/equipments: $e');
    }
  }

  bool _isEquipmentOnline(Map<String, dynamic>? item) {
    if (item == null) return false;

    // 1. Check live telemetry from MqttService stream across all candidate keys
    final primaryId = _getPrimaryDeviceId(item);
    final eqName = (item['equipmentName'] ?? item['EquipmentName'] ?? item['name'] ?? item['Name'] ?? '').toString().trim();
    final imei = (item['imei'] ?? item['Imei'] ?? '').toString().trim();
    final devId = (item['deviceId'] ?? item['equipmentId'] ?? item['id'] ?? item['Id'] ?? '').toString().trim();
    final shortId = (item['shortId'] ?? item['ShortId'] ?? item['equipmentShortId'] ?? '').toString().trim();

    for (final id in [primaryId, imei, eqName, devId, shortId]) {
      if (id.isNotEmpty) {
        final state = _mqttService.getLastStateFor(id);
        if (state != null && state.isActive) {
          return true;
        }
      }
    }

    // 2. Check onOffStatus object from API payload
    final statusObj = item['onOffStatus'] ?? item['OnOffStatus'];
    if (statusObj != null && statusObj is Map) {
      final isOnlineVal = statusObj['isOnline'] ?? statusObj['IsOnline'];
      if (isOnlineVal == true || isOnlineVal == 1 || isOnlineVal.toString().toLowerCase() == 'true') {
        return true;
      }
      final statusStr = (statusObj['status'] ?? statusObj['Status'] ?? statusObj['acStatus'] ?? '').toString().toUpperCase();
      if (statusStr == 'ON' || statusStr == 'OFF' || statusStr == 'ACTIVE' || statusStr == 'ONLINE' || statusStr == 'CONNECTED') {
        return true;
      }
    }

    // 3. Direct status flags
    final isOnlineVal = item['isOnline'] ?? item['IsOnline'] ?? item['isActive'] ?? item['IsActive'];
    if (isOnlineVal == true || isOnlineVal == 1 || isOnlineVal.toString().toLowerCase() == 'true') {
      return true;
    }

    final rootStatus = (item['status'] ?? item['Status'] ?? '').toString().toUpperCase();
    if (rootStatus == 'ON' || rootStatus == 'OFF' || rootStatus == 'ACTIVE' || rootStatus == 'ONLINE' || rootStatus == 'CONNECTED') {
      return true;
    }

    return false;
  }

  int? _getId(Map<String, dynamic>? map) {
    if (map == null) return null;
    final val = map['id'] ?? map['Id'] ?? map['ID'];
    if (val is int) return val;
    if (val != null) return int.tryParse(val.toString());
    return null;
  }

  String _getBrandName(Map<String, dynamic>? map) {
    if (map == null) return '';
    return (map['brand_name'] ?? map['brandName'] ?? map['BrandName'] ?? map['name'] ?? map['Name'] ?? '').toString();
  }

  String _getModelName(Map<String, dynamic>? map) {
    if (map == null) return '';
    return (map['model_name'] ?? map['modelName'] ?? map['ModelName'] ?? map['name'] ?? map['Name'] ?? '').toString();
  }

  String _getCommandName(Map<String, dynamic>? map) {
    if (map == null) return '';
    return (map['command_name'] ?? map['commandName'] ?? map['CommandName'] ?? map['name'] ?? map['Name'] ?? '').toString();
  }

  String _getAddressCode(Map<String, dynamic>? map) {
    if (map == null) return '';
    return (map['address_code'] ?? map['addressCode'] ?? map['AddressCode'] ?? map['code'] ?? map['Code'] ?? '').toString();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    if (_activeDialogSetState != null) {
      _modalNotificationMessage = message;
      _modalNotificationIsError = isError;
      _activeDialogSetState?.call(() {});
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: isError ? AppColors.offline : AppColors.online,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // ── Brand Handlers ──
  Future<void> _addBrand() async {
    final name = _brandNameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('Brand name is required', isError: true);
      return;
    }
    final success = await AcConfigApiService.createBrand(name, _brandDescCtrl.text.trim());
    if (success) {
      _brandNameCtrl.clear();
      _brandDescCtrl.clear();
      _showSnack('AC Brand created successfully');
      _loadAllData();
    } else {
      _showSnack('Failed to create brand', isError: true);
    }
  }

  Future<void> _deleteBrand(int id) async {
    final success = await AcConfigApiService.deleteBrand(id);
    if (success) {
      _showSnack('Brand deleted');
      _loadAllData();
    } else {
      _showSnack('Failed to delete brand', isError: true);
    }
  }

  // ── Model Handlers ──
  Future<void> _addModel() async {
    final name = _modelNameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('Model name is required', isError: true);
      return;
    }

    final createdModel = await AcConfigApiService.createModel(
      name,
      _modelDescCtrl.text.trim(),
      brandId: _selectedBrandForModel,
    );
    if (createdModel != null) {
      _modelNameCtrl.clear();
      _modelDescCtrl.clear();
      _showSnack('AC Model created successfully');
      _loadAllData();
    } else {
      _showSnack('Failed to create model', isError: true);
    }
  }

  Future<void> _deleteModel(int id) async {
    final success = await AcConfigApiService.deleteModel(id);
    if (success) {
      _showSnack('Model deleted');
      _loadAllData();
    } else {
      _showSnack('Failed to delete model', isError: true);
    }
  }

  String _getTargetDeviceId() {
    if (_selectedEquipmentForCmd != null) {
      final eq = _equipments.firstWhere(
        (e) => (e['equipmentId'] ?? e['EquipmentId'] ?? e['id'] ?? e['Id'] ?? '').toString() == _selectedEquipmentForCmd,
        orElse: () => {},
      );
      final devId = (eq['deviceId'] ?? eq['DeviceId'] ?? eq['imei'] ?? eq['Imei'] ?? eq['device_id'] ?? eq['name'] ?? eq['Name'] ?? '').toString();
      if (devId.isNotEmpty) {
        return devId;
      }
    }
    return _mqttService.deviceId.isNotEmpty ? _mqttService.deviceId : '';
  }

  Future<void> _sendDirectIrLearnCommand(String targetDevId, String commandStr) async {
    if (!_mqttService.isConnected) {
      _showSnack('📡 Connecting to MQTT broker...');
      await _mqttService.connect(deviceId: targetDevId);
    }

    _mqttService.setDeviceId(targetDevId);
    await _mqttService.sendControlCommand(commandStr, targetDeviceId: targetDevId);
  }

  void _resetCaptureState() {
    setState(() {
      _capturedRawData = null;
      _capturedHexCode = null;
      _capturedLenVal = null;
      _capturedAddrCode = null;
      _selectedPresetName = null;
      _selectedPresetType = null;
      _cmdIsCapturing = false;
      _cmdCaptureStatus = 'Select a command preset above to arm receiver & capture IR data';
    });
    _showSnack('🔄 Local capture state cleared. Tap a preset button to arm & capture again.');
  }

  void _sendClearIrCommand(String? name) {
    final targetDevId = _getTargetDeviceId();
    String clearCmd = 'CLEAR_ALL';

    if (name != null && name.isNotEmpty) {
      final upper = name.toUpperCase();
      if (upper.contains('POWER_ON') || upper == 'ON') {
        clearCmd = 'CLEAR_ON';
      } else if (upper.contains('POWER_OFF') || upper == 'OFF') {
        clearCmd = 'CLEAR_OFF';
      } else if (upper.contains('DOWN') || upper.contains('TEMP_DOWN')) {
        final match = RegExp(r'(\d+)').firstMatch(upper);
        final temp = match != null ? int.tryParse(match.group(1)!) : 24;
        clearCmd = 'CLEAR_DOWN:${temp ?? 24}';
      } else if (upper.contains('UP') || upper.contains('TEMP_UP') || upper.contains('SET_TEMP')) {
        final match = RegExp(r'(\d+)').firstMatch(upper);
        final temp = match != null ? int.tryParse(match.group(1)!) : 24;
        clearCmd = 'CLEAR_UP:${temp ?? 24}';
      }
    }

    _sendDirectIrLearnCommand(targetDevId, clearCmd);
    _resetCaptureState();
    _showSnack('🧹 Sent $clearCmd command to ${AppConfig.mqttTopic}/$targetDevId/ir_learn');
  }



  Future<void> _sendIrStatusCommand() async {
    final targetDevId = _getTargetDeviceId();
    await _sendDirectIrLearnCommand(targetDevId, 'LEARN_STATUS');
    _showSnack('📊 Published LEARN_STATUS to ${AppConfig.mqttTopic}/$targetDevId/ir_learn');
  }

  Future<void> _sendClearAllCommand() async {
    _showClearAllConfirmDialog();
  }

  void _showIrStatusDialog(String detail) {
    final cardColor = Theme.of(context).cardColor;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final targetDevId = _getTargetDeviceId();

    final upper = detail.toUpperCase();
    bool? onLearned;
    bool? offLearned;
    List<int> missingUp = [];
    List<int> missingDown = [];

    if (upper.contains('ON=YES') || upper.contains('ON=1')) {
      onLearned = true;
    } else if (upper.contains('ON=NO') || upper.contains('ON=0')) {
      onLearned = false;
    }

    if (upper.contains('OFF=YES') || upper.contains('OFF=1')) {
      offLearned = true;
    } else if (upper.contains('OFF=NO') || upper.contains('OFF=0')) {
      offLearned = false;
    }

    final matchUp = RegExp(r'MISSING_UP=([^:]*)', caseSensitive: false).firstMatch(detail);
    if (matchUp != null) {
      final csv = matchUp.group(1) ?? '';
      missingUp = csv.split(',').map((s) => int.tryParse(s.trim())).whereType<int>().toList();
    }

    final matchDown = RegExp(r'MISSING_DOWN=([^:]*)', caseSensitive: false).firstMatch(detail);
    if (matchDown != null) {
      final csv = matchDown.group(1) ?? '';
      missingDown = csv.split(',').map((s) => int.tryParse(s.trim())).whereType<int>().toList();
    }

    final int upLearnedCount = 14 - missingUp.length;
    final int downLearnedCount = 14 - missingDown.length;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surfaceDark : cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.analytics_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'IR Storage Status',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
                    ),
                    Text(
                      'Device: $targetDevId',
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusCardItem(
                  title: 'POWER ON Command',
                  subtitle: onLearned == true ? 'Stored in Device ✅' : (onLearned == false ? 'Not Learnt ❌' : 'Unknown'),
                  isStored: onLearned == true,
                  textColor: textColor,
                ),
                const SizedBox(height: 10),
                _buildStatusCardItem(
                  title: 'POWER OFF Command',
                  subtitle: offLearned == true ? 'Stored in Device ✅' : (offLearned == false ? 'Not Learnt ❌' : 'Unknown'),
                  isStored: offLearned == true,
                  textColor: textColor,
                ),
                const SizedBox(height: 10),
                _buildStatusCardItem(
                  title: 'TEMP UP Steps (16-29°C)',
                  subtitle: '$upLearnedCount / 14 stored\n${missingUp.isNotEmpty ? "Missing: ${missingUp.join(', ')}°C" : "All 14 steps stored ✅"}',
                  isStored: upLearnedCount == 14,
                  textColor: textColor,
                ),
                const SizedBox(height: 10),
                _buildStatusCardItem(
                  title: 'TEMP DOWN Steps (17-30°C)',
                  subtitle: '$downLearnedCount / 14 stored\n${missingDown.isNotEmpty ? "Missing: ${missingDown.join(', ')}°C" : "All 14 steps stored ✅"}',
                  isStored: downLearnedCount == 14,
                  textColor: textColor,
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('OK', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showClearAllConfirmDialog() {
    final targetDevId = _getTargetDeviceId();
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogCtx) {
        final cardColor = Theme.of(context).cardColor;
        final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: isDark ? AppColors.surfaceDark : cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Clear All Learned IR Files?',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
                ),
              ),
            ],
          ),
          content: Text(
            'This action will publish CLEAR_ALL to ${AppConfig.mqttTopic}/$targetDevId/ir_learn and wipe all 30 stored IR files on device (POWER ON, POWER OFF, 14 TEMP UP, and 14 TEMP DOWN files).',
            style: GoogleFonts.inter(fontSize: 13, color: textColor, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                await _sendDirectIrLearnCommand(targetDevId, 'CLEAR_ALL');
                _resetCaptureState();
              },
              icon: const Icon(Icons.delete_forever_rounded, size: 16),
              label: Text('Confirm Clear All', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showClearAllSuccessDialog(String detail) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogCtx) {
        final cardColor = Theme.of(context).cardColor;
        final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: isDark ? AppColors.surfaceDark : cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.online, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'IR Files Cleared',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
                ),
              ),
            ],
          ),
          content: Text(
            '🗑️ Device successfully cleared IR files:\n$detail',
            style: GoogleFonts.inter(fontSize: 13, color: textColor, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('OK', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusCardItem({
    required String title,
    required String subtitle,
    required bool isStored,
    required Color textColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isStored ? AppColors.online.withValues(alpha: 0.12) : AppColors.offline.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isStored ? AppColors.online.withValues(alpha: 0.4) : AppColors.offline.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isStored ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: isStored ? AppColors.online : AppColors.offline,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: textColor),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 11, color: textColor.withValues(alpha: 0.85), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCaptureModalDialog() {
    final cardColor = Theme.of(context).cardColor;
    final borderColor = AppColors.divider.withValues(alpha: 0.4);
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    _modalNotificationMessage = null;
    _modalNotificationIsError = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            _activeDialogSetState = setDialogState;
            final hasCapturedData = _capturedRawData != null && _capturedRawData!.isNotEmpty;
            final targetDevId = _getTargetDeviceId();

            return AlertDialog(
              backgroundColor: isDark ? AppColors.surfaceDark : cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(
                    _cmdIsCapturing ? Icons.radar_rounded : (hasCapturedData ? Icons.check_circle_rounded : Icons.sensors_rounded),
                    color: _cmdIsCapturing ? AppColors.primary : (hasCapturedData ? AppColors.online : Colors.amber),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IR Capture Mode: ${_selectedPresetName ?? "Command"}',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
                        ),
                        Text(
                          'Device: $targetDevId',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_modalNotificationMessage != null && _modalNotificationMessage!.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _modalNotificationIsError
                              ? AppColors.offline.withValues(alpha: 0.18)
                              : AppColors.online.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _modalNotificationIsError ? AppColors.offline : AppColors.online,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_modalNotificationIsError ? AppColors.offline : AppColors.online).withValues(alpha: 0.25),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _modalNotificationIsError ? Icons.error_outline_rounded : Icons.sensors_rounded,
                              color: _modalNotificationIsError ? AppColors.offline : AppColors.online,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _modalNotificationMessage!,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: _modalNotificationIsError ? AppColors.offline : AppColors.online,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (hasCapturedData) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.online.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.online, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.online.withValues(alpha: 0.25),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: AppColors.online,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '🎉 IR Signal Captured Successfully!',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppColors.online,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _capturedLenVal != null
                                        ? 'Pulses Recorded: $_capturedLenVal (LEN=$_capturedLenVal) • Ready to Save'
                                        : 'IR pulse data received from remote • Ready to Save',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 11,
                                      color: textColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _cmdIsCapturing
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : (hasCapturedData ? AppColors.online.withValues(alpha: 0.15) : AppColors.divider.withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _cmdIsCapturing ? AppColors.primary : (hasCapturedData ? AppColors.online : borderColor),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _cmdIsCapturing ? Icons.radar_rounded : Icons.radio_button_checked_rounded,
                            color: _cmdIsCapturing ? AppColors.primary : AppColors.online,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _cmdCaptureStatus,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: _cmdIsCapturing ? AppColors.primary : textColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: hasCapturedData
                            ? AppColors.online.withValues(alpha: 0.08)
                            : cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: hasCapturedData ? AppColors.online : borderColor,
                          width: hasCapturedData ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                hasCapturedData ? Icons.check_circle_rounded : Icons.radar_rounded,
                                color: hasCapturedData ? AppColors.online : AppColors.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Captured Command & LEN Data',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: hasCapturedData ? AppColors.online : textColor,
                                  ),
                                ),
                              ),
                              if (hasCapturedData) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.online.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'READY TO SAVE',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                      color: AppColors.online,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          _buildSummaryDataRow('Command Name:', _selectedPresetName ?? 'None', textColor, isHighlight: true),
                          _buildSummaryDataRow('LEN Value (Address Code):', _capturedAddrCode ?? (_capturedLenVal != null ? 'LEN=$_capturedLenVal' : 'Waiting for remote signal...'), textColor, isHighlight: true),
                          _buildSummaryDataRow('Captured IR Data:', _capturedRawData ?? 'Point remote at receiver & press button...', textColor, isCode: true, isMultiLine: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.all(16),
              actions: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        if (_selectedPresetName != null) {
                          await _armReceiverForSelectedPreset();
                          setDialogState(() {});
                        }
                      },
                      icon: const Icon(Icons.radar_rounded, size: 16),
                      label: Text(_cmdIsCapturing ? 'Armed & Listening...' : 'Start Capture Mode', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        _sendClearIrCommand(_selectedPresetName);
                        setDialogState(() {});
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text('Reset', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orangeAccent,
                        side: const BorderSide(color: Colors.orangeAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogCtx).pop();
                      },
                      child: Text('Close', style: GoogleFonts.inter(color: AppColors.textSecondary)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (!hasCapturedData) {
                          _showSnack('Please capture IR signal before saving', isError: true);
                          return;
                        }
                        Navigator.of(dialogCtx).pop();
                        await _saveCapturedCommandAndAddressToDb();
                      },
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: Text('Save Command & Address', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      _activeDialogSetState = null;
      _modalNotificationMessage = null;
    });
  }

  // ── Command Handlers ──
  Future<void> _armReceiverForSelectedPreset() async {
    if (_selectedPresetName == null || _selectedPresetName!.isEmpty) {
      _showSnack('Please select a Command Preset first', isError: true);
      return;
    }

    final targetDevId = _getTargetDeviceId();
    final brandObj = _brands.firstWhere((b) => _getId(b) == _selectedBrandForCmd, orElse: () => {});
    final brandName = _getBrandName(brandObj);
    final name = _selectedPresetName!;
    final upperName = name.toUpperCase();
    String commandStr = '';

    if (upperName.contains('POWER_ON') || upperName == 'ON') {
      commandStr = 'LEARN_ON';
    } else if (upperName.contains('POWER_OFF') || upperName == 'OFF') {
      commandStr = 'LEARN_OFF';
    } else if (upperName.contains('DOWN') || upperName.contains('TEMP_DOWN')) {
      final match = RegExp(r'(\d+)').firstMatch(upperName);
      final temp = match != null ? int.tryParse(match.group(1)!) : 24;
      commandStr = 'LEARN_DOWN:${temp ?? 24}';
    } else if (upperName.contains('UP') || upperName.contains('TEMP_UP') || upperName.contains('SET_TEMP')) {
      final match = RegExp(r'(\d+)').firstMatch(upperName);
      final temp = match != null ? int.tryParse(match.group(1)!) : 24;
      commandStr = 'LEARN_UP:${temp ?? 24}';
    } else {
      commandStr = 'LEARN_$upperName';
    }

    setState(() {
      _capturedLenVal = null;
      _capturedAddrCode = 'ADDR_${name}_${brandName.isNotEmpty ? brandName : "GENERIC"}';
      _cmdIsCapturing = true;
      _cmdCaptureStatus = '📡 Receiver Armed ($commandStr) for $targetDevId! Point Remote & Press Button...';
    });

    await _sendDirectIrLearnCommand(targetDevId, commandStr);
    _showSnack('📡 Published $commandStr to ${AppConfig.mqttTopic}/$targetDevId/ir_learn');
  }

  void _onPresetChipTap(String name, String type) {
    if (_selectedBrandForCmd == null) {
      _showSnack('Please select AC Brand * first', isError: true);
      return;
    }
    if (_selectedModelForCmd == null) {
      _showSnack('Please select AC Model * first', isError: true);
      return;
    }
    if (_selectedSystemForCmd == null) {
      _showSnack('Please select System * first', isError: true);
      return;
    }
    if (_selectedEquipmentForCmd == null) {
      _showSnack('Please select Equipment * first', isError: true);
      return;
    }

    final targetDevId = _getTargetDeviceId();
    final brandObj = _brands.firstWhere((b) => _getId(b) == _selectedBrandForCmd, orElse: () => {});
    final brandName = _getBrandName(brandObj);

    setState(() {
      _selectedPresetName = name;
      _selectedPresetType = type;
      _capturedLenVal = null;
      _capturedRawData = null;
      _capturedHexCode = null;
      _capturedAddrCode = 'ADDR_${name}_${brandName.isNotEmpty ? brandName : "GENERIC"}';
      _cmdIsCapturing = false;
      _cmdCaptureStatus = 'Preset "$name" selected for $targetDevId. Click "Start Capture Mode" below to arm receiver.';
    });

    // Open Capture Mode Modal Dialog (without auto-publishing LEARN command)
    _showCaptureModalDialog();
  }

  Future<void> _saveCapturedCommandAndAddressToDb() async {
    if (_selectedBrandForCmd == null) {
      _showSnack('Please select AC Brand *', isError: true);
      return;
    }
    if (_selectedModelForCmd == null) {
      _showSnack('Please select AC Model *', isError: true);
      return;
    }
    if (_selectedSystemForCmd == null) {
      _showSnack('Please select System *', isError: true);
      return;
    }
    if (_selectedEquipmentForCmd == null) {
      _showSnack('Please select Equipment *', isError: true);
      return;
    }
    if (_selectedPresetName == null || _selectedPresetName!.isEmpty) {
      _showSnack('Please select a Command Preset above first', isError: true);
      return;
    }

    if (_capturedRawData == null || _capturedRawData!.isEmpty) {
      _showSnack('Please point remote & press button to capture IR data first', isError: true);
      return;
    }

    final addrCode = (_capturedLenVal != null && _capturedLenVal!.isNotEmpty)
        ? 'LEN=$_capturedLenVal'
        : (_capturedAddrCode ?? 'ADDR_${_selectedPresetName}_GENERIC');
    final rawData = _capturedRawData!;
    final hexCode = _capturedHexCode ?? '';

    // Brand Name
    String brandName = '';
    if (_selectedBrandForCmd != null) {
      final brandObj = _brands.firstWhere((b) => _getId(b) == _selectedBrandForCmd, orElse: () => {});
      brandName = _getBrandName(brandObj);
    }

    // Model Name
    String modelName = '';
    if (_selectedModelForCmd != null) {
      final modelObj = _models.firstWhere((m) => _getId(m) == _selectedModelForCmd, orElse: () => {});
      modelName = _getModelName(modelObj);
    }

    // System Name
    String systemName = '';
    if (_selectedSystemForCmd != null) {
      final sys = _systems.firstWhere((s) => (s['systemId'] ?? s['Id'] ?? '').toString() == _selectedSystemForCmd, orElse: () => {});
      systemName = (sys['name'] ?? sys['Name'])?.toString() ?? '';
    }

    // Equipment Name & IMEI / Device ID
    String equipName = '';
    String deviceImei = '';
    if (_selectedEquipmentForCmd != null) {
      final eq = _equipments.firstWhere((e) => (e['equipmentId'] ?? e['EquipmentId'] ?? e['id'] ?? e['Id'] ?? '').toString() == _selectedEquipmentForCmd, orElse: () => {});
      equipName = (eq['name'] ?? eq['Name'] ?? eq['equipmentName'])?.toString() ?? '';
      deviceImei = (eq['deviceId'] ?? eq['DeviceId'] ?? eq['imei'] ?? eq['Imei'] ?? eq['device_id'])?.toString() ?? '';
    }

    final descParts = <String>[];
    descParts.add('Command: $_selectedPresetName');
    if (_capturedLenVal != null && _capturedLenVal!.isNotEmpty) {
      descParts.add('LEN: $_capturedLenVal');
    }
    if (brandName.isNotEmpty) descParts.add('Brand: $brandName');
    if (modelName.isNotEmpty) descParts.add('Model: $modelName');
    if (systemName.isNotEmpty) descParts.add('System: $systemName');
    if (equipName.isNotEmpty) descParts.add('Equip: $equipName');
    if (deviceImei.isNotEmpty) descParts.add('IMEI/Device: $deviceImei');

    final fullDesc = descParts.join(' • ');

    // 1. Save Command Address
    final addrSuccess = await AcConfigApiService.createCommandAddress(
      addressCode: addrCode,
      rawData: rawData,
      hexCode: hexCode,
      description: fullDesc,
      brandId: _selectedBrandForCmd,
      modelId: _selectedModelForCmd,
    );

    // 2. Save AC Command
    final cmdSuccess = await AcConfigApiService.createCommand(
      _selectedPresetName!,
      _selectedPresetType ?? 'GENERAL',
      fullDesc,
      brandId: _selectedBrandForCmd,
      modelId: _selectedModelForCmd,
      addressCode: addrCode,
      rawData: rawData,
      hexCode: hexCode,
    );

    if (addrSuccess || cmdSuccess) {
      _showSnack('🎉 Saved Command "$_selectedPresetName" (LEN=${_capturedLenVal ?? "N/A"}) with Address, Brand, Model & Device ID!');
      setState(() {
        _capturedRawData = null;
        _capturedHexCode = null;
        _capturedAddrCode = null;
        _capturedLenVal = null;
        _selectedPresetName = null;
        _selectedPresetType = null;
        _cmdCaptureStatus = 'Select a command preset above to arm receiver & capture IR data';
        _cmdIsCapturing = false;
      });
      _loadAllData();
    } else {
      _showSnack('Failed to save command and address to database', isError: true);
    }
  }

  Future<void> _deleteCommand(int id) async {
    final success = await AcConfigApiService.deleteCommand(id);
    if (success) {
      _showSnack('Command deleted');
      _loadAllData();
    } else {
      _showSnack('Failed to delete command', isError: true);
    }
  }

  // ── Mapping Handlers ──
  Future<void> _saveEquipmentMapping() async {
    if (_selectedBrandForMap == null) {
      _showSnack('Please select an AC Brand', isError: true);
      return;
    }
    if (_selectedEquipmentForMap == null || _selectedEquipmentForMap!.isEmpty) {
      _showSnack('Please select an Equipment to map', isError: true);
      return;
    }

    // Find the brand name and model name
    final brandObj = _brands.firstWhere(
      (b) => _getId(b) == _selectedBrandForMap,
      orElse: () => {},
    );
    final brandName = _getBrandName(brandObj);

    String modelName = '';
    if (_selectedModelForMap != null) {
      final modelObj = _models.firstWhere(
        (m) => _getId(m) == _selectedModelForMap,
        orElse: () => {},
      );
      modelName = _getModelName(modelObj);
    }

    // Find the equipment
    final equipment = _equipments.firstWhere(
      (e) {
        final eId = (e['equipmentId'] ?? e['EquipmentId'] ?? e['id'] ?? e['Id'] ?? '').toString();
        return eId == _selectedEquipmentForMap;
      },
      orElse: () => {},
    );
    if (equipment.isEmpty) {
      _showSnack('Selected equipment not found', isError: true);
      return;
    }

    // Build update payload - set Brand and AcType on the equipment
    final payload = Map<String, dynamic>.from(equipment);
    payload['brand'] = brandName;
    payload['acType'] = modelName;
    payload['acMonitoring'] = true;

    final result = await AdminService.updateEquipment(
      _selectedEquipmentForMap!,
      payload,
    );

    if (result['status'] == 1) {
      _showSnack('Equipment mapped to $brandName${modelName.isNotEmpty ? " • $modelName" : ""}');
      setState(() {
        _selectedBrandForMap = null;
        _selectedModelForMap = null;
        _selectedSystemForMap = null;
        _selectedEquipmentForMap = null;
      });
      _loadAllData();
    } else {
      _showSnack(result['error'] ?? 'Failed to save mapping', isError: true);
    }
  }

  // ── Address Handlers ──
  Future<void> _addAddress() async {
    final code = _addressCodeCtrl.text.trim();
    if (code.isEmpty) {
      _showSnack('Address code is required', isError: true);
      return;
    }
    String? systemName;
    if (_selectedSystemForAddr != null) {
      final sys = _systems.firstWhere((s) => (s['systemId'] ?? s['Id'] ?? '').toString() == _selectedSystemForAddr, orElse: () => {});
      systemName = (sys['name'] ?? sys['Name'])?.toString();
    }
    String? equipName;
    if (_selectedEquipmentForAddr != null) {
      final eq = _equipments.firstWhere((e) => (e['equipmentId'] ?? e['EquipmentId'] ?? e['id'] ?? e['Id'] ?? '').toString() == _selectedEquipmentForAddr, orElse: () => {});
      equipName = (eq['name'] ?? eq['Name'])?.toString();
    }

    final descParts = <String>[];
    if (systemName != null && systemName.isNotEmpty) descParts.add('System: $systemName');
    if (equipName != null && equipName.isNotEmpty) descParts.add('Equip: $equipName');
    final userDesc = _addressDescCtrl.text.trim();
    if (userDesc.isNotEmpty) descParts.add(userDesc);

    final success = await AcConfigApiService.createCommandAddress(
      addressCode: code,
      rawData: _addressRawCtrl.text.trim(),
      hexCode: _addressHexCtrl.text.trim(),
      description: descParts.isNotEmpty ? descParts.join(' • ') : null,
      brandId: _selectedBrandForAddr,
      modelId: _selectedModelForAddr,
    );
    if (success) {
      _addressCodeCtrl.clear();
      _addressRawCtrl.clear();
      _addressHexCtrl.clear();
      _addressDescCtrl.clear();
      setState(() {
        _selectedBrandForAddr = null;
        _selectedModelForAddr = null;
        _selectedSystemForAddr = null;
        _selectedEquipmentForAddr = null;
      });
      _showSnack('Command Address created successfully');
      _loadAllData();
    } else {
      _showSnack('Failed to create command address', isError: true);
    }
  }

  Future<void> _deleteAddress(int id) async {
    final success = await AcConfigApiService.deleteCommandAddress(id);
    if (success) {
      _showSnack('Address deleted');
      _loadAllData();
    } else {
      _showSnack('Failed to delete address', isError: true);
    }
  }

  // ── IR Capture & Transmit Handlers ──
  void _openCaptureModal(Map<String, dynamic> commandItem) {
    final cmdName = _getCommandName(commandItem);
    final cmdId = _getId(commandItem) ?? 0;
    final bName = _getBrandName(commandItem['brand'] is Map ? commandItem['brand'] : null);
    final mName = _getModelName(commandItem['model'] is Map ? commandItem['model'] : null);

    _activeCaptureCommand = commandItem;
    _dialogRawCtrl = TextEditingController(text: (commandItem['raw_data'] ?? commandItem['rawData'] ?? '').toString());
    _dialogHexCtrl = TextEditingController(text: (commandItem['hex_code'] ?? commandItem['hexCode'] ?? '').toString());
    _dialogAddrCtrl = TextEditingController(
        text: (commandItem['address_code'] ?? commandItem['addressCode'] ?? 'ADDR_${cmdName}_${bName.isNotEmpty ? bName : "GENERIC"}').toString());
    _captureStatusMessage = 'Ready to Capture IR Code';
    _isCapturing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
            final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sensors_rounded, color: AppColors.primary, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Ready to Capture IR: $cmdName',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: textColor),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    if (bName.isNotEmpty || mName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Target: ${bName.isNotEmpty ? bName : ""} ${mName.isNotEmpty ? "• $mName" : ""}',
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.primary),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _isCapturing
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.surfaceDark.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _isCapturing ? AppColors.primary : AppColors.divider.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isCapturing ? Icons.radar_rounded : Icons.radio_button_checked_rounded,
                            color: _isCapturing ? AppColors.primary : AppColors.online,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _captureStatusMessage,
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: _isCapturing ? AppColors.primary : textColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Arm Receiver Commands:', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.primary)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            setModalState(() {
                              _isCapturing = true;
                              _captureStatusMessage = '📡 Armed for POWER ON (LEARN_ON)...';
                            });
                            _mqttService.learnOn();
                            _showSnack('📡 Published LEARN_ON');
                          },
                          icon: const Icon(Icons.power_settings_new_rounded, size: 14),
                          label: Text('LEARN_ON', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            setModalState(() {
                              _isCapturing = true;
                              _captureStatusMessage = '📡 Armed for POWER OFF (LEARN_OFF)...';
                            });
                            _mqttService.learnOff();
                            _showSnack('📡 Published LEARN_OFF');
                          },
                          icon: const Icon(Icons.power_off_rounded, size: 14),
                          label: Text('LEARN_OFF', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            setModalState(() {
                              _isCapturing = true;
                              _captureStatusMessage = '📡 Armed for TEMP UP 20°C (LEARN_UP:20)...';
                            });
                            _mqttService.learnUp(20);
                            _showSnack('📡 Published LEARN_UP:20');
                          },
                          icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                          label: Text('LEARN_UP:20', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            setModalState(() {
                              _isCapturing = true;
                              _captureStatusMessage = '📡 Armed for TEMP DOWN 20°C (LEARN_DOWN:20)...';
                            });
                            _mqttService.learnDown(20);
                            _showSnack('📡 Published LEARN_DOWN:20');
                          },
                          icon: const Icon(Icons.arrow_downward_rounded, size: 14),
                          label: Text('LEARN_DOWN:20', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            setModalState(() {
                              _isCapturing = false;
                              _captureStatusMessage = '⏹️ Sent LEARN_STOP';
                            });
                            _mqttService.learnStop();
                            _showSnack('⏹️ Published LEARN_STOP');
                          },
                          icon: const Icon(Icons.stop_circle_rounded, size: 14),
                          label: Text('LEARN_STOP', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.offline, side: const BorderSide(color: AppColors.offline)),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            _mqttService.getLearnStatus();
                            _showSnack('📊 Published LEARN_STATUS');
                          },
                          icon: const Icon(Icons.info_outline_rounded, size: 14),
                          label: Text('LEARN_STATUS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(_dialogAddrCtrl!, 'Address Code', Icons.alt_route_rounded),
                    const SizedBox(height: 12),
                    _buildTextField(_dialogHexCtrl!, 'Hex Code (e.g. 0x2801)', Icons.code_rounded),
                    const SizedBox(height: 12),
                    _buildTextField(_dialogRawCtrl!, 'Raw IR Data (Captured Pulses)', Icons.data_object_rounded, maxLines: 3),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final raw = _dialogRawCtrl!.text.trim();
                        final hex = _dialogHexCtrl!.text.trim();
                        final addr = _dialogAddrCtrl!.text.trim();

                        if (raw.isEmpty && hex.isEmpty) {
                          _showSnack('Please capture or enter IR raw data / hex code first', isError: true);
                          return;
                        }

                        final type = (commandItem['command_type'] ?? commandItem['commandType'] ?? 'POWER').toString();
                        final desc = (commandItem['description'] ?? '').toString();
                        final bId = _getId(commandItem['brand'] is Map ? commandItem['brand'] : null) ?? commandItem['brand_id'];
                        final mId = _getId(commandItem['model'] is Map ? commandItem['model'] : null) ?? commandItem['model_id'];

                        final success = await AcConfigApiService.updateCommand(
                          cmdId,
                          cmdName,
                          type,
                          desc,
                          brandId: bId is int ? bId : null,
                          modelId: mId is int ? mId : null,
                          addressCode: addr,
                          rawData: raw,
                          hexCode: hex,
                        );

                        if (success) {
                          // Also store in command addresses with linked Brand & Model
                          if (addr.isNotEmpty) {
                            await AcConfigApiService.createCommandAddress(
                              addressCode: addr,
                              rawData: raw,
                              hexCode: hex,
                              description: 'Captured for $cmdName',
                              brandId: bId is int ? bId : null,
                              modelId: mId is int ? mId : null,
                            );
                          }
                          _showSnack('🎉 Captured IR Data Successfully Saved!');
                          Navigator.pop(context);
                          _loadAllData();
                        } else {
                          _showSnack('Failed to save captured IR data', isError: true);
                        }
                      },
                      icon: const Icon(Icons.save_rounded, size: 20),
                      label: Text('Save Stored IR Data', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.online,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _testTransmitIr(Map<String, dynamic> commandItem) {
    final cmdName = _getCommandName(commandItem);
    final devId = _selectedDeviceId.isNotEmpty ? _selectedDeviceId : _mqttService.deviceId;
    if (cmdName.contains('POWER_ON') || cmdName.contains('ON')) {
      _mqttService.turnAcOn(targetDeviceId: devId);
    } else if (cmdName.contains('POWER_OFF') || cmdName.contains('OFF')) {
      _mqttService.turnAcOff(targetDeviceId: devId);
    } else {
      _mqttService.sendControlCommand(cmdName, targetDeviceId: devId);
    }
    _showSnack('📡 Transmitted IR Command: $cmdName');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark ? AppColors.dividerDark : AppColors.divider;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AC Config Management',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAllData,
            tooltip: 'Reload Data',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.branding_watermark_rounded, size: 18), text: 'Brands'),
            Tab(icon: Icon(Icons.devices_rounded, size: 18), text: 'Models'),
            Tab(icon: Icon(Icons.link_rounded, size: 18), text: 'Mappings'),
            Tab(icon: Icon(Icons.bolt_rounded, size: 18), text: 'Commands'),
            Tab(icon: Icon(Icons.alt_route_rounded, size: 18), text: 'Addresses'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildBrandsTab(cardColor, borderColor, textColor, isDark),
                _buildModelsTab(cardColor, borderColor, textColor, isDark),
                _buildMappingsTab(cardColor, borderColor, textColor, isDark),
                _buildCommandsTab(cardColor, borderColor, textColor, isDark),
                _buildAddressesTab(cardColor, borderColor, textColor, isDark),
              ],
            ),
    );
  }

  // ── Tab 1: Brands ──
  Widget _buildBrandsTab(Color cardColor, Color borderColor, Color textColor, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormCard(
            title: 'Add AC Brand',
            icon: Icons.add_circle_outline_rounded,
            cardColor: cardColor,
            borderColor: borderColor,
            textColor: textColor,
            children: [
              _buildTextField(_brandNameCtrl, 'Brand Name (e.g., Daikin, LG, Carrier)', Icons.branding_watermark_rounded),
              const SizedBox(height: 12),
              _buildTextField(_brandDescCtrl, 'Description (optional)', Icons.description_rounded),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _addBrand,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text('Save Brand', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Existing AC Brands (${_brands.length})', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
          const SizedBox(height: 12),
          _brands.isEmpty
              ? _buildEmptyState('No AC Brands added yet')
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _brands.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = _brands[i];
                    final brandId = _getId(item) ?? 0;
                    final desc = (item['description'] ?? item['Description'])?.toString();
                    return _buildListTile(
                      title: _getBrandName(item),
                      subtitle: desc,
                      id: brandId,
                      onDelete: () => _deleteBrand(brandId),
                      cardColor: cardColor,
                      borderColor: borderColor,
                      textColor: textColor,
                    );
                  },
                ),
        ],
      ),
    );
  }

  // ── Tab 2: Models ──
  Widget _buildModelsTab(Color cardColor, Color borderColor, Color textColor, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormCard(
            title: 'Add AC Model',
            icon: Icons.add_circle_outline_rounded,
            cardColor: cardColor,
            borderColor: borderColor,
            textColor: textColor,
            children: [
              _buildDropdown(
                label: 'Select AC Brand (optional)',
                value: _selectedBrandForModel,
                items: _brands,
                nameKey: 'brand_name',
                onChanged: (val) => setState(() => _selectedBrandForModel = val),
              ),
              const SizedBox(height: 12),
              _buildTextField(_modelNameCtrl, 'Model Name (e.g., FTKF50TV, splitac3)', Icons.devices_rounded),
              const SizedBox(height: 12),
              _buildTextField(_modelDescCtrl, 'Description (optional)', Icons.description_rounded),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _addModel,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text('Save Model', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Existing AC Models (${_models.length})', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
          const SizedBox(height: 12),
          _models.isEmpty
              ? _buildEmptyState('No AC Models added yet')
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _models.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = _models[i];
                    final modelId = _getId(item) ?? 0;
                    final desc = (item['description'] ?? item['Description'])?.toString();

                    String? brandName;
                    final brandObj = item['brand'] ?? item['Brand'];
                    if (brandObj is Map<String, dynamic>) {
                      brandName = _getBrandName(brandObj);
                    }
                    if (brandName == null || brandName.isEmpty) {
                      final bId = item['brand_id'] ?? item['brandId'] ?? item['BrandId'];
                      if (bId != null) {
                        final found = _brands.firstWhere((b) => _getId(b) == bId, orElse: () => {});
                        brandName = _getBrandName(found);
                      }
                    }

                    final subtitleParts = <String>[];
                    if (brandName != null && brandName.isNotEmpty) {
                      subtitleParts.add('Brand: $brandName');
                    }
                    if (desc != null && desc.isNotEmpty) {
                      subtitleParts.add(desc);
                    }
                    final subtitleText = subtitleParts.join(' • ');

                    return _buildListTile(
                      title: _getModelName(item),
                      subtitle: subtitleText.isNotEmpty ? subtitleText : null,
                      id: modelId,
                      onDelete: () => _deleteModel(modelId),
                      cardColor: cardColor,
                      borderColor: borderColor,
                      textColor: textColor,
                    );
                  },
                ),
        ],
      ),
    );
  }

  // ── Tab 3: Commands ──
  Widget _buildCommandsTab(Color cardColor, Color borderColor, Color textColor, bool isDark) {
    final availableModels = _selectedBrandForCmd == null
        ? _models
        : _models.where((m) {
            final bId = m['brand_id'] ?? m['brandId'] ?? m['BrandId'];
            final bObj = m['brand'] ?? m['Brand'];
            final objId = bObj is Map<String, dynamic> ? _getId(bObj) : null;
            return bId == _selectedBrandForCmd || objId == _selectedBrandForCmd;
          }).toList();

    final availableEquipmentsForCmd = _selectedSystemForCmd == null
        ? _equipments
        : _equipments.where((e) {
            final sysId = (e['systemId'] ?? e['SystemId'] ?? '').toString();
            return sysId == _selectedSystemForCmd;
          }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormCard(
            title: 'Capture IR Signal for Command',
            icon: Icons.sensors_rounded,
            cardColor: cardColor,
            borderColor: borderColor,
            textColor: textColor,
            children: [
              _buildDropdown(
                label: 'Select AC Brand *',
                value: _selectedBrandForCmd,
                items: _brands,
                nameKey: 'brand_name',
                onChanged: (val) => setState(() {
                  _selectedBrandForCmd = val;
                  _selectedModelForCmd = null;
                }),
              ),
              const SizedBox(height: 12),
              _buildDropdown(
                label: 'Select AC Model *',
                value: _selectedModelForCmd,
                items: availableModels,
                nameKey: 'model_name',
                onChanged: (val) => setState(() => _selectedModelForCmd = val),
              ),
              const SizedBox(height: 12),
              _buildStringDropdown(
                label: 'Select System *',
                value: _selectedSystemForCmd,
                items: _systems,
                idKey: 'systemId',
                nameKey: 'name',
                onChanged: (val) => setState(() {
                  _selectedSystemForCmd = val;
                  _selectedEquipmentForCmd = null;
                }),
              ),
              const SizedBox(height: 12),
              _buildEquipmentDropdown(
                label: 'Select Equipment *',
                value: _selectedEquipmentForCmd,
                items: availableEquipmentsForCmd,
                onChanged: (val) => setState(() => _selectedEquipmentForCmd = val),
              ),
              const SizedBox(height: 16),
              Text(
                'Tap Preset Button to Arm Receiver & Capture IR',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.primary),
              ),
              const SizedBox(height: 10),
              Text(
                'Power & Mode Commands',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildPresetChip('POWER_ON', 'POWER', Colors.green),
                  _buildPresetChip('POWER_OFF', 'POWER', Colors.red),
                  _buildPresetChip('MODE_COOL', 'MODE', Colors.blue),
                  _buildPresetChip('MODE_HEAT', 'MODE', Colors.orange),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.teal),
                  const SizedBox(width: 4),
                  Text(
                    'TEMP UP Step Commands (16–29°C)',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.teal),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(14, (index) {
                  final temp = 16 + index; // 16 to 29
                  return _buildPresetChip('TEMP_UP_$temp', 'TEMP_UP', Colors.teal);
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.indigoAccent),
                  const SizedBox(width: 4),
                  Text(
                    'TEMP DOWN Step Commands (17–30°C)',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.indigoAccent),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(14, (index) {
                  final temp = 17 + index; // 17 to 30
                  return _buildPresetChip('TEMP_DOWN_$temp', 'TEMP_DOWN', Colors.indigoAccent);
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _sendIrStatusCommand,
                      icon: const Icon(Icons.info_outline_rounded, size: 16),
                      label: Text('IR STATUS', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _sendClearAllCommand,
                      icon: const Icon(Icons.delete_forever_rounded, size: 16),
                      label: Text('IR CLEAR ALL', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _cmdIsCapturing
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.surfaceDark.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _cmdIsCapturing ? AppColors.primary : AppColors.divider.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _cmdIsCapturing ? Icons.radar_rounded : Icons.radio_button_checked_rounded,
                      color: _cmdIsCapturing ? AppColors.primary : AppColors.online,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _cmdCaptureStatus,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: _cmdIsCapturing ? AppColors.primary : textColor,
                        ),
                      ),
                    ),
                    if (_selectedPresetName != null && !_cmdIsCapturing && _capturedRawData == null)
                      TextButton.icon(
                        onPressed: _armReceiverForSelectedPreset,
                        icon: const Icon(Icons.radar_rounded, size: 16),
                        label: Text('Start Capture', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    if (_cmdIsCapturing || _capturedRawData != null)
                      TextButton.icon(
                        onPressed: () => _sendClearIrCommand(_selectedPresetName),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text('Reset', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.orangeAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Saved Command Addresses (${_addresses.length})',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
          ),
          const SizedBox(height: 12),
          _addresses.isEmpty
              ? _buildEmptyState('No Command Addresses saved yet')
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _addresses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final item = _addresses[i];
                    return _buildAddressCardBox(item, cardColor, borderColor, textColor, isDark);
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildCapturedSummaryBox(Color cardColor, Color borderColor, Color textColor, bool isDark) {
    final hasCapturedData = _capturedRawData != null && _capturedRawData!.isNotEmpty;

    // Brand Name
    String brandName = 'Not Selected';
    if (_selectedBrandForCmd != null) {
      final brandObj = _brands.firstWhere((b) => _getId(b) == _selectedBrandForCmd, orElse: () => {});
      final bName = _getBrandName(brandObj);
      if (bName.isNotEmpty) brandName = bName;
    }

    // Model Name
    String modelName = 'Not Selected';
    if (_selectedModelForCmd != null) {
      final modelObj = _models.firstWhere((m) => _getId(m) == _selectedModelForCmd, orElse: () => {});
      final mName = _getModelName(modelObj);
      if (mName.isNotEmpty) modelName = mName;
    }

    // System Name
    String systemName = 'Not Selected';
    if (_selectedSystemForCmd != null) {
      final sys = _systems.firstWhere((s) => (s['systemId'] ?? s['Id'] ?? '').toString() == _selectedSystemForCmd, orElse: () => {});
      final sName = (sys['name'] ?? sys['Name'])?.toString();
      if (sName != null && sName.isNotEmpty) systemName = sName;
    }

    // Equipment Name & IMEI / Device ID
    String equipName = 'Not Selected';
    String deviceImei = '';
    if (_selectedEquipmentForCmd != null) {
      final eq = _equipments.firstWhere((e) => (e['equipmentId'] ?? e['EquipmentId'] ?? e['id'] ?? e['Id'] ?? '').toString() == _selectedEquipmentForCmd, orElse: () => {});
      final eName = (eq['name'] ?? eq['Name'] ?? eq['equipmentName'])?.toString();
      if (eName != null && eName.isNotEmpty) equipName = eName;
      final dImei = (eq['deviceId'] ?? eq['DeviceId'] ?? eq['imei'] ?? eq['Imei'] ?? eq['device_id'])?.toString();
      if (dImei != null && dImei.isNotEmpty) deviceImei = dImei;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasCapturedData
            ? AppColors.online.withValues(alpha: 0.08)
            : cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasCapturedData ? AppColors.online.withValues(alpha: 0.5) : borderColor,
          width: hasCapturedData ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasCapturedData ? Icons.check_circle_rounded : Icons.sensors_rounded,
                color: hasCapturedData ? AppColors.online : AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasCapturedData ? 'Captured IR Signal & Command Data' : 'Live Capture & Command Info',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: hasCapturedData ? AppColors.online : textColor,
                  ),
                ),
              ),
              if (hasCapturedData) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.online.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'READY TO SAVE',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      color: AppColors.online,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _buildSummaryDataRow('Command:', _selectedPresetName ?? 'None selected (Tap preset above)', textColor, isHighlight: _selectedPresetName != null),
          _buildSummaryDataRow('Address Code:', _capturedAddrCode ?? 'Auto-generated on selection', textColor),
          _buildSummaryDataRow('IR Pulse Length (LEN):', _capturedLenVal != null ? '${_capturedLenVal!} pulses (LEN=${_capturedLenVal!})' : 'Waiting for remote signal...', textColor, isHighlight: _capturedLenVal != null),
          _buildSummaryDataRow('AC Brand:', brandName, textColor),
          _buildSummaryDataRow('AC Model:', modelName, textColor),
          _buildSummaryDataRow('System:', systemName, textColor),
          _buildSummaryDataRow('Equipment (IMEI):', '$equipName${deviceImei.isNotEmpty ? " (IMEI: $deviceImei)" : ""}', textColor),
          _buildSummaryDataRow('Hex Code:', _capturedHexCode ?? 'Waiting for remote signal...', textColor, isCode: true),
          _buildSummaryDataRow('Raw IR Pulses:', _capturedRawData ?? 'Press remote button to capture pulse data...', textColor, isCode: true, isMultiLine: true),
        ],
      ),
    );
  }

  Widget _buildAddressCardBox(Map<String, dynamic> item, Color cardColor, Color borderColor, Color textColor, bool isDark) {
    final addressId = _getId(item) ?? 0;
    final addrCode = _getAddressCode(item);
    final hexCode = (item['hex_code'] ?? item['hexCode'] ?? item['HexCode'] ?? '').toString();
    final desc = (item['description'] ?? item['Description'] ?? '').toString();
    final lenMatch = RegExp(r'LEN:?\s*(\d+)|LEN(\d+)', caseSensitive: false).firstMatch(desc) ??
                     RegExp(r'LEN:?\s*(\d+)|LEN(\d+)', caseSensitive: false).firstMatch(addrCode);
    final cardLen = lenMatch != null ? (lenMatch.group(1) ?? lenMatch.group(2)) : null;

    String brandName = '';
    final brandObj = item['brand'] ?? item['Brand'];
    if (brandObj is Map<String, dynamic>) {
      brandName = _getBrandName(brandObj);
    }
    if (brandName.isEmpty) {
      final bId = item['brand_id'] ?? item['brandId'] ?? item['BrandId'];
      if (bId != null) {
        final found = _brands.firstWhere((b) => _getId(b) == bId, orElse: () => {});
        brandName = _getBrandName(found);
      }
    }

    String modelName = '';
    final modelObj = item['model'] ?? item['Model'];
    if (modelObj is Map<String, dynamic>) {
      modelName = _getModelName(modelObj);
    }
    if (modelName.isEmpty) {
      final mId = item['model_id'] ?? item['modelId'] ?? item['ModelId'];
      if (mId != null) {
        final found = _models.firstWhere((m) => _getId(m) == mId, orElse: () => {});
        modelName = _getModelName(found);
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alt_route_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'Address Code: ',
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.online.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.online.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        addrCode.isNotEmpty ? addrCode : (cardLen != null ? 'LEN=$cardLen' : 'N/A'),
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.online),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                onPressed: () => _deleteAddress(addressId),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (brandName.isNotEmpty) _buildBadgeChip('Brand', brandName, Colors.blue),
              if (modelName.isNotEmpty) _buildBadgeChip('Model', modelName, Colors.orange),
              if (cardLen != null && cardLen.isNotEmpty) _buildBadgeChip('LEN', '$cardLen pulses', Colors.indigo),
              if (desc.isNotEmpty) _buildBadgeChip('Details', desc, Colors.teal),
              if (hexCode.isNotEmpty) _buildBadgeChip('Hex', hexCode, Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
          Text(value, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _buildSummaryDataRow(String label, String value, Color textColor, {bool isHighlight = false, bool isCode = false, bool isMultiLine = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: isMultiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
                color: isHighlight ? AppColors.primary : textColor,
              ),
              maxLines: isMultiLine ? 3 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 3: Mappings ──
  Widget _buildMappingsTab(Color cardColor, Color borderColor, Color textColor, bool isDark) {
    final availableModels = _selectedBrandForMap == null
        ? _models
        : _models.where((m) {
            final bId = m['brand_id'] ?? m['brandId'] ?? m['BrandId'];
            final bObj = m['brand'] ?? m['Brand'];
            final objId = bObj is Map<String, dynamic> ? _getId(bObj) : null;
            return bId == _selectedBrandForMap || objId == _selectedBrandForMap;
          }).toList();

    // Filter equipments by selected system
    final availableEquipments = _selectedSystemForMap == null
        ? _equipments
        : _equipments.where((e) {
            final sysId = (e['systemId'] ?? e['SystemId'] ?? '').toString();
            return sysId == _selectedSystemForMap;
          }).toList();

    // Find equipments that already have a brand/acType mapped
    final mappedEquipments = _equipments.where((e) {
      final brand = (e['brand'] ?? e['Brand'] ?? '').toString().trim();
      return brand.isNotEmpty;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormCard(
            title: 'Map Equipment to AC Brand & Model',
            icon: Icons.link_rounded,
            cardColor: cardColor,
            borderColor: borderColor,
            textColor: textColor,
            children: [
              _buildDropdown(
                label: 'Select AC Brand',
                value: _selectedBrandForMap,
                items: _brands,
                nameKey: 'brand_name',
                onChanged: (val) => setState(() {
                  _selectedBrandForMap = val;
                  _selectedModelForMap = null;
                }),
              ),
              const SizedBox(height: 12),
              _buildDropdown(
                label: 'Select AC Model',
                value: _selectedModelForMap,
                items: availableModels,
                nameKey: 'model_name',
                onChanged: (val) => setState(() => _selectedModelForMap = val),
              ),
              const SizedBox(height: 12),
              _buildStringDropdown(
                label: 'Select System',
                value: _selectedSystemForMap,
                items: _systems,
                idKey: 'systemId',
                nameKey: 'name',
                onChanged: (val) => setState(() {
                  _selectedSystemForMap = val;
                  _selectedEquipmentForMap = null;
                }),
              ),
              const SizedBox(height: 12),
              _buildEquipmentDropdown(
                label: 'Select Equipment',
                value: _selectedEquipmentForMap,
                items: availableEquipments,
                onChanged: (val) => setState(() => _selectedEquipmentForMap = val),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _saveEquipmentMapping,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text('Save Mapping', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Mapped Equipment (${mappedEquipments.length})', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
          const SizedBox(height: 12),
          mappedEquipments.isEmpty
              ? _buildEmptyState('No Equipment Mappings configured yet')
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: mappedEquipments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final eq = mappedEquipments[i];
                    final eqName = (eq['name'] ?? eq['Name'] ?? eq['equipmentName'] ?? 'Equipment').toString();
                    final eqBrand = (eq['brand'] ?? eq['Brand'] ?? '').toString();
                    final eqModel = (eq['acType'] ?? eq['AcType'] ?? '').toString();
                    final eqImei = (eq['imei'] ?? eq['Imei'] ?? '').toString();
                    final shortId = (eq['shortId'] ?? eq['ShortId'] ?? '').toString();
                    final isActive = _isEquipmentOnline(eq);

                    return Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive ? AppColors.online : AppColors.offline,
                          ),
                        ),
                        title: Text(
                          eqName,
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: textColor),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Brand: $eqBrand${eqModel.isNotEmpty ? " • Model: $eqModel" : ""}',
                              style: GoogleFonts.inter(fontSize: 12, color: AppColors.primary),
                            ),
                            if (eqImei.isNotEmpty || shortId.isNotEmpty)
                              Text(
                                '${eqImei.isNotEmpty ? "IMEI: $eqImei" : ""}${shortId.isNotEmpty ? " • ID: $shortId" : ""}',
                                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
                              ),
                          ],
                        ),
                        isThreeLine: eqImei.isNotEmpty || shortId.isNotEmpty,
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  // ── Tab 5: Addresses ──
  Widget _buildAddressesTab(Color cardColor, Color borderColor, Color textColor, bool isDark) {
    final availableModels = _selectedBrandForAddr == null
        ? _models
        : _models.where((m) {
            final bId = m['brand_id'] ?? m['brandId'] ?? m['BrandId'];
            final bObj = m['brand'] ?? m['Brand'];
            final objId = bObj is Map<String, dynamic> ? _getId(bObj) : null;
            return bId == _selectedBrandForAddr || objId == _selectedBrandForAddr;
          }).toList();

    final availableEquipmentsForAddr = _selectedSystemForAddr == null
        ? _equipments
        : _equipments.where((e) {
            final sysId = (e['systemId'] ?? e['SystemId'] ?? '').toString();
            return sysId == _selectedSystemForAddr;
          }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormCard(
            title: 'Add Command Address',
            icon: Icons.add_circle_outline_rounded,
            cardColor: cardColor,
            borderColor: borderColor,
            textColor: textColor,
            children: [
              _buildDropdown(
                label: 'Link to AC Brand (optional)',
                value: _selectedBrandForAddr,
                items: _brands,
                nameKey: 'brand_name',
                onChanged: (val) => setState(() {
                  _selectedBrandForAddr = val;
                  _selectedModelForAddr = null;
                }),
              ),
              const SizedBox(height: 12),
              _buildDropdown(
                label: 'Link to AC Model (optional)',
                value: _selectedModelForAddr,
                items: availableModels,
                nameKey: 'model_name',
                onChanged: (val) => setState(() => _selectedModelForAddr = val),
              ),
              const SizedBox(height: 12),
              _buildStringDropdown(
                label: 'Select System (optional)',
                value: _selectedSystemForAddr,
                items: _systems,
                idKey: 'systemId',
                nameKey: 'name',
                onChanged: (val) => setState(() {
                  _selectedSystemForAddr = val;
                  _selectedEquipmentForAddr = null;
                }),
              ),
              const SizedBox(height: 12),
              _buildEquipmentDropdown(
                label: 'Select Equipment (optional)',
                value: _selectedEquipmentForAddr,
                items: availableEquipmentsForAddr,
                onChanged: (val) => setState(() => _selectedEquipmentForAddr = val),
              ),
              const SizedBox(height: 12),
              _buildTextField(_addressCodeCtrl, 'Address Code (e.g., ADDR_01)', Icons.alt_route_rounded),
              const SizedBox(height: 12),
              _buildTextField(_addressHexCtrl, 'Hex Code (e.g., 0x2801)', Icons.code_rounded),
              const SizedBox(height: 12),
              _buildTextField(_addressRawCtrl, 'Raw IR Data (e.g., 9000,4500,560...)', Icons.data_object_rounded, maxLines: 2),
              const SizedBox(height: 12),
              _buildTextField(_addressDescCtrl, 'Description (optional)', Icons.description_rounded),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _addAddress,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text('Save Address', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Existing Addresses (${_addresses.length})', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
          const SizedBox(height: 12),
          _addresses.isEmpty
              ? _buildEmptyState('No Command Addresses added yet')
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _addresses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = _addresses[i];
                    final addressId = _getId(item) ?? 0;
                    final hex = item['hex_code'] ?? item['hexCode'] ?? item['HexCode'];
                    final desc = (item['description'] ?? item['Description'])?.toString();

                    String? brandName;
                    final brandObj = item['brand'] ?? item['Brand'];
                    if (brandObj is Map<String, dynamic>) {
                      brandName = _getBrandName(brandObj);
                    }
                    if (brandName == null || brandName.isEmpty) {
                      final bId = item['brand_id'] ?? item['brandId'] ?? item['BrandId'];
                      if (bId != null) {
                        final found = _brands.firstWhere((b) => _getId(b) == bId, orElse: () => {});
                        brandName = _getBrandName(found);
                      }
                    }

                    String? modelName;
                    final modelObj = item['model'] ?? item['Model'];
                    if (modelObj is Map<String, dynamic>) {
                      modelName = _getModelName(modelObj);
                    }
                    if (modelName == null || modelName.isEmpty) {
                      final mId = item['model_id'] ?? item['modelId'] ?? item['ModelId'];
                      if (mId != null) {
                        final found = _models.firstWhere((m) => _getId(m) == mId, orElse: () => {});
                        modelName = _getModelName(found);
                      }
                    }

                    final subParts = <String>[];
                    if (hex != null && hex.toString().isNotEmpty) subParts.add('Hex: $hex');
                    if (brandName != null && brandName.isNotEmpty) subParts.add('Brand: $brandName');
                    if (modelName != null && modelName.isNotEmpty) subParts.add('Model: $modelName');
                    if (desc != null && desc.isNotEmpty) subParts.add(desc);

                    return _buildListTile(
                      title: _getAddressCode(item),
                      subtitle: subParts.isNotEmpty ? subParts.join(' • ') : null,
                      id: addressId,
                      onDelete: () => _deleteAddress(addressId),
                      cardColor: cardColor,
                      borderColor: borderColor,
                      textColor: textColor,
                    );
                  },
                ),
        ],
      ),
    );
  }

  // ── Custom Command Box Widget (Renders Stored Data & Capture Actions) ──
  Widget _buildCommandCardBox({
    required Map<String, dynamic> item,
    required int id,
    required Color cardColor,
    required Color borderColor,
    required Color textColor,
  }) {
    final cmdName = _getCommandName(item);
    final type = item['command_type'] ?? item['commandType'] ?? item['CommandType'];

    String? brandName;
    final brandObj = item['brand'] ?? item['Brand'];
    if (brandObj is Map<String, dynamic>) {
      brandName = _getBrandName(brandObj);
    }
    if (brandName == null || brandName.isEmpty) {
      final bId = item['brand_id'] ?? item['brandId'] ?? item['BrandId'];
      if (bId != null) {
        final found = _brands.firstWhere((b) => _getId(b) == bId, orElse: () => {});
        brandName = _getBrandName(found);
      }
    }

    String? modelName;
    final modelObj = item['model'] ?? item['Model'];
    if (modelObj is Map<String, dynamic>) {
      modelName = _getModelName(modelObj);
    }
    if (modelName == null || modelName.isEmpty) {
      final mId = item['model_id'] ?? item['modelId'] ?? item['ModelId'];
      if (mId != null) {
        final found = _models.firstWhere((m) => _getId(m) == mId, orElse: () => {});
        modelName = _getModelName(found);
      }
    }

    final rawData = (item['raw_data'] ?? item['rawData'] ?? '').toString();
    final hexCode = (item['hex_code'] ?? item['hexCode'] ?? '').toString();
    final addrCode = (item['address_code'] ?? item['addressCode'] ?? '').toString();
    final createdAtRaw = (item['updated_at'] ?? item['updatedAt'] ?? item['created_at'] ?? item['createdAt'] ?? item['stime'] ?? '').toString();
    final isCaptured = rawData.isNotEmpty || hexCode.isNotEmpty || addrCode.isNotEmpty;
    final pulseCount = rawData.isNotEmpty
        ? rawData.split(RegExp(r'[,;\s]+')).where((s) => s.trim().isNotEmpty).length
        : 0;

    String stimeDisplay = '';
    if (createdAtRaw.isNotEmpty) {
      final parsed = DateTime.tryParse(createdAtRaw);
      if (parsed != null) {
        final local = parsed.toLocal();
        stimeDisplay = "${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}";
      } else {
        stimeDisplay = createdAtRaw;
      }
    }

    final subtitleParts = <String>[];
    if (type != null && type.toString().isNotEmpty) subtitleParts.add('Type: $type');
    if (brandName != null && brandName.isNotEmpty) subtitleParts.add('Brand: $brandName');
    if (modelName != null && modelName.isNotEmpty) subtitleParts.add('Model: $modelName');
    final desc = (item['description'] ?? item['Description'])?.toString();
    if (desc != null && desc.isNotEmpty && desc != 'Preset: $cmdName') subtitleParts.add(desc);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isCaptured ? AppColors.online.withValues(alpha: 0.5) : borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cmdName,
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isCaptured ? AppColors.online.withValues(alpha: 0.15) : AppColors.divider.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCaptured ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 12,
                      color: isCaptured ? AppColors.online : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isCaptured ? 'Captured' : 'Pending Capture',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isCaptured ? AppColors.online : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.offline, size: 20),
                onPressed: () => _deleteCommand(id),
              ),
            ],
          ),
          if (subtitleParts.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitleParts.join(' • '),
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 10),
          // ── Stored IR Data Box ──
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_rounded, size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Stored IR Signal Data',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (stimeDisplay.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('Captured Time (stime): $stimeDisplay', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                if (addrCode.isNotEmpty)
                  Text('Address Code: $addrCode', style: GoogleFonts.inter(fontSize: 11, color: textColor)),
                if (hexCode.isNotEmpty)
                  Text('Hex Code: $hexCode', style: GoogleFonts.inter(fontSize: 11, color: textColor)),
                if (pulseCount > 0)
                  Text('Captured Pulses: $pulseCount pulses',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.online)),
                if (rawData.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.online.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      rawData,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaCode(fontSize: 10, color: AppColors.online, height: 1.3),
                    ),
                  ),
                ],
                if (!isCaptured)
                  Text(
                    'No IR signal captured yet. Click "Ready to Capture" below.',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openCaptureModal(item),
                  icon: const Icon(Icons.sensors_rounded, size: 16),
                  label: Text('Ready to Capture', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _testTransmitIr(item),
                icon: const Icon(Icons.send_rounded, size: 16),
                label: Text('Test IR', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.online,
                  side: const BorderSide(color: AppColors.online),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── UI Helper Widgets ──
  Widget _buildPresetChip(String name, String type, Color color) {
    final isSelected = _selectedPresetName == name;

    String displayLabel = name;
    if (name.startsWith('TEMP_UP_')) {
      displayLabel = '▲ ${name.substring(8)}';
    } else if (name.startsWith('TEMP_DOWN_')) {
      displayLabel = '▼ ${name.substring(10)}';
    } else if (name.startsWith('SET_TEMP_')) {
      displayLabel = '▲ ${name.substring(9)}';
    } else {
      displayLabel = name
          .replaceFirst('POWER_', '')
          .replaceFirst('MODE_', '');
    }

    return FilterChip(
      label: Text(
        displayLabel,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : color),
      ),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: isSelected ? color : color.withValues(alpha: 0.5)),
      onSelected: (selected) {
        if (selected) {
          _onPresetChipTap(name, type);
        } else {
          setState(() {
            _selectedPresetName = null;
            _selectedPresetType = null;
          });
        }
      },
    );
  }

  Widget _buildFormCard({
    required String title,
    required IconData icon,
    required Color cardColor,
    required Color borderColor,
    required Color textColor,
    required List<Widget> children,
  }) {
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
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: GoogleFonts.inter(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required int? value,
    required List<Map<String, dynamic>> items,
    required String nameKey,
    required ValueChanged<int?> onChanged,
  }) {
    final validValues = items.map((item) => _getId(item)).where((id) => id != null).toSet();
    final currentValue = (value != null && validValues.contains(value)) ? value : null;

    return DropdownButtonFormField<int>(
      initialValue: currentValue,
      items: items.map((item) {
        final id = _getId(item);
        if (id == null) return null;
        final rawVal = item[nameKey];
        final name = (rawVal != null && rawVal.toString().isNotEmpty)
            ? rawVal.toString()
            : (item['brand_name'] ??
                    item['brandName'] ??
                    item['BrandName'] ??
                    item['model_name'] ??
                    item['modelName'] ??
                    item['ModelName'] ??
                    item['command_name'] ??
                    item['commandName'] ??
                    item['CommandName'] ??
                    item['address_code'] ??
                    item['addressCode'] ??
                    item['AddressCode'] ??
                    item['name'] ??
                    item['Name'] ??
                    'ID: $id')
                .toString();

        return DropdownMenuItem<int>(
          value: id,
          child: Text(name, style: GoogleFonts.inter(fontSize: 14)),
        );
      }).whereType<DropdownMenuItem<int>>().toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildStringDropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required String idKey,
    required String nameKey,
    required ValueChanged<String?> onChanged,
  }) {
    final validValues = items
        .map((item) => (item[idKey] ?? item['Id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
    final currentValue = (value != null && validValues.contains(value)) ? value : null;

    return DropdownButtonFormField<String>(
      initialValue: currentValue,
      isExpanded: true,
      items: items.map((item) {
        final id = (item[idKey] ?? item['Id'] ?? '').toString();
        if (id.isEmpty) return null;
        final name = (item[nameKey] ?? item['Name'] ?? item['name'] ?? 'ID: $id').toString();

        return DropdownMenuItem<String>(
          value: id,
          child: Text(name, style: GoogleFonts.inter(fontSize: 14)),
        );
      }).whereType<DropdownMenuItem<String>>().toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildEquipmentDropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final validValues = items
        .map((item) => (item['equipmentId'] ?? item['EquipmentId'] ?? item['id'] ?? item['Id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
    final currentValue = (value != null && validValues.contains(value)) ? value : null;

    return DropdownButtonFormField<String>(
      initialValue: currentValue,
      isExpanded: true,
      items: items.map((item) {
        final id = (item['equipmentId'] ?? item['EquipmentId'] ?? item['id'] ?? item['Id'] ?? '').toString();
        if (id.isEmpty) return null;
        final name = (item['name'] ?? item['Name'] ?? item['equipmentName'] ?? 'Equipment').toString();
        final isActive = _isEquipmentOnline(item);
        final brand = (item['brand'] ?? item['Brand'] ?? '').toString();

        return DropdownMenuItem<String>(
          value: id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? AppColors.online : AppColors.textSecondary,
                ),
              ),
              Flexible(
                child: Text(
                  '$name${brand.isNotEmpty ? " ($brand)" : ""}',
                  style: GoogleFonts.inter(fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).whereType<DropdownMenuItem<String>>().toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildListTile({
    required String title,
    required String? subtitle,
    required int id,
    required VoidCallback onDelete,
    required Color cardColor,
    required Color borderColor,
    required Color textColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: ListTile(
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: textColor)),
        subtitle: subtitle != null && subtitle.isNotEmpty
            ? Text(subtitle, style: GoogleFonts.inter(fontSize: 12))
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.offline, size: 20),
          onPressed: onDelete,
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
      ),
    );
  }
}
