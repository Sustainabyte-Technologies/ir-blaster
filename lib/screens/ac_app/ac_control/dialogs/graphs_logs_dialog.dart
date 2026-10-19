import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';

void showDeviceLogsDialog({
  required BuildContext context,
  required bool isDark,
  required List<Map<String, dynamic>> activityLogs,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext ctx) {
      return Container(
        height: MediaQuery.of(ctx).size.height * 0.45,
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Device Log & Activity',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Icon(
                    Icons.close_rounded,
                    color: isDark ? Colors.white30 : Colors.black26,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: activityLogs.isEmpty
                  ? Center(
                      child: Text(
                        'No activities recorded yet',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white30 : Colors.black26,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: activityLogs.length,
                      itemBuilder: (context, index) {
                        final log = activityLogs[index];
                        return _buildLogItem(
                          log['message'].toString(),
                          log['time'].toString(),
                          log['color'] as Color,
                          isDark,
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _buildLogItem(String title, String time, Color color, bool isDark) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: isDark ? AppColors.backgroundDark : Colors.grey[50],
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isDark ? AppColors.dividerDark : Colors.grey[200]!,
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.9)
                    : AppColors.textPrimary,
              ),
            ),
          ],
        ),
        Text(
          time,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    ),
  );
}
