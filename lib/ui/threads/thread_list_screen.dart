import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../../state/thread_list_controller.dart';
import '../../protocol/thread.dart';
import '../../core/path_utils.dart';
import '../common/connection_banner.dart';

/// Provider for the thread list controller, bound to the active service.
final threadListControllerProvider =
    ChangeNotifierProvider.autoDispose<ThreadListController>((ref) {
  final service = ref.watch(codexServiceProvider);
  final controller = ThreadListController(service!);
  // Kick off the initial load.
  Future.microtask(controller.refresh);
  return controller;
});

class ThreadListScreen extends ConsumerWidget {
  const ThreadListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(codexServiceProvider);
    if (service == null) {
      // Not connected — bounce back to setup.
      return const _NotConnected();
    }
    final controller = ref.watch(threadListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Threads'),
        actions: [
          IconButton(
            tooltip: 'Frame inspector',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => context.push('/inspector'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newThread(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New chat'),
      ),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(child: _buildBody(context, ref, controller)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ThreadListController controller,
  ) {
    if (controller.threads.isEmpty && controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.threads.isEmpty && controller.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load threads:\n${controller.error}'),
        ),
      );
    }
    if (controller.threads.isEmpty) {
      return const Center(child: Text('No threads yet. Start a new chat.'));
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        itemCount: controller.threads.length + (controller.hasMore ? 1 : 0),
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i >= controller.threads.length) {
            controller.loadMore();
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final thread = controller.threads[i];
          return Dismissible(
            key: ValueKey(thread.id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              child: const Icon(Icons.archive, color: Colors.white),
            ),
            confirmDismiss: (_) => _confirmArchive(context),
            onDismissed: (_) => controller.archive(thread.id),
            child: ListTile(
              title: Text(
                thread.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: _subtitle(context, thread),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusChip(status: thread.status),
                  _ThreadMenu(
                    onArchive: () async {
                      if (await _confirmArchive(context) == true) {
                        await controller.archive(thread.id);
                      }
                    },
                    onDelete: () async {
                      if (await _confirmDelete(context) == true) {
                        await controller.delete(thread.id);
                      }
                    },
                  ),
                ],
              ),
              onTap: () => context.push('/chat/${thread.id}'),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _confirmArchive(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive thread?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete thread?'),
        content: const Text(
          'This permanently deletes the thread and its history. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Subtitle line: cwd basename and/or a relative "last active" time.
  Widget? _subtitle(BuildContext context, ThreadSummary thread) {
    final parts = <String>[
      if (thread.cwd != null && thread.cwd!.isNotEmpty) basenameOf(thread.cwd!),
      if (_relativeTime(thread.updatedAtMs) != null) _relativeTime(thread.updatedAtMs)!,
    ];
    if (parts.isEmpty) return null;
    return Text(
      parts.join('  ·  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  /// A compact relative time like "just now", "5m", "3h", "2d", or a date.
  static String? _relativeTime(int? epochMs) {
    if (epochMs == null || epochMs <= 0) return null;
    final then = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final diff = DateTime.now().difference(then);
    if (diff.isNegative) return 'just now';
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${then.year}-${then.month.toString().padLeft(2, '0')}-'
        '${then.day.toString().padLeft(2, '0')}';
  }

  Future<void> _newThread(BuildContext context, WidgetRef ref) async {
    final service = ref.read(codexServiceProvider);
    if (service == null) return;
    try {
      final result = await service.startThread();
      final thread = result['thread'];
      final threadId = thread is Map<String, dynamic> ? thread['id'] as String? : null;
      if (threadId != null && context.mounted) {
        context.push('/chat/$threadId');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start thread: $e')),
        );
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    // Only surface states worth calling out. `notLoaded` and `idle` are the
    // resting states of a thread and add nothing but clutter, so they render
    // nothing.
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      'active' => ('Running', scheme.primary),
      'systemError' => ('Error', scheme.error),
      _ => (null, null),
    };
    if (label == null) return const SizedBox.shrink();
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
      side: BorderSide(color: color!.withValues(alpha: 0.5)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// Overflow menu on each thread row: archive or delete. Delete is styled
/// destructively; both actions confirm via the caller before running.
class _ThreadMenu extends StatelessWidget {
  const _ThreadMenu({required this.onArchive, required this.onDelete});

  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Thread actions',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'archive') onArchive();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'archive',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.archive_outlined),
            title: Text('Archive'),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: scheme.error),
            title: Text('Delete', style: TextStyle(color: scheme.error)),
          ),
        ),
      ],
    );
  }
}

class _NotConnected extends StatelessWidget {
  const _NotConnected();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Not connected'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/setup'),
              child: const Text('Go to setup'),
            ),
          ],
        ),
      ),
    );
  }
}
