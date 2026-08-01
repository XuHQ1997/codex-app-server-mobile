import '../protocol/items/item.dart';

/// An ordered store of thread items keyed by item id, with efficient in-place
/// delta application.
///
/// Streaming delta application is idempotent w.r.t. `item/completed`: a
/// completed item overwrites any partial streaming state, so replayed history
/// (after `thread/resume`) reconciles cleanly with in-flight deltas.
class ItemStore {
  final Map<String, ThreadItem> _byId = {};
  final List<String> _order = [];

  /// Snapshot of items in insertion order.
  List<ThreadItem> get items =>
      List.unmodifiable(_order.map((id) => _byId[id]!));

  bool get isEmpty => _order.isEmpty;

  void clear() {
    _byId.clear();
    _order.clear();
  }

  ThreadItem? byId(String id) => _byId[id];

  /// Inserts or replaces an item, preserving first-seen order.
  void upsert(ThreadItem item) {
    if (!_byId.containsKey(item.id)) {
      _order.add(item.id);
    }
    _byId[item.id] = item;
  }

  /// Applies `item/started`: insert the full item.
  void onItemStarted(Map<String, dynamic> item) {
    upsert(ThreadItem.fromJson(item));
  }

  /// Applies `item/completed`: replace with the authoritative final item.
  void onItemCompleted(Map<String, dynamic> item) {
    upsert(ThreadItem.fromJson(item));
  }

  /// Ensures an item of the given builder exists; used when a delta arrives
  /// before `item/started`.
  T _ensure<T extends ThreadItem>(String id, T Function() create) {
    final existing = _byId[id];
    if (existing is T) return existing;
    final created = create();
    upsert(created);
    return created;
  }

  void onAgentMessageDelta(String itemId, String delta) {
    _ensure<AgentMessageItem>(itemId, () => AgentMessageItem(itemId))
        .appendDelta(delta);
  }

  void onReasoningSummaryDelta(String itemId, int summaryIndex, String delta) {
    _ensure<ReasoningItem>(itemId, () => ReasoningItem(itemId))
        .appendSummaryDelta(summaryIndex, delta);
  }

  void onReasoningSummaryPartAdded(String itemId) {
    _ensure<ReasoningItem>(itemId, () => ReasoningItem(itemId)).addSummaryPart();
  }

  void onReasoningTextDelta(String itemId, int contentIndex, String delta) {
    _ensure<ReasoningItem>(itemId, () => ReasoningItem(itemId))
        .appendContentDelta(contentIndex, delta);
  }

  void onCommandOutputDelta(String itemId, String delta) {
    _ensure<CommandExecutionItem>(
      itemId,
      () => CommandExecutionItem(itemId, command: ''),
    ).appendOutputDelta(delta);
  }

  void onFileChangePatchUpdated(String itemId, List<dynamic> changes) {
    final item = _ensure<FileChangeItem>(
      itemId,
      () => FileChangeItem(itemId, changes: const []),
    );
    item.changes = changes
        .whereType<Map<String, dynamic>>()
        .map(FileUpdateChange.fromJson)
        .toList();
  }
}
