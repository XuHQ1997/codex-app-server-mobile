import 'package:codexcli_remote/protocol/thread.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThreadSummary.fromJson', () {
    test('parses status as a tagged-union object', () {
      // ThreadStatus is #[serde(tag = "type")] -> {"type": "..."}.
      final t = ThreadSummary.fromJson({
        'id': 'thr_1',
        'preview': 'hello',
        'status': {'type': 'active', 'activeFlags': []},
        'cwd': '/tmp',
      });
      expect(t.status, 'active');
      expect(t.isActive, isTrue);
    });

    test('parses notLoaded status object', () {
      final t = ThreadSummary.fromJson({
        'id': 'thr_2',
        'preview': 'x',
        'status': {'type': 'notLoaded'},
      });
      expect(t.status, 'notLoaded');
    });

    test('still accepts a bare string status for robustness', () {
      final t = ThreadSummary.fromJson({'id': 'a', 'status': 'idle'});
      expect(t.status, 'idle');
    });

    test('converts second-based timestamps to ms', () {
      final t = ThreadSummary.fromJson({
        'id': 'a',
        'updatedAt': 1780000000,
      });
      expect(t.updatedAtMs, 1780000000 * 1000);
    });

    test('displayName falls back preview -> id', () {
      expect(
        ThreadSummary.fromJson({'id': 'a', 'preview': 'Fix the bug'}).displayName,
        'Fix the bug',
      );
      expect(ThreadSummary.fromJson({'id': 'a'}).displayName, 'a');
    });
  });

  group('ThreadListPage.fromJson', () {
    test('parses a flat data array of threads (real schema shape)', () {
      final page = ThreadListPage.fromJson({
        'data': [
          {
            'id': 'thr_1',
            'preview': 'first',
            'status': {'type': 'notLoaded'},
          },
          {
            'id': 'thr_2',
            'preview': 'second',
            'status': {'type': 'active', 'activeFlags': ['waitingOnApproval']},
          },
        ],
        'nextCursor': 'cursor123',
      });
      expect(page.threads.length, 2);
      expect(page.threads[1].status, 'active');
      expect(page.nextCursor, 'cursor123');
    });
  });
}
