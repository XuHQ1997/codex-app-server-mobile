import 'dart:convert';

import 'package:codexcli_remote/data/codex_service.dart';
import 'package:codexcli_remote/protocol/thread_settings.dart';
import 'package:codexcli_remote/rpc/rpc_client.dart';
import 'package:codexcli_remote/rpc/rpc_method_names.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rpc_client_test.dart' show FakeTransport;

void main() {
  group('CodexService composer tools', () {
    late FakeTransport transport;
    late RpcClient client;
    late CodexService service;

    setUp(() {
      // Echo an empty result for every request so the awaited call completes.
      transport = FakeTransport()
        ..autoResponder = (out) => '{"id":${out['id']},"result":{}}';
      client = RpcClient(transport: transport);
      client.start();
      service = CodexService(client);
    });

    Map<String, dynamic> lastRequest() {
      // The transport records raw outbound frames; the request is the last one.
      return jsonDecode(transport.sent.last) as Map<String, dynamic>;
    }

    test('setGoal sends thread/goal/set with objective', () async {
      await service.setGoal('t1', objective: 'Ship the release');
      final req = lastRequest();
      expect(req['method'], RpcMethods.threadGoalSet);
      expect(req['params'], {
        'threadId': 't1',
        'objective': 'Ship the release',
      });
    });

    test('setGoal omits objective when null', () async {
      await service.setGoal('t1', status: 'paused');
      final req = lastRequest();
      expect(req['method'], RpcMethods.threadGoalSet);
      expect(req['params'], {'threadId': 't1', 'status': 'paused'});
    });

    test('compactThread sends thread/compact/start', () async {
      await service.compactThread('t1');
      final req = lastRequest();
      expect(req['method'], RpcMethods.threadCompactStart);
      expect(req['params'], {'threadId': 't1'});
    });

    test('clearGoal sends thread/goal/clear', () async {
      await service.clearGoal('t1');
      final req = lastRequest();
      expect(req['method'], RpcMethods.threadGoalClear);
      expect(req['params'], {'threadId': 't1'});
    });

    test('updateThreadSettings sends only changed fields', () async {
      await service.updateThreadSettings(
        't1',
        model: 'gpt-5-codex',
        effort: ReasoningEffort.high,
      );
      final req = lastRequest();
      expect(req['method'], RpcMethods.threadSettingsUpdate);
      expect(req['params'], {
        'threadId': 't1',
        'model': 'gpt-5-codex',
        'effort': 'high',
      });
    });

    test('updateThreadSettings serializes approvalPolicy to its wire value',
        () async {
      await service.updateThreadSettings(
        't1',
        approvalPolicy: ApprovalPolicy.onRequest,
      );
      final req = lastRequest();
      expect(req['params'], {'threadId': 't1', 'approvalPolicy': 'on-request'});
    });
  });
}
