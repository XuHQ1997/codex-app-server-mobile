import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../protocol/approvals/approval_requests.dart';
import '../../protocol/input/user_input.dart';
import '../../protocol/thread_settings.dart';
import '../../core/path_utils.dart';
import '../../state/approval_controller.dart';
import '../../state/providers.dart';
import '../../state/thread_session_controller.dart';
import '../approvals/approval_sheet.dart';
import '../common/connection_banner.dart';
import '../files/file_browser_screen.dart';
import 'composer.dart';
import 'items/item_widget.dart';
import 'plan_strip.dart';
import 'step_group.dart';
import 'thread_settings_sheet.dart';
import 'token_usage_bar.dart';
import 'transcript_grouping.dart';

/// Session controller for a given thread, rebuilt when the RPC client changes
/// (reconnect). On (re)creation it resumes the thread and hydrates history.
///
/// Kept alive across navigation (via [ref.keepAlive]) so its notification
/// subscription survives leaving the chat screen. Otherwise a turn started
/// just before navigating away would drop its `item/*` notifications (no
/// subscriber), making the just-sent message appear to vanish and the turn
/// read as idle on return. It is still recreated on reconnect because it
/// watches the connection providers.
final threadSessionControllerProvider = ChangeNotifierProvider.autoDispose
    .family<ThreadSessionController, String>((ref, threadId) {
      final service = ref.watch(codexServiceProvider);
      final manager = ref.watch(connectionManagerProvider);
      final client = manager.client;
      if (service == null || client == null) {
        throw StateError('Not connected');
      }
      ref.keepAlive();
      final controller = ThreadSessionController(
        threadId: threadId,
        client: client,
        service: service,
      );
      // Resume + hydrate history.
      Future.microtask(() async {
        try {
          final result = await service.resumeThread(threadId);
          controller.hydrateFromThread(result);
          // `thread/resume` can return turns whose items weren't loaded
          // (`itemsView: notLoaded`), so the transcript comes back empty. In that
          // case pull the full history explicitly via `thread/read`.
          if (!controller.hasItems) {
            final full = await service.readThread(threadId, includeTurns: true);
            controller.hydrateFromThread(full);
          }
        } catch (_) {
          // If resume fails (e.g. mid-unload), fall back to read.
          try {
            final result = await service.readThread(
              threadId,
              includeTurns: true,
            );
            controller.hydrateFromThread(result);
          } catch (_) {
            // Both failed: mark hydrated anyway so the UI leaves the loading
            // state instead of spinning forever.
            controller.markHydrated();
          }
        }
      });
      return controller;
    });

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.threadId});

  final String threadId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  bool _sheetOpen = false;

  /// Cleared once we've forced the view to the bottom after history hydrates,
  /// so opening a thread lands on the latest messages instead of the oldest.
  bool _needsInitialScroll = true;

  /// False until the transcript has been settled at the bottom after the
  /// initial history load. While false the transcript is laid out but kept
  /// invisible behind a loader, so the user never sees the multi-frame
  /// jump-to-bottom scroll — the chat fades in already pinned to the latest
  /// message ("load, then enter"). Once true it stays true for the session, so
  /// later sends don't re-trigger the cover.
  bool _transcriptReady = false;

  /// The scroll extent seen on the previous settle attempt, and how many
  /// attempts remain. Because StepGroup/markdown finalize their heights over
  /// several frames after hydration, a single jump-to-bottom lands short; we
  /// re-pin to the bottom across a few frames until the extent stops growing.
  double _lastSettleExtent = -1;
  int _settleAttemptsLeft = 0;
  int _stableSettleFrames = 0;

  /// Whether the viewport is currently pinned near the bottom. Drives both the
  /// auto-follow behavior and the visibility of the scroll-to-bottom button.
  bool _atBottom = true;

  /// Set when new content arrives while the user is scrolled up, so the
  /// scroll-to-bottom button can advertise unread messages.
  bool _hasNewBelow = false;

  /// Item count at the last frame, to detect newly-appended content.
  int _lastItemCount = 0;

  /// Guards the one-time check for an approval that was already pending when we
  /// entered the chat. Scheduling that check on every build (as before) fired
  /// spurious presentations during streaming, flashing the sheet after a send.
  bool _initialApprovalChecked = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atBottom = position.maxScrollExtent - position.pixels < 120;
    if (atBottom != _atBottom) {
      setState(() {
        _atBottom = atBottom;
        if (atBottom) _hasNewBelow = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(codexServiceProvider);
    if (service == null) {
      return const Scaffold(body: Center(child: Text('Not connected')));
    }

    final controller = ref.watch(
      threadSessionControllerProvider(widget.threadId),
    );
    final sessionData = controller.session;

    // Present approvals as they arrive.
    ref.listen<ApprovalController?>(approvalControllerProvider, (_, next) {
      if (next != null) _maybeShowApproval(next);
    });
    // One-shot: catch an approval that was already pending when we entered
    // (the listener above only fires on subsequent changes). Doing this on
    // every build re-triggered during streaming and flashed the sheet.
    if (!_initialApprovalChecked) {
      _initialApprovalChecked = true;
      final approvals = ref.read(approvalControllerProvider);
      if (approvals != null && approvals.current != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _maybeShowApproval(approvals),
        );
      }
    }

    // Track newly-appended content to drive auto-follow and the unread badge.
    final itemCount = sessionData.items.length;
    final hasNewContent = itemCount != _lastItemCount;
    _lastItemCount = itemCount;
    if (hasNewContent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_needsInitialScroll || _atBottom) {
          _scrollToBottom();
        } else if (mounted) {
          setState(() => _hasNewBelow = true);
        }
      });
    }

    final settings = sessionData.settings;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _AppBarTitle(
          name: settings?.name,
          cwd: settings?.cwd,
          model: settings?.model,
          fallbackId: widget.threadId,
        ),
        actions: [
          if (settings?.cwd != null && settings!.cwd!.isNotEmpty)
            IconButton(
              tooltip: 'Browse files',
              icon: const Icon(Icons.folder_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FileBrowserScreen(rootPath: settings.cwd!),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Thread settings',
            icon: const Icon(Icons.tune),
            onPressed: () => _openSettings(controller, sessionData),
          ),
          IconButton(
            tooltip: 'Frame inspector',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => context.push('/inspector'),
          ),
        ],
      ),
      body: Column(
        children: [
          const ConnectionBanner(),
          TokenUsageBar(usage: sessionData.tokenUsage),
          Expanded(
            child: Stack(
              children: [
                if (sessionData.items.isNotEmpty)
                  // Keep the transcript laid out (so the scroll controller has
                  // clients and can settle to the bottom) but invisible until
                  // that settle completes, then fade it in already pinned.
                  AnimatedOpacity(
                    opacity: _transcriptReady ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: _buildTranscript(sessionData),
                  )
                else if (!sessionData.hydrated)
                  const Center(child: CircularProgressIndicator())
                else
                  const Center(child: Text('Send a message to begin.')),
                if (sessionData.items.isNotEmpty && !_transcriptReady)
                  const Center(child: CircularProgressIndicator()),
                if (_transcriptReady && !_atBottom)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _ScrollToBottomButton(
                      hasNew: _hasNewBelow,
                      onPressed: () => _scrollToBottom(animated: true),
                    ),
                  ),
              ],
            ),
          ),
          if (sessionData.turn.error != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(8),
              child: Text('Error: ${sessionData.turn.error}'),
            ),
          PlanStrip(steps: sessionData.plan),
          Composer(
            isRunning: sessionData.turn.isRunning,
            onSend: (text) => _send(text, sessionData.turn.isRunning),
            onInterrupt: controller.interruptTurn,
            onTool: _runTool,
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings(
    ThreadSessionController controller,
    ThreadSession sessionData,
  ) async {
    final service = ref.read(codexServiceProvider);
    if (service == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ThreadSettingsSheet(
        threadId: widget.threadId,
        service: service,
        current: sessionData.settings ?? const ThreadSettings(),
        onChanged: ({model, approvalPolicy, effort}) {
          controller.applySettings(
            model: model,
            approvalPolicy: approvalPolicy,
            effort: effort,
          );
        },
      ),
    );
  }

  /// Renders the transcript: user/agent messages and plans render standalone,
  /// while every run of intermediate steps folds into a [StepGroup] (a live
  /// scroll window while the turn runs, a collapsed bar once it finishes).
  Widget _buildTranscript(ThreadSession sessionData) {
    final entries = buildTranscriptEntries(
      sessionData.items,
      turnRunning: sessionData.turn.isRunning,
    );
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return switch (entry) {
          ItemEntry e => ItemWidget(key: ValueKey(e.item.id), item: e.item),
          StepGroupEntry e => StepGroup(key: ValueKey(e.id), group: e),
        };
      },
    );
  }

  Future<void> _send(String text, bool isRunning) async {
    final service = ref.read(codexServiceProvider);
    if (service == null) return;
    final input = [TextInput(text)];
    try {
      if (isRunning) {
        // Steer the active turn.
        await service.steerTurn(widget.threadId, input);
      } else {
        await service.startTurn(widget.threadId, input);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
      }
    }
  }

  /// Dispatches a composer tool to its app-server method. `goal` sets the
  /// thread objective from the typed text; `compact` summarizes the thread.
  Future<void> _runTool(ComposerTool tool, String text) async {
    final service = ref.read(codexServiceProvider);
    if (service == null) return;
    try {
      switch (tool) {
        case ComposerTool.goal:
          await service.setGoalAndStart(widget.threadId, text);
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Goal started')));
          }
        case ComposerTool.compact:
          await service.compactThread(widget.threadId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Compacting conversation…')),
            );
          }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${tool.label} failed: $e')));
      }
    }
  }

  void _maybeShowApproval(ApprovalController approvals) {
    final current = approvals.current;
    if (current == null || _sheetOpen) return;
    _sheetOpen = true;
    // Keep the last request rendered during the close animation so the sheet
    // never flashes an empty frame between resolving and popping.
    ApprovalRequest? lastShown = current.request;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => AnimatedBuilder(
        animation: approvals,
        builder: (context, _) {
          final pending = approvals.current;
          if (pending == null) {
            // Nothing pending: pop, but keep showing the last request until the
            // pop takes effect rather than rendering an empty sheet.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            });
            final last = lastShown;
            if (last == null) return const SizedBox.shrink();
            return IgnorePointer(
              child: ApprovalSheet(
                request: last,
                pendingCount: 0,
                onDecision: (_) {},
                onPermissions: (_, scope) {},
                onUserInput: (_) {},
              ),
            );
          }
          lastShown = pending.request;
          return ApprovalSheet(
            request: pending.request,
            pendingCount: approvals.pendingCount,
            onDecision: (decision) {
              approvals.respondDecision(decision);
            },
            onPermissions: (perms, scope) {
              approvals.respondPermissions(perms, scope);
            },
            onUserInput: (answers) {
              approvals.respondUserInput(answers);
            },
          );
        },
      ),
    ).whenComplete(() {
      _sheetOpen = false;
      // If more approvals queued while closing, reopen.
      final next = ref.read(approvalControllerProvider);
      if (next != null && next.current != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _maybeShowApproval(next),
        );
      }
    });
  }

  void _scrollToBottom({bool animated = false}) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // On first render after history hydrates, pin to the bottom. The extent
    // keeps growing for a few frames as StepGroup/markdown finalize their
    // heights, so re-pin across several frames until it stabilizes — then
    // reveal the transcript. The settle loop also handles short threads whose
    // content fits on screen (extent stays 0): it stabilizes immediately and
    // still reveals, so the loader can never get stuck.
    if (_needsInitialScroll) {
      _needsInitialScroll = false;
      _settleAttemptsLeft = 10;
      _lastSettleExtent = -1;
      _stableSettleFrames = 0;
      _settleToBottom();
      return;
    }
    if (animated) {
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(position.maxScrollExtent);
    }
    if (_hasNewBelow && mounted) setState(() => _hasNewBelow = false);
  }

  /// Repeatedly jumps to the bottom over successive frames until the max scroll
  /// extent stops changing (content height has settled) or attempts run out,
  /// then reveals the transcript (see [_transcriptReady]).
  void _settleToBottom() {
    if (!mounted || !_scrollController.hasClients) return;
    final extent = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(extent);
    _atBottom = true;
    final stable = (extent - _lastSettleExtent).abs() < 1.0;
    _stableSettleFrames = stable ? _stableSettleFrames + 1 : 0;
    _lastSettleExtent = extent;
    // Require several consecutive stable layouts. Markdown and nested step
    // lists can report one unchanged extent before completing another layout
    // pass; revealing on that first pause leaves the viewport above the real
    // bottom and makes the jump button appear immediately on entry.
    if (_stableSettleFrames >= 3 || _settleAttemptsLeft-- <= 0) {
      // Settled: reveal the now bottom-pinned transcript.
      if (!_transcriptReady) setState(() => _transcriptReady = true);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _settleToBottom());
  }
}

/// Compact AppBar title showing the thread name (or id), with the cwd basename
/// and current model as a secondary line so the user always knows where they
/// are and what model is running.
class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({
    required this.name,
    required this.cwd,
    required this.model,
    required this.fallbackId,
  });

  final String? name;
  final String? cwd;
  final String? model;
  final String fallbackId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = (name != null && name!.trim().isNotEmpty) ? name! : 'Chat';
    final subtitleParts = [
      if (cwd != null && cwd!.isNotEmpty) basenameOf(cwd!),
      if (model != null && model!.isNotEmpty) model!,
    ];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        if (subtitleParts.isNotEmpty)
          Text(
            subtitleParts.join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Floating button that scrolls the transcript to the latest message. Shows a
/// small dot badge when new content arrived while scrolled up.
class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({required this.hasNew, required this.onPressed});

  final bool hasNew;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Badge(
      isLabelVisible: hasNew,
      smallSize: 10,
      backgroundColor: scheme.primary,
      child: FloatingActionButton.small(
        heroTag: 'scrollToBottom',
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        elevation: 2,
        onPressed: onPressed,
        child: const Icon(Icons.arrow_downward),
      ),
    );
  }
}
