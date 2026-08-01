import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/path_utils.dart';
import '../../state/providers.dart';

/// File extensions rendered inline as images.
const kImageExtensions = {
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico',
};

/// File extensions treated as source code / plain text for the text preview.
const kCodeExtensions = {
  'dart', 'rs', 'go', 'py', 'js', 'ts', 'tsx', 'jsx', 'java', 'kt', 'swift',
  'c', 'h', 'cpp', 'hpp', 'cc', 'cs', 'rb', 'php', 'sh', 'bash', 'zsh',
  'json', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'xml', 'html', 'css',
  'scss', 'sql', 'lua', 'r', 'pl', 'txt', 'log', 'env', 'gitignore',
  'dockerfile', 'makefile', 'gradle', 'properties',
};

/// Files above this size are not previewed inline (avoids pulling megabytes
/// over the wire and OOMing the render). base64 roughly inflates by 4/3, so
/// the actual transfer is a bit larger than this decoded cap.
const _kMaxPreviewBytes = 2 * 1024 * 1024; // 2 MiB

/// Read-only preview for a single host file. Text-like files render as
/// selectable monospace; images render inline; everything else shows a
/// "binary / unsupported" placeholder with the byte size.
class FilePreviewScreen extends ConsumerStatefulWidget {
  const FilePreviewScreen({super.key, required this.path});

  final String path;

  @override
  ConsumerState<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends ConsumerState<FilePreviewScreen> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final service = ref.read(codexServiceProvider);
    if (service == null) {
      // Block body so the setState closure returns void (an arrow would return
      // the Future and trip Flutter's setState-returned-a-Future assertion).
      setState(() {
        _bytes = Future.error('Not connected');
      });
      return;
    }
    setState(() {
      _bytes = service.readFile(widget.path).then(Uint8List.fromList);
    });
  }

  String get _ext {
    final name = basenameOf(widget.path);
    return name.contains('.') ? name.split('.').last.toLowerCase() : '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          basenameOf(widget.path),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _PreviewError(error: snapshot.error!, onRetry: _load);
          }
          final data = snapshot.data ?? Uint8List(0);
          return _buildContent(context, data);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, Uint8List data) {
    if (data.length > _kMaxPreviewBytes) {
      return _Placeholder(
        icon: Icons.description_outlined,
        title: 'File too large to preview',
        subtitle: '${_formatBytes(data.length)} · ${widget.path}',
      );
    }
    if (kImageExtensions.contains(_ext)) {
      return InteractiveViewer(
        maxScale: 8,
        child: Center(child: Image.memory(data)),
      );
    }
    // Decode as UTF-8; fall back to a binary placeholder on invalid bytes or
    // when NUL bytes indicate the content isn't text.
    if (data.contains(0)) {
      return _Placeholder(
        icon: Icons.memory,
        title: 'Binary file',
        subtitle: '${_formatBytes(data.length)} · not previewable',
      );
    }
    String? text;
    try {
      text = utf8.decode(data);
    } on FormatException {
      text = null;
    }
    if (text == null) {
      return _Placeholder(
        icon: Icons.memory,
        title: 'Binary file',
        subtitle: '${_formatBytes(data.length)} · not previewable',
      );
    }
    return _TextView(text: text);
  }
}

class _TextView extends StatelessWidget {
  const _TextView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          text.isEmpty ? '(empty file)' : text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.error, required this.onRetry});

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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
