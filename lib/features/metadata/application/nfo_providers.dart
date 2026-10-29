import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../sources/application/source_providers.dart';
import 'nfo_service.dart';

final nfoServiceProvider = Provider<NfoService>(
  (ref) => NfoService(
    repository: ref.watch(mediaLibraryRepositoryProvider),
    adapters: ref.watch(sourceAdaptersProvider),
    http: ref.watch(remoteHttpClientProvider),
  ),
);

class NfoTaskState {
  const NfoTaskState({this.running = false, this.result});
  final bool running;
  final NfoResult? result;
}

class NfoController extends Notifier<NfoTaskState> {
  int _active = 0;
  @override
  NfoTaskState build() => const NfoTaskState();

  void reportError(String message) {
    if (!ref.mounted) return;
    state = NfoTaskState(
      running: state.running,
      result: NfoResult(
        saved: state.result?.saved ?? 0,
        errors: {...?state.result?.errors, message}.toList(),
      ),
    );
  }

  Future<NfoResult> export({
    int? workId,
    List<int>? fileIds,
    bool replaceIdentity = false,
  }) async {
    final service = ref.read(nfoServiceProvider);
    _active++;
    final explicit = workId == null && fileIds == null;
    state = NfoTaskState(running: true, result: explicit ? null : state.result);
    final watch = Stopwatch()..start();
    AppLogger.instance.info(
      '开始保存目录元数据：workId=$workId，选中文件=${fileIds?.length ?? '全部'}',
      module: 'NFO',
    );
    try {
      final result = await service.export(
        workId: workId,
        fileIds: fileIds,
        replaceIdentity: replaceIdentity,
      );
      final summary =
          '目录元数据保存结束：已保存=${result.saved}，错误=${result.errors.length}，耗时=${watch.elapsedMilliseconds}ms';
      if (result.errors.isEmpty) {
        AppLogger.instance.info(summary, module: 'NFO');
      } else {
        AppLogger.instance.warning(summary, module: 'NFO');
      }
      if (ref.mounted) {
        state = NfoTaskState(
          running: true,
          result: NfoResult(
            saved: (state.result?.saved ?? 0) + result.saved,
            errors: {...?state.result?.errors, ...result.errors}.toList(),
          ),
        );
      }
      return result;
    } catch (error, stack) {
      AppLogger.instance.error(
        '目录元数据保存失败',
        module: 'NFO',
        error: error,
        stackTrace: stack,
      );
      const message = '目录元数据保存失败，请检查媒体源权限后重试';
      reportError(message);
      return const NfoResult(errors: [message]);
    } finally {
      _active--;
      if (ref.mounted) {
        state = NfoTaskState(running: _active > 0, result: state.result);
      }
    }
  }
}

final nfoControllerProvider = NotifierProvider<NfoController, NfoTaskState>(
  NfoController.new,
);
