import 'package:flutter/material.dart';

import 'compact_step.dart';
import 'transcript_grouping.dart';

/// The fixed max height of the step scroll window, live or expanded. Keeps the
/// intermediate work from dominating the screen while still showing a useful
/// slice that the user can scroll through.
const double _kWindowMaxHeight = 200;

/// Renders a [StepGroupEntry] — a run of intermediate agent steps.
///
/// While the turn is running ([StepGroupEntry.live]) it shows a fixed-height
/// scroll window auto-pinned to the newest step, with a spinner header. Once
/// the turn finishes it collapses to a one-line summary bar (`▶ N steps ·
/// shell, edit`) that expands back into the same scroll window on tap.
///
/// Steps render flat (no bubbles) via [CompactStep] so the narrow window shows
/// as much width as possible.
class StepGroup extends StatefulWidget {
  const StepGroup({super.key, required this.group});

  final StepGroupEntry group;

  @override
  State<StepGroup> createState() => _StepGroupState();
}

class _StepGroupState extends State<StepGroup> {
  final _scrollController = ScrollController();
  bool _expanded = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(StepGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the live window pinned to the newest step as it streams in.
    if (widget.group.live) _autoScroll();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    if (group.live) {
      _autoScroll();
      return _windowContainer(
        context,
        header: _liveHeader(context),
        child: _stepList(),
      );
    }
    // Finished group: collapsed bar, expandable to the scroll window.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _collapsedBar(context),
        if (_expanded)
          _windowContainer(context, child: _stepList()),
      ],
    );
  }

  Widget _stepList() {
    final items = widget.group.items;
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, i) =>
          CompactStep(key: ValueKey(items[i].id), item: items[i]),
    );
  }

  /// The bordered, height-capped container that holds the step list.
  Widget _windowContainer(
    BuildContext context, {
    Widget? header,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?header,
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _kWindowMaxHeight),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _liveHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = widget.group.stepCount;
    final label =
        n == 0 ? 'Working…' : 'Working · $n ${n == 1 ? 'step' : 'steps'}';
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _collapsedBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final group = widget.group;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(
                _expanded ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: scheme.outline,
              ),
              const SizedBox(width: 4),
              Text(
                '${group.stepCount} ${group.stepCount == 1 ? 'step' : 'steps'}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.toolLabels.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
