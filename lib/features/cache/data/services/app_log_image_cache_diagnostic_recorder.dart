import 'package:y300/core/diagnostics/app_log_models.dart';
import 'package:y300/core/diagnostics/app_log_recorder.dart';
import 'package:y300/features/cache/data/services/image_cache_diagnostic_recorder.dart';

/// 把图片缓存的隐私安全诊断事件写进应用内日志。
///
/// 事件本身不含 URL/路径（只有 cacheKey fingerprint），因此可以把阶段、失败分类、
/// 服务端状态码和耗时原样展示，方便在手机上定位"图片总加载不出来"。
final class AppLogImageCacheDiagnosticRecorder
    implements ImageCacheDiagnosticRecorder {
  const AppLogImageCacheDiagnosticRecorder(this._log);

  final AppLogRecorder _log;

  @override
  void recordFailure(ImageCacheFailureDiagnostic event) {
    final status = event.statusCode;
    _log.record(
      level: _levelFor(event.failureKind),
      scope: 'image',
      code: '${event.stage.name}/${event.failureKind.name}',
      detail: <String>[
        'code=${event.reasonCode}',
        if (status != null) 'http=$status',
        'ms=${event.elapsedMilliseconds}',
        'owner=${event.ownerType}/${event.role}',
        'key=${event.cacheKeyFingerprint}',
        if (event.bytesReceived != null) 'bytes=${event.bytesReceived}',
        if (event.exceptionType.isNotEmpty) 'err=${event.exceptionType}',
      ].join(' '),
    );
  }

  AppLogLevel _levelFor(ImageCacheDiagnosticFailureKind kind) {
    return switch (kind) {
      ImageCacheDiagnosticFailureKind.unauthorized ||
      ImageCacheDiagnosticFailureKind.securityChallenge ||
      ImageCacheDiagnosticFailureKind.notFound ||
      ImageCacheDiagnosticFailureKind.invalidContent ||
      ImageCacheDiagnosticFailureKind.invalidRequest ||
      ImageCacheDiagnosticFailureKind.decode ||
      ImageCacheDiagnosticFailureKind.server ||
      ImageCacheDiagnosticFailureKind.unsupported => AppLogLevel.warning,
      ImageCacheDiagnosticFailureKind.cancelled => AppLogLevel.info,
      ImageCacheDiagnosticFailureKind.network ||
      ImageCacheDiagnosticFailureKind.timeout ||
      ImageCacheDiagnosticFailureKind.redirectRejected ||
      ImageCacheDiagnosticFailureKind.fileSystem ||
      ImageCacheDiagnosticFailureKind.cacheManager ||
      ImageCacheDiagnosticFailureKind.indexStore ||
      ImageCacheDiagnosticFailureKind.unknown => AppLogLevel.error,
    };
  }
}
