import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';

List<String> parseScheduleDaysList(String? rawDays) {
  if (rawDays == null || rawDays.isEmpty || rawDays.toUpperCase() == 'ALL') {
    return ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  }
  if (rawDays.toUpperCase() == 'DISABLED') {
    return [];
  }
  final tokens =
      rawDays.toUpperCase().split(',').map((s) => s.trim()).toList();
  const allDays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  final matched = allDays.where((d) => tokens.contains(d)).toList();
  return matched.isEmpty ? List.from(allDays) : matched;
}

String formatScheduleDaysSummary(List<String> activeDays) {
  if (activeDays.length == 7) {
    return 'Everyday (All 7 Days)';
  }
  if (activeDays.length == 5 &&
      activeDays.contains('MON') &&
      activeDays.contains('TUE') &&
      activeDays.contains('WED') &&
      activeDays.contains('THU') &&
      activeDays.contains('FRI')) {
    return 'Weekdays (Mon - Fri)';
  }
  if (activeDays.length == 2 &&
      activeDays.contains('SAT') &&
      activeDays.contains('SUN')) {
    return 'Weekend (Sat, Sun)';
  }
  if (activeDays.isEmpty) {
    return 'No days selected';
  }
  const nameMap = {
    'MON': 'Mon',
    'TUE': 'Tue',
    'WED': 'Wed',
    'THU': 'Thu',
    'FRI': 'Fri',
    'SAT': 'Sat',
    'SUN': 'Sun'
  };
  return activeDays.map((d) => nameMap[d] ?? d).join(', ');
}

Widget buildWeeklyDaysSelector({
  required int slot,
  required String currentDays,
  bool isEnabled = true,
  required bool isDark,
  required bool isControlAvailable,
  required bool isActive,
  required bool isBluetoothConnected,
  required String effectiveDeviceId,
  required MqttService mqtt,
  required StateSetter setModalState,
  required void Function(int slot, String formattedDays) onDaysChanged,
  required void Function(String message, Color color, {IconData? icon}) showSnack,
}) {
  final List<String> activeDays = parseScheduleDaysList(currentDays);
  final String summaryText = formatScheduleDaysSummary(activeDays);

  const List<String> dayKeys = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN'
  ];
  const List<String> dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  void updateDays(List<String> newDays) {
    if (!isEnabled) {
      showSnack(
        slot == 0
            ? 'Please turn on Lunch Period first'
            : 'Please turn on Schedule Slot $slot first',
        AppColors.warning,
      );
      return;
    }
    if (!isControlAvailable || (!isActive && !isBluetoothConnected)) {
      showSnack(
        'Device is offline. Connect to Wi-Fi to update schedules.',
        AppColors.offline,
        icon: Icons.wifi_off_rounded,
      );
      return;
    }
    final formattedDays = newDays.length == 7
        ? 'ALL'
        : (newDays.isEmpty ? 'DISABLED' : newDays.join(','));

    onDaysChanged(slot, formattedDays);

    LocalCacheService.saveScheduleSlotConfig(
      effectiveDeviceId,
      slot,
      days: formattedDays,
    );

    if (slot == 0) {
      mqtt.publishScheduleJson({
        'lunch_days': formattedDays,
      }, targetDeviceId: effectiveDeviceId);
      mqtt.updateLunchOptimistic(days: formattedDays);
    } else {
      mqtt.publishScheduleJson({
        'days$slot': formattedDays,
      }, targetDeviceId: effectiveDeviceId);
      mqtt.updateScheduleOptimistic(slot: slot, days: formattedDays);
    }

    final updatedSummary = formatScheduleDaysSummary(newDays);
    showSnack(
      slot == 0
          ? 'Lunch schedule days updated ($updatedSummary)'
          : 'Schedule Slot $slot days updated ($updatedSummary)',
      AppColors.online,
    );
  }

  return Opacity(
    opacity: isEnabled ? 1.0 : 0.6,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: isEnabled
                  ? const Color(0xFF10B981)
                  : (isDark ? Colors.white30 : Colors.black26),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                summaryText,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isEnabled
                      ? (isDark ? Colors.white70 : AppColors.textPrimary)
                      : (isDark ? Colors.white38 : Colors.black38),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(7, (i) {
            final dayKey = dayKeys[i];
            final dayLabel = dayLabels[i];
            final bool isSelected = activeDays.contains(dayKey);

            Color chipBg;
            Color chipText;
            if (isEnabled) {
              chipBg = isSelected
                  ? const Color(0xFF10B981)
                  : (isDark
                      ? const Color(0xFF222B3D)
                      : const Color(0xFFE2E8F0));
              chipText = isSelected
                  ? Colors.white
                  : (isDark ? Colors.white38 : Colors.black38);
            } else {
              chipBg = isSelected
                  ? (isDark
                      ? const Color(0xFF133E32)
                      : const Color(0xFFD1FAE5))
                  : (isDark
                      ? const Color(0xFF161C28)
                      : const Color(0xFFF1F5F9));
              chipText = isSelected
                  ? (isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF059669))
                  : (isDark
                      ? const Color(0xFF333E52)
                      : const Color(0xFFA0AEC0));
            }

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 6 ? 6.0 : 0.0),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (!isEnabled) {
                      showSnack(
                        slot == 0
                            ? 'Please turn on Lunch Period first'
                            : 'Please turn on Schedule Slot $slot first',
                        AppColors.warning,
                      );
                      return;
                    }
                    final nextDays = List<String>.from(activeDays);
                    if (isSelected) {
                      if (nextDays.length > 1) {
                        nextDays.remove(dayKey);
                      } else {
                        showSnack('At least one day must remain selected',
                            AppColors.warning);
                        return;
                      }
                    } else {
                      nextDays.add(dayKey);
                    }
                    updateDays(nextDays);
                  },
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      dayLabel,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: chipText,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    ),
  );
}
