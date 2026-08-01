import 'dart:async';

import 'rpc_message.dart';

/// A handler for a server-initiated JSON-RPC request. Returns the `result`
/// object to send back, or throws an [RpcError] to send an error response.
typedef ServerRequestHandler = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> params,
);

/// Routes server->client requests (e.g. approval prompts) to registered
/// handlers, guaranteeing that exactly one response is emitted per request.
///
/// The router itself does not know how to send frames; the [RpcClient] owns the
/// transport and wires responses back. This class only maps method -> handler.
class ServerRequestRouter {
  final Map<String, ServerRequestHandler> _handlers = {};

  void register(String method, ServerRequestHandler handler) {
    _handlers[method] = handler;
  }

  void unregister(String method) => _handlers.remove(method);

  bool canHandle(String method) => _handlers.containsKey(method);

  /// Invokes the handler for [method]. Throws [RpcError] with code -32601 when
  /// no handler is registered (JSON-RPC "method not found").
  Future<Map<String, dynamic>> dispatch(
    String method,
    Map<String, dynamic> params,
  ) async {
    final handler = _handlers[method];
    if (handler == null) {
      throw RpcError(code: -32601, message: 'No handler for method: $method');
    }
    return handler(params);
  }
}
