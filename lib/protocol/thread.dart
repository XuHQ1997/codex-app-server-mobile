/// Thread summary/detail models returned by thread/* methods.
library;

class ThreadSummary {
  ThreadSummary({
    required this.id,
    this.name,
    this.status = 'notLoaded',
    this.cwd,
    this.updatedAtMs,
    this.preview,
  });

  final String id;
  final String? name;
  final String status;
  final String? cwd;
  final int? updatedAtMs;
  final String? preview;

  factory ThreadSummary.fromJson(Map<String, dynamic> json) => ThreadSummary(
    id: json['id'] as String? ?? '',
    name: json['name'] as String?,
    status: _parseStatus(json['status']),
    cwd: json['cwd'] as String?,
    updatedAtMs: _parseTimestampMs(json),
    preview: json['preview'] as String?,
  );

  /// `status` is a tagged union in the schema: either the plain tag or an
  /// object like `{"type": "active", "activeFlags": [...]}`. Older/loose
  /// payloads may also send a bare string. Normalize all forms to the tag.
  static String _parseStatus(Object? raw) {
    if (raw is String) return raw;
    if (raw is Map) {
      final type = raw['type'];
      if (type is String) return type;
    }
    return 'notLoaded';
  }

  /// The schema exposes `updatedAt` / `recencyAt` / `createdAt` in SECONDS.
  /// Some builds may send `updatedAtMs`. Normalize to milliseconds.
  static int? _parseTimestampMs(Map<String, dynamic> json) {
    final ms = (json['updatedAtMs'] as num?)?.toInt();
    if (ms != null) return ms;
    final seconds = (json['recencyAt'] as num?)?.toInt() ??
        (json['updatedAt'] as num?)?.toInt() ??
        (json['createdAt'] as num?)?.toInt();
    return seconds != null ? seconds * 1000 : null;
  }

  /// True when the thread is actively running (any `active` status).
  bool get isActive => status == 'active';

  String get displayName {
    if (name != null && name!.trim().isNotEmpty) return name!;
    if (preview != null && preview!.trim().isNotEmpty) {
      final p = preview!.trim();
      return p.length > 60 ? '${p.substring(0, 60)}…' : p;
    }
    return id;
  }
}

/// A page of threads from `thread/list`.
class ThreadListPage {
  ThreadListPage({required this.threads, this.nextCursor});

  final List<ThreadSummary> threads;
  final String? nextCursor;

  factory ThreadListPage.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final threads = <ThreadSummary>[];
    if (data is List) {
      for (final t in data) {
        if (t is Map<String, dynamic>) {
          // Entries may wrap the thread under a `thread` key or be flat.
          final threadJson = t['thread'] is Map<String, dynamic>
              ? t['thread'] as Map<String, dynamic>
              : t;
          threads.add(ThreadSummary.fromJson(threadJson));
        }
      }
    }
    return ThreadListPage(
      threads: threads,
      nextCursor: json['nextCursor'] as String?,
    );
  }
}
