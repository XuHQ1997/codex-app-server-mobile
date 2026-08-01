import 'package:flutter/material.dart';

import '../../protocol/items/item.dart';
import 'unified_diff_view.dart';

/// Full-screen diff viewer for a [FileChangeItem], with per-file sections.
class DiffViewerScreen extends StatelessWidget {
  const DiffViewerScreen({super.key, required this.changes, this.title});

  final List<FileUpdateChange> changes;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title ?? 'Changes (${changes.length})')),
      body: ListView.builder(
        itemCount: changes.length,
        itemBuilder: (context, i) {
          final change = changes[i];
          return _FileSection(change: change, initiallyExpanded: changes.length == 1);
        },
      ),
    );
  }
}

class _FileSection extends StatelessWidget {
  const _FileSection({required this.change, this.initiallyExpanded = false});

  final FileUpdateChange change;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      leading: Icon(_kindIcon(change.kind), size: 20),
      title: Text(
        change.path,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(change.kind),
      children: [
        UnifiedDiffView(diff: change.diff, shrinkWrap: true),
      ],
    );
  }

  IconData _kindIcon(String kind) => switch (kind) {
        'add' => Icons.add_circle_outline,
        'delete' => Icons.remove_circle_outline,
        _ => Icons.edit_outlined,
      };
}
