import 'package:codexcli_remote/data/connection_manager.dart';
import 'package:codexcli_remote/data/settings_repository.dart';
import 'package:codexcli_remote/state/providers.dart';
import 'package:codexcli_remote/ui/setup/setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository(this.profile);

  final ServerProfile? profile;

  @override
  Future<ServerProfile?> loadLastProfile() async => profile;
}

void main() {
  testWidgets('restores the last server address and token', (tester) async {
    final repository = _FakeSettingsRepository(
      const ServerProfile(
        id: 'server-1',
        name: 'WSL',
        url: 'ws://100.64.0.10:9999',
        bearerToken: 'saved-token',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: SetupScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .toList();
    expect(fields, hasLength(2));
    expect(fields[0].controller.text, 'ws://100.64.0.10:9999');
    expect(fields[1].controller.text, 'saved-token');
    expect(find.textContaining('wss://'), findsNothing);
    expect(find.textContaining('self-signed'), findsNothing);
    expect(find.textContaining('plaintext'), findsNothing);
  });

  testWidgets('defaults to a ws address when no profile exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _FakeSettingsRepository(null),
          ),
        ],
        child: const MaterialApp(home: SetupScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final address = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .first;
    expect(address.controller.text, 'ws://');
  });
}
