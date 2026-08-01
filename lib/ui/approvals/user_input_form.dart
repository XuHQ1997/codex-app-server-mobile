import 'dart:async';

import 'package:flutter/material.dart';

import '../../protocol/approvals/approval_requests.dart';

/// Label used for the synthetic "None of the above" option when a question has
/// `isOther: true`. Kept identical to the codex CLI so the model receives the
/// same answer string.
const String kOtherOptionLabel = 'None of the above';

/// Renders one `item/tool/requestUserInput` request as a mobile-native form:
/// each question shows its header/prompt, tappable single-select option rows,
/// and an (optionally masked) free-text field. Multiple questions stack in a
/// scrollable column with a single submit action.
///
/// Answer encoding mirrors the CLI: a selected option contributes its raw
/// `label`, and non-empty free-text is appended as `"user_note: <text>"`.
class UserInputForm extends StatefulWidget {
  const UserInputForm({
    super.key,
    required this.questions,
    required this.onSubmit,
    this.autoResolutionMs,
  });

  final List<UserInputQuestion> questions;

  /// If set, the request auto-resolves with empty answers after this many ms.
  final int? autoResolutionMs;

  /// Called with each question id mapped to its ordered answer strings. An
  /// empty map signals an auto-resolution / dismissal with no answers.
  final void Function(Map<String, List<String>> answers) onSubmit;

  @override
  State<UserInputForm> createState() => _UserInputFormState();
}

class _UserInputFormState extends State<UserInputForm> {
  /// Selected option index per question. For `isOther` questions the value
  /// `options.length` denotes the synthetic "None of the above" option.
  late final List<int?> _selected;

  /// Free-text / notes controller per question.
  late final List<TextEditingController> _notes;

  /// Whether the notes field has been revealed for an option question.
  late final List<bool> _notesShown;

  Timer? _timer;
  Duration? _remaining;

  @override
  void initState() {
    super.initState();
    _selected = List<int?>.filled(widget.questions.length, null);
    _notes = List.generate(
      widget.questions.length,
      (_) => TextEditingController(),
    );
    // Free-text-only questions show their input field immediately.
    _notesShown = widget.questions.map((q) => !q.hasOptions).toList();

    final ms = widget.autoResolutionMs;
    if (ms != null && ms > 0) {
      _remaining = Duration(milliseconds: ms);
      _timer = Timer.periodic(const Duration(seconds: 1), _tick);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _notes) {
      c.dispose();
    }
    super.dispose();
  }

  void _tick(Timer timer) {
    final remaining = _remaining;
    if (remaining == null) return;
    final next = remaining - const Duration(seconds: 1);
    if (next <= Duration.zero) {
      timer.cancel();
      // Auto-resolution submits an empty answer set, matching CLI behavior.
      widget.onSubmit(const {});
      return;
    }
    setState(() => _remaining = next);
  }

  /// Any user interaction cancels the auto-resolution countdown, matching the
  /// CLI which snoozes the timer once the user engages.
  void _snoozeTimer() {
    if (_timer == null) return;
    _timer?.cancel();
    _timer = null;
    setState(() => _remaining = null);
  }

  String? _selectedLabel(UserInputQuestion q, int? idx) {
    if (idx == null || q.options == null) return null;
    final options = q.options!;
    if (idx < options.length) return options[idx].label;
    if (idx == options.length && q.isOther) return kOtherOptionLabel;
    return null;
  }

  void _submit() {
    final answers = <String, List<String>>{};
    for (var i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      final list = <String>[];
      final label = _selectedLabel(q, _selected[i]);
      if (label != null) list.add(label);
      final notes = _notes[i].text.trim();
      if (notes.isNotEmpty) list.add('user_note: $notes');
      answers[q.id] = list;
    }
    widget.onSubmit(answers);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_remaining != null) _countdownBanner(context),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.questions.length; i++)
                  _questionBlock(context, i),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget.questions.length > 1 ? 'Submit answers' : 'Submit answer',
          ),
        ),
      ],
    );
  }

  Widget _countdownBanner(BuildContext context) {
    final secs = _remaining!.inSeconds;
    final text = secs >= 60
        ? 'auto-resolves in ${secs ~/ 60}m ${(secs % 60).toString().padLeft(2, '0')}s'
        : 'auto-resolves in ${secs}s';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 16, color: Colors.redAccent),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.redAccent),
          ),
        ],
      ),
    );
  }

  Widget _questionBlock(BuildContext context, int i) {
    final q = widget.questions[i];
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.questions.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'Question ${i + 1}/${widget.questions.length}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          if (q.header.isNotEmpty)
            Text(q.header, style: theme.textTheme.titleSmall),
          if (q.question.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(q.question),
          ],
          if (q.hasOptions) ...[
            const SizedBox(height: 8),
            ..._optionRows(context, i, q),
            _notesToggle(context, i),
          ],
          if (_notesShown[i]) ...[
            const SizedBox(height: 8),
            _notesField(context, i, q),
          ],
        ],
      ),
    );
  }

  List<Widget> _optionRows(BuildContext context, int i, UserInputQuestion q) {
    final options = q.options!;
    final rows = <Widget>[];
    for (var oi = 0; oi < options.length; oi++) {
      rows.add(_optionTile(
        context,
        questionIndex: i,
        optionIndex: oi,
        label: options[oi].label,
        description: options[oi].description,
      ));
    }
    if (q.isOther) {
      rows.add(_optionTile(
        context,
        questionIndex: i,
        optionIndex: options.length,
        label: kOtherOptionLabel,
        description: 'Optionally, add details in notes.',
      ));
    }
    return rows;
  }

  Widget _optionTile(
    BuildContext context, {
    required int questionIndex,
    required int optionIndex,
    required String label,
    required String description,
  }) {
    final selected = _selected[questionIndex] == optionIndex;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        _snoozeTimer();
        setState(() => _selected[questionIndex] = optionIndex);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notesToggle(BuildContext context, int i) {
    if (_notesShown[i]) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () {
          _snoozeTimer();
          setState(() => _notesShown[i] = true);
        },
        icon: const Icon(Icons.note_add_outlined, size: 18),
        label: const Text('Add notes'),
      ),
    );
  }

  Widget _notesField(BuildContext context, int i, UserInputQuestion q) {
    return TextField(
      controller: _notes[i],
      obscureText: q.isSecret,
      minLines: 1,
      maxLines: q.isSecret ? 1 : 4,
      onTap: _snoozeTimer,
      onChanged: (_) => _snoozeTimer(),
      decoration: InputDecoration(
        hintText: q.hasOptions
            ? 'Add notes'
            : (q.isSecret ? 'Enter value' : 'Type your answer'),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
