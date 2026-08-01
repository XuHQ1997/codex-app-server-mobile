import 'dart:convert';

/// JSON-RPC 2.0 message envelopes for the codex app-server.
///
/// The wire format intentionally OMITS the `"jsonrpc": "2.0"` header (the
/// server neither sends nor requires it), and puts exactly one message per
/// WebSocket text frame. These helpers never add that field on encode and
/// ignore it on decode.

/// An outbound request expecting a response.
class RpcRequest {
  RpcRequest({required this.id, required this.method, this.params});

  final Object id; // int or String
  final String method;
  final Map<String, dynamic>? params;

  Map<String, dynamic> toJson() => {
    'id': id,
    'method': method,
    if (params != null) 'params': params,
  };

  String encode() => jsonEncode(toJson());
}

/// An outbound notification (no id, no response expected).
class RpcNotification {
  RpcNotification({required this.method, this.params});

  final String method;
  final Map<String, dynamic>? params;

  Map<String, dynamic> toJson() => {
    'method': method,
    if (params != null) 'params': params,
  };

  String encode() => jsonEncode(toJson());
}

/// A JSON-RPC error object.
class RpcError implements Exception {
  RpcError({required this.code, required this.message, this.data});

  final int code;
  final String message;
  final Object? data;

  factory RpcError.fromJson(Map<String, dynamic> json) => RpcError(
    code: (json['code'] as num).toInt(),
    message: json['message'] as String? ?? 'Unknown error',
    data: json['data'],
  );

  @override
  String toString() => 'RpcError($code): $message';
}

/// Classification of a decoded inbound frame.
enum InboundKind { response, serverRequest, notification, invalid }

/// A parsed inbound frame from the server.
class InboundMessage {
  InboundMessage._(this.kind, this.raw, {this.id, this.method, this.params, this.result, this.error});

  final InboundKind kind;
  final Map<String, dynamic> raw;
  final Object? id;
  final String? method;
  final Map<String, dynamic>? params;
  final Object? result;
  final RpcError? error;

  /// Decodes a single text frame and classifies it by shape:
  ///  * has `id` and (`result` or `error`) -> response
  ///  * has `id` and `method`              -> server->client request
  ///  * has `method`, no `id`              -> notification
  static InboundMessage decode(String frame) {
    late final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(frame);
      if (decoded is! Map<String, dynamic>) {
        return InboundMessage._(InboundKind.invalid, const {});
      }
      json = decoded;
    } catch (_) {
      return InboundMessage._(InboundKind.invalid, const {});
    }

    final id = json['id'];
    final method = json['method'] as String?;
    final hasResult = json.containsKey('result');
    final hasError = json.containsKey('error');

    if (id != null && (hasResult || hasError)) {
      return InboundMessage._(
        InboundKind.response,
        json,
        id: id,
        result: json['result'],
        error: hasError && json['error'] is Map<String, dynamic>
            ? RpcError.fromJson(json['error'] as Map<String, dynamic>)
            : null,
      );
    }

    if (id != null && method != null) {
      return InboundMessage._(
        InboundKind.serverRequest,
        json,
        id: id,
        method: method,
        params: _asParams(json['params']),
      );
    }

    if (method != null) {
      return InboundMessage._(
        InboundKind.notification,
        json,
        method: method,
        params: _asParams(json['params']),
      );
    }

    return InboundMessage._(InboundKind.invalid, json);
  }

  static Map<String, dynamic>? _asParams(Object? params) =>
      params is Map<String, dynamic> ? params : null;
}
