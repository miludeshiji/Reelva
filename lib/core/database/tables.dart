import 'package:drift/drift.dart';

@DataClassName('MediaSourceEntry')
class MediaSources extends Table {
  @override
  String get tableName => 'media_sources';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()();
  TextColumn get name => text()();
  TextColumn get rootLocator => text()();
  TextColumn get credentialRef => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get extensions => text().withDefault(
    const Constant(r'["mkv","mp4","avi","mov","m4v","ts","webm"]'),
  )();
  TextColumn get excludedDirectories => text().withDefault(
    const Constant(r'[".cache","$RECYCLE.BIN","System Volume Information"]'),
  )();
  IntColumn get scanRevision => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastScanAt => dateTime().nullable()();
  TextColumn get errorMessage => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {kind, rootLocator},
  ];
}

@DataClassName('MediaEntryData')
class MediaEntries extends Table {
  @override
  String get tableName => 'media_entries';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceId =>
      integer().references(MediaSources, #id, onDelete: KeyAction.cascade)();
  TextColumn get externalEntryId => text()();
  TextColumn get relativeLocator => text()();
  TextColumn get name => text()();
  BoolColumn get isDirectory => boolean()();
  IntColumn get size => integer().nullable()();
  IntColumn get modifiedAt => integer().named('modified_at').nullable()();
  TextColumn get etag => text().nullable()();
  BoolColumn get available => boolean().withDefault(const Constant(true))();
  IntColumn get lastSeenScanId => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {sourceId, externalEntryId},
  ];
}

@DataClassName('MediaFileData')
class MediaFiles extends Table {
  @override
  String get tableName => 'media_files';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().unique().references(
    MediaEntries,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get container => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get resolutionWidth => integer().nullable()();
  IntColumn get resolutionHeight => integer().nullable()();
  TextColumn get videoCodec => text().nullable()();
  TextColumn get audioCodec => text().nullable()();
  TextColumn get parseState => text().withDefault(const Constant('pending'))();
  TextColumn get candidateType => text().nullable()();
  IntColumn get candidateSeasonNumber => integer().nullable()();
  IntColumn get candidateEpisodeNumber => integer().nullable()();
  TextColumn get candidateDetails => text().nullable()();
}

@DataClassName('WorkData')
class Works extends Table {
  @override
  String get tableName => 'works';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text().nullable()();
  TextColumn get title => text()();
  TextColumn get originalTitle => text().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get overview => text().nullable()();
  TextColumn get posterPath => text().nullable()();
  TextColumn get backdropPath => text().nullable()();
  TextColumn get metadataSource =>
      text().withDefault(const Constant('local'))();
  BoolColumn get metadataLocked =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
    "CHECK (type IS NULL OR type IN ('movie', 'series'))",
  ];
}

@DataClassName('SeasonData')
class Seasons extends Table {
  @override
  String get tableName => 'seasons';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get seriesId =>
      integer().references(Works, #id, onDelete: KeyAction.cascade)();
  IntColumn get seasonNumber => integer()();
  TextColumn get title => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {seriesId, seasonNumber},
  ];
}

@DataClassName('EpisodeData')
class Episodes extends Table {
  @override
  String get tableName => 'episodes';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get seasonId =>
      integer().references(Seasons, #id, onDelete: KeyAction.cascade)();
  IntColumn get episodeNumber => integer()();
  TextColumn get title => text().nullable()();
  TextColumn get overview => text().nullable()();
  DateTimeColumn get airDate => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {seasonId, episodeNumber},
  ];
}

@DataClassName('MediaAssignmentData')
class MediaAssignments extends Table {
  @override
  String get tableName => 'media_assignments';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get fileId =>
      integer().references(MediaFiles, #id, onDelete: KeyAction.cascade)();
  IntColumn get workId => integer().nullable().references(
    Works,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get episodeId => integer().nullable().references(
    Episodes,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get editionLabel => text().nullable()();
  BoolColumn get preferred => boolean().withDefault(const Constant(false))();

  @override
  List<String> get customConstraints => [
    'CHECK ((work_id IS NOT NULL AND episode_id IS NULL) OR (work_id IS NULL AND episode_id IS NOT NULL))',
  ];
}

@DataClassName('PlaybackProgressData')
class PlaybackProgresses extends Table {
  @override
  String get tableName => 'playback_progress';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get targetType => text()();
  IntColumn get targetId => integer()();
  IntColumn get workId => integer().nullable().references(
    Works,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get episodeId => integer().nullable().references(
    Episodes,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get lastFileId => integer().nullable().references(
    MediaFiles,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {targetType, targetId},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK ("
        "(target_type = 'work' AND work_id IS NOT NULL AND target_id = work_id AND episode_id IS NULL) OR "
        "(target_type = 'episode' AND episode_id IS NOT NULL AND target_id = episode_id AND work_id IS NULL)"
        ")",
  ];
}

@DataClassName('ExternalIdData')
class ExternalIds extends Table {
  @override
  String get tableName => 'external_ids';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get workId =>
      integer().references(Works, #id, onDelete: KeyAction.cascade)();
  TextColumn get provider => text()();
  TextColumn get providerEntityId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {provider, providerEntityId},
  ];
}

@DataClassName('MetadataCacheData')
class MetadataCaches extends Table {
  @override
  String get tableName => 'metadata_cache';

  TextColumn get cacheKey => text()();
  TextColumn get provider => text()();
  TextColumn get payloadJson => text()();
  TextColumn get etag => text().nullable()();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {cacheKey};
}
