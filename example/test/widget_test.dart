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

  testWidgets('example renders its actions', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Fire Dio requests'), findsOneWidget);
    expect(find.text('Log an INFO event'), findsOneWidget);
    expect(find.text('Log an ERROR'), findsOneWidget);
  });
}
