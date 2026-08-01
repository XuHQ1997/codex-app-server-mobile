import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/connection_manager.dart';
import '../../state/providers.dart';

/// A thin banner shown when the connection is not ready (reconnecting/failed).
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(connectionStateProvider);
    final state = asyncState.value;
    if (state == null || state.isReady) return const SizedBox.shrink();

    final (color, label, showSpinner) = switch (state.status) {
      ConnectionStatus.connecting => (Colors.orange, 'Connecting…', true),
      ConnectionStatus.initializing => (Colors.orange, 'Initializing…', true),
      ConnectionStatus.reconnecting => (Colors.orange, 'Reconnecting…', true),
      ConnectionStatus.failed => (
          Colors.red,
          'Disconnected — ${state.error ?? 'connection lost'}',
          false,
        ),
      ConnectionStatus.disconnected => (Colors.grey, 'Disconnected', false),
      ConnectionStatus.ready => (Colors.green, 'Connected', false),
    };

    return Material(
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            if (showSpinner)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.circle, size: 12, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            if (state.status == ConnectionStatus.failed)
              TextButton(
                onPressed: () =>
                    ref.read(connectionManagerProvider).reconnectNow(),
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}
