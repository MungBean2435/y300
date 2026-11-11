import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:y300/features/comic/domain/services/comic_image_export_destination.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_writer.dart';

/// 写入用户选择的文件夹，保留 `<根目录>/<作品>/<章节>/序号.jpg` 结构。
///
/// 与相册目标的区别：目录可能被外部文件管理器写入同名文件，因此这里自行做
/// `(1)`、`(2)` 后缀去重；图片字节从缓存文件复制，成功后才报告已导出。
class DirectoryComicImageExportWriter implements ComicImageExportWriter {
  const DirectoryComicImageExportWriter();

  @override
  ComicImageExportLocation get location => ComicImageExportLocation.directory;

  @override
  Future<ComicImageExportWriteResult> write({
    required String sourcePath,
    required String relativeFolder,
    required String displayName,
    required String mimeType,
    required ComicImageExportTarget target,
  }) async {
    final rootPath = target.directoryPath?.trim();
    if (rootPath == null || rootPath.isEmpty) {
      return const ComicImageExportWriteResult.failure(
        ComicImageExportWriteFailure.writeFailed,
      );
    }
    final segments = relativeFolder
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final directory = io.Directory(p.joinAll(<String>[rootPath, ...segments]));
    try {
      await directory.create(recursive: true);
      final destination = await _uniqueFile(directory, displayName);
      await io.File(sourcePath).copy(destination.path);
      return ComicImageExportWriteResult.success(directory.path);
    } on io.FileSystemException catch (error) {
      return ComicImageExportWriteResult.failure(
        _isPermissionError(error)
            ? ComicImageExportWriteFailure.permissionDenied
            : ComicImageExportWriteFailure.writeFailed,
      );
    } on Object {
      return const ComicImageExportWriteResult.failure(
        ComicImageExportWriteFailure.writeFailed,
      );
    }
  }

  bool _isPermissionError(io.FileSystemException error) {
    final code = error.osError?.errorCode;
    // EACCES / EPERM on POSIX; Android SAF 撤销授权时也会落到这两种错误。
    if (code == 13 || code == 1) {
      return true;
    }
    return error.message.toLowerCase().contains('permission denied');
  }

  Future<io.File> _uniqueFile(
    io.Directory directory,
    String displayName,
  ) async {
    final dot = displayName.lastIndexOf('.');
    final base = dot > 0 ? displayName.substring(0, dot) : displayName;
    final extension = dot > 0 ? displayName.substring(dot) : '';
    var candidate = io.File(p.join(directory.path, displayName));
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = io.File(p.join(directory.path, '$base ($suffix)$extension'));
      suffix += 1;
    }
    return candidate;
  }
}
