import 'package:logging/logging.dart';

/// Configures a single root logging listener. Call once from `main`.
void setupLogging({Level level = Level.INFO}) {
  Logger.root.level = level;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print(
      '${record.time.toIso8601String()} '
      '[${record.level.name}] ${record.loggerName}: ${record.message}'
      '${record.error != null ? ' -- ${record.error}' : ''}',
    );
  });
}

Logger appLogger(String name) => Logger(name);
