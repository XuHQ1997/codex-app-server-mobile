import 'dart:async';
import 'dart:io';

import '../core/constants.dart';
import '../core/logging.dart';
import 'ws_transport.dart';

/// A [WsTransport] backed by `dart:io`'s [WebSocket].
///
/// We use `dart:io` directly (rather than a higher-level wrapper) because the
/// codex app-server has two strict handshake requirements:
///
///  * The client must present `Authorization: Bearer <token>` when the server
///    is started with `--ws-auth`.
///  * The client must NOT send an `Origin` header — the axum layer rejects any
///    upgrade request carrying `Origin` with `403 Forbidden`.
///
/// `WebSocket.connect` from `dart:io` does not add an `Origin` header for
/// non-browser clients, which is exactly what we need. (This is why the app is
/// mobile-only and never built for Flutter web, where the browser forces an
/// Origin header and blocks custom WebSocket headers.)
class IoWsTransport implements WsTransport {
  IoWsTransport({required this.url, this.bearerToken});

  /// `ws://host:port`. IPv6 literals must be bracketed.
  final String url;

  /// Optional capability/bearer token sent as `Authorization: Bearer <token>`.
  final String? bearerToken;

  final _log = appLogger('IoWsTransport');
  final _incoming = StreamController<String>.broadcast();
  final _done = Completer<void>();

  WebSocket? _socket;
  StreamSubscription<dynamic>? _sub;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> connect() async {
    final headers = <String, dynamic>{
      if (bearerToken != null && bearerToken!.isNotEmpty)
        HttpHeaders.authorizationHeader: 'Bearer $bearerToken',
    };

    _log.info('Connecting to $url');
    final socket = await WebSocket.connect(url, headers: headers);
    socket.pingInterval = AppConstants.pingInterval;
    _socket = socket;

    _sub = socket.listen(
      (data) {
        if (data is String) {
          _incoming.add(data);
        } else {
          // Binary frames are not part of the JSON-RPC protocol; ignore them.
          _log.fine('Ignoring non-text frame (${data.runtimeType})');
        }
      },
      onError: (Object e, StackTrace st) {
        _log.warning('Socket error', e, st);
        _finish();
      },
      onDone: () {
        _log.info('Socket closed (code=${socket.closeCode})');
        _finish();
      },
      cancelOnError: false,
    );
  }

  @override
  void send(String message) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('Cannot send: transport is not connected');
    }
    socket.add(message);
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    await _socket?.close();
    _socket = null;
    _finish();
    await _incoming.close();
  }

  void _finish() {
    if (!_done.isCompleted) _done.complete();
  }
}
