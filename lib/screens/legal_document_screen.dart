import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../legal/legal_info.dart';
import '../core/responsive.dart';
import '../widgets/info_content_unavailable.dart';
import '../widgets/ios_page.dart';

/// Shows one of the legal documents in assets/legal/ (Terms and Conditions or
/// Privacy Policy), with the clinic details filled in.
///
/// The document is loaded once in initState (not in build), so rebuilds
/// (keyboard, rotation, text size) don't reload and re-parse it. The files
/// are ~10 KB, so loading and filling them on the UI isolate takes about a
/// millisecond; a background isolate would cost more than it saves. The
/// load time is logged so that can be checked.
class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.asset,
    this.previousPageTitle,
  });

  const LegalDocumentScreen.terms({super.key, this.previousPageTitle})
    : title = 'Terms and Conditions',
      asset = LegalInfo.termsAsset;

  const LegalDocumentScreen.privacy({super.key, this.previousPageTitle})
    : title = 'Privacy Policy',
      asset = LegalInfo.privacyAsset;

  final String title;
  final String asset;

  /// The back button's label ("‹ Privacy"). Null (e.g. from the consent
  /// screen) shows a bare chevron.
  final String? previousPageTitle;

  static const Color primaryTeal = Color(0xFF23A8AA);
  static const Color darkTeal = Color(0xFF0D6E71);

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  static const String _tag = 'LegalDocument';

  final DiagnosticLogger _logger = DiagnosticLogger.I;

  /// The filled-in document; created once so rebuilds reuse it.
  late final Future<String> _document = _load();

  String get title => widget.title;

  @override
  void initState() {
    super.initState();
    _logger.info(_tag, 'Screen opened', {'asset': widget.asset});
  }

  Future<String> _load() async {
    final stopwatch = Stopwatch()..start();
    try {
      final text = LegalInfo.fill(await rootBundle.loadString(widget.asset));
      _logger.info(_tag, 'Document loaded', {
        'asset': widget.asset,
        'chars': text.length,
        'ms': stopwatch.elapsedMilliseconds,
      });
      return text;
    } catch (e, st) {
      _logger.error(
        _tag,
        'Document failed to load',
        {'asset': widget.asset},
        e,
        st,
      );
      rethrow; // shown as "Could not open this document."
    }
  }

  @override
  Widget build(BuildContext context) {
    return IosPage(
      title: title,
      previousPageTitle: widget.previousPageTitle,
      slivers: [
        FutureBuilder<String>(
          future: _document,
          builder: (context, snap) {
            if (snap.hasError) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: InfoContentUnavailable(
                  icon: CupertinoIcons.doc_text,
                  title: 'Could not open this document.',
                  body: 'Go back and open it again.',
                ),
              );
            }
            if (!snap.hasData) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator.adaptive()),
              );
            }
            return SliverPadding(
              // Readable line length on tablets too: the text stays in a
              // [kReadableMaxWidth] column however wide the screen is.
              padding: readablePadding(
                context,
                const EdgeInsets.fromLTRB(20, 8, 20, 40),
                kReadableMaxWidth,
              ),
              sliver: SliverToBoxAdapter(
                child: SelectionArea(
                  // The navigation bar already shows the title.
                  child: LegalText(snap.data!, omitTitle: true),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Renders the small Markdown subset the legal documents use: `#`/`##`
/// headings, `- ` bullets, paragraphs (consecutive lines are joined) and
/// `**bold**` inline text.
class LegalText extends StatelessWidget {
  const LegalText(this.markdown, {super.key, this.omitTitle = false});

  final String markdown;

  /// Skips the document's first `# ` heading, for pages whose navigation
  /// bar already shows the title (it would otherwise appear twice).
  final bool omitTitle;

  /// `*italic*` markers (the text is kept, the stars are dropped).
  static final RegExp _italic = RegExp(r'\*([^*]+)\*');

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    // Body text at iOS Body size (17) with a generous line height, so a
    // long legal document is comfortable to read.
    final body = (textTheme.bodyLarge ?? const TextStyle(fontSize: 17))
        .copyWith(height: 1.45, color: palette.textPrimary);
    // Headings in the label colour, not teal: colour is kept for meaning.
    final titleStyle = textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: palette.textPrimary,
    );
    final sectionStyle = textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: palette.textPrimary,
    );
    final children = <Widget>[];
    final paragraph = <String>[];
    var titleSkipped = !omitTitle;

    void flush() {
      if (paragraph.isEmpty) return;
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text.rich(_inline(paragraph.join(' '), body)),
        ),
      );
      paragraph.clear();
    }

    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      if (line.startsWith('# ')) {
        flush();
        if (!titleSkipped) {
          titleSkipped = true;
          continue;
        }
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(line.substring(2), style: titleStyle),
          ),
        );
      } else if (line.startsWith('## ')) {
        flush();
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(line.substring(3), style: sectionStyle),
          ),
        );
      } else if (line.startsWith('- ')) {
        flush();
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: body),
                Expanded(child: Text.rich(_inline(line.substring(2), body))),
              ],
            ),
          ),
        );
      } else if (line.isEmpty) {
        flush();
      } else {
        paragraph.add(line);
      }
    }
    flush();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// Splits on `**` markers; odd segments are bold, `*text*` is italic.
  static TextSpan _inline(String text, TextStyle style) {
    final parts = text.split('**');
    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i < parts.length; i++)
          TextSpan(
            text: parts[i].replaceAllMapped(_italic, (m) => m[1]!),
            style: i.isOdd
                ? const TextStyle(fontWeight: FontWeight.bold)
                : null,
          ),
      ],
    );
  }
}
