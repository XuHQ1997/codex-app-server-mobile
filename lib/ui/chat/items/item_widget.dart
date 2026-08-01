import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../protocol/items/item.dart';
import '../../common/markdown_view.dart';
import '../../diff/diff_viewer_screen.dart';
import '../status_dot.dart';

/// Renders a single [ThreadItem] to a widget, switching on its concrete type,
/// with an [UnknownItem] fallback so new server types never crash the UI.
class ItemWidget extends StatelessWidget {
  const ItemWidget({super.key, required this.item});

  final ThreadItem item;

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      UserMessageItem i => _UserMessage(item: i),
      AgentMessageItem i => _AgentMessage(item: i),
      ReasoningItem i => _Reasoning(item: i),
      CommandExecutionItem i => _CommandExecution(item: i),
      FileChangeItem i => _FileChange(item: i),
      McpToolCallItem i => _ToolCard(
          icon: Icons.extension,
          title: '${i.server} · ${i.tool}',
          status: i.status,
        ),
      WebSearchItem i => _ToolCard(
          icon: Icons.search,
          title: 'Web search: ${i.query}',
          status: null,
        ),
      PlanItem i => _PlanBubble(item: i),
      ReviewModeItem i => _Marker(
          text: i.entered ? 'Entered review mode' : 'Exited review mode',
        ),
      ContextCompactionItem _ => const _Marker(text: 'Context compacted'),
      UnknownItem i => _Unknown(item: i),
      _ => const SizedBox.shrink(),
    };
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.child,
    this.alignEnd = false,
    this.color,
  });

  final Widget child;
  final bool alignEnd;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.item});
  final UserMessageItem item;

  @override
  Widget build(BuildContext context) {
    return _Bubble(
      alignEnd: true,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Text(item.text),
    );
  }
}

/// The agent's final answer. Rendered as flowing body content (no bubble or
/// border) so it reads like prose and stands out from the bordered tool cards
/// and user bubbles around it.
class _AgentMessage extends StatelessWidget {
  const _AgentMessage({required this.item});
  final AgentMessageItem item;

  @override
  Widget build(BuildContext context) {
    if (item.text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: MarkdownView(data: item.text),
    );
  }
}

class _Reasoning extends StatelessWidget {
  const _Reasoning({required this.item});
  final ReasoningItem item;

  @override
  Widget build(BuildContext context) {
    final summary = item.summary.where((s) => s.trim().isNotEmpty).join('\n\n');
    if (summary.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.psychology_outlined, size: 18),
          title: const Text('Reasoning', style: TextStyle(fontSize: 13)),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                summary,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Command executions can produce a lot of output, so they render collapsed by
/// default (command + status only) and expand on tap to reveal output and the
/// exit/duration footer. Expansion state is kept per-item via the widget key.
class _CommandExecution extends StatefulWidget {
  const _CommandExecution({required this.item});
  final CommandExecutionItem item;

  @override
  State<_CommandExecution> createState() => _CommandExecutionState();
}

class _CommandExecutionState extends State<_CommandExecution> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final scheme = Theme.of(context).colorScheme;
    final hasDetails = item.output.isNotEmpty ||
        item.exitCode != null ||
        item.durationMs != null;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap:
                hasDetails ? () => setState(() => _expanded = !_expanded) : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.terminal, size: 16, color: Colors.white70),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.command,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  StatusDot(status: item.status, size: 10),
                  if (hasDetails) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: Colors.white54,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded && item.output.isNotEmpty)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 240),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: SingleChildScrollView(
                child: SelectableText(
                  item.output,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          if (_expanded && (item.exitCode != null || item.durationMs != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                [
                  if (item.exitCode != null) 'exit ${item.exitCode}',
                  if (item.durationMs != null) '${item.durationMs}ms',
                ].join(' · '),
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}

class _FileChange extends StatelessWidget {
  const _FileChange({required this.item});
  final FileChangeItem item;

  @override
  Widget build(BuildContext context) {
    return _Bubble(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DiffViewerScreen(changes: item.changes),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.edit_document, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${item.changes.length} file(s) changed',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            StatusDot(status: item.status, size: 10),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _PlanBubble extends StatelessWidget {
  const _PlanBubble({required this.item});
  final PlanItem item;

  @override
  Widget build(BuildContext context) {
    if (item.text.isEmpty) return const SizedBox.shrink();
    return _Bubble(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: MarkdownView(data: item.text),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.icon, required this.title, this.status});
  final IconData icon;
  final String title;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return _Bubble(
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis)),
          if (status != null) StatusDot(status: status!, size: 10),
        ],
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

class _Unknown extends StatelessWidget {
  const _Unknown({required this.item});
  final UnknownItem item;

  @override
  Widget build(BuildContext context) {
    return _Bubble(
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unsupported item: ${item.type}',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            const JsonEncoder.withIndent('  ').convert(item.raw),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
      ),
    );
  }
}
