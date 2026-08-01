import 'package:flutter/material.dart';

/// A compact status indicator for a thread item's lifecycle: a spinner while
/// `inProgress`, otherwise a small colored dot keyed to the terminal status.
///
/// Shared by the transcript's tool cards and the collapsed step rows so their
/// status affordance stays visually consistent.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status, this.size = 10});

  final String status;

  /// Diameter of the resting dot; the spinner uses a slightly larger box.
  final double size;

  @override
  Widget build(BuildContext context) {
    if (status == 'inProgress') {
      return SizedBox(
        width: size + 1,
        height: size + 1,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final color = switch (status) {
      'completed' => Colors.green,
      'failed' => Colors.red,
      'declined' => Colors.orange,
      _ => Colors.grey,
    };
    return Icon(Icons.circle, size: size, color: color);
  }
}
