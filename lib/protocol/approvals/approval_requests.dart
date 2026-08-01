/// Approval / permission request models (server -> client requests) and the
/// decision responses the client sends back.
library;

/// The kind of approval being requested.
enum ApprovalKind { commandExecution, fileChange, permissions, toolUserInput }

/// A single selectable option for a [UserInputQuestion].
class UserInputOption {
  const UserInputOption({required this.label, required this.description});

  final String label;
  final String description;

  factory UserInputOption.fromJson(Map<String, dynamic> json) {
    return UserInputOption(
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

/// One question in a `item/tool/requestUserInput` request. A question may have
/// selectable [options], be free-text only (options null/empty), or both.
class UserInputQuestion {
  const UserInputQuestion({
    required this.id,
    required this.header,
    required this.question,
    this.isOther = false,
    this.isSecret = false,
    this.options,
  });

  final String id;
  final String header;
  final String question;

  /// When true, an extra "None of the above" option is offered after [options].
  final bool isOther;

  /// When true, free-text input for this question should be masked.
  final bool isSecret;

  /// Selectable options, or null/empty for a free-text-only question.
  final List<UserInputOption>? options;

  bool get hasOptions => options != null && options!.isNotEmpty;

  factory UserInputQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    return UserInputQuestion(
      id: json['id'] as String? ?? '',
      header: json['header'] as String? ?? '',
      question: json['question'] as String? ?? '',
      isOther: json['isOther'] as bool? ?? false,
      isSecret: json['isSecret'] as bool? ?? false,
      options: rawOptions is List
          ? rawOptions
              .whereType<Map<String, dynamic>>()
              .map(UserInputOption.fromJson)
              .toList()
          : null,
    );
  }
}

/// A parsed approval request awaiting a user decision.
class ApprovalRequest {
  ApprovalRequest({
    required this.kind,
    required this.method,
    required this.params,
    this.threadId,
    this.turnId,
    this.itemId,
    this.reason,
    this.command,
    this.cwd,
    this.changes,
    this.availableDecisions,
    this.questions,
    this.autoResolutionMs,
  });

  final ApprovalKind kind;
  final String method;
  final Map<String, dynamic> params;
  final String? threadId;
  final String? turnId;
  final String? itemId;
  final String? reason;

  /// For command execution approvals.
  final String? command;
  final String? cwd;

  /// For file change approvals: the proposed changes as raw maps.
  final List<Map<String, dynamic>>? changes;

  /// Ordered list of allowed decisions to present (when the server provides it).
  final List<String>? availableDecisions;

  /// For tool user-input requests: the questions to answer.
  final List<UserInputQuestion>? questions;

  /// For tool user-input requests: if set, the request auto-resolves with empty
  /// answers after this many milliseconds.
  final int? autoResolutionMs;

  factory ApprovalRequest.fromRequest(
    ApprovalKind kind,
    String method,
    Map<String, dynamic> params,
  ) {
    return ApprovalRequest(
      kind: kind,
      method: method,
      params: params,
      threadId: params['threadId'] as String?,
      turnId: params['turnId'] as String?,
      itemId: params['itemId'] as String?,
      reason: params['reason'] as String?,
      command: _commandString(params['command']),
      cwd: params['cwd'] as String?,
      changes: _changes(params),
      availableDecisions: _decisions(params['availableDecisions']),
      questions: _questions(params),
      autoResolutionMs: (params['autoResolutionMs'] as num?)?.toInt(),
    );
  }

  static String? _commandString(Object? raw) {
    if (raw is String) return raw;
    if (raw is List) return raw.map((e) => e.toString()).join(' ');
    return null;
  }

  static List<Map<String, dynamic>>? _changes(Map<String, dynamic> params) {
    final raw = params['changes'];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().toList();
    }
    return null;
  }

  /// Parses `availableDecisions`, keeping only the plain-string variants
  /// (`accept`, `acceptForSession`, `decline`, `cancel`). The server may also
  /// send object-form decisions (e.g. `{acceptWithExecpolicyAmendment: {...}}`)
  /// which this client can't act on — including them would render a giant,
  /// unreadable button from the raw object, so they're dropped.
  static List<String>? _decisions(Object? raw) {
    if (raw is! List) return null;
    final strings = raw.whereType<String>().toList();
    return strings.isEmpty ? null : strings;
  }

  static List<UserInputQuestion>? _questions(Map<String, dynamic> params) {
    final raw = params['questions'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(UserInputQuestion.fromJson)
          .toList();
    }
    return null;
  }
}

/// Default decision button order per approval kind when the server omits
/// `availableDecisions`.
class ApprovalDecisions {
  ApprovalDecisions._();

  static const command = ['accept', 'acceptForSession', 'decline', 'cancel'];
  static const fileChange = ['accept', 'acceptForSession', 'decline', 'cancel'];

  /// Human-facing label for a decision value.
  static String label(String decision) {
    switch (decision) {
      case 'accept':
        return 'Approve';
      case 'acceptForSession':
        return 'Approve for session';
      case 'decline':
        return 'Decline';
      case 'cancel':
        return 'Cancel turn';
      default:
        return decision;
    }
  }

  /// Whether this decision is destructive/negative styling.
  static bool isNegative(String decision) =>
      decision == 'decline' || decision == 'cancel';
}
