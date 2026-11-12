// lib/ios/app_controls.dart
//
// Controls that are real iOS Liquid Glass controls on iPhone and exactly the
// app's existing Material widgets on Android.
//
// The pattern: each wrapper takes a `material` builder holding the widget
// the screen had before. With the iPhone look off (Android) that builder is
// returned untouched, so Android can't drift; with it on, the matching
// cupertino_native_better control is drawn instead. Screens change only at
// the call site.
//
// Native controls are platform views (a little costly each), so use these
// for the handful of controls on a page, never inside long builder lists,
// bottom sheets or dialogs (glass shows through modals).

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import 'ios_chrome.dart';

/// An on/off switch: `CNSwitch` on iPhone, a teal Material `Switch`
/// elsewhere. A null [onChanged] shows it disabled on both.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final callback = onChanged;
    if (!useIosChrome) {
      return Switch(
        value: value,
        onChanged: callback,
        activeThumbColor: Colors.white,
        activeTrackColor: AppPalette.teal,
      );
    }
    return CNSwitch(
      value: value,
      // CNSwitch needs a callback even when disabled.
      onChanged: callback ?? (_) {},
      enabled: callback != null,
      color: AppPalette.teal,
    );
  }
}

/// A list row with a switch at the end (the iOS Settings pattern).
///
/// Android: [material] (the screen's existing `SwitchListTile`).
/// iPhone: a `ListTile` with the same leading/title/subtitle and an
/// [AppSwitch]; tapping anywhere on the row toggles it, like the
/// `SwitchListTile` it replaces.
class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    required this.material,
    this.subtitle,
    this.leading,
    this.contentPadding,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final EdgeInsetsGeometry? contentPadding;
  final Widget Function() material;

  @override
  Widget build(BuildContext context) {
    if (!useIosChrome) return material();
    final onChanged = this.onChanged;
    return ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      contentPadding: contentPadding,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged(!value),
      trailing: AppSwitch(value: value, onChanged: onChanged),
    );
  }
}

/// A one-of-several picker. Android: [material] (the existing
/// `SegmentedButton`). iPhone: the native segmented control; [segments]
/// pairs each value with its label, in order.
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    required this.material,
  });

  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final Widget Function() material;

  @override
  Widget build(BuildContext context) {
    if (!useIosChrome) return material();
    final index = segments.indexWhere((s) => s.$1 == selected);
    if (index < 0) {
      // A caller bug (the value isn't one of the segments); logged so it
      // isn't mistaken for the native control ignoring the setting.
      DiagnosticLogger.I.warn('IosChrome', 'Segmented value not in segments', {
        'segments': segments.length,
      });
    }
    return CNSegmentedControl(
      labels: [for (final s in segments) s.$2],
      // -1 would crash the native control; fall back to the first segment.
      selectedIndex: index < 0 ? 0 : index,
      onValueChanged: (i) {
        // The index comes back over the platform channel; never trust it
        // to be in range.
        if (i < 0 || i >= segments.length) {
          DiagnosticLogger.I.warn('IosChrome', 'Segment index out of range', {
            'index': i,
            'segments': segments.length,
          });
          return;
        }
        onChanged(segments[i].$1);
      },
      color: AppPalette.teal,
    );
  }
}

/// A page's button.
///
/// Android: [material] (the existing button). iPhone: a filled Liquid
/// Glass capsule tinted teal. [sfSymbol] is an optional SF Symbol name
/// shown before the label.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.material,
    this.sfSymbol,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget Function() material;
  final String? sfSymbol;

  @override
  Widget build(BuildContext context) {
    if (!useIosChrome) return material();
    final symbol = sfSymbol;
    return CNButton(
      label: label,
      icon: symbol == null ? null : CNSymbol(symbol, size: 17),
      onPressed: onPressed,
      enabled: onPressed != null,
      tint: AppPalette.teal,
      config: CNButtonConfig(
        style: CNButtonStyle.prominentGlass,
        minHeight: 48,
        // The native label is a plain string, so apply the phone's and the
        // in-app Settings > Text size scale here (17 pt = iOS body size).
        labelFontSize: MediaQuery.textScalerOf(context).scale(17),
      ),
    );
  }
}

/// Asks a yes/no question. Returns true only when the user confirmed.
///
/// Android: runs [material] (the screen's existing `showDialog`).
/// iPhone: a native alert. If the native alert can't be shown (it returns
/// no answer or throws), the Material dialog is shown instead, so the
/// question is never silently skipped; unless the screen was closed in the
/// meantime, when the answer is "no".
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required Future<bool?> Function() material,
  String? message,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  if (!useIosChrome) return await material() ?? false;
  return confirmWithFallback(
    native: () async {
      final result = await CNAlert.show<bool>(
        context: context,
        title: title,
        message: message,
        actions: [
          CNAlertAction(label: cancelLabel, value: false, isCancel: true),
          CNAlertAction(
            label: confirmLabel,
            value: true,
            isDestructive: destructive,
            isDefault: !destructive,
          ),
        ],
      );
      // Cancel and confirm both carry a value; null means no alert.
      return result?.value;
    },
    material: material,
    canFallBack: () => context.mounted,
    title: title,
  );
}

/// Runs [native]; when it gives no answer (null) or throws, logs it and
/// runs [material] instead. Returns true only for an explicit yes.
///
/// [canFallBack] is asked before the fallback: the native alert is awaited
/// first, and if the screen was closed meanwhile its context can no longer
/// show a dialog (showDialog on an unmounted context throws). The answer
/// is then "no", which is the safe one for every confirm in the app (they
/// all guard a destructive action).
///
/// [title] is the app's own constant question text (never user input), so
/// it is safe to log and tells which confirm misbehaved.
@visibleForTesting
Future<bool> confirmWithFallback({
  required Future<bool?> Function() native,
  required Future<bool?> Function() material,
  bool Function()? canFallBack,
  String title = '',
}) async {
  final logger = DiagnosticLogger.I;
  try {
    final answer = await native();
    if (answer != null) {
      logger.info('IosChrome', 'Native alert answered', {
        'title': title,
        'confirmed': answer,
      });
      return answer;
    }
    logger.warn(
      'IosChrome',
      'Native alert gave no answer; showing the Material dialog',
      {'title': title},
    );
  } catch (e, st) {
    logger.warn(
      'IosChrome',
      'Native alert failed; showing the Material dialog',
      {'title': title},
      e,
      st,
    );
  }
  if (canFallBack != null && !canFallBack()) {
    logger.warn('IosChrome', 'Screen closed before the fallback dialog', {
      'title': title,
    });
    return false;
  }
  return await material() ?? false;
}
