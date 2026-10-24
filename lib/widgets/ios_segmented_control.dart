// lib/widgets/ios_segmented_control.dart
//
// The iOS segmented control (a grey track with a sliding white "thumb" under
// the selected option), used for short exclusive choices such as Theme,
// Text size and the report period. Replaces Material's SegmentedButton,
// whose outlined pill look reads as Android.

import 'package:flutter/cupertino.dart';

import '../core/app_palette.dart';

class IosSegmentedControl<T extends Object> extends StatelessWidget {
  const IosSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  /// Value -> label, in display order.
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        backgroundColor: palette.inputFill,
        // White thumb in light mode, a lighter grey than the card in dark.
        thumbColor: context.isDarkMode
            ? const Color(0xFF636366)
            : const Color(0xFFFFFFFF),
        padding: const EdgeInsets.all(2),
        onValueChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
        children: {
          for (final entry in options.entries)
            entry.key: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                entry.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: entry.key == value
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: palette.textPrimary,
                ),
              ),
            ),
        },
      ),
    );
  }
}
