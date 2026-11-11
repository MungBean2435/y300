import 'package:y300/features/comic/domain/services/comic_image_export_destination.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_writer.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';

/// 写入系统相册：复用阅读器既有的平台导出通道（MediaStore / 照片库）。
///
/// 通道本身已负责权限、格式与相册内同名去重，这里只把漫画的相册名映射过去。
class GalleryComicImageExportWriter implements ComicImageExportWriter {
  const GalleryComicImageExportWriter({required ReaderImageExportSink sink})
    : _sink = sink;

  final ReaderImageExportSink _sink;

  @override
  ComicImageExportLocation get location => ComicImageExportLocation.gallery;

  @override
  Future<ComicImageExportWriteResult> write({
    required String sourcePath,
    required String relativeFolder,
    required String displayName,
    required String mimeType,
    required ComicImageExportTarget target,
  }) async {
    try {
      final destination = await _sink.save(
        sourcePath: sourcePath,
        displayName: displayName,
        mimeType: mimeType,
        albumName: relativeFolder,
      );
      return ComicImageExportWriteResult.success(destination.displayLocation);
    } on ReaderImageExportException catch (error) {
      return ComicImageExportWriteResult.failure(_mapFailure(error.reason));
    } on Object {
      return const ComicImageExportWriteResult.failure(
        ComicImageExportWriteFailure.writeFailed,
      );
    }
  }

  ComicImageExportWriteFailure _mapFailure(
    ReaderImageExportFailureReason reason,
  ) {
    return switch (reason) {
      ReaderImageExportFailureReason.cacheUnavailable =>
        ComicImageExportWriteFailure.cacheUnavailable,
      ReaderImageExportFailureReason.permissionDenied ||
      ReaderImageExportFailureReason.permissionRestricted =>
        ComicImageExportWriteFailure.permissionDenied,
      ReaderImageExportFailureReason.unsupportedPlatform ||
      ReaderImageExportFailureReason.unsupportedFormat =>
        ComicImageExportWriteFailure.unsupportedFormat,
      ReaderImageExportFailureReason.mediaWriteFailed =>
        ComicImageExportWriteFailure.writeFailed,
    };
  }
}
