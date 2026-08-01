// The private field names deliberately differ from the public constructor
// params, so initializing formals cannot be used here.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/logging.dart';
import '../data/codex_service.dart';
import '../protocol/items/item.dart';
import '../protocol/thread_settings.dart';
import '../protocol/turn.dart';
import '../rpc/rpc_client.dart';
import '../rpc/rpc_message.dart';
import '../rpc/rpc_method_names.dart';
import 'item_store.dart';

/// Aggregated, immutable snapshot the chat UI renders.
@immutable
class ThreadSession {
  const ThreadSession({
    required this.items,
    required this.turn,
    required this.plan,
    this.tokenUsage,
    this.settings,
    this.hydrated = false,
  });

  final List<ThreadItem> items;
  final TurnState turn;
  final List<PlanStep> plan;
  final TokenUsage? tokenUsage;

  /// Current thread settings (model / approval policy / effort / cwd / name),
  /// hydrated from `thread/resume` and kept current via `thread/settings/updated`.
  final ThreadSettings? settings;

  /// Whether the initial history load (`thread/resume`/`read`) has finished.
  /// The UI shows a loading state instead of the "empty" prompt until this is
  /// true, so a thread with history doesn't briefly flash "send a message".
  final bool hydrated;
}

/// Drives one thread's live state: subscribes to the RPC notification stream,
/// filters by threadId, applies deltas to an [ItemStore], and emits coalesced
/// snapshots so the UI rebuilds at most ~once per frame during streaming.
class ThreadSessionController extends ChangeNotifier {
  ThreadSessionController({
    required this.threadId,
    required RpcClient client,
    required CodexService service,
  })  : _client = client,
        _service = service {
    _subscribe();
  }

  final String threadId;
  final RpcClient _client;
  final CodexService _service;
  final _log = appLogger('ThreadSession');

  final ItemStore _store = ItemStore();
  TurnState _turn = const TurnState();
  List<PlanStep> _plan = const [];
  TokenUsage? _tokenUsage;
  ThreadSettings? _settings;
  bool _hydrated = false;

  StreamSubscription<InboundMessage>? _sub;
  bool _dirty = false;
  bool _flushScheduled = false;

  ThreadSession get session => ThreadSession(
        items: _store.items,
        turn: _turn,
        plan: _plan,
        tokenUsage: _tokenUsage,
        settings: _settings,
        hydrated: _hydrated,
      );

  /// Whether any thread items are currently loaded. The resume flow uses this
  /// to decide whether a `thread/read` fallback is needed (resume can return
  /// turns whose `items` weren't loaded — `itemsView: notLoaded`).
  bool get hasItems => !_store.isEmpty;

  void _subscribe() {
    _sub = _client.notifications.listen(_onMessage);
  }

  /// Loads history into the store (from a `thread/resume` or `thread/read`
  /// result). Idempotent: items are keyed by id.
  void hydrateFromThread(Map<String, dynamic> threadResult) {
    // `thread/resume` carries settings (model/approvalPolicy/reasoningEffort/
    // cwd) at the top level and the name under `thread`. `thread/read` omits
    // them, leaving the previous (or null) settings in place.
    final parsed = ThreadSettings.fromMap(threadResult);
    if (parsed.model != null ||
        parsed.approvalPolicy != null ||
        parsed.effort != null ||
        parsed.cwd != null ||
        parsed.name != null) {
      _settings = parsed;
    }
    final thread = threadResult['thread'];
    final turns = thread is Map<String, dynamic> ? thread['turns'] : null;
    if (turns is List) {
      for (final turn in turns) {
        if (turn is Map<String, dynamic>) {
          final items = turn['items'];
          if (items is List) {
            for (final item in items) {
              if (item is Map<String, dynamic>) {
                _store.upsert(ThreadItem.fromJson(item));
              }
            }
          }
        }
      }
      // Restore turn lifecycle from the last turn so a thread that's still
      // running (e.g. we left the chat mid-turn) comes back showing the
      // interrupt button and lets `interruptTurn` target the live turn — and
      // so a completed turn doesn't read as idle. Only overwrite when the
      // resume actually reports a turn, so we don't clobber live state that
      // arrived via notifications before hydration completed.
      final lastTurn = turns.whereType<Map<String, dynamic>>().lastOrNull;
      if (lastTurn != null) {
        final status = lastTurn['status'] as String?;
        final turnId = lastTurn['id'] as String?;
        if (status != null) {
          final error = lastTurn['error'] is Map
              ? (lastTurn['error'] as Map)['message'] as String?
              : null;
          _turn = TurnState(turnId: turnId, status: status, error: error);
        }
      }
    }
    _hydrated = true;
    _markDirty();
  }

  /// Marks hydration complete without any history (e.g. resume + read both
  /// failed), so the UI stops showing the loading state.
  void markHydrated() {
    if (_hydrated) return;
    _hydrated = true;
    _markDirty();
  }

  void _onMessage(InboundMessage msg) {
    final method = msg.method;
    final params = msg.params;
    if (method == null || params == null) return;
    // Filter to this thread where a threadId is present.
    final tid = params['threadId'] as String?;
    if (tid != null && tid != threadId) return;

    switch (method) {
      case RpcMethods.nItemStarted:
        final item = params['item'];
        if (item is Map<String, dynamic>) _store.onItemStarted(item);
      case RpcMethods.nItemCompleted:
        final item = params['item'];
        if (item is Map<String, dynamic>) _store.onItemCompleted(item);
      case RpcMethods.nItemAgentMessageDelta:
        _store.onAgentMessageDelta(
          params['itemId'] as String? ?? '',
          params['delta'] as String? ?? '',
        );
      case RpcMethods.nItemReasoningSummaryTextDelta:
        _store.onReasoningSummaryDelta(
          params['itemId'] as String? ?? '',
          (params['summaryIndex'] as num?)?.toInt() ?? 0,
          params['delta'] as String? ?? '',
        );
      case RpcMethods.nItemReasoningSummaryPartAdded:
        _store.onReasoningSummaryPartAdded(params['itemId'] as String? ?? '');
      case RpcMethods.nItemReasoningTextDelta:
        _store.onReasoningTextDelta(
          params['itemId'] as String? ?? '',
          (params['contentIndex'] as num?)?.toInt() ?? 0,
          params['delta'] as String? ?? '',
        );
      case RpcMethods.nItemCommandOutputDelta:
        _store.onCommandOutputDelta(
          params['itemId'] as String? ?? '',
          params['delta'] as String? ?? '',
        );
      case RpcMethods.nItemFileChangePatchUpdated:
        final changes = params['changes'];
        if (changes is List) {
          _store.onFileChangePatchUpdated(
            params['itemId'] as String? ?? '',
            changes,
          );
        }
      case RpcMethods.nTurnStarted:
        final turn = params['turn'];
        final turnId = turn is Map<String, dynamic> ? turn['id'] as String? : null;
        _turn = TurnState(turnId: turnId, status: 'inProgress');
      case RpcMethods.nTurnCompleted:
        final turn = params['turn'];
        final status =
            turn is Map<String, dynamic> ? turn['status'] as String? : null;
        final error = turn is Map<String, dynamic> && turn['error'] is Map
            ? (turn['error'] as Map)['message'] as String?
            : null;
        _turn = _turn.copyWith(status: status ?? 'completed', error: error);
      case RpcMethods.nTurnPlanUpdated:
        final plan = params['plan'];
        if (plan is List) {
          _plan = plan
              .whereType<Map<String, dynamic>>()
              .map(PlanStep.fromJson)
              .toList();
        }
      case RpcMethods.nTokenUsageUpdated:
        _tokenUsage = TokenUsage.fromJson(params);
      case RpcMethods.nThreadSettingsUpdated:
        final settings = params['settings'];
        final source = settings is Map<String, dynamic> ? settings : params;
        _settings = (_settings ?? const ThreadSettings()).copyWith(
          model: source['model'] as String?,
          approvalPolicy: ApprovalPolicy.fromWire(source['approvalPolicy']),
          effort: ReasoningEffort.fromWire(
            source['effort'] ?? source['reasoningEffort'],
          ),
          cwd: source['cwd'] as String?,
        );
      case RpcMethods.nError:
        final err = params['error'];
        final message = err is Map ? err['message'] as String? : null;
        final willRetry = params['willRetry'] as bool? ?? false;
        if (!willRetry) {
          _turn = _turn.copyWith(status: 'failed', error: message);
        }
        _log.warning('Turn error: $message (willRetry=$willRetry)');
      default:
        return; // ignore unrelated notifications
    }
    _markDirty();
  }

  /// Coalesce rapid delta updates into at most one notify per frame.
  void _markDirty() {
    _dirty = true;
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _flushScheduled = false;
    if (!_dirty) return;
    _dirty = false;
    notifyListeners();
  }

  Future<void> interruptTurn() async {
    final turnId = _turn.turnId;
    if (turnId == null) return;
    await _service.interruptTurn(threadId, turnId);
  }

  /// Optimistically reflects a settings change locally (e.g. right after a
  /// successful `thread/settings/update`), so the AppBar updates without
  /// waiting for the `thread/settings/updated` notification.
  void applySettings({
    String? model,
    ApprovalPolicy? approvalPolicy,
    ReasoningEffort? effort,
  }) {
    _settings = (_settings ?? const ThreadSettings()).copyWith(
      model: model,
      approvalPolicy: approvalPolicy,
      effort: effort,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
