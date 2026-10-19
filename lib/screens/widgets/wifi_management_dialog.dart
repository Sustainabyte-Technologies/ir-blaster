import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';
import 'package:ir_blaster_ac/core/services/mqtt_config_service.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';

class WifiManagementDialog extends StatefulWidget {
  final MqttService mqtt;
  final String initialSsid;
  final String? initialMac;
  final String? deviceId;
  final String? targetDeviceName;
  final bool isIndividualEquipment;
  final Function(String ssid, String password)? onWifiConfigured;

  const WifiManagementDialog({
    super.key,
    required this.mqtt,
    required this.initialSsid,
    this.initialMac,
    this.deviceId,
    this.targetDeviceName,
    this.isIndividualEquipment = false,
    this.onWifiConfigured,
  });

  @override
  State<WifiManagementDialog> createState() => _WifiManagementDialogState();
}

class _WifiManagementDialogState extends State<WifiManagementDialog> {
  final _newSsidCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  bool _showNewPassword = false;
  bool _isResetting = false;

  String _cachedPrimarySsid = '';
  String _cachedPrimaryPass = '';
  String _cachedMac = '';

  bool _showPrimaryPassword = false;

  StreamSubscription? _responseSub;

  // ── MQTT Connection fields ──────────────────────────────────────────────
  bool _showMqttSection = false;
  bool _isConnectingMqtt = false;
  bool _mqttConnectSuccess = false;
  String _mqttConnectStatus = '';
  bool _mqttPassVisible = false;

  final _mqttHostCtrl = TextEditingController();
  final _mqttPortCtrl = TextEditingController();
  final _mqttTopicCtrl = TextEditingController();
  final _mqttUserCtrl = TextEditingController();
  final _mqttPassCtrl = TextEditingController();

  static String formatMacAddress(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return '';
    final noDelim = clean
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .toUpperCase();
    if (noDelim.length == 12 && RegExp(r'^[0-9A-F]{12}$').hasMatch(noDelim)) {
      final parts = <String>[];
      for (int i = 0; i < 12; i += 2) {
        parts.add(noDelim.substring(i, i + 2));
      }
      return parts.join(':');
    }
    if (RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$').hasMatch(clean)) {
      return clean.replaceAll('-', ':').toUpperCase();
    }
    return clean;
  }

  Future<void> _loadCachedCredentials() async {
    final primary = await LocalCacheService.getWifiCredentials();

    final pSsid = primary['ssid'] ?? '';
    final pPass = primary['password'] ?? '';

    String foundMac = widget.initialMac ?? '';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (foundMac.isEmpty && widget.deviceId != null && widget.deviceId!.isNotEmpty) {
        foundMac = prefs.getString('device_mac_${widget.deviceId}') ??
            prefs.getString('device_mac_${widget.deviceId!.toLowerCase()}') ??
            '';
      }
      if (foundMac.isEmpty && !widget.isIndividualEquipment) {
        foundMac = prefs.getString('device_mac') ??
            prefs.getString('wifi_mac') ??
            '';
      }

      if (foundMac.isEmpty) {
        final listJson = prefs.getString('local_provisioned_devices') ?? '[]';
        final List<dynamic> list = jsonDecode(listJson);
        for (final item in list) {
          if (item is Map) {
            final devId = (item['id'] ?? '').toString();
            final shortId = (item['shortId'] ?? '').toString();
            final ssid = (item['ssid'] ?? '').toString();

            if ((widget.deviceId != null &&
                    widget.deviceId!.isNotEmpty &&
                    (devId.toLowerCase() == widget.deviceId!.toLowerCase() ||
                        shortId.toLowerCase() ==
                            widget.deviceId!.toLowerCase())) ||
                (pSsid.isNotEmpty &&
                    ssid.toLowerCase() == pSsid.toLowerCase())) {
              final m = (item['mac'] ?? item['wifiMac'] ?? item['imei'] ?? '').toString();
              if (m.isNotEmpty) {
                foundMac = m;
                break;
              }
            }
          }
        }
        if (foundMac.isEmpty && list.isNotEmpty && list.first is Map && !widget.isIndividualEquipment) {
          foundMac =
              (list.first['mac'] ?? list.first['wifiMac'] ?? '').toString();
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error reading MAC in WifiManagementDialog: $e');
    }

    if (mounted) {
      setState(() {
        _cachedPrimarySsid = pSsid;
        _cachedPrimaryPass = pPass;
        if (foundMac.isNotEmpty) {
          _cachedMac = formatMacAddress(foundMac);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCachedCredentials();
    _newSsidCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _newPassCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    // Request current WiFi status immediately for targeted device
    widget.mqtt.requestWifiStatus(targetDeviceId: widget.deviceId);
    // Pre-fill MQTT fields from current config
    _mqttHostCtrl.text = AppConfig.mqttBroker;
    _mqttPortCtrl.text = AppConfig.mqttPort.toString();
    final devId = widget.deviceId ?? '';
    final root = AppConfig.mqttRoot;
    if (devId.isNotEmpty && !root.toLowerCase().contains(devId.toLowerCase())) {
      _mqttTopicCtrl.text = '$root/$devId';
    } else {
      _mqttTopicCtrl.text = root;
    }
    _mqttUserCtrl.text = AppConfig.mqttUsername;
    _mqttPassCtrl.text = AppConfig.mqttPassword;

    // Subscribe to response stream for feedback inside the dialog
    _responseSub = widget.mqtt.responseStream.listen((resp) {
      if (!mounted) return;

      if (resp.type == SirisResponseType.wifiPrimarySet) {
        _showSnack('Primary WiFi saved: ${resp.detail}', AppColors.online);
        _loadCachedCredentials();
      } else if (resp.type == SirisResponseType.wifiSecondarySet) {
        _showSnack('Secondary WiFi saved: ${resp.detail}', AppColors.online);
        _loadCachedCredentials();
      } else if (resp.type == SirisResponseType.wifiResetBtOpen) {
        _showSnack('WiFi reset complete on device!', AppColors.warning);
      } else if (resp.type == SirisResponseType.wifiError) {
        _showSnack('WiFi Error: ${resp.detail}', AppColors.offline);
      } else if (resp.type == SirisResponseType.wifiRollback) {
        _showSnack(
            'WiFi failed! Rolled back to: ${resp.detail}', AppColors.warning);
        _loadCachedCredentials();
      }
    });
  }

  void _showSnack(String message, Color bgColor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _responseSub?.cancel();
    _newSsidCtrl.dispose();
    _newPassCtrl.dispose();
    _mqttHostCtrl.dispose();
    _mqttPortCtrl.dispose();
    _mqttTopicCtrl.dispose();
    _mqttUserCtrl.dispose();
    _mqttPassCtrl.dispose();
    super.dispose();
  }

  /// Reconnect app MQTT to a new broker using the entered credentials.
  Future<void> _handleMqttConnect() async {
    final host = _mqttHostCtrl.text.trim();
    final portStr = _mqttPortCtrl.text.trim();
    final topic = _mqttTopicCtrl.text.trim();
    final user = _mqttUserCtrl.text.trim();
    final pass = _mqttPassCtrl.text.trim();

    if (host.isEmpty) {
      _showSnack('Please enter the MQTT Broker URL / IP', AppColors.warning);
      return;
    }
    final port = int.tryParse(portStr) ?? 1883;

    setState(() {
      _isConnectingMqtt = true;
      _mqttConnectStatus = 'Connecting to $host:$port...';
      _mqttConnectSuccess = false;
    });

    // Disconnect existing connection first
    widget.mqtt.disconnect();
    await Future.delayed(const Duration(milliseconds: 400));

    // Override cached MQTT credentials in MqttConfigService
    MqttConfigService.updateCachedCredentials(
      host: host,
      port: port,
      topic: topic.isNotEmpty ? topic : user,
      username: user,
      password: pass,
    );

    // Reconnect with new broker settings
    final ok = await widget.mqtt.connect(
      deviceId: widget.deviceId,
      companyId: null,
    );

    if (!mounted) return;
    setState(() {
      _isConnectingMqtt = false;
      _mqttConnectSuccess = ok;
      _mqttConnectStatus = ok
          ? 'Connected to $host:$port ✓'
          : 'Connection failed. Check broker details.';
    });

    if (ok) {
      _showSnack('MQTT connected to $host:$port', AppColors.online);
    } else {
      _showSnack('MQTT connection failed', AppColors.offline);
    }
  }
  Future<void> _handleMqttWifiConfigure() async {
    final newSsid = _newSsidCtrl.text.trim();
    final newPass = _newPassCtrl.text.trim();

    if (newSsid.isEmpty) {
      _showSnack('Please enter New SSID', AppColors.warning);
      return;
    }

    if (!widget.mqtt.isConnected) {
      _showSnack(
          widget.isIndividualEquipment
              ? 'Network is not connected. Please ensure device is online.'
              : 'MQTT is not connected. Connect MQTT below.',
          AppColors.warning);
      if (!widget.isIndividualEquipment) setState(() => _showMqttSection = true);
      return;
    }

    setState(() => _isResetting = true);

    try {
      await LocalCacheService.saveWifiCredentials(newSsid, newPass);
      await _loadCachedCredentials();

      widget.mqtt.setPrimaryWifiMqtt(newSsid, newPass, targetDeviceId: widget.deviceId);
      await Future.delayed(const Duration(milliseconds: 300));
      widget.mqtt.sendWifiConnect(targetDeviceId: widget.deviceId);

      final devName = widget.targetDeviceName ?? widget.deviceId ?? 'device';
      _showSnack('WiFi credentials sent via MQTT for $devName to "$newSsid". Connecting...', AppColors.online);

      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() => _isResetting = false);
        Navigator.of(context).pop();
        widget.onWifiConfigured?.call(newSsid, newPass);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResetting = false);
        _showSnack('Error sending WiFi via MQTT: $e', AppColors.offline);
      }
    }
  }

  Future<void> _handleMqttWifiConnectOnly() async {
    if (!widget.mqtt.isConnected) {
      _showSnack(
          widget.isIndividualEquipment
              ? 'Network is not connected. Please ensure device is online.'
              : 'MQTT is not connected. Connect MQTT below.',
          AppColors.warning);
      if (!widget.isIndividualEquipment) setState(() => _showMqttSection = true);
      return;
    }

    setState(() => _isResetting = true);
    try {
      widget.mqtt.sendWifiConnect(targetDeviceId: widget.deviceId);
      final devName = widget.targetDeviceName ?? widget.deviceId ?? 'device';
      _showSnack('WiFi Connect command sent via MQTT for $devName.', AppColors.online);

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() => _isResetting = false);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResetting = false);
        _showSnack('Error sending WiFi Connect via MQTT: $e', AppColors.offline);
      }
    }
  }

  Future<void> _handleMqttWifiReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          widget.isIndividualEquipment ? 'Reset Wi-Fi' : 'Reset WiFi via MQTT',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: Text(
          widget.isIndividualEquipment
              ? 'Are you sure you want to reset device Wi-Fi?\n\nThis will send a Wi-Fi reset command over the network.'
              : 'Are you sure you want to reset device WiFi via MQTT?\n\nThis will send a WiFi reset command over MQTT.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
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
            child: Text(
              widget.isIndividualEquipment ? 'Reset Wi-Fi' : 'Reset via MQTT',
              style: GoogleFonts.inter(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    if (!widget.mqtt.isConnected) {
      _showSnack(
          widget.isIndividualEquipment
              ? 'Network is not connected. Please ensure device is online.'
              : 'MQTT is not connected. Expand MQTT Connection below to connect.',
          AppColors.warning);
      if (!widget.isIndividualEquipment) setState(() => _showMqttSection = true);
      return;
    }

    setState(() => _isResetting = true);
    try {
      await LocalCacheService.clearWifiCredentials();
      await LocalCacheService.clearSecondaryWifiCredentials();
      await _loadCachedCredentials();

      widget.mqtt.sendWifiReset(targetDeviceId: widget.deviceId);
      _showSnack('WiFi Reset command sent via MQTT.', AppColors.warning);

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() => _isResetting = false);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResetting = false);
        _showSnack('Error sending WiFi Reset via MQTT: $e', AppColors.offline);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E2F) : Colors.grey[50]!;
    final textColor = isDark ? Colors.white : AppColors.textPrimary;
    final subtitleColor = isDark ? Colors.white54 : AppColors.textSecondary;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: StreamBuilder<SirisDeviceState>(
            stream: widget.mqtt.stateStream,
            initialData: widget.mqtt.lastState,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final isOnline =
                  widget.mqtt.isConnected && (state?.isActive ?? false);

              final devicePrimarySsid = state?.primarySsid ?? '';
              final displayPrimarySsid = devicePrimarySsid.isNotEmpty
                  ? devicePrimarySsid
                  : _cachedPrimarySsid;
              final primaryPassDisplay = (displayPrimarySsid ==
                          _cachedPrimarySsid &&
                      _cachedPrimaryPass.isNotEmpty)
                  ? _cachedPrimaryPass
                  : (displayPrimarySsid.isNotEmpty ? 'Saved on Device' : '');

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.wifi,
                            color: Colors.green, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isIndividualEquipment
                                  ? (widget.targetDeviceName != null &&
                                          widget.targetDeviceName!.isNotEmpty
                                      ? '${widget.targetDeviceName} Network'
                                      : 'Device WiFi & Network')
                                  : 'WiFi Management',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              widget.isIndividualEquipment
                                  ? 'WiFi & Network credentials'
                                  : 'Configure or reset credentials',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: subtitleColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  if (widget.isIndividualEquipment) ...[
                    // ── Device Credentials Card ─────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.black12,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Device Credentials',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // MAC ID row with copy
                          Builder(builder: (context) {
                            String resolvedMac = _cachedMac;
                            if (state?.wifiMac != null && state!.wifiMac.isNotEmpty) {
                              resolvedMac = formatMacAddress(state.wifiMac);
                            } else if (resolvedMac.isEmpty && state?.deviceId != null && state!.deviceId.isNotEmpty) {
                              final c = formatMacAddress(state.deviceId);
                              if (c.contains(':')) resolvedMac = c;
                            } else if (resolvedMac.isEmpty && state?.imei != null && state!.imei.isNotEmpty) {
                              final c = formatMacAddress(state.imei);
                              if (c.contains(':')) resolvedMac = c;
                            }
                            if (resolvedMac.isEmpty && widget.initialMac != null && widget.initialMac!.isNotEmpty) {
                              resolvedMac = formatMacAddress(widget.initialMac!);
                            }
                            final displayMac = resolvedMac.isNotEmpty ? resolvedMac : '--:--:--:--:--:--';
                            return _buildDetailRow(
                              'MAC ID',
                              displayMac,
                              isDark,
                              icon: resolvedMac.isNotEmpty
                                  ? GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        Clipboard.setData(ClipboardData(text: resolvedMac));
                                        _showSnack('MAC ID copied to clipboard', AppColors.online);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 6.0),
                                        child: Icon(Icons.copy_rounded, size: 13,
                                            color: isDark ? Colors.white54 : Colors.black45),
                                      ),
                                    )
                                  : null,
                            );
                          }),

                          const Divider(height: 16),

                          // WiFi Credentials
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(Icons.wifi_rounded, size: 16,
                                  color: isOnline ? Colors.green : subtitleColor),
                              const SizedBox(width: 6),
                              Text('WiFi',
                                  style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isOnline ? Colors.green : subtitleColor)),
                              const SizedBox(width: 6),
                              Container(
                                width: 7, height: 7,
                                decoration: BoxDecoration(
                                  color: isOnline ? Colors.green : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (displayPrimarySsid.isNotEmpty) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Text('SSID  ',
                                            style: GoogleFonts.inter(fontSize: 11,
                                                color: isDark ? Colors.white38 : Colors.black45)),
                                        Expanded(child: Text(displayPrimarySsid,
                                            style: GoogleFonts.inter(fontSize: 12,
                                                fontWeight: FontWeight.w600, color: textColor),
                                            overflow: TextOverflow.ellipsis)),
                                      ]),
                                      const SizedBox(height: 4),
                                      Row(children: [
                                        Text('Pass  ',
                                            style: GoogleFonts.inter(fontSize: 11,
                                                color: isDark ? Colors.white38 : Colors.black45)),
                                        Expanded(child: Text(
                                            _showPrimaryPassword ? primaryPassDisplay : '•• •• •• ••',
                                            style: GoogleFonts.inter(fontSize: 12,
                                                fontWeight: FontWeight.w600, color: textColor),
                                            overflow: TextOverflow.ellipsis)),
                                      ]),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    _showPrimaryPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                    size: 18, color: subtitleColor,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => setState(() => _showPrimaryPassword = !_showPrimaryPassword),
                                ),
                              ],
                            ),
                          ] else ...[
                            Text('Not Configured',
                                style: GoogleFonts.inter(fontSize: 12, color: subtitleColor, fontStyle: FontStyle.italic)),
                          ],


                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],


                  // New WiFi Credentials Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New WiFi Credentials',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newSsidCtrl,
                          style:
                              GoogleFonts.inter(fontSize: 13, color: textColor),
                          decoration: InputDecoration(
                            labelText: 'New SSID',
                            labelStyle: GoogleFonts.inter(
                                color: subtitleColor, fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newPassCtrl,
                          obscureText: !_showNewPassword,
                          style:
                              GoogleFonts.inter(fontSize: 13, color: textColor),
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            labelStyle: GoogleFonts.inter(
                                color: subtitleColor, fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showNewPassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                size: 18,
                                color: subtitleColor,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(
                                    () => _showNewPassword = !_showNewPassword);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Mode explanation banner
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: (widget.mqtt.isConnected
                              ? AppColors.online
                              : AppColors.warning)
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (widget.mqtt.isConnected
                                ? AppColors.online
                                : AppColors.warning)
                            .withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          widget.mqtt.isConnected
                              ? Icons.cloud_done_rounded
                              : Icons.warning_amber_rounded,
                          size: 16,
                          color: widget.mqtt.isConnected
                              ? AppColors.online
                              : AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.mqtt.isConnected
                                ? (widget.isIndividualEquipment
                                    ? 'Updates Wi-Fi credentials directly over the network for ${widget.targetDeviceName ?? widget.deviceId ?? 'device'}.'
                                    : 'Updates Wi-Fi credentials over MQTT directly for ${widget.targetDeviceName ?? widget.deviceId ?? 'device'}.')
                                : 'Network connection is disconnected. Please connect before updating.',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: textColor,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Wi-Fi Action Buttons ────────────────────────────────────
                  if (_newSsidCtrl.text.isNotEmpty) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _isResetting ? null : _handleMqttWifiConfigure,
                        icon: _isResetting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.wifi_protected_setup_rounded,
                                size: 18),
                        label: Text(
                          _isResetting
                              ? 'Sending to Device...'
                              : (widget.isIndividualEquipment
                                  ? 'Update Wi-Fi'
                                  : 'Update Wi-Fi via MQTT'),
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _isResetting ? null : _handleMqttWifiConnectOnly,
                        icon: _isResetting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.wifi_protected_setup_rounded,
                                size: 18),
                        label: Text(
                          _isResetting
                              ? 'Connecting...'
                              : (widget.isIndividualEquipment
                                  ? 'Reconnect Wi-Fi'
                                  : 'Reconnect Wi-Fi via MQTT'),
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _isResetting ? null : _handleMqttWifiReset,
                      icon: const Icon(Icons.restart_alt_rounded,
                          size: 15, color: AppColors.offline),
                      label: Text(
                        widget.isIndividualEquipment
                            ? 'Reset Wi-Fi'
                            : 'Reset via MQTT',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.offline,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  // ── MQTT Broker Connection Card (Technical / Collapsible) ───
                  // Only visible on home page dialog (!widget.isIndividualEquipment).
                  // Removed from select equipment inside page as requested!
                  if (!widget.isIndividualEquipment) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _showMqttSection = !_showMqttSection),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: widget.mqtt.isConnected
                                ? AppColors.primary.withValues(alpha: 0.35)
                                : (isDark ? Colors.white10 : Colors.black12),
                            width: widget.mqtt.isConnected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: widget.mqtt.isConnected
                                    ? AppColors.primary.withValues(alpha: 0.12)
                                    : Colors.grey.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.cloud_queue_rounded,
                                size: 18,
                                color: widget.mqtt.isConnected
                                    ? AppColors.primary
                                    : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'MQTT Connection',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: textColor,
                                    ),
                                  ),
                                  Text(
                                    widget.mqtt.isConnected
                                        ? AppConfig.mqttBroker.isNotEmpty
                                            ? AppConfig.mqttBroker
                                            : 'Connected'
                                        : 'Not connected — tap to configure',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: widget.mqtt.isConnected
                                        ? AppColors.primary
                                        : subtitleColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Status dot
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: widget.mqtt.isConnected
                                    ? Colors.green
                                    : Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Icon(
                              _showMqttSection
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: subtitleColor,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Expandable MQTT form
                    if (_showMqttSection) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white10 : Colors.black12,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMqttField(
                              label: 'Broker URL / IP',
                              controller: _mqttHostCtrl,
                              icon: Icons.dns_rounded,
                              isDark: isDark,
                              textColor: textColor,
                              subtitleColor: subtitleColor,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                SizedBox(
                                  width: 90,
                                  child: _buildMqttField(
                                    label: 'Port',
                                    controller: _mqttPortCtrl,
                                    icon: Icons.numbers_rounded,
                                    keyboard: TextInputType.number,
                                    isDark: isDark,
                                    textColor: textColor,
                                    subtitleColor: subtitleColor,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildMqttField(
                                    label: 'Topic / Root',
                                    controller: _mqttTopicCtrl,
                                    icon: Icons.tag_rounded,
                                    isDark: isDark,
                                    textColor: textColor,
                                    subtitleColor: subtitleColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _buildMqttField(
                              label: 'Username',
                              controller: _mqttUserCtrl,
                              icon: Icons.person_rounded,
                              isDark: isDark,
                              textColor: textColor,
                              subtitleColor: subtitleColor,
                            ),
                            const SizedBox(height: 10),
                            _buildMqttField(
                              label: 'Password',
                              controller: _mqttPassCtrl,
                              icon: Icons.lock_rounded,
                              isDark: isDark,
                              textColor: textColor,
                              subtitleColor: subtitleColor,
                              obscure: !_mqttPassVisible,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _mqttPassVisible
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  size: 16,
                                  color: subtitleColor,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => setState(
                                    () => _mqttPassVisible = !_mqttPassVisible),
                              ),
                            ),

                            // Status feedback
                            if (_mqttConnectStatus.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _mqttConnectSuccess
                                      ? Colors.green.withValues(alpha: 0.10)
                                      : Colors.red.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _mqttConnectSuccess
                                        ? Colors.green.withValues(alpha: 0.3)
                                        : Colors.red.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _mqttConnectSuccess
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.error_outline_rounded,
                                      size: 14,
                                      color: _mqttConnectSuccess
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _mqttConnectStatus,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: _mqttConnectSuccess
                                              ? Colors.green
                                              : Colors.red,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _isConnectingMqtt
                                    ? null
                                    : _handleMqttConnect,
                                icon: _isConnectingMqtt
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Icon(Icons.cloud_done_rounded,
                                        size: 16),
                                label: Text(
                                  _isConnectingMqtt
                                      ? 'Connecting...'
                                      : 'Connect MQTT',
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }



  Widget _buildDetailRow(String label, String value, bool isDark,
      {Color? valueColor, Widget? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                icon,
                const SizedBox(width: 4),
              ],
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color:
                      valueColor ?? (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMqttField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool isDark,
    required Color textColor,
    required Color subtitleColor,
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      style: GoogleFonts.inter(fontSize: 12, color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: subtitleColor, fontSize: 11),
        prefixIcon: Icon(icon, size: 16, color: subtitleColor),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary),
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }
}
