import 'dart:async';
import 'dart:io';

const _defaultPort = 8888;
const _version = '0.2.0';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exit(64);
  }

  final command = args.first;
  final rest = args.skip(1).toList();

  switch (command) {
    case 'open':
      await _openCommand(rest);
      break;
    case 'forward':
      await _forwardCommand(rest);
      break;
    case 'devices':
      await _devicesCommand();
      break;
    case '--help':
    case '-h':
    case 'help':
      _printUsage();
      break;
    case '--version':
    case '-v':
    case 'version':
      stdout.writeln('watchdog $_version');
      break;
    default:
      stderr.writeln('Unknown command: $command');
      _printUsage();
      exit(64);
  }
}

Future<void> _openCommand(List<String> args) async {
  final port = _parsePort(args);
  final skipAdb = args.contains('--no-adb');
  final url = 'http://localhost:$port';

  stdout.writeln('Watchdog DevTools');
  stdout.writeln('  port: $port');
  stdout.writeln('  url:  $url');
  stdout.writeln('');

  if (!skipAdb) {
    await _runAdbForward(port);
  } else {
    stdout.writeln('Skipping adb forward (--no-adb).');
  }

  stdout.writeln('');
  stdout.writeln('Opening $url in your default browser...');
  final ok = await _openUrl(url);
  if (!ok) {
    stderr.writeln('Could not open browser automatically. Visit $url manually.');
    exit(1);
  }
}

Future<void> _forwardCommand(List<String> args) async {
  final port = _parsePort(args);
  final ok = await _runAdbForward(port);
  if (!ok) exit(1);
}

Future<void> _devicesCommand() async {
  final adb = await _findAdb();
  if (adb == null) {
    stderr.writeln('adb not found on PATH.');
    stderr.writeln('Install Android platform tools or run `watchdog open --no-adb`.');
    exit(1);
  }
  final result = await Process.run(adb, ['devices']);
  stdout.write(result.stdout);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    exit(result.exitCode);
  }
}

int _parsePort(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--port' || a == '-p') {
      if (i + 1 >= args.length) {
        stderr.writeln('Missing value for $a');
        exit(64);
      }
      return int.tryParse(args[i + 1]) ??
          (throw FormatException('Invalid port: ${args[i + 1]}'));
    }
    if (a.startsWith('--port=')) {
      return int.tryParse(a.substring('--port='.length)) ??
          (throw FormatException('Invalid port: $a'));
    }
  }
  return _defaultPort;
}

Future<bool> _runAdbForward(int port) async {
  final adb = await _findAdb();
  if (adb == null) {
    stdout.writeln('adb not found on PATH — skipping port forwarding.');
    stdout.writeln('(Needed only for Android emulator or USB-connected device.)');
    return false;
  }

  final result = await Process.run(adb, [
    'forward',
    'tcp:$port',
    'tcp:$port',
  ]);

  if (result.exitCode == 0) {
    stdout.writeln('adb forward tcp:$port tcp:$port — OK');
    return true;
  }

  final err = (result.stderr as String).trim();
  if (err.contains('no devices/emulators found')) {
    stdout.writeln('adb: no Android device connected — skipping port forwarding.');
    stdout.writeln('(This is fine for iOS simulator or physical iOS devices.)');
    return true;
  }

  stderr.writeln('adb forward failed: $err');
  return false;
}

Future<String?> _findAdb() async {
  final which = Platform.isWindows ? 'where' : 'which';
  try {
    final result = await Process.run(which, ['adb']);
    if (result.exitCode == 0) {
      final out = (result.stdout as String).trim().split('\n').first.trim();
      if (out.isNotEmpty) return out;
    }
  } on ProcessException {
    // fall through
  }

  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null) return null;

  final candidates = <String>[
    if (Platform.isMacOS) '$home/Library/Android/sdk/platform-tools/adb',
    if (Platform.isLinux) '$home/Android/Sdk/platform-tools/adb',
    if (Platform.isWindows) '$home\\AppData\\Local\\Android\\Sdk\\platform-tools\\adb.exe',
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

Future<bool> _openUrl(String url) async {
  try {
    if (Platform.isMacOS) {
      final r = await Process.run('open', [url]);
      return r.exitCode == 0;
    }
    if (Platform.isLinux) {
      final r = await Process.run('xdg-open', [url]);
      return r.exitCode == 0;
    }
    if (Platform.isWindows) {
      final r = await Process.run('cmd', ['/c', 'start', '', url]);
      return r.exitCode == 0;
    }
  } on ProcessException catch (e) {
    stderr.writeln('Failed to open browser: $e');
  }
  return false;
}

void _printUsage() {
  stdout.writeln('''
Watchdog DevTools CLI

Usage:
  watchdog <command> [options]

Commands:
  open         Forward the Watchdog port (via adb, if available) and open
               http://localhost:<port> in the default browser.
  forward      Only run `adb forward` for the Watchdog port (no browser).
  devices      List Android devices visible to adb.
  help         Show this message.
  version      Print the CLI version.

Options:
  -p, --port <port>   Port used by Watchdog (default: $_defaultPort).
      --no-adb        Skip adb port-forwarding (iOS simulator / real WiFi).

Examples:
  watchdog open
  watchdog open --port 9000
  watchdog open --no-adb
  watchdog forward
''');
}
