part of '../../ac_control_page.dart';

extension _ACControlEditScheduleDialog on _ACControlPageState {

  void _showEditScheduleDialog(BuildContext context, int slot, String type,
      String currentTime, bool isDark, [StateSetter? setModalState]) {
    String default24h = '08:00';
    if (currentTime.contains('AM') || currentTime.contains('PM')) {
      try {
        final parts = currentTime.split(' ');
        final timePart = parts[0];
        final amPm = parts[1];
        final timeParts = timePart.split(':');
        int hour = int.parse(timeParts[0]);
        final int minute = int.parse(timeParts[1]);
        if (amPm == 'PM' && hour < 12) hour += 12;
        if (amPm == 'AM' && hour == 12) hour = 0;
        default24h =
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    } else {
      default24h = currentTime;
    }

    final timeController = TextEditingController(text: default24h);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final textCol = isDark ? Colors.white : AppColors.textPrimary;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            slot == 0
                ? "Configure Lunch ($type)"
                : "Configure Slot $slot ($type)",
            style:
                GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Time (HH:MM in 24h)",
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: timeController,
                      keyboardType: TextInputType.datetime,
                      style: TextStyle(color: textCol),
                      decoration: InputDecoration(
                        hintText: "e.g. 08:30 or 17:45",
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.access_time_rounded,
                        color: AppColors.primary),
                    onPressed: () async {
                      final TimeOfDay? picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (picked != null) {
                        final String formatted = _timeOfDayTo24h(picked);
                        timeController.text = formatted;
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                final String rawInput = timeController.text.trim().toUpperCase();
                final bool isPm = rawInput.contains('PM');
                final bool isAm = rawInput.contains('AM');
                final String clean = rawInput.replaceAll('AM', '').replaceAll('PM', '').trim();
                final regExp = RegExp(r'^([01]?[0-9]|2[0-3]):[0-5][0-9]$');
                if (!regExp.hasMatch(clean)) {
                  _showSnack(
                      "Invalid time format. Use HH:MM or HH:MM AM/PM", AppColors.offline);
                  return;
                }

                final parts = clean.split(':');
                int hour = int.parse(parts[0]);
                final int minute = int.parse(parts[1]);
                if (isPm && hour < 12) hour += 12;
                if (isAm && hour == 12) hour = 0;

                String time =
                    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

                // Check device connection before sending
                if (!_isControlAvailable) {
                  _showSnack(
                      'Device is offline. Connect to Wi-Fi to configure schedules.',
                      AppColors.offline,
                      icon: Icons.wifi_off_rounded);
                  return;
                }

                if (slot == 0) {
                  final curLunchDays = _savedSchDays[0] ?? 'ALL';
                  _userSchOverrideTime[0] = DateTime.now();
                  _schEnabled[0] = true;
                  _schSwitchOverrides[0] = true;
                  if (type == 'ON') {
                    _savedSchOn[0] = time;
                    final curLunchOff = (_savedSchOff[0] != null &&
                            _savedSchOff[0] != 'DISABLED' &&
                            _savedSchOff[0]!.isNotEmpty &&
                            _savedSchOff[0] != '--:--')
                        ? _savedSchOff[0]!
                        : '13:00';
                    _savedSchOff[0] = curLunchOff;
                    LocalCacheService.saveScheduleSlotConfig(
                        _effectiveDeviceId, 0,
                        isEnabled: true,
                        onTime: time,
                        offTime: curLunchOff,
                        days: curLunchDays);
                    _mqtt.setLunchOn(time,
                        days: curLunchDays, targetDeviceId: _effectiveDeviceId);
                    _mqtt.publishScheduleJson({
                      'lunch_on': time,
                      'lunch_off': curLunchOff,
                      'lunch_days': curLunchDays,
                    }, targetDeviceId: _effectiveDeviceId);
                    _mqtt.updateLunchOptimistic(
                        lunchOn: time,
                        lunchOff: curLunchOff,
                        days: curLunchDays);
                    updateUI(() => _lunchOn = time);
                    if (setModalState != null) setModalState(() {});
                  } else {
                    _savedSchOff[0] = time;
                    final curLunchOn = (_savedSchOn[0] != null &&
                            _savedSchOn[0] != 'DISABLED' &&
                            _savedSchOn[0]!.isNotEmpty &&
                            _savedSchOn[0] != '--:--')
                        ? _savedSchOn[0]!
                        : '12:00';
                    _savedSchOn[0] = curLunchOn;
                    LocalCacheService.saveScheduleSlotConfig(
                        _effectiveDeviceId, 0,
                        isEnabled: true,
                        onTime: curLunchOn,
                        offTime: time,
                        days: curLunchDays);
                    _mqtt.setLunchOff(time,
                        days: curLunchDays, targetDeviceId: _effectiveDeviceId);
                    _mqtt.publishScheduleJson({
                      'lunch_on': curLunchOn,
                      'lunch_off': time,
                      'lunch_days': curLunchDays,
                    }, targetDeviceId: _effectiveDeviceId);
                    _mqtt.updateLunchOptimistic(
                        lunchOn: curLunchOn,
                        lunchOff: time,
                        days: curLunchDays);
                    updateUI(() => _lunchOff = time);
                    if (setModalState != null) setModalState(() {});
                  }
                  Navigator.pop(context);
                  _showSnack('Lunch $type set to ${_formatTo12Hour(time)}',
                      AppColors.primary);
                } else {
                  final fallbackOn = (slot == 2
                      ? '18:00'
                      : slot == 3
                          ? '09:00'
                          : slot == 4
                              ? '07:00'
                              : slot == 5
                                  ? '10:00'
                                  : '08:00');
                  final fallbackOff = (slot == 2
                      ? '23:00'
                      : slot == 3
                          ? '17:00'
                          : slot == 4
                              ? '15:00'
                              : slot == 5
                                  ? '19:00'
                                  : '13:00');
                  final curDays = _savedSchDays[slot] ?? 'ALL';
                  _userSchOverrideTime[slot] = DateTime.now();
                  _schEnabled[slot] = true;
                  if (type == 'ON') {
                    _savedSchOn[slot] = time;
                    final curOff = (_savedSchOff[slot] != null &&
                            _savedSchOff[slot] != 'DISABLED' &&
                            _savedSchOff[slot]!.isNotEmpty &&
                            _savedSchOff[slot] != '--:--')
                        ? _savedSchOff[slot]!
                        : fallbackOff;
                    _savedSchOff[slot] = curOff;
                    LocalCacheService.saveScheduleSlotConfig(
                        _effectiveDeviceId, slot,
                        isEnabled: true,
                        onTime: time,
                        offTime: curOff,
                        days: curDays);
                    _mqtt.setScheduleOn(slot, time,
                        days: curDays, targetDeviceId: _effectiveDeviceId);
                    _mqtt.publishScheduleJson({
                      'on$slot': time,
                      'off$slot': curOff,
                      'days$slot': curDays,
                    }, targetDeviceId: _effectiveDeviceId);
                    _mqtt.updateScheduleOptimistic(
                        slot: slot,
                        onTime: time,
                        offTime: curOff,
                        days: curDays);
                    updateUI(() {
                      if (slot == 1) {
                        _schOn1 = time;
                      } else if (slot == 2) {
                        _schOn2 = time;
                      } else if (slot == 3) {
                        _schOn3 = time;
                      } else if (slot == 4) {
                        _schOn4 = time;
                      } else if (slot == 5) {
                        _schOn5 = time;
                      }
                    });
                    if (setModalState != null) setModalState(() {});
                  } else {
                    _savedSchOff[slot] = time;
                    final curOn = (_savedSchOn[slot] != null &&
                            _savedSchOn[slot] != 'DISABLED' &&
                            _savedSchOn[slot]!.isNotEmpty &&
                            _savedSchOn[slot] != '--:--')
                        ? _savedSchOn[slot]!
                        : fallbackOn;
                    _savedSchOn[slot] = curOn;
                    LocalCacheService.saveScheduleSlotConfig(
                        _effectiveDeviceId, slot,
                        isEnabled: true,
                        onTime: curOn,
                        offTime: time,
                        days: curDays);
                    _mqtt.setScheduleOff(slot, time,
                        days: curDays, targetDeviceId: _effectiveDeviceId);
                    _mqtt.publishScheduleJson({
                      'on$slot': curOn,
                      'off$slot': time,
                      'days$slot': curDays,
                    }, targetDeviceId: _effectiveDeviceId);
                    _mqtt.updateScheduleOptimistic(
                        slot: slot,
                        onTime: curOn,
                        offTime: time,
                        days: curDays);
                    updateUI(() {
                      if (slot == 1) {
                        _schOff1 = time;
                      } else if (slot == 2) {
                        _schOff2 = time;
                      } else if (slot == 3) {
                        _schOff3 = time;
                      } else if (slot == 4) {
                        _schOff4 = time;
                      } else if (slot == 5) {
                        _schOff5 = time;
                      }
                    });
                    if (setModalState != null) setModalState(() {});
                  }
                  Navigator.pop(context);
                  _showSnack(
                      'Schedule $type set to ${_formatTo12Hour(time)} for Slot $slot',
                      AppColors.primary);
                }

                // Query status after a delay to confirm device received the command
                Future.delayed(const Duration(milliseconds: 800), () {
                  _mqtt.getScheduleStatus(targetDeviceId: _effectiveDeviceId);
                });
                // Second query for slower hardware
                Future.delayed(const Duration(milliseconds: 2500), () {
                  _mqtt.getScheduleStatus(targetDeviceId: _effectiveDeviceId);
                });
              },
              child: const Text("Save",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.green)),
            ),
          ],
        );
      },
    );
  }
}
