import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/diagnostics/app_log_recorder.dart';

/// 全应用共享的诊断日志环形缓冲。
final appLogRecorderProvider = Provider<AppLogRecorder>((ref) {
  final recorder = RingBufferAppLogRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});
