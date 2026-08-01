import 'package:flutter/material.dart';

import '../../protocol/items/item.dart';
import '../diff/diff_viewer_screen.dart';
import 'status_dot.dart';
import 'transcript_grouping.dart';

/// Renders a single intermediate step as a flat, borderless row for use inside
/// a [StepGroup]'s scroll window. Deliberately bubble-free and compact so the
/// narrow window shows as much useful width as possible.
///
/// Commands expand their output inline on tap; file changes open the full diff
/// viewer; everything else is a one-line summary.
class CompactStep extends StatelessWidget {
  const CompactStep({super.key, required this.item});

  final ThreadItem item;

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      CommandExecutionItem i => _CommandStep(item: i),
      FileChangeItem i => _FileChangeStep(item: i),
      AgentMessageItem i => _iconLine(
          context,
          Icons.chat_bubble_outline,
          i.text.trim(),
        ),
      ReasoningItem i => _iconLine(
          context,
          Icons.psychology_outlined,
          _reasoningText(i),
          italic: true,
        ),
      WebSearchItem i =>
        _iconLine(context, Icons.search, 'Searched: ${i.query}'),
      McpToolCallItem i => _iconLine(
          context,
          Icons.extension,
          '${i.server} · ${i.tool}',
          status: i.status,
        ),
      ReviewModeItem i => _iconLine(
          context,
          Icons.rate_review_outlined,
          i.entered ? 'Entered review mode' : 'Exited review mode',
        ),
      ContextCompactionItem _ =>
        _iconLine(context, Icons.compress, 'Context compacted'),
      _ => _iconLine(context, Icons.circle, stepLabel(item)),
    };
  }

  static String _reasoningText(ReasoningItem item) {
    final summary =
        item.summary.where((s) => s.trim().isNotEmpty).join(' ').trim();
    return summary.isEmpty ? 'Thinking…' : summary;
  }

  Widget _iconLine(
    BuildContext context,
    IconData icon,
    String text, {
    String? status,
    bool italic = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: scheme.onSurfaceVariant,
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          if (status != null) ...[
            const SizedBox(width: 6),
            StatusDot(status: status, size: 9),
          ],
        ],
      ),
    );
  }
}

/// A command step: command line + status, expandable to reveal output inline.
class _CommandStep extends StatefulWidget {
  const _CommandStep({required this.item});
  final CommandExecutionItem item;

  @override
  State<_CommandStep> createState() => _CommandStepState();
}

class _CommandStepState extends State<_CommandStep> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final scheme = Theme.of(context).colorScheme;
    final hasOutput = item.output.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasOutput ? () => setState(() => _expanded = !_expanded) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.command,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.3,
                    ),
                    maxLines: _expanded ? null : 2,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                StatusDot(status: item.status, size: 9),
                if (hasOutput)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: scheme.outline,
                  ),
              ],
            ),
          ),
        ),
        if (_expanded && hasOutput)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(left: 23, bottom: 4),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                item.output,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
              ),
            ),
          ),
      ],
    );
  }
}

/// A file-change step: tappable one-liner that opens the full diff viewer.
class _FileChangeStep extends StatelessWidget {
  const _FileChangeStep({required this.item});
  final FileChangeItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DiffViewerScreen(changes: item.changes),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          children: [
            Icon(Icons.edit_document, size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${item.changes.length} file(s) changed',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ),
            StatusDot(status: item.status, size: 9),
            Icon(Icons.chevron_right, size: 16, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}
