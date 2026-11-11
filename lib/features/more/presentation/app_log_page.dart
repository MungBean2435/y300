import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/diagnostics/app_log_models.dart';
import 'package:y300/core/diagnostics/diagnostics_providers.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 设置里的诊断日志页：只读本次运行内的低敏事件，可复制给开发者。
///
/// 日志只写内存，退出应用即清空；内容不含 URL、文件路径或正文。
class AppLogPage extends ConsumerWidget {
  const AppLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final recorder = ref.watch(appLogRecorderProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.moreDiagnosticLog),
        actions: [
          IconButton(
            key: const Key('diagnostic-log-copy'),
            tooltip: l10n.diagnosticLogCopy,
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () => _copy(context, l10n, recorder.entries.value),
          ),
          IconButton(
            key: const Key('diagnostic-log-clear'),
            tooltip: l10n.diagnosticLogClear,
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              recorder.clear();
              _snack(context, l10n.diagnosticLogCleared);
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<AppLogEntry>>(
        valueListenable: recorder.entries,
        builder: (context, entries, _) {
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.diagnosticLogEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          final newestFirst = entries.reversed.toList(growable: false);
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: newestFirst.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = newestFirst[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SelectableText(
                  entry.toLine(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _copy(
    BuildContext context,
    AppLocalizations l10n,
    List<AppLogEntry> entries,
  ) async {
    if (entries.isEmpty) {
      _snack(context, l10n.diagnosticLogEmpty);
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: entries.map((entry) => entry.toLine()).join('\n')),
    );
    if (!context.mounted) {
      return;
    }
    _snack(context, l10n.diagnosticLogCopied);
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
