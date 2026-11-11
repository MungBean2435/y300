import 'package:flutter/material.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_destination.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_use_case.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 运行中的导出：进度 + 取消，完成或取消后返回结果。
///
/// 导出是前台任务，因此不做"后台继续下载"的假象：关闭/取消都走协作式取消，
/// 结果只包含已经真正写成功的张数。
Future<ComicImageExportResult?> showComicImageExportProgressSheet({
  required BuildContext context,
  required ComicImageExportUseCase useCase,
  required String comicId,
  required ComicImageExportScope scope,
  required ComicImageExportTarget target,
  String? episodeId,
  VoidCallback? onCompleted,
}) {
  return showDialog<ComicImageExportResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ComicImageExportProgressDialog(
      useCase: useCase,
      comicId: comicId,
      scope: scope,
      target: target,
      episodeId: episodeId,
      onCompleted: onCompleted,
    ),
  );
}

class _ComicImageExportProgressDialog extends StatefulWidget {
  const _ComicImageExportProgressDialog({
    required this.useCase,
    required this.comicId,
    required this.scope,
    required this.target,
    this.episodeId,
    this.onCompleted,
  });

  final ComicImageExportUseCase useCase;
  final String comicId;
  final ComicImageExportScope scope;
  final ComicImageExportTarget target;
  final String? episodeId;
  final VoidCallback? onCompleted;

  @override
  State<_ComicImageExportProgressDialog> createState() =>
      _ComicImageExportProgressDialogState();
}

class _ComicImageExportProgressDialogState
    extends State<_ComicImageExportProgressDialog>
    implements ComicImageExportProgressObserver {
  final ComicImageExportCancellationToken _cancellationToken =
      ComicImageExportCancellationToken();
  ComicImageExportProgress? _progress;
  bool _cancelling = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void onChange(ComicImageExportProgress progress) {
    if (!mounted) {
      return;
    }
    setState(() => _progress = progress);
  }

  Future<void> _run() async {
    if (_started) {
      return;
    }
    _started = true;
    ComicImageExportResult? result;
    try {
      result = await widget.useCase.export(
        comicId: widget.comicId,
        target: widget.target,
        scope: widget.scope,
        episodeId: widget.episodeId,
        observer: this,
        cancellationToken: _cancellationToken,
      );
    } on Object {
      result = null;
    }
    if (!mounted) {
      return;
    }
    widget.onCompleted?.call();
    Navigator.of(context).pop(result);
  }

  void _cancel() {
    if (_cancelling) {
      return;
    }
    _cancellationToken.cancel();
    setState(() => _cancelling = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = _progress;
    final total = progress?.total ?? 0;
    final completed = progress?.completed ?? 0;
    final failed = progress?.failed ?? 0;
    final value = total <= 0 ? null : (completed / total).clamp(0.0, 1.0);
    return AlertDialog(
      key: const Key('comic-export-progress-dialog'),
      title: Text(
        widget.scope == ComicImageExportScope.work
            ? l10n.comicExportWork
            : l10n.comicExportChapter,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: value),
          const SizedBox(height: 12),
          Text(l10n.comicExportProgress(completed, total)),
          if (failed > 0) ...[
            const SizedBox(height: 4),
            Text(
              l10n.comicExportPartialFailed(failed),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (progress != null && progress.chapterTitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              progress.chapterTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('comic-export-cancel'),
          onPressed: _cancelling ? null : _cancel,
          child: Text(
            _cancelling ? l10n.comicExportCancelling : l10n.commonCancel,
          ),
        ),
      ],
    );
  }
}
