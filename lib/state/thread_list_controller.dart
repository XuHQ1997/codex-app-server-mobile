import 'package:flutter/foundation.dart';

import '../data/codex_service.dart';
import '../protocol/thread.dart';

/// Paginated thread list state.
class ThreadListController extends ChangeNotifier {
  ThreadListController(this._service);

  final CodexService _service;

  final List<ThreadSummary> _threads = [];
  String? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  List<ThreadSummary> get threads => List.unmodifiable(_threads);
  bool get loading => _loading;
  bool get hasMore => _hasMore;
  String? get error => _error;

  Future<void> refresh() async {
    _threads.clear();
    _cursor = null;
    _hasMore = true;
    _error = null;
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    notifyListeners();
    try {
      final page = await _service.listThreads(cursor: _cursor);
      _threads.addAll(page.threads);
      _sortByRecency();
      _cursor = page.nextCursor;
      _hasMore = page.nextCursor != null && page.threads.isNotEmpty;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Orders threads by most-recent activity first. Threads without a known
  /// timestamp sort to the end, keeping their relative order stable.
  void _sortByRecency() {
    _threads.sort((a, b) {
      final at = a.updatedAtMs;
      final bt = b.updatedAtMs;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
  }

  Future<void> archive(String threadId) async {
    await _service.archiveThread(threadId);
    _threads.removeWhere((t) => t.id == threadId);
    notifyListeners();
  }

  Future<void> delete(String threadId) async {
    await _service.deleteThread(threadId);
    _threads.removeWhere((t) => t.id == threadId);
    notifyListeners();
  }
}
