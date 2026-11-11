import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/diagnostics/app_log_models.dart';
import 'package:y300/core/diagnostics/app_log_recorder.dart';
import 'package:y300/core/diagnostics/diagnostics_providers.dart';
import 'package:y300/features/more/presentation/app_log_page.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('diagnostic log page lists entries newest first and can clear', (
    tester,
  ) async {
    final recorder = RingBufferAppLogRecorder();
    addTearDown(recorder.dispose);
    recorder.record(
      level: AppLogLevel.warning,
      scope: 'image',
      code: 'download/notFound',
      detail: 'http=404',
    );
    recorder.record(
      level: AppLogLevel.error,
      scope: 'export',
      code: 'write_failed',
      detail: 'reason=permissionDenied',
    );
    final l10n = AppLocalizationsZh();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appLogRecorderProvider.overrideWithValue(recorder)],
        child: const LocalizedTestApp(home: AppLogPage()),
      ),
    );
    await tester.pump();

    expect(find.textContaining('write_failed'), findsOneWidget);
    expect(find.textContaining('download/notFound'), findsOneWidget);
    expect(
      tester.getTopLeft(find.textContaining('write_failed')).dy,
      lessThan(tester.getTopLeft(find.textContaining('download/notFound')).dy),
    );

    await tester.tap(find.byKey(const Key('diagnostic-log-clear')));
    await tester.pump();

    expect(find.text(l10n.diagnosticLogEmpty), findsOneWidget);
  });

  testWidgets('diagnostic log page shows an empty state', (tester) async {
    final recorder = RingBufferAppLogRecorder();
    addTearDown(recorder.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appLogRecorderProvider.overrideWithValue(recorder)],
        child: const LocalizedTestApp(home: AppLogPage()),
      ),
    );

    expect(find.text(AppLocalizationsZh().diagnosticLogEmpty), findsOneWidget);
  });
}
