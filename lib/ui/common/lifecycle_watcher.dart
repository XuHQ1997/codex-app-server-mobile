import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging.dart';
import '../../data/connection_manager.dart';
import '../../state/providers.dart';

/// Watches app lifecycle (foreground/background) and network connectivity, and
/// nudges the [ConnectionManager] to reconnect promptly when the app returns to
/// the foreground or the network changes.
///
/// This complements the manager's own exponential-backoff reconnect loop by
/// short-circuiting the wait when we have a strong signal that connectivity may
/// have been restored — the common mobile case of unlocking the phone or
/// switching Wi-Fi/cellular.
class LifecycleWatcher extends ConsumerStatefulWidget {
  const LifecycleWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LifecycleWatcher> createState() => _LifecycleWatcherState();
}

class _LifecycleWatcherState extends ConsumerState<LifecycleWatcher>
    with WidgetsBindingObserver {
  final _log = appLogger('LifecycleWatcher');
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connSub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    super.dispose();
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final hasNetwork =
        results.any((r) => r != ConnectivityResult.none);
    if (hasNetwork) {
      _log.info('Connectivity changed ($results); trying reconnect');
      _reconnectIfNeeded();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _log.info('App resumed; refreshing connection');
      final manager = ref.read(connectionManagerProvider);
      if (manager.state.status != ConnectionStatus.disconnected) {
        manager.reconnectNow(force: true);
      }
    }
  }

  void _reconnectIfNeeded() {
    final manager = ref.read(connectionManagerProvider);
    if (manager.state.status != ConnectionStatus.ready &&
        manager.state.status != ConnectionStatus.disconnected) {
      manager.reconnectNow();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
