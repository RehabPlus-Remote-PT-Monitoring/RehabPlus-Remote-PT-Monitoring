// Opens the phone's screen-cast settings for the "Cast screen" button on the
// exercise screen.
//
// Why: the patient stands 2-3 m from the phone so the camera sees their whole
// body, and from there the rep counter and form warnings are too small to
// read. Mirroring the phone to a TV or laptop fixes that without any accounts
// or extra hardware beyond what the patient already owns.
//
// Android has no public API to start a cast, so the native side
// (android/app/src/main/kotlin/com/rehabplus/app/MainActivity.kt) opens the
// cast settings page and the patient picks their TV there. When that page
// doesn't exist (some brands hide it, or we're not on Android) the caller
// shows written instructions instead; see [castInstructions].

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../core/diagnostic_logger.dart';

class CastService {
  /// [channel] and [isAndroid] are injectable so tests can run without a
  /// device.
  CastService({MethodChannel? channel, bool? isAndroid})
    : _channel = channel ?? const MethodChannel(channelName),
      _isAndroid = isAndroid ?? Platform.isAndroid;

  /// Must match CAST_CHANNEL in MainActivity.kt.
  static const String channelName = 'com.rehabplus.app/cast';

  final MethodChannel _channel;
  final bool _isAndroid;
  final DiagnosticLogger _log = DiagnosticLogger.I;

  /// [isCasting] is polled every few seconds, so its failure is logged once,
  /// not on every poll.
  bool _isCastingFailureLogged = false;

  /// Tries to open the system cast settings.
  ///
  /// Returns true if a settings page opened. Returns false (never throws)
  /// when there is no such page or the call failed, so the caller can fall
  /// back to [castInstructions].
  Future<bool> openCastSettings() async {
    if (!_isAndroid) {
      _log.info('Cast', 'Cast settings skipped: not Android');
      return false;
    }
    try {
      final openedAction = await _channel.invokeMethod<String>(
        'openCastSettings',
      );
      if (openedAction == null) {
        _log.warn('Cast', 'No cast settings page on this phone');
        return false;
      }
      _log.info('Cast', 'Opened cast settings', {'action': openedAction});
      return true;
    } on MissingPluginException catch (e, st) {
      // Native handler missing (e.g. an old build of MainActivity).
      _log.warn('Cast', 'Cast channel not registered', null, e, st);
      return false;
    } on PlatformException catch (e, st) {
      _log.warn('Cast', 'Opening cast settings failed', null, e, st);
      return false;
    }
  }

  /// Whether the screen is currently being cast to a TV or external display.
  /// False (never throws) when unknown, e.g. off Android or on failure.
  Future<bool> isCasting() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isCasting') ?? false;
    } on Exception catch (e, st) {
      // MissingPluginException / PlatformException: treat as not casting.
      if (!_isCastingFailureLogged) {
        _isCastingFailureLogged = true;
        _log.warn('Cast', 'Could not check casting state', null, e, st);
      }
      return false;
    }
  }
}

/// Short line shown under the "where to stand" tip on the exercise screen.
const String castHint =
    'Too far to read the screen? Tap the cast button at the top to show it '
    'on a TV or laptop.';

/// Step-by-step help shown when the settings page can't be opened, or when
/// the patient wants to know what to do on the cast page.
const List<String> castInstructions = [
  'Turn on the TV or laptop and connect it to the same Wi-Fi as your phone.',
  'On your phone, swipe down from the top and tap "Screen Cast", '
      '"Smart View" or "Cast" (the name depends on your phone).',
  'Chromecast or Google TV: open the Google Home app and tap '
      '"Cast my screen".',
  'Windows laptop: open the "Connect" app on the laptop (Settings > System > '
      'Projecting to this PC) so it shows up in your phone\'s cast list.',
  'Pick your TV or laptop from the list, then come back to RehabPlus. '
      'Turning the phone sideways fills more of the TV.',
];
