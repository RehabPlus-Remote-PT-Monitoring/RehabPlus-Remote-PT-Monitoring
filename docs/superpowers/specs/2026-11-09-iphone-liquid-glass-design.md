# iPhone build: Liquid Glass controls + fluid transitions (design)

Branch: `iphone-testing` only (org repo). Not for `camera/monitoring`, and
Android must look and behave exactly as today.

## Intent

The user is testing RehabPlus on an iPhone and wants it to feel like a
current iOS (26/27) app: real Liquid Glass controls and fluid, connected
movement between screens (they cited ColorOS 17 on OPPO as the feel). An
earlier iOS restyle (`6481a23`, reverted in `7704dd6`) was rejected because
it "diverged way too much from the old UI": it replaced the fonts, teal
headers, gradient pill nav and layouts with Apple's grouped-list look.

## Goals

- Real UIKit/SwiftUI Liquid Glass controls on iOS 26+ where they replace
  existing controls one-for-one: bottom tab bar, switches, sliders,
  segmented controls, primary/secondary buttons, yes/no alerts.
- Fluid navigation on iOS: interactive edge-swipe back, an iOS-style
  slide with parallax for pushed pages, a crossfade+slight scale between
  bottom tabs, and Hero morphs from exercise cards into the exercise page.
- Keep the RehabPlus look: same screens, layouts, teal headers, Phosphor
  icons, fonts. Flatten gradients to solid teal and add a small set of
  supporting accent colours.

## Non-goals

- No layout changes, no new screens, no Apple grouped-list restyle, no
  font change, no large-title nav bars (this is what the user rejected).
- No change on Android (every change gated by `Platform.isIOS` or a single
  `useIosChrome` flag), and no change on `camera/monitoring`.
- The camera/exercise screen keeps its tuned overlay; only its app-bar
  buttons and end-session alert may change.

## Anti-goals (would be a failure even if it works)

- The app no longer looks like RehabPlus (teal identity lost).
- Glass controls bleeding over sheets/dialogs, or jank in scrolling lists.
- Every future merge from `camera/monitoring` conflicting in every screen.

## Constraints

- Flutter is pinned at 3.41.2 / Dart 3.11 (CI too); Flutter 3.47+ breaks
  `phosphor_flutter`.
- No Mac: iOS compiles only in the `iOS unsigned IPA` GitHub workflow
  (Xcode 26 needed by the package). Nothing can be seen on a simulator;
  visual checks happen on the user's iPhone (sideloaded) and through
  `idevicesyslog` logs.
- Real Liquid Glass needs iOS 26+; below that the package falls back to
  Cupertino widgets, which is acceptable.
- Platform views are costly: no native glass inside long scrolling lists.

## Approaches considered

1. **Native glass on the controls only (picked).** `cupertino_native_better`
   2.4.0 (real UIKit/SwiftUI controls, iOS 27 support, Cupertino fallback
   below iOS 26, Dart ^3.9). Keeps every screen, swaps controls one-for-one
   through small wrapper widgets. Trade-off: platform views cost a little
   per control; package is a single maintainer (active: released 8 Nov 2026).
2. **Native bars on every screen** (`adaptive_platform_ui`). More "Apple",
   but replaces the teal headers with iOS toolbars, repeating the rejected
   restyle.
3. **Flutter-drawn imitation glass** (`liquid_glass_renderer`). Needs
   Flutter 3.47; ruled out by the pin.

The user said "do what you feel best"; approach 1 was my recommendation.

## Design

### Platform switch
`lib/ios/ios_chrome.dart`: `bool get useIosChrome => Platform.isIOS`
(overridable in tests). Every iOS-only branch reads this one flag.

### Wrapper widgets (`lib/ios/`)
Each wrapper renders today's widget when `!useIosChrome`, so screens change
by one constructor call and Android output is identical:
- `AppSwitch` -> `CNSwitch` / existing `Switch`.
- `AppSlider` -> `CNSlider` / existing `Slider`.
- `AppSegmented` -> `CNSegmentedControl` / existing control.
- `AppButton` (filled / tonal) -> `CNButton` (prominentGlass tinted teal /
  glass) / existing `FilledButton`/`ElevatedButton`.
- `showAppConfirm(...)` -> `CNAlert.show` / existing `AlertDialog`
  (only plain yes/no dialogs; dialogs with their own fields stay Flutter).
Not wrapped: text fields, list tiles, cards, chips, snackbars.

### Tab bar
`DashboardScreen._buildBottomNav` on iOS: a `CNTabBar` with the same four
destinations (SF Symbols mapped from the Phosphor icons: house/
figure.strengthtraining.traditional/bubble.left/person.crop.circle,
filled when active), teal tint, unread badge on Messages, content extends
behind it (`extendBody`) with bottom padding raised so last items clear it.
Tablet sidebar (>= 1000 dp) unchanged. `CNTabBarRouteObserver` registered
on `MaterialApp.navigatorObservers` (iOS only).

### Transitions (iOS only)
- `PageTransitionsTheme` for iOS: `CupertinoPageTransitionsBuilder`
  (edge-swipe back + parallax). Android keeps `FadeForwards`.
- Tab switch: the existing `AnimatedSwitcher` gets a fade + 0.98->1.0
  scale, ~250 ms, ease-out (respects `MediaQuery.disableAnimations`).
- Hero: exercise card icon/title -> exercise page header; profile avatar
  -> Account Info/Edit Profile avatar.
- Light haptic on tab change and primary actions (iOS only).

### Colour
- `AppPalette` gains accents used sparingly for status/highlights:
  `accentCoral` (warm, complementary to teal), `accentMint`, `accentAmber`
  (warnings), each with a dark-mode value.
- Gradients (`LinearGradient`, 30+ uses) become solid brand teal on iOS via
  a helper `brandFill(context)` that returns the gradient on Android and a
  solid `BoxDecoration` colour on iOS. Same widget tree on both.

### Merge cost
All new code lives in `lib/ios/` + palette additions; screens change only
at call sites (wrapper constructors, `brandFill`). Expect small conflicts
when merging `camera/monitoring` into `iphone-testing`, not rewrites.

## Decisions after the builder check (my calls unless marked)

- Switches/segmented controls in Settings, App Lock settings and the
  Progress Report ARE wrapped: those screens hold a handful of controls,
  not long builder lists, so a few platform views are fine. The
  `SwitchListTile`s become an `AppSwitchTile` (same title/subtitle layout,
  trailing `AppSwitch`). "No glass in long lists" means `ListView.builder`
  / grids with many items (history, messages, exercise lists).
- The camera screen's slider stays Flutter (tuned screen); no `AppSlider`
  is built until there is a call site.
- Gradients: only BRAND surfaces go solid teal on iOS (teal headers,
  nav pill/sidebar highlight, buttons, splash and login backgrounds).
  Data visuals keep their gradients (chart area fill, avatar fallback).
- Buttons: `AppButton` replaces page-level `FilledButton`/`ElevatedButton`
  call sites. Buttons inside bottom sheets and dialogs stay Flutter (glass
  under a modal is the known bleed issue), restyled as teal capsules so
  they still match.
- Accents (approved by the user): coral = streaks, achievements and
  "today" highlights; amber = warnings (pain check-in, form warnings);
  mint = completed ticks / done states. Everything else stays teal.
- Tabs keep the existing carousel slide (already fluid, ColorOS-like)
  instead of a new crossfade+scale.
- Hero only for the profile avatar: exercise cards open the camera screen,
  which must not be restyled, so no exercise-card Hero.
- No unread badge on the Messages tab: the app has no messages-unread
  source today (only notifications), and adding one is out of scope.
- Deployment target: the package needs iOS 15.0; the app is already 15.5,
  so no change.

## Verification

- `flutter analyze`, full `flutter test`; widget tests for each wrapper with
  `useIosChrome` false (identical Material widget) and true (CN widget in
  tree), plus golden-free checks that Android dashboard still builds its
  pill nav.
- Android profile APK builds (proves no Android regressions in compile).
- iOS: CI workflow green; user sideloads the IPA; check on the iPhone:
  glass tab bar, switches, alerts, swipe-back, tab crossfade, Hero, dark
  mode, no glass over sheets.
- handoff.md row with "not yet checked on the iPhone" until the user does.

## Left to the builder

SF Symbol choices per icon, exact accent hex values (must pass WCAG AA for
text on surface), which dialogs count as "plain yes/no", Hero tag naming.
