import 'dart:io' as io;

import 'package:y300/core/diagnostics/app_log_models.dart';
import 'package:y300/core/diagnostics/app_log_recorder.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_destination.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_link_refresher.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_use_case.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_writer.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart'
    show
        ReaderImageExportFileName,
        ReaderImageExportFormat,
        ReaderImageExportFormatResolver;

/// 顺序导出漫画图片到相册或文件夹。
///
/// 取图复用图片缓存服务（同一 cacheKey / referer，命中缓存时不重复下载），
/// 落盘按目标分派给 [ComicImageExportWriter]。导出是前台可取消任务：不写
/// SQLite、不跨重启恢复，与持久缓存队列的语义区分。
class DefaultComicImageExportUseCase implements ComicImageExportUseCase {
  DefaultComicImageExportUseCase({
    required ComicRepository comicRepository,
    required ImageCacheService imageCacheService,
    required List<ComicImageExportWriter> writers,
    String? imageReferer,
    AppLogRecorder? log,
    ComicImageExportLinkRefresher? linkRefresher,
  }) : _comicRepository = comicRepository,
       _imageCacheService = imageCacheService,
       _writers = List<ComicImageExportWriter>.unmodifiable(writers),
       _imageReferer = imageReferer,
       _log = log,
       _linkRefresher = linkRefresher;

  static const String _albumRoot = 'Y300';

  final ComicRepository _comicRepository;
  final ImageCacheService _imageCacheService;
  final List<ComicImageExportWriter> _writers;
  final String? _imageReferer;
  final AppLogRecorder? _log;
  final ComicImageExportLinkRefresher? _linkRefresher;
  final Map<String, Future<ComicImageExportResult>> _inFlight =
      <String, Future<ComicImageExportResult>>{};

  @override
  Future<ComicImageExportResult> export({
    required String comicId,
    required ComicImageExportTarget target,
    ComicImageExportScope scope = ComicImageExportScope.chapter,
    String? episodeId,
    ComicImageExportProgressObserver? observer,
    ComicImageExportCancellationToken? cancellationToken,
  }) {
    final normalizedComicId = comicId.trim();
    if (!target.isUsable || normalizedComicId.isEmpty) {
      return Future<ComicImageExportResult>.value(
        ComicImageExportResult.nothingToExport(
          target: target,
          displayLocation: _displayLocationFor(target, <String>[_albumRoot]),
        ),
      );
    }
    final identity =
        '$normalizedComicId\u0000${scope.name}\u0000'
        '${episodeId?.trim() ?? ''}\u0000${target.identity}';
    final existing = _inFlight[identity];
    if (existing != null) {
      return existing;
    }
    late final Future<ComicImageExportResult> task;
    task =
        _export(
          comicId: normalizedComicId,
          target: target,
          scope: scope,
          episodeId: episodeId?.trim(),
          observer: observer,
          cancellationToken: cancellationToken,
        ).whenComplete(() {
          if (identical(_inFlight[identity], task)) {
            _inFlight.remove(identity);
          }
        });
    _inFlight[identity] = task;
    return task;
  }

  Future<ComicImageExportResult> _export({
    required String comicId,
    required ComicImageExportTarget target,
    required ComicImageExportScope scope,
    required String? episodeId,
    required ComicImageExportProgressObserver? observer,
    required ComicImageExportCancellationToken? cancellationToken,
  }) async {
    final detail = await _comicRepository.getComicDetail(comicId: comicId);
    final comicTitle = _titleOrFallback(detail?.title, comicId);
    final episodes = await _episodesFor(
      comicId: comicId,
      scope: scope,
      episodeId: episodeId,
    );
    if (episodes.isEmpty) {
      return ComicImageExportResult.nothingToExport(
        target: target,
        displayLocation: _displayLocationFor(target, <String>[
          _albumRoot,
          _safeSegment(comicTitle),
        ]),
      );
    }

    // Resolve every chapter first so progress can report a real total instead of
    // growing while the bar moves.
    final chapterImages = <_ExportChapter>[];
    for (final episode in episodes) {
      final images = await _comicRepository.getEpisodeImages(
        episodeId: episode.episodeId,
      );
      final ordered = List<ComicEpisodeImageItem>.of(images)
        ..sort((left, right) => left.imageIndex.compareTo(right.imageIndex));
      chapterImages.add(
        _ExportChapter(
          episodeId: episode.episodeId,
          title: _titleOrFallback(episode.episodeTitle, episode.sourceTid),
          images: ordered,
        ),
      );
    }

    final total = chapterImages.fold<int>(
      0,
      (sum, chapter) => sum + chapter.images.length,
    );
    if (total == 0) {
      return ComicImageExportResult.nothingToExport(
        target: target,
        displayLocation: _displayLocationFor(target, <String>[
          _albumRoot,
          _safeSegment(comicTitle),
        ]),
      );
    }

    final writer = _writerFor(target);
    if (writer == null) {
      return ComicImageExportResult.nothingToExport(
        target: target,
        displayLocation: _displayLocationFor(target, <String>[
          _albumRoot,
          _safeSegment(comicTitle),
        ]),
      );
    }
    final failures = <ComicImageExportWriteFailure, int>{};
    var attempted = 0;
    var exported = 0;
    var failed = 0;
    var skipped = 0;
    var cancelled = false;
    String? displayLocation;

    _log?.record(
      level: AppLogLevel.info,
      scope: 'export',
      code: 'start',
      detail:
          'comic=$comicId scope=${scope.name} target=${target.location.name} '
          'chapters=${chapterImages.length} pages=$total',
    );

    for (
      var chapterIndex = 0;
      chapterIndex < chapterImages.length;
      chapterIndex++
    ) {
      var chapter = chapterImages[chapterIndex];
      final chapterFolder = _relativeFolder(
        comicTitle: comicTitle,
        chapterTitle: chapter.title,
      );
      final failedIndexes = <int>[];
      final failedReasons = <int, ComicImageExportWriteFailure>{};
      for (final image in chapter.images) {
        if (cancellationToken?.isCancellationRequested ?? false) {
          cancelled = true;
          break;
        }
        final outcome = await _exportImage(
          comicId: comicId,
          chapter: chapter,
          chapterFolder: chapterFolder,
          image: image,
          target: target,
          writer: writer,
        );
        attempted += 1;
        switch (outcome) {
          case _ExportSuccess(:final location):
            exported += 1;
            if (location != null && location.isNotEmpty) {
              displayLocation = location;
            }
          case _ExportSkipped():
            skipped += 1;
          case _ExportFailed(:final reason):
            failed += 1;
            failedIndexes.add(image.imageIndex);
            failedReasons[image.imageIndex] = reason;
            failures.update(reason, (count) => count + 1, ifAbsent: () => 1);
        }
        observer?.onChange(
          ComicImageExportProgress(
            completed: attempted,
            failed: failed,
            total: total,
            chapterTitle: chapter.title,
            target: target,
          ),
        );
      }
      if (cancelled) {
        break;
      }
      // 一次性有界重试：附件链接过期（404/403）时重新解析原帖拿新地址。
      // 页数变化说明章节结构变了，交给用户显式刷新，导出不静默重排。
      if (failedIndexes.isNotEmpty) {
        final refreshed = await _refreshChapterLinks(
          comicId: comicId,
          chapter: chapter,
        );
        if (refreshed != null) {
          chapter = refreshed;
          chapterImages[chapterIndex] = refreshed;
          for (final failedIndex in failedIndexes) {
            if (cancellationToken?.isCancellationRequested ?? false) {
              cancelled = true;
              break;
            }
            final image = _imageAtIndex(refreshed, failedIndex);
            if (image == null) {
              continue;
            }
            final retry = await _exportImage(
              comicId: comicId,
              chapter: refreshed,
              chapterFolder: chapterFolder,
              image: image,
              target: target,
              writer: writer,
            );
            if (retry is! _ExportSuccess) {
              continue;
            }
            final previousReason = failedReasons.remove(failedIndex);
            if (previousReason != null) {
              final remaining = (failures[previousReason] ?? 1) - 1;
              if (remaining <= 0) {
                failures.remove(previousReason);
              } else {
                failures[previousReason] = remaining;
              }
            }
            failed -= 1;
            exported += 1;
            if (retry.location != null && retry.location!.isNotEmpty) {
              displayLocation = retry.location;
            }
            _log?.record(
              level: AppLogLevel.info,
              scope: 'export',
              code: 'retry_ok',
              detail: 'episode=${chapter.episodeId} page=$failedIndex',
            );
          }
        }
      }
    }

    final resolvedLocation =
        displayLocation ??
        _displayLocationFor(target, <String>[
          _albumRoot,
          _safeSegment(comicTitle),
        ]);
    _log?.record(
      level: failed > 0 ? AppLogLevel.warning : AppLogLevel.info,
      scope: 'export',
      code: 'done',
      detail:
          'exported=$exported failed=$failed skipped=$skipped '
          'cancelled=$cancelled target=${target.location.name}',
    );
    return ComicImageExportResult(
      exportedCount: exported,
      failedCount: failed,
      skippedCount: skipped,
      cancelled: cancelled,
      target: target,
      displayLocation: resolvedLocation,
      failures: Map<ComicImageExportWriteFailure, int>.unmodifiable(failures),
    );
  }

  Future<_ExportChapter?> _refreshChapterLinks({
    required String comicId,
    required _ExportChapter chapter,
  }) async {
    final refresher = _linkRefresher;
    if (refresher == null) {
      return null;
    }
    final refreshed = await refresher.refresh(
      comicId: comicId,
      episodeId: chapter.episodeId,
      sourceTid: _sourceTidOf(chapter.episodeId),
    );
    if (!refreshed) {
      return null;
    }
    final images = await _comicRepository.getEpisodeImages(
      episodeId: chapter.episodeId,
    );
    if (images.length != chapter.images.length) {
      return null;
    }
    final ordered = List<ComicEpisodeImageItem>.of(images)
      ..sort((left, right) => left.imageIndex.compareTo(right.imageIndex));
    _log?.record(
      level: AppLogLevel.info,
      scope: 'export',
      code: 'link_refreshed',
      detail: 'episode=${chapter.episodeId} pages=${ordered.length}',
    );
    return _ExportChapter(
      episodeId: chapter.episodeId,
      title: chapter.title,
      images: ordered,
    );
  }

  ComicEpisodeImageItem? _imageAtIndex(_ExportChapter chapter, int index) {
    for (final image in chapter.images) {
      if (image.imageIndex == index) {
        return image;
      }
    }
    return null;
  }

  Future<List<ComicEpisodeItem>> _episodesFor({
    required String comicId,
    required ComicImageExportScope scope,
    required String? episodeId,
  }) async {
    final episodes = await _comicRepository.getComicEpisodes(
      comicId: comicId,
      descending: false,
    );
    if (scope == ComicImageExportScope.work || episodeId == null) {
      return episodes;
    }
    final matched = episodes
        .where((episode) => episode.episodeId == episodeId)
        .toList(growable: false);
    if (matched.isNotEmpty) {
      return matched;
    }
    // Hidden or just-removed chapters are still readable; export by identity
    // instead of failing on the catalog mismatch.
    return <ComicEpisodeItem>[
      ComicEpisodeItem(
        comicId: comicId,
        episodeId: episodeId,
        episodeTitle: null,
        sourceTid: _sourceTidOf(episodeId),
        sourceUrl: '',
        orderIndex: 0,
        publishTimeText: null,
      ),
    ];
  }

  Future<_ExportImageOutcome> _exportImage({
    required String comicId,
    required _ExportChapter chapter,
    required String chapterFolder,
    required ComicEpisodeImageItem image,
    required ComicImageExportTarget target,
    required ComicImageExportWriter writer,
  }) async {
    final sourceUrl = image.effectiveSourceUrl.trim();
    if (sourceUrl.isEmpty) {
      return const _ExportImageOutcome.skipped();
    }
    final cacheKey = _cacheKeyFor(comicId: comicId, image: image);
    final cached = await _imageCacheService.ensureCached(
      ImageCacheRequest(
        cacheKey: cacheKey,
        sourceUrl: sourceUrl,
        referer: _imageReferer,
        ownerType: ImageCacheOwnerType.comic,
        ownerId: comicId,
        role: ImageCacheRole.comicPage,
        episodeId: chapter.episodeId,
        imageIndex: image.imageIndex,
        retentionClass: ImageRetentionClass.recentReader,
      ),
    );
    final localPath = cached.localPath?.trim();
    if (!cached.success || localPath == null || localPath.isEmpty) {
      _log?.record(
        level: AppLogLevel.warning,
        scope: 'export',
        code: 'cache_unavailable',
        detail:
            'episode=${chapter.episodeId} page=${image.imageIndex} '
            'key=$cacheKey',
      );
      return const _ExportImageOutcome.failed(
        ComicImageExportWriteFailure.cacheUnavailable,
      );
    }
    final ReaderImageExportFormat? format;
    try {
      format = await ReaderImageExportFormatResolver.resolve(
        file: io.File(localPath),
        sourceUrl: sourceUrl,
      );
    } on Object {
      return const _ExportImageOutcome.failed(
        ComicImageExportWriteFailure.cacheUnavailable,
      );
    }
    if (format == null) {
      _log?.record(
        level: AppLogLevel.warning,
        scope: 'export',
        code: 'unsupported_format',
        detail: 'episode=${chapter.episodeId} page=${image.imageIndex}',
      );
      return const _ExportImageOutcome.failed(
        ComicImageExportWriteFailure.unsupportedFormat,
      );
    }
    final displayName = ReaderImageExportFileName.sanitize(
      '${chapter.title}-${image.imageIndex + 1}',
      extension: format.extension,
    );
    final result = await writer.write(
      sourcePath: localPath,
      relativeFolder: chapterFolder,
      displayName: displayName,
      mimeType: format.mimeType,
      target: target,
    );
    if (!result.success) {
      final reason = result.failure ?? ComicImageExportWriteFailure.unknown;
      _log?.record(
        level: AppLogLevel.error,
        scope: 'export',
        code: 'write_failed',
        detail:
            'episode=${chapter.episodeId} page=${image.imageIndex} '
            'reason=${reason.name} target=${target.location.name}',
      );
      return _ExportImageOutcome.failed(reason);
    }
    return _ExportImageOutcome.success(result.displayLocation);
  }

  ComicImageExportWriter? _writerFor(ComicImageExportTarget target) {
    for (final writer in _writers) {
      if (writer.location == target.location) {
        return writer;
      }
    }
    return null;
  }

  String _cacheKeyFor({
    required String comicId,
    required ComicEpisodeImageItem image,
  }) {
    final stable = image.stableCacheKey?.trim();
    if (stable != null && stable.isNotEmpty) {
      return stable;
    }
    return ImageCacheKeys.comicPage(
      comicId: comicId,
      episodeId: image.episodeId,
      imageIndex: image.imageIndex,
    );
  }

  String _relativeFolder({
    required String comicTitle,
    required String chapterTitle,
  }) {
    return <String>[
      _albumRoot,
      _safeSegment(comicTitle),
      _safeSegment(chapterTitle),
    ].join('/');
  }

  String _displayLocationFor(
    ComicImageExportTarget target,
    List<String> parts,
  ) {
    final relative = parts.join('/');
    if (target.location == ComicImageExportLocation.gallery) {
      return relative;
    }
    final root = target.directoryPath?.trim() ?? '';
    return root.isEmpty ? relative : '$root/$relative';
  }

  String _safeSegment(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sanitized.isEmpty) {
      return 'untitled';
    }
    return sanitized.length > 60
        ? sanitized.substring(0, 60).trimRight()
        : sanitized;
  }

  String _sourceTidOf(String episodeId) {
    final separator = episodeId.lastIndexOf(':');
    if (separator < 0 || separator == episodeId.length - 1) {
      return episodeId;
    }
    return episodeId.substring(separator + 1);
  }

  String _titleOrFallback(String? value, String fallback) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }
}

class _ExportChapter {
  const _ExportChapter({
    required this.episodeId,
    required this.title,
    required this.images,
  });

  final String episodeId;
  final String title;
  final List<ComicEpisodeImageItem> images;
}

sealed class _ExportImageOutcome {
  const _ExportImageOutcome();

  const factory _ExportImageOutcome.success(String? location) = _ExportSuccess;

  const factory _ExportImageOutcome.failed(
    ComicImageExportWriteFailure reason,
  ) = _ExportFailed;

  const factory _ExportImageOutcome.skipped() = _ExportSkipped;
}

class _ExportSuccess extends _ExportImageOutcome {
  const _ExportSuccess(this.location);

  final String? location;
}

class _ExportFailed extends _ExportImageOutcome {
  const _ExportFailed(this.reason);

  final ComicImageExportWriteFailure reason;
}

class _ExportSkipped extends _ExportImageOutcome {
  const _ExportSkipped();
}
