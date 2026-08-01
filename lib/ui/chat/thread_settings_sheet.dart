import 'package:flutter/material.dart';

import '../../data/codex_service.dart';
import '../../protocol/thread_settings.dart';

/// Bottom sheet for changing a live thread's model, approval policy, and
/// reasoning effort via `thread/settings/update`. Models are fetched lazily
/// from `model/list`. On success [onChanged] is invoked so the caller can
/// optimistically update its local settings.
///
/// Backed by an experimental server method — if the server rejects the update
/// (method not found), the sheet surfaces a clear "not supported" message
/// instead of failing silently.
class ThreadSettingsSheet extends StatefulWidget {
  const ThreadSettingsSheet({
    super.key,
    required this.threadId,
    required this.service,
    required this.current,
    required this.onChanged,
  });

  final String threadId;
  final CodexService service;
  final ThreadSettings current;
  final void Function({
    String? model,
    ApprovalPolicy? approvalPolicy,
    ReasoningEffort? effort,
  }) onChanged;

  @override
  State<ThreadSettingsSheet> createState() => _ThreadSettingsSheetState();
}

class _ThreadSettingsSheetState extends State<ThreadSettingsSheet> {
  List<ModelInfo>? _models;
  String? _modelsError;
  bool _saving = false;

  late String? _model = widget.current.model;
  late ApprovalPolicy? _approval = widget.current.approvalPolicy;
  late ReasoningEffort? _effort = widget.current.effort;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      final models = await widget.service.listModels();
      if (!mounted) return;
      setState(() => _models = models);
    } catch (e) {
      if (!mounted) return;
      setState(() => _modelsError = '$e');
    }
  }

  /// Reasoning efforts supported by the selected model, or a sensible default
  /// set when the model catalog isn't available.
  List<ReasoningEffort> get _effortOptions {
    final model = _models?.where((m) => m.model == _model).firstOrNull;
    final supported = model?.supportedEfforts ?? const [];
    if (supported.isNotEmpty) return supported;
    return const [
      ReasoningEffort.minimal,
      ReasoningEffort.low,
      ReasoningEffort.medium,
      ReasoningEffort.high,
    ];
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // Only send fields that actually changed.
    final model = _model != widget.current.model ? _model : null;
    final approval =
        _approval != widget.current.approvalPolicy ? _approval : null;
    final effort = _effort != widget.current.effort ? _effort : null;
    if (model == null && approval == null && effort == null) {
      Navigator.of(context).pop();
      return;
    }
    try {
      await widget.service.updateThreadSettings(
        widget.threadId,
        model: model,
        approvalPolicy: approval,
        effort: effort,
      );
      widget.onChanged(model: model, approvalPolicy: approval, effort: effort);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final notSupported = '$e'.toLowerCase().contains('method') ||
          '$e'.contains('-32601');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notSupported
              ? 'This server build does not support changing settings mid-thread.'
              : 'Update failed: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, size: 20),
                const SizedBox(width: 8),
                Text('Thread settings', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            _sectionLabel(context, 'Model'),
            _modelSelector(context),
            const SizedBox(height: 16),
            _sectionLabel(context, 'Reasoning effort'),
            _effortSelector(context),
            const SizedBox(height: 16),
            _sectionLabel(context, 'Approval policy'),
            _approvalSelector(context),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );

  Widget _modelSelector(BuildContext context) {
    if (_modelsError != null) {
      // Couldn't fetch the catalog — let the user keep the current model.
      return Text(
        _model ?? 'Unknown model',
        style: const TextStyle(fontWeight: FontWeight.w500),
      );
    }
    final models = _models;
    if (models == null) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    // Ensure the current model is selectable even if hidden from the catalog.
    final ids = models.map((m) => m.model).toSet();
    final current = _model;
    return DropdownButtonFormField<String>(
      initialValue: current != null && ids.contains(current) ? current : null,
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      hint: Text(current ?? 'Select a model'),
      items: [
        for (final m in models)
          DropdownMenuItem(
            value: m.model,
            child: Text(
              m.isDefault ? '${m.displayName} (default)' : m.displayName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) => setState(() {
        _model = v;
        // Reset effort if the new model doesn't support the current one.
        if (v != null && !_effortOptions.contains(_effort)) {
          _effort = null;
        }
      }),
    );
  }

  Widget _effortSelector(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final e in _effortOptions)
          ChoiceChip(
            label: Text(e.label),
            selected: _effort == e,
            onSelected: (_) => setState(() => _effort = e),
          ),
      ],
    );
  }

  Widget _approvalSelector(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RadioGroup<ApprovalPolicy>(
      groupValue: _approval,
      onChanged: (v) => setState(() => _approval = v),
      child: Column(
        children: [
          for (final p in ApprovalPolicy.selectable)
            RadioListTile<ApprovalPolicy>(
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              value: p,
              title: Text(p.label),
              subtitle: Text(
                p.description,
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}
