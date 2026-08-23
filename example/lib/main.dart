// Minimal integration example for the Watchdog package.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:watchdog/watchdog.dart';

// A Dio client wired with Watchdog — every request now shows up in the
// Network tab exactly like a Chopper one would.
final dio = Dio(BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com'))
  ..interceptors.add(Watchdog.dioInterceptor);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Single-call start — no separate initialize() needed.
  await Watchdog.start(
    config: const WatchdogConfig(
      apiBaseUrl: 'https://api.example.com',
    ),
  );

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Watchdog Example',
      debugShowCheckedModeBanner: false,
      home: ExamplePage(),
    );
  }
}

class ExamplePage extends StatelessWidget {
  const ExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🐕 Watchdog Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Open http://localhost:8888 in Chrome\n'
                  'to see live logs and network events.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                // Both a successful and a failing Dio call — watch them land
                // in the Network tab.
                await dio.get<dynamic>('/todos/1');
                try {
                  await dio.get<dynamic>('/this-route-does-not-exist');
                } on DioException {
                  // 404 still shows up as a (red) row in the Network tab.
                }
              },
              child: const Text('Fire Dio requests'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Watchdog.info('Button tapped', stackTrace: StackTrace.current);
              },
              child: const Text('Log an INFO event'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () {
                Watchdog.warning('This is a warning');
              },
              child: const Text('Log a WARNING'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Watchdog.error(
                  'Simulated error',
                  error: Exception('Something went wrong'),
                  stackTrace: StackTrace.current,
                );
              },
              child: const Text('Log an ERROR'),
            ),
          ],
        ),
      ),
    );
  }
}