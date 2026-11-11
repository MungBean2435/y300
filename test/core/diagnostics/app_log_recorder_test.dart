import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/diagnostics/app_log_models.dart';
import 'package:y300/core/diagnostics/app_log_recorder.dart';

void main() {
  test('records entries in order and keeps only the newest capacity', () {
    final recorder = RingBufferAppLogRecorder(capacity: 3);
    addTearDown(recorder.dispose);

    for (var index = 0; index < 5; index++) {
      recorder.record(
        level: AppLogLevel.warning,
        scope: 'image',
        code: 'download/notFound',
        detail: 'page=$index',
      );
    }

    expect(recorder.entries.value, hasLength(3));
    expect(recorder.entries.value.first.detail, 'page=2');
    expect(recorder.entries.value.last.detail, 'page=4');
    expect(recorder.droppedCount, 2);
  });

  test('clear drops every entry and the dropped counter', () {
    final recorder = RingBufferAppLogRecorder(capacity: 1);
    addTearDown(recorder.dispose);

    recorder.record(level: AppLogLevel.info, scope: 'export', code: 'start');
    recorder.record(level: AppLogLevel.info, scope: 'export', code: 'done');
    expect(recorder.droppedCount, 1);

    recorder.clear();

    expect(recorder.entries.value, isEmpty);
    expect(recorder.droppedCount, 0);
  });

  test('line format keeps scope, code and level readable', () {
    final entry = AppLogEntry(
      at: DateTime(2026, 11, 11, 12, 3, 4),
      level: AppLogLevel.error,
      scope: 'image',
      code: 'download/securityChallenge',
      detail: 'code=waf_unavailable http=405',
    );

    final line = entry.toLine();

    expect(line, startsWith('12:03:04 ERROR [image]'));
    expect(line, contains('download/securityChallenge'));
    expect(line, contains('http=405'));
  });
}
