import 'package:codexcli_remote/protocol/items/item.dart';
import 'package:codexcli_remote/state/item_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ItemStore', () {
    test('inserts items in first-seen order', () {
      final store = ItemStore();
      store.onItemStarted({'id': 'a', 'type': 'agentMessage', 'text': ''});
      store.onItemStarted({'id': 'b', 'type': 'agentMessage', 'text': ''});
      expect(store.items.map((i) => i.id).toList(), ['a', 'b']);
    });

    test('agentMessage deltas accumulate', () {
      final store = ItemStore();
      store.onItemStarted({'id': 'm', 'type': 'agentMessage', 'text': ''});
      store.onAgentMessageDelta('m', 'Hel');
      store.onAgentMessageDelta('m', 'lo');
      final item = store.byId('m') as AgentMessageItem;
      expect(item.text, 'Hello');
    });

    test('delta before item/started lazily creates the item', () {
      final store = ItemStore();
      store.onAgentMessageDelta('x', 'streamed');
      final item = store.byId('x') as AgentMessageItem;
      expect(item.text, 'streamed');
    });

    test('item/completed is authoritative over streamed deltas', () {
      final store = ItemStore();
      store.onItemStarted({'id': 'm', 'type': 'agentMessage', 'text': ''});
      store.onAgentMessageDelta('m', 'partial');
      store.onItemCompleted({'id': 'm', 'type': 'agentMessage', 'text': 'FINAL'});
      final item = store.byId('m') as AgentMessageItem;
      expect(item.text, 'FINAL');
      // Order preserved, no duplicate.
      expect(store.items.length, 1);
    });

    test('reasoning summary deltas target the correct index', () {
      final store = ItemStore();
      store.onItemStarted({'id': 'r', 'type': 'reasoning'});
      store.onReasoningSummaryDelta('r', 0, 'first');
      store.onReasoningSummaryPartAdded('r');
      store.onReasoningSummaryDelta('r', 1, 'second');
      final item = store.byId('r') as ReasoningItem;
      expect(item.summary[0], 'first');
      expect(item.summary[1], 'second');
    });

    test('command output deltas accumulate', () {
      final store = ItemStore();
      store.onItemStarted({
        'id': 'c',
        'type': 'commandExecution',
        'command': 'ls',
        'status': 'inProgress',
      });
      store.onCommandOutputDelta('c', 'line1\n');
      store.onCommandOutputDelta('c', 'line2\n');
      final item = store.byId('c') as CommandExecutionItem;
      expect(item.output, 'line1\nline2\n');
    });

    test('fileChange patchUpdated replaces changes', () {
      final store = ItemStore();
      store.onItemStarted({
        'id': 'f',
        'type': 'fileChange',
        'changes': [],
        'status': 'inProgress',
      });
      store.onFileChangePatchUpdated('f', [
        {'path': 'a.dart', 'kind': 'update', 'diff': '@@ -1 +1 @@'},
      ]);
      final item = store.byId('f') as FileChangeItem;
      expect(item.changes.length, 1);
      expect(item.changes.first.path, 'a.dart');
    });

    test('unknown item types fall back to UnknownItem', () {
      final store = ItemStore();
      store.onItemStarted({'id': 'z', 'type': 'someNewItemType', 'foo': 'bar'});
      expect(store.byId('z'), isA<UnknownItem>());
    });
  });
}
