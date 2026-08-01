import 'package:codexcli_remote/data/codex_service.dart';
import 'package:codexcli_remote/rpc/rpc_client.dart';
import 'package:codexcli_remote/state/thread_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rpc_client_test.dart' show FakeTransport;

void main() {
  group('ThreadSessionController.hydrateFromThread', () {
    late ThreadSessionController controller;

    setUp(() {
      final transport = FakeTransport();
      final client = RpcClient(transport: transport)..start();
      controller = ThreadSessionController(
        threadId: 't1',
        client: client,
        service: CodexService(client),
      );
    });

    test('restores a running turn from the last turn of a resume', () {
      controller.hydrateFromThread({
        'thread': {
          'id': 't1',
          'turns': [
            {
              'id': 'turn1',
              'status': 'inProgress',
              'items': [
                {'id': 'u1', 'type': 'userMessage', 'content': [
                  {'type': 'text', 'text': 'hello'}
                ]},
              ],
            },
          ],
        },
      });
      final session = controller.session;
      // The just-sent user message is present again after hydration.
      expect(session.items.map((i) => i.id), contains('u1'));
      // And the turn reads as running, so the composer shows interrupt.
      expect(session.turn.isRunning, isTrue);
      expect(session.turn.turnId, 'turn1');
    });

    test('marks a completed turn as not running', () {
      controller.hydrateFromThread({
        'thread': {
          'id': 't1',
          'turns': [
            {'id': 'turn1', 'status': 'completed', 'items': <dynamic>[]},
          ],
        },
      });
      expect(controller.session.turn.isRunning, isFalse);
      expect(controller.session.turn.status, 'completed');
    });

    test('uses the LAST turn status when multiple turns exist', () {
      controller.hydrateFromThread({
        'thread': {
          'id': 't1',
          'turns': [
            {'id': 'turn1', 'status': 'completed', 'items': <dynamic>[]},
            {'id': 'turn2', 'status': 'inProgress', 'items': <dynamic>[]},
          ],
        },
      });
      expect(controller.session.turn.isRunning, isTrue);
      expect(controller.session.turn.turnId, 'turn2');
    });

    test('leaves turn untouched when resume reports no turns', () {
      controller.hydrateFromThread({
        'thread': {'id': 't1', 'turns': <dynamic>[]},
      });
      // Default idle state preserved.
      expect(controller.session.turn.status, 'idle');
    });

    test('session starts un-hydrated and becomes hydrated after load', () {
      expect(controller.session.hydrated, isFalse);
      controller.hydrateFromThread({
        'thread': {'id': 't1', 'turns': <dynamic>[]},
      });
      expect(controller.session.hydrated, isTrue);
    });

    test('markHydrated flips hydrated without any history', () {
      expect(controller.session.hydrated, isFalse);
      controller.markHydrated();
      expect(controller.session.hydrated, isTrue);
      expect(controller.session.items, isEmpty);
    });
  });
}
