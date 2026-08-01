import 'package:flutter/material.dart';

import '../../../protocol/turn.dart';

/// A compact, horizontally-scrollable strip of plan/todo steps pinned above
/// the composer.
class PlanStrip extends StatelessWidget {
  const PlanStrip({super.key, required this.steps});

  final List<PlanStep> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final done = steps.where((s) => s.status == 'completed').length;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: const Icon(Icons.checklist, size: 20),
        title: Text('Plan · $done/${steps.length}',
            style: const TextStyle(fontSize: 13)),
        children: [
          for (final step in steps)
            ListTile(
              dense: true,
              leading: _icon(step.status),
              title: Text(step.step, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _icon(String status) => switch (status) {
        'completed' => const Icon(Icons.check_circle, size: 18, color: Colors.green),
        'inProgress' => const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        _ => const Icon(Icons.radio_button_unchecked, size: 18),
      };
}
