import 'package:flutter/material.dart';

/// Renders a unified diff string with +/- line coloring.
///
/// Intentionally simple: splits on lines and colors by leading character.
/// Large diffs render lazily via [ListView.builder].
class UnifiedDiffView extends StatelessWidget {
  const UnifiedDiffView({super.key, required this.diff, this.shrinkWrap = false});

  final String diff;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final lines = diff.split('\n');
    final scheme = Theme.of(context).colorScheme;

    Color? bgFor(String line) {
      if (line.startsWith('+') && !line.startsWith('+++')) {
        return Colors.green.withValues(alpha: 0.15);
      }
      if (line.startsWith('-') && !line.startsWith('---')) {
        return Colors.red.withValues(alpha: 0.15);
      }
      if (line.startsWith('@@')) {
        return scheme.primaryContainer.withValues(alpha: 0.4);
      }
      return null;
    }

    Color fgFor(String line) {
      if (line.startsWith('+') && !line.startsWith('+++')) return Colors.green.shade800;
      if (line.startsWith('-') && !line.startsWith('---')) return Colors.red.shade800;
      if (line.startsWith('@@')) return scheme.primary;
      return scheme.onSurface;
    }

    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[i];
        return Container(
          width: double.infinity,
          color: bgFor(line),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Text(
            line.isEmpty ? ' ' : line,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: fgFor(line),
            ),
          ),
        );
      },
    );
  }
}
