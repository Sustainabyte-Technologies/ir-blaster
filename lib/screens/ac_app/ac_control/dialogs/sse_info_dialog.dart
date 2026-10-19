import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';

String formatLastSeen(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 5) return 'just now';
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

Widget _sseInfoRow(String label, String value, Color valueColor, bool isDark) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
      Flexible(
        child: Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
        ),
      ),
    ],
  );
}

void showSseInfoDialog({
  required BuildContext context,
  required bool isDark,
  required MqttService mqtt,
  required String activeDeviceId,
  required String activeDeviceImei,
}) {
  final textCol = isDark ? Colors.white : AppColors.textPrimary;
  final subtextCol = isDark ? Colors.white54 : Colors.black54;

  showDialog(
    context: context,
    builder: (BuildContext ctx) {
      return AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              mqtt.isSseConnected
                  ? Icons.sensors_rounded
                  : Icons.sensors_off_rounded,
              color: mqtt.isSseConnected ? Colors.green : Colors.red,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              'Stream Status',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: textCol,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sseInfoRow(
              'Connection',
              mqtt.isSseConnected ? 'Connected' : 'Disconnected',
              mqtt.isSseConnected ? Colors.green : Colors.red,
              isDark,
            ),
            const SizedBox(height: 12),
            _sseInfoRow('Endpoint', '/mqtt/stream', AppColors.primary, isDark),
            const SizedBox(height: 12),
            _sseInfoRow(
              'Last Data',
              mqtt.sseLastDataTime != null
                  ? formatLastSeen(mqtt.sseLastDataTime!)
                  : 'No data received',
              subtextCol,
              isDark,
            ),
            const SizedBox(height: 12),
            _sseInfoRow(
              'Device ID',
              activeDeviceId.isNotEmpty ? activeDeviceId : '--',
              subtextCol,
              isDark,
            ),
            const SizedBox(height: 12),
            _sseInfoRow(
              'IMEI',
              activeDeviceImei.isNotEmpty ? activeDeviceImei : '--',
              subtextCol,
              isDark,
            ),
            if (mqtt.sseLastPayload != null) ...[
              const SizedBox(height: 16),
              Text(
                'Last Payload',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: subtextCol,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Text(
                    mqtt.sseLastPayload!,
                    style: GoogleFonts.robotoMono(
                      fontSize: 9,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      );
    },
  );
}
