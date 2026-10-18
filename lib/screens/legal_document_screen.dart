import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/diagnostic_logger.dart';
import '../legal/legal_info.dart';

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
  });

  const LegalDocumentScreen.terms({super.key})
    : title = 'Terms and Conditions',
      asset = LegalInfo.termsAsset;

  const LegalDocumentScreen.privacy({super.key})
    : title = 'Privacy Policy',
      asset = LegalInfo.privacyAsset;

  final String title;
  final String asset;

  static const Color primaryTeal = Color(0xFF23A8AA);
  static const Color darkTeal = Color(0xFF0D6E71);

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  static const String _tag = 'LegalDocument';
  static const Color primaryTeal = LegalDocumentScreen.primaryTeal;
  static const Color darkTeal = LegalDocumentScreen.darkTeal;

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
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F4),
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: FutureBuilder<String>(
              future: _document,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(
                    child: Text('Could not open this document.'),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: SelectionArea(
                    child: LegalText(snap.data!),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [darkTeal, Color(0xFF1A8587), primaryTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 20),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the small Markdown subset the legal documents use: `#`/`##`
/// headings, `- ` bullets, paragraphs (consecutive lines are joined) and
/// `**bold**` inline text.
class LegalText extends StatelessWidget {
  const LegalText(this.markdown, {super.key});

  final String markdown;

  /// `*italic*` markers (the text is kept, the stars are dropped).
  static final RegExp _italic = RegExp(r'\*([^*]+)\*');

  static const _body = TextStyle(
    fontSize: 14,
    height: 1.55,
    color: Colors.black87,
  );

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    final paragraph = <String>[];

    void flush() {
      if (paragraph.isEmpty) return;
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text.rich(_inline(paragraph.join(' '), _body)),
        ),
      );
      paragraph.clear();
    }

    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      if (line.startsWith('# ')) {
        flush();
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              line.substring(2),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        );
      } else if (line.startsWith('## ')) {
        flush();
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              line.substring(3),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0D6E71),
              ),
            ),
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
                const Text('•  ', style: _body),
                Expanded(child: Text.rich(_inline(line.substring(2), _body))),
              ],
            ),
          ),
        );
      } else if (line.isEmpty) {
        flush();
        if (children.isNotEmpty) children.add(const SizedBox(height: 2));
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
