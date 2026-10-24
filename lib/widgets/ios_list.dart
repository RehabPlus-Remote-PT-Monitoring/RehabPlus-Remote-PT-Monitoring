// lib/widgets/ios_list.dart
//
// iOS "inset grouped" lists, as in the iPhone Settings app: rounded white
// (dark: #1C1C1E) groups on the grey page, a small uppercase grey header
// above each group and an optional grey footnote below, 44 pt minimum rows,
// separators that start after the icon, and a chevron on rows that open
// something.
//
//   IosSection(
//     header: 'Account',
//     footer: 'Turning this off stops phone alerts only.',
//     children: [
//       IosRow(icon: CupertinoIcons.lock, iconColor: IosColors.blue,
//              title: 'App lock', value: 'On', onTap: _openLock),
//       IosSwitchRow(icon: CupertinoIcons.bell, title: 'Reminders',
//              value: on, onChanged: _setReminders),
//     ],
//   )
//
// Put IosSections inside an IosPage (or any padded scroll view). They have
// no horizontal margin of their own; the page padding provides it.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_palette.dart';

/// iOS system tints for the coloured icon squares, so related settings get
/// distinct, familiar colours instead of everything in teal.
abstract final class IosColors {
  static const blue = Color(0xFF0A84FF);
  static const green = Color(0xFF30D158);
  static const indigo = Color(0xFF5E5CE6);
  static const orange = Color(0xFFFF9F0A);
  static const pink = Color(0xFFFF375F);
  static const purple = Color(0xFFBF5AF2);
  static const red = Color(0xFFFF453A);
  static const teal = AppPalette.teal;
  static const gray = Color(0xFF8E8E93);
}

/// One rounded group of rows with an optional header and footer.
class IosSection extends StatelessWidget {
  const IosSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
    this.hasLeading = true,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  /// False when the rows have no icons, so separators start at the text.
  final bool hasLeading;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final caption = TextStyle(
      fontSize: 13,
      color: palette.textMuted,
      fontWeight: FontWeight.w400,
    );
    return CupertinoListSection.insetGrouped(
      margin: const EdgeInsets.only(bottom: 8),
      topMargin: 16,
      backgroundColor: Colors.transparent,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      separatorColor: palette.divider,
      hasLeading: hasLeading,
      header: header == null
          ? null
          : Text(header!.toUpperCase(), style: caption),
      footer: footer == null ? null : Text(footer!, style: caption),
      children: children,
    );
  }
}

/// The coloured rounded square behind a row icon (white glyph), like the
/// iPhone Settings app.
class IosIconSquare extends StatelessWidget {
  const IosIconSquare(this.icon, {super.key, this.color = IosColors.teal});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 29,
      height: 29,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}

/// A standard row: icon square, title (+ optional subtitle), an optional
/// grey value on the right and a chevron when it opens something.
class IosRow extends StatelessWidget {
  const IosRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor = IosColors.teal,
    this.leading,
    this.value,
    this.trailing,
    this.onTap,
    this.showChevron,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color iconColor;

  /// Overrides [icon] (e.g. an avatar).
  final Widget? leading;

  /// Grey text on the right, e.g. "On" or a phone number.
  final String? value;

  /// Replaces the chevron, e.g. a badge.
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Defaults to true when [onTap] is set.
  final bool? showChevron;

  /// Red title, for Sign out and similar.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final chevron = showChevron ?? onTap != null;
    return CupertinoListTile(
      backgroundColor: palette.surface,
      backgroundColorActivated: palette.surfaceMuted,
      leading:
          leading ??
          (icon == null ? null : IosIconSquare(icon!, color: iconColor)),
      leadingSize: 29,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          color: destructive ? IosColors.red : palette.textPrimary,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 2,
              style: TextStyle(fontSize: 13, color: palette.textMuted),
            ),
      additionalInfo: value == null
          ? null
          : Text(
              value!,
              style: TextStyle(fontSize: 17, color: palette.textMuted),
            ),
      trailing:
          trailing ??
          (chevron
              ? Icon(
                  CupertinoIcons.chevron_forward,
                  size: 18,
                  color: palette.textFaint,
                )
              : null),
      onTap: onTap,
    );
  }
}

/// A row with an iOS switch on the right. The whole row toggles it.
class IosSwitchRow extends StatelessWidget {
  const IosSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor = IosColors.teal,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color iconColor;
  final bool value;

  /// Null disables the switch (e.g. while saving).
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: IosRow(
        title: title,
        subtitle: subtitle,
        icon: icon,
        iconColor: iconColor,
        showChevron: false,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: CupertinoSwitch(
          value: value,
          activeTrackColor: AppPalette.teal,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// A row that holds an arbitrary control under its title, such as an
/// IosSegmentedControl (Theme, Text size). Keeps the section's padding.
class IosControlRow extends StatelessWidget {
  const IosControlRow({
    super.key,
    required this.title,
    this.icon,
    this.iconColor = IosColors.teal,
    required this.child,
  });

  final String title;
  final IconData? icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      color: palette.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                IosIconSquare(icon!, color: iconColor),
                const SizedBox(width: 14),
              ],
              Text(
                title,
                style: TextStyle(fontSize: 17, color: palette.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
