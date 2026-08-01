/// Thread settings + model catalog models for the `thread/settings/update`
/// (experimental) and `model/list` methods.
///
/// These back the in-chat settings sheet where the user switches the model,
/// approval policy, and reasoning effort of a live thread.
library;

/// Approval policy — the `AskForApproval` enum on the wire (kebab-case).
/// `granular` is an experimental object form we don't author from mobile, so
/// it's represented as an opaque tag here.
enum ApprovalPolicy {
  untrusted('untrusted', 'Untrusted only', 'Only run trusted commands without asking'),
  onRequest('on-request', 'On request', 'Ask when the agent wants to act'),
  never('never', 'Never ask', 'Run everything without prompting'),
  granular('granular', 'Granular', 'Fine-grained rules (set via CLI)');

  const ApprovalPolicy(this.wire, this.label, this.description);

  final String wire;
  final String label;
  final String description;

  static ApprovalPolicy? fromWire(Object? raw) {
    // The wire value may be a bare string or an object (granular) with a
    // discriminant; normalize both.
    final tag = switch (raw) {
      String s => s,
      Map m => m['type'] as String? ?? m.keys.firstOrNull?.toString(),
      _ => null,
    };
    if (tag == null) return null;
    for (final p in values) {
      if (p.wire == tag) return p;
    }
    return null;
  }

  /// Policies offered as selectable options in the settings sheet.
  static const selectable = [untrusted, onRequest, never];
}

/// Reasoning effort — serialized as a lowercase string. Modeled as a value
/// object (not a closed enum) so unknown/custom efforts round-trip safely.
class ReasoningEffort {
  const ReasoningEffort(this.wire);

  final String wire;

  static const none = ReasoningEffort('none');
  static const minimal = ReasoningEffort('minimal');
  static const low = ReasoningEffort('low');
  static const medium = ReasoningEffort('medium');
  static const high = ReasoningEffort('high');
  static const xhigh = ReasoningEffort('xhigh');

  String get label => switch (wire) {
        'none' => 'None',
        'minimal' => 'Minimal',
        'low' => 'Low',
        'medium' => 'Medium',
        'high' => 'High',
        'xhigh' => 'Extra high',
        _ => wire,
      };

  static ReasoningEffort? fromWire(Object? raw) =>
      raw is String && raw.isNotEmpty ? ReasoningEffort(raw) : null;

  @override
  bool operator ==(Object other) =>
      other is ReasoningEffort && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;
}

/// Current settings snapshot for a thread. Fields are nullable because the
/// source (`thread/resume` top-level or `thread/settings/updated`) may omit
/// some, and older servers omit them entirely.
class ThreadSettings {
  const ThreadSettings({
    this.model,
    this.approvalPolicy,
    this.effort,
    this.cwd,
    this.name,
  });

  final String? model;
  final ApprovalPolicy? approvalPolicy;
  final ReasoningEffort? effort;
  final String? cwd;
  final String? name;

  ThreadSettings copyWith({
    String? model,
    ApprovalPolicy? approvalPolicy,
    ReasoningEffort? effort,
    String? cwd,
    String? name,
  }) =>
      ThreadSettings(
        model: model ?? this.model,
        approvalPolicy: approvalPolicy ?? this.approvalPolicy,
        effort: effort ?? this.effort,
        cwd: cwd ?? this.cwd,
        name: name ?? this.name,
      );

  /// Parses from a map that may be the `thread/resume` response (fields at top
  /// level, sandbox under `sandbox`, effort under `reasoningEffort`) or a
  /// `thread/settings/updated` settings object (effort under `effort`).
  factory ThreadSettings.fromMap(Map<String, dynamic> json) {
    final thread = json['thread'];
    final name = thread is Map<String, dynamic> ? thread['name'] as String? : null;
    return ThreadSettings(
      model: json['model'] as String?,
      approvalPolicy: ApprovalPolicy.fromWire(json['approvalPolicy']),
      effort: ReasoningEffort.fromWire(
        json['reasoningEffort'] ?? json['effort'],
      ),
      cwd: json['cwd'] as String?,
      name: name,
    );
  }
}

/// A model entry from `model/list`.
class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.model,
    required this.displayName,
    this.isDefault = false,
    this.supportedEfforts = const [],
    this.defaultEffort,
  });

  final String id;

  /// The model slug passed back in settings/turn params.
  final String model;
  final String displayName;
  final bool isDefault;
  final List<ReasoningEffort> supportedEfforts;
  final ReasoningEffort? defaultEffort;

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    final efforts = <ReasoningEffort>[];
    final raw = json['supportedReasoningEfforts'];
    if (raw is List) {
      for (final e in raw) {
        final w = e is Map ? e['reasoningEffort'] : e;
        final parsed = ReasoningEffort.fromWire(w);
        if (parsed != null) efforts.add(parsed);
      }
    }
    return ModelInfo(
      id: json['id'] as String? ?? json['model'] as String? ?? '',
      model: json['model'] as String? ?? json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ??
          json['model'] as String? ??
          json['id'] as String? ??
          '',
      isDefault: json['isDefault'] as bool? ?? false,
      supportedEfforts: efforts,
      defaultEffort: ReasoningEffort.fromWire(json['defaultReasoningEffort']),
    );
  }
}
