import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/connection_manager.dart';
import '../data/codex_service.dart';
import '../data/settings_repository.dart';
import 'approval_controller.dart';

/// Secure-storage-backed settings/profiles repository.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

/// The single connection manager for the app session.
final connectionManagerProvider = Provider<ConnectionManager>((ref) {
  final manager = ConnectionManager();
  ref.onDispose(manager.dispose);
  return manager;
});

/// Streams the current connection state.
final connectionStateProvider = StreamProvider<ConnectionState>((ref) {
  final manager = ref.watch(connectionManagerProvider);
  // Seed with the current value so late subscribers see it immediately.
  return _startWith(manager.states, manager.state);
});

/// A [CodexService] bound to the current RPC client, or null when not ready.
final codexServiceProvider = Provider<CodexService?>((ref) {
  final asyncState = ref.watch(connectionStateProvider);
  final manager = ref.watch(connectionManagerProvider);
  final ready = asyncState.value?.isReady ?? false;
  final client = manager.client;
  if (!ready || client == null) return null;
  return CodexService(client);
});

/// Approval controller bound to the active RPC client's server-request router.
/// Recreated whenever the client changes (i.e. after a reconnect) so approval
/// handlers are re-registered on the new router.
final approvalControllerProvider =
    ChangeNotifierProvider<ApprovalController?>((ref) {
  final asyncState = ref.watch(connectionStateProvider);
  final manager = ref.watch(connectionManagerProvider);
  final ready = asyncState.value?.isReady ?? false;
  final client = manager.client;
  if (!ready || client == null) return null;
  return ApprovalController(client.router);
});

Stream<T> _startWith<T>(Stream<T> source, T initial) async* {
  yield initial;
  yield* source;
}
