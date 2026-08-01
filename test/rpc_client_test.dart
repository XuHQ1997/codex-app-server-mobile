import 'dart:async';
import 'dart:convert';

import 'package:codexcli_remote/rpc/rpc_client.dart';
import 'package:codexcli_remote/rpc/rpc_message.dart';
import 'package:codexcli_remote/transport/ws_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory transport that lets tests script server responses.
class FakeTransport implements WsTransport {
  final _incoming = StreamController<String>.broadcast();
  final _done = Completer<void>();
  final List<String> sent = [];

  /// Called with each outbound frame; return value (if non-null) is pushed
  /// back as an inbound frame to simulate a server reply.
  String? Function(Map<String, dynamic> outbound)? autoResponder;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> connect() async {}

  @override
  void send(String message) {
    sent.add(message);
    final decoded = _decode(message);
    final reply = autoResponder?.call(decoded);
    if (reply != null) {
      scheduleMicrotask(() => _incoming.add(reply));
    }
  }

  void push(String frame) => _incoming.add(frame);

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
    await _incoming.close();
  }

  static Map<String, dynamic> _decode(String s) {
    return jsonDecode(s) as Map<String, dynamic>;
  }
}

void main() {
  test('call() correlates a response to its request id', () async {
    final transport = FakeTransport()
      ..autoResponder = (out) {
        final id = out['id'];
        return '{"id":$id,"result":{"echo":"${out['method']}"}}';
      };
    final client = RpcClient(transport: transport);
    client.start();

    final result = await client.callObject('thread/start');
    expect(result['echo'], 'thread/start');

    await client.dispose();
    await transport.close();
  });

  test('call() surfaces an error response as RpcError', () async {
    final transport = FakeTransport()
      ..autoResponder = (out) {
        final id = out['id'];
        return '{"id":$id,"error":{"code":-32001,'
            '"message":"Server overloaded; retry later."}}';
      };
    final client = RpcClient(transport: transport);
    client.start();

    await expectLater(
      client.call('turn/start'),
      throwsA(isA<RpcError>()
          .having((e) => e.code, 'code', -32001)),
    );

    await client.dispose();
    await transport.close();
  });

  test('server->client request is routed and answered exactly once', () async {
    final transport = FakeTransport();
    final client = RpcClient(transport: transport);
    client.router.register('item/commandExecution/requestApproval', (params) async {
      return {'decision': 'accept'};
    });
    client.start();

    // Simulate an inbound approval request from the server.
    transport.push(
      '{"id":99,"method":"item/commandExecution/requestApproval",'
      '"params":{"command":"ls"}}',
    );

    // The client should send back exactly one response with the same id.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final responses = transport.sent
        .map(FakeTransport._decode)
        .where((m) => m['id'] == 99)
        .toList();
    expect(responses.length, 1);
    expect((responses.first['result'] as Map)['decision'], 'accept');

    await client.dispose();
    await transport.close();
  });

  test('unhandled server request gets a method-not-found error', () async {
    final transport = FakeTransport();
    final client = RpcClient(transport: transport);
    client.start();

    transport.push('{"id":7,"method":"some/unknown/request","params":{}}');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final response = transport.sent
        .map(FakeTransport._decode)
        .firstWhere((m) => m['id'] == 7);
    expect((response['error'] as Map)['code'], -32601);

    await client.dispose();
    await transport.close();
  });
}
