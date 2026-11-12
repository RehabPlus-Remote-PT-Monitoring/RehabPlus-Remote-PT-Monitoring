import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../core/responsive.dart';
import '../ios/app_controls.dart';

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

  @override
  void initState() {
    super.initState();
    // main.dart logs why startup failed; this marks what the patient sees.
    DiagnosticLogger.I.info('Startup', 'Startup error screen shown');
  }

  Future<void> _retry() async {
    // The button is disabled while retrying; this also covers a fast double
    // tap that lands before the rebuild.
    if (_retrying) return;
    setState(() => _retrying = true);
    final logger = DiagnosticLogger.I;
    final stopwatch = Stopwatch()..start();
    logger.info('Startup', 'Retrying startup');
    Widget next;
    try {
      next = await widget.onRetry();
    } catch (e, st) {
      // onRetry normally reports failure by returning another error screen;
      // if it throws instead, stay here with the button usable again rather
      // than spinning forever.
      logger.error('Startup', 'Startup retry crashed', {
        'ms': stopwatch.elapsedMilliseconds,
      }, e, st);
      if (mounted) setState(() => _retrying = false);
      return;
    }
    if (!mounted) return;
    final failedAgain = next is StartupErrorScreen;
    logger.info('Startup', 'Startup retry finished', {
      'ms': stopwatch.elapsedMilliseconds,
      'ok': !failedAgain,
      'next': next.runtimeType.toString(),
    });
    if (failedAgain) {
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
                    Icons.cloud_off_rounded,
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
                  AppButton(label: _retrying ? 'Trying again...' : 'Try again', onPressed: _retrying ? null : _retry, sfSymbol: 'arrow.clockwise', material: () => FilledButton.icon(
                    onPressed: _retrying ? null : _retry,
                    icon: _retrying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(_retrying ? 'Trying again...' : 'Try again'),
                  )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
