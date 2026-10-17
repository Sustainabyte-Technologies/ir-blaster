import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';

/// ─── Schedule Calendar Page ─────────────────────────────────────────────────
/// Full-page schedule management with day-of-week support.
/// Uses the SIRIS 2.0 JSON schedule API to publish changes.
class ScheduleCalendarPage extends StatefulWidget {
  final String deviceName;
  final SirisDeviceState? initialState;

  const ScheduleCalendarPage({
    super.key,
    required this.deviceName,
    this.initialState,
  });

  @override
  State<ScheduleCalendarPage> createState() => _ScheduleCalendarPageState();
}

class _ScheduleCalendarPageState extends State<ScheduleCalendarPage>
    with SingleTickerProviderStateMixin {
  // Constants
  static const _kDayLabels = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  static const _kDayLetters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const _kPrimary = Color(0xFF6CC042);
  static const _kBg = Color(0xFF0F0C1B);
  static const _kCardBg = Color(0xFF1A1730);
  static const _kLunchColor = Color(0xFFF59E0B);
  static const _kDisabledColor = Color(0xFF3A3650);

  // Slot data: 5 schedule slots + 1 lunch = 6 total
  // Each slot: {on, off, days, enabled}
  late List<_SlotData> _slots;
  late _SlotData _lunchSlot;

  // Original state to diff against
  late List<_SlotData> _originalSlots;
  late _SlotData _originalLunch;

  // Tab: 0 = Schedules, 1 = Lunch
  int _activeTab = 0;

  // Expanded slot index (-1 = none)
  int _expandedSlot = -1;

  // MQTT
  final MqttService _mqtt = MqttService();
  StreamSubscription<SirisResponse>? _responseSub;
  bool _isSaving = false;
  String? _saveMessage;

  late AnimationController _saveAnimController;

  @override
  void initState() {
    super.initState();
    _saveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _initSlotsFromState(widget.initialState ?? _mqtt.lastState);

    // Listen for schedule responses
    _responseSub = _mqtt.responseStream.listen(_onMqttResponse);
  }

  void _initSlotsFromState(SirisDeviceState? state) {
    _slots = List.generate(5, (i) {
      final idx = i + 1;
      String on = 'DISABLED', off = 'DISABLED', days = 'ALL';
      if (state != null) {
        on = _getSlotOn(state, idx);
        off = _getSlotOff(state, idx);
        days = _getSlotDays(state, idx);
      }
      final defOn = idx == 1 ? '08:00' : idx == 2 ? '18:00' : idx == 3 ? '09:00' : idx == 4 ? '07:00' : '10:00';
      final defOff = idx == 1 ? '13:00' : idx == 2 ? '23:00' : idx == 3 ? '17:00' : idx == 4 ? '15:00' : '19:00';
      return _SlotData(
        on: on,
        off: off,
        days: days,
        lastOn: (on != 'DISABLED' && on != '--:--') ? on : defOn,
        lastOff: (off != 'DISABLED' && off != '--:--') ? off : defOff,
      );
    });

    final lunchOn = state?.lunchOn ?? 'DISABLED';
    final lunchOff = state?.lunchOff ?? 'DISABLED';
    _lunchSlot = _SlotData(
      on: lunchOn,
      off: lunchOff,
      days: state?.lunchDays ?? 'ALL',
      lastOn: (lunchOn != 'DISABLED' && lunchOn != '--:--') ? lunchOn : '12:00',
      lastOff: (lunchOff != 'DISABLED' && lunchOff != '--:--') ? lunchOff : '13:00',
    );

    // Deep copy originals for diffing
    _originalSlots = _slots.map((s) => s.copy()).toList();
    _originalLunch = _lunchSlot.copy();
    _loadCachedTimes();
  }

  Future<void> _loadCachedTimes() async {
    if (widget.deviceName.isEmpty) return;
    for (int i = 0; i < 5; i++) {
      final idx = i + 1;
      final cfg = await LocalCacheService.getScheduleSlotConfig(widget.deviceName, idx);
      if (cfg != null) {
        if (cfg['onTime'] != null && cfg['onTime']!.isNotEmpty) {
          _slots[i].lastOn = cfg['onTime']!;
        }
        if (cfg['offTime'] != null && cfg['offTime']!.isNotEmpty) {
          _slots[i].lastOff = cfg['offTime']!;
        }
        if (cfg['days'] != null && cfg['days']!.isNotEmpty && cfg['days'] != 'DISABLED') {
          _slots[i].days = cfg['days']!;
        }
      }
    }
    final lunchCfg = await LocalCacheService.getScheduleSlotConfig(widget.deviceName, 0);
    if (lunchCfg != null) {
      if (lunchCfg['onTime'] != null && lunchCfg['onTime']!.isNotEmpty) {
        _lunchSlot.lastOn = lunchCfg['onTime']!;
      }
      if (lunchCfg['offTime'] != null && lunchCfg['offTime']!.isNotEmpty) {
        _lunchSlot.lastOff = lunchCfg['offTime']!;
      }
      if (lunchCfg['days'] != null && lunchCfg['days']!.isNotEmpty && lunchCfg['days'] != 'DISABLED') {
        _lunchSlot.days = lunchCfg['days']!;
      }
    }
    if (mounted) setState(() {});
  }

  String _getSlotOn(SirisDeviceState s, int idx) {
    switch (idx) {
      case 1: return s.schOn1;
      case 2: return s.schOn2;
      case 3: return s.schOn3;
      case 4: return s.schOn4;
      case 5: return s.schOn5;
      default: return 'DISABLED';
    }
  }

  String _getSlotOff(SirisDeviceState s, int idx) {
    switch (idx) {
      case 1: return s.schOff1;
      case 2: return s.schOff2;
      case 3: return s.schOff3;
      case 4: return s.schOff4;
      case 5: return s.schOff5;
      default: return 'DISABLED';
    }
  }

  String _getSlotDays(SirisDeviceState s, int idx) {
    switch (idx) {
      case 1: return s.schDays1;
      case 2: return s.schDays2;
      case 3: return s.schDays3;
      case 4: return s.schDays4;
      case 5: return s.schDays5;
      default: return 'ALL';
    }
  }

  @override
  void dispose() {
    _responseSub?.cancel();
    _saveAnimController.dispose();
    super.dispose();
  }

  void _onMqttResponse(SirisResponse response) {
    if (!mounted) return;
    if (response.type == SirisResponseType.scheduleUpdated) {
      setState(() {
        _isSaving = false;
        _saveMessage = 'Schedule updated successfully!';
      });
      _clearMessageAfterDelay();
    } else if (response.type == SirisResponseType.scheduleUpdatedWithErrors) {
      setState(() {
        _isSaving = false;
        _saveMessage = 'Saved with warnings: ${response.detail ?? "some day fields skipped"}';
      });
      _clearMessageAfterDelay();
    } else if (response.type == SirisResponseType.scheduleError) {
      setState(() {
        _isSaving = false;
        _saveMessage = 'Error: invalid JSON payload';
      });
      _clearMessageAfterDelay();
    }
  }

  void _clearMessageAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _saveMessage = null);
    });
  }

  // ── Build JSON payload from diff ────────────────────────────────────────
  Map<String, dynamic> _buildPayload() {
    final payload = <String, dynamic>{};

    for (int i = 0; i < 5; i++) {
      final idx = i + 1;
      final cur = _slots[i];
      final orig = _originalSlots[i];

      if (cur.on != orig.on) payload['on$idx'] = cur.on;
      if (cur.off != orig.off) payload['off$idx'] = cur.off;
      if (cur.days != orig.days) payload['days$idx'] = cur.days;
      if (cur.date != orig.date && cur.date != null) payload['date$idx'] = cur.date;
    }

    if (_lunchSlot.on != _originalLunch.on) payload['lunch_on'] = _lunchSlot.on;
    if (_lunchSlot.off != _originalLunch.off) payload['lunch_off'] = _lunchSlot.off;
    if (_lunchSlot.days != _originalLunch.days) payload['lunch_days'] = _lunchSlot.days;

    return payload;
  }

  bool get _hasChanges => _buildPayload().isNotEmpty;

  Future<void> _saveSchedule() async {
    final payload = _buildPayload();
    if (payload.isEmpty) {
      setState(() => _saveMessage = 'No changes to save');
      _clearMessageAfterDelay();
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    // Optimistically update local state
    _mqtt.updateFullScheduleOptimistic(
      schOn1: _slots[0].on, schOff1: _slots[0].off, schDays1: _slots[0].days,
      schOn2: _slots[1].on, schOff2: _slots[1].off, schDays2: _slots[1].days,
      schOn3: _slots[2].on, schOff3: _slots[2].off, schDays3: _slots[2].days,
      schOn4: _slots[3].on, schOff4: _slots[3].off, schDays4: _slots[3].days,
      schOn5: _slots[4].on, schOff5: _slots[4].off, schDays5: _slots[4].days,
      lunchOn: _lunchSlot.on, lunchOff: _lunchSlot.off, lunchDays: _lunchSlot.days,
    );

    // Also dispatch explicit text commands for firmware compatibility
    for (int i = 0; i < 5; i++) {
      final idx = i + 1;
      final cur = _slots[i];
      final orig = _originalSlots[i];
      if (cur.on != orig.on || cur.off != orig.off || cur.days != orig.days || cur.date != orig.date) {
        if (cur.on != 'DISABLED' && cur.off != 'DISABLED' && cur.on != '--:--' && cur.off != '--:--') {
          _mqtt.setScheduleOn(idx, cur.on, days: cur.days, date: cur.date, targetDeviceId: widget.deviceName);
          _mqtt.setScheduleOff(idx, cur.off, days: cur.days, date: cur.date, targetDeviceId: widget.deviceName);
        } else if (cur.on == 'DISABLED' && cur.off == 'DISABLED') {
          _mqtt.clearScheduleSlot(idx, targetDeviceId: widget.deviceName);
        }
      }
    }
    if (_lunchSlot.on != _originalLunch.on || _lunchSlot.off != _originalLunch.off || _lunchSlot.days != _originalLunch.days) {
      if (_lunchSlot.on != 'DISABLED' && _lunchSlot.off != 'DISABLED' && _lunchSlot.on != '--:--' && _lunchSlot.off != '--:--') {
        _mqtt.setLunchOn(_lunchSlot.on, days: _lunchSlot.days, targetDeviceId: widget.deviceName);
        _mqtt.setLunchOff(_lunchSlot.off, days: _lunchSlot.days, targetDeviceId: widget.deviceName);
      } else {
        _mqtt.clearLunchSlot(targetDeviceId: widget.deviceName);
      }
    }

    final success = await _mqtt.publishScheduleJson(payload);

    if (widget.deviceName.isNotEmpty) {
      for (int i = 0; i < 5; i++) {
        final idx = i + 1;
        LocalCacheService.saveScheduleSlotConfig(
          widget.deviceName,
          idx,
          onTime: _slots[i].lastOn,
          offTime: _slots[i].lastOff,
          days: _slots[i].days,
        );
      }
      LocalCacheService.saveScheduleSlotConfig(
        widget.deviceName,
        0,
        onTime: _lunchSlot.lastOn,
        offTime: _lunchSlot.lastOff,
        days: _lunchSlot.days,
      );
    }

    if (!success && mounted) {
      setState(() {
        _isSaving = false;
        _saveMessage = 'Failed to publish — check MQTT connection';
      });
      _clearMessageAfterDelay();
      return;
    }

    // Update originals after successful publish so next diff is clean
    _originalSlots = _slots.map((s) => s.copy()).toList();
    _originalLunch = _lunchSlot.copy();

    // If no response within 5s, treat as success anyway (device may not send SCHEDULE_UPDATED)
    Future.delayed(const Duration(seconds: 5), () {
      if (_isSaving && mounted) {
        setState(() {
          _isSaving = false;
          _saveMessage = 'Schedule published (awaiting device confirmation)';
        });
        _clearMessageAfterDelay();
      }
    });
  }

  // ── Day Toggle ────────────────────────────────────────────────────────
  List<String> _parseDays(String days) {
    final upper = days.toUpperCase().trim();
    if (upper == 'ALL' || upper == 'DAILY' || upper == 'EVERYDAY') {
      return List.from(_kDayLabels);
    }
    return upper.split(',').map((d) => d.trim()).where((d) => _kDayLabels.contains(d)).toList();
  }

  String _encodeDays(List<String> days) {
    if (days.length == 7) return 'ALL';
    // Sort in SUN→SAT order
    final sorted = List<String>.from(days);
    sorted.sort((a, b) => _kDayLabels.indexOf(a).compareTo(_kDayLabels.indexOf(b)));
    return sorted.join(',');
  }

  void _toggleDay(int slotIdx, String day, bool isLunch) {
    setState(() {
      final slot = isLunch ? _lunchSlot : _slots[slotIdx];
      final current = _parseDays(slot.days);
      if (current.contains(day)) {
        current.remove(day);
      } else {
        current.add(day);
      }
      slot.days = current.isEmpty ? 'ALL' : _encodeDays(current);
    });
    HapticFeedback.selectionClick();
  }

  void _setAllDays(int slotIdx, bool isLunch) {
    setState(() {
      final slot = isLunch ? _lunchSlot : _slots[slotIdx];
      slot.days = 'ALL';
    });
    HapticFeedback.selectionClick();
  }

  // ── Time Picker ────────────────────────────────────────────────────────
  Future<void> _pickTime(int slotIdx, bool isOn, bool isLunch) async {
    final slot = isLunch ? _lunchSlot : _slots[slotIdx];
    final currentStr = isOn ? slot.on : slot.off;

    TimeOfDay initial = TimeOfDay.now();
    if (currentStr != 'DISABLED' && currentStr.contains(':')) {
      try {
        final parts = currentStr.split(':');
        initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {}
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _kPrimary,
              surface: _kCardBg,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: _kBg,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isOn) {
          slot.on = formatted;
          slot.lastOn = formatted;
        } else {
          slot.off = formatted;
          slot.lastOff = formatted;
        }
      });
      if (widget.deviceName.isNotEmpty) {
        LocalCacheService.saveScheduleSlotConfig(
          widget.deviceName,
          isLunch ? 0 : (slotIdx + 1),
          onTime: slot.lastOn,
          offTime: slot.lastOff,
          days: slot.days,
        );
      }
      HapticFeedback.selectionClick();
    }
  }

  void _disableSlot(int slotIdx, bool isLunch) {
    setState(() {
      final slot = isLunch ? _lunchSlot : _slots[slotIdx];
      if (slot.on != 'DISABLED' && slot.on != '--:--') {
        slot.lastOn = slot.on;
      }
      if (slot.off != 'DISABLED' && slot.off != '--:--') {
        slot.lastOff = slot.off;
      }
      slot.on = 'DISABLED';
      slot.off = 'DISABLED';
    });
    HapticFeedback.mediumImpact();
  }

  void _enableSlot(int slotIdx, bool isLunch) {
    setState(() {
      final slot = isLunch ? _lunchSlot : _slots[slotIdx];
      slot.on = slot.lastOn;
      slot.off = slot.lastOff;
    });
    HapticFeedback.lightImpact();
  }

  String _formatTime(String time) {
    if (time == 'DISABLED' || time == '--:--' || !time.contains(':')) return '--:--';
    try {
      final parts = time.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      int displayHour = hour % 12;
      if (displayHour == 0) displayHour = 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return '--:--';
    }
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            _buildTabBar(),
            const SizedBox(height: 16),
            // Save message banner
            if (_saveMessage != null)
              _buildMessageBanner(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: _activeTab == 0
                      ? _buildScheduleSlots()
                      : _buildLunchSlot(),
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ─── HEADER ────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Schedule & Calendar",
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  widget.deviceName,
                  style: GoogleFonts.outfit(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Clear all button
          _buildActionChip(
            icon: Icons.delete_outline_rounded,
            color: const Color(0xFFEF4444),
            onTap: _confirmClearAll,
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  // ─── TAB BAR ───────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _buildTab("Schedules", 0, Icons.calendar_today_rounded),
          const SizedBox(width: 8),
          _buildTab("Lunch Break", 1, Icons.lunch_dining_rounded),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index, IconData icon) {
    final isActive = _activeTab == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() {
          _activeTab = index;
          _expandedSlot = -1;
        }),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? _kPrimary : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            boxShadow: isActive
                ? [BoxShadow(color: _kPrimary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isActive ? Colors.white : Colors.white60),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: isActive ? Colors.white : Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── MESSAGE BANNER ────────────────────────────────────────────────────
  Widget _buildMessageBanner() {
    final isError = _saveMessage?.toLowerCase().contains('error') == true ||
        _saveMessage?.toLowerCase().contains('failed') == true;
    final isWarning = _saveMessage?.toLowerCase().contains('warning') == true;
    final color = isError
        ? const Color(0xFFEF4444)
        : isWarning
            ? _kLunchColor
            : _kPrimary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _saveMessage ?? '',
              style: GoogleFonts.outfit(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ─── SCHEDULE SLOTS ────────────────────────────────────────────────────
  List<Widget> _buildScheduleSlots() {
    return [
      for (int i = 0; i < 5; i++) ...[
        _buildSlotCard(i, false),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 80),
    ];
  }

  List<Widget> _buildLunchSlot() {
    return [
      _buildSlotCard(0, true),
      const SizedBox(height: 80),
    ];
  }

  Widget _buildSlotCard(int index, bool isLunch) {
    final slot = isLunch ? _lunchSlot : _slots[index];
    final isEnabled = slot.on != 'DISABLED';
    final isExpanded = isLunch ? (_expandedSlot == 99) : (_expandedSlot == index);
    final color = isLunch ? _kLunchColor : _kPrimary;
    final label = isLunch ? 'LUNCH BREAK' : 'SCHEDULE ${index + 1}';
    final days = _parseDays(slot.days);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: _kCardBg.withOpacity(isEnabled ? 1.0 : 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isEnabled
              ? color.withOpacity(isExpanded ? 0.5 : 0.2)
              : Colors.white.withOpacity(0.06),
          width: isExpanded ? 1.5 : 1.0,
        ),
        boxShadow: isExpanded && isEnabled
            ? [BoxShadow(color: color.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4))]
            : [],
      ),
      child: Column(
        children: [
          // ── Slot Header ──
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  final key = isLunch ? 99 : index;
                  _expandedSlot = _expandedSlot == key ? -1 : key;
                });
                HapticFeedback.selectionClick();
              },
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    // Status dot
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: isEnabled ? color : Colors.white24,
                        shape: BoxShape.circle,
                        boxShadow: isEnabled
                            ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6)]
                            : [],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Label
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        color: isEnabled ? Colors.white : Colors.white38,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    // Time display
                    if (isEnabled) ...[
                      _buildTimeChip(slot.on, color),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward_rounded, color: Colors.white12, size: 12),
                      ),
                      _buildTimeChip(slot.off, color),
                    ] else ...[
                      _buildTimeChip(slot.lastOn, Colors.white24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward_rounded, color: Colors.white12, size: 12),
                      ),
                      _buildTimeChip(slot.lastOff, Colors.white24),
                    ],
                    const SizedBox(width: 8),
                    // Expand icon
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white30, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Expanded Content ──
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedContent(index, isLunch, slot, color, isEnabled, days),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeChip(String time, Color color) {
    final isSet = time != '--:--' && time != 'DISABLED';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isSet ? color.withOpacity(0.1) : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSet ? color.withOpacity(0.3) : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Text(
        _formatTime(time),
        style: GoogleFonts.outfit(
          color: isSet ? Colors.white : Colors.white30,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildExpandedContent(
    int index, bool isLunch, _SlotData slot, Color color, bool isEnabled, List<String> days,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 14),

          // ── Enable/Disable toggle ──
          Row(
            children: [
              Icon(
                isEnabled ? Icons.power_settings_new_rounded : Icons.power_off_rounded,
                color: isEnabled ? color : Colors.white24,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                isEnabled ? 'Enabled' : 'Disabled',
                style: GoogleFonts.outfit(
                  color: isEnabled ? Colors.white70 : Colors.white30,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  if (isEnabled) {
                    _disableSlot(index, isLunch);
                  } else {
                    _enableSlot(index, isLunch);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 24,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isEnabled ? color : _kDisabledColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: AnimatedAlign(
                    alignment: isEnabled ? Alignment.centerRight : Alignment.centerLeft,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 20, height: 20,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (isEnabled) ...[
            const SizedBox(height: 18),

            // ── Time Pickers ──
            Text('TIME', style: _sectionLabel()),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildTimePicker(
                    label: 'START',
                    time: slot.on,
                    color: color,
                    onTap: () => _pickTime(index, true, isLunch),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTimePicker(
                    label: 'END',
                    time: slot.off,
                    color: color,
                    onTap: () => _pickTime(index, false, isLunch),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // ── Day Selector / Date Picker ──
            Row(
              children: [
                Text(slot.date != null ? 'CALENDAR DATE' : 'ACTIVE DAYS', style: _sectionLabel()),
                const Spacer(),
                if (!isLunch) ...[
                  GestureDetector(
                    onTap: () async {
                      if (slot.date != null) {
                        setState(() => slot.date = null);
                      } else {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() {
                            slot.date =
                                "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                          });
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: slot.date != null ? color.withOpacity(0.15) : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: slot.date != null ? color.withOpacity(0.4) : Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            slot.date != null ? Icons.calendar_today_rounded : Icons.calendar_month_outlined,
                            size: 11,
                            color: slot.date != null ? color : Colors.white60,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            slot.date != null ? slot.date! : 'SET DATE',
                            style: GoogleFonts.outfit(
                              color: slot.date != null ? color : Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (slot.date != null) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.close_rounded, size: 10, color: color),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (slot.date == null)
                  GestureDetector(
                    onTap: () => _setAllDays(index, isLunch),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: days.length == 7 ? color.withOpacity(0.15) : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: days.length == 7 ? color.withOpacity(0.4) : Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Text(
                        'ALL',
                        style: GoogleFonts.outfit(
                          color: days.length == 7 ? color : Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (slot.date == null)
              _buildDayChips(index, isLunch, days, color)
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_available_rounded, color: color, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'One-time schedule on ${slot.date}',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'Spec Sec 7',
                      style: GoogleFonts.outfit(
                        color: color.withOpacity(0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  TextStyle _sectionLabel() => GoogleFonts.outfit(
    color: Colors.white30,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );

  Widget _buildTimePicker({
    required String label,
    required String time,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isSet = time != '--:--' && time != 'DISABLED';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          decoration: BoxDecoration(
            color: isSet ? color.withOpacity(0.06) : Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSet ? color.withOpacity(0.25) : Colors.white.withOpacity(0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: Colors.white30,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    label == 'START' ? Icons.play_arrow_rounded : Icons.stop_rounded,
                    color: isSet ? color : Colors.white24,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatTime(time),
                    style: GoogleFonts.outfit(
                      color: isSet ? Colors.white : Colors.white30,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayChips(int index, bool isLunch, List<String> selectedDays, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (dayIdx) {
        final day = _kDayLabels[dayIdx];
        final letter = _kDayLetters[dayIdx];
        final isSelected = selectedDays.contains(day);
        final isToday = dayIdx == (DateTime.now().weekday % 7);

        return GestureDetector(
          onTap: () => _toggleDay(index, day, isLunch),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withOpacity(0.15)
                  : Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? color.withOpacity(0.5)
                    : isToday
                        ? Colors.white.withOpacity(0.15)
                        : Colors.white.withOpacity(0.06),
                width: isToday && !isSelected ? 1.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withOpacity(0.15), blurRadius: 8)]
                  : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  letter,
                  style: GoogleFonts.outfit(
                    color: isSelected ? color : Colors.white38,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (isToday)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 4, height: 4,
                    decoration: BoxDecoration(
                      color: isSelected ? color : Colors.white30,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ─── FOOTER ────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: _kBg,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.04)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                "CANCEL",
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveSchedule,
              style: ElevatedButton.styleFrom(
                backgroundColor: _hasChanges ? _kPrimary : _kDisabledColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      _hasChanges ? "SAVE CHANGES" : "SAVE",
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CLEAR ALL ─────────────────────────────────────────────────────────
  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF131122),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_forever_rounded,
                    color: Color(0xFFEF4444), size: 32),
              ),
              const SizedBox(height: 20),
              Text(
                "Clear All Schedules?",
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "This will disable all 5 schedule slots and the lunch break. Tap SAVE to apply.",
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white38,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white60,
                        side: BorderSide(color: Colors.white.withOpacity(0.08)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text("Cancel",
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          for (var s in _slots) {
                            s.on = 'DISABLED';
                            s.off = 'DISABLED';
                            s.days = 'ALL';
                          }
                          _lunchSlot.on = 'DISABLED';
                          _lunchSlot.off = 'DISABLED';
                          _lunchSlot.days = 'ALL';
                        });
                        HapticFeedback.heavyImpact();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text("Clear All",
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mutable slot data holder for schedule slots.
class _SlotData {
  String on;
  String off;
  String days;
  String? date;
  String lastOn;
  String lastOff;

  _SlotData({
    required this.on,
    required this.off,
    required this.days,
    this.date,
    String? lastOn,
    String? lastOff,
  })  : lastOn = lastOn ?? (on != 'DISABLED' && on != '--:--' ? on : '08:00'),
        lastOff = lastOff ?? (off != 'DISABLED' && off != '--:--' ? off : '17:00');

  _SlotData copy() => _SlotData(
        on: on,
        off: off,
        days: days,
        date: date,
        lastOn: lastOn,
        lastOff: lastOff,
      );
}
