import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'watchdog_broadcaster.dart';

/// Runs a local HTTP + WebSocket server that:
///
///  - `GET  /`        → serves the self-contained [watchdogHtml] DevTools page
///  - `GET  /stream`  → upgrades to a WebSocket; used by the HTML page
///  - `GET  /health`  → simple JSON health-check (useful for CI/ping)
///
/// Start with [WatchdogServer.start], stop with [WatchdogServer.stop].
class WatchdogServer {
  WatchdogServer({
    required this.broadcaster,
    this.port = 8888,
    this.host = '0.0.0.0',
    this.onLocationRefreshRequested,
  });

  final WatchdogBroadcaster broadcaster;
  final int port;
  final String host;

  /// Called when the DevTools page sends a `location_refresh_request`
  /// command (e.g. a Location tab refresh button). Wired by
  /// [WatchdogRuntime] to [WatchdogLocationTracker.refreshLocation]. Since
  /// this server runs in-process with the app itself, no relay is needed —
  /// the HTML page talks straight to the device.
  final void Function()? onLocationRefreshRequested;

  HttpServer? _server;

  bool get isRunning => _server != null;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Starts the server. Prints the DevTools URL to the console.
  Future<void> start() async {
    if (_server != null) return; // already running

    final router = Router()
      ..get('/', _htmlHandler)
      ..get('/stream', _wsHandler)
      ..get('/health', _healthHandler);

    final handler = const Pipeline().addMiddleware(_corsMiddleware()).addHandler(router.call);

    _server = await shelf_io.serve(handler, host, port);
    _server!.autoCompress = true;

    final wifiIp = await _getWifiIpAddress();
    final displayHost = wifiIp ?? host;

    // ignore: avoid_print
    print(
      '\n🐕 Watchdog DevTools running → http://$displayHost:$port\n'
      '   Open this URL in any browser on the same network.\n',
    );
  }

  /// Stops the server gracefully.
  Future<void> stop() async {
    await _server?.close(force: false);
    _server = null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns the device's WiFi/LAN IP address, or null if unavailable.
  Future<String?> _getWifiIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        // Skip docker, VPN, and other virtual interfaces
        final name = iface.name.toLowerCase();
        if (name.startsWith('docker') ||
            name.startsWith('veth') ||
            name.startsWith('br-')) {
          continue;
        }
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  // ── Handlers ──────────────────────────────────────────────────────────────

  /// Serves the embedded HTML DevTools page.
  Response _htmlHandler(Request request) {
    return Response.ok(_kWatchdogHtml, headers: {'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache'});
  }

  /// Upgrades HTTP to WebSocket and registers the client with [WatchdogBroadcaster].
  Handler get _wsHandler {
    return webSocketHandler((WebSocketChannel channel, String? protocol) {
      broadcaster.addClient(channel);

      channel.stream.listen(
        (message) {
          // Handle commands from the HTML page (e.g. "clear")
          if (message == 'clear') {
            broadcaster.broadcastClear();
            return;
          }
          if (message is String) {
            try {
              final data = jsonDecode(message) as Map<String, dynamic>;
              if (data['type'] == 'location_refresh_request') {
                onLocationRefreshRequested?.call();
              }
            } catch (_) {
              // Not JSON / not a recognized command — ignore.
            }
          }
        },
        onDone: () => broadcaster.removeClient(channel),
        onError: (_) => broadcaster.removeClient(channel),
        cancelOnError: true,
      );
    });
  }

  /// Returns a simple health-check response.
  Response _healthHandler(Request request) {
    return Response.ok(
      '{"status":"ok","clients":${broadcaster.clientCount}}',
      headers: {'Content-Type': 'application/json'},
    );
  }

  // ── CORS middleware ───────────────────────────────────────────────────────

  /// Adds CORS headers so the HTML page can connect even when served from a
  /// different origin during development.
  Middleware _corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await innerHandler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  static const Map<String, String> _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type',
  };
}

const String _kWatchdogHtml = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Watchdog DevTools</title>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg0:#121212;--bg1:#1e1e1e;--bg2:#252526;--bg3:#2d2d2d;--bg4:#37373d;
  --border:#3c3c3c;--border-light:#505050;
  --text1:#e0e0e0;--text2:#a0a0a0;--text3:#6a6a6a;
  --accent:#3b9eff;--accent-dim:#264f78;
  --green:#4ec9b0;--red:#f44747;--orange:#ce9178;--yellow:#dcdcaa;
  --cyan:#9cdcfe;--purple:#c586c0;--blue:#569cd6;--magenta:#d16d9e;
  --method-get:#4ec9b0;--method-post:#569cd6;--method-put:#ce9178;
  --method-delete:#f44747;--method-patch:#c586c0;
  --status-2xx:#4ec9b0;--status-3xx:#569cd6;--status-4xx:#ce9178;--status-5xx:#f44747;
  --radius:6px;--radius-sm:4px;
  --font-mono:"SF Mono","Fira Code","Cascadia Code",Consolas,monospace;
  --font-sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
}
html,body{height:100%;overflow:hidden;font-family:var(--font-sans);background:var(--bg0);color:var(--text1);font-size:13px;line-height:1.5}
::-webkit-scrollbar{width:8px;height:8px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:var(--border);border-radius:4px}
::-webkit-scrollbar-thumb:hover{background:var(--border-light)}

/* ── Layout ──────────────────────────────────────────── */
#app{display:flex;flex-direction:column;height:100vh}
.topbar{display:flex;align-items:center;height:44px;padding:0 16px;background:var(--bg2);border-bottom:1px solid var(--border);flex-shrink:0;gap:12px}
.topbar-logo{display:flex;align-items:center;gap:8px;font-weight:600;font-size:14px;color:var(--text1)}
.topbar-logo svg{width:20px;height:20px}
.topbar-spacer{flex:1}
.topbar-stats{display:flex;gap:16px;font-size:12px;color:var(--text2)}
.topbar-stats span{display:flex;align-items:center;gap:4px}
.stat-count{color:var(--text1);font-weight:600;font-variant-numeric:tabular-nums}
.conn-status{display:flex;align-items:center;gap:6px;font-size:12px}
.conn-dot{width:8px;height:8px;border-radius:50%;transition:background .3s}
.conn-dot.on{background:var(--green)}
.conn-dot.off{background:var(--red);animation:pulse-dot 1.5s infinite}
@keyframes pulse-dot{0%,100%{opacity:1}50%{opacity:.4}}
.btn{background:var(--bg3);border:1px solid var(--border);color:var(--text2);padding:4px 12px;border-radius:var(--radius-sm);cursor:pointer;font-size:12px;transition:all .15s}
.btn:hover{background:var(--bg4);color:var(--text1);border-color:var(--border-light)}
.btn-danger:hover{background:#5c2020;border-color:var(--red);color:var(--red)}

.tab-bar{display:flex;height:36px;background:var(--bg1);border-bottom:1px solid var(--border);padding:0 16px;flex-shrink:0}
.tab-btn{position:relative;padding:0 16px;height:100%;display:flex;align-items:center;gap:6px;background:none;border:none;color:var(--text2);cursor:pointer;font-size:13px;font-family:var(--font-sans);transition:color .15s}
.tab-btn:hover{color:var(--text1)}
.tab-btn.active{color:var(--text1)}
.tab-btn.active::after{content:"";position:absolute;bottom:0;left:0;right:0;height:2px;background:var(--accent);border-radius:2px 2px 0 0}
.tab-badge{background:var(--bg4);color:var(--text2);font-size:10px;padding:1px 6px;border-radius:10px;font-weight:600;min-width:18px;text-align:center}
.tab-btn.active .tab-badge{background:var(--accent-dim);color:var(--accent)}

.content-area{flex:1;display:flex;overflow:hidden;position:relative}
.tab-panel{display:none;flex-direction:column;flex:1;overflow:hidden}
.tab-panel.active{display:flex}

/* ── Filter Bar ──────────────────────────────────────── */
.filter-bar{display:flex;align-items:center;gap:10px;padding:8px 16px;background:var(--bg1);border-bottom:1px solid var(--border);flex-shrink:0;flex-wrap:wrap}
.search-box{position:relative;flex:0 0 260px}
.search-box input{width:100%;height:28px;background:var(--bg3);border:1px solid var(--border);border-radius:var(--radius-sm);padding:0 8px 0 28px;color:var(--text1);font-size:12px;font-family:var(--font-sans);outline:none;transition:border-color .15s}
.search-box input:focus{border-color:var(--accent)}
.search-box input::placeholder{color:var(--text3)}
.search-box::before{content:"\2315";position:absolute;left:9px;top:50%;transform:translateY(-50%);color:var(--text3);font-size:14px;pointer-events:none}
.filter-sep{width:1px;height:20px;background:var(--border)}
.filter-label{font-size:11px;color:var(--text3);text-transform:uppercase;letter-spacing:.5px}
.chip{display:inline-flex;align-items:center;height:24px;padding:0 8px;border-radius:12px;font-size:11px;font-weight:600;cursor:pointer;transition:all .15s;border:1px solid transparent;user-select:none}
.chip.on{opacity:1}.chip.off{opacity:.3}
.chip:hover{opacity:.8}
.chip-get{background:rgba(78,201,176,.15);color:var(--method-get);border-color:rgba(78,201,176,.3)}
.chip-post{background:rgba(86,156,214,.15);color:var(--method-post);border-color:rgba(86,156,214,.3)}
.chip-put{background:rgba(206,145,120,.15);color:var(--method-put);border-color:rgba(206,145,120,.3)}
.chip-delete{background:rgba(244,71,71,.15);color:var(--method-delete);border-color:rgba(244,71,71,.3)}
.chip-patch{background:rgba(197,134,192,.15);color:var(--method-patch);border-color:rgba(197,134,192,.3)}
.chip-2xx{background:rgba(78,201,176,.15);color:var(--status-2xx)}
.chip-3xx{background:rgba(86,156,214,.15);color:var(--status-3xx)}
.chip-4xx{background:rgba(206,145,120,.15);color:var(--status-4xx)}
.chip-5xx{background:rgba(244,71,71,.15);color:var(--status-5xx)}
.chip-verbose{background:rgba(106,106,106,.15);color:var(--text3)}
.chip-debug{background:rgba(156,220,254,.12);color:var(--cyan)}
.chip-info{background:rgba(78,201,176,.12);color:var(--green)}
.chip-warning{background:rgba(220,220,170,.12);color:var(--yellow)}
.chip-error{background:rgba(244,71,71,.12);color:var(--red)}
.chip-critical{background:rgba(244,71,71,.25);color:#ff8a8a}

/* ── Network Table ───────────────────────────────────── */
.table-wrap{flex:1;overflow:auto}
.net-table{width:100%;border-collapse:collapse;table-layout:fixed}
.net-table th{position:sticky;top:0;background:var(--bg2);color:var(--text2);font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:.5px;padding:8px 12px;text-align:left;border-bottom:1px solid var(--border);z-index:2}
.net-table td{padding:7px 12px;border-bottom:1px solid var(--bg3);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-size:12px;vertical-align:middle}
.net-table th:nth-child(1),.net-table td:nth-child(1){width:48px;text-align:center}
.net-table th:nth-child(2),.net-table td:nth-child(2){width:42px;text-align:center}
.net-table th:nth-child(3),.net-table td:nth-child(3){width:72px}
.net-table th:nth-child(4),.net-table td:nth-child(4){width:auto;min-width:200px}
.net-table th:nth-child(5),.net-table td:nth-child(5){width:72px;text-align:center}
.net-table th:nth-child(6),.net-table td:nth-child(6){width:80px;text-align:right}
.net-table th:nth-child(7),.net-table td:nth-child(7){width:120px;text-align:right;white-space:nowrap}
.row-num{font-family:var(--font-mono);font-size:11px;color:var(--text3);overflow:visible;white-space:nowrap}
.net-row{cursor:pointer;transition:background .1s}
.net-row:hover{background:var(--bg3)}
.net-row.selected{background:var(--bg4)}
.net-row.pending{animation:pulse-row 1.5s infinite}
@keyframes pulse-row{0%,100%{opacity:1}50%{opacity:.5}}
.status-dot-cell{width:10px;height:10px;border-radius:50%;display:inline-block}
.status-dot-cell.s2xx{background:var(--status-2xx)}.status-dot-cell.s3xx{background:var(--status-3xx)}
.status-dot-cell.s4xx{background:var(--status-4xx)}.status-dot-cell.s5xx{background:var(--status-5xx)}
.status-dot-cell.pending{background:var(--text3)}.status-dot-cell.failed{background:var(--red)}
.method-badge{display:inline-block;padding:1px 6px;border-radius:3px;font-size:11px;font-weight:700;font-family:var(--font-mono);letter-spacing:.3px}
.method-badge.GET{background:rgba(78,201,176,.15);color:var(--method-get)}
.method-badge.POST{background:rgba(86,156,214,.15);color:var(--method-post)}
.method-badge.PUT{background:rgba(206,145,120,.15);color:var(--method-put)}
.method-badge.DELETE{background:rgba(244,71,71,.15);color:var(--method-delete)}
.method-badge.PATCH{background:rgba(197,134,192,.15);color:var(--method-patch)}
.status-code{font-family:var(--font-mono);font-weight:600;font-size:12px}
.status-code.s2xx{color:var(--status-2xx)}.status-code.s3xx{color:var(--status-3xx)}
.status-code.s4xx{color:var(--status-4xx)}.status-code.s5xx{color:var(--status-5xx)}
.status-code.failed{color:var(--red)}
.duration{font-family:var(--font-mono);color:var(--text2);font-size:12px}
.duration.slow{color:var(--orange)}.duration.very-slow{color:var(--red)}
.timestamp{font-family:var(--font-mono);color:var(--text3);font-size:11px;overflow:visible;white-space:nowrap}
.path-text{color:var(--text1)}.path-host{color:var(--text3);font-size:11px;margin-left:6px}

/* ── Detail Panel ────────────────────────────────────── */
.detail-overlay{position:absolute;top:0;right:0;bottom:0;width:520px;background:var(--bg1);border-left:1px solid var(--border);display:flex;flex-direction:column;transform:translateX(100%);transition:transform .2s ease;z-index:10;box-shadow:-4px 0 20px rgba(0,0,0,.3)}
.detail-overlay.open{transform:translateX(0)}
.detail-header{display:flex;align-items:center;justify-content:space-between;padding:10px 16px;border-bottom:1px solid var(--border);flex-shrink:0}
.detail-title{font-weight:600;font-size:13px;display:flex;align-items:center;gap:8px}
.detail-close{background:none;border:none;color:var(--text2);cursor:pointer;font-size:18px;line-height:1;padding:4px;border-radius:var(--radius-sm)}
.detail-close:hover{background:var(--bg3);color:var(--text1)}
.detail-body{flex:1;overflow-y:auto;padding:0}
.detail-section{border-bottom:1px solid var(--border)}
.section-head{display:flex;align-items:center;gap:6px;padding:10px 16px;cursor:pointer;font-size:12px;font-weight:600;color:var(--text2);user-select:none;transition:background .1s}
.section-head:hover{background:var(--bg3);color:var(--text1)}
.section-chevron{font-size:10px;transition:transform .15s;display:inline-block;width:12px}
.section-head.open .section-chevron{transform:rotate(90deg)}
.section-content{display:none;padding:0 16px 12px}
.section-head.open+.section-content{display:block}
.kv-table{width:100%;font-size:12px}
.kv-table td{padding:3px 0;vertical-align:top}
.kv-table td:first-child{color:var(--purple);font-family:var(--font-mono);white-space:nowrap;padding-right:16px;width:1%;font-size:11px}
.kv-table td:last-child{color:var(--text1);font-family:var(--font-mono);word-break:break-all;font-size:11px}
.detail-general{display:grid;grid-template-columns:auto 1fr;gap:4px 16px;font-size:12px}
.detail-general dt{color:var(--text3);font-size:11px}.detail-general dd{color:var(--text1);font-family:var(--font-mono);word-break:break-all;font-size:12px}
.json-pre{background:var(--bg0);border:1px solid var(--border);border-radius:var(--radius-sm);padding:12px;overflow-x:auto;font-family:var(--font-mono);font-size:11px;line-height:1.6;max-height:400px;white-space:pre-wrap;word-break:break-word}
.j-key{color:var(--purple)}.j-str{color:var(--orange)}.j-num{color:var(--green)}.j-bool{color:var(--blue)}.j-null{color:var(--text3)}
.curl-pre{background:var(--bg0);border:1px solid var(--border);border-radius:var(--radius-sm);padding:12px;font-family:var(--font-mono);font-size:11px;line-height:1.6;white-space:pre-wrap;word-break:break-all;color:var(--text1)}
.copy-btn{display:inline-flex;align-items:center;gap:4px;padding:3px 10px;background:var(--bg3);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text2);cursor:pointer;font-size:11px;margin-top:8px;transition:all .15s}
.copy-btn:hover{background:var(--bg4);color:var(--text1)}.copy-btn.copied{color:var(--green);border-color:var(--green)}
.section-toolbar{display:flex;justify-content:flex-end;margin-bottom:6px}
.url-full{font-family:var(--font-mono);font-size:11px;color:var(--cyan);word-break:break-all;padding:8px;background:var(--bg0);border-radius:var(--radius-sm);margin-bottom:8px}
.error-box{background:rgba(244,71,71,.08);border:1px solid rgba(244,71,71,.2);border-radius:var(--radius-sm);padding:12px;font-family:var(--font-mono);font-size:11px;color:var(--red);white-space:pre-wrap}
.stack-pre{margin-top:8px;color:var(--text2);font-size:10px;max-height:200px;overflow:auto}

/* ── Log Cards ───────────────────────────────────────── */
.log-list{flex:1;overflow-y:auto;padding:4px 0}
.log-num{flex-shrink:0;width:32px;font-family:var(--font-mono);font-size:11px;color:var(--text3);text-align:right;padding-top:2px}
.log-card{display:flex;gap:10px;padding:8px 16px;border-bottom:1px solid var(--bg3);cursor:default;transition:background .1s;align-items:flex-start}
.log-card:hover{background:var(--bg3)}
.log-card.expandable{cursor:pointer}
.log-copy{flex-shrink:0;width:28px;height:28px;display:flex;align-items:center;justify-content:center;background:none;border:1px solid transparent;border-radius:var(--radius-sm);color:var(--text3);cursor:pointer;opacity:0;transition:all .15s;font-size:14px;padding:0}
.log-card:hover .log-copy{opacity:1}
.log-copy:hover{background:var(--bg4);border-color:var(--border);color:var(--text1)}
.log-copy.copied{color:var(--green);opacity:1}
.log-level{flex-shrink:0;width:64px;text-align:center;padding:2px 0;border-radius:3px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.5px}
.log-level.verbose{background:rgba(106,106,106,.15);color:var(--text3)}
.log-level.debug{background:rgba(156,220,254,.12);color:var(--cyan)}
.log-level.info{background:rgba(78,201,176,.12);color:var(--green)}
.log-level.warning{background:rgba(220,220,170,.15);color:var(--yellow)}
.log-level.error{background:rgba(244,71,71,.12);color:var(--red)}
.log-level.critical{background:rgba(244,71,71,.3);color:#ff8a8a;font-weight:800}
.log-time{flex-shrink:0;font-family:var(--font-mono);font-size:11px;color:var(--text3);padding-top:2px;width:90px}
.log-body{flex:1;min-width:0}
.log-title{font-size:11px;color:var(--text3);margin-bottom:1px}
.log-msg{font-size:12px;color:var(--text1);word-break:break-word;white-space:pre-wrap}
.log-expand{margin-top:6px;padding:8px;background:var(--bg0);border-radius:var(--radius-sm);font-family:var(--font-mono);font-size:11px;display:none}
.log-card.expanded .log-expand{display:block}
.log-error-text{color:var(--red);margin-bottom:4px}
.log-stack-text{color:var(--text3);font-size:10px;max-height:200px;overflow:auto;white-space:pre-wrap}

/* ── Error Cards ─────────────────────────────────────── */
.err-num{flex-shrink:0;width:32px;font-family:var(--font-mono);font-size:11px;color:var(--text3);text-align:right;padding-top:2px}
.error-card{display:flex;gap:10px;padding:10px 16px;border-bottom:1px solid var(--bg3);align-items:flex-start;cursor:pointer;transition:background .1s}
.error-card:hover{background:var(--bg3)}
.error-source{flex-shrink:0;padding:2px 8px;border-radius:3px;font-size:10px;font-weight:700;text-transform:uppercase}
.error-source.net-src{background:rgba(86,156,214,.15);color:var(--blue)}
.error-source.log-src{background:rgba(244,71,71,.15);color:var(--red)}
.error-time{flex-shrink:0;font-family:var(--font-mono);font-size:11px;color:var(--text3);width:90px;padding-top:2px}
.error-body{flex:1;min-width:0}
.error-headline{font-size:12px;color:var(--text1);font-weight:500}
.error-detail{font-size:11px;color:var(--text2);margin-top:2px}
.error-expand{margin-top:6px;padding:8px;background:var(--bg0);border-radius:var(--radius-sm);font-family:var(--font-mono);font-size:11px;display:none;white-space:pre-wrap;color:var(--text2);max-height:300px;overflow:auto}
.error-card.expanded .error-expand{display:block}

/* ── Instance Cards ──────────────────────────────────── */
.chip-inst-bloc{background:rgba(86,156,214,.15);color:var(--blue)}
.chip-inst-provider{background:rgba(197,134,192,.15);color:var(--purple)}
.chip-inst-repo{background:rgba(78,201,176,.15);color:var(--green)}
.chip-inst-svc{background:rgba(220,220,170,.15);color:var(--yellow)}
.chip-inst-net{background:rgba(206,145,120,.15);color:var(--orange)}
.chip-inst-other{background:rgba(106,106,106,.15);color:var(--text2)}
.view-toggle{display:flex;gap:0;border:1px solid var(--border);border-radius:var(--radius-sm);overflow:hidden;margin-left:auto}
.view-btn{padding:4px 14px;background:var(--bg3);border:none;color:var(--text2);cursor:pointer;font-size:11px;font-weight:600;font-family:var(--font-sans);transition:all .15s}
.view-btn:not(:last-child){border-right:1px solid var(--border)}
.view-btn:hover{color:var(--text1)}.view-btn.active{background:var(--accent-dim);color:var(--accent)}
.inst-view{display:none;flex-direction:column;flex:1;overflow:hidden}
.inst-view.active{display:flex}
.inst-summary{display:flex;gap:10px;padding:8px 16px;background:var(--bg2);border-bottom:1px solid var(--border);flex-wrap:wrap}
.inst-summary:empty{display:none}
.inst-stat{display:flex;align-items:center;gap:6px;padding:4px 10px;border-radius:var(--radius);background:var(--bg3);font-size:11px}
.inst-stat-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}
.inst-stat-dot.bloc{background:var(--blue)}.inst-stat-dot.provider{background:var(--purple)}.inst-stat-dot.repository{background:var(--green)}
.inst-stat-dot.service{background:var(--yellow)}.inst-stat-dot.network{background:var(--orange)}
.inst-stat-dot.other{background:var(--text3)}
.inst-stat-label{color:var(--text2)}.inst-stat-val{color:var(--text1);font-weight:600;font-variant-numeric:tabular-nums}
.inst-stat.warn{border:1px solid rgba(244,71,71,.3);background:rgba(244,71,71,.08)}
.inst-stat.warn .inst-stat-val{color:var(--red)}
.inst-card{display:flex;gap:10px;padding:10px 16px;border-bottom:1px solid var(--bg3);transition:background .1s;align-items:flex-start;cursor:pointer}
.inst-card:hover{background:var(--bg3)}
.inst-card.has-dup{border-left:3px solid var(--red)}
.inst-num{flex-shrink:0;width:32px;font-family:var(--font-mono);font-size:11px;color:var(--text3);text-align:right;padding-top:2px}
.inst-status{flex-shrink:0;width:60px;text-align:center;padding:2px 0;border-radius:3px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.3px}
.inst-status.active-st{background:rgba(78,201,176,.12);color:var(--green)}
.inst-status.closed-st{background:rgba(106,106,106,.15);color:var(--text3)}
.inst-cat{flex-shrink:0;width:80px;text-align:center;padding:2px 0;border-radius:3px;font-size:10px;font-weight:600;text-transform:uppercase}
.inst-cat.bloc{background:rgba(86,156,214,.15);color:var(--blue)}
.inst-cat.provider{background:rgba(197,134,192,.15);color:var(--purple)}
.inst-cat.repository{background:rgba(78,201,176,.15);color:var(--green)}
.inst-cat.service{background:rgba(220,220,170,.15);color:var(--yellow)}
.inst-cat.network{background:rgba(206,145,120,.15);color:var(--orange)}
.inst-cat.other{background:rgba(106,106,106,.15);color:var(--text2)}
.inst-time{flex-shrink:0;font-family:var(--font-mono);font-size:11px;color:var(--text3);width:90px;padding-top:2px;white-space:nowrap;overflow:visible}
.inst-body{flex:1;min-width:0}
.inst-type{font-size:12px;color:var(--text1);font-weight:600;font-family:var(--font-mono)}
.inst-meta{display:flex;gap:12px;margin-top:3px;font-size:11px;color:var(--text2);flex-wrap:wrap}
.inst-meta-item{display:flex;align-items:center;gap:4px}
.inst-dup-badge{display:inline-flex;align-items:center;gap:3px;padding:1px 6px;border-radius:3px;font-size:10px;font-weight:700;background:rgba(244,71,71,.15);color:var(--red)}
.inst-size{font-size:10px;color:var(--text3);font-family:var(--font-mono)}
.inst-expand{margin-top:8px;padding:10px;background:var(--bg0);border:1px solid var(--border);border-radius:var(--radius-sm);font-family:var(--font-mono);font-size:11px;display:none;white-space:pre-wrap;word-break:break-word;color:var(--text2);max-height:400px;overflow:auto}
.inst-card.expanded .inst-expand{display:block}
.inst-expand-section{margin-bottom:8px}
.inst-expand-title{color:var(--accent);font-weight:600;margin-bottom:4px;font-size:11px}
.inst-stack-frame{color:var(--text2);font-size:10px;line-height:1.6}
.inst-stack-frame .file-ref{color:var(--cyan)}
/* Timeline cards */
.tl-card{display:flex;gap:10px;padding:6px 16px;border-bottom:1px solid var(--bg3);font-size:11px;align-items:flex-start}
.tl-card:hover{background:var(--bg3)}
.tl-num{flex-shrink:0;width:32px;font-family:var(--font-mono);color:var(--text3);text-align:right}
.tl-action{flex-shrink:0;width:68px;text-align:center;padding:1px 0;border-radius:3px;font-size:9px;font-weight:700;text-transform:uppercase}
.tl-action.stateChange{background:rgba(156,220,254,.1);color:var(--cyan)}
.tl-action.created{background:rgba(78,201,176,.1);color:var(--green)}
.tl-action.closed{background:rgba(244,71,71,.1);color:var(--red)}
.tl-type{color:var(--text1);font-family:var(--font-mono);flex-shrink:0;width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.tl-time{flex-shrink:0;font-family:var(--font-mono);color:var(--text3);width:90px;white-space:nowrap;overflow:visible}
.tl-detail{flex:1;color:var(--text2);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}

/* ── Empty State ─────────────────────────────────────── */
.empty-state{display:flex;flex-direction:column;align-items:center;justify-content:center;flex:1;color:var(--text3);gap:12px;padding:40px}
.empty-icon{font-size:48px;opacity:.3}
.empty-title{font-size:16px;font-weight:500;color:var(--text2)}
.empty-desc{font-size:12px;text-align:center;max-width:320px;line-height:1.6}

/* ── Routes Tab ──────────────────────────────────────── */
.route-panel-layout{display:flex;flex:1;overflow:hidden}
.route-events{flex:0 0 380px;display:flex;flex-direction:column;overflow:hidden;border-right:1px solid var(--border)}
.route-event-list{flex:1;overflow-y:auto;padding:4px 0}

/* 3D Viewport */
.route-3d-viewport{flex:1;display:flex;flex-direction:column;overflow:hidden;background:radial-gradient(ellipse at 50% 80%,#1a1f2e 0%,var(--bg0) 70%);position:relative}
.route-3d-header{padding:12px 20px;display:flex;align-items:center;justify-content:space-between;flex-shrink:0;z-index:2}
.route-3d-header-left{display:flex;align-items:center;gap:12px}
.route-3d-title{font-size:13px;font-weight:600;color:var(--text2)}
.route-depth-badge{display:inline-flex;align-items:center;gap:5px;padding:3px 10px;border-radius:12px;font-size:11px;font-weight:700;font-family:var(--font-mono);background:rgba(59,158,255,.12);color:var(--accent);border:1px solid rgba(59,158,255,.2)}
.route-depth-badge svg{width:12px;height:12px}
/* 3D Scene Container */
.route-3d-scene{flex:1;display:flex;align-items:center;justify-content:center;perspective:2200px;perspective-origin:50% 40%;overflow:hidden;padding:20px;position:relative;min-height:0}

/* Stack Frame — visible wireframe container */
.route-stack-3d{transform-style:preserve-3d;position:relative;transition:transform .6s cubic-bezier(.23,1,.32,1);transform:rotateX(55deg) rotateZ(-42deg);padding:24px 28px 28px;z-index:2}
.route-stack-3d::before{content:'';position:absolute;inset:0;border:1.5px solid rgba(255,255,255,.06);border-radius:14px;background:linear-gradient(180deg,rgba(255,255,255,.02),rgba(255,255,255,.005));pointer-events:none}
.route-stack-3d::after{content:'';position:absolute;inset:6px;border:1px dashed rgba(255,255,255,.04);border-radius:10px;pointer-events:none}
.route-stack-3d:hover{transform:rotateX(50deg) rotateZ(-40deg)}

/* Card */
.r3d-card{width:260px;position:relative;cursor:pointer;transition:all .4s cubic-bezier(.23,1,.32,1);transform-style:preserve-3d;margin-bottom:0}
.r3d-card-inner{width:100%;border-radius:14px;padding:14px 16px;display:flex;flex-direction:column;gap:8px;background:linear-gradient(165deg,rgba(45,50,68,.92),rgba(30,33,48,.95));backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,.06);box-shadow:0 2px 8px rgba(0,0,0,.3),0 1px 0 rgba(255,255,255,.03) inset;overflow:hidden;position:relative;transition:all .35s cubic-bezier(.23,1,.32,1)}

/* Hover */
.r3d-card:hover{z-index:50!important;transform:translateY(-4px) translateZ(30px) scale(1.02)!important}
.r3d-card:hover .r3d-card-inner{border-color:rgba(255,255,255,.18);box-shadow:0 12px 40px rgba(0,0,0,.5),0 1px 0 rgba(255,255,255,.08) inset}
.r3d-card:hover .r3d-glow{opacity:.15}

/* Selected */
.r3d-card.r3d-selected{z-index:40!important;transform:translateY(-6px) translateZ(40px) scale(1.03)!important}
.r3d-card.r3d-selected .r3d-card-inner{border-color:rgba(59,158,255,.5);box-shadow:0 8px 40px rgba(59,158,255,.15),0 0 0 1px rgba(59,158,255,.2),0 1px 0 rgba(255,255,255,.08) inset}
.r3d-card.r3d-selected .r3d-name{color:var(--accent)}
.r3d-card.r3d-selected .r3d-select-ring{opacity:1}

/* Active (top of stack) */
.r3d-card.r3d-active .r3d-card-inner{background:linear-gradient(165deg,rgba(59,100,255,.1),rgba(30,50,150,.08));border-color:rgba(59,158,255,.3)}
.r3d-card.r3d-active .r3d-name{color:var(--accent)}
.r3d-card.r3d-active .r3d-status{background:rgba(59,158,255,.15);color:var(--accent);border-color:rgba(59,158,255,.25)}
.r3d-card.r3d-active .r3d-pulse{display:block}

/* Duplicate */
.r3d-card.r3d-dup .r3d-card-inner{border-color:rgba(244,71,71,.3)}
.r3d-card.r3d-dup .r3d-dup-indicator{display:flex}

/* Card effects */
.r3d-glow{position:absolute;top:-50%;left:-20%;width:140%;height:140%;background:radial-gradient(ellipse at 30% 0%,rgba(59,158,255,.2),transparent 60%);opacity:0;transition:opacity .4s;pointer-events:none;z-index:0}
.r3d-select-ring{position:absolute;inset:-2px;border-radius:16px;border:2px solid var(--accent);opacity:0;transition:opacity .3s;pointer-events:none;z-index:3}
.r3d-pulse{display:none;position:absolute;top:10px;right:10px;width:7px;height:7px;border-radius:50%;background:var(--accent);z-index:4}
.r3d-pulse::after{content:'';position:absolute;inset:-3px;border-radius:50%;border:1.5px solid var(--accent);animation:r3dPulseRing 2s ease-out infinite;opacity:0}
.r3d-edge-line{position:absolute;left:0;right:0;bottom:-1px;height:1px;background:linear-gradient(90deg,transparent,rgba(255,255,255,.05) 20%,rgba(255,255,255,.05) 80%,transparent);pointer-events:none}

/* Card content */
.r3d-top-row{display:flex;align-items:center;justify-content:space-between;gap:8px;position:relative;z-index:2}
.r3d-name{font-size:12px;font-weight:700;color:var(--text1);font-family:var(--font-mono);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;flex:1;line-height:1.3;transition:color .3s}
.r3d-index{flex-shrink:0;font-size:8px;font-weight:800;color:var(--text3);font-family:var(--font-mono);background:rgba(255,255,255,.06);padding:2px 7px;border-radius:6px;letter-spacing:.4px}
.r3d-bottom-row{display:flex;align-items:center;gap:6px;position:relative;z-index:2}
.r3d-status{font-size:8px;font-weight:800;text-transform:uppercase;letter-spacing:.6px;padding:2px 8px;border-radius:5px;background:rgba(255,255,255,.05);color:var(--text3);border:1px solid rgba(255,255,255,.04);transition:all .3s}
.r3d-time{font-size:9px;color:var(--text3);font-family:var(--font-mono);opacity:.7}
.r3d-action-badge{font-size:7px;font-weight:800;text-transform:uppercase;letter-spacing:.8px;padding:2px 7px;border-radius:4px;margin-left:auto}
.r3d-action-badge.push{background:rgba(78,201,176,.1);color:var(--green)}
.r3d-action-badge.pop{background:rgba(244,71,71,.1);color:var(--red)}
.r3d-action-badge.replace{background:rgba(229,192,68,.1);color:var(--yellow)}
.r3d-action-badge.remove{background:rgba(190,100,240,.1);color:#be64f0}
.r3d-dup-indicator{display:none;align-items:center;gap:3px;font-size:8px;font-weight:800;color:var(--red);padding:2px 6px;border-radius:4px;background:rgba(244,71,71,.08)}
.r3d-dup-indicator svg{width:9px;height:9px}

/* Info bar */
.r3d-info-bar{display:none;position:absolute;bottom:12px;left:12px;right:12px;z-index:10;padding:10px 14px;border-radius:10px;background:rgba(30,33,48,.95);backdrop-filter:blur(16px);border:1px solid rgba(59,158,255,.2);box-shadow:0 8px 32px rgba(0,0,0,.4);animation:r3dSlideUp .3s ease-out}
.r3d-info-bar.visible{display:flex;align-items:center;gap:12px}
.r3d-info-name{font-size:12px;font-weight:700;color:var(--accent);font-family:var(--font-mono);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.r3d-info-meta{font-size:10px;color:var(--text3);font-family:var(--font-mono)}
.r3d-info-close{background:none;border:1px solid rgba(255,255,255,.1);color:var(--text3);cursor:pointer;width:22px;height:22px;border-radius:6px;display:flex;align-items:center;justify-content:center;font-size:12px;transition:all .15s;flex-shrink:0}
.r3d-info-close:hover{background:rgba(255,255,255,.06);color:var(--text1)}

/* Focus overlay */
.route-focus-overlay{position:absolute;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.6);z-index:5;opacity:0;pointer-events:none;transition:opacity .3s}
.route-focus-overlay.visible{opacity:1;pointer-events:auto}

/* Route detail drawer */
.route-detail-drawer{position:absolute;top:0;right:0;bottom:0;width:360px;background:var(--bg1);border-left:1px solid var(--border);z-index:6;transform:translateX(100%);transition:transform .3s cubic-bezier(.25,.46,.45,.94);display:flex;flex-direction:column;box-shadow:-8px 0 30px rgba(0,0,0,.3)}
.route-detail-drawer.open{transform:translateX(0)}
.rd-header{display:flex;align-items:center;justify-content:space-between;padding:14px 16px;border-bottom:1px solid var(--border);flex-shrink:0}
.rd-title{font-weight:600;font-size:14px;color:var(--text1);font-family:var(--font-mono);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1;margin-right:8px}
.rd-close{background:none;border:1px solid var(--border);color:var(--text2);cursor:pointer;width:28px;height:28px;border-radius:var(--radius-sm);display:flex;align-items:center;justify-content:center;font-size:16px;transition:all .15s;flex-shrink:0}
.rd-close:hover{background:var(--bg3);color:var(--text1);border-color:var(--border-light)}
.rd-body{flex:1;overflow-y:auto;padding:16px}
.rd-section{margin-bottom:16px}
.rd-section-title{font-size:10px;text-transform:uppercase;letter-spacing:.8px;color:var(--text3);font-weight:600;margin-bottom:8px}
.rd-field{display:flex;justify-content:space-between;align-items:center;padding:6px 0;border-bottom:1px solid var(--bg3)}
.rd-field-label{font-size:11px;color:var(--text3)}
.rd-field-value{font-size:12px;color:var(--text1);font-family:var(--font-mono);text-align:right;max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.rd-stack-item{display:flex;align-items:center;gap:8px;padding:6px 10px;border-radius:var(--radius-sm);margin-bottom:4px;font-size:12px;font-family:var(--font-mono);background:var(--bg3);transition:background .15s}
.rd-stack-item:hover{background:var(--bg4)}
.rd-stack-item.rd-current{background:rgba(59,158,255,.1);border:1px solid rgba(59,158,255,.2)}
.rd-stack-idx{width:20px;font-size:10px;color:var(--text3);text-align:center;font-weight:600;flex-shrink:0}
.rd-stack-name{color:var(--text1);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.rd-stack-dot{width:6px;height:6px;border-radius:50%;background:var(--text3);flex-shrink:0}
.rd-stack-item.rd-current .rd-stack-dot{background:var(--accent);box-shadow:0 0 6px var(--accent)}
.rd-stack-item.rd-current .rd-stack-name{color:var(--accent)}
.rd-json-block{background:var(--bg0);border:1px solid var(--border);border-radius:var(--radius-sm);padding:10px;font-family:var(--font-mono);font-size:10px;line-height:1.6;white-space:pre-wrap;word-break:break-word;max-height:200px;overflow:auto;color:var(--text2)}

/* Event list cards */
.route-ev-card{display:flex;gap:10px;padding:8px 16px;border-bottom:1px solid var(--bg3);transition:background .1s;align-items:center;font-size:12px;cursor:pointer}
.route-ev-card:hover{background:var(--bg3)}
.route-ev-card.route-ev-active{background:rgba(59,158,255,.06);border-left:2px solid var(--accent)}
.route-ev-num{flex-shrink:0;width:28px;font-family:var(--font-mono);font-size:10px;color:var(--text3);text-align:right}
.route-ev-action{flex-shrink:0;width:60px;text-align:center;padding:2px 0;border-radius:3px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.3px}
.route-ev-action.push{background:rgba(78,201,176,.12);color:var(--green)}
.route-ev-action.pop{background:rgba(244,71,71,.12);color:var(--red)}
.route-ev-action.replace{background:rgba(206,145,120,.12);color:var(--orange)}
.route-ev-action.remove{background:rgba(220,220,170,.12);color:var(--yellow)}
.route-ev-time{flex-shrink:0;font-family:var(--font-mono);font-size:11px;color:var(--text3);width:85px;white-space:nowrap;overflow:visible}
.route-ev-name{flex:1;font-family:var(--font-mono);color:var(--text1);font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0}
.route-ev-depth{flex-shrink:0;font-family:var(--font-mono);font-size:10px;color:var(--text3);padding:1px 6px;background:var(--bg4);border-radius:3px}
.chip-push{background:rgba(78,201,176,.15);color:var(--green)}
.chip-pop{background:rgba(244,71,71,.15);color:var(--red)}
.chip-replace{background:rgba(206,145,120,.15);color:var(--orange)}
.chip-remove{background:rgba(220,220,170,.15);color:var(--yellow)}

@keyframes r3dPush{0%{opacity:0;transform:translateZ(-40px) scale(.9)}60%{opacity:1}100%{opacity:1;transform:translateZ(0) scale(1)}}
@keyframes r3dPulseRing{0%{transform:scale(1);opacity:.5}100%{transform:scale(2.5);opacity:0}}
@keyframes r3dSlideUp{0%{opacity:0;transform:translateY(10px)}100%{opacity:1;transform:translateY(0)}}
@keyframes r3dPop{0%{opacity:1;transform:translateZ(20px) scale(1.02)}100%{opacity:0;transform:translateZ(60px) scale(1.05) rotateX(-3deg)}}

/* ── Animations ──────────────────────────────────────── */
@keyframes fadeIn{from{opacity:0;transform:translateY(-6px)}to{opacity:1;transform:translateY(0)}}
.fade-in{animation:fadeIn .25s ease-out}

/* ── Socket Tab ────────────────────────────────────── */
.sock-list{display:flex;flex-direction:column;gap:1px;overflow-y:auto;flex:1;padding:6px}
.sock-card{display:flex;align-items:flex-start;gap:8px;padding:8px 10px;background:var(--bg2);border-radius:var(--radius-sm);cursor:pointer;border-left:3px solid transparent;transition:background .15s}
.sock-card:hover{background:var(--bg3)}
.sock-card.expanded{background:var(--bg3)}
.sock-card.sock-send{border-left-color:var(--method-post)}
.sock-card.sock-receive{border-left-color:var(--green)}
.sock-card.sock-error{border-left-color:var(--red)}
.sock-num{flex-shrink:0;width:28px;font-family:var(--font-mono);font-size:10px;color:var(--text3);text-align:right;padding-top:2px}
.sock-dir{flex-shrink:0;width:50px;text-align:center;padding:2px 0;border-radius:3px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.3px}
.sock-dir.send{background:rgba(86,156,214,.12);color:var(--method-post)}
.sock-dir.receive{background:rgba(78,201,176,.12);color:var(--green)}
.sock-meta{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}
.sock-headline{display:flex;align-items:center;gap:8px}
.sock-type{font-family:var(--font-mono);font-weight:600;color:var(--text1);font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sock-channel{font-family:var(--font-mono);font-size:10px;color:var(--text3);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sock-size{flex-shrink:0;font-family:var(--font-mono);font-size:10px;color:var(--text3);padding:1px 6px;background:var(--bg4);border-radius:3px}
.sock-time{flex-shrink:0;font-family:var(--font-mono);font-size:11px;color:var(--text3);width:85px;white-space:nowrap;padding-top:2px}
.sock-expand{display:none;margin-top:6px;padding-top:6px;border-top:1px solid var(--border)}
.sock-card.expanded .sock-expand{display:block}
.sock-data-label{font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:var(--text3);margin-bottom:4px}
.sock-data-body{font-family:var(--font-mono);font-size:11px;white-space:pre-wrap;word-break:break-all;color:var(--cyan);background:var(--bg1);padding:8px;border-radius:var(--radius-sm);max-height:300px;overflow-y:auto}
.sock-error-msg{color:var(--red);font-size:11px;font-family:var(--font-mono);margin-top:4px}
.sock-preview{font-family:var(--font-mono);font-size:11px;color:var(--text3);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%;margin-top:2px}
.sock-copy{flex-shrink:0;width:28px;height:28px;display:flex;align-items:center;justify-content:center;border:none;background:var(--bg4);color:var(--text3);border-radius:var(--radius-sm);cursor:pointer;transition:all .15s;font-size:13px;padding:0}
.sock-copy:hover{background:var(--accent-dim);color:var(--accent)}
.sock-copy.copied{background:rgba(78,201,176,.15);color:var(--green)}
.chip-send{background:rgba(86,156,214,.15);color:var(--method-post)}
.chip-receive{background:rgba(78,201,176,.15);color:var(--green)}
.sock-status-bar{display:flex;gap:8px;padding:4px 10px;flex-wrap:wrap}
.sock-status-bar:empty{display:none}
.sock-status-chip{display:inline-flex;align-items:center;gap:6px;padding:4px 10px;border-radius:20px;font-size:11px;font-family:var(--font-mono);font-weight:500;background:var(--bg3);border:1px solid var(--border);transition:all .3s ease}
.sock-status-chip .sock-status-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0;transition:background .3s ease}
.sock-status-chip.st-connected{border-color:rgba(78,201,176,.3);background:rgba(78,201,176,.08)}
.sock-status-chip.st-connected .sock-status-dot{background:var(--green);box-shadow:0 0 6px var(--green)}
.sock-status-chip.st-connecting,.sock-status-chip.st-reconnecting{border-color:rgba(220,220,170,.3);background:rgba(220,220,170,.08)}
.sock-status-chip.st-connecting .sock-status-dot,.sock-status-chip.st-reconnecting .sock-status-dot{background:var(--yellow);box-shadow:0 0 6px var(--yellow);animation:sockPulse 1.2s ease-in-out infinite}
.sock-status-chip.st-disconnected,.sock-status-chip.st-failed,.sock-status-chip.st-closed{border-color:rgba(244,71,71,.3);background:rgba(244,71,71,.08)}
.sock-status-chip.st-disconnected .sock-status-dot,.sock-status-chip.st-failed .sock-status-dot,.sock-status-chip.st-closed .sock-status-dot{background:var(--red);box-shadow:0 0 6px var(--red)}
@keyframes sockPulse{0%,100%{opacity:1}50%{opacity:.3}}
</style>
</head>
<body>
<div id="app">
  <!-- Top Bar -->
  <header class="topbar">
    <div class="topbar-logo">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10 5.172C10 3.782 8.423 2.679 6.5 3c-2.823.47-4.113 6.006-4 7 .137 1.217 1.5 2 2.5 2s2-.5 3-1.5c1-1 1.5-2 1.5-3.328z"/><path d="M14.267 5.172c0-1.39 1.577-2.493 3.5-2.172 2.823.47 4.113 6.006 4 7-.137 1.217-1.5 2-2.5 2s-2-.5-3-1.5-1.5-2-1.5-3.328z"/><path d="M8 14v.5M16 14v.5M11.25 16.25h1.5L12 17l-.75-.75z"/><path d="M4.42 11.247A13.152 13.152 0 0 0 4 14.556C4 18.728 7.582 21 12 21s8-2.272 8-6.444a13.158 13.158 0 0 0-.42-3.31"/></svg>
      Watchdog
    </div>
    <div class="topbar-spacer"></div>
    <div class="topbar-stats">
      <span>Network: <span class="stat-count" id="stat-net">0</span></span>
      <span>Logs: <span class="stat-count" id="stat-log">0</span></span>
      <span>Errors: <span class="stat-count" id="stat-err">0</span></span>
      <span>Instances: <span class="stat-count" id="stat-inst">0</span></span>
      <span>Routes: <span class="stat-count" id="stat-route">0</span></span>
    </div>
    <div class="conn-status">
      <span class="conn-dot off" id="conn-dot"></span>
      <span id="conn-text">Disconnected</span>
    </div>
    <button class="btn btn-danger" id="btn-clear" title="Clear all events">Clear</button>
  </header>

  <!-- Tab Bar -->
  <nav class="tab-bar">
    <button class="tab-btn active" data-tab="network">Network <span class="tab-badge" id="badge-net">0</span></button>
    <button class="tab-btn" data-tab="logs">Logs <span class="tab-badge" id="badge-log">0</span></button>
    <button class="tab-btn" data-tab="errors">Errors <span class="tab-badge" id="badge-err">0</span></button>
    <button class="tab-btn" data-tab="instances">Instances <span class="tab-badge" id="badge-inst">0</span></button>
    <button class="tab-btn" data-tab="routes">Routes <span class="tab-badge" id="badge-route">0</span></button>
    <button class="tab-btn" data-tab="socket">Socket <span class="tab-badge" id="badge-sock">0</span></button>
  </nav>

  <!-- Content -->
  <div class="content-area">
    <!-- Network Tab -->
    <div class="tab-panel active" id="panel-network">
      <div class="filter-bar">
        <div class="search-box"><input type="text" id="net-search" placeholder="Filter by URL or path..."></div>
        <div class="filter-sep"></div>
        <span class="filter-label">Method</span>
        <span class="chip chip-get on" data-filter="method" data-val="GET">GET</span>
        <span class="chip chip-post on" data-filter="method" data-val="POST">POST</span>
        <span class="chip chip-put on" data-filter="method" data-val="PUT">PUT</span>
        <span class="chip chip-delete on" data-filter="method" data-val="DELETE">DEL</span>
        <span class="chip chip-patch on" data-filter="method" data-val="PATCH">PATCH</span>
        <div class="filter-sep"></div>
        <span class="filter-label">Status</span>
        <span class="chip chip-2xx on" data-filter="status" data-val="2xx">2xx</span>
        <span class="chip chip-3xx on" data-filter="status" data-val="3xx">3xx</span>
        <span class="chip chip-4xx on" data-filter="status" data-val="4xx">4xx</span>
        <span class="chip chip-5xx on" data-filter="status" data-val="5xx">5xx</span>
      </div>
      <div class="table-wrap" id="net-table-wrap">
        <table class="net-table">
          <thead><tr><th>#</th><th></th><th>Method</th><th>Path</th><th>Status</th><th>Duration</th><th>Time</th></tr></thead>
          <tbody id="net-tbody"></tbody>
        </table>
      </div>
      <div class="empty-state" id="net-empty">
        <div class="empty-icon">&#128225;</div>
        <div class="empty-title">No network requests yet</div>
        <div class="empty-desc">Interact with your app to see HTTP traffic stream here in real-time.</div>
      </div>
    </div>

    <!-- Logs Tab -->
    <div class="tab-panel" id="panel-logs">
      <div class="filter-bar">
        <div class="search-box"><input type="text" id="log-search" placeholder="Filter by message..."></div>
        <div class="filter-sep"></div>
        <span class="filter-label">Level</span>
        <span class="chip chip-verbose on" data-filter="level" data-val="verbose">VERBOSE</span>
        <span class="chip chip-debug on" data-filter="level" data-val="debug">DEBUG</span>
        <span class="chip chip-info on" data-filter="level" data-val="info">INFO</span>
        <span class="chip chip-warning on" data-filter="level" data-val="warning">WARNING</span>
        <span class="chip chip-error on" data-filter="level" data-val="error">ERROR</span>
        <span class="chip chip-critical on" data-filter="level" data-val="critical">CRITICAL</span>
        <div class="filter-sep"></div>
        <button class="btn" id="btn-copy-logs" title="Copy all visible logs">Copy All</button>
      </div>
      <div class="log-list" id="log-list"></div>
      <div class="empty-state" id="log-empty">
        <div class="empty-icon">&#128203;</div>
        <div class="empty-title">No logs yet</div>
        <div class="empty-desc">App logs will appear here in real-time as your app runs.</div>
      </div>
    </div>

    <!-- Errors Tab -->
    <div class="tab-panel" id="panel-errors">
      <div class="filter-bar">
        <div class="search-box"><input type="text" id="err-search" placeholder="Filter errors..."></div>
      </div>
      <div class="log-list" id="err-list"></div>
      <div class="empty-state" id="err-empty">
        <div class="empty-icon">&#9989;</div>
        <div class="empty-title">No errors</div>
        <div class="empty-desc">Good news! No errors or failed requests detected yet.</div>
      </div>
    </div>

    <!-- Instances Tab -->
    <div class="tab-panel" id="panel-instances">
      <div class="filter-bar">
        <div class="search-box"><input type="text" id="inst-search" placeholder="Filter by type name..."></div>
        <div class="filter-sep"></div>
        <span class="filter-label">Category</span>
        <span class="chip chip-inst-bloc on" data-filter="cat" data-val="bloc">BLoC</span>
        <span class="chip chip-inst-provider on" data-filter="cat" data-val="provider">Riverpod</span>
        <span class="chip chip-inst-repo on" data-filter="cat" data-val="repository">Repository</span>
        <span class="chip chip-inst-svc on" data-filter="cat" data-val="service">Service</span>
        <span class="chip chip-inst-net on" data-filter="cat" data-val="network">Network</span>
        <span class="chip chip-inst-other on" data-filter="cat" data-val="other">Other</span>
        <div class="filter-sep"></div>
        <div class="view-toggle">
          <button class="view-btn active" data-view="instances">Instances</button>
          <button class="view-btn" data-view="timeline">State Changes</button>
        </div>
      </div>
      <div class="inst-summary" id="inst-summary"></div>
      <!-- Instances View (created objects, in-place updates) -->
      <div class="inst-view active" id="inst-view-instances">
        <div class="log-list" id="inst-list"></div>
        <div class="empty-state" id="inst-empty">
          <div class="empty-icon">&#128230;</div>
          <div class="empty-title">No instances tracked yet</div>
          <div class="empty-desc">BLoC, Repository, Service and Network instances will appear here as they are created.</div>
        </div>
      </div>
      <!-- State Changes View (timeline) -->
      <div class="inst-view" id="inst-view-timeline">
        <div class="log-list" id="timeline-list"></div>
        <div class="empty-state" id="timeline-empty">
          <div class="empty-icon">&#128260;</div>
          <div class="empty-title">No state changes yet</div>
          <div class="empty-desc">BLoC state transitions will appear here in real-time.</div>
        </div>
      </div>
    </div>

    <!-- Routes Tab -->
    <div class="tab-panel" id="panel-routes">
      <div class="filter-bar">
        <div class="search-box"><input type="text" id="route-search" placeholder="Filter by route name..."></div>
        <div class="filter-sep"></div>
        <span class="filter-label">Action</span>
        <span class="chip chip-push on" data-filter="routeAction" data-val="push">PUSH</span>
        <span class="chip chip-pop on" data-filter="routeAction" data-val="pop">POP</span>
        <span class="chip chip-replace on" data-filter="routeAction" data-val="replace">REPLACE</span>
        <span class="chip chip-remove on" data-filter="routeAction" data-val="remove">REMOVE</span>
      </div>
      <div class="route-panel-layout">
        <!-- Event Timeline -->
        <div class="route-events">
          <div class="route-event-list" id="route-list"></div>
          <div class="empty-state" id="route-empty">
            <div class="empty-icon">&#128268;</div>
            <div class="empty-title">No navigation events yet</div>
            <div class="empty-desc">Route pushes, pops, and replacements will appear here as you navigate through the app.</div>
          </div>
        </div>
        <!-- 3D Stack Viewport -->
        <div class="route-3d-viewport">
          <div class="route-3d-header">
            <div class="route-3d-header-left">
              <span class="route-3d-title">Navigation Stack</span>
              <span class="route-depth-badge"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2L2 7l10 5 10-5-10-5z"/><path d="M2 17l10 5 10-5"/><path d="M2 12l10 5 10-5"/></svg><span id="route-depth">0</span></span>
            </div>
          </div>
          <div class="route-3d-scene">
            <div class="route-stack-3d" id="route-stack"></div>
            <div class="r3d-info-bar" id="r3d-info"><span class="r3d-info-name" id="r3d-info-name"></span><span class="r3d-info-meta" id="r3d-info-meta"></span><button class="r3d-info-close" id="r3d-info-close">&times;</button></div>
          </div>
          <div class="route-focus-overlay" id="route-overlay"></div>
          <div class="route-detail-drawer" id="route-drawer">
            <div class="rd-header">
              <span class="rd-title" id="rd-title"></span>
              <button class="rd-close" id="rd-close">&times;</button>
            </div>
            <div class="rd-body" id="rd-body"></div>
          </div>
        </div>
      </div>
    </div>

    <div class="tab-panel" id="panel-socket">
      <div class="filter-bar">
        <div class="search-box"><input type="text" id="sock-search" placeholder="Filter by type, channel, or data..."></div>
        <div class="filter-sep"></div>
        <span class="filter-label">Direction</span>
        <span class="chip chip-send on" data-filter="sockDir" data-val="send">SEND</span>
        <span class="chip chip-receive on" data-filter="sockDir" data-val="receive">RECEIVE</span>
      </div>
      <div class="sock-status-bar" id="sock-status-bar"></div>
      <div class="sock-list" id="sock-list"></div>
      <div class="empty-state" id="sock-empty"><div class="empty-icon">&#128268;</div><div class="empty-title">No socket messages yet</div><div class="empty-desc">WebSocket send and receive messages will appear here in real-time.</div></div>
    </div>

    <!-- Detail Panel -->
    <aside class="detail-overlay" id="detail-panel">
      <div class="detail-header">
        <span class="detail-title" id="detail-title">Request Details</span>
        <button class="detail-close" id="detail-close">&times;</button>
      </div>
      <div class="detail-body" id="detail-body"></div>
    </aside>
  </div>
</div>

<script>
(function(){
"use strict";

// ── State ─────────────────────────────────────────────────
const S = {
  netMap: {},
  netOrder: [],
  netCounter: 0,
  logCounter: 0,
  errCounter: 0,
  instCounter: 0,
  logs: [],
  errors: [],
  instances: [],
  instCategoryCounts: {bloc:0,repository:0,service:0,network:0,other:0},
  instActiveMap: {},
  instTypeCreations: {},
  routeCounter: 0,
  routes: [],
  routeStack: [],
  sockCounter: 0,
  sockets: [],
  activeTab: "network",
  selectedId: null,
  filters: {
    method: {GET:true,POST:true,PUT:true,DELETE:true,PATCH:true},
    status: {"2xx":true,"3xx":true,"4xx":true,"5xx":true},
    level: {verbose:true,debug:true,info:true,warning:true,error:true,critical:true},
    cat: {bloc:true,repository:true,service:true,network:true,other:true},
    action: {created:true,stateChange:true,closed:true},
    routeAction: {push:true,pop:true,replace:true,remove:true},
    sockDir: {send:true,receive:true},
    netSearch: "",
    logSearch: "",
    errSearch: "",
    instSearch: "",
    routeSearch: "",
    sockSearch: ""
  }
};

// ── DOM refs ──────────────────────────────────────────────
const $ = (s) => document.querySelector(s);
const $$ = (s) => document.querySelectorAll(s);
const netTbody = $("#net-tbody");
const netEmpty = $("#net-empty");
const netTableWrap = $("#net-table-wrap");
const logList = $("#log-list");
const logEmpty = $("#log-empty");
const errList = $("#err-list");
const errEmpty = $("#err-empty");
const detailPanel = $("#detail-panel");
const detailBody = $("#detail-body");
const instList = $("#inst-list");
const instEmpty = $("#inst-empty");
const instSummary = $("#inst-summary");
const tlList = $("#timeline-list");
const tlEmpty = $("#timeline-empty");
const routeList = $("#route-list");
const routeEmpty = $("#route-empty");
const routeStackEl = $("#route-stack");
const routeDepthEl = $("#route-depth");
const sockList = $("#sock-list");
const sockEmpty = $("#sock-empty");
const connDot = $("#conn-dot");
const connText = $("#conn-text");

// ── Utilities ─────────────────────────────────────────────
function fmtTime(ms){
  const d=new Date(ms);
  return d.toTimeString().slice(0,8)+"."+String(d.getMilliseconds()).padStart(3,"0");
}
function fmtDuration(ms){
  if(ms==null)return "...";
  if(ms<1000)return ms+"ms";
  return (ms/1000).toFixed(2)+"s";
}
function escHtml(s){
  if(typeof s!=="string")s=String(s);
  return s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
}
function statusRange(code){
  if(!code)return null;
  if(code<200)return "1xx";if(code<300)return "2xx";if(code<400)return "3xx";if(code<500)return "4xx";return "5xx";
}
function durationClass(ms){
  if(ms==null)return "";if(ms>3000)return "very-slow";if(ms>1000)return "slow";return "";
}
function hostFromUrl(u){try{return new URL(u).host}catch(_){return ""}}
function pathFromUrl(u){try{return new URL(u).pathname}catch(_){return u}}

// ── JSON Syntax Highlighter ───────────────────────────────
function highlightJson(val,indent){
  if(indent===undefined)indent=0;
  if(val===null)return '<span class="j-null">null</span>';
  if(typeof val==="boolean")return '<span class="j-bool">'+val+"</span>";
  if(typeof val==="number")return '<span class="j-num">'+val+"</span>";
  if(typeof val==="string")return '<span class="j-str">"'+escHtml(val)+'"</span>';
  const pad="  ".repeat(indent);
  const pad1="  ".repeat(indent+1);
  if(Array.isArray(val)){
    if(val.length===0)return "[]";
    const items=val.map(function(v){return pad1+highlightJson(v,indent+1)});
    return "[\n"+items.join(",\n")+"\n"+pad+"]";
  }
  if(typeof val==="object"){
    const keys=Object.keys(val);
    if(keys.length===0)return "{}";
    const entries=keys.map(function(k){return pad1+'<span class="j-key">"'+escHtml(k)+'"</span>: '+highlightJson(val[k],indent+1)});
    return "{\n"+entries.join(",\n")+"\n"+pad+"}";
  }
  return escHtml(String(val));
}

function jsonBlock(val){
  if(val==null)return '<div class="json-pre" style="color:var(--text3)">null</div>';
  var obj=val;
  if(typeof val==="string"){try{obj=JSON.parse(val)}catch(_){return '<div class="json-pre">'+escHtml(val)+"</div>"}}
  return '<div class="json-pre">'+highlightJson(obj,0)+"</div>";
}

function kvTable(map){
  if(!map||Object.keys(map).length===0)return '<span style="color:var(--text3);font-size:12px">None</span>';
  var h='<table class="kv-table">';
  for(var k in map)h+="<tr><td>"+escHtml(k)+"</td><td>"+escHtml(map[k])+"</td></tr>";
  return h+"</table>";
}

function buildCurl(ev){
  var c="curl -X "+ev.method+" \\\n  "+JSON.stringify(ev.url);
  var hdrs=ev.requestHeaders||{};
  for(var k in hdrs)c+=" \\\n  -H "+JSON.stringify(k+": "+hdrs[k]);
  if(ev.requestBody!=null){
    var b=typeof ev.requestBody==="string"?ev.requestBody:JSON.stringify(ev.requestBody);
    c+=" \\\n  -d "+JSON.stringify(b);
  }
  return c;
}

function copyText(text,btn){
  navigator.clipboard.writeText(text).then(function(){
    btn.classList.add("copied");btn.textContent="Copied!";
    setTimeout(function(){btn.classList.remove("copied");btn.textContent="Copy"},1500);
  });
}

function fmtLogText(d){
  var s="#"+d._num+" ["+d.level.toUpperCase()+"] "+fmtTime(d.timestamp);
  if(d.title)s+=" ("+d.title+")";
  s+="\n"+d.message;
  if(d.error)s+="\nError: "+d.error;
  if(d.stackTrace)s+="\n"+d.stackTrace;
  return s;
}

// ── Counters ──────────────────────────────────────────────
function updateCounts(){
  var nc=S.netOrder.length, lc=S.logs.length, ec=S.errors.length, ic=S.instances.length, rc=S.routes.length, sc=S.sockets.length;
  $("#stat-net").textContent=nc;
  $("#stat-log").textContent=lc;
  $("#stat-err").textContent=ec;
  $("#stat-inst").textContent=ic;
  $("#stat-route").textContent=rc;
  $("#badge-net").textContent=nc;
  $("#badge-log").textContent=lc;
  $("#badge-err").textContent=ec;
  $("#badge-inst").textContent=ic;
  $("#badge-route").textContent=rc;
  $("#badge-sock").textContent=sc;
}

// ── Network Rendering ─────────────────────────────────────
function makeNetRow(ev){
  var tr=document.createElement("tr");
  tr.className="net-row fade-in";
  tr.dataset.id=ev.id;
  if(ev.status==="pending")tr.classList.add("pending");
  updateNetRowContent(tr,ev);
  tr.addEventListener("click",function(){openDetail(ev.id)});
  return tr;
}

function updateNetRowContent(tr,ev){
  var sc=ev.statusCode;
  var sr=statusRange(sc);
  var dotCls=ev.status==="failed"?"failed":ev.status==="pending"?"pending":sr?"s"+sr:"pending";
  var scText=ev.status==="failed"?"ERR":sc||"...";
  var scCls=ev.status==="failed"?"failed":sr?"s"+sr:"";
  var dur=fmtDuration(ev.durationMs);
  var durCls=durationClass(ev.durationMs);
  var p=ev.path||pathFromUrl(ev.url);
  var host=hostFromUrl(ev.url);

  tr.innerHTML=
    '<td><span class="row-num">'+(ev._num||"")+"</span></td>"+
    '<td><span class="status-dot-cell '+dotCls+'"></span></td>'+
    '<td><span class="method-badge '+ev.method+'">'+ev.method+"</span></td>"+
    '<td><span class="path-text">'+escHtml(p)+'</span><span class="path-host">'+escHtml(host)+"</span></td>"+
    '<td><span class="status-code '+scCls+'">'+scText+"</span></td>"+
    '<td><span class="duration '+durCls+'">'+dur+"</span></td>"+
    '<td><span class="timestamp">'+fmtTime(ev.timestamp)+"</span></td>";
  if(ev.status!=="pending")tr.classList.remove("pending");
}

function handleNetworkEvent(data){
  var existing=S.netMap[data.id];
  if(existing){
    Object.assign(existing,data);
    var row=netTbody.querySelector('[data-id="'+data.id+'"]');
    if(row)updateNetRowContent(row,existing);
  } else {
    data._num=++S.netCounter;
    S.netMap[data.id]=data;
    S.netOrder.unshift(data.id);
    var newRow=makeNetRow(data);
    if(netTbody.firstChild)netTbody.insertBefore(newRow,netTbody.firstChild);
    else netTbody.appendChild(newRow);
    if(S.netOrder.length>2000){
      var oldId=S.netOrder.pop();delete S.netMap[oldId];
      var oldRow=netTbody.querySelector('[data-id="'+oldId+'"]');
      if(oldRow)oldRow.remove();
    }
  }
  // Check if error
  if(data.status==="failed"||(data.statusCode&&data.statusCode>=400)){
    addError({type:"network",id:data.id,timestamp:data.timestamp,headline:data.method+" "+data.statusCode+" "+(data.path||pathFromUrl(data.url)),detail:data.errorMessage||"HTTP "+data.statusCode,expand:data.errorStackTrace||null,raw:data});
  }
  applyNetFilters();
  updateCounts();
  if(S.selectedId===data.id)renderDetail(data);
  toggleNetEmpty();
}

function applyNetFilters(){
  var rows=netTbody.querySelectorAll(".net-row");
  var search=S.filters.netSearch.toLowerCase();
  rows.forEach(function(r){
    var ev=S.netMap[r.dataset.id];if(!ev){r.style.display="none";return}
    var show=true;
    if(!S.filters.method[ev.method])show=false;
    if(show&&ev.statusCode){var sr=statusRange(ev.statusCode);if(sr&&!S.filters.status[sr])show=false}
    if(show&&search){var u=(ev.url+"|"+(ev.path||"")).toLowerCase();if(u.indexOf(search)===-1)show=false}
    r.style.display=show?"":"none";
  });
}
function toggleNetEmpty(){
  var has=S.netOrder.length>0;
  netEmpty.style.display=has?"none":"flex";
  netTableWrap.style.display=has?"":"none";
}

// ── Detail Panel ──────────────────────────────────────────
function openDetail(id){
  S.selectedId=id;
  var ev=S.netMap[id];if(!ev)return;
  $$(".net-row").forEach(function(r){r.classList.toggle("selected",r.dataset.id===id)});
  renderDetail(ev);
  detailPanel.classList.add("open");
}
function closeDetail(){
  S.selectedId=null;
  detailPanel.classList.remove("open");
  $$(".net-row.selected").forEach(function(r){r.classList.remove("selected")});
}

function renderDetail(ev){
  var sc=ev.statusCode;var sr=statusRange(sc);
  var scCls=ev.status==="failed"?"failed":sr?"s"+sr:"";
  var h="";

  // General
  h+=section("General",'<div class="url-full">'+escHtml(ev.url)+"</div>"+
    '<div class="detail-general">'+
    "<dt>Method</dt><dd><span class='method-badge "+ev.method+"'>"+ev.method+"</span></dd>"+
    "<dt>Status</dt><dd><span class='status-code "+scCls+"'>"+(ev.status==="failed"?"FAILED":sc||"Pending")+"</span></dd>"+
    "<dt>Duration</dt><dd>"+fmtDuration(ev.durationMs)+"</dd>"+
    "<dt>Time</dt><dd>"+fmtTime(ev.timestamp)+"</dd>"+
    "<dt>Status</dt><dd>"+ev.status+"</dd>"+
    "</div>",true);

  // Request Headers
  h+=section("Request Headers",kvTable(ev.requestHeaders));

  // Query Params
  var qp=ev.queryParams;
  if(qp&&Object.keys(qp).length>0) h+=section("Query Parameters",kvTable(qp));

  // Request Body
  if(ev.requestBody!=null) h+=section("Request Body",'<div class="section-toolbar"><button class="copy-btn" onclick="window._copyJson(this,\'req\')">Copy</button></div>'+jsonBlock(ev.requestBody));

  // Response Headers
  if(ev.responseHeaders) h+=section("Response Headers",kvTable(ev.responseHeaders));

  // Response Body
  if(ev.responseBody!=null) h+=section("Response Body",'<div class="section-toolbar"><button class="copy-btn" onclick="window._copyJson(this,\'res\')">Copy</button></div>'+jsonBlock(ev.responseBody),true);

  // Error
  if(ev.errorMessage) h+=section("Error",'<div class="error-box">'+escHtml(ev.errorMessage)+(ev.errorStackTrace?'<div class="stack-pre">'+escHtml(ev.errorStackTrace)+"</div>":"")+"</div>",true);

  // cURL
  h+=section("cURL",'<div class="curl-pre" id="curl-text">'+escHtml(buildCurl(ev))+'</div><button class="copy-btn" onclick="window._copyCurl(this)">Copy</button>');

  detailBody.innerHTML=h;

  var title=ev.method+" "+(ev.path||pathFromUrl(ev.url));
  $("#detail-title").innerHTML='<span class="method-badge '+ev.method+'">'+ev.method+"</span> "+(ev.path||pathFromUrl(ev.url));

  // Store for copy
  window._detailEv=ev;
}

function section(title,content,open){
  return '<div class="detail-section"><div class="section-head'+(open?" open":"")+'"><span class="section-chevron">&#9656;</span> '+title+"</div>"+
    '<div class="section-content"'+(open?' style="display:block"':"")+">"+content+"</div></div>";
}

window._copyJson=function(btn,which){
  var ev=window._detailEv;if(!ev)return;
  var d=which==="req"?ev.requestBody:ev.responseBody;
  var txt=typeof d==="string"?d:JSON.stringify(d,null,2);
  copyText(txt||"",btn);
};
window._copyCurl=function(btn){
  var ev=window._detailEv;if(!ev)return;
  copyText(buildCurl(ev),btn);
};

// ── Log Rendering ─────────────────────────────────────────
function handleLogEvent(data){
  data._num=++S.logCounter;
  S.logs.unshift(data);
  if(S.logs.length>5000)S.logs.pop();

  var card=makeLogCard(data);
  if(logList.firstChild)logList.insertBefore(card,logList.firstChild);
  else logList.appendChild(card);

  // Errors tab
  if(data.level==="error"||data.level==="critical"){
    addError({type:"log",id:data.id,timestamp:data.timestamp,headline:"["+data.level.toUpperCase()+"] "+(data.title||""),detail:data.message,expand:data.error?(data.error+(data.stackTrace?"\n"+data.stackTrace:"")):data.stackTrace||null,raw:data});
  }

  applyLogFilters();
  updateCounts();
  toggleLogEmpty();
}

function makeLogCard(data){
  var el=document.createElement("div");
  el.className="log-card fade-in";
  el.dataset.id=data.id;
  el.dataset.level=data.level;
  var hasExpand=!!(data.error||data.stackTrace);
  if(hasExpand)el.classList.add("expandable");

  var inner='<span class="log-num">'+data._num+"</span>"+
    '<span class="log-level '+data.level+'">'+data.level+"</span>"+
    '<span class="log-time">'+fmtTime(data.timestamp)+"</span>"+
    '<div class="log-body">';
  if(data.title)inner+='<div class="log-title">'+escHtml(data.title)+"</div>";
  inner+='<div class="log-msg">'+escHtml(data.message)+"</div>";
  if(hasExpand){
    inner+='<div class="log-expand">';
    if(data.error)inner+='<div class="log-error-text">'+escHtml(data.error)+"</div>";
    if(data.stackTrace)inner+='<div class="log-stack-text">'+escHtml(data.stackTrace)+"</div>";
    inner+="</div>";
  }
  inner+='</div><button class="log-copy" title="Copy this log">&#128203;</button>';
  el.innerHTML=inner;
  el.querySelector(".log-copy").addEventListener("click",function(e){
    e.stopPropagation();
    var btn=e.currentTarget;
    var txt=fmtLogText(data);
    copyText(txt,btn);
    btn.innerHTML="&#10003;";btn.classList.add("copied");
    setTimeout(function(){btn.innerHTML="&#128203;";btn.classList.remove("copied")},1500);
  });
  if(hasExpand)el.addEventListener("click",function(e){if(!e.target.closest(".log-copy"))el.classList.toggle("expanded")});
  return el;
}

function applyLogFilters(){
  var search=S.filters.logSearch.toLowerCase();
  logList.querySelectorAll(".log-card").forEach(function(c){
    var lvl=c.dataset.level;
    var show=S.filters.level[lvl]!==false;
    if(show&&search){var msg=c.textContent.toLowerCase();if(msg.indexOf(search)===-1)show=false}
    c.style.display=show?"":"none";
  });
}
function toggleLogEmpty(){
  var has=S.logs.length>0;logEmpty.style.display=has?"none":"flex";logList.style.display=has?"":"none";
}

// ── Errors Tab ────────────────────────────────────────────
function addError(err){
  err._num=++S.errCounter;
  S.errors.unshift(err);
  if(S.errors.length>3000)S.errors.pop();
  var card=makeErrorCard(err);
  if(errList.firstChild)errList.insertBefore(card,errList.firstChild);
  else errList.appendChild(card);
  applyErrFilters();
  toggleErrEmpty();
}

function makeErrorCard(err){
  var el=document.createElement("div");
  el.className="error-card fade-in";
  var srcCls=err.type==="network"?"net-src":"log-src";
  var srcLabel=err.type==="network"?"NETWORK":"LOG";
  var inner='<span class="err-num">'+err._num+"</span>"+
    '<span class="error-source '+srcCls+'">'+srcLabel+"</span>"+
    '<span class="error-time">'+fmtTime(err.timestamp)+"</span>"+
    '<div class="error-body"><div class="error-headline">'+escHtml(err.headline)+'</div><div class="error-detail">'+escHtml(err.detail)+"</div>";
  if(err.expand)inner+='<div class="error-expand">'+escHtml(err.expand)+"</div>";
  inner+="</div>";
  el.innerHTML=inner;
  if(err.expand)el.addEventListener("click",function(){el.classList.toggle("expanded")});
  return el;
}

function applyErrFilters(){
  var search=S.filters.errSearch.toLowerCase();
  errList.querySelectorAll(".error-card").forEach(function(c){
    if(!search){c.style.display="";return}
    var txt=c.textContent.toLowerCase();
    c.style.display=txt.indexOf(search)!==-1?"":"none";
  });
}
function toggleErrEmpty(){
  var has=S.errors.length>0;errEmpty.style.display=has?"none":"flex";errList.style.display=has?"":"none";
}

// ── Instances Tab ─────────────────────────────────────────
// instByType: { typeName: [{ instanceId, created, closed, cat, state, size, stack, details, creations:[] }] }
// This groups by type and tracks duplicates.

function handleInstanceEvent(data){
  data._num=++S.instCounter;
  S.instances.push(data);
  if(S.instances.length>10000)S.instances.shift();

  if(data.action==="created"){
    // Track in activeMap
    if(data.instanceId){
      S.instActiveMap[data.instanceId]={type:data.typeName,cat:data.category,time:data.timestamp,state:data.currentState,size:data.estimatedSizeBytes,stack:data.creationStack,details:data.details,regType:data.registrationType,num:data._num};
      S.instCategoryCounts[data.category]=(S.instCategoryCounts[data.category]||0)+1;
    }
    // Track type creation count for duplicate detection
    if(!S.instTypeCreations[data.typeName])S.instTypeCreations[data.typeName]=[];
    S.instTypeCreations[data.typeName].push({instanceId:data.instanceId,time:data.timestamp,stack:data.creationStack,num:data._num});
    // Rebuild instance card
    rebuildInstCard(data.typeName);
  } else if(data.action==="closed"){
    if(data.instanceId&&S.instActiveMap[data.instanceId]){
      var cat=S.instActiveMap[data.instanceId].cat;
      S.instCategoryCounts[cat]=Math.max(0,(S.instCategoryCounts[cat]||0)-1);
      S.instActiveMap[data.instanceId].closed=data.timestamp;
      S.instActiveMap[data.instanceId].lifetime=data.details;
    }
    rebuildInstCard(data.typeName);
  } else if(data.action==="stateChange"){
    // Update active instance state
    if(data.instanceId&&S.instActiveMap[data.instanceId]){
      S.instActiveMap[data.instanceId].state=data.currentState;
      S.instActiveMap[data.instanceId].size=data.estimatedSizeBytes;
    }
    // Rebuild the full card so expanded view also shows latest state
    rebuildInstCard(data.typeName);
  }

  // Add to timeline
  addTimelineEntry(data);
  updateInstSummary();
  updateCounts();
  toggleInstEmpty();
  toggleTlEmpty();
}

function rebuildInstCard(typeName){
  var creations=S.instTypeCreations[typeName]||[];
  if(creations.length===0)return;
  var firstCreation=creations[0];
  var cat="other";
  var activeInstances=[];
  var closedInstances=[];
  for(var i=0;i<creations.length;i++){
    var iid=creations[i].instanceId;
    var info=S.instActiveMap[iid];
    if(info){cat=info.cat;if(info.closed)closedInstances.push(info);else activeInstances.push(info)}
  }
  var totalCreated=creations.length;
  var isDup=totalCreated>1;
  var latestActive=activeInstances.length>0?activeInstances[activeInstances.length-1]:null;
  var latestInfo=latestActive||(closedInstances.length>0?closedInstances[closedInstances.length-1]:null);

  // Remove existing card
  var old=instList.querySelector('[data-type="'+CSS.escape(typeName)+'"]');
  if(old)old.remove();

  var el=document.createElement("div");
  el.className="inst-card fade-in";
  if(isDup)el.classList.add("has-dup");
  el.dataset.cat=cat;
  el.dataset.type=typeName;

  var statusCls=activeInstances.length>0?"active-st":"closed-st";
  var statusTxt=activeInstances.length>0?"ACTIVE":"CLOSED";
  var sizeStr=latestInfo&&latestInfo.size!=null?fmtSize(latestInfo.size):"";

  var inner='<span class="inst-num">'+firstCreation.num+"</span>"+
    '<span class="inst-status '+statusCls+'">'+statusTxt+"</span>"+
    '<span class="inst-cat '+cat+'">'+cat+"</span>"+
    '<span class="inst-time">'+fmtTime(firstCreation.time)+"</span>"+
    '<div class="inst-body"><span class="inst-type">'+escHtml(typeName)+"</span>";

  // Meta row
  inner+='<div class="inst-meta">';
  if(latestInfo&&latestInfo.regType)inner+='<span class="inst-meta-item" style="color:var(--blue);font-weight:600">'+escHtml(latestInfo.regType)+"</span>";
  if(latestInfo&&latestInfo.details)inner+='<span class="inst-meta-item">'+escHtml(latestInfo.details)+"</span>";
  if(sizeStr)inner+='<span class="inst-meta-item inst-size">'+sizeStr+"</span>";
  inner+='<span class="inst-meta-item">Active: '+activeInstances.length+"</span>";
  if(isDup)inner+='<span class="inst-dup-badge">&#9888; '+totalCreated+"x created</span>";
  if(closedInstances.length>0)inner+='<span class="inst-meta-item">Closed: '+closedInstances.length+"</span>";
  inner+="</div>";

  // Current state (for active instances)
  if(latestActive&&latestActive.state){
    inner+='<div style="margin-top:4px;font-size:11px;color:var(--text3)">Current state: <span class="inst-current-state" style="color:var(--text2)">'+escHtml(truncate(latestActive.state,120))+"</span></div>";
  }

  // Expandable section
  inner+='<div class="inst-expand">';

  // All creation instances
  for(var c=0;c<creations.length;c++){
    var cr=creations[c];
    var ai=S.instActiveMap[cr.instanceId];
    inner+='<div class="inst-expand-section"><div class="inst-expand-title">Instance #'+(c+1)+" — Created at "+fmtTime(cr.time);
    if(ai&&ai.closed)inner+=" — Closed at "+fmtTime(ai.closed);
    if(ai&&ai.lifetime)inner+=" ("+escHtml(ai.lifetime)+")";
    inner+="</div>";
    if(ai&&ai.state){
      inner+='<div class="inst-expand-title">Current State: <button class="copy-btn inst-copy-state" style="display:inline-flex;margin-left:8px;vertical-align:middle" data-state="'+escHtml(ai.state)+'">Copy</button></div>';
      inner+='<div class="json-pre" style="max-height:500px;overflow:auto;white-space:pre-wrap;word-break:break-word">'+formatState(ai.state)+"</div>";
    }
    if(cr.stack){
      inner+='<div class="inst-expand-title" style="margin-top:6px">Creation Stack Trace:</div>';
      inner+='<div class="inst-stack-frame">'+formatStack(cr.stack)+"</div>";
    }
    inner+="</div>";
  }
  inner+="</div></div>";
  el.innerHTML=inner;
  el.addEventListener("click",function(e){if(!e.target.closest(".inst-copy-state"))el.classList.toggle("expanded")});
  // Copy state buttons
  el.querySelectorAll(".inst-copy-state").forEach(function(btn){
    btn.addEventListener("click",function(e){
      e.stopPropagation();
      var state=btn.dataset.state;
      copyText(state||"",btn);
    });
  });

  // Insert sorted by category then alpha
  insertInstSorted(el,cat,typeName);
  applyInstFilters();
}

function insertInstSorted(el,cat,typeName){
  var cards=instList.querySelectorAll(".inst-card");
  var catOrder={bloc:0,repository:1,service:2,network:3,other:4};
  var ci=catOrder[cat]!=null?catOrder[cat]:4;
  for(var i=0;i<cards.length;i++){
    var oci=catOrder[cards[i].dataset.cat]!=null?catOrder[cards[i].dataset.cat]:4;
    if(ci<oci||(ci===oci&&typeName<(cards[i].dataset.type||""))){
      instList.insertBefore(el,cards[i]);return;
    }
  }
  instList.appendChild(el);
}

function truncate(s,len){if(!s)return"";return s.length>len?s.substring(0,len)+"...":s}

function formatStack(stack){
  if(!stack)return"";
  return escHtml(stack).replace(/(package:[^\s)]+)/g,'<span class="file-ref">$1</span>');
}

function formatState(stateStr){
  if(!stateStr)return"";
  // Try to parse as JSON first
  try{var obj=JSON.parse(stateStr);return highlightJson(obj,0)}catch(_){}
  // Format Dart toString output: ClassName(field1: val, field2: val, ...)
  // Pretty-print by adding newlines after commas inside parens
  var s=escHtml(stateStr);
  // Indent nested parentheses
  var result="";var depth=0;var inStr=false;
  for(var i=0;i<s.length;i++){
    var ch=s[i];
    if(ch==="("||ch==="[" ||ch==="{"){
      depth++;
      result+=ch+"\n"+"  ".repeat(depth);
    } else if(ch===")"||ch==="]"||ch==="}"){
      depth=Math.max(0,depth-1);
      result+="\n"+"  ".repeat(depth)+ch;
    } else if(ch===","&&depth>0){
      result+=",\n"+"  ".repeat(depth);
    } else {
      result+=ch;
    }
  }
  // Syntax highlight known patterns
  result=result.replace(/(\w+):/g,'<span class="j-key">$1</span>:');
  result=result.replace(/: (true|false)/g,': <span class="j-bool">$1</span>');
  result=result.replace(/: (null)/g,': <span class="j-null">$1</span>');
  result=result.replace(/: (\d+\.?\d*)/g,': <span class="j-num">$1</span>');
  return result;
}

function fmtSize(bytes){
  if(bytes==null)return"";
  if(bytes<1024)return bytes+"B";
  if(bytes<1048576)return (bytes/1024).toFixed(1)+"KB";
  return (bytes/1048576).toFixed(2)+"MB";
}

// Timeline view
var tlCounter=0;
function addTimelineEntry(data){
  tlCounter++;
  var el=document.createElement("div");
  el.className="tl-card fade-in";
  el.dataset.cat=data.category;
  var detail="";
  if(data.action==="stateChange")detail=truncate(data.currentState,80);
  else if(data.action==="created")detail=data.details||"";
  else if(data.action==="closed")detail=data.details||"";

  el.innerHTML='<span class="tl-num">'+tlCounter+"</span>"+
    '<span class="tl-action '+data.action+'">'+data.action+"</span>"+
    '<span class="tl-type" title="'+escHtml(data.typeName)+'">'+escHtml(data.typeName)+"</span>"+
    '<span class="tl-time">'+fmtTime(data.timestamp)+"</span>"+
    '<span class="tl-detail">'+escHtml(detail)+"</span>";

  if(tlList.firstChild)tlList.insertBefore(el,tlList.firstChild);
  else tlList.appendChild(el);
  // Cap timeline entries
  if(tlList.children.length>3000)tlList.removeChild(tlList.lastChild);
}

function updateInstSummary(){
  var cats=["bloc","provider","repository","service","network","other"];
  var labels=["BLoC","Riverpod","Repository","Service","Network","Other"];
  var h="";
  var totalActive=Object.keys(S.instActiveMap).filter(function(k){return!S.instActiveMap[k].closed}).length;
  h+='<div class="inst-stat"><span class="inst-stat-label">Total Active:</span><span class="inst-stat-val">'+totalActive+"</span></div>";

  // Duplicate warning
  var dupCount=0;
  for(var t in S.instTypeCreations){if(S.instTypeCreations[t].length>1)dupCount++}
  if(dupCount>0)h+='<div class="inst-stat warn"><span class="inst-stat-label">&#9888; Duplicates:</span><span class="inst-stat-val">'+dupCount+" types</span></div>";

  for(var i=0;i<cats.length;i++){
    var c=S.instCategoryCounts[cats[i]]||0;
    var total=0;for(var t in S.instTypeCreations){var cr=S.instTypeCreations[t];if(cr.length>0){var info=S.instActiveMap[cr[0].instanceId];if(info&&info.cat===cats[i])total++}}
    if(total>0||c>0){
      h+='<div class="inst-stat"><span class="inst-stat-dot '+cats[i]+'"></span><span class="inst-stat-label">'+labels[i]+':</span><span class="inst-stat-val">'+c+" active</span></div>";
    }
  }
  instSummary.innerHTML=h;
}

function applyInstFilters(){
  var search=S.filters.instSearch.toLowerCase();
  instList.querySelectorAll(".inst-card").forEach(function(c){
    var cat=c.dataset.cat;
    var show=S.filters.cat[cat]!==false;
    if(show&&search){var txt=c.textContent.toLowerCase();if(txt.indexOf(search)===-1)show=false}
    c.style.display=show?"":"none";
  });
  // Also filter timeline
  tlList.querySelectorAll(".tl-card").forEach(function(c){
    var cat=c.dataset.cat;
    var show=S.filters.cat[cat]!==false;
    if(show&&search){var txt=c.textContent.toLowerCase();if(txt.indexOf(search)===-1)show=false}
    c.style.display=show?"":"none";
  });
}
function toggleInstEmpty(){
  var hasInst=instList.querySelectorAll(".inst-card").length>0;
  $("#inst-empty").style.display=hasInst?"none":"flex";
  instList.style.display=hasInst?"":"none";
}
function toggleTlEmpty(){
  var hasTl=tlList.querySelectorAll(".tl-card").length>0;
  tlEmpty.style.display=hasTl?"none":"flex";
  tlList.style.display=hasTl?"":"none";
}

// ── Routes Tab ────────────────────────────────────────────
var routeOverlay=$("#route-overlay");
var routeDrawer=$("#route-drawer");
var rdBody=$("#rd-body");
var rdTitle=$("#rd-title");
S.routeSelectedIdx=null;
S.routeLastTimestamps={};

function handleRouteEvent(data){
  data._num=++S.routeCounter;
  S.routes.unshift(data);
  if(S.routes.length>5000)S.routes.pop();

  S.routeStack=data.fullStack||[];
  // Track latest timestamp per route for display
  S.routeLastTimestamps[data.routeName]=data.timestamp;

  var card=makeRouteEventCard(data);
  if(routeList.firstChild)routeList.insertBefore(card,routeList.firstChild);
  else routeList.appendChild(card);

  renderRouteStack3D(data.action);
  applyRouteFilters();
  updateCounts();
  toggleRouteEmpty();
}

function makeRouteEventCard(data){
  var el=document.createElement("div");
  el.className="route-ev-card fade-in";
  el.dataset.action=data.action;
  el.dataset.id=data.id;
  el.innerHTML='<span class="route-ev-num">'+data._num+"</span>"+
    '<span class="route-ev-action '+data.action+'">'+data.action+"</span>"+
    '<span class="route-ev-time">'+fmtTime(data.timestamp)+"</span>"+
    '<span class="route-ev-name" title="'+escHtml(data.routeName)+'">'+escHtml(data.routeName)+"</span>"+
    '<span class="route-ev-depth">'+data.depth+"</span>";
  el.addEventListener("click",function(){openRouteDetail(data)});
  return el;
}

var _r3dSelected=-1;

function renderRouteStack3D(lastAction){
  var stack=S.routeStack;
  routeDepthEl.textContent=stack.length;
  var nameCounts={};
  for(var i=0;i<stack.length;i++){nameCounts[stack[i]]=(nameCounts[stack[i]]||0)+1}
  var routeActions={};
  for(var j=S.routes.length-1;j>=0;j--){var r=S.routes[j];if(!routeActions[r.routeName])routeActions[r.routeName]=r.action}

  var cardH=62;var gap=6;var zStep=12;
  var html="";
  for(var i=0;i<stack.length;i++){
    var name=stack[i];var isTop=i===stack.length-1;var isDup=nameCounts[name]>1;
    var fromBottom=i;
    var ty=-(fromBottom*(cardH+gap));
    var tz=fromBottom*zStep;

    var cls="r3d-card";
    if(isTop)cls+=" r3d-active";
    if(isDup)cls+=" r3d-dup";
    if(i===_r3dSelected)cls+=" r3d-selected";
    var anim="";
    if(isTop&&lastAction==="push")anim="animation:r3dPush .4s cubic-bezier(.23,1,.32,1) forwards;";
    var ts=S.routeLastTimestamps[name];var timeTxt=ts?fmtTime(ts):"";
    var status=isTop?"ACTIVE":"#"+(i+1);
    var action=routeActions[name]||"push";
    var shortName=name.replace(/Route$/,"");

    html+='<div class="'+cls+'" data-idx="'+i+'" style="transform:translateY('+ty+'px) translateZ('+tz+'px);z-index:'+(i+1)+';'+anim+'">';
    html+='<div class="r3d-card-inner">';
    html+='<div class="r3d-glow"></div>';
    html+='<div class="r3d-select-ring"></div>';
    html+='<div class="r3d-pulse"></div>';
    html+='<div class="r3d-top-row"><span class="r3d-name" title="'+escHtml(name)+'">'+escHtml(shortName)+'</span><span class="r3d-index">'+status+'</span></div>';
    html+='<div class="r3d-bottom-row">';
    if(timeTxt)html+='<span class="r3d-time">'+timeTxt+'</span>';
    html+='<span class="r3d-action-badge '+action+'">'+action+'</span>';
    if(isDup)html+='<span class="r3d-dup-indicator"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>DUP</span>';
    html+='</div>';
    html+='<div class="r3d-edge-line"></div>';
    html+='</div></div>';
  }
  routeStackEl.innerHTML=html;

  routeStackEl.querySelectorAll(".r3d-card").forEach(function(c){
    c.addEventListener("click",function(e){
      e.stopPropagation();
      var idx=parseInt(c.dataset.idx);
      if(_r3dSelected===idx){_r3dSelected=-1;_hideR3dInfo()}
      else{_r3dSelected=idx;_showR3dInfo(idx)}
      renderRouteStack3D(null);
    });
    c.addEventListener("dblclick",function(e){
      e.stopPropagation();
      openRouteCardDetail(parseInt(c.dataset.idx));
    });
  });
}

function _showR3dInfo(idx){
  var stack=S.routeStack;if(idx<0||idx>=stack.length)return;
  var name=stack[idx];var ts=S.routeLastTimestamps[name];
  var el=document.getElementById("r3d-info");
  document.getElementById("r3d-info-name").textContent=name;
  document.getElementById("r3d-info-meta").textContent="Layer "+(idx+1)+" of "+stack.length+(ts?" \u00b7 "+fmtTime(ts):"");
  el.classList.add("visible");
}
function _hideR3dInfo(){var el=document.getElementById("r3d-info");if(el)el.classList.remove("visible")}

document.addEventListener("DOMContentLoaded",function(){
  var closeBtn=document.getElementById("r3d-info-close");
  if(closeBtn)closeBtn.addEventListener("click",function(){_r3dSelected=-1;_hideR3dInfo();renderRouteStack3D(null)});
  var scene=document.querySelector(".route-3d-scene");
  if(scene)scene.addEventListener("click",function(e){
    if(e.target===scene||e.target.classList.contains("route-stack-3d")){_r3dSelected=-1;_hideR3dInfo();renderRouteStack3D(null)}
  });
});

function openRouteCardDetail(idx){
  if(idx<0||idx>=S.routeStack.length)return;
  var name=S.routeStack[idx];
  // Find the latest route event matching this name
  var ev=null;
  for(var i=0;i<S.routes.length;i++){
    if(S.routes[i].routeName===name){ev=S.routes[i];break}
  }
  if(ev)openRouteDetail(ev,idx);
  else{
    // Build minimal detail from stack info
    openRouteDetail({routeName:name,fullStack:S.routeStack,action:"push",timestamp:Date.now(),depth:S.routeStack.length,id:"stack-"+idx},idx);
  }
}

function openRouteDetail(data,highlightIdx){
  rdTitle.textContent=data.routeName||"Route";
  var idx=highlightIdx!=null?highlightIdx:(data.fullStack?data.fullStack.indexOf(data.routeName):-1);

  var h='<div class="rd-section"><div class="rd-section-title">Details</div>';
  h+='<div class="rd-field"><span class="rd-field-label">Route Name</span><span class="rd-field-value">'+escHtml(data.routeName)+"</span></div>";
  h+='<div class="rd-field"><span class="rd-field-label">Action</span><span class="rd-field-value"><span class="route-ev-action '+data.action+'" style="display:inline-block">'+data.action+"</span></span></div>";
  h+='<div class="rd-field"><span class="rd-field-label">Timestamp</span><span class="rd-field-value">'+fmtTime(data.timestamp)+"</span></div>";
  h+='<div class="rd-field"><span class="rd-field-label">Stack Depth</span><span class="rd-field-value">'+data.depth+"</span></div>";
  if(data.routeType)h+='<div class="rd-field"><span class="rd-field-label">Route Type</span><span class="rd-field-value">'+escHtml(data.routeType)+"</span></div>";
  if(data.previousRouteName)h+='<div class="rd-field"><span class="rd-field-label">Previous Route</span><span class="rd-field-value">'+escHtml(data.previousRouteName)+"</span></div>";
  if(data.arguments)h+='<div class="rd-field"><span class="rd-field-label">Arguments</span><span class="rd-field-value">'+escHtml(data.arguments)+"</span></div>";
  if(data.isModal)h+='<div class="rd-field"><span class="rd-field-label">Modal</span><span class="rd-field-value" style="color:var(--purple)">Yes</span></div>';
  h+="</div>";

  // Stack snapshot
  if(data.fullStack&&data.fullStack.length>0){
    h+='<div class="rd-section"><div class="rd-section-title">Stack Snapshot ('+data.fullStack.length+")</div>";
    for(var i=data.fullStack.length-1;i>=0;i--){
      var isCurrent=i===idx;
      h+='<div class="rd-stack-item'+(isCurrent?" rd-current":"")+'">';
      h+='<span class="rd-stack-idx">'+(i+1)+"</span>";
      h+='<span class="rd-stack-dot"></span>';
      h+='<span class="rd-stack-name">'+escHtml(data.fullStack[i])+"</span></div>";
    }
    h+="</div>";
  }

  // Raw JSON
  h+='<div class="rd-section"><div class="rd-section-title">Raw Event Data</div>';
  var raw={};for(var k in data){if(k[0]!=="_")raw[k]=data[k]}
  h+='<div class="rd-json-block">'+highlightJson(raw,0)+"</div>";
  h+='<button class="copy-btn" style="margin-top:8px" id="rd-copy-json">Copy JSON</button>';
  h+="</div>";

  rdBody.innerHTML=h;
  routeOverlay.classList.add("visible");
  routeDrawer.classList.add("open");

  var copyBtn=$("#rd-copy-json");
  if(copyBtn)copyBtn.addEventListener("click",function(){copyText(JSON.stringify(raw,null,2),copyBtn)});
}

function closeRouteDetail(){
  routeOverlay.classList.remove("visible");
  routeDrawer.classList.remove("open");
}

// Close handlers
$("#rd-close").addEventListener("click",closeRouteDetail);
routeOverlay.addEventListener("click",closeRouteDetail);

function applyRouteFilters(){
  var search=S.filters.routeSearch.toLowerCase();
  routeList.querySelectorAll(".route-ev-card").forEach(function(c){
    var act=c.dataset.action;
    var show=S.filters.routeAction[act]!==false;
    if(show&&search){var txt=c.textContent.toLowerCase();if(txt.indexOf(search)===-1)show=false}
    c.style.display=show?"":"none";
  });
}
function toggleRouteEmpty(){
  var has=S.routes.length>0;
  routeEmpty.style.display=has?"none":"flex";
  routeList.style.display=has?"":"none";
}

// ── Socket ────────────────────────────────────────────────
function handleSocketEvent(data){
  S.sockCounter++;data._num=S.sockCounter;
  S.sockets.unshift(data);if(S.sockets.length>5000)S.sockets.pop();
  var card=makeSockCard(data);sockList.prepend(card);
  if(sockList.children.length>5000)sockList.removeChild(sockList.lastChild);
  applySockFilters();updateCounts();toggleSockEmpty();
}
function makeSockCard(ev){
  var card=document.createElement("div");
  var dir=ev.direction||"receive";
  card.className="sock-card sock-"+dir+(ev.error?" sock-error":"")+" fade-in";
  card.dataset.dir=dir;
  card.addEventListener("click",function(e){if(!e.target.closest(".sock-copy"))card.classList.toggle("expanded")});
  var typeLabel=ev.messageType||"unknown";
  var channelLabel=ev.channel||"";
  var sizeLabel=formatSize(ev.sizeBytes);
  var timeLabel=fmtTime(ev.timestamp);
  var dataStr=ev.data!=null?(typeof ev.data==="string"?ev.data:JSON.stringify(ev.data,null,2)):"(empty)";
  var preview=dataStr.length>120?dataStr.substring(0,120)+"\u2026":dataStr;
  preview=preview.replace(/\n/g," ");
  card.innerHTML='<span class="sock-num">'+ev._num+'</span>'
    +'<span class="sock-dir '+dir+'">'+(dir==="send"?"\u25B2 SEND":"\u25BC RECV")+'</span>'
    +'<div class="sock-meta"><div class="sock-headline"><span class="sock-type">'+escHtml(typeLabel)+'</span>'
    +(channelLabel?'<span class="sock-channel">'+escHtml(channelLabel)+'</span>':'')
    +'</div><div class="sock-preview">'+escHtml(preview)+'</div></div>'
    +(sizeLabel?'<span class="sock-size">'+sizeLabel+'</span>':'')
    +'<button class="sock-copy" title="Copy payload">\uD83D\uDCCB</button>'
    +'<span class="sock-time">'+timeLabel+'</span>'
    +'<div class="sock-expand"><div class="sock-data-label">Payload</div><div class="sock-data-body">'+escHtml(dataStr)+'</div>'
    +(ev.error?'<div class="sock-error-msg">Error: '+escHtml(ev.error)+'</div>':'')
    +'</div>';
  var copyBtn=card.querySelector(".sock-copy");
  copyBtn.addEventListener("click",function(e){
    e.stopPropagation();
    navigator.clipboard.writeText(dataStr).then(function(){
      copyBtn.textContent="\u2713";copyBtn.classList.add("copied");
      setTimeout(function(){copyBtn.textContent="\uD83D\uDCCB";copyBtn.classList.remove("copied")},1500);
    });
  });
  return card;
}
function formatSize(b){
  if(b==null)return"";if(b<1024)return b+"B";if(b<1024*1024)return(b/1024).toFixed(1)+"KB";return(b/(1024*1024)).toFixed(1)+"MB";
}
function applySockFilters(){
  var search=S.filters.sockSearch.toLowerCase();
  sockList.querySelectorAll(".sock-card").forEach(function(c){
    var dir=c.dataset.dir;var show=S.filters.sockDir[dir]!==false;
    if(show&&search){if(c.textContent.toLowerCase().indexOf(search)===-1)show=false}
    c.style.display=show?"":"none";
  });
}
function toggleSockEmpty(){
  var has=S.sockets.length>0;
  sockEmpty.style.display=has?"none":"flex";
  sockList.style.display=has?"":"none";
}

var sockStatusBar=$("#sock-status-bar");
var sockStatuses={};
function handleSocketStatus(data){
  var ch=data.channel||"unknown";
  var st=data.state||"disconnected";
  sockStatuses[ch]=st;
  renderSockStatuses();
}
function renderSockStatuses(){
  sockStatusBar.innerHTML="";
  for(var ch in sockStatuses){
    var st=sockStatuses[ch];
    var label=st.charAt(0).toUpperCase()+st.slice(1);
    var chip=document.createElement("span");
    chip.className="sock-status-chip st-"+st;
    chip.innerHTML='<span class="sock-status-dot"></span>'+escHtml(ch)+' \u2014 '+label;
    sockStatusBar.appendChild(chip);
  }
}

// ── Clear ─────────────────────────────────────────────────
function clearAll(){
  S.netMap={};S.netOrder=[];S.netCounter=0;S.logCounter=0;S.errCounter=0;S.instCounter=0;S.routeCounter=0;S.sockCounter=0;tlCounter=0;S.logs=[];S.errors=[];S.instances=[];S.routes=[];S.routeStack=[];S.routeLastTimestamps={};S.routeSelectedIdx=null;S.sockets=[];S.instCategoryCounts={bloc:0,repository:0,service:0,network:0,other:0};S.instActiveMap={};S.instTypeCreations={};S.selectedId=null;sockStatuses={};
  netTbody.innerHTML="";logList.innerHTML="";errList.innerHTML="";instList.innerHTML="";tlList.innerHTML="";instSummary.innerHTML="";routeList.innerHTML="";routeStackEl.innerHTML="";routeDepthEl.textContent="0";sockList.innerHTML="";sockStatusBar.innerHTML="";
  closeDetail();closeRouteDetail();
  updateCounts();toggleNetEmpty();toggleLogEmpty();toggleErrEmpty();toggleInstEmpty();toggleTlEmpty();toggleRouteEmpty();toggleSockEmpty();
}

// ── WebSocket ─────────────────────────────────────────────
var ws={socket:null,delay:1000,maxDelay:10000,timer:null,wasConnected:false};
function wsConnect(){
  var loc=window.location;
  var url="ws://"+loc.host+"/stream";
  ws.socket=new WebSocket(url);
  ws.socket.onopen=function(){
    if(ws.wasConnected)clearAll();
    ws.wasConnected=true;
    ws.delay=1000;
    connDot.className="conn-dot on";connText.textContent="Connected";
  };
  ws.socket.onclose=function(){
    connDot.className="conn-dot off";connText.textContent="Reconnecting...";
    ws.timer=setTimeout(wsConnect,ws.delay);
    ws.delay=Math.min(ws.delay*2,ws.maxDelay);
  };
  ws.socket.onerror=function(){};
  ws.socket.onmessage=function(e){
    try{var data=JSON.parse(e.data)}catch(_){return}
    if(data.type==="network")handleNetworkEvent(data);
    else if(data.type==="log")handleLogEvent(data);
    else if(data.type==="instance")handleInstanceEvent(data);
    else if(data.type==="route")handleRouteEvent(data);
    else if(data.type==="socket")handleSocketEvent(data);
    else if(data.type==="socket_status")handleSocketStatus(data);
    else if(data.type==="clear")clearAll();
  };
}

// ── Tab Switching ─────────────────────────────────────────
$$(".tab-btn").forEach(function(btn){
  btn.addEventListener("click",function(){
    var tab=btn.dataset.tab;
    S.activeTab=tab;
    $$(".tab-btn").forEach(function(b){b.classList.toggle("active",b.dataset.tab===tab)});
    $$(".tab-panel").forEach(function(p){p.classList.toggle("active",p.id==="panel-"+tab)});
  });
});

// ── Filter Chips ──────────────────────────────────────────
$$(".chip[data-filter]").forEach(function(chip){
  chip.addEventListener("click",function(){
    chip.classList.toggle("on");chip.classList.toggle("off");
    var f=chip.dataset.filter;var v=chip.dataset.val;
    if(f==="method")S.filters.method[v]=chip.classList.contains("on");
    else if(f==="status")S.filters.status[v]=chip.classList.contains("on");
    else if(f==="level")S.filters.level[v]=chip.classList.contains("on");
    else if(f==="cat")S.filters.cat[v]=chip.classList.contains("on");
    else if(f==="action")S.filters.action[v]=chip.classList.contains("on");
    else if(f==="routeAction")S.filters.routeAction[v]=chip.classList.contains("on");
    else if(f==="sockDir")S.filters.sockDir[v]=chip.classList.contains("on");
    if(f==="method"||f==="status")applyNetFilters();
    else if(f==="level")applyLogFilters();
    else if(f==="cat"||f==="action")applyInstFilters();
    else if(f==="routeAction")applyRouteFilters();
    else if(f==="sockDir")applySockFilters();
  });
});

// ── Search Inputs ─────────────────────────────────────────
var searchTimeout;
function debounce(fn,ms){return function(){clearTimeout(searchTimeout);searchTimeout=setTimeout(fn,ms)}}
$("#net-search").addEventListener("input",debounce(function(){S.filters.netSearch=$("#net-search").value;applyNetFilters()},150));
$("#log-search").addEventListener("input",debounce(function(){S.filters.logSearch=$("#log-search").value;applyLogFilters()},150));
$("#err-search").addEventListener("input",debounce(function(){S.filters.errSearch=$("#err-search").value;applyErrFilters()},150));
$("#inst-search").addEventListener("input",debounce(function(){S.filters.instSearch=$("#inst-search").value;applyInstFilters()},150));
$("#route-search").addEventListener("input",debounce(function(){S.filters.routeSearch=$("#route-search").value;applyRouteFilters()},150));
$("#sock-search").addEventListener("input",debounce(function(){S.filters.sockSearch=$("#sock-search").value;applySockFilters()},150));

// ── Instance View Toggle ──────────────────────────────────
$$(".view-btn").forEach(function(btn){
  btn.addEventListener("click",function(){
    var v=btn.dataset.view;
    $$(".view-btn").forEach(function(b){b.classList.toggle("active",b.dataset.view===v)});
    $$(".inst-view").forEach(function(p){p.classList.toggle("active",p.id==="inst-view-"+v)});
  });
});

// ── Section Toggle ────────────────────────────────────────
document.addEventListener("click",function(e){
  var head=e.target.closest(".section-head");
  if(head)head.classList.toggle("open");
});

// ── Clear Button ──────────────────────────────────────────
$("#btn-clear").addEventListener("click",function(){
  clearAll();
  if(ws.socket&&ws.socket.readyState===WebSocket.OPEN)ws.socket.send("clear");
});

// ── Copy All Logs ─────────────────────────────────────────
$("#btn-copy-logs").addEventListener("click",function(){
  var btn=this;
  var visible=S.logs.filter(function(d){
    if(S.filters.level[d.level]===false)return false;
    var s=S.filters.logSearch.toLowerCase();
    if(s&&d.message.toLowerCase().indexOf(s)===-1)return false;
    return true;
  });
  var txt=visible.map(fmtLogText).join("\n\n");
  navigator.clipboard.writeText(txt).then(function(){
    var orig=btn.textContent;btn.textContent="Copied!";
    setTimeout(function(){btn.textContent=orig},1500);
  });
});

// ── Detail Close ──────────────────────────────────────────
$("#detail-close").addEventListener("click",closeDetail);
document.addEventListener("keydown",function(e){if(e.key==="Escape")closeDetail()});

// ── Init ──────────────────────────────────────────────────
toggleNetEmpty();toggleLogEmpty();toggleErrEmpty();toggleInstEmpty();toggleTlEmpty();toggleRouteEmpty();
wsConnect();

})();
</script>
</body>
</html>''';
