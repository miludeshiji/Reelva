import 'package:flutter/foundation.dart';

/// 媒体文件名解析结果领域模型
@immutable
class ParsedMediaFilename {
  const ParsedMediaFilename({
    required this.rawName,
    required this.title,
    this.secondaryTitle,
    this.year,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeNumbers = const [],
    this.isMultiEpisode = false,
    this.isSpecialOrOva = false,
    this.episodeTitle,
    this.editionLabel,
    this.resolution,
    this.type,
    this.isConfident = false,
    this.isAmbiguous = false,
  });

  /// 原始文件名（包含扩展名）
  final String rawName;

  /// 主标题（已清理无意义分隔符与压制标签）
  final String title;

  /// 次要标题（如中英文混排时的英文外文标题）
  final String? secondaryTitle;

  /// 发行年份（1900 - 2099）
  final int? year;

  /// 季号（剧集有效；特辑/OVA 为 0）
  final int? seasonNumber;

  /// 确定集号（单集有效；多集或不确定集号时为 null）
  final int? episodeNumber;

  /// 多集覆盖的集号列表（如 S01E01-E02 为 [1, 2]）
  final List<int> episodeNumbers;

  /// 是否为多集文件（如 S01E01-E02、01x01-02）
  final bool isMultiEpisode;

  /// 是否为 OVA、SP 或特典候选
  final bool isSpecialOrOva;

  /// 分集独立标题（如 S01E05.Gray.Matter 中的 Gray Matter）
  final String? episodeTitle;

  /// 版本版本标签（如 Director's Cut、Extended、Remastered）
  final String? editionLabel;

  /// 分辨率（如 4K, 1080p, 720p）
  final String? resolution;

  /// 作品类型识别：'movie'、'series' 或 null（不确定）
  final String? type;

  /// 是否具有高置信度（具备清晰且无歧义的影视剧集特征与年份/集号）
  final bool isConfident;

  /// 是否结构模糊/无年份/难以确定类型
  final bool isAmbiguous;

  ParsedMediaFilename copyWith({
    String? rawName,
    String? title,
    String? secondaryTitle,
    int? year,
    int? seasonNumber,
    int? episodeNumber,
    List<int>? episodeNumbers,
    bool? isMultiEpisode,
    bool? isSpecialOrOva,
    String? episodeTitle,
    String? editionLabel,
    String? resolution,
    String? type,
    bool? isConfident,
    bool? isAmbiguous,
  }) {
    return ParsedMediaFilename(
      rawName: rawName ?? this.rawName,
      title: title ?? this.title,
      secondaryTitle: secondaryTitle ?? this.secondaryTitle,
      year: year ?? this.year,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      episodeNumbers: episodeNumbers ?? this.episodeNumbers,
      isMultiEpisode: isMultiEpisode ?? this.isMultiEpisode,
      isSpecialOrOva: isSpecialOrOva ?? this.isSpecialOrOva,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      editionLabel: editionLabel ?? this.editionLabel,
      resolution: resolution ?? this.resolution,
      type: type ?? this.type,
      isConfident: isConfident ?? this.isConfident,
      isAmbiguous: isAmbiguous ?? this.isAmbiguous,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedMediaFilename &&
          runtimeType == other.runtimeType &&
          rawName == other.rawName &&
          title == other.title &&
          secondaryTitle == other.secondaryTitle &&
          year == other.year &&
          seasonNumber == other.seasonNumber &&
          episodeNumber == other.episodeNumber &&
          listEquals(episodeNumbers, other.episodeNumbers) &&
          isMultiEpisode == other.isMultiEpisode &&
          isSpecialOrOva == other.isSpecialOrOva &&
          episodeTitle == other.episodeTitle &&
          editionLabel == other.editionLabel &&
          resolution == other.resolution &&
          type == other.type &&
          isConfident == other.isConfident &&
          isAmbiguous == other.isAmbiguous;

  @override
  int get hashCode => Object.hash(
    rawName,
    title,
    secondaryTitle,
    year,
    seasonNumber,
    episodeNumber,
    Object.hashAll(episodeNumbers),
    isMultiEpisode,
    isSpecialOrOva,
    episodeTitle,
    editionLabel,
    resolution,
    type,
    isConfident,
    isAmbiguous,
  );

  @override
  String toString() =>
      'ParsedMediaFilename(title: "$title", type: $type, year: $year, s: $seasonNumber, e: $episodeNumber, confident: $isConfident)';
}

/// 媒体文件名智能解析器
class MediaFilenameParser {
  const MediaFilenameParser._();

  static final RegExp _extRegex = RegExp(
    r'\.(mkv|mp4|avi|mov|m4v|ts|webm|flv|wmv|iso)$',
    caseSensitive: false,
  );

  static final RegExp _yearRegex = RegExp(r'(?<!\d)(19\d\d|20\d\d)(?!\d)');

  static final RegExp _resolutionRegex = RegExp(
    r'(?<!\w)(4k|2160p|1080p|1080i|720p|576p|480p|uhd|fhd|hd)(?!\w)',
    caseSensitive: false,
  );

  static final RegExp _editionRegex = RegExp(
    r"(?<!\w)(director'?s[\.\s_-]*cut|extended([\.\s_-]*cut)?|remastered|theatrical([\.\s_-]*cut)?|unrated|special[\.\s_-]*edition|imax|criterion)(?!\w)",
    caseSensitive: false,
  );

  static final RegExp _junkRegex = RegExp(
    r'(?<!\w)(bluray|blu-ray|bdrip|brrip|web-dl|webdl|webrip|web|hdrip|dvdrip|remux|x264|x265|h264|h265|hevc|avc|10bit|hdr10\+|hdr10|hdr|dolby[\.\s_-]*vision|dovi|dv|aac|ac3|dts-hd|dts|truehd|atmos|flac|eac3|ddp5\.1|dd5\.1)(?!\w)',
    caseSensitive: false,
  );

  // S01E05 or S01E01-E02 or S01E01-02 or S01E01E02
  static final RegExp _sxxExxRegex = RegExp(
    r'[sS](?<season>\d{1,2})[\.\s_-]*[eE](?<ep1>\d{1,3})(?:[\.\s_-]*(?:[eE]|[-~])(?<ep2>\d{1,3}))?',
  );

  // 01x05 or 1x05 or 01x01-02
  static final RegExp _xxExxRegex = RegExp(
    r'(?<!\d)(?<season>\d{1,2})[xX](?<ep1>\d{1,3})(?:[\.\s_-]*(?:[xX]|[-~])(?<ep2>\d{1,3}))?(?!\d)',
  );

  // SP01, OVA, Special 1
  static final RegExp _spOvaRegex = RegExp(
    r'(?<!\w)(?:(sp|ova|oad|special)[\.\s_-]*(?<ep1>\d{1,3})?)(?!\w)',
    caseSensitive: false,
  );

  // 第05集 or 第5话
  static final RegExp _chineseEpRegex = RegExp(
    r'第[\.\s_-]*(?<ep1>\d{1,4})[\.\s_-]*[集话話期]',
  );

  /// 解析媒体文件名
  static ParsedMediaFilename parse(
    String rawName, {
    List<String> directoryNames = const [],
  }) {
    var nameWithoutExt = rawName.replaceAll(_extRegex, '').trim();

    // 1. 提取分辨率
    String? resolution;
    final resMatch = _resolutionRegex.firstMatch(nameWithoutExt);
    if (resMatch != null) {
      final resText = resMatch.group(1)!.toUpperCase();
      if (resText == '2160P' || resText == 'UHD' || resText == '4K') {
        resolution = '4K';
      } else if (resText == '1080P' || resText == '1080I' || resText == 'FHD') {
        resolution = '1080p';
      } else if (resText == '720P' || resText == 'HD') {
        resolution = '720p';
      } else {
        resolution = resText.toLowerCase();
      }
    }

    // 2. 提取版本标签
    String? editionLabel;
    final editionMatch = _editionRegex.firstMatch(nameWithoutExt);
    if (editionMatch != null) {
      editionLabel = _formatEditionLabel(editionMatch.group(1)!);
    }

    // 3. 检查剧集 Season/Episode / OVA 模式
    int? seasonNumber;
    int? episodeNumber;
    final episodeNumbers = <int>[];
    var isMultiEpisode = false;
    var isSpecialOrOva = false;
    String? episodeTitle;
    var isSeries = false;
    int cutIndex = nameWithoutExt.length;
    int epEndIndex = -1;

    // 标准 SxxExx（包含 S00 特别篇及 S00E01-E02 多集特别篇）
    final sxxMatch = _sxxExxRegex.firstMatch(nameWithoutExt);
    if (sxxMatch != null) {
      isSeries = true;
      final sNum = int.tryParse(sxxMatch.namedGroup('season')!);
      seasonNumber = sNum;
      if (sNum == 0) {
        isSpecialOrOva = true;
      }
      final ep1 = int.tryParse(sxxMatch.namedGroup('ep1')!);
      final ep2Str = sxxMatch.namedGroup('ep2');
      final ep2 = ep2Str != null ? int.tryParse(ep2Str) : null;

      if (ep1 != null && ep2 != null && ep2 > ep1) {
        isMultiEpisode = true;
        for (var i = ep1; i <= ep2; i++) {
          episodeNumbers.add(i);
        }
        episodeNumber = null;
      } else if (ep1 != null) {
        episodeNumber = ep1;
        episodeNumbers.add(ep1);
      }
      cutIndex = sxxMatch.start;
      epEndIndex = sxxMatch.end;
    }

    // 01x05 模式
    if (!isSeries) {
      final xxMatch = _xxExxRegex.firstMatch(nameWithoutExt);
      if (xxMatch != null) {
        isSeries = true;
        seasonNumber = int.tryParse(xxMatch.namedGroup('season')!);
        final ep1 = int.tryParse(xxMatch.namedGroup('ep1')!);
        final ep2Str = xxMatch.namedGroup('ep2');
        final ep2 = ep2Str != null ? int.tryParse(ep2Str) : null;

        if (ep1 != null && ep2 != null && ep2 > ep1) {
          isMultiEpisode = true;
          for (var i = ep1; i <= ep2; i++) {
            episodeNumbers.add(i);
          }
          episodeNumber = null;
        } else if (ep1 != null) {
          episodeNumber = ep1;
          episodeNumbers.add(ep1);
        }
        cutIndex = xxMatch.start;
        epEndIndex = xxMatch.end;
      }
    }

    // 中文分集 "第05集"
    if (!isSeries) {
      final cnEpMatch = _chineseEpRegex.firstMatch(nameWithoutExt);
      if (cnEpMatch != null) {
        isSeries = true;
        seasonNumber = 1;
        final ep1 = int.tryParse(cnEpMatch.namedGroup('ep1')!);
        if (ep1 != null) {
          episodeNumber = ep1;
          episodeNumbers.add(ep1);
        }
        cutIndex = cnEpMatch.start;
        epEndIndex = cnEpMatch.end;
      }
    }

    // 单独的 E01 / EP01，季号可由目录上下文提供。
    if (!isSeries) {
      final episodeMatch = RegExp(
        r'(?<![a-zA-Z0-9])ep?(?<episode>\d{1,3})(?!\d)(?:[ ._-]*(?:e|[-~])(?<end>\d{1,3})(?!\d))?',
        caseSensitive: false,
      ).firstMatch(nameWithoutExt);
      final numericMatch = directoryNames.isNotEmpty
          ? RegExp(r'^(?<episode>\d{1,3})$').firstMatch(nameWithoutExt)
          : null;
      final match = episodeMatch ?? numericMatch;
      if (match != null) {
        isSeries = true;
        episodeNumber = int.parse(match.namedGroup('episode')!);
        if (episodeMatch == null) seasonNumber = 1;
        episodeNumbers.add(episodeNumber);
        if (episodeMatch != null) {
          final end = int.tryParse(episodeMatch.namedGroup('end') ?? '');
          if (end != null && end > episodeNumber) {
            episodeNumbers.addAll([
              for (var number = episodeNumber + 1; number <= end; number++)
                number,
            ]);
            episodeNumber = null;
            isMultiEpisode = true;
          }
        }
        cutIndex = match.start;
        epEndIndex = match.end;
      }
    }

    // SP / OVA 模式
    if (!isSeries) {
      final spMatch = _spOvaRegex.firstMatch(nameWithoutExt);
      if (spMatch != null) {
        isSeries = true;
        isSpecialOrOva = true;
        seasonNumber = 0;
        final epStr = spMatch.namedGroup('ep1');
        if (epStr != null) {
          episodeNumber = int.tryParse(epStr);
          if (episodeNumber != null) episodeNumbers.add(episodeNumber);
        }
        cutIndex = spMatch.start;
        epEndIndex = spMatch.end;
      }
    }

    // 4. 提取年份（支持 1917.2019 / 2001.A.Space.Odyssey.1968 等数字标题）
    int? year;
    final yearMatches = _yearRegex.allMatches(nameWithoutExt).where((ym) {
      final y = int.parse(ym.group(1)!);
      return y >= 1900 && y <= 2099;
    }).toList();

    if (isSeries) {
      // 剧集：年份出现在 SxxExx 标记之前
      for (final ym in yearMatches) {
        if (ym.start < cutIndex) {
          year = int.parse(ym.group(1)!);
          cutIndex = ym.start;
          break;
        }
      }
    } else {
      // 电影或候选视频：先计算最早压制/分辨率/版本标签位置
      var earliestJunk = nameWithoutExt.length;
      if (resMatch != null && resMatch.start < earliestJunk) {
        earliestJunk = resMatch.start;
      }
      if (editionMatch != null && editionMatch.start < earliestJunk) {
        earliestJunk = editionMatch.start;
      }
      final mJunk = _junkRegex.firstMatch(nameWithoutExt);
      if (mJunk != null && mJunk.start < earliestJunk) {
        earliestJunk = mJunk.start;
      }

      final preJunkYears = yearMatches
          .where((ym) => ym.start < earliestJunk)
          .toList();

      if (preJunkYears.length == 1) {
        final ym = preJunkYears.first;
        if (ym.start == 0 && ym.end >= earliestJunk) {
          // 纯数字文件名如 1984.mp4，作为片名，年份未知
          year = null;
          cutIndex = earliestJunk;
        } else {
          year = int.parse(ym.group(1)!);
          cutIndex = ym.start;
        }
      } else if (preJunkYears.length > 1) {
        // 多个年份（如 1917.2019 或 2001.A.Space.Odyssey.1968）
        // 取最后一个后置年份作为发售年份，前置年份作为片名一部分
        final lastYear = preJunkYears.last;
        if (lastYear.start > 0) {
          year = int.parse(lastYear.group(1)!);
          cutIndex = lastYear.start;
        } else {
          year = null;
          cutIndex = earliestJunk;
        }
      } else {
        cutIndex = earliestJunk;
      }
    }
    if (isSeries &&
        sxxMatch == null &&
        !_xxExxRegex.hasMatch(nameWithoutExt) &&
        !isSpecialOrOva) {
      seasonNumber =
          seasonFromName(nameWithoutExt) ??
          directoryNames.reversed
              .map(seasonFromName)
              .whereType<int>()
              .firstOrNull ??
          seasonNumber;
    }

    // 5. 提取标题
    final rawTitlePart = nameWithoutExt.substring(0, cutIndex).trim();
    final cleanedTitle = _cleanTitle(rawTitlePart);

    // 提取可能的次要标题（如中文 + 英文组合）
    var (mainTitle, secTitle) = _extractDualTitles(cleanedTitle);
    if (isSeries && mainTitle.isEmpty) {
      for (final directory in directoryNames.reversed) {
        if (seasonFromName(directory) != null) continue;
        final parent = parse(directory);
        if (parent.title.isEmpty) continue;
        mainTitle = parent.title;
        secTitle = parent.secondaryTitle;
        year ??= parent.year;
        break;
      }
    }
    if (year == null) {
      for (final directory in directoryNames.reversed) {
        year = parse(directory).year;
        if (year != null) break;
      }
    }

    // 6. 提取剧集的分集标题 (Episode Title)
    if (isSeries && epEndIndex > 0 && epEndIndex < nameWithoutExt.length) {
      final trailingPart = nameWithoutExt.substring(epEndIndex);
      // 找到下一个标签 (分辨率、年份、压制标签等)
      var epTitleEnd = trailingPart.length;
      final tRes = _resolutionRegex.firstMatch(trailingPart);
      if (tRes != null && tRes.start < epTitleEnd) epTitleEnd = tRes.start;
      final tJunk = _junkRegex.firstMatch(trailingPart);
      if (tJunk != null && tJunk.start < epTitleEnd) epTitleEnd = tJunk.start;
      final tEd = _editionRegex.firstMatch(trailingPart);
      if (tEd != null && tEd.start < epTitleEnd) epTitleEnd = tEd.start;

      final rawEpTitle = trailingPart.substring(0, epTitleEnd);
      final cleanEpTitle = _cleanTitle(rawEpTitle);
      if (cleanEpTitle.isNotEmpty) {
        episodeTitle = cleanEpTitle;
      }
    }

    // 7. 判断类型、置信度与模糊性
    String? type;
    var isConfident = false;
    var isAmbiguous = false;

    if (isSeries) {
      type = 'series';
      if (isMultiEpisode) {
        // 多集文件必须保留待确认审查状态
        isConfident = false;
        isAmbiguous = false;
      } else if (isSpecialOrOva && episodeNumber == null) {
        // 未知集号的特辑/OVA 不伪造 0/1，标记审查
        isConfident = false;
        isAmbiguous = true;
      } else if (episodeNumber != null) {
        isConfident = true;
      } else {
        isConfident = false;
        isAmbiguous = true;
      }
    } else {
      // 电影或未确定文件
      if (year != null) {
        type = 'movie';
        isConfident = true;
      } else {
        // 无年份
        type = null;
        isConfident = false;
        isAmbiguous = true;
      }
    }

    return ParsedMediaFilename(
      rawName: rawName,
      title: mainTitle.isNotEmpty ? mainTitle : _cleanTitle(nameWithoutExt),
      secondaryTitle: secTitle,
      year: year,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodeNumbers: episodeNumbers,
      isMultiEpisode: isMultiEpisode,
      isSpecialOrOva: isSpecialOrOva,
      episodeTitle: episodeTitle,
      editionLabel: editionLabel,
      resolution: resolution,
      type: type,
      isConfident: isConfident,
      isAmbiguous: isAmbiguous,
    );
  }

  static String _cleanTitle(String raw) {
    var s = raw
        .replaceAll(RegExp(r'[\[\]\(\)\{\}]'), ' ')
        .replaceAll(RegExp(r'[\._\+]'), ' ')
        .replaceAll(RegExp(r'[\s-]+$'), '')
        .replaceAll(RegExp(r'^[\s-]+'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    return s;
  }

  static int? seasonFromName(String name) {
    final match = RegExp(
      r'(?<![a-zA-Z0-9])(?:s|season[ ._-]*)(\d{1,2})(?!\d)|第[ ._-]*(\d{1,2})[ ._-]*季',
      caseSensitive: false,
    ).firstMatch(name);
    return match == null ? null : int.parse(match.group(1) ?? match.group(2)!);
  }

  static (String, String?) _extractDualTitles(String title) {
    // 匹配中文标题与后续英文标题，如 "流浪地球2 The Wandering Earth II"
    final match = RegExp(
      r'^([\u4e00-\u9fa5\d\s·：:—\-]+?)\s+([A-Za-z0-9\s:\-\.,!?]+)$',
    ).firstMatch(title);

    if (match != null) {
      final part1 = match.group(1)!.trim();
      final part2 = match.group(2)!.trim();
      // 确保第一部分确实包含汉字
      if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(part1) &&
          RegExp(r'[A-Za-z]').hasMatch(part2)) {
        return (part1, part2);
      }
    }

    return (title, null);
  }

  static String _formatEditionLabel(String raw) {
    final lower = raw.toLowerCase().replaceAll(RegExp(r'[\.\s_-]+'), ' ');
    if (lower.contains('director')) return "Director's Cut";
    if (lower.contains('extended')) return 'Extended Cut';
    if (lower.contains('remaster')) return 'Remastered';
    if (lower.contains('theatrical')) return 'Theatrical Cut';
    if (lower.contains('unrated')) return 'Unrated';
    if (lower.contains('imax')) return 'IMAX';
    if (lower.contains('criterion')) return 'Criterion';
    if (lower.contains('special')) return 'Special Edition';
    return raw;
  }
}
