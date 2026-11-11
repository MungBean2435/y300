import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:y300/features/cache/domain/models/image_cache_models.dart';

enum ReaderImageExportPlatform { android, ios, unsupported }

class ReaderImageExportMetadata {
  const ReaderImageExportMetadata({required this.baseName, this.albumName});

  final String baseName;
  final String? albumName;
}

class ReaderImageExportRequest {
  const ReaderImageExportRequest({
    required this.cacheRequest,
    required this.metadata,
  });

  final ImageCacheRequest cacheRequest;
  final ReaderImageExportMetadata metadata;
}

class ReaderImageExportDestination {
  const ReaderImageExportDestination({
    required this.platform,
    required this.locator,
    required this.displayLocation,
  });

  final ReaderImageExportPlatform platform;

  /// Android content URI or iOS PhotoKit asset local identifier.
  final String locator;
  final String displayLocation;
}

enum ReaderImageExportFailureReason {
  cacheUnavailable,
  permissionDenied,
  permissionRestricted,
  unsupportedPlatform,
  unsupportedFormat,
  mediaWriteFailed,
}

class ReaderImageExportResult {
  const ReaderImageExportResult._({
    required this.success,
    this.destination,
    this.failureReason,
    this.message,
  });

  const ReaderImageExportResult.success(
    ReaderImageExportDestination destination,
  ) : this._(success: true, destination: destination);

  const ReaderImageExportResult.failure(
    ReaderImageExportFailureReason reason, {
    String? message,
  }) : this._(success: false, failureReason: reason, message: message);

  final bool success;
  final ReaderImageExportDestination? destination;
  final ReaderImageExportFailureReason? failureReason;
  final String? message;
}

class ReaderImageExportException implements Exception {
  const ReaderImageExportException(this.reason, [this.message]);

  final ReaderImageExportFailureReason reason;
  final String? message;

  @override
  String toString() {
    final detail = message;
    return detail == null || detail.isEmpty
        ? 'ReaderImageExportException($reason)'
        : 'ReaderImageExportException($reason): $detail';
  }
}

abstract interface class ReaderImageExportSink {
  Future<ReaderImageExportDestination> save({
    required String sourcePath,
    required String displayName,
    required String mimeType,
    String? albumName,
  });
}

abstract interface class ReaderImageExportService {
  Future<ReaderImageExportResult> export(ReaderImageExportRequest request);
}

class ReaderImageExportFormat {
  const ReaderImageExportFormat({
    required this.mimeType,
    required this.extension,
  });

  final String mimeType;
  final String extension;
}

class ReaderImageExportFormatResolver {
  const ReaderImageExportFormatResolver._();

  static Future<ReaderImageExportFormat?> resolve({
    required File file,
    required String sourceUrl,
  }) async {
    final header = await _readHeader(file);
    if (_startsWith(header, const <int>[0xFF, 0xD8, 0xFF])) {
      return const ReaderImageExportFormat(
        mimeType: 'image/jpeg',
        extension: 'jpg',
      );
    }
    if (_startsWith(header, const <int>[0x89, 0x50, 0x4E, 0x47])) {
      return const ReaderImageExportFormat(
        mimeType: 'image/png',
        extension: 'png',
      );
    }
    if (_startsWith(header, const <int>[0x47, 0x49, 0x46, 0x38])) {
      return const ReaderImageExportFormat(
        mimeType: 'image/gif',
        extension: 'gif',
      );
    }
    if (_startsWith(header, const <int>[0x52, 0x49, 0x46, 0x46]) &&
        header.length >= 12 &&
        String.fromCharCodes(header.sublist(8, 12)) == 'WEBP') {
      return const ReaderImageExportFormat(
        mimeType: 'image/webp',
        extension: 'webp',
      );
    }

    final extension = p
        .extension(Uri.tryParse(sourceUrl)?.path ?? '')
        .toLowerCase()
        .replaceFirst('.', '');
    return switch (extension) {
      'jpg' || 'jpeg' => const ReaderImageExportFormat(
        mimeType: 'image/jpeg',
        extension: 'jpg',
      ),
      'png' => const ReaderImageExportFormat(
        mimeType: 'image/png',
        extension: 'png',
      ),
      'gif' => const ReaderImageExportFormat(
        mimeType: 'image/gif',
        extension: 'gif',
      ),
      'webp' => const ReaderImageExportFormat(
        mimeType: 'image/webp',
        extension: 'webp',
      ),
      _ => null,
    };
  }

  static Future<List<int>> _readHeader(File file) async {
    final bytes = <int>[];
    await for (final chunk in file.openRead(0, 16)) {
      bytes.addAll(chunk);
      if (bytes.length >= 16) {
        break;
      }
    }
    return bytes;
  }

  static bool _startsWith(List<int> value, List<int> prefix) {
    if (value.length < prefix.length) {
      return false;
    }
    for (var i = 0; i < prefix.length; i++) {
      if (value[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }
}

class ReaderImageExportFileName {
  const ReaderImageExportFileName._();

  static String sanitize(String baseName, {required String extension}) {
    var value = baseName.trim();
    value = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    value = value.replaceFirst(RegExp(r'\.$'), '_');
    if (value.isEmpty) {
      value = 'Y300-image';
    }
    if (value.length > 96) {
      value = value.substring(0, 96).trimRight();
    }
    final suffix = '.$extension';
    if (!value.toLowerCase().endsWith(suffix)) {
      value += suffix;
    }
    return value;
  }
}
