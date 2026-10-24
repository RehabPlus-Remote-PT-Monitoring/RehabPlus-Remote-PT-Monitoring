// lib/widgets/dashboard_shell.dart
//
// The frame around the dashboard's four tab pages. It picks the navigation
// for the screen width:
//
//   * narrower than kSidebarBreakpoint (phones, tablets in portrait): the
//     translucent iOS tab bar at the bottom, with the page scrolling under
//     it (Scaffold.extendBody);
//   * kSidebarBreakpoint and wider (tablets in landscape): an iPad-style
//     sidebar on the left and no bottom bar. The page area then gets a
//     MediaQuery whose width is the space to the right of the sidebar, so
//     readablePadding / isTwoColumn inside the pages measure what they
//     really have.
//
// Rotating switches live. The page area keeps a GlobalKey, so the open page
// is moved to its new place in the tree rather than rebuilt: its scroll
// position and other state survive the rotation.
//
// Switching tabs cross-fades quickly (like iOS, no sideways slide), and not
// at all with the system's "remove animations" setting on.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../core/responsive.dart';
import 'dashboard_sidebar.dart';
import 'dashboard_tab_bar.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.page,
    required this.sidebarHeader,
  });

  final List<DashboardDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// The page of the selected destination, already built by the caller.
  final Widget page;

  /// App name / logo at the top of the sidebar.
  final Widget sidebarHeader;

  /// How long the cross-fade between tabs takes.
  static const Duration tabFadeDuration = Duration(milliseconds: 150);

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  /// Keeps the page area's state when rotation moves it between the
  /// tab-bar layout and the sidebar layout.
  final GlobalKey _pageAreaKey = GlobalKey(debugLabel: 'dashboard pages');

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final showSidebar = media.size.width >= kSidebarBreakpoint;
    final pageArea = _buildPageArea(media);

    if (showSidebar) {
      return Scaffold(
        backgroundColor: context.palette.background,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DashboardSidebar(
              destinations: widget.destinations,
              selectedIndex: widget.selectedIndex,
              onSelect: widget.onSelect,
              header: widget.sidebarHeader,
            ),
            Expanded(
              child: MediaQuery(
                data: _pageAreaMedia(media),
                child: pageArea,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.palette.background,
      // Pages draw behind the translucent bar; Scaffold adds the bar's
      // height to MediaQuery.padding.bottom so their content can clear it.
      extendBody: true,
      body: pageArea,
      bottomNavigationBar: DashboardTabBar(
        destinations: widget.destinations,
        selectedIndex: widget.selectedIndex,
        onSelect: widget.onSelect,
      ),
    );
  }

  Widget _buildPageArea(MediaQueryData media) {
    final duration = media.disableAnimations
        ? Duration.zero
        : DashboardShell.tabFadeDuration;
    return KeyedSubtree(
      key: _pageAreaKey,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        // Pages fill the area while they fade (the default Stack would let
        // a page that shrink-wraps its width end up narrower).
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, ?current],
        ),
        child: KeyedSubtree(
          key: ValueKey(widget.selectedIndex),
          child: widget.page,
        ),
      ),
    );
  }

  /// The MediaQuery for the area right of the sidebar: narrower by the
  /// sidebar's width, and without the left safe-area inset, which the
  /// sidebar already covers.
  MediaQueryData _pageAreaMedia(MediaQueryData media) {
    final withoutLeftInset = media.removePadding(removeLeft: true).removeViewPadding(removeLeft: true);
    final width = math.max(0.0, media.size.width - DashboardSidebar.width);
    return withoutLeftInset.copyWith(size: Size(width, media.size.height));
  }
}
