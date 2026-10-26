import 'package:path/path.dart' as p;

import 'player_settings.dart';

/// 可独立加载的字幕格式，不包含需要配套文件的 VobSub IDX/SUB。
const subtitleExtensions = ['srt', 'ass', 'ssa', 'vtt', 'smi', 'sami', 'sup'];

bool isSubtitleFile(String name) => subtitleExtensions.contains(
  p.extension(name).replaceFirst('.', '').toLowerCase(),
);

bool matchesSubtitle(
  String videoName,
  String subtitleName,
  TrackAutoLoad mode,
) {
  if (mode == TrackAutoLoad.disabled || !isSubtitleFile(subtitleName)) {
    return false;
  }
  final video = p.basenameWithoutExtension(videoName).toLowerCase();
  final subtitle = p.basenameWithoutExtension(subtitleName).toLowerCase();
  if (video.isEmpty) return false;
  if (video == subtitle) return true;
  if (mode == TrackAutoLoad.exact || !subtitle.startsWith(video)) return false;
  // 限制后缀边界，避免第 01 集误挂第 010 集的字幕。
  return RegExp(r'^[.\s_\-\[(]').hasMatch(subtitle.substring(video.length));
}

String? subtitleLanguage(String name) {
  final tokens = p
      .basenameWithoutExtension(name)
      .toLowerCase()
      .split(RegExp(r'[.\s_\-\[\]()]'));
  for (final language in tokens.reversed) {
    if (const [
      'zh',
      'chi',
      'zho',
      'chs',
      'cht',
      'sc',
      'tc',
      'en',
      'eng',
      'ja',
      'jpn',
      'ko',
      'kor',
      'fr',
      'fra',
      'de',
      'deu',
      'es',
      'spa',
    ].contains(language)) {
      return language;
    }
  }
  return null;
}

int subtitleLanguagePriority(String name, String preferences) {
  final language = subtitleLanguage(name);
  if (language == null) return preferences.split(',').length;
  String normalize(String value) => switch (value.trim().toLowerCase()) {
    'chi' ||
    'zho' ||
    'chs' ||
    'cht' ||
    'sc' ||
    'tc' ||
    'zh-hans' ||
    'zh-hant' => 'zh',
    'eng' => 'en',
    'jpn' => 'ja',
    'kor' => 'ko',
    'fra' => 'fr',
    'deu' => 'de',
    'spa' => 'es',
    final value => value,
  };
  final languages = preferences.split(',').map(normalize).toList();
  final index = languages.indexOf(normalize(language));
  return index < 0 ? languages.length : index;
}
