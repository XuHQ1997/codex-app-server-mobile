/// Transcript grouping: collapses the intermediate work of each turn into a
/// single group so the transcript reads as a conversation — user messages and
/// the agent's final reply — with everything in between (tool calls, reasoning,
/// and the agent's interstitial "thinking out loud" text) tucked into one
/// foldable group.
///
/// Boundaries that always render standalone: user messages and plans. An
/// agent message is standalone only when it is the *final* message of a segment
/// (the turn's summary); earlier agent messages fold into the group as
/// intermediate notes.
///
/// The grouping is a pure function over the flat item list — it never mutates
/// items, it only decides which render individually vs. inside a group — which
/// keeps it easy to test and reason about.
library;

import '../../protocol/items/item.dart';

/// A rendered row in the transcript: either one standalone [ThreadItem] or a
/// group of intermediate steps.
sealed class TranscriptEntry {
  const TranscriptEntry();
}

/// A single item rendered on its own (user message, plan, or the final agent
/// message of a segment).
class ItemEntry extends TranscriptEntry {
  const ItemEntry(this.item);
  final ThreadItem item;
}

/// A folded run of a turn's intermediate items (steps + interstitial agent
/// notes).
class StepGroupEntry extends TranscriptEntry {
  StepGroupEntry(List<ThreadItem> items, {this.live = false})
      : items = List.unmodifiable(items),
        assert(items.isNotEmpty);

  final List<ThreadItem> items;

  /// True when this is the trailing group of an in-progress turn, i.e. the
  /// agent is actively producing these items. Drives the live scroll-window
  /// rendering (vs. the collapsed bar for finished groups).
  final bool live;

  /// Stable key derived from the first item's id, so the group keeps its
  /// expansion state across rebuilds even as later items stream in.
  String get id => 'group:${items.first.id}';

  /// Number of step-like actions (tools / reasoning), excluding any folded
  /// agent notes. Always >= 1 because a group always contains at least one step.
  int get stepCount => items.where(isStepItem).length;

  /// De-duplicated, order-preserving tool labels for the summary bar (step
  /// items only).
  List<String> get toolLabels {
    final seen = <String>{};
    final out = <String>[];
    for (final item in items) {
      if (!isStepItem(item)) continue;
      final label = stepLabel(item);
      if (seen.add(label)) out.add(label);
    }
    return out;
  }
}

/// Whether [item] is a step-like action (tool call, reasoning, search, …), as
/// opposed to a message or plan. Used for counting/labeling group contents.
bool isStepItem(ThreadItem item) => switch (item) {
      UserMessageItem _ => false,
      AgentMessageItem _ => false,
      PlanItem _ => false,
      _ => true,
    };

/// Items that always render standalone and never fold into a group.
bool _isBoundary(ThreadItem item) =>
    item is UserMessageItem || item is PlanItem;

/// A short category label for [item], used in the group summary bar.
String stepLabel(ThreadItem item) => switch (item) {
      CommandExecutionItem _ => 'shell',
      FileChangeItem _ => 'edit',
      WebSearchItem _ => 'search',
      ReasoningItem _ => 'thinking',
      McpToolCallItem i => i.tool.isNotEmpty ? i.tool : 'mcp',
      ReviewModeItem _ => 'review',
      ContextCompactionItem _ => 'compact',
      _ => 'step',
    };

/// Groups each turn's intermediate items into a [StepGroupEntry]; user
/// messages, plans, and the final agent message of each segment render as
/// standalone [ItemEntry]s.
///
/// When [turnRunning] is true, a group that reaches the end of the list with no
/// trailing agent summary is marked [StepGroupEntry.live] so the UI renders it
/// as a live scroll window; once the turn completes the next snapshot renders
/// it as a collapsed bar.
List<TranscriptEntry> buildTranscriptEntries(
  List<ThreadItem> items, {
  bool turnRunning = false,
}) {
  final entries = <TranscriptEntry>[];
  var i = 0;
  while (i < items.length) {
    final item = items[i];
    if (_isBoundary(item)) {
      entries.add(ItemEntry(item));
      i++;
      continue;
    }
    // Collect a content segment up to the next boundary (or the end). This may
    // include steps and any agent messages emitted while working.
    final start = i;
    while (i < items.length && !_isBoundary(items[i])) {
      i++;
    }
    final segment = items.sublist(start, i);
    final reachesEnd = i == items.length;

    // While a turn is running, keep its whole trailing segment inside the live
    // scroll window — including the agent text still being generated, which
    // isn't the final answer yet. Only once the turn finishes (or for earlier,
    // already-complete segments) do we peel the trailing agent messages out to
    // render the turn's final reply standalone.
    final isLiveSegment = reachesEnd && turnRunning;
    if (isLiveSegment) {
      entries.add(StepGroupEntry(segment, live: true));
      continue;
    }

    // Peel the trailing run of agent messages — the turn's final answer — so it
    // renders standalone. Everything before it folds into one group.
    var cut = segment.length;
    while (cut > 0 && segment[cut - 1] is AgentMessageItem) {
      cut--;
    }
    final grouped = segment.sublist(0, cut);
    final trailing = segment.sublist(cut);

    if (grouped.isNotEmpty) {
      entries.add(StepGroupEntry(grouped));
    }
    for (final t in trailing) {
      entries.add(ItemEntry(t));
    }
  }
  return entries;
}
