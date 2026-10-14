import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/core/services/mqtt_config_service.dart';
import 'configuration_page.dart';

class BluetoothScannerPage extends StatefulWidget {
  final bool returnConnection;
  final String? targetDeviceId;
  final String? targetDeviceName;

  const BluetoothScannerPage({
    super.key,
    this.returnConnection = false,
    this.targetDeviceId,
    this.targetDeviceName,
  });

  @override
  State<BluetoothScannerPage> createState() => _BluetoothScannerPageState();
}

class _BluetoothScannerPageState extends State<BluetoothScannerPage>
    with WidgetsBindingObserver {
  bool _isScanning = false;
  final List<BluetoothDiscoveryResult> _devices = [];
  bool _showIRBlasterOnly = false;
  StreamSubscription<BluetoothDiscoveryResult>? _streamSubscription;
  Timer? _uiUpdateTimer;
  bool _needsUpdate = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Set<String> _bondedAddresses = {};

  static const Color _themeGreen = Color.fromARGB(255, 123, 159, 71);
  Color get _background => mounted ? Theme.of(context).scaffoldBackgroundColor : const Color(0xFF1A1A2E);
  Color get _cardBackground => mounted ? Theme.of(context).cardColor : const Color(0xFF2D2D44);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.targetDeviceId != null && widget.targetDeviceId!.isNotEmpty) {
      _searchController.text = widget.targetDeviceId!;
      _searchQuery = widget.targetDeviceId!;
    }
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _searchQuery) {
        setState(() {
          _searchQuery = q;
        });
      }
    });
    _initBluetooth();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBondedDevices();
    }
  }

  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    _streamSubscription?.cancel();
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initBluetooth() async {
    // Pre-fetch dynamic MQTT config from server in background while scanning
    MqttConfigService.fetchMqttConfig(type: 'AC');
    await _requestPermissionsAndEnableBluetooth();
    await _refreshBondedDevices();
    // Auto-start scanning
    if (mounted) {
      _startScan();
    }
  }

  Future<void> _refreshBondedDevices() async {
    try {
      final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      if (mounted) {
        setState(() {
          _bondedAddresses = bonded.map((d) => d.address.toUpperCase()).toSet();
        });
        // Pre-populate list with bonded devices so they show immediately
        for (final d in bonded) {
          final alreadyInList = _devices.any((r) => r.device.address == d.address);
          if (!alreadyInList) {
            _devices.add(BluetoothDiscoveryResult(device: d, rssi: 0));
          }
        }
        if (bonded.isNotEmpty) {
          setState(() {});
        }
      }
    } catch (e) {
      debugPrint("Bonded devices check note: $e");
    }
  }

  Future<bool> _requestBluetoothPermissions() async {
    // Request all required Bluetooth permissions for Android 12+
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();

    // Check if all permissions are granted
    bool allGranted = statuses[Permission.bluetoothConnect]!.isGranted &&
                      statuses[Permission.bluetoothScan]!.isGranted;
    
    // Location is often required for Bluetooth discovery on older Android versions
    bool locationGranted = statuses[Permission.locationWhenInUse]!.isGranted;

    if (!allGranted && mounted) {
      _showPermissionError("Bluetooth permissions are required to scan.");
      return false;
    }
    
    if (!locationGranted && mounted) {
      _showPermissionError("Location permission is required for Bluetooth discovery.");
      return false;
    }

    return allGranted;
  }

  Future<void> _requestPermissionsAndEnableBluetooth() async {
    // First request permissions
    final permissionsGranted = await _requestBluetoothPermissions();
    if (!permissionsGranted) return;

    // Then enable Bluetooth
    await _checkAndEnableBluetooth();
  }

  Future<void> _checkAndEnableBluetooth() async {
    try {
      final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
      if (!(isEnabled ?? false)) {
        final result = await FlutterBluetoothSerial.instance.requestEnable();
        if (result ?? false) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Bluetooth enabled")),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Bluetooth is required to scan devices."),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showPermissionError("Error enabling Bluetooth: $e");
    }
  }

  void _showPermissionError(String message) {
    if (!mounted) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ $message"),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: "Settings",
            textColor: Colors.white,
            onPressed: () => openAppSettings(),
          ),
        ),
      );
    } catch (_) {}
  }

  void _startScan() async {
    // Check permissions first
    final permissionsGranted = await _requestBluetoothPermissions();
    if (!permissionsGranted) return;

    final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
    if (!(isEnabled ?? false)) {
      await _checkAndEnableBluetooth();
      return;
    }

    // cancel previous scan if any
    _streamSubscription?.cancel();
    _uiUpdateTimer?.cancel();

    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _devices.clear();
    });

    _streamSubscription =
        FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
      final index = _devices
          .indexWhere((d) => d.device.address == result.device.address);
      if (index >= 0) {
        _devices[index] = result;
      } else {
        _devices.add(result);
      }
      _needsUpdate = true;
    });

    // Start a timer to update the UI periodically instead of on every device discovery
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_needsUpdate && mounted) {
        setState(() {
          _needsUpdate = false;
        });
      }
    });

    _streamSubscription?.onDone(() {
      _uiUpdateTimer?.cancel();
      if (mounted) {
        setState(() {
          _isScanning = false;
          _needsUpdate = false;
        });
      }
    });
  }

  void _showLoadingDialog({String message = "Connecting..."}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
              BoxShadow(
                color: _themeGreen.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_themeGreen),
                strokeWidth: 4,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _hideLoadingDialog() {
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showInvalidDeviceDialog(BluetoothDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 12),
            const Text(
              "Invalid Device",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "\"${device.name ?? device.address}\" is not an Optibyte IR device.",
              style: const TextStyle(fontSize: 15, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade900.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade700),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Only Optibyte devices are supported.",
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
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange.shade400,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              "OK",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isConnecting = false;

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    // Check if device is an Optibyte IR device only if filter is active
    if (_showIRBlasterOnly && !_isIRBlaster(device.name ?? '')) {
      _showInvalidDeviceDialog(device);
      return;
    }

    // If not bonded, try to bond silently in the background (non-blocking)
    if (!_bondedAddresses.contains(device.address.toUpperCase())) {
      try {
        final state = await FlutterBluetoothSerial.instance.getBondStateForAddress(device.address);
        if (!state.isBonded) {
          debugPrint("Device not paired. Attempting silent bond...");
          try {
            await FlutterBluetoothSerial.instance.bondDeviceAtAddress(device.address);
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _isConnecting = true;
    });

    // 1. Properly close previous connection in MqttService to free up the ESP32 channel
    try {
      if (MqttService().bluetoothConnection != null) {
        debugPrint("Closing previous connection from MqttService before connecting...");
        await MqttService().bluetoothConnection?.close();
        MqttService().bluetoothConnection = null;
        MqttService().bluetoothDevice = null;
      }
    } catch (_) {}

    // 2. Cancel active scan/discovery and let the Bluetooth radio exit inquiry mode
    if (_isScanning) {
      _uiUpdateTimer?.cancel();
      await _streamSubscription?.cancel();
      _streamSubscription = null;
      try {
        await FlutterBluetoothSerial.instance.cancelDiscovery();
      } catch (_) {}
      if (mounted) {
        setState(() => _isScanning = false);
      }
      // Critical delay: Android Bluetooth radio needs ~750ms to transition from inquiry to paging
      await Future.delayed(const Duration(milliseconds: 750));
    }

    _showLoadingDialog(message: "Connecting to ${device.name ?? 'Device'}...");

    try {
      debugPrint("Connecting to RFCOMM address: ${device.address}...");
      BluetoothConnection? connection;

      try {
        connection = await BluetoothConnection.toAddress(device.address)
            .timeout(const Duration(seconds: 14));
      } catch (firstErr) {
        debugPrint("Attempt 1 failed ($firstErr). Waiting 1.5s before retry...");
        await Future.delayed(const Duration(milliseconds: 1500));
        connection = await BluetoothConnection.toAddress(device.address)
            .timeout(const Duration(seconds: 14));
      }

      if (connection.isConnected && mounted) {
        final activeConn = connection;
        _hideLoadingDialog();
        _refreshBondedDevices();
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Connected to ${device.name ?? device.address}"),
              backgroundColor: _themeGreen,
              duration: const Duration(seconds: 2),
            ),
          );
        } catch (_) {}
        if (widget.returnConnection) {
          MqttService().bluetoothConnection = activeConn;
          MqttService().bluetoothDevice = device;
          Navigator.pop(context, true);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ConfigurationPage(
                connection: activeConn,
                device: device,
              ),
            ),
          );
        }
      } else {
        throw Exception("Could not establish active connection.");
      }
    } catch (e) {
      debugPrint("❌ Bluetooth connection error: $e");
      if (mounted) {
        _hideLoadingDialog();
        setState(() {
          _isConnecting = false;
        });
        _showConnectionFailureDialog(device, e.toString());
      }
    } finally {
      if (mounted && _isConnecting) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  void _showConnectionFailureDialog(BluetoothDevice device, String error) {
    final name = device.name ?? device.address;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text("Connection Failed", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Could not establish Bluetooth connection to $name (${device.address}).",
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 14),
            const Text(
              "Quick Checklist:",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _buildSolutionStep("1", "Pair device in Phone Bluetooth Settings first (PIN: 1234 or auto)."),
            _buildSolutionStep("2", "Single Client: Ensure no other phone or previous app session is connected."),
            _buildSolutionStep("3", "Restart Hardware: Turn off and turn back on the IR Blaster device."),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Dismiss", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings_bluetooth, size: 16),
            label: const Text("Open BT Settings"),
            style: ElevatedButton.styleFrom(
              backgroundColor: _themeGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              FlutterBluetoothSerial.instance.openSettings();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSolutionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 2, right: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _themeGreen.withOpacity(0.3),
              shape: BoxShape.circle,
              border: Border.all(color: _themeGreen, width: 1),
            ),
            child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.3)),
          ),
        ],
      ),
    );
  }


  /// On ESP32 hardware, Base Wi-Fi Station MAC = Bluetooth Classic MAC - 2.
  static String calculateWifiMac(String btMac) {
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

  /// On ESP32 hardware, Bluetooth Classic MAC = Base Wi-Fi Station MAC + 2.
  static String calculateBtMac(String mac) {
    final clean = mac.replaceAll(':', '').replaceAll('-', '').trim();
    if (clean.length != 12) return mac;
    try {
      final lastByte = int.parse(clean.substring(10, 12), radix: 16);
      final btLastByte = (lastByte + 2) & 0xFF;
      final hex = btLastByte.toRadixString(16).padLeft(2, '0').toUpperCase();
      final baseHex = clean.substring(0, 10).toUpperCase() + hex;
      final parts = <String>[];
      for (int i = 0; i < 12; i += 2) {
        parts.add(baseHex.substring(i, i + 2));
      }
      return parts.join(':');
    } catch (_) {
      return mac;
    }
  }

  bool _looksLikeMac(String str) {
    final s = str.trim();
    return RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$').hasMatch(s);
  }

  bool _isMatchingTarget(BluetoothDevice device, String target) {
    final t = target.trim().toLowerCase();
    if (t.isEmpty) return false;

    final tClean = t.replaceAll(':', '').replaceAll('-', '').replaceAll(' ', '');

    final name = (device.name ?? '').toLowerCase();
    if (name.contains(t) || (tClean.isNotEmpty && name.replaceAll(' ', '').contains(tClean))) {
      return true;
    }

    final btMac = device.address.toLowerCase();
    final btMacClean = btMac.replaceAll(':', '').replaceAll('-', '');
    if (btMac.contains(t) || btMacClean.contains(tClean)) return true;

    final wifiMac = calculateWifiMac(device.address).toLowerCase();
    final wifiMacClean = wifiMac.replaceAll(':', '').replaceAll('-', '');
    if (wifiMac.contains(t) || wifiMacClean.contains(tClean)) return true;

    // Check last 8 chars (ShortId)
    final btShort = btMacClean.length >= 8 ? btMacClean.substring(btMacClean.length - 8) : btMacClean;
    final wifiShort = wifiMacClean.length >= 8 ? wifiMacClean.substring(wifiMacClean.length - 8) : wifiMacClean;
    if (tClean.isNotEmpty && (btShort.contains(tClean) || wifiShort.contains(tClean))) {
      return true;
    }

    if (widget.targetDeviceName != null && widget.targetDeviceName!.isNotEmpty) {
      if (name.contains(widget.targetDeviceName!.toLowerCase())) return true;
    }

    return false;
  }

  bool _isIRBlaster(String deviceName) {
    final lowerName = deviceName.toLowerCase().trim();
    if (lowerName.isEmpty || lowerName == "unknown device") return false;
    return lowerName.contains('sustainabyte') ||
        lowerName.contains('optibyte') ||
        lowerName.contains('ir blaster') ||
        lowerName.contains('ir-blaster') ||
        lowerName.contains('irblaster') ||
        lowerName.contains('siris') ||
        lowerName.contains('testir') ||
        lowerName.contains('itir') ||
        lowerName.contains('esp32');
  }

  BluetoothDiscoveryResult? get _targetMatchedResult {
    final target = widget.targetDeviceId ?? _searchQuery;
    if (target.trim().isEmpty) return null;
    for (final r in _devices) {
      if (_isMatchingTarget(r.device, target)) {
        return r;
      }
    }
    return null;
  }

  List<BluetoothDiscoveryResult> get _filteredDevices {
    List<BluetoothDiscoveryResult> baseList = _devices;
    if (_showIRBlasterOnly) {
      baseList = baseList.where((result) => _isIRBlaster(result.device.name ?? '')).toList();
    }

    final activeQuery = _searchQuery.isNotEmpty ? _searchQuery : (widget.targetDeviceId ?? '');

    if (activeQuery.trim().isNotEmpty) {
      final matches = <BluetoothDiscoveryResult>[];
      final others = <BluetoothDiscoveryResult>[];

      for (final r in baseList) {
        if (_isMatchingTarget(r.device, activeQuery)) {
          matches.add(r);
        } else if (_searchQuery.isEmpty) {
          // If search bar is empty but targetDeviceId exists, still show other devices below
          others.add(r);
        }
      }

      matches.sort((a, b) => b.rssi.compareTo(a.rssi));
      others.sort((a, b) => b.rssi.compareTo(a.rssi));

      return [...matches, ...others];
    }

    baseList.sort((a, b) => b.rssi.compareTo(a.rssi));
    return baseList;
  }

  Widget _buildDeviceTile(BluetoothDiscoveryResult result) {
    final device = result.device;
    final rssi = result.rssi;
    final name = device.name ?? "Unknown Device";
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);
    final textSecondaryColor = isDark ? Colors.white70 : const Color(0xFF5A6E85);

    final activeTarget = widget.targetDeviceId ?? _searchQuery;
    final isMatched = activeTarget.isNotEmpty && _isMatchingTarget(device, activeTarget);

    return Card(
      color: isMatched
          ? (isDark ? const Color(0xFF1E3824) : const Color(0xFFE8F5E9))
          : _cardBackground,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isMatched ? _themeGreen : Colors.transparent,
          width: isMatched ? 2 : 0,
        ),
      ),
      elevation: isMatched ? 4 : 2,
      child: ListTile(
        leading: Container(
          decoration: BoxDecoration(
            color: isMatched ? Colors.green.shade600 : _themeGreen,
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.all(8),
          child: Icon(
            isMatched ? Icons.check_circle_outline : Icons.bluetooth,
            color: Colors.white,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
              ),
            ),
            if (isMatched)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _themeGreen,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "ACTIVE TARGET",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${device.address}  •  RSSI: $rssi dBm",
                style: TextStyle(fontSize: 12, color: textSecondaryColor),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    _bondedAddresses.contains(device.address.toUpperCase())
                        ? Icons.link
                        : Icons.link_off,
                    size: 13,
                    color: _bondedAddresses.contains(device.address.toUpperCase())
                        ? Colors.greenAccent
                        : Colors.amberAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _bondedAddresses.contains(device.address.toUpperCase())
                        ? "PAIRED IN PHONE"
                        : "NOT PAIRED YET",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _bondedAddresses.contains(device.address.toUpperCase())
                          ? Colors.greenAccent
                          : Colors.amberAccent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: ElevatedButton(
          onPressed: _isConnecting ? null : () => _connectToDevice(device),
          style: ElevatedButton.styleFrom(
            backgroundColor: isMatched ? Colors.green.shade700 : _themeGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            isMatched
                ? "Connect Target"
                : (_bondedAddresses.contains(device.address.toUpperCase())
                    ? "Connect"
                    : "Pair / Connect"),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);
    final textSecondaryColor = isDark ? Colors.white70 : const Color(0xFF5A6E85);

    final targetMatch = _targetMatchedResult;
    final isDirectMacSearch = _looksLikeMac(_searchQuery) &&
        _devices.every((d) => d.device.address.toLowerCase() != _searchQuery.toLowerCase());

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _themeGreen,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Bluetooth Scanner",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          // Target Device Banner (if targetDeviceId is passed)
          if (widget.targetDeviceId != null && widget.targetDeviceId!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: targetMatch != null
                    ? (isDark ? const Color(0xFF1B3320) : const Color(0xFFE8F5E9))
                    : (isDark ? const Color(0xFF262C38) : const Color(0xFFEBF1F7)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: targetMatch != null ? _themeGreen : Colors.blueGrey.withOpacity(0.3),
                  width: targetMatch != null ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    targetMatch != null ? Icons.check_circle : Icons.gps_fixed,
                    color: targetMatch != null ? _themeGreen : Colors.orangeAccent,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              "ACTIVE TARGET DEVICE",
                              style: TextStyle(
                                color: targetMatch != null ? _themeGreen : textSecondaryColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            if (targetMatch != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: _themeGreen,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  "FOUND",
                                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.targetDeviceId!,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: textColor,
                          ),
                        ),
                        if (widget.targetDeviceName != null && widget.targetDeviceName!.isNotEmpty)
                          Text(
                            widget.targetDeviceName!,
                            style: TextStyle(fontSize: 12, color: textSecondaryColor),
                          ),
                      ],
                    ),
                  ),
                  if (targetMatch != null)
                    ElevatedButton.icon(
                      onPressed: _isConnecting ? null : () => _connectToDevice(targetMatch.device),
                      icon: const Icon(Icons.bolt, size: 16),
                      label: const Text("Connect"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _themeGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    )
                  else if (_isScanning)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(_themeGreen)),
                    ),
                ],
              ),
            ),
          ],

          // Search & Filter Box
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Search by Device ID, Wi-Fi MAC, or Name...",
                hintStyle: TextStyle(color: textSecondaryColor, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: _themeGreen, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: _cardBackground,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _themeGreen, width: 1.5),
                ),
              ),
            ),
          ),

          // Direct MAC Connect button (if user typed valid MAC not yet discovered)
          if (isDirectMacSearch) ...[
            () {
              final btAddress = calculateBtMac(_searchQuery);
              final isConverted = btAddress.toUpperCase() != _searchQuery.toUpperCase();
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _cardBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _themeGreen),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt, color: _themeGreen, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Direct Connect: $btAddress",
                            style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          if (isConverted)
                            Text(
                              "Calculated BT MAC (+2 from Wi-Fi MAC)",
                              style: TextStyle(color: textSecondaryColor, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _isConnecting
                          ? null
                          : () => _connectToDevice(BluetoothDevice(address: btAddress)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _themeGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      child: const Text("Direct Connect"),
                    ),
                  ],
                ),
              );
            }(),
          ],

          // Scan button and filter toggle row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? null : _startScan,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(_isScanning ? "Scanning..." : "Scan Devices"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _themeGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () {
                    setState(() {
                      _showIRBlasterOnly = !_showIRBlasterOnly;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _showIRBlasterOnly,
                        activeColor: _themeGreen,
                        onChanged: (val) {
                          setState(() {
                            _showIRBlasterOnly = val ?? false;
                          });
                        },
                      ),
                      Text(
                        "IR Only",
                        style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_isScanning) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: LinearProgressIndicator(
                backgroundColor: _cardBackground,
                valueColor: const AlwaysStoppedAnimation<Color>(_themeGreen),
              ),
            ),
          ],

          // Devices list
          Expanded(
            child: RepaintBoundary(
              child: _filteredDevices.isNotEmpty
                  ? ListView.builder(
                      itemCount: _filteredDevices.length,
                      padding: const EdgeInsets.only(bottom: 20),
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) =>
                          _buildDeviceTile(_filteredDevices[index]),
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bluetooth_searching, size: 48, color: textSecondaryColor),
                            const SizedBox(height: 12),
                            Text(
                              _isScanning
                                  ? "Scanning for Bluetooth devices..."
                                  : _searchQuery.isNotEmpty
                                      ? "No devices matching \"$_searchQuery\".\nCheck Wi-Fi MAC or Device ID."
                                      : _showIRBlasterOnly
                                          ? "No IR devices found.\nUncheck 'IR Only' to see all devices."
                                          : "No devices found.\nTap 'Scan Devices' to search again.",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: textSecondaryColor),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
