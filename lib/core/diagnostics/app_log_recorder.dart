import 'package:flutter/foundation.dart';
import 'package:y300/core/diagnostics/app_log_models.dart';

/// 进程内诊断日志记录器。
///
/// 只保留最近 [capacity] 条，不写文件、不联网、不上报；页面被杀后自然清空。
/// 读法用 [entries] 的 ValueListenable，写入是同步的，方便在失败路径上调用。
abstract interface class AppLogRecorder {
  ValueListenable<List<AppLogEntry>> get entries;

  void record({
    required AppLogLevel level,
    required String scope,
    required String code,
    String? detail,
  });

  void clear();
}

final class RingBufferAppLogRecorder implements AppLogRecorder {
  RingBufferAppLogRecorder({this.capacity = 400})
    : assert(capacity > 0),
      _entries = ValueNotifier<List<AppLogEntry>>(
        const <AppLogEntry>[],
      );

  final int capacity;
  final ValueNotifier<List<AppLogEntry>> _entries;
  int _dropped = 0;

  @override
  ValueListenable<List<AppLogEntry>> get entries => _entries;

  /// 因容量上限被丢弃的条数（提示用户"只看到最近 N 条"）。
  int get droppedCount => _dropped;

  @override
  void record({
    required AppLogLevel level,
    required String scope,
    required String code,
    String? detail,
  }) {
    final entry = AppLogEntry(
      at: DateTime.now(),
      level: level,
      scope: scope,
      code: code,
      detail: detail,
    );
    final next = List<AppLogEntry>.of(_entries.value)..add(entry);
    if (next.length > capacity) {
      final overflow = next.length - capacity;
      next.removeRange(0, overflow);
      _dropped += overflow;
    }
    _entries.value = List<AppLogEntry>.unmodifiable(next);
  }

  @override
  void clear() {
    _dropped = 0;
    _entries.value = const <AppLogEntry>[];
  }

  void dispose() {
    _entries.dispose();
  }
}
