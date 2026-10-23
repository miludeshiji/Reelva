import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sources/application/source_providers.dart';
import '../domain/playback_progress.dart';
import '../infrastructure/playback_progress_repository.dart';

export '../domain/playback_progress.dart';
export '../infrastructure/playback_progress_repository.dart';
export 'progress_player_engine.dart';

/// 播放进度仓储 Provider
final playbackProgressRepositoryProvider = Provider<PlaybackProgressRepository>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    return PlaybackProgressRepository(db: db);
  },
);

/// 首页「继续观看 (Continue Watching)」展架数据流 Provider
final continueWatchingProvider = StreamProvider<List<ContinueWatchingEntry>>((
  ref,
) {
  final repo = ref.watch(playbackProgressRepositoryProvider);
  return repo.watchContinueWatching(limit: 20);
});
