/// 一条应用内诊断日志。
///
/// 只放低敏信息：scope/code 是固定枚举风格字符串，detail 只允许放状态码、阶段、
/// 耗时、fingerprint 之类的技术字段——**不写 URL、路径、正文或凭据**。
class AppLogEntry {
  const AppLogEntry({
    required this.at,
    required this.level,
    required this.scope,
    required this.code,
    this.detail,
  });

  final DateTime at;
  final AppLogLevel level;

  /// 来源模块：`image`、`export`、`reader`、`network` 等。
  final String scope;

  /// 简短机器码，便于 grep：如 `download/notFound`、`write_failed`。
  final String code;

  /// 已脱敏的补充信息。
  final String? detail;

  String toLine() {
    final buffer = StringBuffer()
      ..write(_two(at.hour))
      ..write(':')
      ..write(_two(at.minute))
      ..write(':')
      ..write(_two(at.second))
      ..write(' ')
      ..write(_levelTag(level))
      ..write(' [')
      ..write(scope)
      ..write('] ')
      ..write(code);
    final extra = detail?.trim();
    if (extra != null && extra.isNotEmpty) {
      buffer
        ..write(' · ')
        ..write(extra);
    }
    return buffer.toString();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _levelTag(AppLogLevel level) {
    return switch (level) {
      AppLogLevel.info => 'INFO ',
      AppLogLevel.warning => 'WARN ',
      AppLogLevel.error => 'ERROR',
    };
  }
}

enum AppLogLevel { info, warning, error }
