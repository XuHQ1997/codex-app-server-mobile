/// Small path helpers shared by the UI. The app-server reports POSIX and
/// Windows (WSL) working directories, so these handle both separators.
library;

/// Returns the last path segment of [path], handling both `/` and `\`
/// separators and ignoring a single trailing separator. E.g.
/// `/home/me/project/` -> `project`, `C:\src\app` -> `app`.
String basenameOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  final trimmed = normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final idx = trimmed.lastIndexOf('/');
  return idx >= 0 ? trimmed.substring(idx + 1) : trimmed;
}

/// True when [path] looks like a Windows path (`C:\...` or backslash-separated).
/// Used to preserve the host's native separator when joining/splitting.
bool _isWindowsPath(String path) =>
    path.contains('\\') || RegExp(r'^[A-Za-z]:').hasMatch(path);

/// Joins [child] (a single directory entry name) onto absolute [base],
/// preserving the host separator style so WSL/POSIX and Windows both work.
String joinPath(String base, String child) {
  final sep = _isWindowsPath(base) ? '\\' : '/';
  final trimmedBase =
      base.endsWith(sep) ? base.substring(0, base.length - 1) : base;
  return '$trimmedBase$sep$child';
}

/// Returns the parent directory of absolute [path], or `null` when [path] is
/// already a filesystem root (`/`, `C:\`). Preserves the host separator.
String? parentOf(String path) {
  final windows = _isWindowsPath(path);
  final sep = windows ? '\\' : '/';
  final normalized = windows ? path.replaceAll('/', '\\') : path;
  final trimmed = normalized.endsWith(sep) && normalized.length > 1
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final idx = trimmed.lastIndexOf(sep);
  if (idx < 0) return null;
  if (windows) {
    // `C:\foo` -> `C:\` (keep the trailing slash on a drive root).
    if (idx <= 2) return trimmed.substring(0, idx + 1);
    return trimmed.substring(0, idx);
  }
  // POSIX: parent of `/foo` is `/` (root); `/` itself has no parent.
  if (idx == 0) return trimmed.length > 1 ? '/' : null;
  return trimmed.substring(0, idx);
}
