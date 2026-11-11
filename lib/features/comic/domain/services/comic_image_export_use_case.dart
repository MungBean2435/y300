import 'package:y300/features/comic/domain/services/comic_image_export_destination.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_writer.dart';

/// 导出范围：当前章节，或整部作品的全部章节。
enum ComicImageExportScope { chapter, work }

/// 导出进度快照。只描述数量，不暴露图片 URL 或内部路径。
class ComicImageExportProgress {
  const ComicImageExportProgress({
    required this.completed,
    required this.failed,
    required this.total,
    required this.chapterTitle,
    required this.target,
  });

  final int completed;
  final int failed;
  final int total;
  final String chapterTitle;
  final ComicImageExportTarget target;

  bool get isFinished => completed + failed >= total;
}

abstract interface class ComicImageExportProgressObserver {
  void onChange(ComicImageExportProgress progress);
}

/// 协作式取消令牌：每张图、每个章节开始前检查一次。
final class ComicImageExportCancellationToken {
  bool _isCancellationRequested = false;

  bool get isCancellationRequested => _isCancellationRequested;

  void cancel() {
    _isCancellationRequested = true;
  }
}

/// 导出汇总。
class ComicImageExportResult {
  const ComicImageExportResult({
    required this.exportedCount,
    required this.failedCount,
    required this.skippedCount,
    required this.cancelled,
    required this.target,
    required this.displayLocation,
    this.failures = const <ComicImageExportWriteFailure, int>{},
  });

  const ComicImageExportResult.nothingToExport({
    required this.target,
    required this.displayLocation,
  }) : exportedCount = 0,
       failedCount = 0,
       skippedCount = 0,
       cancelled = false,
       failures = const <ComicImageExportWriteFailure, int>{};

  final int exportedCount;
  final int failedCount;

  /// 章节内没有任何图片、或图片没有可用地址时计入跳过。
  final int skippedCount;
  final bool cancelled;
  final ComicImageExportTarget target;
  final String displayLocation;
  final Map<ComicImageExportWriteFailure, int> failures;

  bool get isEmpty =>
      exportedCount == 0 && failedCount == 0 && skippedCount == 0;
}

abstract interface class ComicImageExportUseCase {
  /// 导出 [comicId] 的当前章节（[episodeId]）或整部作品。
  ///
  /// 相册与目录目标共用同一条取图/进度/取消流程，只有写入端不同。
  Future<ComicImageExportResult> export({
    required String comicId,
    required ComicImageExportTarget target,
    ComicImageExportScope scope = ComicImageExportScope.chapter,
    String? episodeId,
    ComicImageExportProgressObserver? observer,
    ComicImageExportCancellationToken? cancellationToken,
  });
}
