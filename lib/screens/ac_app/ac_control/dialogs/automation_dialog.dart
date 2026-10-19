part of '../../ac_control_page.dart';

extension _ACControlAutomationDialog on _ACControlPageState {
  void _showAutomationDialog(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Smart Automation',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      Switch(
                        value: _isAutomated,
                        activeThumbColor: AppColors.primary,
                        onChanged: (value) async {
                          if (!_isControlAvailable) {
                            _showSnack(
                              'Device is offline. Connect to Wi-Fi to use smart automation.',
                              AppColors.offline,
                              icon: Icons.wifi_off_rounded,
                            );
                            return;
                          }
                          setModalState(() {
                            _isAutomated = value;
                          });
                          updateUI(() {
                            _isAutomated = value;
                          });
                          _addLog(
                              'Automation ${value ? 'ENABLED' : 'DISABLED'}',
                              AppColors.primary);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('auto_enabled', value);
                          if (value) {
                            _mqtt.enableAutomation(
                              autoTemp: _autoTemp,
                              targetDeviceId: _effectiveDeviceId,
                              targetDeviceImei: _activeDeviceImei.isNotEmpty
                                  ? _activeDeviceImei
                                  : null,
                              targetDeviceName:
                                  _selectedEquipmentName.isNotEmpty
                                      ? _selectedEquipmentName
                                      : null,
                            );
                          } else {
                            _mqtt.disableAutomation(
                              targetDeviceId: _effectiveDeviceId,
                              targetDeviceImei: _activeDeviceImei.isNotEmpty
                                  ? _activeDeviceImei
                                  : null,
                              targetDeviceName:
                                  _selectedEquipmentName.isNotEmpty
                                      ? _selectedEquipmentName
                                      : null,
                            );
                          }
                          _showSnack(
                            'Smart Automation ${value ? 'Enabled ($_autoTemp°C)' : 'Disabled'}',
                            value ? AppColors.online : AppColors.offline,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Let the IR Blaster adjust your AC settings intelligently based on room parameters to optimize comfort and save energy.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(
                      color:
                          isDark ? AppColors.dividerDark : AppColors.divider),
                  const SizedBox(height: 16),
                  Text(
                    'Automation Triggers',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTemperatureThresholdTriggerItem(
                    enabled: _isAutomated,
                    isDark: isDark,
                    setModalState: setModalState,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Automation threshold is independent from normal AC temperature ($_setTemp°C).',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateAutoTemp(int newTemp, [StateSetter? setModalState]) async {
    if (newTemp < 16 || newTemp > 30) return;
    if (setModalState != null) {
      setModalState(() {
        _autoTemp = newTemp;
      });
    }
    updateUI(() {
      _autoTemp = newTemp;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_temp', newTemp);

    _addLog('Smart Automation threshold set to $newTemp°C', AppColors.primary);

    if (_isAutomated) {
      if (!_isControlAvailable) {
        _showSnack(
          'Device offline. Saved threshold $newTemp°C will apply when online.',
          AppColors.offline,
          icon: Icons.wifi_off_rounded,
        );
      } else {
        _mqtt.setAutoTemperature(
          newTemp,
          targetDeviceId: _effectiveDeviceId,
          targetDeviceImei:
              _activeDeviceImei.isNotEmpty ? _activeDeviceImei : null,
          targetDeviceName:
              _selectedEquipmentName.isNotEmpty ? _selectedEquipmentName : null,
        );
        _showSnack(
          'Smart Automation target set to $newTemp°C',
          AppColors.primary,
          icon: Icons.thermostat_rounded,
        );
      }
    }
  }

  Widget _buildTemperatureThresholdTriggerItem({
    required bool enabled,
    required bool isDark,
    required StateSetter setModalState,
  }) {
    final titleColor = enabled
        ? (isDark ? Colors.white : AppColors.textPrimary)
        : (isDark ? Colors.white54 : Colors.black45);
    final descColor = enabled
        ? (isDark ? Colors.white60 : Colors.black54)
        : (isDark ? Colors.white24 : Colors.black26);
    final iconColor = enabled
        ? AppColors.primary
        : (isDark ? Colors.white24 : Colors.black26);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: enabled
            ? (isDark
                ? AppColors.primary.withValues(alpha: 0.08)
                : AppColors.primary.withValues(alpha: 0.05))
            : (isDark
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled
              ? AppColors.primary.withValues(alpha: 0.25)
              : (isDark ? Colors.white10 : Colors.black12),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: enabled
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.black.withValues(alpha: 0.03)),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.thermostat_rounded,
                color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Temperature Threshold',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: enabled
                            ? AppColors.primary.withValues(alpha: 0.2)
                            : (isDark
                                ? Colors.white10
                                : Colors.black.withValues(alpha: 0.05)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$_autoTemp°C',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: enabled
                              ? AppColors.primary
                              : (isDark
                                  ? Colors.white38
                                  : Colors.black38),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Turn off AC when room temp drops below $_autoTemp°C',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: descColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Stepper: -  [Temp]  +
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E293B)
                  : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: enabled
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : (isDark ? Colors.white12 : Colors.black12),
                width: 1,
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Decrease button (-)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _autoTemp <= 16
                        ? null
                        : () => _updateAutoTemp(
                            _autoTemp - 1, setModalState),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(
                        Icons.remove_rounded,
                        size: 16,
                        color: _autoTemp <= 16
                            ? (isDark
                                ? Colors.white24
                                : Colors.black26)
                            : (enabled
                                ? (isDark
                                    ? Colors.white
                                    : AppColors.textPrimary)
                                : (isDark
                                    ? Colors.white38
                                    : Colors.black38)),
                      ),
                    ),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 28),
                  alignment: Alignment.center,
                  child: Text(
                    '$_autoTemp°',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: enabled
                          ? AppColors.primary
                          : (isDark
                              ? Colors.white54
                              : Colors.black45),
                    ),
                  ),
                ),
                // Increase button (+)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _autoTemp >= 30
                        ? null
                        : () => _updateAutoTemp(
                            _autoTemp + 1, setModalState),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: _autoTemp >= 30
                            ? (isDark
                                ? Colors.white24
                                : Colors.black26)
                            : (enabled
                                ? (isDark
                                    ? Colors.white
                                    : AppColors.textPrimary)
                                : (isDark
                                    ? Colors.white38
                                    : Colors.black38)),
                      ),
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
}
