import 'package:y300/features/comic/domain/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_link_refresher.dart';
import 'package:y300/features/comic/domain/services/comic_reader_service.dart';

/// 重新解析原帖并替换章节图片地址，供导出失败后的一次性重试使用。
///
/// 只在页数未变时保留原有索引关系；页数变化说明帖子结构变了，交给用户显式
/// "刷新本话"，避免导出过程中静默重排页码。
final class ReaderServiceComicImageExportLinkRefresher
    implements ComicImageExportLinkRefresher {
  const ReaderServiceComicImageExportLinkRefresher({
    required ComicRepository comicRepository,
    required Future<ComicReaderService> readerService,
  }) : _comicRepository = comicRepository,
       _readerService = readerService;

  final ComicRepository _comicRepository;
  final Future<ComicReaderService> _readerService;

  @override
  Future<bool> refresh({
    required String comicId,
    required String episodeId,
    required String sourceTid,
  }) async {
    final existing = await _comicRepository.getEpisodeImages(
      episodeId: episodeId,
    );
    final readerService = await _readerService;
    final fetchResult = await readerService.fetchEpisodeImages(sourceTid);
    if (fetchResult is! ComicEpisodeImagesFetched) {
      return false;
    }
    final urls = fetchResult.imageUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    if (urls.isEmpty || urls.length != existing.length) {
      return false;
    }
    final repository = _comicRepository;
    if (repository is! ComicEpisodeImageDirectoryReplacer) {
      return false;
    }
    await (repository as ComicEpisodeImageDirectoryReplacer)
        .replaceEpisodeImages(episodeId: episodeId, imageUrls: urls);
    return true;
  }
}
