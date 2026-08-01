import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rpc/rpc_client.dart';
import '../../state/providers.dart';

/// Debug screen showing raw JSON-RPC frames on the wire. Useful for capturing
/// fixtures and diagnosing protocol issues.
class FrameInspectorScreen extends ConsumerStatefulWidget {
  const FrameInspectorScreen({super.key});

  @override
  ConsumerState<FrameInspectorScreen> createState() =>
      _FrameInspectorScreenState();
}

class _FrameInspectorScreenState extends ConsumerState<FrameInspectorScreen> {
  final List<RawFrame> _frames = [];
  StreamSubscription<RawFrame>? _sub;

  @override
  void initState() {
    super.initState();
    // Attach to the current RPC client's raw frame stream once available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    final manager = ref.read(connectionManagerProvider);
    final client = manager.client;
    if (client == null) return;
    // Seed with the buffered history so frames that flowed before this screen
    // opened (e.g. the thread/resume round-trip) are visible, newest first.
    setState(() {
      _frames
        ..clear()
        ..addAll(client.recentFrames.reversed);
    });
    _sub = client.rawFrames.listen((frame) {
      if (!mounted) return;
      setState(() {
        _frames.insert(0, frame);
        if (_frames.length > 500) _frames.removeLast();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Frame inspector'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(_frames.clear),
          ),
        ],
      ),
      body: _frames.isEmpty
          ? const Center(child: Text('No frames yet. Connect and interact.'))
          : ListView.separated(
              itemCount: _frames.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final frame = _frames[i];
                final inbound = frame.direction == FrameDirection.inbound;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    inbound ? Icons.south_west : Icons.north_east,
                    color: inbound ? Colors.blue : Colors.green,
                    size: 18,
                  ),
                  title: Text(
                    frame.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  subtitle: Text(frame.timestamp.toIso8601String()),
                  onTap: () => _showFrame(frame),
                );
              },
            ),
    );
  }

  void _showFrame(RawFrame frame) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        builder: (context, controller) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    frame.direction == FrameDirection.inbound
                        ? 'Inbound'
                        : 'Outbound',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: frame.text),
                    ),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  child: SelectableText(
                    frame.text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
