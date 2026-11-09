# iPhone Liquid Glass + Fluid Transitions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the iPhone build only, swap RehabPlus's controls for real iOS Liquid Glass controls, make page changes fluid, flatten brand gradients to solid teal and add coral/mint/amber accents, without changing any screen's layout or anything on Android.

**Architecture:** One flag (`useIosChrome`, = `Platform.isIOS`, overridable in tests) gates everything. New code lives in `lib/ios/`: wrapper widgets that render today's Material widget when the flag is off and a `cupertino_native_better` widget when on, plus colour helpers. Screens only change at call sites (constructor swaps), so merges from `camera/monitoring` stay small.

**Tech Stack:** Flutter 3.41.2 / Dart 3.11, `cupertino_native_better: ^2.4.0` (UIKit/SwiftUI platform views, Cupertino fallback below iOS 26), flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-09-iphone-liquid-glass-design.md`

## Global Constraints

- Branch `iphone-testing` only; push to the org repo by URL. Never `camera/monitoring`, never the group repo.
- Android output must be identical: every new branch reads `useIosChrome`; with it false each wrapper returns exactly the widget the call site had before.
- No layout changes, no font change, no large-title nav bars, no grouped-list restyle.
- The camera screen (`pose_detector_screen.dart`) keeps its slider and overlay; only its plain yes/no dialogs may change.
- No native glass inside `ListView.builder`/grids with many items, or inside bottom sheets/dialogs.
- Flutter pin 3.41.2 (don't bump); iOS deployment target stays 15.5.
- Code style: readable over compact, doc comments on why, failures logged through `DiagnosticLogger` (`lib/core/diagnostic_logger.dart`), `context.palette` for neutral colours. `dart format` only files you create.
- Accents (user-approved): coral = streaks, achievements, "today" highlights; amber = warnings; mint = completed/done. Accents are for icons, dots and fills, not body text.

## Review Focus

1. Dark mode on iOS: glass tab bar, accents and solid headers must read on the dark palette (tests pump both brightnesses for every wrapper).
2. A modal (dialog/bottom sheet) opened over a page with glass controls: glass must not draw over it (`CNTabBarRouteObserver` registered; wrapper buttons not used inside sheets).
3. Text scale up to 1.6x (Settings > Text size): `AppSwitchTile` titles wrap instead of overflowing beside the native switch.
4. Disabled state: `AppSwitch`/`AppButton` with `onChanged`/`onPressed` null must render disabled on both paths, not crash (`CNSwitch.onChanged` is non-nullable).
5. Tab bar on iOS: the last item of each tab page must scroll clear of the floating bar (bottom padding raised).

---

### Task 1: iOS flag, dependency, observer and page transitions

**Files:**
- Create: `lib/ios/ios_chrome.dart`
- Modify: `pubspec.yaml` (add `cupertino_native_better: ^2.4.0` under dependencies with a one-line comment), `lib/main.dart:144-147` (transitions) and the `MaterialApp(...)` call (navigatorObservers)
- Test: `test/ios_chrome_test.dart`

**Interfaces:**
- Produces: `bool get useIosChrome`; `@visibleForTesting set debugUseIosChromeOverride(bool? v)`; `PageTransitionsTheme appPageTransitions({required bool ios})`; `List<NavigatorObserver> appNavigatorObservers({required bool ios})`.

- [ ] **Step 1: Write the failing tests** — `appPageTransitions(ios: true)` maps every `TargetPlatform` to a `CupertinoPageTransitionsBuilder`; `appPageTransitions(ios: false)` maps every platform to `FadeForwardsPageTransitionsBuilder` (today's behaviour); `appNavigatorObservers(ios: true)` contains exactly one `CNTabBarRouteObserver`, `(ios: false)` is empty; `debugUseIosChromeOverride = true` makes `useIosChrome` true on the Linux test host, `null` restores `Platform.isIOS` (false).
- [ ] **Step 2: Run** `flutter test test/ios_chrome_test.dart` — expect FAIL (file missing).
- [ ] **Step 3: Implement** `lib/ios/ios_chrome.dart` (header comment explaining the flag and why Android is untouched), `flutter pub get`, then in `main.dart` replace the inline `PageTransitionsTheme` with `appPageTransitions(ios: useIosChrome)` and add `navigatorObservers: appNavigatorObservers(ios: useIosChrome)`.
- [ ] **Step 4: Run** the test file and `flutter analyze` — PASS / no issues.
- [ ] **Step 5: Commit** `iOS chrome: flag, cupertino_native_better, swipe-back transitions`.

### Task 2: Accent colours and brand gradient helper

**Files:**
- Create: `lib/ios/brand_colors.dart`
- Test: `test/brand_colors_test.dart`

**Interfaces:**
- Produces: `class AppAccents { static Color coral(BuildContext); static Color mint(BuildContext); static Color amber(BuildContext); }` and `Gradient brandGradient(List<Color> colors, {AlignmentGeometry begin = Alignment.centerLeft, AlignmentGeometry end = Alignment.centerRight})`.
- Values when `useIosChrome`: coral light `0xFFFF7A59` / dark `0xFFFF9479`; mint light `0xFF2EB88A` / dark `0xFF5FD3A8`; amber light `0xFFF5A623` / dark `0xFFFFC14D`; `brandGradient` returns a `LinearGradient` of `[AppPalette.midTeal, AppPalette.midTeal]` (solid, white text keeps contrast).
- Values when not: each accent takes a `fallback` the call site passes today (`coral(context, fallback: Color(0xFFFF6B35))`, etc.), and `brandGradient` returns `LinearGradient(colors: colors, begin: begin, end: end)` unchanged. Signature therefore: `static Color coral(BuildContext context, {required Color fallback})` (same for mint/amber).

- [ ] **Step 1: Write the failing tests** — with override false: `brandGradient([a,b,c], begin: topLeft, end: bottomRight)` equals `LinearGradient(colors: [a,b,c], begin: topLeft, end: bottomRight)`; `AppAccents.mint(ctx, fallback: X) == X`. With override true: gradient colours are all `AppPalette.midTeal`; accents return the light values under a light theme and the dark values under a dark theme (pump a `MaterialApp(theme: ...)` with each brightness and read inside a `Builder`).
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** in `lib/ios/brand_colors.dart`.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `iOS chrome: accent colours and solid brand fill`.

### Task 3: Control wrappers

**Files:**
- Create: `lib/ios/app_controls.dart`
- Test: `test/app_controls_test.dart`

**Interfaces:**
- Produces:
  - `AppSwitch({required bool value, required ValueChanged<bool>? onChanged, Color? activeColor})` — off: `Switch(value, onChanged, activeThumbColor/activeColor as today)`; on: `CNSwitch(value, onChanged ?? (_) {}, enabled: onChanged != null, color: activeColor ?? AppPalette.teal)`.
  - `AppSwitchTile({required Widget title, Widget? subtitle, Widget? secondary, required bool value, required ValueChanged<bool>? onChanged, Color? activeColor, EdgeInsetsGeometry? contentPadding})` — off: `SwitchListTile(...)` with the same arguments; on: `ListTile(leading: secondary, title, subtitle, trailing: AppSwitch(...), onTap: toggles, contentPadding)`.
  - `AppSegmented<T>({required List<(T value, String label)> segments, required T selected, required ValueChanged<T> onChanged, ButtonStyle? materialStyle})` — off: `SegmentedButton<T>` built exactly as settings/report do today (single selection, `showSelectedIcon: false`, `style: materialStyle`); on: `CNSegmentedControl(labels, selectedIndex, onValueChanged: i => onChanged(segments[i].$1), color: AppPalette.teal)`.
  - `AppButton({required String label, required VoidCallback? onPressed, IconData? materialIcon, String? sfSymbol, bool prominent = true, required Widget Function() material})` — off: returns `material()` (the call site's existing button, untouched); on: `CNButton(label, icon: sfSymbol != null ? CNSymbol(sfSymbol) : null, onPressed, enabled: onPressed != null, tint: AppPalette.teal, config: CNButtonConfig(style: prominent ? CNButtonStyle.prominentGlass : CNButtonStyle.glass, minHeight: 48))` stretched to the width the call site gave the old button.
  - `Future<bool> showAppConfirm(BuildContext context, {required String title, String? message, required String confirmLabel, String cancelLabel = 'Cancel', bool destructive = false, required Future<bool?> Function() material})` — off: `await material() ?? false`; on: `CNAlert.show<bool>` with cancel + confirm actions (`isDestructive: destructive`), result `== true`. Log a failure of the native alert through `DiagnosticLogger` and fall back to `material()`.

- [ ] **Step 1: Write the failing tests** (pump in light and dark, override false then true, reset in `tearDown`): off-path finds `Switch`/`SwitchListTile`/`SegmentedButton`/the material button/`AlertDialog` and none of `CNSwitch`/`CNSegmentedControl`/`CNButton`; on-path finds the CN widget; `AppSwitch(onChanged: null)` pumps without error on both paths; `AppSwitchTile` at `textScaler: TextScaler.linear(1.6)` and width 360 has no overflow (`tester.takeException()` is null); tapping the on-path tile's row calls `onChanged(!value)`; `AppSegmented` on-path maps index 1 back to `segments[1].$1`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** `lib/ios/app_controls.dart`. CN widgets fall back to Cupertino on the test host, which is fine for type checks.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `iOS chrome: switch, segmented, button and confirm wrappers`.

### Task 4: Liquid Glass tab bar on the dashboard

**Files:**
- Modify: `lib/screens/dashboard_screen.dart` (`build` phone branch ~line 347-352, `_buildBottomNav` ~1372)
- Create: `lib/ios/glass_tab_bar.dart`
- Test: `test/glass_tab_bar_test.dart`

**Interfaces:**
- Consumes: `useIosChrome`, `DashboardDestination` (`lib/widgets/dashboard_sidebar.dart`).
- Produces: `GlassTabBar({required List<DashboardDestination> destinations, required int currentIndex, required ValueChanged<int> onTap})` and `const Map<String, (String, String)> kTabSymbols` = `{'Home': ('house', 'house.fill'), 'Exercise': ('figure.strengthtraining.traditional', 'figure.strengthtraining.traditional'), 'Messages': ('bubble.left', 'bubble.left.fill'), 'Profile': ('person.crop.circle', 'person.crop.circle.fill')}`.

- [ ] **Step 1: Write the failing tests** — `GlassTabBar` builds a `CNTabBar` with 4 items whose labels match the destinations and `currentIndex` passes through; tapping calls `onTap`; every destination label has an entry in `kTabSymbols`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** `GlassTabBar` (`CNTabBar(tint: AppPalette.teal, items: [...], currentIndex, onTap)`). In the dashboard's phone `Scaffold`: when `useIosChrome`, `extendBody: true`, `bottomNavigationBar: SafeArea(top: false, child: GlassTabBar(destinations: _destinations, currentIndex: _bottomNavIndex, onTap: _selectTab))`, and wrap `_buildPageArea()` in a `MediaQuery` whose `padding.bottom` is raised by 64 so tab pages' last items clear the bar (Review Focus 5). Android keeps `ReadableWidth(child: _buildBottomNav())`. Sidebar (>= 1000 dp) unchanged. On iOS, `_selectTab` also calls `HapticFeedback.selectionClick()` when the index changes. The existing carousel slide between tabs stays (it already gives the ColorOS-style movement; this overrides the spec's crossfade idea, noted in the handoff row).
- [ ] **Step 4: Run** the test, `flutter test test/dashboard_sidebar_test.dart test/tablet_*_test.dart`, `flutter analyze` — PASS.
- [ ] **Step 5: Commit** `iOS chrome: Liquid Glass tab bar on the dashboard`.

### Task 5: Use the wrappers at call sites

**Files (modify only these call sites):**
- Switches: `lib/screens/settings_screen.dart:743`, `lib/screens/app_lock_settings_screen.dart:154,167` -> `AppSwitchTile`.
- Segmented: `lib/screens/settings_screen.dart:805`, `lib/screens/progress_report_screen.dart:337` -> `AppSegmented`.
- Page buttons (one each): account_info, app_lock_offer, change_password, consent, dashboard, demo, edit_profile, forgot_password, history, login_page, startup_error (`grep -n "FilledButton\|ElevatedButton"`). Wrap with `AppButton(label: <same text>, onPressed: <same>, material: () => <the existing button expression>)`. Skip any inside `showDialog`/`showModalBottomSheet` builders and the one in `pose_detector_screen.dart`.
- Confirms: the `showDialog` calls at `settings_screen.dart:305,308`, `history_screen.dart:678`, `consent_screen.dart:128`, `app_lock_screen.dart:237`, `pose_detector_screen.dart:822,2310,2420,2561` — convert ONLY those whose content is a title + message + two buttons returning a bool; leave dialogs holding text fields, sliders or custom widgets as they are and list them in the commit message.

- [ ] **Step 1:** Make the edits (no `dart format` on these files; keep diffs to the call sites).
- [ ] **Step 2: Run** `flutter analyze` and the full `flutter test` — PASS (existing widget tests run with the flag off, so they prove Android is unchanged).
- [ ] **Step 3: Commit** `iOS chrome: native switches, segmented controls, buttons and alerts`.

### Task 6: Solid brand fills, accents and avatar Hero

**Files:**
- Brand gradients -> `brandGradient(...)` (same colours/begin/end args): dashboard 416, 754, 863, 1443; profile 215; account_info 160; edit_profile 396; consent 294; legal_document 118; privacy_legal 106; settings 626; progress_report 472; change_password 292; goals 138; history 296, 433; notification_page 237, 334; demo 209, 532, 654; app_lock_screen 274; forgot_password 170, 409; login_page 185; splash_screen 274; dashboard_sidebar 88, 143. Leave: progress_charts 347, profile_avatar 34, history 548, messages 648, dashboard 1254.
- Accents: coral -> dashboard 975 (Active Days stat) and 614 (Alerts chip); mint -> dashboard 1277, 1313, 1322, demo 288, goals `_achievedGreen`, progress_report `_goodColor`; amber -> history 738/811 (`Colors.orange`), progress_report `_warningColor`. Each passes today's colour as `fallback`.
- Hero: `ProfileAvatar` gains optional `heroTag`; pass `'profile-avatar'` at profile_screen 255, account_info 89, edit_profile 461 (only one visible per route, so the tag is unique per route).
- Test: extend `test/brand_colors_test.dart` with a `ProfileAvatar(heroTag: 'x')` pump that finds one `Hero` with that tag, and none without a tag.

- [ ] **Step 1: Write the Hero test** — FAIL.
- [ ] **Step 2: Make the edits**, then `flutter analyze` + full `flutter test` — PASS.
- [ ] **Step 3: Commit** `iOS chrome: solid teal brand fills, coral/mint/amber accents, avatar Hero`.

### Task 7: Verify, ship to CI, handoff

- [ ] **Step 1:** `flutter build apk --profile --split-per-abi` — builds (Android compiles with the new plugin).
- [ ] **Step 2:** Add a handoff.md status row (what was built, files, the carousel-instead-of-crossfade call, dialogs left as Flutter, "Not yet checked on the iPhone").
- [ ] **Step 3:** `git push https://github.com/RehabPlus-Remote-PT-Monitoring/RehabPlus-Remote-PT-Monitoring.git HEAD:iphone-testing` after confirming fast-forward; poll the `iOS unsigned IPA` run until `completed success` (fix compile errors if not), then download the IPA into `/home/izaac/Downloads/RehabPlus-iOS/` (old one renamed `-old`).
