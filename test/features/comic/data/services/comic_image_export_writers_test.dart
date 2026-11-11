import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/services/directory_comic_image_export_writer.dart';
import 'package:y300/features/comic/data/services/gallery_comic_image_export_writer.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_destination.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_writer.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';

void main() {
  test('directory writer mirrors the work/chapter folder structure', () async {
    final root = await _tempDirectory();
    final source = await _sourceImage(root);
    const writer = DirectoryComicImageExportWriter();

    final result = await writer.write(
      sourcePath: source.path,
      relativeFolder: 'Y300/作品 A/第 1 话',
      displayName: '001.jpg',
      mimeType: 'image/jpeg',
      target: ComicImageExportTarget.directory(root.path),
    );

    expect(result.success, isTrue);
    expect(result.displayLocation, contains('第 1 话'));
    final written = io.File('${root.path}/Y300/作品 A/第 1 话/001.jpg');
    expect(written.existsSync(), isTrue);
    expect(written.lengthSync(), source.lengthSync());
  });

  test('directory writer never overwrites an existing file', () async {
    final root = await _tempDirectory();
    final source = await _sourceImage(root);
    const writer = DirectoryComicImageExportWriter();

    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await writer.write(
        sourcePath: source.path,
        relativeFolder: 'Y300/work/chapter',
        displayName: '001.jpg',
        mimeType: 'image/jpeg',
        target: ComicImageExportTarget.directory(root.path),
      );
      expect(result.success, isTrue);
    }

    final directory = io.Directory('${root.path}/Y300/work/chapter');
    final names = directory
        .listSync()
        .whereType<io.File>()
        .map((file) => file.uri.pathSegments.last)
        .toSet();
    expect(names, <String>{'001.jpg', '001 (1).jpg'});
  });

  test('directory writer fails without a usable directory target', () async {
    final root = await _tempDirectory();
    final source = await _sourceImage(root);
    const writer = DirectoryComicImageExportWriter();

    final result = await writer.write(
      sourcePath: source.path,
      relativeFolder: 'Y300/work/chapter',
      displayName: '001.jpg',
      mimeType: 'image/jpeg',
      target: const ComicImageExportTarget.directory('  '),
    );

    expect(result.success, isFalse);
    expect(result.failure, ComicImageExportWriteFailure.writeFailed);
  });

  test(
    'gallery writer forwards the album and reports the destination',
    () async {
      final sink = _RecordingSink();
      final writer = GalleryComicImageExportWriter(sink: sink);

      final result = await writer.write(
        sourcePath: '/tmp/source.jpg',
        relativeFolder: 'Y300/作品/第 1 话',
        displayName: '001.jpg',
        mimeType: 'image/jpeg',
        target: const ComicImageExportTarget.gallery(),
      );

      expect(result.success, isTrue);
      expect(sink.albumNames, <String?>['Y300/作品/第 1 话']);
      expect(sink.displayNames, <String>['001.jpg']);
      expect(result.displayLocation, 'Pictures/Y300/作品/第 1 话/001.jpg');
    },
  );

  test('gallery writer maps a permission failure', () async {
    final sink = _RecordingSink(
      failure: const ReaderImageExportException(
        ReaderImageExportFailureReason.permissionDenied,
      ),
    );
    final writer = GalleryComicImageExportWriter(sink: sink);

    final result = await writer.write(
      sourcePath: '/tmp/source.jpg',
      relativeFolder: 'Y300/作品/第 1 话',
      displayName: '001.jpg',
      mimeType: 'image/jpeg',
      target: const ComicImageExportTarget.gallery(),
    );

    expect(result.success, isFalse);
    expect(result.failure, ComicImageExportWriteFailure.permissionDenied);
  });
}

Future<io.Directory> _tempDirectory() async {
  final directory = await io.Directory.systemTemp.createTemp('y300-export-');
  addTearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });
  return directory;
}

Future<io.File> _sourceImage(io.Directory root) async {
  final file = io.File('${root.path}/source.jpg');
  await file.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 1, 2, 3]);
  return file;
}

class _RecordingSink implements ReaderImageExportSink {
  _RecordingSink({this.failure});

  final ReaderImageExportException? failure;
  final List<String?> albumNames = <String?>[];
  final List<String> displayNames = <String>[];

  @override
  Future<ReaderImageExportDestination> save({
    required String sourcePath,
    required String displayName,
    required String mimeType,
    String? albumName,
  }) async {
    final error = failure;
    if (error != null) {
      throw error;
    }
    albumNames.add(albumName);
    displayNames.add(displayName);
    return ReaderImageExportDestination(
      platform: ReaderImageExportPlatform.android,
      locator: 'content://media/external/images/media/1',
      displayLocation: 'Pictures/$albumName/$displayName',
    );
  }
}
