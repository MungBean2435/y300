import 'package:y300/features/comic/domain/services/comic_image_export_destination.dart';

/// 单张图片写入失败的分类。
enum ComicImageExportWriteFailure {
  cacheUnavailable,
  unsupportedFormat,
  permissionDenied,
  writeFailed,
  cancelled,
  unknown,
}

/// 单张图片的写入结果。
class ComicImageExportWriteResult {
  const ComicImageExportWriteResult._({
    required this.success,
    this.displayLocation,
    this.failure,
  });

  const ComicImageExportWriteResult.success(String displayLocation)
    : this._(success: true, displayLocation: displayLocation);

  const ComicImageExportWriteResult.failure(
    ComicImageExportWriteFailure failure,
  ) : this._(success: false, failure: failure);

  final bool success;

  /// 用户可读的落点，如 `Pictures/Y300/作品/章节` 或目录绝对路径。
  final String? displayLocation;
  final ComicImageExportWriteFailure? failure;
}

/// 把已缓存的图片写到 [ComicImageExportTarget]。
///
/// 相册与文件夹的差异只在这个边界内：导出用例负责取图、命名与进度，写入端
/// 负责各自的落盘规则（MediaStore 去重 / 目录内文件名去重）。
abstract interface class ComicImageExportWriter {
  ComicImageExportLocation get location;

  Future<ComicImageExportWriteResult> write({
    required String sourcePath,

    /// 相册名或目录相对路径，已按段清洗，例如 `Y300/作品/章节`。
    required String relativeFolder,
    required String displayName,
    required String mimeType,
    required ComicImageExportTarget target,
  });
}
