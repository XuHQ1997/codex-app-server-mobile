/// A minimal bidirectional string transport abstraction.
///
/// Kept transport-agnostic so the RPC layer can be unit-tested against an
/// in-memory implementation without a real socket.
abstract class WsTransport {
  /// Inbound frames. Each event is exactly one JSON-RPC message (one WebSocket
  /// text frame on the wire).
  Stream<String> get incoming;

  /// Resolves when the underlying connection has closed (for any reason).
  Future<void> get done;

  /// Sends one JSON-RPC message as a single text frame.
  void send(String message);

  /// Opens the connection. Throws on failure.
  Future<void> connect();

  /// Closes the connection.
  Future<void> close();
}
