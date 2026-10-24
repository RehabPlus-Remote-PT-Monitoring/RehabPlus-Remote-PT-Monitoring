import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../core/responsive.dart';

/// Shown instead of the splash's next screen when app startup failed (for
/// example Firebase couldn't initialise). Lets the patient try again rather
/// than staring at a splash screen that never finishes.
class StartupErrorScreen extends StatefulWidget {
  const StartupErrorScreen({super.key, required this.onRetry});

  /// Re-runs startup and resolves to the screen to show next.
  final Future<Widget> Function() onRetry;

  @override
  State<StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<StartupErrorScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    DiagnosticLogger.I.info('Startup', 'Retrying startup');
    final next = await widget.onRetry();
    if (!mounted) return;
    if (next is StartupErrorScreen) {
      // Failed again: stay here and let the patient retry once more.
      setState(() => _retrying = false);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => next),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ReadableWidth(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.wifi_slash,
                    size: 64,
                    color: Color(0xFF00BCD4),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'RehabPlus could not start',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your internet connection and try again. '
                    'If this keeps happening, contact the clinic.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.palette.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _retrying ? null : _retry,
                    icon: _retrying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                          )
                        : const Icon(CupertinoIcons.arrow_clockwise),
                    label: Text(_retrying ? 'Trying again...' : 'Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
