import 'package:flutter/material.dart';

class WifiSectionWidget extends StatefulWidget {
  final Color themeGreen;
  final bool isWifiConnected;
  final String wifiStatus;
  final String wifiIP;
  final VoidCallback onShowWifiSetup;
  final bool showMqttDropdown;
  final VoidCallback onToggleMqttDropdown;
  final String mqttStatus;
  final bool isMqttConnected;
  final TextEditingController mqttHostController;
  final TextEditingController mqttPortController;
  final TextEditingController mqttTopicController;
  final TextEditingController mqttUserController;
  final TextEditingController mqttPassController;
  final VoidCallback onSendMqttSettings;
  final VoidCallback onConnectMqtt;
  final bool autoControlEnabled;
  final ValueChanged<bool> onAutoControlChanged;
  final TextEditingController autoOnController;
  final TextEditingController autoOffController;
  final VoidCallback onApplyAutoConfig;

  const WifiSectionWidget({
    super.key,
    required this.themeGreen,
    required this.isWifiConnected,
    required this.wifiStatus,
    required this.wifiIP,
    required this.onShowWifiSetup,
    required this.showMqttDropdown,
    required this.onToggleMqttDropdown,
    required this.mqttStatus,
    required this.isMqttConnected,
    required this.mqttHostController,
    required this.mqttPortController,
    required this.mqttTopicController,
    required this.mqttUserController,
    required this.mqttPassController,
    required this.onSendMqttSettings,
    required this.onConnectMqtt,
    required this.autoControlEnabled,
    required this.onAutoControlChanged,
    required this.autoOnController,
    required this.autoOffController,
    required this.onApplyAutoConfig,
  });

  @override
  State<WifiSectionWidget> createState() => _WifiSectionWidgetState();
}

class _WifiSectionWidgetState extends State<WifiSectionWidget> {
  static const Color _cardBackground = Color(0xFF2D2D44);
  bool _mqttPassVisible = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildWifiCard(),
        _buildMqttDropdownCard(),
      ],
    );
  }

  Widget _buildWifiCard() {
    return Card(
      color: _cardBackground,
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wifi, color: widget.themeGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.wifiStatus,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: widget.isWifiConnected 
                              ? Colors.green 
                              : (widget.wifiStatus.contains('...') || widget.wifiStatus.contains('⏳') ? Colors.orange : Colors.red),
                        ),
                      ),
                      if (widget.wifiStatus.contains('...') || widget.wifiStatus.contains('⏳'))
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                          ),
                        ),
                    ],
                  ),
                  if (widget.wifiIP.isNotEmpty)
                    Text(widget.wifiIP, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: widget.onShowWifiSetup,
                        icon: const Icon(Icons.settings_suggest_rounded, size: 16),
                        label: const Text('WiFi & MQTT Setup'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.themeGreen,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.onToggleMqttDropdown,
                        icon: Icon(
                          widget.showMqttDropdown ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                          color: Colors.white70,
                        ),
                        label: Text(
                          widget.showMqttDropdown ? 'Hide MQTT' : 'MQTT Config',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
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

  Widget _buildMqttDropdownCard() {
    if (!widget.showMqttDropdown) return const SizedBox.shrink();

    return Card(
      color: _cardBackground,
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'MQTT Broker Settings',
                    style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
                Chip(
                  label: Text(widget.mqttStatus, style: const TextStyle(fontSize: 12)),
                  backgroundColor: widget.isMqttConnected ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                "Format: MQTT:topic=${widget.mqttTopicController.text.trim()},port=${widget.mqttPortController.text.trim()},ip=${widget.mqttHostController.text.trim()},user=${widget.mqttUserController.text.trim()},password=***",
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 10),
            _field('topic', widget.mqttTopicController),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _field('port', widget.mqttPortController, keyboard: TextInputType.number),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _field('ip', widget.mqttHostController),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field('user', widget.mqttUserController)),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(
                    'password',
                    widget.mqttPassController,
                    obscure: !_mqttPassVisible,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _mqttPassVisible ? Icons.visibility : Icons.visibility_off,
                        color: Colors.white70,
                        size: 18,
                      ),
                      onPressed: () {
                        setState(() {
                          _mqttPassVisible = !_mqttPassVisible;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: widget.onSendMqttSettings,
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('Save & Send'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.themeGreen,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: widget.onConnectMqtt,
                  icon: const Icon(Icons.cloud_done, size: 16),
                  label: const Text('Connect MQTT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const Divider(height: 22, color: Colors.white24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Auto Control',
                    style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
                Switch(
                  value: widget.autoControlEnabled,
                  onChanged: widget.onAutoControlChanged,
                  activeTrackColor: widget.themeGreen,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field('Auto ON Temp (°C)', widget.autoOnController, keyboard: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _field('Auto OFF Temp (°C)', widget.autoOffController, keyboard: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: widget.onApplyAutoConfig,
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('Apply Auto Config'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        border: const OutlineInputBorder(),
        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
        isDense: true,
        suffixIcon: suffixIcon,
      ),
    );
  }
}
