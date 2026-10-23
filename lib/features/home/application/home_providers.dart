import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/domain/library_work.dart';
import '../../sources/application/source_providers.dart';

/// 首页最近添加影视作品流 Provider（默认获取前 20 条，按创建时间倒序）
final recentWorksProvider = StreamProvider.autoDispose<List<LibraryWork>>((
  ref,
) {
  final repo = ref.watch(mediaLibraryRepositoryProvider);
  return repo.watchRecentWorks(limit: 20);
});
