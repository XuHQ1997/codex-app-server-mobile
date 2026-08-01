/// Turn / plan / token-usage models.
library;

/// A single plan (todo) step from `turn/plan/updated`.
class PlanStep {
  PlanStep({required this.step, required this.status});

  final String step;

  /// `pending`, `inProgress`, or `completed`.
  final String status;

  factory PlanStep.fromJson(Map<String, dynamic> json) => PlanStep(
    step: json['step'] as String? ?? '',
    status: json['status'] as String? ?? 'pending',
  );
}

/// Token usage snapshot from `thread/tokenUsage/updated`.
///
/// The payload carries two breakdowns plus the window size:
///   `tokenUsage.last`  — the most recent turn's usage; its `totalTokens` is
///                        the CURRENT active context size (resets after a
///                        compaction), so it drives the context-usage bar.
///   `tokenUsage.total` — cumulative usage across the whole thread; grows
///                        monotonically and is shown only as a session total.
///   `tokenUsage.modelContextWindow` — the model's context window (nullable).
///
/// The context-percent math mirrors codex's `percent_of_context_window_remaining`
/// (protocol.rs): a fixed [baselineTokens] (system prompt, tools, and headroom
/// to run compact) is subtracted from both the used tokens and the window
/// before computing the fraction, so a fresh thread reads ~0% used.
class TokenUsage {
  TokenUsage({
    this.contextTokens = 0,
    this.inputTokens = 0,
    this.cachedInputTokens = 0,
    this.outputTokens = 0,
    this.reasoningOutputTokens = 0,
    this.sessionTotalTokens = 0,
    this.contextWindow,
  });

  /// Tokens occupying the context window right now (`last.totalTokens`).
  final int contextTokens;
  final int inputTokens;
  final int cachedInputTokens;
  final int outputTokens;
  final int reasoningOutputTokens;

  /// Cumulative tokens across the whole thread (`total.totalTokens`).
  final int sessionTotalTokens;

  /// The model's context window size in tokens, when known.
  final int? contextWindow;

  /// Baseline tokens always present in context (prompt, tools, compact
  /// headroom). Matches codex's `BASELINE_TOKENS`.
  static const int baselineTokens = 12000;

  /// Percent of the (baseline-adjusted) context window still free, 0..100, or
  /// null when the window size is unknown.
  int? get contextRemainingPercent {
    final window = contextWindow;
    if (window == null) return null;
    if (window <= baselineTokens) return 0;
    final effective = window - baselineTokens;
    final used = (contextTokens - baselineTokens).clamp(0, effective);
    final remaining = effective - used;
    return (remaining / effective * 100).clamp(0.0, 100.0).round();
  }

  /// Percent of the context window used, 0..100, or null when unknown.
  int? get contextUsedPercent {
    final remaining = contextRemainingPercent;
    return remaining == null ? null : 100 - remaining;
  }

  /// Fraction of the context window used (0..1) for the progress bar, or null
  /// when the window size is unknown.
  double? get contextFraction {
    final used = contextUsedPercent;
    return used == null ? null : used / 100.0;
  }

  /// Parses either the nested `thread/tokenUsage/updated` params
  /// (`{tokenUsage: {last: {...}, total: {...}, modelContextWindow}}`) or a
  /// flat breakdown (older/simpler payloads).
  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    final usage = json['tokenUsage'];
    if (usage is Map<String, dynamic>) {
      // Prefer `last` for the active context; fall back to `total` then the
      // usage object itself if a build omits the breakdowns.
      final last = usage['last'];
      final total = usage['total'];
      final lastMap = last is Map<String, dynamic> ? last : null;
      final totalMap = total is Map<String, dynamic> ? total : null;
      final breakdown = lastMap ?? totalMap ?? usage;
      return TokenUsage._fromBreakdown(
        breakdown,
        sessionTotalTokens:
            (totalMap?['totalTokens'] as num?)?.toInt() ?? 0,
        contextWindow: (usage['modelContextWindow'] as num?)?.toInt(),
      );
    }
    final flatTotal = (json['totalTokens'] as num?)?.toInt() ?? 0;
    return TokenUsage._fromBreakdown(
      json,
      sessionTotalTokens: flatTotal,
      contextWindow: (json['modelContextWindow'] as num?)?.toInt(),
    );
  }

  factory TokenUsage._fromBreakdown(
    Map<String, dynamic> json, {
    required int sessionTotalTokens,
    int? contextWindow,
  }) =>
      TokenUsage(
        contextTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
        inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
        cachedInputTokens: (json['cachedInputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
        reasoningOutputTokens:
            (json['reasoningOutputTokens'] as num?)?.toInt() ?? 0,
        sessionTotalTokens: sessionTotalTokens,
        contextWindow: contextWindow,
      );
}

/// Lightweight view of the current turn's lifecycle state.
class TurnState {
  const TurnState({this.turnId, this.status = 'idle', this.error});

  final String? turnId;

  /// `idle`, `inProgress`, `completed`, `interrupted`, or `failed`.
  final String status;
  final String? error;

  bool get isRunning => status == 'inProgress';

  TurnState copyWith({String? turnId, String? status, String? error}) =>
      TurnState(
        turnId: turnId ?? this.turnId,
        status: status ?? this.status,
        error: error,
      );
}
