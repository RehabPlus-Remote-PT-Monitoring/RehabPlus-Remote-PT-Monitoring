import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/services/cast_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(CastService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void answerWith(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  test('returns true when the native side opened a settings page', () async {
    String? calledMethod;
    answerWith((call) async {
      calledMethod = call.method;
      return 'android.settings.CAST_SETTINGS';
    });

    final opened = await CastService(isAndroid: true).openCastSettings();

    expect(opened, isTrue);
    expect(calledMethod, 'openCastSettings');
  });

  test('returns false when the phone has no cast settings page', () async {
    answerWith((_) async => null);
    expect(await CastService(isAndroid: true).openCastSettings(), isFalse);
  });

  test('returns false instead of throwing on a platform error', () async {
    answerWith((_) async => throw PlatformException(code: 'boom'));
    expect(await CastService(isAndroid: true).openCastSettings(), isFalse);
  });

  test('returns false when the native handler is missing', () async {
    // No mock handler registered -> MissingPluginException.
    expect(await CastService(isAndroid: true).openCastSettings(), isFalse);
  });

  test('does not call the channel off Android', () async {
    var called = false;
    answerWith((_) async {
      called = true;
      return 'x';
    });
    expect(await CastService(isAndroid: false).openCastSettings(), isFalse);
    expect(called, isFalse);
  });
}
