part of '../../ac_control_page.dart';

extension _ACControlSchedulesSheet on _ACControlPageState {
  Future<void> _showSchedulesSheet(BuildContext context, bool isDark) async {
    await _loadCachedSchedules();
    if (!mounted) return;
    showModalBottomSheet(
      context: this.context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        int activeTab = 0;
        final cardBg =
            isDark ? AppColors.backgroundDark : const Color(0xFFF1F5F9);
        final textCol = isDark ? Colors.white : AppColors.textPrimary;
        final subtextCol = isDark ? Colors.white38 : Colors.black45;

        return StreamBuilder<SirisDeviceState>(
          stream: _mqtt.stateStream.where(_isStateForActiveDevice),
          initialData: _mqtt.getLastStateFor(_effectiveDeviceId) ??
              (_mqtt.lastState != null &&
                      _isStateForActiveDevice(_mqtt.lastState!)
                  ? _mqtt.lastState
                  : null),
          builder: (context, snapshot) {
            final state = snapshot.data;
            final String schOn1 = (_savedSchOn[1] != null &&
                    _savedSchOn[1] != 'DISABLED' &&
                    _savedSchOn[1]!.isNotEmpty)
                ? _savedSchOn[1]!
                : (state?.schOn1 ?? _schOn1);
            final String schOff1 = (_savedSchOff[1] != null &&
                    _savedSchOff[1] != 'DISABLED' &&
                    _savedSchOff[1]!.isNotEmpty)
                ? _savedSchOff[1]!
                : (state?.schOff1 ?? _schOff1);
            final String schOn2 = (_savedSchOn[2] != null &&
                    _savedSchOn[2] != 'DISABLED' &&
                    _savedSchOn[2]!.isNotEmpty)
                ? _savedSchOn[2]!
                : (state?.schOn2 ?? _schOn2);
            final String schOff2 = (_savedSchOff[2] != null &&
                    _savedSchOff[2] != 'DISABLED' &&
                    _savedSchOff[2]!.isNotEmpty)
                ? _savedSchOff[2]!
                : (state?.schOff2 ?? _schOff2);
            final String schOn3 = (_savedSchOn[3] != null &&
                    _savedSchOn[3] != 'DISABLED' &&
                    _savedSchOn[3]!.isNotEmpty)
                ? _savedSchOn[3]!
                : (state?.schOn3 ?? _schOn3);
            final String schOff3 = (_savedSchOff[3] != null &&
                    _savedSchOff[3] != 'DISABLED' &&
                    _savedSchOff[3]!.isNotEmpty)
                ? _savedSchOff[3]!
                : (state?.schOff3 ?? _schOff3);
            final String schOn4 = (_savedSchOn[4] != null &&
                    _savedSchOn[4] != 'DISABLED' &&
                    _savedSchOn[4]!.isNotEmpty)
                ? _savedSchOn[4]!
                : (state?.schOn4 ?? _schOn4);
            final String schOff4 = (_savedSchOff[4] != null &&
                    _savedSchOff[4] != 'DISABLED' &&
                    _savedSchOff[4]!.isNotEmpty)
                ? _savedSchOff[4]!
                : (state?.schOff4 ?? _schOff4);
            final String schOn5 = (_savedSchOn[5] != null &&
                    _savedSchOn[5] != 'DISABLED' &&
                    _savedSchOn[5]!.isNotEmpty)
                ? _savedSchOn[5]!
                : (state?.schOn5 ?? _schOn5);
            final String schOff5 = (_savedSchOff[5] != null &&
                    _savedSchOff[5] != 'DISABLED' &&
                    _savedSchOff[5]!.isNotEmpty)
                ? _savedSchOff[5]!
                : (state?.schOff5 ?? _schOff5);
            final String schOnLunch = (_savedSchOn[0] != null &&
                    _savedSchOn[0] != 'DISABLED' &&
                    _savedSchOn[0]!.isNotEmpty)
                ? _savedSchOn[0]!
                : (state?.lunchOn ?? _lunchOn);
            final String schOffLunch = (_savedSchOff[0] != null &&
                    _savedSchOff[0] != 'DISABLED' &&
                    _savedSchOff[0]!.isNotEmpty)
                ? _savedSchOff[0]!
                : (state?.lunchOff ?? _lunchOff);

            if (state != null) {
              _syncSavedScheduleTimes(state);
            }

            // Sync overrides with telemetry — clear override only when hardware confirms
            final Map<int, String> slotOnMap = {
              1: schOn1,
              2: schOn2,
              3: schOn3,
              4: schOn4,
              5: schOn5
            };
            final Map<int, String> slotOffMap = {
              1: schOff1,
              2: schOff2,
              3: schOff3,
              4: schOff4,
              5: schOff5
            };
            for (int slot in List.from(_schSwitchOverrides.keys)) {
              if (slot == 0) {
                final bool telemetryActive =
                    (schOnLunch != 'DISABLED' || schOffLunch != 'DISABLED');
                if (_schSwitchOverrides[0] == telemetryActive) {
                  _schSwitchOverrides.remove(0);
                  _schOverrideTimers[0]?.cancel();
                  _schOverrideTimers.remove(0);
                }
              } else {
                final bool telemetryActive = (slotOnMap[slot] != 'DISABLED' ||
                    slotOffMap[slot] != 'DISABLED');
                if (_schSwitchOverrides[slot] == telemetryActive) {
                  _schSwitchOverrides.remove(slot);
                  _schOverrideTimers[slot]?.cancel();
                  _schOverrideTimers.remove(slot);
                }
              }
            }

            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                return Container(
                  height: MediaQuery.of(context).size.height * 0.7,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white12 : Colors.black12,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Schedules',
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: textCol,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              _showSseInfoDialog(context, isDark);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _mqtt.isSseConnected
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _mqtt.isSseConnected
                                      ? Colors.green.withValues(alpha: 0.3)
                                      : Colors.red.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: _mqtt.isSseConnected
                                          ? Colors.green
                                          : Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _mqtt.isSseConnected ? 'Live' : 'Offline',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _mqtt.isSseConnected
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      // SSE Stream Status Banner
                      if (_mqtt.sseLastDataTime != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.04)
                                : const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : const Color(0xFFD0DBFF),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.sensors_rounded,
                                size: 16,
                                color: _mqtt.isSseConnected
                                    ? AppColors.primary
                                    : (isDark
                                        ? Colors.white30
                                        : Colors.black26),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Last sync: ${_formatLastSeen(_mqtt.sseLastDataTime!)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  if (!_isControlAvailable) {
                                    _showSnack(
                                        'Device is offline. Connect to Wi-Fi to refresh schedules.',
                                        AppColors.offline,
                                        icon: Icons.wifi_off_rounded);
                                    return;
                                  }
                                  _mqtt.getScheduleStatus(
                                      targetDeviceId: _effectiveDeviceId);
                                  _showSnack('Refreshing schedules...',
                                      AppColors.primary);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Custom Tab Selector
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    activeTab = 0;
                                  });
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: activeTab == 0
                                        ? (isDark
                                            ? AppColors.surfaceDark
                                            : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: activeTab == 0
                                        ? [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : [],
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Daily Schedule',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: activeTab == 0
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: activeTab == 0
                                            ? textCol
                                            : subtextCol,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    activeTab = 1;
                                  });
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: activeTab == 1
                                        ? (isDark
                                            ? AppColors.surfaceDark
                                            : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: activeTab == 1
                                        ? [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : [],
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Lunch Period',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: activeTab == 1
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: activeTab == 1
                                            ? textCol
                                            : subtextCol,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                          child: activeTab == 0
                              ? ListView.builder(
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: 5,
                                  itemBuilder: (context, idx) {
                                    final int slot = idx + 1;
                                    String schOn;
                                    String schOff;
                                    String? schDays;
                                    if (slot == 1) {
                                      schOn = schOn1;
                                      schOff = schOff1;
                                      schDays = state?.schDays1;
                                    } else if (slot == 2) {
                                      schOn = schOn2;
                                      schOff = schOff2;
                                      schDays = state?.schDays2;
                                    } else if (slot == 3) {
                                      schOn = schOn3;
                                      schOff = schOff3;
                                      schDays = state?.schDays3;
                                    } else if (slot == 4) {
                                      schOn = schOn4;
                                      schOff = schOff4;
                                      schDays = state?.schDays4;
                                    } else {
                                      schOn = schOn5;
                                      schOff = schOff5;
                                      schDays = state?.schDays5;
                                    }

                                    final overrideTime =
                                        _userSchOverrideTime[slot];
                                    final bool isOverrideActive =
                                        overrideTime != null &&
                                            DateTime.now()
                                                    .difference(overrideTime)
                                                    .inSeconds <
                                                60;

                                    String defRawOn = '08:00';
                                    String defRawOff = '13:00';

                                    if (slot == 2) {
                                      defRawOn = '18:00';
                                      defRawOff = '23:00';
                                    } else if (slot == 3) {
                                      defRawOn = '09:00';
                                      defRawOff = '17:00';
                                    } else if (slot == 4) {
                                      defRawOn = '07:00';
                                      defRawOff = '15:00';
                                    } else if (slot == 5) {
                                      defRawOn = '10:00';
                                      defRawOff = '19:00';
                                    }

                                    final String rawOnTime =
                                        (isOverrideActive &&
                                                _savedSchOn[slot] != null)
                                            ? _savedSchOn[slot]!
                                            : (_savedSchOn[slot] ??
                                                (schOn != 'DISABLED' &&
                                                        schOn.isNotEmpty &&
                                                        schOn != '--:--'
                                                    ? schOn
                                                    : defRawOn));
                                    final String rawOffTime =
                                        (isOverrideActive &&
                                                _savedSchOff[slot] != null)
                                            ? _savedSchOff[slot]!
                                            : (_savedSchOff[slot] ??
                                                (schOff != 'DISABLED' &&
                                                        schOff.isNotEmpty &&
                                                        schOff != '--:--'
                                                    ? schOff
                                                    : defRawOff));

                                    final bool isSlotActive =
                                        _schEnabled[slot] ??
                                            (_schSwitchOverrides[slot] ??
                                                ((schOn != 'DISABLED' &&
                                                        schOn.isNotEmpty &&
                                                        schOn != '--:--') ||
                                                    (schOff != 'DISABLED' &&
                                                        schOff.isNotEmpty &&
                                                        schOff != '--:--')));

                                    final String onTimeDisplay =
                                        _formatTo12Hour(rawOnTime);
                                    final String offTimeDisplay =
                                        _formatTo12Hour(rawOffTime);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 18, vertical: 16),
                                      decoration: BoxDecoration(
                                        color: cardBg,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isDark
                                              ? AppColors.dividerDark
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Slot Title and Master Switch
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Schedule Slot $slot',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: textCol,
                                                ),
                                              ),
                                              Switch(
                                                value: isSlotActive,
                                                activeThumbColor: AppColors.primary,
                                                onChanged: (val) {
                                                  if (!_isControlAvailable) {
                                                    _showSnack(
                                                        'Device is offline. Connect to Wi-Fi to change schedules.',
                                                        AppColors.offline,
                                                        icon: Icons.wifi_off_rounded);
                                                    return;
                                                  }
                                                  _userSchOverrideTime[slot] =
                                                      DateTime.now();
                                                  final daysToSend = _savedSchDays[
                                                          slot] ??
                                                      ((schDays != null &&
                                                              schDays !=
                                                                  'DISABLED' &&
                                                              schDays
                                                                  .isNotEmpty)
                                                          ? schDays
                                                          : 'ALL');
                                                  _savedSchDays[slot] =
                                                      daysToSend;
                                                  _savedSchOn[slot] = rawOnTime;
                                                  _savedSchOff[slot] =
                                                      rawOffTime;
                                                  _schEnabled[slot] = val;
                                                  setModalState(() {
                                                    _schSwitchOverrides[slot] =
                                                        val;
                                                  });
                                                  updateUI(() {
                                                    _schSwitchOverrides[slot] =
                                                        val;
                                                  });
                                                  LocalCacheService
                                                      .saveScheduleSlotConfig(
                                                    _effectiveDeviceId,
                                                    slot,
                                                    isEnabled: val,
                                                    onTime: rawOnTime,
                                                    offTime: rawOffTime,
                                                    days: daysToSend,
                                                  );

                                                  if (val) {
                                                    _mqtt.setScheduleOn(
                                                        slot, rawOnTime,
                                                        days: daysToSend,
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt.publishScheduleJson({
                                                      'on$slot': rawOnTime,
                                                      'off$slot': rawOffTime,
                                                      'days$slot': daysToSend,
                                                    },
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt
                                                        .updateScheduleOptimistic(
                                                            slot: slot,
                                                            onTime: rawOnTime,
                                                            offTime: rawOffTime,
                                                            days: daysToSend);
                                                    Future.delayed(
                                                        const Duration(
                                                            milliseconds: 400),
                                                        () {
                                                      _mqtt.setScheduleOff(
                                                          slot, rawOffTime,
                                                          days: daysToSend,
                                                          targetDeviceId:
                                                              _effectiveDeviceId);
                                                      _mqtt
                                                          .updateScheduleOptimistic(
                                                              slot: slot,
                                                              onTime: rawOnTime,
                                                              offTime:
                                                                  rawOffTime,
                                                              days: daysToSend);
                                                    });
                                                  } else {
                                                    _mqtt.clearScheduleSlot(
                                                        slot,
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt.publishScheduleJson({
                                                      'on$slot': 'DISABLED',
                                                      'off$slot': 'DISABLED',
                                                    },
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt
                                                        .updateScheduleOptimistic(
                                                            slot: slot,
                                                            clear: true);
                                                  }
                                                  Future.delayed(
                                                      const Duration(
                                                          milliseconds: 1500),
                                                      () {
                                                    _mqtt.getScheduleStatus(
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                  });
                                                  Future.delayed(
                                                      const Duration(
                                                          milliseconds: 4000),
                                                      () {
                                                    _mqtt.getScheduleStatus(
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),

                                          // ON and OFF Times Side-by-Side
                                          Row(
                                            children: [
                                              // ON Time block
                                              Expanded(
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () {
                                                    _showEditScheduleDialog(
                                                      context,
                                                      slot,
                                                      'ON',
                                                      onTimeDisplay,
                                                      isDark,
                                                      setModalState,
                                                    );
                                                  },
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'ON Time',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: subtextCol,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        onTimeDisplay,
                                                        style:
                                                            GoogleFonts.outfit(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: isSlotActive
                                                              ? textCol
                                                              : textCol
                                                                  .withValues(
                                                                      alpha: 0.4),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              // Divider
                                              Container(
                                                height: 30,
                                                width: 1,
                                                color: isDark
                                                    ? Colors.white10
                                                    : Colors.black12,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 16),
                                              ),
                                              // OFF Time block
                                              Expanded(
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () {
                                                    _showEditScheduleDialog(
                                                      context,
                                                      slot,
                                                      'OFF',
                                                      offTimeDisplay,
                                                      isDark,
                                                      setModalState,
                                                    );
                                                  },
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'OFF Time',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: subtextCol,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        offTimeDisplay,
                                                        style:
                                                            GoogleFonts.outfit(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: isSlotActive
                                                              ? textCol
                                                              : textCol
                                                                  .withValues(
                                                                      alpha: 0.4),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          _buildWeeklyDaysSelector(
                                            slot: slot,
                                            isEnabled: isSlotActive,
                                            isDark: isDark,
                                            setModalState: setModalState,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              : SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isDark
                                            ? AppColors.dividerDark
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: () {
                                      final lunchOverrideTime =
                                          _userSchOverrideTime[0];
                                      final bool isLunchOverrideActive =
                                          lunchOverrideTime != null &&
                                              DateTime.now()
                                                      .difference(
                                                          lunchOverrideTime)
                                                      .inSeconds <
                                                  60;

                                      final String rawLunchOn =
                                          (isLunchOverrideActive &&
                                                  _savedSchOn[0] != null)
                                              ? _savedSchOn[0]!
                                              : (_savedSchOn[0] ??
                                                  (schOnLunch != 'DISABLED' &&
                                                          schOnLunch
                                                              .isNotEmpty &&
                                                          schOnLunch != '--:--'
                                                      ? schOnLunch
                                                      : '12:00'));
                                      final String rawLunchOff =
                                          (isLunchOverrideActive &&
                                                  _savedSchOff[0] != null)
                                              ? _savedSchOff[0]!
                                              : (_savedSchOff[0] ??
                                                  (schOffLunch != 'DISABLED' &&
                                                          schOffLunch
                                                              .isNotEmpty &&
                                                          schOffLunch != '--:--'
                                                      ? schOffLunch
                                                      : '13:00'));

                                      final bool isLunchActive =
                                          _schEnabled[0] ??
                                              (_schSwitchOverrides[0] ??
                                                  (schOnLunch != 'DISABLED' ||
                                                      schOffLunch !=
                                                          'DISABLED'));

                                      final String lunchOnDisplay =
                                          _formatTo12Hour(rawLunchOn);
                                      final String lunchOffDisplay =
                                          _formatTo12Hour(rawLunchOff);

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Lunch Title and Switch
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Lunch Period',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: textCol,
                                                ),
                                              ),
                                              Switch(
                                                value: isLunchActive,
                                                activeThumbColor: AppColors.primary,
                                                onChanged: (val) {
                                                  if (!_isControlAvailable) {
                                                    _showSnack(
                                                        'Device is offline. Connect to Wi-Fi to change schedules.',
                                                        AppColors.offline,
                                                        icon: Icons.wifi_off_rounded);
                                                    return;
                                                  }
                                                  _userSchOverrideTime[0] =
                                                      DateTime.now();
                                                  final lunchDaysToSend =
                                                      _savedSchDays[0] ?? 'ALL';
                                                  _savedSchDays[0] =
                                                      lunchDaysToSend;
                                                  _savedSchOn[0] = rawLunchOn;
                                                  _savedSchOff[0] = rawLunchOff;
                                                  _schEnabled[0] = val;
                                                  setModalState(() {
                                                    _schSwitchOverrides[0] =
                                                        val;
                                                  });
                                                  updateUI(() {
                                                    _schSwitchOverrides[0] =
                                                        val;
                                                  });
                                                  LocalCacheService
                                                      .saveScheduleSlotConfig(
                                                    _effectiveDeviceId,
                                                    0,
                                                    isEnabled: val,
                                                    onTime: rawLunchOn,
                                                    offTime: rawLunchOff,
                                                    days: lunchDaysToSend,
                                                  );

                                                  if (val) {
                                                    _mqtt.setLunchOn(rawLunchOn,
                                                        days: lunchDaysToSend,
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt.publishScheduleJson({
                                                      'lunch_on': rawLunchOn,
                                                      'lunch_off': rawLunchOff,
                                                      'lunch_days':
                                                          lunchDaysToSend,
                                                    },
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt.updateLunchOptimistic(
                                                        lunchOn: rawLunchOn,
                                                        lunchOff: rawLunchOff,
                                                        days: lunchDaysToSend);
                                                    Future.delayed(
                                                        const Duration(
                                                            milliseconds: 400),
                                                        () {
                                                      _mqtt.setLunchOff(
                                                          rawLunchOff,
                                                          days: lunchDaysToSend,
                                                          targetDeviceId:
                                                              _effectiveDeviceId);
                                                      _mqtt.updateLunchOptimistic(
                                                          lunchOn: rawLunchOn,
                                                          lunchOff: rawLunchOff,
                                                          days:
                                                              lunchDaysToSend);
                                                    });
                                                  } else {
                                                    _mqtt.clearLunchSlot(
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt.publishScheduleJson({
                                                      'lunch_on': 'DISABLED',
                                                      'lunch_off': 'DISABLED',
                                                    },
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                    _mqtt.updateLunchOptimistic(
                                                        clear: true);
                                                  }
                                                  _showSnack(
                                                      val
                                                          ? 'Lunch Period enabled'
                                                          : 'Lunch Period cleared',
                                                      val
                                                          ? AppColors.online
                                                          : AppColors.warning);
                                                  Future.delayed(
                                                      const Duration(
                                                          milliseconds: 1500),
                                                      () {
                                                    _mqtt.getScheduleStatus(
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                  });
                                                  Future.delayed(
                                                      const Duration(
                                                          milliseconds: 4000),
                                                      () {
                                                    _mqtt.getScheduleStatus(
                                                        targetDeviceId:
                                                            _effectiveDeviceId);
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),

                                          // ON and OFF Times Side-by-Side
                                          Row(
                                            children: [
                                              // ON Time block
                                              Expanded(
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () {
                                                    _showEditScheduleDialog(
                                                      context,
                                                      0,
                                                      'ON',
                                                      lunchOnDisplay,
                                                      isDark,
                                                      setModalState,
                                                    );
                                                  },
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'ON Time',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: subtextCol,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        lunchOnDisplay,
                                                        style:
                                                            GoogleFonts.outfit(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: isLunchActive
                                                              ? textCol
                                                              : textCol
                                                                  .withValues(
                                                                      alpha: 0.4),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              // Divider
                                              Container(
                                                height: 30,
                                                width: 1,
                                                color: isDark
                                                    ? Colors.white10
                                                    : Colors.black12,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 16),
                                              ),
                                              // OFF Time block
                                              Expanded(
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () {
                                                    _showEditScheduleDialog(
                                                      context,
                                                      0,
                                                      'OFF',
                                                      lunchOffDisplay,
                                                      isDark,
                                                      setModalState,
                                                    );
                                                  },
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'OFF Time',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: subtextCol,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        lunchOffDisplay,
                                                        style:
                                                            GoogleFonts.outfit(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: isLunchActive
                                                              ? textCol
                                                              : textCol
                                                                  .withValues(
                                                                      alpha: 0.4),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          _buildWeeklyDaysSelector(
                                            slot: 0,
                                            isEnabled: isLunchActive,
                                            isDark: isDark,
                                            setModalState: setModalState,
                                          ),
                                        ],
                                      );
                                    }(),
                                  ),
                                )),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
