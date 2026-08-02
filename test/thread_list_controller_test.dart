import 'dart:convert';

import 'package:codexcli_remote/data/codex_service.dart';
import 'package:codexcli_remote/rpc/rpc_client.dart';
import 'package:codexcli_remote/state/thread_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rpc_client_test.dart' show FakeTransport;

void main() {
  group('ThreadListController sorting', () {
    test('orders threads by most-recent updatedAt first', () async {
      // A single page of threads returned out of recency order.
      final transport = FakeTransport()
        ..autoResponder = (out) {
          if (out['method'] != 'thread/list') {
            return '{"id":${out['id']},"result":{}}';
          }
          final result = {
            'data': [
              {'id': 'old', 'updatedAt': 1000},
              {'id': 'newest', 'updatedAt': 3000},
              {'id': 'mid', 'updatedAt': 2000},
              {'id': 'no_time'},
            ],
            'nextCursor': null,
          };
          return jsonEncode({'id': out['id'], 'result': result});
        };
      final client = RpcClient(transport: transport)..start();
      final controller = ThreadListController(CodexService(client));

      await controller.refresh();

      final ids = controller.threads.map((t) => t.id).toList();
      // Most recent first; the timestamp-less thread sorts to the end.
      expect(ids, ['newest', 'mid', 'old', 'no_time']);

      await client.dispose();
      await transport.close();
    });

    test('groups by cwd while retaining recency order', () async {
      final transport = FakeTransport()
        ..autoResponder = (out) {
          final result = {
            'data': [
              {'id': 'a-old', 'cwd': '/work/a', 'updatedAt': 1000},
              {'id': 'b-new', 'cwd': '/work/b', 'updatedAt': 4000},
              {'id': 'a-new', 'cwd': '/work/a', 'updatedAt': 3000},
              {'id': 'unknown', 'updatedAt': 2000},
            ],
            'nextCursor': null,
          };
          return jsonEncode({'id': out['id'], 'result': result});
        };
      final client = RpcClient(transport: transport)..start();
      final controller = ThreadListController(CodexService(client));

      await controller.refresh();

      expect(controller.directoryGroups.map((group) => group.cwd), [
        '/work/b',
        '/work/a',
        null,
      ]);
      expect(controller.directoryGroups[1].threads.map((thread) => thread.id), [
        'a-new',
        'a-old',
      ]);

      await client.dispose();
      await transport.close();
    });
  });
}
