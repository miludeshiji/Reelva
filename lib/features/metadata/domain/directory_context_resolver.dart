import 'package:path/path.dart' as p;

/// 只解释适配器定义的定位符，不从 URL 参数或不透明文档 ID 猜测目录。
class DirectoryContextResolver {
  const DirectoryContextResolver._();

  static List<String> resolve({
    required String kind,
    required String rootLocator,
    required String locator,
  }) {
    String? relative;
    String rootName = '';
    final indexed = Uri.tryParse(locator);
    if (kind == 'androidSaf' && indexed?.scheme == 'reelva-index') {
      final root = Uri.parse(rootLocator);
      if (root.authority == 'com.android.externalstorage.documents') {
        rootName = root.pathSegments.last.split('/').last.split(':').last;
      }
      relative = indexed!.pathSegments.join('/');
    } else if (kind == 'local') {
      final windows = RegExp(r'^[A-Za-z]:|\\').hasMatch(rootLocator);
      final context = p.Context(
        style: windows ? p.Style.windows : p.Style.posix,
      );
      rootName = context.basename(context.normalize(rootLocator));
      if (context.isAbsolute(locator)) {
        if (!context.isWithin(rootLocator, locator)) return const [];
        relative = context.relative(locator, from: rootLocator);
      } else {
        relative = locator;
      }
      relative = relative.replaceAll(r'\', '/');
    } else if (kind == 'webdav') {
      final root = Uri.tryParse(rootLocator);
      if (root == null || root.userInfo.isNotEmpty) return const [];
      rootName =
          root.pathSegments.where((part) => part.isNotEmpty).lastOrNull ?? '';
      if (Uri.tryParse(locator)?.hasScheme ?? true) return const [];
      relative = locator;
    } else if (kind == 'smb') {
      final root = Uri.tryParse(rootLocator);
      if (root == null || root.userInfo.isNotEmpty) return const [];
      final rootPath = '/${root.pathSegments.skip(1).join('/')}';
      final base = rootPath
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList();
      final segments = locator
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList();
      if (base.length >= segments.length) return const [];
      for (var i = 0; i < base.length; i++) {
        if (base[i] != segments[i]) return const [];
      }
      rootName = base.lastOrNull ?? '';
      relative = segments.skip(base.length).join('/');
    } else if (kind == 'androidSaf') {
      final root = Uri.tryParse(rootLocator);
      final entry = Uri.tryParse(locator);
      if (root == null ||
          entry == null ||
          root.authority != entry.authority ||
          root.authority != 'com.android.externalstorage.documents') {
        return const [];
      }
      final rootSegments = root.pathSegments;
      final entrySegments = entry.pathSegments;
      final treeIndex = rootSegments.indexOf('tree');
      final documentIndex = entrySegments.indexOf('document');
      if (treeIndex < 0 ||
          documentIndex < 0 ||
          treeIndex + 1 >= rootSegments.length ||
          documentIndex + 1 >= entrySegments.length) {
        return const [];
      }
      final tree = rootSegments[treeIndex + 1];
      final document = entrySegments[documentIndex + 1];
      if (!document.startsWith('$tree/')) return const [];
      rootName = tree.split('/').last.split(':').last;
      relative = document.substring(tree.length + 1);
    }
    if (relative == null ||
        relative.contains('://') ||
        relative.startsWith('/') ||
        relative.contains(r'\')) {
      return const [];
    }
    final parts = relative.split('/');
    if (parts.any(
      (part) =>
          part.isEmpty ||
          part == '..' ||
          part == '.' ||
          part.contains('\u0000'),
    )) {
      return const [];
    }
    return [
      if (rootName.isNotEmpty && !rootName.contains(':')) rootName,
      ...parts.take(parts.length - 1),
    ];
  }
}
