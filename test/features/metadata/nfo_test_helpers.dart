import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/metadata/application/nfo_service.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

/// 界面用例使用虚拟目录；真实文件和协议行为由 NFO 集成用例覆盖。
class FakeNfoService extends Fake implements NfoService {
  int exports = 0;
  bool fail = false;

  @override
  Future<NfoResult> export({
    int? workId,
    List<int>? fileIds,
    bool replaceIdentity = false,
  }) async {
    exports++;
    return fail
        ? const NfoResult(errors: ['目录不可写'])
        : NfoResult(saved: fileIds?.length ?? 1);
  }

  @override
  Future<NfoDirectoryContext?> importDirectory(
    MediaSourceConfig source,
    String directory,
    List<MediaEntry> entries, {
    NfoDirectoryContext? inherited,
    void Function(String)? onError,
  }) async => inherited;
}
