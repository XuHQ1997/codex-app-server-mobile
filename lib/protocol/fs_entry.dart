/// Filesystem models for the `fs/*` app-server methods used by the file
/// browser. Paths on the wire are plain absolute path strings (not `file://`
/// URIs), matching the server's `AbsolutePathBuf` serialization.
library;

/// A single child returned by `fs/readDirectory`. `fileName` is the entry name
/// only (no path components); callers join it onto the parent directory.
class FsEntry {
  const FsEntry({
    required this.fileName,
    required this.isDirectory,
    required this.isFile,
  });

  final String fileName;
  final bool isDirectory;
  final bool isFile;

  factory FsEntry.fromJson(Map<String, dynamic> json) => FsEntry(
        fileName: json['fileName'] as String? ?? '',
        isDirectory: json['isDirectory'] as bool? ?? false,
        isFile: json['isFile'] as bool? ?? false,
      );

  /// Whether this entry is something other than a plain file or directory
  /// (e.g. a symlink or special file). Rendered but not drillable/previewable.
  bool get isOther => !isDirectory && !isFile;
}

/// Metadata for a single path from `fs/getMetadata`. Timestamps are Unix
/// milliseconds, or `0` when the platform does not report them.
class FsMetadata {
  const FsMetadata({
    required this.isDirectory,
    required this.isFile,
    required this.isSymlink,
    required this.createdAtMs,
    required this.modifiedAtMs,
  });

  final bool isDirectory;
  final bool isFile;
  final bool isSymlink;
  final int createdAtMs;
  final int modifiedAtMs;

  factory FsMetadata.fromJson(Map<String, dynamic> json) => FsMetadata(
        isDirectory: json['isDirectory'] as bool? ?? false,
        isFile: json['isFile'] as bool? ?? false,
        isSymlink: json['isSymlink'] as bool? ?? false,
        createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
        modifiedAtMs: (json['modifiedAtMs'] as num?)?.toInt() ?? 0,
      );
}
