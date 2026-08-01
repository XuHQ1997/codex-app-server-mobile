import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/path_utils.dart';
import '../../data/codex_service.dart';
import '../../protocol/fs_entry.dart';
import '../../state/providers.dart';
import 'file_preview_screen.dart';

/// Read-only browser for the app-server host's working tree, rooted at the
/// thread's cwd. Directories drill down in place (hardware back walks up the
/// tree, then pops the screen at the root); files open a [FilePreviewScreen].
class FileBrowserScreen extends ConsumerStatefulWidget {
  const FileBrowserScreen({super.key, required this.rootPath});

  /// Absolute directory the browser starts in and cannot navigate above.
  final String rootPath;

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen> {
  late String _path = widget.rootPath;
  Future<List<FsEntry>>? _listing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final service = ref.read(codexServiceProvider);
    if (service == null) {
      // Block body (not arrow): the setState closure must return void. An arrow
      // returns the assigned Future and trips Flutter's "setState callback
      // returned a Future" assertion.
      setState(() {
        _listing = Future.value(const []);
      });
      return;
    }
    setState(() {
      _listing = _fetchSorted(service, _path);
    });
  }

  Future<List<FsEntry>> _fetchSorted(CodexService service, String path) async {
    final entries = await service.readDirectory(path);
    // Directories first, then files, each case-insensitively by name.
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
    });
    return entries;
  }

  void _enter(FsEntry entry) {
    final childPath = joinPath(_path, entry.fileName);
    if (entry.isDirectory) {
      setState(() => _path = childPath);
      _load();
    } else if (entry.isFile) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FilePreviewScreen(path: childPath),
        ),
      );
    }
  }

  /// Whether the current directory is the browser root (can't navigate above
  /// it). The browser never walks above [widget.rootPath], so equality is the
  /// only condition.
  bool get _atRoot => _path == widget.rootPath;

  void _goUp() {
    if (_atRoot) return;
    final parent = parentOf(_path);
    if (parent == null) return;
    setState(() => _path = parent);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: _PathTitle(path: _path, rootPath: widget.rootPath),
          leading: _atRoot
              ? null
              : IconButton(
                  tooltip: 'Up',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: _goUp,
                ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
        ),
        body: FutureBuilder<List<FsEntry>>(
          future: _listing,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorView(error: snapshot.error!, onRetry: _load);
            }
            final entries = snapshot.data ?? const [];
            if (entries.isEmpty) {
              return const _EmptyView();
            }
            return RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  return _EntryTile(entry: entry, onTap: () => _enter(entry));
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// AppBar title: the current directory name over its path relative to root.
class _PathTitle extends StatelessWidget {
  const _PathTitle({required this.path, required this.rootPath});

  final String path;
  final String rootPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = basenameOf(path);
    // Show where we are relative to the root, so deep nesting stays legible.
    final relative = path == rootPath
        ? path
        : path.startsWith(rootPath)
            ? '…${path.substring(rootPath.length)}'
            : path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
        Text(
          relative,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFamily: 'monospace',
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final FsEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _iconFor(context, entry);
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(
        entry.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: entry.isDirectory
          ? const Icon(Icons.chevron_right, size: 20)
          : null,
      // Symlinks/special files are shown but not actionable.
      enabled: !entry.isOther,
      onTap: entry.isOther ? null : onTap,
    );
  }

  (IconData, Color?) _iconFor(BuildContext context, FsEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    if (entry.isDirectory) return (Icons.folder, scheme.primary);
    if (entry.isOther) return (Icons.link, scheme.onSurfaceVariant);
    return (_fileIcon(entry.fileName), scheme.onSurfaceVariant);
  }

  IconData _fileIcon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (kImageExtensions.contains(ext)) return Icons.image_outlined;
    if (kCodeExtensions.contains(ext)) return Icons.code;
    if (ext == 'md' || ext == 'markdown') return Icons.article_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Scrollable so pull-to-refresh still works on empty dirs.
      children: const [
        SizedBox(height: 120),
        Center(child: Text('Empty directory')),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
