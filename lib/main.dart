import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app.dart';
import 'core/logging.dart';

void main() {
  setupLogging(level: Level.INFO);
  runApp(const ProviderScope(child: CodexRemoteApp()));
}
