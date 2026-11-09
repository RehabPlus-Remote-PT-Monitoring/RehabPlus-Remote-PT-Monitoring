// lib/widgets/profile_info_row.dart
//
// One "label ........ value" row in the Profile screen's info cards
// (Personal Info, Rehab Info).

import 'package:flutter/material.dart';

import '../core/app_palette.dart';

class ProfileInfoRow extends StatelessWidget {
  const ProfileInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      // A long value (e.g. a full diagnosis under Condition) wraps onto
      // more lines under itself, right-aligned, instead of running off the
      // card. The label keeps its width; icon and label stay on the first
      // line.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: palette.textMuted),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: palette.textMuted, fontSize: 13)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.end,
              softWrap: true,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
