// lib/widgets/info_content_unavailable.dart
//
// The iOS "content unavailable" empty state (SwiftUI's
// ContentUnavailableView): a large grey symbol, a bold title and one short
// line of explanation, centred on the page. Used when a list is empty or
// could not load (My Goals, Notifications), instead of a coloured circle
// that looked like a button.
//
//   InfoContentUnavailable(
//     icon: CupertinoIcons.bell_slash,
//     title: 'No notifications yet',
//     body: 'Messages and reminders from your clinic appear here.',
//   )
//
// Inside a CustomScrollView, wrap it in
// `SliverFillRemaining(hasScrollBody: false, child: ...)` so it is centred
// in the space under the navigation bar.

import 'package:flutter/material.dart';

import '../core/app_palette.dart';

class InfoContentUnavailable extends StatelessWidget {
  const InfoContentUnavailable({
    super.key,
    required this.icon,
    required this.title,
    this.body,
  });

  final IconData icon;
  final String title;

  /// One line saying why the list is empty or what to do next.
  final String? body;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Decorative: the title says the same thing in words.
            ExcludeSemantics(
              child: Icon(icon, size: 56, color: palette.textFaint),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
