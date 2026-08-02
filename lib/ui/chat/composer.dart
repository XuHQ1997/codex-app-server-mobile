import 'package:flutter/material.dart';

/// A composer tool that changes what pressing "send" does. Staged via the
/// toolbar and shown as a marker chip above the input until sent or cleared.
enum ComposerTool {
  goal,
  compact;

  String get label => switch (this) {
    ComposerTool.goal => 'Goal',
    ComposerTool.compact => 'Compact',
  };

  IconData get icon => switch (this) {
    ComposerTool.goal => Icons.flag_outlined,
    ComposerTool.compact => Icons.compress,
  };

  /// Whether this tool consumes the text field as its argument. `compact`
  /// takes no argument, so its input is disabled.
  bool get usesText => switch (this) {
    ComposerTool.goal => true,
    ComposerTool.compact => false,
  };
}

/// Message composer: an optional tool toolbar, a marker for the staged tool,
/// a multiline text field, and a send button. While a turn is running the send
/// button becomes an interrupt button.
///
/// Tapping a toolbar tool stages it (shown as a marker chip). Pressing send
/// then dispatches that tool via [onTool] instead of sending a plain message.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.onSend,
    required this.onInterrupt,
    required this.onTool,
    required this.isRunning,
    this.enabled = true,
  });

  final void Function(String text) onSend;
  final VoidCallback onInterrupt;

  /// Invoked when a staged tool is sent. [text] is the trimmed input (the
  /// objective for `goal`; empty for `compact`).
  final void Function(ComposerTool tool, String text) onTool;

  final bool isRunning;
  final bool enabled;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  bool _hasText = false;
  ComposerTool? _staged;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleTool(ComposerTool tool) {
    setState(() => _staged = _staged == tool ? null : tool);
  }

  /// Whether send is currently actionable given the staged tool and text.
  bool get _canSend {
    if (!widget.enabled) return false;
    final tool = _staged;
    if (tool != null && !tool.usesText) return true; // e.g. compact
    return _hasText;
  }

  void _send() {
    final text = _controller.text.trim();
    final tool = _staged;
    if (tool != null) {
      if (tool.usesText && text.isEmpty) return;
      widget.onTool(tool, tool.usesText ? text : '');
    } else {
      if (text.isEmpty) return;
      widget.onSend(text);
    }
    _controller.clear();
    setState(() => _staged = null);
  }

  @override
  Widget build(BuildContext context) {
    final staged = _staged;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _toolMenu(),
            const SizedBox(width: 4),
            Expanded(child: _textField(staged)),
            const SizedBox(width: 6),
            _button(context),
          ],
        ),
      ),
    );
  }

  Widget _toolMenu() {
    return PopupMenuButton<ComposerTool>(
      tooltip: 'Composer tools',
      enabled: widget.enabled,
      icon: const Icon(Icons.add_circle_outline),
      onSelected: _toggleTool,
      itemBuilder: (context) => [
        for (final tool in ComposerTool.values)
          PopupMenuItem(
            value: tool,
            child: Row(
              children: [
                Icon(tool.icon, size: 18),
                const SizedBox(width: 10),
                Text(tool.label),
              ],
            ),
          ),
      ],
    );
  }

  Widget _textField(ComposerTool? staged) {
    final usesText = staged == null || staged.usesText;
    final hint = switch (staged) {
      null => 'Message codex…',
      ComposerTool.goal => 'Describe the goal…',
      ComposerTool.compact => 'Summarize · press send',
    };
    return TextField(
      controller: _controller,
      // Keep the field enabled even for no-text tools (e.g. compact) so the
      // in-field clear pill stays tappable; block typing via readOnly instead.
      // A disabled TextField also disables hit-testing on its prefixIcon.
      enabled: widget.enabled,
      readOnly: !usesText,
      minLines: 1,
      maxLines: 6,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        hintText: hint,
        // When a tool is staged, show a compact single-word pill inside the
        // field instead of a verbose marker banner above it.
        prefixIcon: staged == null ? null : _stagedPill(staged),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
      ),
    );
  }

  /// A compact pill shown inside the text field for the staged tool, e.g.
  /// `goal ×`. Tapping the × clears the staged tool.
  Widget _stagedPill(ComposerTool tool) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tool.label.toLowerCase(),
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 2),
            InkWell(
              onTap: () => setState(() => _staged = null),
              borderRadius: BorderRadius.circular(10),
              child: Icon(
                Icons.close,
                size: 15,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(BuildContext context) {
    if (widget.isRunning) {
      return IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
        icon: const Icon(Icons.stop),
        onPressed: widget.onInterrupt,
        tooltip: 'Interrupt',
      );
    }
    return IconButton.filled(
      icon: const Icon(Icons.arrow_upward),
      onPressed: _canSend ? _send : null,
      tooltip: 'Send',
    );
  }
}
