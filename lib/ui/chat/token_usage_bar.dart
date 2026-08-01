import 'package:flutter/material.dart';

import '../../../protocol/turn.dart';

/// A thin bar showing how much of the model's context window is used for the
/// current thread. When the window size is known it renders a progress bar with
/// a "42% context" label; otherwise it falls back to a compact token count.
/// Tapping toggles a detailed token breakdown.
class TokenUsageBar extends StatefulWidget {
  const TokenUsageBar({super.key, required this.usage});

  final TokenUsage? usage;

  @override
  State<TokenUsageBar> createState() => _TokenUsageBarState();
}

class _TokenUsageBarState extends State<TokenUsageBar> {
  bool _showDetail = false;

  @override
  Widget build(BuildContext context) {
    final u = widget.usage;
    if (u == null || (u.contextTokens == 0 && u.sessionTotalTokens == 0)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final fraction = u.contextFraction;

    return Material(
      color: scheme.surfaceContainer,
      child: InkWell(
        onTap: () => setState(() => _showDetail = !_showDetail),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.data_usage, size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(child: _label(context, u, fraction)),
                  Icon(
                    _showDetail ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: scheme.outline,
                  ),
                ],
              ),
              if (fraction != null) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 4,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: _barColor(scheme, fraction),
                  ),
                ),
              ],
              if (_showDetail) ...[
                const SizedBox(height: 4),
                Text(
                  'context ${_compact(u.contextTokens)}'
                  '${u.contextWindow != null ? ' / ${_compact(u.contextWindow!)}' : ''}'
                  ' · session ${_compact(u.sessionTotalTokens)}'
                  '${u.cachedInputTokens > 0 ? ' · cached ${_compact(u.cachedInputTokens)}' : ''}',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, TokenUsage u, double? fraction) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final usedPct = u.contextUsedPercent;
    if (usedPct != null) {
      return Text(
        '$usedPct% context · ${_compact(u.contextTokens)} / ${_compact(u.contextWindow!)} tokens',
        style: style,
      );
    }
    return Text('${_compact(u.contextTokens)} tokens in context', style: style);
  }

  Color _barColor(ColorScheme scheme, double fraction) {
    if (fraction >= 0.9) return scheme.error;
    if (fraction >= 0.75) return Colors.orange;
    return scheme.primary;
  }

  /// Compact token count, e.g. 128000 -> "128k", 12345 -> "12.3k".
  static String _compact(int n) {
    if (n < 1000) return '$n';
    final k = n / 1000;
    return k >= 100 ? '${k.round()}k' : '${k.toStringAsFixed(1)}k';
  }
}
