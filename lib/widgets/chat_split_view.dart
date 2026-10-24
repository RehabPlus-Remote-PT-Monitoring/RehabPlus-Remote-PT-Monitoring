// lib/widgets/chat_split_view.dart
//
// iPad Messages layout: the list of conversations in a fixed-width column on
// the left and the open conversation filling the rest, with a hairline
// between them.
//
// Each pane gets its own MediaQuery width, so the readable-column helpers
// (readablePadding, IosPage's title inset) measure the pane they are in
// rather than the whole page; without this the 320 dp list would be padded
// as if it were a full tablet page.

import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../core/responsive.dart';

/// Width of the conversation list in the split layout.
const double kChatListPaneWidth = 320;

/// True when the Messages tab has room for list and conversation side by
/// side. Uses MediaQuery, which the dashboard narrows to the page area.
bool useChatSplitView(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kTwoColumnBreakpoint;

class ChatSplitView extends StatelessWidget {
  const ChatSplitView({
    super.key,
    required this.list,
    required this.detail,
    this.listWidth = kChatListPaneWidth,
  });

  final Widget list;
  final Widget detail;
  final double listWidth;

  /// [child] sees a MediaQuery as wide as its pane.
  Widget _pane(BuildContext context, double width, Widget child) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(size: Size(width, media.size.height)),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final divider = context.palette.divider;
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 0.5;
        final detailWidth = constraints.maxWidth - listWidth - dividerWidth;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: listWidth, child: _pane(context, listWidth, list)),
            Container(width: dividerWidth, color: divider),
            Expanded(child: _pane(context, detailWidth, detail)),
          ],
        );
      },
    );
  }
}
