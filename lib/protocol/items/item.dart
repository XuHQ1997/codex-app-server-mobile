/// Thread items — the units rendered in the chat transcript.
///
/// Discriminated by a camelCase `type` string. Unknown types fall back to
/// [UnknownItem] so new server variants never crash the UI.
///
/// Items that receive streaming deltas keep mutable buffers so high-frequency
/// updates are cheap; [ThreadSessionController] materializes immutable snapshots
/// for the UI.
library;

/// Base for all thread items. Every item has a stable [id] matching the
/// `itemId` used by delta notifications.
abstract class ThreadItem {
  ThreadItem(this.id);

  final String id;

  /// The raw `type` discriminator, for debugging / unknown items.
  String get type;

  /// Parses a `ThreadItem` from an `item` JSON object.
  static ThreadItem fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final type = json['type'] as String? ?? 'unknown';
    switch (type) {
      case 'userMessage':
        return UserMessageItem.fromJson(id, json);
      case 'agentMessage':
        return AgentMessageItem.fromJson(id, json);
      case 'reasoning':
        return ReasoningItem.fromJson(id, json);
      case 'commandExecution':
        return CommandExecutionItem.fromJson(id, json);
      case 'fileChange':
        return FileChangeItem.fromJson(id, json);
      case 'mcpToolCall':
        return McpToolCallItem.fromJson(id, json);
      case 'webSearch':
        return WebSearchItem.fromJson(id, json);
      case 'plan':
        return PlanItem.fromJson(id, json);
      case 'enteredReviewMode':
        return ReviewModeItem(id, entered: true, review: json['review'] as String?);
      case 'exitedReviewMode':
        return ReviewModeItem(id, entered: false, review: json['review'] as String?);
      case 'contextCompaction':
        return ContextCompactionItem(id);
      default:
        return UnknownItem(id, type, json);
    }
  }
}

/// A user message item (echoed back by the server).
class UserMessageItem extends ThreadItem {
  UserMessageItem(super.id, {required this.text, this.clientId});

  final String text;
  final String? clientId;

  @override
  String get type => 'userMessage';

  factory UserMessageItem.fromJson(String id, Map<String, dynamic> json) {
    // `content` is a list of user inputs; extract concatenated text.
    final buf = StringBuffer();
    final content = json['content'];
    if (content is List) {
      for (final c in content) {
        if (c is Map && c['type'] == 'text' && c['text'] is String) {
          buf.write(c['text'] as String);
        }
      }
    }
    return UserMessageItem(
      id,
      text: buf.toString(),
      clientId: json['clientId'] as String?,
    );
  }
}

/// The main assistant message bubble (markdown).
class AgentMessageItem extends ThreadItem {
  AgentMessageItem(super.id, {String text = ''}) : _buffer = StringBuffer(text);

  final StringBuffer _buffer;

  String get text => _buffer.toString();

  void appendDelta(String delta) => _buffer.write(delta);

  @override
  String get type => 'agentMessage';

  factory AgentMessageItem.fromJson(String id, Map<String, dynamic> json) =>
      AgentMessageItem(id, text: json['text'] as String? ?? '');
}

/// Chain-of-thought reasoning: streamed summaries and raw content blocks.
class ReasoningItem extends ThreadItem {
  ReasoningItem(super.id, {List<String>? summary, List<String>? content})
    : summary = summary ?? <String>[],
      content = content ?? <String>[];

  final List<String> summary;
  final List<String> content;

  void appendSummaryDelta(int index, String delta) {
    while (summary.length <= index) {
      summary.add('');
    }
    summary[index] = summary[index] + delta;
  }

  void addSummaryPart() => summary.add('');

  void appendContentDelta(int index, String delta) {
    while (content.length <= index) {
      content.add('');
    }
    content[index] = content[index] + delta;
  }

  @override
  String get type => 'reasoning';

  factory ReasoningItem.fromJson(String id, Map<String, dynamic> json) =>
      ReasoningItem(
        id,
        summary: _stringList(json['summary']),
        content: _stringList(json['content']),
      );
}

/// A shell command execution with streamed output.
class CommandExecutionItem extends ThreadItem {
  CommandExecutionItem(
    super.id, {
    required this.command,
    this.cwd,
    this.status = 'inProgress',
    String output = '',
    this.exitCode,
    this.durationMs,
  }) : _output = StringBuffer(output);

  final String command;
  final String? cwd;
  String status;
  final StringBuffer _output;
  int? exitCode;
  int? durationMs;

  String get output => _output.toString();

  void appendOutputDelta(String delta) => _output.write(delta);

  @override
  String get type => 'commandExecution';

  factory CommandExecutionItem.fromJson(String id, Map<String, dynamic> json) =>
      CommandExecutionItem(
        id,
        command: json['command'] as String? ?? '',
        cwd: json['cwd'] as String?,
        status: json['status'] as String? ?? 'inProgress',
        output: json['aggregatedOutput'] as String? ?? '',
        exitCode: (json['exitCode'] as num?)?.toInt(),
        durationMs: (json['durationMs'] as num?)?.toInt(),
      );
}

/// A single file change within a [FileChangeItem].
class FileUpdateChange {
  FileUpdateChange({required this.path, required this.kind, required this.diff});

  final String path;

  /// `add`, `delete`, or `update`.
  final String kind;

  /// Unified diff for this file.
  final String diff;

  factory FileUpdateChange.fromJson(Map<String, dynamic> json) {
    var kind = 'update';
    final rawKind = json['kind'];
    if (rawKind is String) {
      kind = rawKind;
    } else if (rawKind is Map && rawKind.isNotEmpty) {
      kind = rawKind.keys.first.toString();
    }
    return FileUpdateChange(
      path: json['path'] as String? ?? '',
      kind: kind,
      diff: json['diff'] as String? ?? '',
    );
  }
}

/// A proposed / applied patch across one or more files.
class FileChangeItem extends ThreadItem {
  FileChangeItem(super.id, {required this.changes, this.status = 'inProgress'});

  List<FileUpdateChange> changes;
  String status;

  @override
  String get type => 'fileChange';

  factory FileChangeItem.fromJson(String id, Map<String, dynamic> json) =>
      FileChangeItem(
        id,
        changes: _changeList(json['changes']),
        status: json['status'] as String? ?? 'inProgress',
      );

  static List<FileUpdateChange> _changeList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(FileUpdateChange.fromJson)
        .toList();
  }
}

/// An MCP tool call.
class McpToolCallItem extends ThreadItem {
  McpToolCallItem(
    super.id, {
    required this.server,
    required this.tool,
    this.status = 'inProgress',
    this.arguments,
  });

  final String server;
  final String tool;
  String status;
  final Object? arguments;

  @override
  String get type => 'mcpToolCall';

  factory McpToolCallItem.fromJson(String id, Map<String, dynamic> json) =>
      McpToolCallItem(
        id,
        server: json['server'] as String? ?? '',
        tool: json['tool'] as String? ?? '',
        status: json['status'] as String? ?? 'inProgress',
        arguments: json['arguments'],
      );
}

/// A web search issued by the agent.
class WebSearchItem extends ThreadItem {
  WebSearchItem(super.id, {required this.query});
  final String query;

  @override
  String get type => 'webSearch';

  factory WebSearchItem.fromJson(String id, Map<String, dynamic> json) =>
      WebSearchItem(id, query: json['query'] as String? ?? '');
}

/// A proposed plan (plan mode). Built from a complete `item/started` /
/// `item/completed` payload; plan text is not streamed incrementally.
class PlanItem extends ThreadItem {
  PlanItem(super.id, {this.text = ''});

  final String text;

  @override
  String get type => 'plan';

  factory PlanItem.fromJson(String id, Map<String, dynamic> json) =>
      PlanItem(id, text: json['text'] as String? ?? '');
}

/// Entered / exited review mode marker.
class ReviewModeItem extends ThreadItem {
  ReviewModeItem(super.id, {required this.entered, this.review});
  final bool entered;
  final String? review;

  @override
  String get type => entered ? 'enteredReviewMode' : 'exitedReviewMode';
}

/// A context compaction marker.
class ContextCompactionItem extends ThreadItem {
  ContextCompactionItem(super.id);

  @override
  String get type => 'contextCompaction';
}

/// Fallback for any item type this client doesn't model yet.
class UnknownItem extends ThreadItem {
  UnknownItem(super.id, this._type, this.raw);
  final String _type;
  final Map<String, dynamic> raw;

  @override
  String get type => _type;
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return <String>[];
  return raw.map((e) => e?.toString() ?? '').toList();
}
