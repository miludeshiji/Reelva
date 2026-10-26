import 'tmdb_models.dart';
import 'work_metadata.dart';

class MetadataFile {
  const MetadataFile({
    required this.fileId,
    required this.sourceId,
    required this.entryId,
    required this.name,
    required this.workId,
    required this.metadata,
    required this.metadataSource,
    required this.locked,
    this.episode,
  });

  final int fileId;
  final int sourceId;
  final String entryId;
  final String name;
  final int workId;
  final WorkMetadata metadata;
  final String metadataSource;
  final bool locked;
  final TmdbEpisode? episode;
}
