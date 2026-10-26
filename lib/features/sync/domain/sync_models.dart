import 'package:flutter/foundation.dart';

/// 新记录仅发送观看进度；metadata 用于读取并跳过旧版本的历史批次。
enum SyncRecordKind { progress, metadata }

/// 同步目标全局标识（仅支持 proven TMDB external_ids）
@immutable
class SyncTarget {
  final String workType; // 'movie' 或 'series'
  final int tmdbId;
  final int? seasonNumber;
  final int? episodeNumber;

  const SyncTarget({
    required this.workType,
    required this.tmdbId,
    this.seasonNumber,
    this.episodeNumber,
  });

  /// 全局唯一标识符
  /// movie: `movie:123`
  /// series (metadata): `series:123`
  /// series (progress episode): `series:123:s1e2`
  String get id {
    if (workType == 'movie') {
      return 'movie:$tmdbId';
    }
    if (seasonNumber != null && episodeNumber != null) {
      return 'series:$tmdbId:s${seasonNumber}e$episodeNumber';
    }
    return 'series:$tmdbId';
  }

  Map<String, dynamic> toJson() => {
    'workType': workType,
    'tmdbId': tmdbId,
    if (seasonNumber != null) 'seasonNumber': seasonNumber,
    if (episodeNumber != null) 'episodeNumber': episodeNumber,
  };

  factory SyncTarget.fromJson(Map<String, dynamic> json) {
    final dynamic workTypeRaw = json['workType'];
    if (workTypeRaw is! String ||
        (workTypeRaw != 'movie' && workTypeRaw != 'series')) {
      throw const SyncException('同步目标作品类型无效');
    }
    final dynamic tmdbIdRaw = json['tmdbId'];
    if (tmdbIdRaw is! int || tmdbIdRaw <= 0) {
      throw const SyncException('同步目标标识无效');
    }
    final dynamic seasonNumberRaw = json['seasonNumber'];
    final dynamic episodeNumberRaw = json['episodeNumber'];

    if (seasonNumberRaw != null &&
        (seasonNumberRaw is! int || seasonNumberRaw < 0)) {
      throw const SyncException('季编号格式不合法');
    }
    if (episodeNumberRaw != null &&
        (episodeNumberRaw is! int || episodeNumberRaw < 0)) {
      throw const SyncException('分集编号格式不合法');
    }

    final seasonNumber = seasonNumberRaw as int?;
    final episodeNumber = episodeNumberRaw as int?;

    if (workTypeRaw == 'movie' &&
        (seasonNumber != null || episodeNumber != null)) {
      throw const SyncException('电影目标不可包含季集信息');
    }
    if ((seasonNumber != null && episodeNumber == null) ||
        (seasonNumber == null && episodeNumber != null)) {
      throw const SyncException('剧集分集编号必须成对指定');
    }

    return SyncTarget(
      workType: workTypeRaw,
      tmdbId: tmdbIdRaw,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncTarget &&
          runtimeType == other.runtimeType &&
          workType == other.workType &&
          tmdbId == other.tmdbId &&
          seasonNumber == other.seasonNumber &&
          episodeNumber == other.episodeNumber;

  @override
  int get hashCode =>
      Object.hash(workType, tmdbId, seasonNumber, episodeNumber);

  @override
  String toString() => 'SyncTarget($id)';
}

/// 同步版本（时间戳毫秒 + 32位十六进制设备标识）
/// 遵循 Last-Writer-Wins: 先比对 stamp（时间戳），再比对 deviceId（字典序）
@immutable
class SyncVersion implements Comparable<SyncVersion> {
  final int stamp;
  final String deviceId;

  const SyncVersion({required this.stamp, required this.deviceId});

  static final RegExp _deviceIdRegex = RegExp(r'^[0-9a-f]{32}$');

  @override
  int compareTo(SyncVersion other) {
    final stampComp = stamp.compareTo(other.stamp);
    if (stampComp != 0) {
      return stampComp;
    }
    return deviceId.compareTo(other.deviceId);
  }

  Map<String, dynamic> toJson() => {'stamp': stamp, 'deviceId': deviceId};

  factory SyncVersion.fromJson(Map<String, dynamic> json) {
    final dynamic stampRaw = json['stamp'];
    if (stampRaw is! int || stampRaw < 0) {
      throw const SyncException('同步版本时间戳无效');
    }
    final dynamic deviceIdRaw = json['deviceId'];
    if (deviceIdRaw is! String || !_deviceIdRegex.hasMatch(deviceIdRaw)) {
      throw const SyncException('设备标识格式不合法');
    }
    return SyncVersion(stamp: stampRaw, deviceId: deviceIdRaw);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncVersion &&
          runtimeType == other.runtimeType &&
          stamp == other.stamp &&
          deviceId == other.deviceId;

  @override
  int get hashCode => Object.hash(stamp, deviceId);

  @override
  String toString() => 'SyncVersion(stamp: $stamp, deviceId: $deviceId)';
}

/// 单条同步记录
@immutable
class SyncRecord {
  final SyncTarget target;
  final SyncRecordKind kind;
  final SyncVersion version;
  final Map<String, dynamic> value;

  const SyncRecord({
    required this.target,
    required this.kind,
    required this.version,
    required this.value,
  });

  static final RegExp _posterRegex = RegExp(
    r'^/[a-zA-Z0-9_\-]+\.(jpg|jpeg|png|webp)$',
    caseSensitive: false,
  );

  /// 复合主键: `${kind.name}:${target.id}`
  String get key => '${kind.name}:${target.id}';

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'target': target.toJson(),
    'version': version.toJson(),
    'value': value,
  };

  factory SyncRecord.fromJson(Map<String, dynamic> json) {
    final dynamic kindRaw = json['kind'];
    if (kindRaw is! String) {
      throw const SyncException('同步记录类型缺失或无效');
    }
    final SyncRecordKind kind;
    try {
      kind = SyncRecordKind.values.byName(kindRaw);
    } catch (_) {
      throw const SyncException('同步记录类型缺失或无效');
    }

    final dynamic targetRaw = json['target'];
    if (targetRaw is! Map<String, dynamic>) {
      throw const SyncException('同步目标格式不合法');
    }
    final target = SyncTarget.fromJson(targetRaw);

    final dynamic versionRaw = json['version'];
    if (versionRaw is! Map<String, dynamic>) {
      throw const SyncException('同步版本信息不合法');
    }
    final version = SyncVersion.fromJson(versionRaw);

    final dynamic valueRaw = json['value'];
    if (valueRaw is! Map<String, dynamic>) {
      throw const SyncException('同步数据内容不合法');
    }

    // 校验 Target 与 Kind 匹配约束
    if (kind == SyncRecordKind.metadata) {
      if (target.seasonNumber != null || target.episodeNumber != null) {
        throw const SyncException('元数据同步目标必须为作品级');
      }
    } else if (kind == SyncRecordKind.progress) {
      if (target.workType == 'series' &&
          (target.seasonNumber == null || target.episodeNumber == null)) {
        throw const SyncException('剧集播放进度目标必须指定分集');
      }
    }

    // 白名单字段与类型校验
    final Map<String, dynamic> cleanValue = {};
    if (kind == SyncRecordKind.progress) {
      const allowedKeys = {'positionMs', 'durationMs', 'completed'};
      for (final k in valueRaw.keys) {
        if (!allowedKeys.contains(k)) {
          throw const SyncException('播放进度字段存在未允许的属性');
        }
      }
      final dynamic pos = valueRaw['positionMs'];
      if (pos is! int || pos < 0) {
        throw const SyncException('播放进度时间数据不合法');
      }
      cleanValue['positionMs'] = pos;

      final dynamic dur = valueRaw['durationMs'];
      if (dur is! int || dur < 0) {
        throw const SyncException('播放进度时间数据不合法');
      }
      cleanValue['durationMs'] = dur;

      final dynamic comp = valueRaw['completed'];
      if (comp is! bool) {
        throw const SyncException('播放完成标记格式不合法');
      }
      cleanValue['completed'] = comp;
    } else if (kind == SyncRecordKind.metadata) {
      const allowedKeys = {'title', 'year', 'overview', 'posterPath'};
      for (final k in valueRaw.keys) {
        if (!allowedKeys.contains(k)) {
          throw const SyncException('元数据字段存在未允许的属性');
        }
      }
      final dynamic titleRaw = valueRaw['title'];
      if (titleRaw is! String) {
        throw const SyncException('元数据标题不能为空');
      }
      final title = titleRaw.trim();
      if (title.isEmpty) {
        throw const SyncException('元数据标题不能为空');
      }

      int? year;
      if (valueRaw.containsKey('year')) {
        final dynamic yearRaw = valueRaw['year'];
        if (yearRaw != null) {
          if (yearRaw is! int || yearRaw < 1888 || yearRaw > 2100) {
            throw const SyncException('元数据年份超出有效范围');
          }
          year = yearRaw;
        }
      }

      String? overview;
      if (valueRaw.containsKey('overview')) {
        final dynamic overviewRaw = valueRaw['overview'];
        if (overviewRaw != null) {
          if (overviewRaw is! String) {
            throw const SyncException('元数据简介格式无效');
          }
          overview = overviewRaw;
        }
      }

      String? posterPath;
      if (valueRaw.containsKey('posterPath')) {
        final dynamic posterRaw = valueRaw['posterPath'];
        if (posterRaw != null) {
          if (posterRaw is! String) {
            throw const SyncException('元数据海报路径格式无效');
          }
          final cleanPoster = posterRaw.trim();
          if (!_posterRegex.hasMatch(cleanPoster)) {
            throw const SyncException('元数据海报路径格式无效');
          }
          posterPath = cleanPoster;
        }
      }

      // 规范化元数据字段，显式写入 4 个键，防止本地省略 null 与远端显式 null 导致回响
      cleanValue['title'] = title;
      cleanValue['year'] = year;
      cleanValue['overview'] = overview;
      cleanValue['posterPath'] = posterPath;
    }

    return SyncRecord(
      target: target,
      kind: kind,
      version: version,
      value: cleanValue,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncRecord &&
          runtimeType == other.runtimeType &&
          target == other.target &&
          kind == other.kind &&
          version == other.version &&
          mapEquals(value, other.value);

  @override
  int get hashCode => Object.hash(
    target,
    kind,
    version,
    Object.hashAllUnordered(
      value.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => 'SyncRecord(key: $key, version: $version)';
}

/// 同步批次
@immutable
class SyncBatch {
  final String deviceId;
  final int sequence;
  final List<SyncRecord> records;

  const SyncBatch({
    required this.deviceId,
    required this.sequence,
    required this.records,
  });

  static final RegExp _deviceIdRegex = RegExp(r'^[0-9a-f]{32}$');

  /// 文件名: `<32lowerhexdevice>-<positive-seq>.json`
  String get fileName => '$deviceId-$sequence.json';

  Map<String, dynamic> toJson() => {
    'version': 1,
    'deviceId': deviceId,
    'sequence': sequence,
    'records': records.map((r) => r.toJson()).toList(),
  };

  factory SyncBatch.fromJson(Map<String, dynamic> json) {
    final dynamic version = json['version'];
    if (version != 1) {
      throw const SyncException('同步数据批次版本不受支持');
    }
    final dynamic deviceId = json['deviceId'];
    if (deviceId is! String || !_deviceIdRegex.hasMatch(deviceId)) {
      throw const SyncException('设备标识格式不合法');
    }
    final dynamic sequence = json['sequence'];
    if (sequence is! int || sequence < 1) {
      throw const SyncException('同步批次序号无效');
    }
    final dynamic recordsRaw = json['records'];
    if (recordsRaw is! List) {
      throw const SyncException('同步批次记录列表格式不合法');
    }
    final List<SyncRecord> records = [];
    for (final item in recordsRaw) {
      if (item is! Map<String, dynamic>) {
        throw const SyncException('同步批次记录格式不合法');
      }
      records.add(SyncRecord.fromJson(item));
    }

    return SyncBatch(deviceId: deviceId, sequence: sequence, records: records);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncBatch &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          sequence == other.sequence &&
          listEquals(records, other.records);

  @override
  int get hashCode => Object.hash(deviceId, sequence, Object.hashAll(records));

  @override
  String toString() =>
      'SyncBatch(fileName: $fileName, recordCount: ${records.length})';
}

/// 同步异常（安全 toString，绝不泄露远程凭据或内部机密）
class SyncException implements Exception {
  final String message;

  const SyncException(this.message);

  @override
  String toString() => 'SyncException: $message';
}

/// 同步结果统计报告
@immutable
class SyncReport {
  final int uploaded;
  final int downloaded;
  final int applied;
  final int pending;
  final int localOnly;
  final int configurationApplied;

  const SyncReport({
    required this.uploaded,
    required this.downloaded,
    required this.applied,
    required this.pending,
    required this.localOnly,
    this.configurationApplied = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncReport &&
          runtimeType == other.runtimeType &&
          uploaded == other.uploaded &&
          downloaded == other.downloaded &&
          applied == other.applied &&
          pending == other.pending &&
          localOnly == other.localOnly &&
          configurationApplied == other.configurationApplied;

  @override
  int get hashCode => Object.hash(
    uploaded,
    downloaded,
    applied,
    pending,
    localOnly,
    configurationApplied,
  );

  @override
  String toString() =>
      'SyncReport(uploaded: $uploaded, downloaded: $downloaded, applied: $applied, pending: $pending, localOnly: $localOnly)';
}
