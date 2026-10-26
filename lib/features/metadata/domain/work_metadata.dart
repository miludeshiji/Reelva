/// 与提供商无关的作品元数据；无外部身份的 NFO 也可独立导入。
class WorkMetadata {
  const WorkMetadata({
    required this.type,
    required this.title,
    this.tmdbId,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.year,
    this.premiered,
  });
  final String type;
  final String title;
  final int? tmdbId;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final int? year;
  final DateTime? premiered;
}
