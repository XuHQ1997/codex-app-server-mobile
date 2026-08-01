import 'package:codexcli_remote/protocol/items/item.dart';
import 'package:codexcli_remote/ui/chat/transcript_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

UserMessageItem _user(String id) => UserMessageItem(id, text: 'u');
AgentMessageItem _agent(String id) => AgentMessageItem(id, text: 'a');
CommandExecutionItem _cmd(String id) =>
    CommandExecutionItem(id, command: 'ls');
FileChangeItem _edit(String id) => FileChangeItem(id, changes: const []);
WebSearchItem _search(String id) => WebSearchItem(id, query: 'q');
PlanItem _plan(String id) => PlanItem(id, text: 'p');

void main() {
  group('buildTranscriptEntries', () {
    test('folds a turn\'s steps into a group, keeping the final agent reply out',
        () {
      final items = <ThreadItem>[
        _user('u1'),
        _cmd('c1'),
        _edit('e1'),
        _search('s1'),
        _agent('a1'),
      ];
      final entries = buildTranscriptEntries(items);
      expect(entries.length, 3); // user, group, agent
      expect(entries[0], isA<ItemEntry>());
      expect(entries[1], isA<StepGroupEntry>());
      expect(entries[2], isA<ItemEntry>());
      final group = entries[1] as StepGroupEntry;
      expect(group.stepCount, 3);
      expect(group.toolLabels, ['shell', 'edit', 'search']);
      expect(group.id, 'group:c1');
    });

    test('interstitial agent notes fold into the group, only the last is out',
        () {
      // cmd, agent-note, cmd, agent-final : the middle note folds in, the
      // trailing agent message renders standalone.
      final items = <ThreadItem>[
        _user('u1'),
        _cmd('c1'),
        _agent('a1'), // interstitial note
        _cmd('c2'),
        _agent('a2'), // final answer
      ];
      final entries = buildTranscriptEntries(items);
      expect(entries.length, 3); // user, group(c1,a1,c2), agent(a2)
      final group = entries[1] as StepGroupEntry;
      expect(group.items.length, 3); // c1, a1, c2 all folded
      expect(group.stepCount, 2); // only c1 + c2 count as steps
      expect(entries[2], isA<ItemEntry>());
      expect((entries[2] as ItemEntry).item.id, 'a2');
    });

    test('a segment with no trailing agent message is all group', () {
      final items = <ThreadItem>[_user('u1'), _cmd('c1'), _agent('a1'), _cmd('c2')];
      final entries = buildTranscriptEntries(items);
      expect(entries.length, 2); // user, group
      expect((entries[1] as StepGroupEntry).items.length, 3);
    });

    test('folds even a single step', () {
      final items = <ThreadItem>[_user('u1'), _cmd('c1'), _agent('a1')];
      final entries = buildTranscriptEntries(items);
      expect(entries.length, 3);
      expect(entries[1], isA<StepGroupEntry>());
      expect((entries[1] as StepGroupEntry).stepCount, 1);
    });

    test('de-duplicates repeated tool labels in order', () {
      final items = <ThreadItem>[_cmd('c1'), _cmd('c2'), _edit('e1'), _cmd('c3')];
      final group = buildTranscriptEntries(items).single as StepGroupEntry;
      expect(group.stepCount, 4);
      expect(group.toolLabels, ['shell', 'edit']);
    });

    test('trailing group is not live when the turn is idle', () {
      final items = <ThreadItem>[_cmd('c1'), _edit('e1')];
      final group = buildTranscriptEntries(items).single as StepGroupEntry;
      expect(group.live, isFalse);
    });

    test('trailing group is live when the turn is running', () {
      final items = <ThreadItem>[_cmd('c1'), _edit('e1')];
      final group = buildTranscriptEntries(items, turnRunning: true).single
          as StepGroupEntry;
      expect(group.live, isTrue);
    });

    test('while running, the whole trailing segment stays in the live group',
        () {
      // Mid-stream the agent may already be emitting its reply text, but it
      // isn't final yet — it must stay inside the live window, not peel out.
      final items = <ThreadItem>[_cmd('c1'), _agent('a1')];
      final entries = buildTranscriptEntries(items, turnRunning: true);
      expect(entries.length, 1);
      final group = entries[0] as StepGroupEntry;
      expect(group.live, isTrue);
      expect(group.items.length, 2); // cmd + streaming agent text both inside
    });

    test('once the turn finishes, the final agent reply peels out standalone',
        () {
      // Same items, turn now idle: the trailing agent message renders on its own.
      final items = <ThreadItem>[_cmd('c1'), _agent('a1')];
      final entries = buildTranscriptEntries(items);
      expect(entries.length, 2);
      expect(entries[0], isA<StepGroupEntry>());
      expect((entries[0] as StepGroupEntry).live, isFalse);
      expect(entries[1], isA<ItemEntry>());
      expect((entries[1] as ItemEntry).item.id, 'a1');
    });

    test('an already-complete earlier segment peels even while a later turn runs',
        () {
      // First segment is before a user boundary, so it's complete and peels;
      // the trailing segment after the user message is the live one.
      final items = <ThreadItem>[
        _cmd('c1'),
        _agent('a1'), // final reply of the first (complete) turn
        _user('u1'),
        _cmd('c2'),
        _agent('a2'), // still streaming
      ];
      final entries = buildTranscriptEntries(items, turnRunning: true);
      // group(c1) | agent(a1) | user(u1) | liveGroup(c2,a2)
      expect(entries.length, 4);
      expect((entries[0] as StepGroupEntry).live, isFalse);
      expect((entries[1] as ItemEntry).item.id, 'a1');
      expect((entries[2] as ItemEntry).item.id, 'u1');
      final live = entries[3] as StepGroupEntry;
      expect(live.live, isTrue);
      expect(live.items.length, 2);
    });

    test('user messages and plans are hard boundaries between groups', () {
      final items = <ThreadItem>[
        _cmd('c1'),
        _edit('e1'),
        _plan('p1'),
        _cmd('c2'),
        _user('u1'),
        _search('s1'),
      ];
      final entries = buildTranscriptEntries(items);
      expect(entries.length, 5); // group, plan, group, user, group
      expect(entries[0], isA<StepGroupEntry>());
      expect(entries[1], isA<ItemEntry>()); // plan
      expect(entries[2], isA<StepGroupEntry>());
      expect(entries[3], isA<ItemEntry>()); // user
      expect(entries[4], isA<StepGroupEntry>());
    });

    test('empty list yields no entries', () {
      expect(buildTranscriptEntries(const []), isEmpty);
    });
  });
}
