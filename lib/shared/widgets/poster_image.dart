import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 海报专用磁盘缓存管理器
///
/// 注意：[maxNrOfCacheObjects] 是缓存对象（图片文件）数量上限，并非字节大小硬上限；
/// 配合 TMDB 缩略图（w342 / w500 / w780）控制单张海报体积，避免海报墙过度占用磁盘空间。
class PosterCacheManager {
  static const String cacheKey = 'reelva_posters_cache';

  static final CacheManager instance = CacheManager(
    Config(
      cacheKey,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 300,
    ),
  );

  /// 清空本地海报图片缓存
  static Future<void> clearCache() async {
    await instance.emptyCache();
  }
}

/// 统一的 TMDB 影视海报展示组件
///
/// 专用于 TMDB 相对海报路径（如 `/abc.jpg`）。
/// 具备自动构造绝对 URL、受控磁盘缓存与内存解码宽度限制（[memCacheWidth]）、
/// 优雅加载占位与异常标题文字兜底能力，避免同步文件 I/O 阻塞 UI 线程。
class PosterImage extends StatelessWidget {
  const PosterImage({
    super.key,
    required this.posterPath,
    this.title,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.size = 'w342',
  });

  /// TMDB 相对海报路径（如 `/q6y0Go1tsGEsmtFryDOJo3dEmqu.jpg`）
  final String? posterPath;

  /// 作品标题（用于无海报或加载失败时的安全文字占位展示）
  final String? title;

  /// 图片宽度
  final double? width;

  /// 图片高度
  final double? height;

  /// 图片填充方式
  final BoxFit fit;

  /// 圆角剪裁
  final BorderRadius borderRadius;

  /// TMDB 规格尺寸（默认 w342，详情页可用 w500 或 w780）
  final String size;

  static String buildTmdbPosterUrl(
    String relativePath, {
    String size = 'w342',
  }) {
    final cleanPath = relativePath.startsWith('/')
        ? relativePath
        : '/$relativePath';
    return 'https://image.tmdb.org/t/p/$size$cleanPath';
  }

  int? get _memCacheWidth {
    if (size.startsWith('w')) {
      final parsed = int.tryParse(size.substring(1));
      if (parsed != null && parsed > 0) return parsed;
    }
    return 342;
  }

  @override
  Widget build(BuildContext context) {
    final raw = posterPath?.trim();

    Widget content;
    if (raw == null || raw.isEmpty) {
      content = _buildPlaceholder(context);
    } else {
      final url = buildTmdbPosterUrl(raw, size: size);
      content = CachedNetworkImage(
        imageUrl: url,
        cacheManager: PosterCacheManager.instance,
        memCacheWidth: _memCacheWidth,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, _) => _buildLoading(context),
        errorWidget: (context, _, error) => _buildPlaceholder(context),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(width: width, height: height, child: content),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: colorScheme.surfaceContainerHighest,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxH = constraints.maxHeight;
          final iconSize = (maxH * 0.35).clamp(18.0, 32.0);

          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.movie_outlined,
                  size: iconSize,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                if (title != null &&
                    title!.trim().isNotEmpty &&
                    maxH >= 40) ...[
                  const SizedBox(height: 2),
                  Flexible(
                    child: Text(
                      title!,
                      maxLines: maxH < 80 ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: maxH < 80 ? 10 : 11,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
