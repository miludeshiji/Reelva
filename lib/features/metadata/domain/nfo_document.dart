import 'package:xml/xml.dart';

import 'tmdb_models.dart';
import 'work_metadata.dart';

/// Kodi/Jellyfin 共同使用的基础字段，未识别的 XML 字段在更新时保留。
class NfoDocument {
  const NfoDocument({
    required this.kind,
    required this.metadata,
    this.episode,
    this.poster,
    this.fanart,
  });

  final String kind;
  final WorkMetadata metadata;
  final TmdbEpisode? episode;
  final String? poster;
  final String? fanart;

  factory NfoDocument.parse(String text) {
    final XmlElement root;
    try {
      root = XmlDocument.parse(text).rootElement;
    } on XmlException {
      throw const MetadataException('NFO 文件不是有效 XML', code: 'invalid_nfo');
    }
    final kind = root.name.local;
    if (!const ['movie', 'tvshow', 'episodedetails'].contains(kind)) {
      throw const MetadataException('不支持此 NFO 类型', code: 'invalid_nfo');
    }
    String? value(String name) {
      final text = root.getElement(name)?.innerText.trim();
      return text == null || text.isEmpty ? null : text;
    }

    final title = value('title');
    if (title == null) {
      throw const MetadataException('NFO 缺少标题', code: 'invalid_nfo');
    }
    final idText =
        root
            .findElements('uniqueid')
            .where((id) => id.getAttribute('type')?.toLowerCase() == 'tmdb')
            .firstOrNull
            ?.innerText ??
        value('tmdbid');
    final id = int.tryParse(idText ?? '');
    final validId = id != null && id > 0 ? id : null;
    final date = DateTime.tryParse(value('premiered') ?? '');
    TmdbEpisode? episode;
    if (kind == 'episodedetails') {
      final season = int.tryParse(value('season') ?? '');
      final number = int.tryParse(value('episode') ?? '');
      if (season == null || season < 0 || number == null || number < 1) {
        throw const MetadataException('分集 NFO 缺少有效季号或集号', code: 'invalid_nfo');
      }
      episode = TmdbEpisode(
        tmdbId: validId,
        seasonNumber: season,
        episodeNumber: number,
        title: title,
        overview: value('plot'),
        airDate: DateTime.tryParse(value('aired') ?? ''),
      );
    }
    final thumbs = root.findElements('thumb');
    final poster =
        thumbs.where((e) => e.getAttribute('aspect') == 'poster').firstOrNull ??
        thumbs.where((e) => e.getAttribute('aspect') == null).firstOrNull;
    String? tmdbPath(String? url) {
      final uri = Uri.tryParse(url ?? '');
      if (uri?.host != 'image.tmdb.org' || uri!.pathSegments.length < 4) {
        return null;
      }
      return '/${uri.pathSegments.last}';
    }

    final posterText = poster?.innerText.trim();
    final fanart = root
        .getElement('fanart')
        ?.getElement('thumb')
        ?.innerText
        .trim();
    return NfoDocument(
      kind: kind,
      episode: episode,
      poster: posterText?.isNotEmpty == true ? posterText : null,
      fanart: fanart?.isNotEmpty == true ? fanart : null,
      metadata: WorkMetadata(
        type: kind == 'movie' ? 'movie' : 'series',
        title: kind == 'episodedetails' ? value('showtitle') ?? '' : title,
        tmdbId: kind == 'episodedetails' ? null : validId,
        originalTitle: value('originaltitle'),
        overview: value('plot'),
        premiered: date,
        year: int.tryParse(value('year') ?? '') ?? date?.year,
        posterPath: tmdbPath(posterText),
        backdropPath: tmdbPath(fanart),
      ),
    );
  }

  String encode({String? existing}) {
    XmlElement? previous;
    if (existing != null) {
      // 不以损坏文件为模板，更不能用一次导出静默覆盖它。
      NfoDocument.parse(existing);
      previous = XmlDocument.parse(existing).rootElement;
    }
    final newId = kind == 'episodedetails' ? episode?.tmdbId : metadata.tmdbId;
    final oldId = previous
        ?.findElements('uniqueid')
        .where((e) => e.getAttribute('type') == 'tmdb')
        .firstOrNull
        ?.innerText;
    if (previous?.name.local != kind ||
        (newId != null && oldId != null && oldId != '$newId')) {
      previous = null;
    }
    final root = previous?.copy() ?? XmlElement(XmlName.parts(kind));
    void set(String name, Object? value, {bool preserveMissing = false}) {
      if (value == null && preserveMissing) return;
      root.children.removeWhere(
        (child) => child is XmlElement && child.name.local == name,
      );
      if (value != null) {
        root.children.add(
          XmlElement(XmlName.parts(name), [], [XmlText('$value')]),
        );
      }
    }

    String? date(DateTime? value) => value?.toIso8601String().split('T').first;
    final ep = episode;
    set(
      'title',
      kind == 'episodedetails' ? ep?.title ?? metadata.title : metadata.title,
    );
    if (kind == 'episodedetails' && ep != null) {
      set('showtitle', metadata.title);
      set('season', ep.seasonNumber);
      set('episode', ep.episodeNumber);
      set('plot', ep.overview);
      set('aired', date(ep.airDate), preserveMissing: true);
    } else {
      set('originaltitle', metadata.originalTitle);
      set('plot', metadata.overview);
      set('year', metadata.year);
      set('premiered', date(metadata.premiered), preserveMissing: true);
    }
    if (newId != null) {
      root.children.removeWhere(
        (child) =>
            child is XmlElement &&
            (child.name.local == 'tmdbid' ||
                child.name.local == 'uniqueid' &&
                    child.getAttribute('type') == 'tmdb'),
      );
      for (final id in root.findElements('uniqueid')) {
        id.removeAttribute('default');
      }
      root.children.add(
        XmlElement(
          const XmlName.parts('uniqueid'),
          [
            XmlAttribute(const XmlName.parts('type'), 'tmdb'),
            XmlAttribute(const XmlName.parts('default'), 'true'),
          ],
          [XmlText('$newId')],
        ),
      );
    } else if (root.getElement('uniqueid') == null) {
      // 本地身份使用独立 provider，绝不将本地编号或整剧 ID 冒充分集 TMDB ID。
      final key =
          '${metadata.type}:${metadata.title}:${metadata.year}:${ep?.seasonNumber}:${ep?.episodeNumber}';
      var hash = 2166136261;
      for (final unit in key.codeUnits) {
        hash = ((hash ^ unit) * 16777619) & 0xffffffff;
      }
      root.children.add(
        XmlElement(
          const XmlName.parts('uniqueid'),
          [
            XmlAttribute(const XmlName.parts('type'), 'reelva'),
            XmlAttribute(const XmlName.parts('default'), 'true'),
          ],
          [XmlText(hash.toRadixString(16))],
        ),
      );
    }
    if (poster != null) {
      root.children.removeWhere(
        (child) =>
            child is XmlElement &&
            child.name.local == 'thumb' &&
            (child.getAttribute('aspect') == 'poster' ||
                child.getAttribute('aspect') == null),
      );
      root.children.add(
        XmlElement(
          const XmlName.parts('thumb'),
          [XmlAttribute(const XmlName.parts('aspect'), 'poster')],
          [XmlText(poster!)],
        ),
      );
    }
    if (fanart != null) {
      set('fanart', null);
      root.children.add(
        XmlElement(const XmlName.parts('fanart'), [], [
          XmlElement(const XmlName.parts('thumb'), [], [XmlText(fanart!)]),
        ]),
      );
    }
    return XmlDocument([
      XmlDeclaration([
        XmlAttribute(const XmlName.parts('version'), '1.0'),
        XmlAttribute(const XmlName.parts('encoding'), 'UTF-8'),
      ]),
      root,
    ]).toXmlString(pretty: true);
  }
}
