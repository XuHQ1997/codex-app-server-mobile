import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/logging.dart';
import '../protocol/approvals/approval_requests.dart';
import '../rpc/rpc_method_names.dart';
import '../rpc/server_request_router.dart';

/// A pending approval awaiting a user decision, with a completer the UI
/// resolves.
class PendingApproval {
  PendingApproval(this.request, this._completer);

  final ApprovalRequest request;
  final Completer<Map<String, dynamic>> _completer;

  bool get isResolved => _completer.isCompleted;

  void resolve(Map<String, dynamic> result) {
    if (!_completer.isCompleted) _completer.complete(result);
  }
}

/// Registers approval handlers on the [ServerRequestRouter] and exposes a queue
/// of pending approvals for the UI to present sequentially.
///
/// Each incoming approval request blocks (awaits a completer) until the user
/// picks a decision; the router then sends exactly one response.
class ApprovalController extends ChangeNotifier {
  ApprovalController(this._router) {
    _register();
  }

  final ServerRequestRouter _router;
  final _log = appLogger('ApprovalController');
  final List<PendingApproval> _queue = [];

  /// The approval currently shown to the user (head of the queue).
  PendingApproval? get current => _queue.isEmpty ? null : _queue.first;

  int get pendingCount => _queue.length;

  void _register() {
    _router.register(
      RpcMethods.rCommandExecutionApproval,
      (params) => _enqueue(ApprovalKind.commandExecution,
          RpcMethods.rCommandExecutionApproval, params),
    );
    _router.register(
      RpcMethods.rFileChangeApproval,
      (params) => _enqueue(
          ApprovalKind.fileChange, RpcMethods.rFileChangeApproval, params),
    );
    _router.register(
      RpcMethods.rPermissionsApproval,
      (params) => _enqueue(
          ApprovalKind.permissions, RpcMethods.rPermissionsApproval, params),
    );
    _router.register(
      RpcMethods.rToolRequestUserInput,
      (params) => _enqueue(
          ApprovalKind.toolUserInput, RpcMethods.rToolRequestUserInput, params),
    );
  }

  Future<Map<String, dynamic>> _enqueue(
    ApprovalKind kind,
    String method,
    Map<String, dynamic> params,
  ) {
    final request = ApprovalRequest.fromRequest(kind, method, params);
    final completer = Completer<Map<String, dynamic>>();
    final pending = PendingApproval(request, completer);
    _queue.add(pending);
    _log.info('Enqueued approval: $method (queue=${_queue.length})');
    notifyListeners();
    return completer.future.whenComplete(() {
      _queue.remove(pending);
      notifyListeners();
    });
  }

  /// Responds to the current command/file-change approval with a decision.
  void respondDecision(String decision) {
    final pending = current;
    if (pending == null) return;
    pending.resolve({'decision': decision});
  }

  /// Responds to a permissions approval with a granted subset and scope.
  void respondPermissions(Map<String, dynamic> permissions, String scope) {
    final pending = current;
    if (pending == null) return;
    pending.resolve({'permissions': permissions, 'scope': scope});
  }

  /// Responds to a tool user-input request. [answers] maps each question id to
  /// its ordered answer strings (selected option label(s) and/or a
  /// `user_note:`-prefixed free-text entry). Shapes the payload as the
  /// `ToolRequestUserInputResponse` the server expects.
  void respondUserInput(Map<String, List<String>> answers) {
    final pending = current;
    if (pending == null) return;
    pending.resolve({
      'answers': {
        for (final entry in answers.entries)
          entry.key: {'answers': entry.value},
      },
    });
  }

  /// Rejects the current approval (used when the transport drops).
  void cancelCurrent() {
    final pending = current;
    if (pending == null) return;
    // Tool user-input requests have no "decision"; auto-resolve them with an
    // empty answer set (matching the CLI's interrupt / auto-resolution path).
    if (pending.request.kind == ApprovalKind.toolUserInput) {
      pending.resolve({'answers': <String, dynamic>{}});
      return;
    }
    pending.resolve({'decision': 'cancel'});
  }
}
