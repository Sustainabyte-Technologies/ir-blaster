import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';

void showAutoOffTimerDialog({
  required BuildContext context,
  required bool isDark,
  required void Function(String message, Color color) onTimerSet,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) {
      Widget timerOption(String label) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              onTimerSet('Auto-off timer set for $label', AppColors.primary);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: dark ? AppColors.backgroundDark : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: dark ? AppColors.dividerDark : Colors.transparent,
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: dark ? Colors.white70 : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set Auto-Off Timer',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose when to automatically turn off the AC.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                timerOption('30 min'),
                const SizedBox(width: 12),
                timerOption('1 hour'),
                const SizedBox(width: 12),
                timerOption('2 hours'),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );
}
