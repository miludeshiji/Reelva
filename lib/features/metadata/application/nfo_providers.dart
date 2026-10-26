import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    try {
      final result = await service.export(
        workId: workId,
        fileIds: fileIds,
        replaceIdentity: replaceIdentity,
      );
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
    } catch (_) {
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
