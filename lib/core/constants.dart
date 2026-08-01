/// App-wide constants for the codex app-server client.
library;

class AppConstants {
  AppConstants._();

  /// Identifies this client to the app-server (`initialize.clientInfo.name`).
  static const clientName = 'codexcli_remote';
  static const clientTitle = 'Codex Remote';
  static const clientVersion = '1.0.0';

  /// Default JSON-RPC request timeout.
  static const requestTimeout = Duration(seconds: 30);

  /// WebSocket application-level ping interval to detect half-open sockets.
  static const pingInterval = Duration(seconds: 20);

  /// Reconnect backoff bounds.
  static const reconnectBaseDelay = Duration(milliseconds: 500);
  static const reconnectMaxDelay = Duration(seconds: 30);
}
