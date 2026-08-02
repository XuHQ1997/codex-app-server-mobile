import 'dart:async';

import '../core/constants.dart';
import '../core/logging.dart';
import '../rpc/backoff.dart';
import '../rpc/rpc_client.dart';
import '../rpc/rpc_method_names.dart';
import '../transport/io_ws_transport.dart';
import '../transport/ws_transport.dart';

/// Connection profile: how to reach a remote codex app-server.
class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.name,
    required this.url,
    this.bearerToken,
  });

  final String id;
  final String name;

  /// `ws://host:port`, normally reached over a private Tailscale network.
  final String url;
  final String? bearerToken;

  ServerProfile copyWith({String? name, String? url, String? bearerToken}) =>
      ServerProfile(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        bearerToken: bearerToken ?? this.bearerToken,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    // NB: bearerToken is stored separately in secure storage, not here.
  };

  factory ServerProfile.fromJson(Map<String, dynamic> json, {String? token}) =>
      ServerProfile(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Server',
        url: json['url'] as String? ?? '',
        bearerToken: token,
      );
}

/// Overall connection lifecycle state.
enum ConnectionStatus {
  disconnected,
  connecting,
  initializing,
  ready,
  reconnecting,
  failed,
}

class ConnectionState {
  const ConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.profile,
    this.error,
  });

  final ConnectionStatus status;
  final ServerProfile? profile;
  final String? error;

  bool get isReady => status == ConnectionStatus.ready;

  ConnectionState copyWith({
    ConnectionStatus? status,
    ServerProfile? profile,
    String? error,
  }) => ConnectionState(
    status: status ?? this.status,
    profile: profile ?? this.profile,
    error: error,
  );
}

/// Factory that builds a transport for a profile. Injectable for testing.
typedef TransportFactory = WsTransport Function(ServerProfile profile);

WsTransport _defaultTransportFactory(ServerProfile profile) =>
    IoWsTransport(url: profile.url, bearerToken: profile.bearerToken);

/// Owns the transport + [RpcClient] lifecycle: connect, JSON-RPC handshake,
/// and reconnect. Exposes the active [RpcClient] and a state stream.
///
/// Thread resume after a reconnect is handled by listeners (the active session
/// controller) that watch [onReady] and re-issue `thread/resume`.
class ConnectionManager {
  ConnectionManager({TransportFactory? transportFactory})
    : _transportFactory = transportFactory ?? _defaultTransportFactory;

  final TransportFactory _transportFactory;
  final _log = appLogger('ConnectionManager');
  final _stateController = StreamController<ConnectionState>.broadcast();
  final _readyController = StreamController<void>.broadcast();
  final _backoff = Backoff();

  ConnectionState _state = const ConnectionState();
  RpcClient? _client;
  WsTransport? _transport;
  StreamSubscription<void>? _doneSub;
  Timer? _reconnectTimer;
  bool _attempting = false;
  bool _manualClose = false;

  Stream<ConnectionState> get states => _stateController.stream;
  ConnectionState get state => _state;

  /// Emits whenever the connection reaches [ConnectionStatus.ready]
  /// (initial connect AND after each successful reconnect).
  Stream<void> get onReady => _readyController.stream;

  RpcClient? get client => _client;

  void _setState(ConnectionState s) {
    _state = s;
    _stateController.add(s);
  }

  /// Connects to [profile] and performs the initialize/initialized handshake.
  Future<void> connect(ServerProfile profile) async {
    _manualClose = false;
    _reconnectTimer?.cancel();
    await _teardown();
    _backoff.reset();
    await _attempt(profile);
  }

  Future<void> _attempt(ServerProfile profile) async {
    if (_attempting) return;
    _attempting = true;
    _setState(
      _state.copyWith(status: ConnectionStatus.connecting, profile: profile),
    );
    try {
      final transport = _transportFactory(profile);
      await transport.connect();
      _transport = transport;

      final client = RpcClient(transport: transport);
      client.start();
      _client = client;

      _setState(_state.copyWith(status: ConnectionStatus.initializing));
      await client.callObject(
        RpcMethods.initialize,
        params: {
          'clientInfo': {
            'name': AppConstants.clientName,
            'title': AppConstants.clientTitle,
            'version': AppConstants.clientVersion,
          },
          'capabilities': {'experimentalApi': false},
        },
      );
      client.notify(RpcMethods.initialized);

      // Watch for the transport closing to drive reconnect.
      _doneSub = transport.done.asStream().listen((_) => _onDisconnected());

      _backoff.reset();
      _setState(_state.copyWith(status: ConnectionStatus.ready));
      _readyController.add(null);
      _log.info('Connected & initialized: ${profile.url}');
    } catch (e, st) {
      _log.warning('Connect attempt failed', e, st);
      await _teardown();
      _setState(
        _state.copyWith(status: ConnectionStatus.failed, error: e.toString()),
      );
      if (!_manualClose) {
        _scheduleReconnect(profile);
      }
    } finally {
      _attempting = false;
    }
  }

  void _onDisconnected() {
    if (_manualClose) return;
    final profile = _state.profile;
    if (profile == null) return;
    _log.info('Disconnected; scheduling reconnect');
    _setState(_state.copyWith(status: ConnectionStatus.reconnecting));
    _scheduleReconnect(profile);
  }

  void _scheduleReconnect(ServerProfile profile) {
    if (_manualClose) return;
    _reconnectTimer?.cancel();
    final delay = _backoff.next();
    _log.info(
      'Reconnecting in ${delay.inMilliseconds}ms '
      '(attempt ${_backoff.attempt})',
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_manualClose) return;
      _attempt(profile);
    });
  }

  /// Forces an immediate reconnect. With [force], also replaces a connection
  /// that still reports ready; mobile OSes can silently invalidate a socket
  /// while the app is suspended before its close event reaches Dart.
  Future<void> reconnectNow({bool force = false}) async {
    final profile = _state.profile;
    if (profile == null || _manualClose) return;
    if (_attempting) return;
    if (_state.status == ConnectionStatus.ready && !force) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _backoff.reset();
    await _teardown();
    await _attempt(profile);
  }

  Future<void> disconnect() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _teardown();
    _setState(const ConnectionState(status: ConnectionStatus.disconnected));
  }

  Future<void> _teardown() async {
    await _doneSub?.cancel();
    _doneSub = null;
    await _client?.dispose();
    _client = null;
    await _transport?.close();
    _transport = null;
  }

  Future<void> dispose() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    await _teardown();
    await _stateController.close();
    await _readyController.close();
  }
}
