import 'dart:math';

import '../core/constants.dart';

/// Exponential backoff with full jitter for reconnects and `-32001` retries.
class Backoff {
  Backoff({
    this.base = AppConstants.reconnectBaseDelay,
    this.max = AppConstants.reconnectMaxDelay,
  });

  final Duration base;
  final Duration max;
  final _rng = Random();

  int _attempt = 0;

  /// Returns the next delay and advances the attempt counter.
  Duration next() {
    final exp = base.inMilliseconds * pow(2, _attempt);
    final capped = min(exp.toDouble(), max.inMilliseconds.toDouble());
    _attempt++;
    // Full jitter: uniform in [0, capped].
    final jittered = _rng.nextDouble() * capped;
    return Duration(milliseconds: jittered.round());
  }

  void reset() => _attempt = 0;

  int get attempt => _attempt;
}
