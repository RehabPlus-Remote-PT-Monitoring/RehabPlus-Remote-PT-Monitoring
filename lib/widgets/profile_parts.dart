// lib/widgets/profile_parts.dart
//
// Building blocks for the Profile tab, Edit Profile and Account Info, in the
// look of the Apple ID page of iPhone Settings:
//
//   * ProfileIdentityCard  centred avatar, name, email and status chip.
//   * ProfileStatsCard     the Sessions / Sets / Reps / Avg Score numbers.
//   * ProfileInfoRow       a read-only "label ........ grey value" row.
//   * ProfileFormRow       an iOS form row: label on the left, field on the
//                          right, for use inside an IosSection.
//   * ProfileCentredActionRow  a centred action row (Sign Out in red).
//   * ProfileNavTextButton the "Edit" / "Save" text button for the nav bar.
//
// All of them sit on palette.surface without shadows or gradients and follow
// the app's dark mode through context.palette.

import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import 'ios_list.dart';
import 'pressable.dart';
import 'profile_avatar.dart';

/// Minimum row height on iOS (44 pt touch target).
const double _kRowMinHeight = 44;

/// Same insets as CupertinoListTile, so these rows line up with IosRows
/// in the same section.
const EdgeInsetsDirectional _kRowPadding = EdgeInsetsDirectional.fromSTEB(
  20,
  11,
  16,
  11,
);

/// The patient's identity at the top of the Profile tab. Tapping it opens
/// Edit Profile, like tapping your name in iPhone Settings.
class ProfileIdentityCard extends StatelessWidget {
  const ProfileIdentityCard({
    super.key,
    required this.photo,
    required this.name,
    required this.email,
    required this.statusLabel,
    this.onTap,
  });

  final Uint8List? photo;
  final String name;
  final String email;

  /// Shown in the chip under the email, e.g. "Active Patient".
  final String statusLabel;

  /// Null makes the card non-interactive (e.g. while Edit is opening).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ProfileAvatar(photo: photo, size: 88),
          const SizedBox(height: 12),
          Text(
            name.isEmpty ? 'Your name' : name,
            textAlign: TextAlign.center,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: palette.textPrimary,
            ),
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              email,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
          ],
          const SizedBox(height: 10),
          _StatusChip(label: statusLabel),
        ],
      ),
    );

    return Pressable(
      onTap: onTap,
      semanticLabel: onTap == null ? null : 'Edit profile',
      child: card,
    );
  }
}

/// Small grey pill with a green dot. The words carry the meaning, the dot
/// only decorates it, so colour is never the only signal.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.circle_fill,
            size: 8,
            color: IosColors.green,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// One number in [ProfileStatsCard].
class ProfileStat {
  const ProfileStat({required this.label, required this.value});

  final String label;
  final String value;
}

/// A row of numbers separated by thin dividers, on a plain card.
class ProfileStatsCard extends StatelessWidget {
  const ProfileStatsCard({super.key, required this.stats});

  final List<ProfileStat> stats;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    final cells = <Widget>[];
    for (var i = 0; i < stats.length; i++) {
      if (i > 0) {
        cells.add(Container(width: 0.5, height: 36, color: palette.divider));
      }
      final stat = stats[i];
      cells.add(
        Expanded(
          child: MergeSemantics(
            child: Column(
              children: [
                Text(
                  stat.value,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat.label,
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: cells),
    );
  }
}

/// A read-only label/value row for an IosSection (no icon, no chevron).
/// The label keeps its natural width; a long value (an email) wraps on the
/// right instead of overflowing.
class ProfileInfoRow extends StatelessWidget {
  const ProfileInfoRow({super.key, required this.label, required this.value});

  final String label;

  /// Empty shows a dash, so a missing value reads as "not set".
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Container(
        color: palette.surface,
        constraints: const BoxConstraints(minHeight: _kRowMinHeight),
        padding: _kRowPadding,
        child: Row(
          children: [
            Text(
              label,
              style: textTheme.bodyLarge?.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value.isEmpty ? '—' : value,
                textAlign: TextAlign.end,
                style: textTheme.bodyLarge?.copyWith(color: palette.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An iOS form row: the label on the left, the text field filling the
/// right, no box around the field (the section is the box). Read-only rows
/// show grey text and a lock so it's clear why they can't be edited.
class ProfileFormRow extends StatelessWidget {
  const ProfileFormRow({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.validator,
    this.readOnly = false,
    this.autofillHints,
    this.capitalization = TextCapitalization.none,
    this.textInputAction,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool readOnly;
  final Iterable<String>? autofillHints;
  final TextCapitalization capitalization;
  final TextInputAction? textInputAction;

  /// Wide enough for "Date of Birth" at the default text size, so the
  /// fields line up in one column like an iOS form.
  static const double _labelWidth = 116;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final fieldStyle = textTheme.bodyLarge?.copyWith(
      color: readOnly ? palette.textMuted : palette.textPrimary,
    );

    return Container(
      color: palette.surface,
      constraints: const BoxConstraints(minHeight: _kRowMinHeight),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Padding(
              // Same baseline as the field text.
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                label,
                style: textTheme.bodyLarge?.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              readOnly: readOnly,
              validator: validator,
              autofillHints: readOnly ? null : autofillHints,
              textCapitalization: capitalization,
              textInputAction: textInputAction,
              style: fieldStyle,
              decoration: InputDecoration(
                hintText: hint ?? label,
                hintStyle: textTheme.bodyLarge?.copyWith(
                  color: palette.textFaint,
                ),
                // The global theme fills inputs; a field inside a white
                // group must not draw its own box.
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                suffixIcon: readOnly
                    ? Icon(
                        CupertinoIcons.lock_fill,
                        size: 14,
                        color: palette.textFaint,
                        semanticLabel: 'Managed by your clinic',
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row with its title centred, for actions in their own section such as
/// Sign Out (iPhone Settings > Apple ID > Sign Out).
class ProfileCentredActionRow extends StatelessWidget {
  const ProfileCentredActionRow({
    super.key,
    required this.title,
    required this.onTap,
    this.destructive = false,
    this.busy = false,
  });

  final String title;

  /// Null disables the row.
  final VoidCallback? onTap;

  /// Red title.
  final bool destructive;

  /// Shows a spinner instead of the title while the action runs.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = destructive ? IosColors.red : AppPalette.teal;
    return CupertinoListTile(
      backgroundColor: palette.surface,
      backgroundColorActivated: palette.surfaceMuted,
      onTap: busy ? null : onTap,
      title: Center(
        child: busy
            ? const CupertinoActivityIndicator()
            : Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  color: onTap == null ? palette.textFaint : color,
                ),
              ),
      ),
    );
  }
}

/// A teal text button for the right side of an iOS navigation bar
/// ("Edit", "Save"). At least 44 pt tall.
class ProfileNavTextButton extends StatelessWidget {
  const ProfileNavTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.bold = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// iOS makes the confirming action (Save, Done) semibold.
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 17,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: onPressed == null
              ? context.palette.textFaint
              : AppPalette.teal,
        ),
      ),
    );
  }
}
