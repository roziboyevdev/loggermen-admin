import 'package:flutter_test/flutter_test.dart';

import 'package:watchdog_example/main.dart';

void main() {
  group('isValidWatchdogServerUrl', () {
    test('accepts an origin', () {
      expect(isValidWatchdogServerUrl('wss://loggermen.roziboyevdev.uz'), isTrue);
      expect(isValidWatchdogServerUrl('ws://192.168.1.50:8080'), isTrue);
      expect(isValidWatchdogServerUrl('wss://host/'), isTrue);
    });

    test('rejects what the package cannot dial', () {
      // Empty define — the case that produced an endless retry loop.
      expect(isValidWatchdogServerUrl(''), isFalse);
      expect(isValidWatchdogServerUrl('   '), isFalse);
      // Missing scheme.
      expect(isValidWatchdogServerUrl('loggermen.roziboyevdev.uz'), isFalse);
      // http(s) is not a socket scheme.
      expect(isValidWatchdogServerUrl('https://loggermen.roziboyevdev.uz'), isFalse);
      // A path makes the client request ".../watchdog/ws/app".
      expect(isValidWatchdogServerUrl('wss://host/watchdog'), isFalse);
    });
  });

  group('isValidWatchdogClientKey', () {
    test('accepts a real key', () {
      expect(
        isValidWatchdogClientKey('f0e44ef9c41ee0bdc943c9a0cc4b959de60a50299f45bfa1'),
        isTrue,
      );
    });

    test('rejects placeholders that are merely non-empty', () {
      expect(isValidWatchdogClientKey(''), isFalse);
      expect(isValidWatchdogClientKey('   '), isFalse);
      // The server template's own value.
      expect(isValidWatchdogClientKey('change-client-key'), isFalse);
      // build.example.json ships this marker.
      expect(isValidWatchdogClientKey('<serverdagi .env dagi key>'), isFalse);
    });
  });

  test('a localhost fallback would have passed the shape check', () {
    // Why the defaults are empty rather than "helpful": this URL is valid, so
    // only an empty default keeps a define-less build from dialling the phone.
    expect(isValidWatchdogServerUrl('ws://localhost:8080'), isTrue);
  });

  testWidgets('example renders its actions', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Fire Dio requests'), findsOneWidget);
    expect(find.text('Log an INFO event'), findsOneWidget);
    expect(find.text('Log an ERROR'), findsOneWidget);
  });
}
