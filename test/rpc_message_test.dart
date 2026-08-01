import 'package:codexcli_remote/rpc/rpc_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InboundMessage.decode', () {
    test('classifies a response with result', () {
      final msg = InboundMessage.decode('{"id":1,"result":{"ok":true}}');
      expect(msg.kind, InboundKind.response);
      expect(msg.id, 1);
      expect((msg.result as Map)['ok'], true);
      expect(msg.error, isNull);
    });

    test('classifies a response with error', () {
      final msg = InboundMessage.decode(
        '{"id":2,"error":{"code":-32001,"message":"Server overloaded; retry later."}}',
      );
      expect(msg.kind, InboundKind.response);
      expect(msg.error, isNotNull);
      expect(msg.error!.code, -32001);
    });

    test('classifies a server->client request (has id and method)', () {
      final msg = InboundMessage.decode(
        '{"id":61,"method":"item/commandExecution/requestApproval",'
        '"params":{"command":"ls","cwd":"/tmp"}}',
      );
      expect(msg.kind, InboundKind.serverRequest);
      expect(msg.id, 61);
      expect(msg.method, 'item/commandExecution/requestApproval');
      expect(msg.params!['command'], 'ls');
    });

    test('classifies a notification (method, no id)', () {
      final msg = InboundMessage.decode(
        '{"method":"item/agentMessage/delta",'
        '"params":{"threadId":"t1","itemId":"i1","delta":"hi"}}',
      );
      expect(msg.kind, InboundKind.notification);
      expect(msg.id, isNull);
      expect(msg.method, 'item/agentMessage/delta');
      expect(msg.params!['delta'], 'hi');
    });

    test('ignores a stray jsonrpc header field', () {
      final msg = InboundMessage.decode(
        '{"jsonrpc":"2.0","id":5,"result":{}}',
      );
      expect(msg.kind, InboundKind.response);
      expect(msg.id, 5);
    });

    test('marks malformed frames invalid', () {
      expect(InboundMessage.decode('not json').kind, InboundKind.invalid);
      expect(InboundMessage.decode('[]').kind, InboundKind.invalid);
      expect(InboundMessage.decode('{}').kind, InboundKind.invalid);
    });
  });

  group('RpcRequest encoding', () {
    test('never includes a jsonrpc field', () {
      final encoded = RpcRequest(id: 1, method: 'initialize', params: {'a': 1})
          .encode();
      expect(encoded.contains('jsonrpc'), isFalse);
      expect(encoded.contains('"method":"initialize"'), isTrue);
    });

    test('omits params when null', () {
      final encoded = RpcRequest(id: 2, method: 'initialized').encode();
      expect(encoded.contains('params'), isFalse);
    });
  });
}
