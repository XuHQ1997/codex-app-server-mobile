import 'package:codexcli_remote/protocol/approvals/approval_requests.dart';
import 'package:codexcli_remote/rpc/rpc_method_names.dart';
import 'package:codexcli_remote/rpc/server_request_router.dart';
import 'package:codexcli_remote/state/approval_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApprovalRequest.fromRequest (tool user input)', () {
    test('parses questions, options, isOther/isSecret and autoResolutionMs', () {
      final params = <String, dynamic>{
        'threadId': 't1',
        'turnId': 'turn1',
        'itemId': 'call1',
        'autoResolutionMs': 60000,
        'questions': [
          {
            'id': 'q1',
            'header': 'Pick one',
            'question': 'Choose an option.',
            'isOther': true,
            'isSecret': false,
            'options': [
              {'label': 'Option A', 'description': 'first'},
              {'label': 'Option B', 'description': 'second'},
            ],
          },
          {
            'id': 'q2',
            'header': 'Secret',
            'question': 'Enter a token.',
            'isSecret': true,
          },
        ],
      };

      final req = ApprovalRequest.fromRequest(
        ApprovalKind.toolUserInput,
        RpcMethods.rToolRequestUserInput,
        params,
      );

      expect(req.turnId, 'turn1');
      expect(req.autoResolutionMs, 60000);
      expect(req.questions, isNotNull);
      expect(req.questions!.length, 2);

      final q1 = req.questions![0];
      expect(q1.id, 'q1');
      expect(q1.header, 'Pick one');
      expect(q1.isOther, true);
      expect(q1.hasOptions, true);
      expect(q1.options!.map((o) => o.label), ['Option A', 'Option B']);

      final q2 = req.questions![1];
      expect(q2.isSecret, true);
      expect(q2.hasOptions, false);
      expect(q2.options, isNull);
    });
  });

  group('ApprovalController.respondUserInput', () {
    test('shapes answers into ToolRequestUserInputResponse', () async {
      final router = ServerRequestRouter();
      final controller = ApprovalController(router);

      final responseFuture = router.dispatch(
        RpcMethods.rToolRequestUserInput,
        {
          'turnId': 'turn1',
          'questions': [
            {'id': 'q1', 'header': 'h', 'question': 'q'},
          ],
        },
      );

      // The request is now enqueued and awaiting a decision.
      expect(controller.current, isNotNull);

      controller.respondUserInput({
        'q1': ['Option A', 'user_note: hello'],
        'q2': <String>[],
      });

      final result = await responseFuture;
      expect(result, {
        'answers': {
          'q1': {
            'answers': ['Option A', 'user_note: hello'],
          },
          'q2': {'answers': <String>[]},
        },
      });
      expect(controller.current, isNull);
    });

    test('cancelCurrent auto-resolves user input with empty answers', () async {
      final router = ServerRequestRouter();
      final controller = ApprovalController(router);

      final responseFuture = router.dispatch(
        RpcMethods.rToolRequestUserInput,
        {
          'turnId': 'turn1',
          'questions': [
            {'id': 'q1', 'header': 'h', 'question': 'q'},
          ],
        },
      );

      controller.cancelCurrent();

      final result = await responseFuture;
      expect(result, {'answers': <String, dynamic>{}});
    });

    test('cancelCurrent still sends decision:cancel for command approvals',
        () async {
      final router = ServerRequestRouter();
      final controller = ApprovalController(router);

      final responseFuture = router.dispatch(
        RpcMethods.rCommandExecutionApproval,
        {'turnId': 'turn1', 'command': 'ls'},
      );

      controller.cancelCurrent();

      final result = await responseFuture;
      expect(result, {'decision': 'cancel'});
    });
  });

  group('ApprovalRequest.fromRequest (availableDecisions)', () {
    test('keeps plain-string decisions', () {
      final req = ApprovalRequest.fromRequest(
        ApprovalKind.commandExecution,
        RpcMethods.rCommandExecutionApproval,
        {
          'turnId': 'turn1',
          'command': 'ls',
          'availableDecisions': ['accept', 'acceptForSession', 'decline'],
        },
      );
      expect(req.availableDecisions, ['accept', 'acceptForSession', 'decline']);
    });

    test('drops object-form decisions that would render as giant buttons', () {
      final req = ApprovalRequest.fromRequest(
        ApprovalKind.commandExecution,
        RpcMethods.rCommandExecutionApproval,
        {
          'turnId': 'turn1',
          'command': 'ls',
          'availableDecisions': [
            'accept',
            {
              'acceptWithExecpolicyAmendment': {'execpolicy_amendment': []},
            },
            'decline',
          ],
        },
      );
      expect(req.availableDecisions, ['accept', 'decline']);
    });

    test('null when no string decisions remain', () {
      final req = ApprovalRequest.fromRequest(
        ApprovalKind.commandExecution,
        RpcMethods.rCommandExecutionApproval,
        {
          'turnId': 'turn1',
          'command': 'ls',
          'availableDecisions': [
            {'applyNetworkPolicyAmendment': <String, dynamic>{}},
          ],
        },
      );
      expect(req.availableDecisions, isNull);
    });
  });
}
