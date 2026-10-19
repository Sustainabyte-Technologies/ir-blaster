part of '../../ac_control_page.dart';

extension _ACControlSections on _ACControlPageState {

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
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
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
      updateUI();
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
    final bg = isDark ? bgDark.withValues(alpha: 0.15) : bgLight;
    final borderCol = isDark ? borderDark.withValues(alpha: 0.4) : borderLight;

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
                              : accentColor.withValues(alpha: 0.15),
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
    final Color statusColor = _isPowerOn ? AppColors.online : AppColors.offline;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _isAutomated ? Icons.smart_toy_rounded : Icons.ac_unit_rounded,
          color: statusColor,
          size: 16,
        ),
        const SizedBox(width: 6),
        Text(
          _isAutomated
              ? 'Smart Auto ($_autoTemp°C)'
              : (_isPowerOn ? 'Cool Mode' : 'Power Off'),
          style: GoogleFonts.inter(
            color: statusColor,
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
            color: statusColor,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _isPowerOn ? 'Target: $_setTemp°C' : 'AC Off',
          style: GoogleFonts.inter(
            color: statusColor,
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
    final color = _isPowerOn ? AppColors.online : AppColors.offline;
    return GestureDetector(
      onTap: _togglePower,
      child: SizedBox(
        width: 170,
        height: 170,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) {
            final double pulseVal = _pulseCtrl.value;
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Outer breathing aura ring (Green when ON, Red when OFF)
                Positioned(
                  width: 170 + (pulseVal * 24),
                  height: 170 + (pulseVal * 24),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color.withValues(alpha: 0.35 * (1.0 - pulseVal)),
                        width: 1.5 + (pulseVal * 2.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.2 * (1.0 - pulseVal)),
                          blurRadius: 14 + (pulseVal * 12),
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
                      color: color.withValues(alpha: 0.35 + pulseVal * 0.2),
                      width: 6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.18 + (pulseVal * 0.15)),
                        blurRadius: 18.0 + (pulseVal * 14.0),
                        spreadRadius: 2.0 + (pulseVal * 5.0),
                      ),
                      BoxShadow(
                        color: isDark
                            ? Colors.black38
                            : Colors.black.withValues(alpha: 0.04),
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
                  color: color,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: color.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                child: Text(
                  _isPowerOn ? 'TURN OFF' : 'TURN ON',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.8,
                  ),
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
    final bool isEnabled = _isControlAvailable && _isPowerOn;

    return GestureDetector(
      onTap: isEnabled
          ? onTap
          : () {
              _showSnack('AC is OFF. Turn on AC to adjust temperature.',
                  AppColors.offline,
                  icon: Icons.power_settings_new_rounded);
            },
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? AppColors.surfaceDark : Colors.white,
          border: Border.all(
            color: _isPowerOn
                ? (isDark ? AppColors.dividerDark : AppColors.divider)
                : AppColors.offline.withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: _isPowerOn
                  ? (isDark
                      ? Colors.black26
                      : Colors.black.withValues(alpha: 0.04))
                  : AppColors.offline.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: _isPowerOn
              ? AppColors.online
              : AppColors.offline.withValues(alpha: 0.6),
          size: 22,
        ),
      ),
    );
  }

  Widget _buildActionGrid(Color cardColor, Color textColor, bool isDark) {
    final bool canControlTemp = _isPowerOn;

    return Row(
      children: [
        // 1. Smart Auto Mode (AUTO / AUTO_OFF / AUTO:<temp>)
        _buildActionItem(
          icon: Icons.smart_toy_rounded,
          label: 'Auto',
          value: _isAutomated ? '$_autoTemp°C' : 'Off',
          activeColor: AppColors.online,
          activeBg: const Color(0xFFECFDF5),
          isActive: _isAutomated && _isPowerOn,
          isEnabled: canControlTemp,
          onTap: _toggleAutoMode,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
        ),
        const SizedBox(width: 8),
        // 2. Clear / Reset Target Setpoint (TEMP_CLEAR sets 24°C)
        _buildActionItem(
          icon: Icons.restart_alt_rounded,
          label: 'Reset',
          value: '24°C',
          activeColor: AppColors.online,
          activeBg: const Color(0xFFECFDF5),
          isActive: _setTemp == 24 && _isPowerOn,
          isEnabled: canControlTemp,
          onTap: _resetTempToDefault,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
        ),
        const SizedBox(width: 8),
        // 3. Step UP Temperature (TEMP_UP / +1°C)
        _buildActionItem(
          icon: Icons.arrow_upward_rounded,
          label: 'Temp Up',
          value: '+1°C',
          activeColor: AppColors.online,
          activeBg: const Color(0xFFECFDF5),
          isActive: _setTemp < 30 && _isPowerOn,
          isEnabled: canControlTemp,
          onTap: _incrementTemp,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
        ),
        const SizedBox(width: 8),
        // 4. Step DOWN Temperature (TEMP_DOWN / -1°C)
        _buildActionItem(
          icon: Icons.arrow_downward_rounded,
          label: 'Temp Down',
          value: '-1°C',
          activeColor: AppColors.online,
          activeBg: const Color(0xFFECFDF5),
          isActive: _setTemp > 16 && _isPowerOn,
          isEnabled: canControlTemp,
          onTap: _decrementTemp,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
        ),
        const SizedBox(width: 8),
        // 5. Query Full State & Force Telemetry (STATUS)
        _buildActionItem(
          icon: Icons.sync_rounded,
          label: 'Status',
          value: 'Live',
          activeColor: AppColors.online,
          activeBg: const Color(0xFFECFDF5),
          isActive: _isActive,
          isEnabled: true,
          onTap: _requestStatus,
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
    bool isEnabled = true,
  }) {
    final bool isInteractable = _isControlAvailable && isEnabled;

    final bg = (isActive && isInteractable)
        ? (isDark ? activeColor.withValues(alpha: 0.15) : activeBg)
        : (!isEnabled
            ? (isDark
                ? AppColors.offline.withValues(alpha: 0.06)
                : const Color(0xFFFEF2F2))
            : cardColor);

    final borderCol = (isActive && isInteractable)
        ? activeColor.withValues(alpha: 0.4)
        : (!isEnabled
            ? AppColors.offline.withValues(alpha: 0.3)
            : (isDark ? AppColors.dividerDark : AppColors.divider));

    return Expanded(
      child: GestureDetector(
        onTap: isInteractable
            ? onTap
            : () {
                _showSnack('AC is OFF. Turn on AC to use $label.',
                    AppColors.offline,
                    icon: Icons.power_settings_new_rounded);
              },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderCol, width: 1.2),
            boxShadow: [
              if (isActive && isInteractable)
                BoxShadow(
                  color: activeColor.withValues(alpha: isDark ? 0.15 : 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              customIcon ??
                  Icon(
                    icon,
                    color: (isActive && isInteractable)
                        ? activeColor
                        : (!isEnabled
                            ? AppColors.offline.withValues(alpha: 0.6)
                            : AppColors.textHint),
                    size: 22,
                  ),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: !isEnabled
                      ? AppColors.offline.withValues(alpha: 0.7)
                      : (isDark ? Colors.white54 : Colors.black54),
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
                      : (!isEnabled
                          ? AppColors.offline
                          : AppColors.textHint),
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
              ? AppColors.online.withValues(alpha: 0.12)
              : (isDark
                  ? AppColors.coolBlue.withValues(alpha: 0.12)
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
              ? AppColors.primary.withValues(alpha: 0.12)
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
            border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
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
}
