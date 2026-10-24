// lib/widgets/ios_page.dart
//
// The standard inner page: an iOS large-title navigation bar that collapses
// into a small centred title as you scroll, with a back button that names
// the previous screen ("‹ Profile"), over the grouped grey page background.
// Replaces the custom teal header each inner page used to draw.
//
//   IosPage(
//     title: 'Settings',
//     previousPageTitle: 'Profile',
//     children: [IosSection(...), IosSection(...)],
//   )
//
// Content is padded into the readable column (lib/core/responsive.dart), and
// the large title is indented to line up with it on tablets. Pass
// [maxWidth] = adaptiveMaxWidth(context) for screens that use two columns.
// For a list built lazily or other slivers, pass [slivers] instead of
// [children]. [bottom] is pinned under the scroll view (e.g. a Save button).

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../core/responsive.dart';

class IosPage extends StatelessWidget {
  const IosPage({
    super.key,
    required this.title,
    this.previousPageTitle,
    this.trailing,
    this.children,
    this.slivers,
    this.bottom,
    this.maxWidth = kReadableMaxWidth,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 32),
    this.onRefresh,
  }) : assert(
         (children == null) != (slivers == null),
         'Pass either children or slivers',
       );

  final String title;

  /// Shown next to the back chevron. Null shows a bare chevron.
  final String? previousPageTitle;

  /// Right side of the bar: a CupertinoButton/IconButton or a small row.
  final Widget? trailing;

  final List<Widget>? children;
  final List<Widget>? slivers;
  final Widget? bottom;
  final double maxWidth;

  /// Padding of [children] inside the readable column.
  final EdgeInsets padding;

  /// Adds iOS pull-to-refresh under the large title.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final inset = readableInset(context, maxWidth);

    final content =
        slivers ??
        [
          SliverPadding(
            padding: readablePadding(context, padding, maxWidth),
            sliver: SliverList.list(children: children!),
          ),
        ];

    return Scaffold(
      backgroundColor: palette.background,
      body: CustomScrollView(
        // iOS bounce even when the content is short, so the large title
        // still collapses and stretches like a native page.
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Padding(
              // Line the title up with the content column on tablets.
              padding: EdgeInsets.only(left: inset),
              child: Text(title),
            ),
            middle: Text(title),
            alwaysShowMiddle: false,
            previousPageTitle: previousPageTitle,
            trailing: trailing,
            padding: EdgeInsetsDirectional.only(
              start: inset > 0 ? inset : 8,
              end: inset > 0 ? inset + 8 : 16,
            ),
            backgroundColor: palette.background.withValues(alpha: 0.86),
            border: Border(
              bottom: BorderSide(color: palette.divider, width: 0.5),
            ),
            // Only one bar per route here, and Material routes don't use
            // Cupertino's flying-title transition reliably.
            transitionBetweenRoutes: false,
          ),
          if (onRefresh != null)
            CupertinoSliverRefreshControl(onRefresh: onRefresh),
          ...content,
        ],
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              top: false,
              child: ReadableWidth(
                maxWidth: maxWidth,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: bottom,
                ),
              ),
            ),
    );
  }
}
