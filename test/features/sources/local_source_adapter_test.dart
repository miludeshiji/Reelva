import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/local_source_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalSourceAdapter', () {
    late Directory tempDir;
    late MediaSourceConfig source;
    late LocalSourceAdapter adapter;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'reelva_local_adapter_test_',
      );
      source = MediaSourceConfig(
        id: 1,
        kind: 'local',
        name: 'Test Source',
        rootLocator: tempDir.path,
      );
      adapter = const LocalSourceAdapter();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('kind is local', () {
      expect(adapter.kind, 'local');
    });

    group('pickDirectory', () {
      test('returns null when picker returns null', () async {
        final adapterWithPicker = LocalSourceAdapter(
          openDirectoryPicker: ({confirmButtonText, initialDirectory}) async =>
              null,
        );
        final selection = await adapterWithPicker.pickDirectory();
        expect(selection, isNull);
      });

      test(
        'returns DirectorySelection when picker returns valid path',
        () async {
          final targetPath = p.join(tempDir.path, 'MyMovies');
          await Directory(targetPath).create();

          final adapterWithPicker = LocalSourceAdapter(
            openDirectoryPicker: ({
              confirmButtonText,
              initialDirectory,
            }) async => targetPath,
          );
          final selection = await adapterWithPicker.pickDirectory();

          expect(selection, isNotNull);
          expect(selection!.kind, 'local');
          expect(selection.rootLocator, p.normalize(targetPath));
          expect(selection.name, 'MyMovies');
        },
      );

      test('maps PlatformException to MediaSourceException', () async {
        final adapterWithPicker = LocalSourceAdapter(
          openDirectoryPicker: ({confirmButtonText, initialDirectory}) async {
            throw PlatformException(code: 'SECURITY_ERROR', message: 'Denied');
          },
        );

        expect(
          () => adapterWithPicker.pickDirectory(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'SECURITY_ERROR',
            ),
          ),
        );
      });
    });

    group('listEntries', () {
      test('lists direct files and directories with relative locator and externalId', () async {
        final subDir = Directory(p.join(tempDir.path, 'Sci-Fi'));
        await subDir.create();
        final testFile = File(p.join(tempDir.path, 'Inception.mp4'));
        await testFile.writeAsString('test video content');

        final entries = await adapter
            .listEntries(source, source.rootLocator)
            .toList();

        expect(entries.length, 2);
        final dirEntry = entries.firstWhere((e) => e.name == 'Sci-Fi');
        expect(dirEntry.isDirectory, isTrue);
        expect(dirEntry.locator, 'Sci-Fi');
        expect(dirEntry.externalId, Platform.isWindows ? 'sci-fi' : 'Sci-Fi');

        final fileEntry = entries.firstWhere((e) => e.name == 'Inception.mp4');
        expect(fileEntry.isDirectory, isFalse);
        expect(fileEntry.locator, 'Inception.mp4');
        expect(
          fileEntry.externalId,
          Platform.isWindows ? 'inception.mp4' : 'Inception.mp4',
        );
        expect(fileEntry.size, greaterThan(0));
        expect(fileEntry.modifiedAt, isNotNull);
      });

      test(
        'lists subdirectories when passed subdirectory externalId',
        () async {
          final subDir = Directory(p.join(tempDir.path, 'Series', 'Season1'));
          await subDir.create(recursive: true);
          final epFile = File(p.join(subDir.path, 'Episode1.mkv'));
          await epFile.writeAsString('video');

          final rootEntries = await adapter
              .listEntries(source, source.rootLocator)
              .toList();
          final seriesEntry = rootEntries.singleWhere(
            (e) => e.name == 'Series',
          );

          final seasonEntries = await adapter
              .listEntries(source, seriesEntry.externalId)
              .toList();
          final seasonEntry = seasonEntries.singleWhere(
            (e) => e.name == 'Season1',
          );

          final entries = await adapter
              .listEntries(source, seasonEntry.externalId)
              .toList();

          expect(entries.length, 1);
          final epEntry = entries.first;
          expect(epEntry.name, 'Episode1.mkv');
          expect(
            epEntry.externalId,
            Platform.isWindows
                ? 'series/season1/episode1.mkv'
                : 'Series/Season1/Episode1.mkv',
          );
          final resource = await adapter.resolvePlayback(
            source,
            epEntry.locator,
          );
          expect(await File.fromUri(resource.uri).readAsString(), 'video');
        },
      );

      test('skips links to avoid link loops and reparse traversal', () async {
        final realDir = Directory(p.join(tempDir.path, 'RealDir'));
        await realDir.create();
        final link = Link(p.join(tempDir.path, 'LoopLink'));
        try {
          await link.create(realDir.path);
        } catch (_) {
          // 在没有管理员权限的 Windows 环境下可能无法创建符号链接，跳过测试链接部分
          return;
        }

        final entries = await adapter
            .listEntries(source, source.rootLocator)
            .toList();
        final linkEntries = entries.where((e) => e.name == 'LoopLink');
        expect(linkEntries, isEmpty);
      });

      test(
        'throws MediaSourceException when directory does not exist',
        () async {
          final nonExistentSource = MediaSourceConfig(
            id: 2,
            kind: 'local',
            name: 'Missing',
            rootLocator: p.join(tempDir.path, 'GhostDir'),
          );

          expect(
            () => adapter
                .listEntries(nonExistentSource, nonExistentSource.rootLocator)
                .toList(),
            throwsA(
              isA<MediaSourceException>().having(
                (e) => e.code,
                'code',
                'not_found',
              ),
            ),
          );
        },
      );
    });

    group('stat', () {
      test('returns stat for file', () async {
        final testFile = File(p.join(tempDir.path, 'video.mp4'));
        await testFile.writeAsString('12345');

        final stat = await adapter.stat(source, 'video.mp4');
        expect(stat.size, 5);
        expect(stat.modifiedAt, isNotNull);
      });

      test('returns stat for directory', () async {
        final subDir = Directory(p.join(tempDir.path, 'sub'));
        await subDir.create();

        final stat = await adapter.stat(source, 'sub');
        expect(stat.size, isNull);
        expect(stat.modifiedAt, isNotNull);
      });

      test('throws MediaSourceException when entry not found', () async {
        expect(
          () => adapter.stat(source, 'missing.mp4'),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'not_found',
            ),
          ),
        );
      });
    });

    group('resolvePlayback', () {
      test('returns PlaybackResource with file URI and display name', () async {
        final testFile = File(p.join(tempDir.path, 'Matrix.mkv'));
        await testFile.writeAsString('matrix video');

        final resource = await adapter.resolvePlayback(source, 'Matrix.mkv');
        expect(resource.uri.scheme, 'file');
        expect(resource.displayName, 'Matrix.mkv');
        expect(await File.fromUri(resource.uri).readAsString(), 'matrix video');
      });

      test('throws MediaSourceException when file not found', () async {
        expect(
          () => adapter.resolvePlayback(source, 'not_there.mp4'),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'not_found',
            ),
          ),
        );
      });
    });
  });
}
