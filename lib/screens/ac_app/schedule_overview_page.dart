import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/screens/ac_app/schedule_calendar_page.dart';

class ScheduleOverviewPage extends StatefulWidget {
  const ScheduleOverviewPage({Key? key}) : super(key: key);

  @override
  State<ScheduleOverviewPage> createState() => _ScheduleOverviewPageState();
}

class _ScheduleOverviewPageState extends State<ScheduleOverviewPage> {
  final MqttService _mqtt = MqttService();
  StreamSubscription<SirisDeviceState>? _stateSub;
  SirisDeviceState? _state;

  @override
  void initState() {
    super.initState();
    _state = _mqtt.lastState;
    _stateSub = _mqtt.stateStream.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.backgroundDark : AppColors.background;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          'SCHEDULE OVERVIEW',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: textColor,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_calendar_rounded, color: textColor, size: 22),
            tooltip: 'Manage Schedules',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScheduleCalendarPage(
                    deviceName: _state?.deviceId ?? 'Device',
                    initialState: _state,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ScheduleOverviewContent(state: _state),
    );
  }
}

class ScheduleOverviewContent extends StatelessWidget {
  final SirisDeviceState? state;

  const ScheduleOverviewContent({Key? key, this.state}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

    // Build schedule items from live state
    final schedules = _buildScheduleItems(state);

    if (schedules.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded,
                color: textColor.withOpacity(0.15), size: 56),
            const SizedBox(height: 16),
            Text(
              'No active schedules',
              style: GoogleFonts.outfit(
                color: textColor.withOpacity(0.4),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the calendar icon to set up schedules',
              style: GoogleFonts.inter(
                color: textColor.withOpacity(0.25),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Active Schedule Timeline',
              style: GoogleFonts.outfit(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 32),
            ...List.generate(schedules.length, (index) {
              return _buildScheduleRow(
                context,
                schedules[index],
                isLast: index == schedules.length - 1,
                textColor: textColor,
              );
            }),
          ],
        ),
      ),
    );
  }

  List<_ScheduleItem> _buildScheduleItems(SirisDeviceState? s) {
    if (s == null) return [];
    final items = <_ScheduleItem>[];

    // Helper to check if a slot is active
    bool isActive(String on, String off) =>
        on != 'DISABLED' && off != 'DISABLED' && on != '--:--' && off != '--:--';

    String formatDays(String days) {
      if (days.toUpperCase() == 'ALL' || days.toUpperCase() == 'DAILY' || days.toUpperCase() == 'EVERYDAY') {
        return 'Every day';
      }
      return days;
    }

    // Slot 1
    if (isActive(s.schOn1, s.schOff1)) {
      items.add(_ScheduleItem(
        time: _format12h(s.schOn1),
        title: 'Schedule 1 — ON',
        subtitle: 'AC turns ON · ${formatDays(s.schDays1)}',
        color: AppColors.coolBlue,
      ));
      items.add(_ScheduleItem(
        time: _format12h(s.schOff1),
        title: 'Schedule 1 — OFF',
        subtitle: 'AC turns OFF · ${formatDays(s.schDays1)}',
        color: AppColors.offline,
      ));
    }

    // Slot 2
    if (isActive(s.schOn2, s.schOff2)) {
      items.add(_ScheduleItem(
        time: _format12h(s.schOn2),
        title: 'Schedule 2 — ON',
        subtitle: 'AC turns ON · ${formatDays(s.schDays2)}',
        color: AppColors.coolBlue,
      ));
      items.add(_ScheduleItem(
        time: _format12h(s.schOff2),
        title: 'Schedule 2 — OFF',
        subtitle: 'AC turns OFF · ${formatDays(s.schDays2)}',
        color: AppColors.offline,
      ));
    }

    // Slot 3
    if (isActive(s.schOn3, s.schOff3)) {
      items.add(_ScheduleItem(
        time: _format12h(s.schOn3),
        title: 'Schedule 3 — ON',
        subtitle: 'AC turns ON · ${formatDays(s.schDays3)}',
        color: AppColors.coolBlue,
      ));
      items.add(_ScheduleItem(
        time: _format12h(s.schOff3),
        title: 'Schedule 3 — OFF',
        subtitle: 'AC turns OFF · ${formatDays(s.schDays3)}',
        color: AppColors.offline,
      ));
    }

    // Slot 4
    if (isActive(s.schOn4, s.schOff4)) {
      items.add(_ScheduleItem(
        time: _format12h(s.schOn4),
        title: 'Schedule 4 — ON',
        subtitle: 'AC turns ON · ${formatDays(s.schDays4)}',
        color: AppColors.coolBlue,
      ));
      items.add(_ScheduleItem(
        time: _format12h(s.schOff4),
        title: 'Schedule 4 — OFF',
        subtitle: 'AC turns OFF · ${formatDays(s.schDays4)}',
        color: AppColors.offline,
      ));
    }

    // Slot 5
    if (isActive(s.schOn5, s.schOff5)) {
      items.add(_ScheduleItem(
        time: _format12h(s.schOn5),
        title: 'Schedule 5 — ON',
        subtitle: 'AC turns ON · ${formatDays(s.schDays5)}',
        color: AppColors.coolBlue,
      ));
      items.add(_ScheduleItem(
        time: _format12h(s.schOff5),
        title: 'Schedule 5 — OFF',
        subtitle: 'AC turns OFF · ${formatDays(s.schDays5)}',
        color: AppColors.offline,
      ));
    }

    // Lunch Break
    if (isActive(s.lunchOn, s.lunchOff)) {
      items.add(_ScheduleItem(
        time: _format12h(s.lunchOn),
        title: 'Lunch Break — OFF',
        subtitle: 'AC turns OFF for break · ${formatDays(s.lunchDays)}',
        color: AppColors.heatOrange,
      ));
      items.add(_ScheduleItem(
        time: _format12h(s.lunchOff),
        title: 'Lunch Break — ON',
        subtitle: 'AC resumes after break · ${formatDays(s.lunchDays)}',
        color: AppColors.primary,
      ));
    }

    // Sort by time
    items.sort((a, b) => a.time.compareTo(b.time));

    return items;
  }

  String _format12h(String time) {
    if (time == 'DISABLED' || time == '--:--' || !time.contains(':')) return '--:--';
    try {
      final parts = time.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      int displayHour = hour % 12;
      if (displayHour == 0) displayHour = 12;
      return '${displayHour.toString().padLeft(2, ' ')}:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return time;
    }
  }

  Widget _buildScheduleRow(BuildContext context, _ScheduleItem item, {required bool isLast, required Color textColor}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: item.color.withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: textColor.withOpacity(0.1),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: Text(
              item.time,
              style: GoogleFonts.inter(
                color: textColor.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            width: 1.5,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: textColor.withOpacity(0.1),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: GoogleFonts.outfit(
                      color: item.color,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: GoogleFonts.inter(
                      color: textColor.withOpacity(0.4),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleItem {
  final String time;
  final String title;
  final String subtitle;
  final Color color;

  _ScheduleItem({
    required this.time,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}
