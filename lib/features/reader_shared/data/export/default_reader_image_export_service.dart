import 'dart:async';
import 'dart:io';

import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';

class DefaultReaderImageExportService implements ReaderImageExportService {
  DefaultReaderImageExportService({
    required ImageCacheService imageCacheService,
    required ReaderImageExportSink sink,
  }) : _imageCacheService = imageCacheService,
       _sink = sink;

  final ImageCacheService _imageCacheService;
  final ReaderImageExportSink _sink;
  final Map<String, Future<ReaderImageExportResult>> _inFlight =
      <String, Future<ReaderImageExportResult>>{};

  @override
  Future<ReaderImageExportResult> export(ReaderImageExportRequest request) {
    final identity = _requestIdentity(request);
    final existing = _inFlight[identity];
    if (existing != null) {
      return existing;
    }
    late final Future<ReaderImageExportResult> task;
    task = _exportSafely(request).whenComplete(() {
      if (identical(_inFlight[identity], task)) {
        _inFlight.remove(identity);
      }
    });
    _inFlight[identity] = task;
    return task;
  }

  Future<ReaderImageExportResult> _exportSafely(
    ReaderImageExportRequest request,
  ) async {
    try {
      return await _export(request);
    } on Object catch (error) {
      // Keep the application service total: a cache or platform implementation
      // must never turn a toolbar action into an unhandled Future error.
      return ReaderImageExportResult.failure(
        ReaderImageExportFailureReason.mediaWriteFailed,
        message: error.toString(),
      );
    }
  }

  Future<ReaderImageExportResult> _export(
    ReaderImageExportRequest request,
  ) async {
    late final CachedImageResult cached;
    try {
      cached = await _imageCacheService.ensureCached(request.cacheRequest);
    } on Object catch (error) {
      return ReaderImageExportResult.failure(
        ReaderImageExportFailureReason.cacheUnavailable,
        message: error.toString(),
      );
    }
    final localPath = cached.localPath?.trim();
    if (!cached.success || localPath == null || localPath.isEmpty) {
      return const ReaderImageExportResult.failure(
        ReaderImageExportFailureReason.cacheUnavailable,
      );
    }

    final file = File(localPath);
    late final ReaderImageExportFormat? format;
    try {
      if (!await file.exists()) {
        return const ReaderImageExportResult.failure(
          ReaderImageExportFailureReason.cacheUnavailable,
        );
      }
      format = await ReaderImageExportFormatResolver.resolve(
        file: file,
        sourceUrl: request.cacheRequest.sourceUrl,
      );
    } on Object catch (error) {
      return ReaderImageExportResult.failure(
        ReaderImageExportFailureReason.cacheUnavailable,
        message: error.toString(),
      );
    }
    if (format == null) {
      return const ReaderImageExportResult.failure(
        ReaderImageExportFailureReason.unsupportedFormat,
      );
    }

    final displayName = ReaderImageExportFileName.sanitize(
      request.metadata.baseName,
      extension: format.extension,
    );
    try {
      final destination = await _sink.save(
        sourcePath: file.path,
        displayName: displayName,
        mimeType: format.mimeType,
        albumName: request.metadata.albumName,
      );
      return ReaderImageExportResult.success(destination);
    } on ReaderImageExportException catch (error) {
      return ReaderImageExportResult.failure(
        error.reason,
        message: error.message,
      );
    } on Object catch (error) {
      return ReaderImageExportResult.failure(
        ReaderImageExportFailureReason.mediaWriteFailed,
        message: error.toString(),
      );
    }
  }

  String _requestIdentity(ReaderImageExportRequest request) {
    final cacheKey = request.cacheRequest.cacheKey.trim();
    return '$cacheKey\n${request.cacheRequest.sourceUrl}\n'
        '${request.metadata.baseName}';
  }
}
