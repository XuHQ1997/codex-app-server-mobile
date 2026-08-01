import 'dart:async';
import 'dart:convert';

import '../core/constants.dart';
import '../core/logging.dart';
import '../transport/ws_transport.dart';
import 'rpc_message.dart';
import 'server_request_router.dart';

/// Correlates JSON-RPC requests with responses over a [WsTransport], routes
/// inbound frames, and exposes a broadcast stream of notifications.
///
/// Routing rules (see [InboundMessage.decode]):
///  * response       -> completes the pending future for that id
///  * server request -> dispatched via [ServerRequestRouter]; the returned
///                       result (or thrown [RpcError]) is sent back with the id
///  * notification   -> pushed onto [notifications]
class RpcClient {
  RpcClient({required this.transport, ServerRequestRouter? router})
    : router = router ?? ServerRequestRouter();

  final WsTransport transport;
  final ServerRequestRouter router;

  final _log = appLogger('RpcClient');
  final _notifications = StreamController<InboundMessage>.broadcast();
  final _rawFrames = StreamController<RawFrame>.broadcast();
  final Map<Object, Completer<Object?>> _pending = {};

  /// Ring buffer of the most recent raw frames, so the debug inspector can
  /// replay history when opened after traffic has already flowed (the
  /// [rawFrames] stream itself does not buffer for late subscribers).
  final List<RawFrame> _recentFrames = [];
  static const _maxRecentFrames = 300;

  int _nextId = 1;
  StreamSubscription<String>? _sub;
  bool _closed = false;

  /// Broadcast stream of inbound notifications.
  Stream<InboundMessage> get notifications => _notifications.stream;

  /// Raw inbound/outbound frames for the debug frame inspector.
  Stream<RawFrame> get rawFrames => _rawFrames.stream;

  /// A snapshot of recently observed frames (oldest first) for the inspector to
  /// render immediately on open.
  List<RawFrame> get recentFrames => List.unmodifiable(_recentFrames);

  /// Records a frame into the ring buffer and publishes it to live listeners.
  void _emitFrame(RawFrame frame) {
    _recentFrames.add(frame);
    if (_recentFrames.length > _maxRecentFrames) _recentFrames.removeAt(0);
    _rawFrames.add(frame);
  }

  /// Begins consuming inbound frames. Call after [transport.connect].
  void start() {
    _sub = transport.incoming.listen(_onFrame, onDone: _onTransportDone);
  }

  void _onTransportDone() {
    // Fail all in-flight requests so callers don't hang forever.
    final err = StateError('Transport closed');
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(err);
    }
    _pending.clear();
  }

  Future<void> _onFrame(String frame) async {
    _emitFrame(RawFrame(direction: FrameDirection.inbound, text: frame));
    final msg = InboundMessage.decode(frame);
    switch (msg.kind) {
      case InboundKind.response:
        final completer = _pending.remove(msg.id);
        if (completer == null) {
          _log.warning('Response for unknown id: ${msg.id}');
          return;
        }
        if (msg.error != null) {
          completer.completeError(msg.error!);
        } else {
          completer.complete(msg.result);
        }
      case InboundKind.serverRequest:
        await _handleServerRequest(msg);
      case InboundKind.notification:
        _notifications.add(msg);
      case InboundKind.invalid:
        _log.warning('Ignoring invalid inbound frame');
    }
  }

  Future<void> _handleServerRequest(InboundMessage msg) async {
    final method = msg.method!;
    final id = msg.id!;
    // Surface the request to any notification listeners too (so UI can show a
    // pending prompt even before the handler resolves).
    _notifications.add(msg);

    if (!router.canHandle(method)) {
      _log.warning('No handler for server request: $method');
      _sendRaw({
        'id': id,
        'error': {'code': -32601, 'message': 'No handler for method: $method'},
      });
      return;
    }

    try {
      final result = await router.dispatch(method, msg.params ?? const {});
      _sendRaw({'id': id, 'result': result});
    } on RpcError catch (e) {
      _sendRaw({
        'id': id,
        'error': {'code': e.code, 'message': e.message, if (e.data != null) 'data': e.data},
      });
    } catch (e, st) {
      _log.warning('Server request handler threw', e, st);
      _sendRaw({
        'id': id,
        'error': {'code': -32000, 'message': e.toString()},
      });
    }
  }

  /// Sends a request and awaits its response.
  Future<Object?> call(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = AppConstants.requestTimeout,
  }) {
    if (_closed) {
      return Future.error(StateError('RpcClient is closed'));
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;

    final request = RpcRequest(id: id, method: method, params: params);
    final encoded = request.encode();
    _emitFrame(RawFrame(direction: FrameDirection.outbound, text: encoded));
    try {
      transport.send(encoded);
    } catch (e) {
      _pending.remove(id);
      return Future.error(e);
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('Request timed out: $method', timeout);
      },
    );
  }

  /// Sends a request and returns the result decoded as a JSON object.
  Future<Map<String, dynamic>> callObject(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = AppConstants.requestTimeout,
  }) async {
    final result = await call(method, params: params, timeout: timeout);
    if (result is Map<String, dynamic>) return result;
    return <String, dynamic>{};
  }

  /// Sends a notification (no response expected).
  void notify(String method, {Map<String, dynamic>? params}) {
    final n = RpcNotification(method: method, params: params);
    final encoded = n.encode();
    _emitFrame(RawFrame(direction: FrameDirection.outbound, text: encoded));
    transport.send(encoded);
  }

  void _sendRaw(Map<String, dynamic> json) {
    final encoded = jsonEncode(json);
    _emitFrame(RawFrame(direction: FrameDirection.outbound, text: encoded));
    transport.send(encoded);
  }

  Future<void> dispose() async {
    _closed = true;
    await _sub?.cancel();
    _onTransportDone();
    await _notifications.close();
    await _rawFrames.close();
  }
}

/// Direction of a raw frame for the debug inspector.
enum FrameDirection { inbound, outbound }

/// A raw JSON-RPC frame observed on the wire (for debugging).
class RawFrame {
  RawFrame({required this.direction, required this.text})
    : timestamp = DateTime.now();

  final FrameDirection direction;
  final String text;
  final DateTime timestamp;
}
