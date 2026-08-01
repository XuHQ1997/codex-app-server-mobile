import 'package:flutter/material.dart';

import '../../protocol/approvals/approval_requests.dart';
import '../../protocol/items/item.dart';
import '../diff/diff_viewer_screen.dart';
import '../diff/unified_diff_view.dart';
import 'user_input_form.dart';

/// A modal bottom sheet rendering a single approval request. The buttons are
/// rendered in the server-provided `availableDecisions` order when present,
/// otherwise a sensible default per approval kind.
///
/// Returns the chosen decision map via [onDecision]. It is non-dismissible by
/// tapping outside so a decision is always made.
class ApprovalSheet extends StatelessWidget {
  const ApprovalSheet({
    super.key,
    required this.request,
    required this.pendingCount,
    required this.onDecision,
    required this.onPermissions,
    required this.onUserInput,
  });

  final ApprovalRequest request;
  final int pendingCount;
  final void Function(String decision) onDecision;
  final void Function(Map<String, dynamic> permissions, String scope)
      onPermissions;
  final void Function(Map<String, List<String>> answers) onUserInput;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_icon(), color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(_title(), style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (pendingCount > 1)
                  Chip(
                    label: Text('+${pendingCount - 1} more'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (request.kind == ApprovalKind.toolUserInput)
              // The form owns its own scroll + submit button.
              Flexible(
                child: UserInputForm(
                  questions: request.questions ?? const [],
                  autoResolutionMs: request.autoResolutionMs,
                  onSubmit: onUserInput,
                ),
              )
            else ...[
              Flexible(child: SingleChildScrollView(child: _body(context))),
              const SizedBox(height: 16),
              ..._buttons(context),
            ],
          ],
        ),
      ),
    );
  }

  IconData _icon() => switch (request.kind) {
        ApprovalKind.commandExecution => Icons.terminal,
        ApprovalKind.fileChange => Icons.edit_document,
        ApprovalKind.permissions => Icons.security,
        ApprovalKind.toolUserInput => Icons.help_outline,
      };

  String _title() => switch (request.kind) {
        ApprovalKind.commandExecution => 'Run command?',
        ApprovalKind.fileChange => 'Apply file changes?',
        ApprovalKind.permissions => 'Grant permissions?',
        ApprovalKind.toolUserInput => 'Input requested',
      };

  Widget _body(BuildContext context) {
    switch (request.kind) {
      case ApprovalKind.commandExecution:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (request.reason != null) ...[
              Text(request.reason!),
              const SizedBox(height: 8),
            ],
            if (request.command != null)
              _CodeBlock(text: request.command!),
            if (request.cwd != null) ...[
              const SizedBox(height: 8),
              Text('cwd: ${request.cwd}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        );
      case ApprovalKind.fileChange:
        final changes = request.changes ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (request.reason != null) ...[
              Text(request.reason!),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(child: Text('${changes.length} file(s) will change:')),
                if (changes.any((c) => (c['diff'] as String?)?.isNotEmpty ?? false))
                  TextButton.icon(
                    onPressed: () => _openFullDiff(context, changes),
                    icon: const Icon(Icons.open_in_full, size: 16),
                    label: const Text('Full diff'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (final c in changes) _FileChangeTile(change: c),
          ],
        );
      case ApprovalKind.permissions:
        final lines = _permissionSummary(request.params['permissions']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(request.reason ??
                'The agent is requesting additional permissions.'),
            if (request.cwd != null) ...[
              const SizedBox(height: 8),
              Text('cwd: ${request.cwd}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(line.icon,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(line.text,
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        );
      case ApprovalKind.toolUserInput:
        // Rendered via UserInputForm in build(); never reached here.
        return const SizedBox.shrink();
    }
  }

  List<Widget> _buttons(BuildContext context) {
    if (request.kind == ApprovalKind.permissions) {
      // Simple grant-all-requested / deny for now.
      final requested = request.params['permissions'];
      return [
        FilledButton(
          onPressed: () => onPermissions(
            requested is Map<String, dynamic> ? requested : {},
            'turn',
          ),
          child: const Text('Grant for this turn'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: () => onPermissions(
            requested is Map<String, dynamic> ? requested : {},
            'session',
          ),
          child: const Text('Grant for session'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => onPermissions(const {}, 'turn'),
          child: const Text('Deny'),
        ),
      ];
    }

    final decisions = request.availableDecisions ??
        (request.kind == ApprovalKind.commandExecution
            ? ApprovalDecisions.command
            : ApprovalDecisions.fileChange);

    return [
      for (final decision in decisions)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ApprovalDecisions.isNegative(decision)
              ? OutlinedButton(
                  onPressed: () => onDecision(decision),
                  child: Text(ApprovalDecisions.label(decision)),
                )
              : FilledButton(
                  onPressed: () => onDecision(decision),
                  child: Text(ApprovalDecisions.label(decision)),
                ),
        ),
    ];
  }

  static String _changeKind(Object? kind) {
    if (kind is String) return kind;
    if (kind is Map && kind.isNotEmpty) return kind.keys.first.toString();
    return 'update';
  }

  /// Derives a short, human-readable summary of a requested permission profile
  /// (`{network:{enabled}, fileSystem:{read,write,entries}}`) instead of dumping
  /// the raw object. Returns an empty list when there's nothing concrete.
  static List<_PermissionLine> _permissionSummary(Object? permissions) {
    if (permissions is! Map) return const [];
    final lines = <_PermissionLine>[];

    final network = permissions['network'];
    if (network is Map && network['enabled'] == true) {
      lines.add(const _PermissionLine(Icons.public, 'Network access'));
    }

    final fs = permissions['fileSystem'];
    if (fs is Map) {
      int count(Object? v) => v is List ? v.length : 0;
      final reads = count(fs['read']);
      final writes = count(fs['write']);
      final entries = count(fs['entries']);
      if (reads > 0) {
        lines.add(_PermissionLine(
            Icons.description_outlined, 'Read $reads path(s)'));
      }
      if (writes > 0) {
        lines.add(_PermissionLine(Icons.edit_outlined, 'Write $writes path(s)'));
      }
      if (entries > 0 && reads == 0 && writes == 0) {
        lines.add(_PermissionLine(
            Icons.folder_outlined, 'File system access ($entries)'));
      }
    }
    return lines;
  }

  void _openFullDiff(
    BuildContext context,
    List<Map<String, dynamic>> changes,
  ) {
    final parsed = changes.map(FileUpdateChange.fromJson).toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiffViewerScreen(changes: parsed, title: 'Proposed changes'),
      ),
    );
  }
}

/// One proposed file change in a fileChange approval: path + kind header that
/// expands to an inline diff, so the user can inspect changes before approving
/// instead of blind-approving.
class _FileChangeTile extends StatelessWidget {
  const _FileChangeTile({required this.change});

  final Map<String, dynamic> change;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = change['path']?.toString() ?? '?';
    final kind = ApprovalSheet._changeKind(change['kind']);
    final diff = change['diff'] as String? ?? '';
    final header = Row(
      children: [
        Icon(_kindIcon(kind), size: 16, color: _kindColor(kind, scheme)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            path,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(kind, style: TextStyle(fontSize: 11, color: scheme.outline)),
      ],
    );
    if (diff.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: header);
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        dense: true,
        title: header,
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              child: UnifiedDiffView(diff: diff, shrinkWrap: true),
            ),
          ),
        ],
      ),
    );
  }

  IconData _kindIcon(String kind) => switch (kind) {
        'add' => Icons.add_circle_outline,
        'delete' => Icons.remove_circle_outline,
        _ => Icons.edit_outlined,
      };

  Color _kindColor(String kind, ColorScheme scheme) => switch (kind) {
        'add' => Colors.green,
        'delete' => Colors.red,
        _ => scheme.onSurfaceVariant,
      };
}

/// A single summarized permission line (icon + short text).
class _PermissionLine {
  const _PermissionLine(this.icon, this.text);
  final IconData icon;
  final String text;
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
  }
}
