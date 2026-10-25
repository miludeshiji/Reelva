import 'package:path/path.dart' as p;

import '../domain/media_source_adapter.dart';
import '../domain/source_models.dart';

class BrowsedMediaFile {
  const BrowsedMediaFile({
    required this.entry,
    required this.directoryIds,
    required this.directoryNames,
  });

  final MediaEntry entry;
  final List<String> directoryIds;
  final List<String> directoryNames;
}

/// 复用各协议的目录枚举，保留 SAF 等不透明目录标识。
class SourceBrowser {
  SourceBrowser({required this.source, required this.adapter});

  final MediaSourceConfig source;
  final MediaSourceAdapter adapter;
  final Map<String, Future<List<MediaEntry>>> _directories = {};

  Future<List<MediaEntry>> listDirectory(String id) async {
    try {
      return await (_directories[id] ??= _readDirectory(id));
    } catch (_) {
      _directories.remove(id);
      rethrow;
    }
  }

  void refreshDirectory(String id) => _directories.remove(id);

  Future<List<MediaEntry>> _readDirectory(String id) async {
    try {
      final extensions = source.extensions
          .map((extension) => extension.replaceFirst('.', '').toLowerCase())
          .toSet();
      final excluded = source.excludedDirectories
          .map((directory) => directory.toLowerCase())
          .toSet();
      final entries = await adapter.listEntries(source, id).where((entry) {
        if (entry.name.startsWith('.')) return false;
        if (entry.isDirectory) {
          return !excluded.contains(entry.name.toLowerCase());
        }
        return extensions.contains(
          p.extension(entry.name).replaceFirst('.', '').toLowerCase(),
        );
      }).toList();
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return entries;
    } catch (_) {
      _directories.remove(id);
      rethrow;
    }
  }

  Future<List<BrowsedMediaFile>> collectFiles({
    required List<String> directoryIds,
    required List<String> directoryNames,
  }) async {
    final visited = directoryIds.take(directoryIds.length - 1).toSet();
    final files = <String, BrowsedMediaFile>{};
    final queue = [(directoryIds, directoryNames)];
    for (var index = 0; index < queue.length; index++) {
      final (ids, names) = queue[index];
      if (!visited.add(ids.last)) continue;
      for (final entry in await listDirectory(ids.last)) {
        if (entry.isDirectory) {
          queue.add(([...ids, entry.externalId], [...names, entry.name]));
        } else {
          files.putIfAbsent(
            entry.externalId,
            () => BrowsedMediaFile(
              entry: entry,
              directoryIds: ids,
              directoryNames: names,
            ),
          );
        }
      }
    }
    return files.values.toList();
  }
}
