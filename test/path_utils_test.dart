import 'package:codexcli_remote/core/path_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('basenameOf', () {
    test('returns the last POSIX segment', () {
      expect(basenameOf('/home/me/project'), 'project');
    });

    test('ignores a single trailing slash', () {
      expect(basenameOf('/home/me/project/'), 'project');
    });

    test('handles Windows/WSL backslashes', () {
      expect(basenameOf(r'C:\src\app'), 'app');
    });

    test('returns the input when there is no separator', () {
      expect(basenameOf('project'), 'project');
    });

    test('handles a bare root', () {
      expect(basenameOf('/'), '');
    });
  });

  group('joinPath', () {
    test('joins a child onto a POSIX directory', () {
      expect(joinPath('/home/me', 'project'), '/home/me/project');
    });

    test('avoids double separators when base ends in slash', () {
      expect(joinPath('/home/me/', 'project'), '/home/me/project');
    });

    test('joins from a POSIX root', () {
      expect(joinPath('/', 'etc'), '/etc');
    });

    test('preserves Windows separators', () {
      expect(joinPath(r'C:\src', 'app'), r'C:\src\app');
    });
  });

  group('parentOf', () {
    test('returns the parent of a POSIX directory', () {
      expect(parentOf('/home/me/project'), '/home/me');
    });

    test('parent of a top-level dir is the root', () {
      expect(parentOf('/home'), '/');
    });

    test('root has no parent', () {
      expect(parentOf('/'), isNull);
    });

    test('ignores a trailing slash', () {
      expect(parentOf('/home/me/project/'), '/home/me');
    });

    test('returns the drive root for a top-level Windows dir', () {
      expect(parentOf(r'C:\src'), r'C:\');
    });

    test('returns the parent of a nested Windows dir', () {
      expect(parentOf(r'C:\src\app'), r'C:\src');
    });
  });
}
