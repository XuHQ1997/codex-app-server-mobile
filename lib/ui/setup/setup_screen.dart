import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../data/connection_manager.dart';
import '../../state/providers.dart';

/// Setup / connection screen: pick or define a server profile and connect.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController(text: 'ws://');
  final _tokenController = TextEditingController();
  String? _profileId;
  String _profileName = 'Codex Server';
  bool _obscureToken = true;
  bool _connecting = false;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restoreLastProfile();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _restoreLastProfile() async {
    try {
      final profile = await ref
          .read(settingsRepositoryProvider)
          .loadLastProfile();
      if (!mounted) return;
      if (profile != null) {
        _profileId = profile.id;
        _profileName = profile.name;
        _urlController.text = profile.url;
        _tokenController.text = profile.bearerToken ?? '';
      }
    } catch (_) {
      // Keep the form usable if secure storage is temporarily unavailable.
    } finally {
      if (mounted) {
        setState(() {
          _restoring = false;
        });
      }
    }
  }

  String? _validateUrl(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter a server URL';
    final uri = Uri.tryParse(v);
    if (uri == null) return 'Invalid URL';
    if (uri.scheme != 'ws') return 'URL must start with ws://';
    if (uri.host.isEmpty) return 'URL is missing a host';
    if (!uri.hasPort) return 'URL is missing a port';
    return null;
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _connecting = true);

    final url = _urlController.text.trim();
    final profile = ServerProfile(
      id: _profileId ?? const Uuid().v4(),
      name: _profileName,
      url: url,
      bearerToken: _tokenController.text.trim().isEmpty
          ? null
          : _tokenController.text.trim(),
    );
    _profileId = profile.id;

    final settings = ref.read(settingsRepositoryProvider);
    await settings.saveLastProfile(profile);

    final manager = ref.read(connectionManagerProvider);
    // `connect()` awaits the full handshake, so on return `manager.state` is
    // already the terminal state (ready or failed). Reading it directly avoids
    // a race with the broadcast `states` stream, where the `ready` event can be
    // emitted before we subscribe — which previously left the UI stuck on
    // "Connecting…" even though the log showed "Connected & initialized".
    await manager.connect(profile);
    final result = manager.state;

    if (!mounted) return;
    setState(() => _connecting = false);

    if (result.status == ConnectionStatus.ready) {
      context.go('/threads');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed: ${result.error ?? 'unknown'}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Codex Remote'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Frame inspector',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => context.push('/inspector'),
          ),
        ],
      ),
      body: SafeArea(
        child: _restoring
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                Icons.terminal,
                                size: 32,
                                color: colors.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Connect to your Codex server',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Access the app-server running on your WSL '
                              'machine through your private Tailscale network.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        size: 18,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Private network',
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              color: colors.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    controller: _urlController,
                                    decoration: const InputDecoration(
                                      labelText: 'Server address',
                                      hintText: 'ws://100.x.x.x:9999',
                                      helperText:
                                          'Use the WSL host’s Tailscale IP or MagicDNS name.',
                                      prefixIcon: Icon(Icons.dns_outlined),
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.url,
                                    textInputAction: TextInputAction.next,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    validator: _validateUrl,
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    controller: _tokenController,
                                    obscureText: _obscureToken,
                                    decoration: InputDecoration(
                                      labelText: 'Access token',
                                      hintText: 'Optional',
                                      helperText:
                                          'Required when app-server uses --ws-auth.',
                                      prefixIcon: const Icon(
                                        Icons.key_outlined,
                                      ),
                                      border: const OutlineInputBorder(),
                                      suffixIcon: IconButton(
                                        tooltip: _obscureToken
                                            ? 'Show token'
                                            : 'Hide token',
                                        icon: Icon(
                                          _obscureToken
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscureToken = !_obscureToken,
                                        ),
                                      ),
                                    ),
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) {
                                      if (!_connecting) _connect();
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Icon(
                                  Icons.lock_outline,
                                  size: 16,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Address and token are restored securely '
                                    'the next time you open the app.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 52,
                              child: FilledButton.icon(
                                onPressed: _connecting ? null : _connect,
                                icon: _connecting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.arrow_forward),
                                label: Text(
                                  _connecting ? 'Connecting…' : 'Connect',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
