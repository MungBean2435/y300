import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/comic/data/use_cases/comic_image_export_use_case_impl.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_destination.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_use_case.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_writer.dart';

void main() {
  test(
    'chapter export follows image index order and reports a real total',
    () async {
      final repository = _FakeComicRepository(
        episodes: <ComicEpisodeItem>[
          _episode('101', orderIndex: 0, title: '第 1 话'),
        ],
        images: <String, List<ComicEpisodeImageItem>>{
          'yamibo:100:101': <ComicEpisodeImageItem>[
            _image('yamibo:100:101', index: 2),
            _image('yamibo:100:101', index: 0),
            _image('yamibo:100:101', index: 1),
          ],
        },
      );
      final cache = _FakeImageCacheService();
      final galleryWriter = _RecordingWriter(ComicImageExportLocation.gallery);
      final useCase = DefaultComicImageExportUseCase(
        comicRepository: repository,
        imageCacheService: cache,
        writers: <ComicImageExportWriter>[
          galleryWriter,
          _RecordingWriter(ComicImageExportLocation.directory),
        ],
        imageReferer: 'https://bbs.yamibo.com/',
      );
      final progress = <ComicImageExportProgress>[];

      final result = await useCase.export(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
        target: const ComicImageExportTarget.gallery(),
        observer: _RecordingObserver(progress),
      );

      expect(result.exportedCount, 3);
      expect(result.failedCount, 0);
      expect(galleryWriter.written, hasLength(3));
      expect(galleryWriter.written[0], endsWith('.jpg'));
      expect(cache.ensuredKeys, <String>[
        'comic/yamibo:100/yamibo:100:101/000',
        'comic/yamibo:100/yamibo:100:101/001',
        'comic/yamibo:100/yamibo:100:101/002',
      ]);
      expect(cache.referers, everyElement('https://bbs.yamibo.com/'));
      expect(progress.last.total, 3);
      expect(progress.last.completed, 3);
    },
  );

  test('work export walks every chapter in catalog order', () async {
    final repository = _FakeComicRepository(
      episodes: <ComicEpisodeItem>[
        _episode('101', orderIndex: 0, title: '第 1 话'),
        _episode('102', orderIndex: 1, title: '第 2 话'),
      ],
      images: <String, List<ComicEpisodeImageItem>>{
        'yamibo:100:101': <ComicEpisodeImageItem>[
          _image('yamibo:100:101', index: 0),
        ],
        'yamibo:100:102': <ComicEpisodeImageItem>[
          _image('yamibo:100:102', index: 0),
          _image('yamibo:100:102', index: 1),
        ],
      },
    );
    final useCase = DefaultComicImageExportUseCase(
      comicRepository: repository,
      imageCacheService: _FakeImageCacheService(),
      writers: <ComicImageExportWriter>[
        _RecordingWriter(ComicImageExportLocation.directory),
      ],
    );

    final result = await useCase.export(
      comicId: 'yamibo:100',
      scope: ComicImageExportScope.work,
      target: const ComicImageExportTarget.directory('/tmp/y300-export'),
    );

    expect(result.exportedCount, 3);
    expect(result.failedCount, 0);
  });

  test(
    'cancellation stops after the current page and keeps partial counts',
    () async {
      final repository = _FakeComicRepository(
        episodes: <ComicEpisodeItem>[_episode('101', orderIndex: 0)],
        images: <String, List<ComicEpisodeImageItem>>{
          'yamibo:100:101': <ComicEpisodeImageItem>[
            _image('yamibo:100:101', index: 0),
            _image('yamibo:100:101', index: 1),
            _image('yamibo:100:101', index: 2),
          ],
        },
      );
      final writer = _RecordingWriter(ComicImageExportLocation.gallery);
      final useCase = DefaultComicImageExportUseCase(
        comicRepository: repository,
        imageCacheService: _FakeImageCacheService(),
        writers: <ComicImageExportWriter>[writer],
      );
      final token = ComicImageExportCancellationToken();

      final result = await useCase.export(
        comicId: 'yamibo:100',
        episodeId: 'yamibo:100:101',
        target: const ComicImageExportTarget.gallery(),
        cancellationToken: token,
        observer: _CancellingObserver(token),
      );

      expect(result.cancelled, isTrue);
      expect(result.exportedCount, 1);
      expect(writer.written, hasLength(1));
    },
  );

  test('cache failures are counted without aborting the rest', () async {
    final repository = _FakeComicRepository(
      episodes: <ComicEpisodeItem>[_episode('101', orderIndex: 0)],
      images: <String, List<ComicEpisodeImageItem>>{
        'yamibo:100:101': <ComicEpisodeImageItem>[
          _image('yamibo:100:101', index: 0),
          _image('yamibo:100:101', index: 1),
        ],
      },
    );
    final cache = _FakeImageCacheService(
      failKeys: <String>{'comic/yamibo:100/yamibo:100:101/000'},
    );
    final useCase = DefaultComicImageExportUseCase(
      comicRepository: repository,
      imageCacheService: cache,
      writers: <ComicImageExportWriter>[
        _RecordingWriter(ComicImageExportLocation.gallery),
      ],
    );

    final result = await useCase.export(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:101',
      target: const ComicImageExportTarget.gallery(),
    );

    expect(result.exportedCount, 1);
    expect(result.failedCount, 1);
    expect(result.failures[ComicImageExportWriteFailure.cacheUnavailable], 1);
  });

  test('an empty chapter reports nothing to export', () async {
    final repository = _FakeComicRepository(
      episodes: <ComicEpisodeItem>[_episode('101', orderIndex: 0)],
      images: const <String, List<ComicEpisodeImageItem>>{},
    );
    final useCase = DefaultComicImageExportUseCase(
      comicRepository: repository,
      imageCacheService: _FakeImageCacheService(),
      writers: <ComicImageExportWriter>[
        _RecordingWriter(ComicImageExportLocation.gallery),
      ],
    );

    final result = await useCase.export(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:101',
      target: const ComicImageExportTarget.gallery(),
    );

    expect(result.isEmpty, isTrue);
    expect(result.exportedCount, 0);
  });

  test('identical concurrent exports share one running task', () async {
    final repository = _FakeComicRepository(
      episodes: <ComicEpisodeItem>[_episode('101', orderIndex: 0)],
      images: <String, List<ComicEpisodeImageItem>>{
        'yamibo:100:101': <ComicEpisodeImageItem>[
          _image('yamibo:100:101', index: 0),
        ],
      },
    );
    final writer = _RecordingWriter(ComicImageExportLocation.gallery);
    final useCase = DefaultComicImageExportUseCase(
      comicRepository: repository,
      imageCacheService: _FakeImageCacheService(),
      writers: <ComicImageExportWriter>[writer],
    );

    final first = useCase.export(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:101',
      target: const ComicImageExportTarget.gallery(),
    );
    final second = useCase.export(
      comicId: 'yamibo:100',
      episodeId: 'yamibo:100:101',
      target: const ComicImageExportTarget.gallery(),
    );

    expect(identical(first, second), isTrue);
    await Future.wait(<Future<ComicImageExportResult>>[first, second]);
    expect(writer.written, hasLength(1));
  });
}

class _RecordingObserver implements ComicImageExportProgressObserver {
  _RecordingObserver(this.progress);

  final List<ComicImageExportProgress> progress;

  @override
  void onChange(ComicImageExportProgress value) {
    progress.add(value);
  }
}

class _CancellingObserver implements ComicImageExportProgressObserver {
  _CancellingObserver(this.token);

  final ComicImageExportCancellationToken token;

  @override
  void onChange(ComicImageExportProgress progress) {
    if (progress.completed >= 1) {
      token.cancel();
    }
  }
}

class _RecordingWriter implements ComicImageExportWriter {
  _RecordingWriter(this.location);

  @override
  final ComicImageExportLocation location;
  final List<String> written = <String>[];

  @override
  Future<ComicImageExportWriteResult> write({
    required String sourcePath,
    required String relativeFolder,
    required String displayName,
    required String mimeType,
    required ComicImageExportTarget target,
  }) async {
    written.add(displayName);
    return ComicImageExportWriteResult.success(relativeFolder);
  }
}

class _FakeImageCacheService implements ImageCacheService {
  _FakeImageCacheService({Set<String>? failKeys}) : _failKeys = failKeys;

  final Set<String>? _failKeys;
  final List<String> ensuredKeys = <String>[];
  final List<String?> referers = <String?>[];

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    ensuredKeys.add(request.cacheKey);
    referers.add(request.referer);
    if (_failKeys?.contains(request.cacheKey) ?? false) {
      return CachedImageResult.failed;
    }
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: '/tmp/y300-export-source.jpg',
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async => CachedImageResult.failed;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<void> clearUnprotected() async {}
}

class _FakeComicRepository implements ComicRepository {
  _FakeComicRepository({required this.episodes, required this.images});

  final List<ComicEpisodeItem> episodes;
  final Map<String, List<ComicEpisodeImageItem>> images;

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async => null;

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
  }) async {
    return episodes;
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({
    required String episodeId,
  }) async {
    return images[episodeId] ?? const <ComicEpisodeImageItem>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ComicEpisodeItem _episode(
  String tid, {
  required int orderIndex,
  String? title,
}) {
  return ComicEpisodeItem(
    comicId: 'yamibo:100',
    episodeId: 'yamibo:100:$tid',
    episodeTitle: title,
    sourceTid: tid,
    sourceUrl: 'https://bbs.yamibo.com/thread-$tid-1-1.html',
    orderIndex: orderIndex,
    publishTimeText: null,
  );
}

ComicEpisodeImageItem _image(String episodeId, {required int index}) {
  return ComicEpisodeImageItem(
    episodeId: episodeId,
    imageUrl: 'https://img.test/$episodeId-$index.jpg',
    imageIndex: index,
    cacheStatus: 'none',
  );
}
