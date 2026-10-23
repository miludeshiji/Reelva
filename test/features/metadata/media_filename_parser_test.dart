import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/metadata/domain/media_filename_parser.dart';

void main() {
  group('MediaFilenameParser Tests', () {
    group('Movie with Chinese / Year / Resolution / Codec', () {
      test('parses Chinese title with year and 4K/2160p resolution', () {
        final parsed = MediaFilenameParser.parse(
          '流浪地球2.2023.4K.2160p.WEB-DL.H265.AAC.mp4',
        );
        expect(parsed.title, '流浪地球2');
        expect(parsed.year, 2023);
        expect(parsed.resolution, '4K');
        expect(parsed.type, 'movie');
        expect(parsed.isConfident, isTrue);
        expect(parsed.isAmbiguous, isFalse);
      });

      test(
        'parses mixed Chinese and English titles with 1080p and edition',
        () {
          final parsed = MediaFilenameParser.parse(
            '千与千寻.Spirited.Away.2001.1080p.BluRay.x264.Remastered.mkv',
          );
          expect(parsed.title, '千与千寻');
          expect(parsed.secondaryTitle, 'Spirited Away');
          expect(parsed.year, 2001);
          expect(parsed.resolution, '1080p');
          expect(parsed.editionLabel, 'Remastered');
          expect(parsed.type, 'movie');
          expect(parsed.isConfident, isTrue);
        },
      );

      test('parses Western movie with Director Cut edition tag', () {
        final parsed = MediaFilenameParser.parse(
          'Blade.Runner.1982.Final.Cut.1080p.BluRay.x264.mkv',
        );
        expect(parsed.title, 'Blade Runner');
        expect(parsed.year, 1982);
        expect(parsed.resolution, '1080p');
        expect(parsed.type, 'movie');
        expect(parsed.isConfident, isTrue);
      });

      test('parses movie with Director Cut explicit tag', () {
        final parsed = MediaFilenameParser.parse(
          'Kingdom.of.Heaven.2005.Directors.Cut.1080p.mkv',
        );
        expect(parsed.title, 'Kingdom of Heaven');
        expect(parsed.year, 2005);
        expect(parsed.editionLabel, "Director's Cut");
        expect(parsed.type, 'movie');
      });

      test('parses movie with Extended Cut tag', () {
        final parsed = MediaFilenameParser.parse(
          'The.Lord.of.the.Rings.The.Fellowship.of.the.Ring.2001.Extended.Cut.2160p.mkv',
        );
        expect(parsed.year, 2001);
        expect(parsed.editionLabel, 'Extended Cut');
        expect(parsed.resolution, '4K');
        expect(parsed.type, 'movie');
      });
      test('parses numeric title 1917 with year 2019 correctly', () {
        final parsed = MediaFilenameParser.parse(
          '1917.2019.1080p.BluRay.x264.mkv',
        );
        expect(parsed.title, '1917');
        expect(parsed.year, 2019);
        expect(parsed.type, 'movie');
        expect(parsed.isConfident, isTrue);
      });

      test(
        'parses numeric title 2001 A Space Odyssey with year 1968 correctly',
        () {
          final parsed = MediaFilenameParser.parse(
            '2001.A.Space.Odyssey.1968.1080p.mkv',
          );
          expect(parsed.title, '2001 A Space Odyssey');
          expect(parsed.year, 1968);
          expect(parsed.type, 'movie');
          expect(parsed.isConfident, isTrue);
        },
      );
    });

    group('Standard TV Series S01E05 and 01x05', () {
      test('parses standard S01E05 with episode title', () {
        final parsed = MediaFilenameParser.parse(
          'Breaking.Bad.S01E05.Gray.Matter.1080p.BluRay.x264.mkv',
        );
        expect(parsed.title, 'Breaking Bad');
        expect(parsed.seasonNumber, 1);
        expect(parsed.episodeNumber, 5);
        expect(parsed.episodeNumbers, [5]);
        expect(parsed.episodeTitle, 'Gray Matter');
        expect(parsed.resolution, '1080p');
        expect(parsed.type, 'series');
        expect(parsed.isConfident, isTrue);
        expect(parsed.isMultiEpisode, isFalse);
      });

      test('parses 01x05 format with episode title', () {
        final parsed = MediaFilenameParser.parse(
          'The.Office.US.01x05.Basketball.720p.HDTV.x264.mkv',
        );
        expect(parsed.title, 'The Office US');
        expect(parsed.seasonNumber, 1);
        expect(parsed.episodeNumber, 5);
        expect(parsed.episodeTitle, 'Basketball');
        expect(parsed.resolution, '720p');
        expect(parsed.type, 'series');
        expect(parsed.isConfident, isTrue);
        expect(parsed.isMultiEpisode, isFalse);
      });

      test('parses series with year in title', () {
        final parsed = MediaFilenameParser.parse(
          'Fargo.2014.S02E08.720p.WEB-DL.mkv',
        );
        expect(parsed.title, 'Fargo');
        expect(parsed.year, 2014);
        expect(parsed.seasonNumber, 2);
        expect(parsed.episodeNumber, 8);
        expect(parsed.type, 'series');
        expect(parsed.isConfident, isTrue);
      });

      test('parses Chinese episode format', () {
        final parsed = MediaFilenameParser.parse('三体.2023.第05集.1080p.mp4');
        expect(parsed.title, '三体');
        expect(parsed.year, 2023);
        expect(parsed.seasonNumber, 1);
        expect(parsed.episodeNumber, 5);
        expect(parsed.type, 'series');
        expect(parsed.isConfident, isTrue);
      });
      test(
        'parses series without year still establishes season 1 episode 5',
        () {
          final parsed = MediaFilenameParser.parse(
            'Show.Name.S01E05.1080p.mkv',
          );
          expect(parsed.title, 'Show Name');
          expect(parsed.year, isNull);
          expect(parsed.seasonNumber, 1);
          expect(parsed.episodeNumber, 5);
          expect(parsed.type, 'series');
        },
      );
    });

    group('Multi-episode Range', () {
      test('parses S03E01-E02 range without faking single episode number', () {
        final parsed = MediaFilenameParser.parse(
          'Friends.S03E01-E02.1080p.mkv',
        );
        expect(parsed.title, 'Friends');
        expect(parsed.seasonNumber, 3);
        expect(parsed.episodeNumber, isNull); // 严禁伪造确定集号
        expect(parsed.episodeNumbers, [1, 2]);
        expect(parsed.isMultiEpisode, isTrue);
        expect(parsed.type, 'series');
        expect(parsed.isConfident, isFalse); // 多集待确认审查
      });

      test('parses S01E01-02 short range', () {
        final parsed = MediaFilenameParser.parse('Chernobyl.S01E01-02.mkv');
        expect(parsed.title, 'Chernobyl');
        expect(parsed.seasonNumber, 1);
        expect(parsed.episodeNumber, isNull);
        expect(parsed.episodeNumbers, [1, 2]);
        expect(parsed.isMultiEpisode, isTrue);
        expect(parsed.isConfident, isFalse);
      });

      test('parses 01x01-03 range', () {
        final parsed = MediaFilenameParser.parse(
          'Band.of.Brothers.01x01-03.1080p.mkv',
        );
        expect(parsed.title, 'Band of Brothers');
        expect(parsed.seasonNumber, 1);
        expect(parsed.episodeNumber, isNull);
        expect(parsed.episodeNumbers, [1, 2, 3]);
        expect(parsed.isMultiEpisode, isTrue);
        expect(parsed.isConfident, isFalse);
      });
      test('parses S00E01-E02 special multi-episode correctly without losing range', () {
        final parsed = MediaFilenameParser.parse(
          'Sherlock.S00E01-E02.The.Abominable.Bride.1080p.mkv',
        );
        expect(parsed.title, 'Sherlock');
        expect(parsed.seasonNumber, 0);
        expect(parsed.episodeNumber, isNull);
        expect(parsed.episodeNumbers, [1, 2]);
        expect(parsed.isMultiEpisode, isTrue);
        expect(parsed.isSpecialOrOva, isTrue);
        expect(parsed.type, 'series');
        expect(parsed.isConfident, isFalse);
      });
    });

    group('Specials and OVA Candidates', () {
      test('parses OVA with number as special season 0', () {
        final parsed = MediaFilenameParser.parse(
          'Attack.on.Titan.OVA.1.1080p.mkv',
        );
        expect(parsed.title, 'Attack on Titan');
        expect(parsed.seasonNumber, 0);
        expect(parsed.episodeNumber, 1);
        expect(parsed.isSpecialOrOva, isTrue);
        expect(parsed.type, 'series');
      });

      test('parses bare Special without number without faking 0 or 1', () {
        final parsed = MediaFilenameParser.parse(
          'Sousou.no.Frieren.Special.mkv',
        );
        expect(parsed.title, 'Sousou no Frieren');
        expect(parsed.seasonNumber, 0);
        expect(parsed.episodeNumber, isNull); // 严禁伪造集号
        expect(parsed.isSpecialOrOva, isTrue);
        expect(parsed.type, 'series');
        expect(parsed.isConfident, isFalse); // 未知集号标记审查
      });

      test('parses S00E02 format', () {
        final parsed = MediaFilenameParser.parse(
          'Doctor.Who.S00E02.The.Runaway.Bride.1080p.mkv',
        );
        expect(parsed.title, 'Doctor Who');
        expect(parsed.seasonNumber, 0);
        expect(parsed.episodeNumber, 2);
        expect(parsed.episodeTitle, 'The Runaway Bride');
        expect(parsed.isSpecialOrOva, isTrue);
        expect(parsed.type, 'series');
      });
    });

    group('Ambiguous and No-year Files', () {
      test('parses file without year or pattern as ambiguous', () {
        final parsed = MediaFilenameParser.parse('SampleVideo.mp4');
        expect(parsed.title, 'SampleVideo');
        expect(parsed.year, isNull);
        expect(parsed.type, isNull);
        expect(parsed.isAmbiguous, isTrue);
        expect(parsed.isConfident, isFalse);
      });

      test('parses bare single-word video file without year', () {
        final parsed = MediaFilenameParser.parse('Inception.mkv');
        expect(parsed.title, 'Inception');
        expect(parsed.year, isNull);
        expect(parsed.type, isNull);
        expect(parsed.isAmbiguous, isTrue);
        expect(parsed.isConfident, isFalse);
      });

      test(
        'parses video with resolution but no year as ambiguous candidate',
        () {
          final parsed = MediaFilenameParser.parse('Avatar.1080p.mkv');
          expect(parsed.title, 'Avatar');
          expect(parsed.year, isNull);
          expect(parsed.resolution, '1080p');
          expect(parsed.type, isNull);
          expect(parsed.isAmbiguous, isTrue);
          expect(parsed.isConfident, isFalse);
        },
      );
      test('parses bare numeric filename 1984 as title with unknown year and low confidence', () {
        final parsed = MediaFilenameParser.parse('1984.mp4');
        expect(parsed.title, '1984');
        expect(parsed.year, isNull);
        expect(parsed.type, isNull);
        expect(parsed.isAmbiguous, isTrue);
        expect(parsed.isConfident, isFalse);
      });
    });
  });
}
