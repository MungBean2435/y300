import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/use_cases/comic_image_export_use_case_providers.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_use_case.dart';
import 'package:y300/features/comic/presentation/widgets/comic_image_export_destination_sheet.dart';
import 'package:y300/features/comic/presentation/widgets/comic_image_export_progress_sheet.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 漫画导出的统一编排：确认 → 选位置 → 执行 → 汇总。
///
/// 阅读器与详情页共用这一条流程，避免两处各自实现"选相册/选目录"和结果文案。
Future<ComicImageExportResult?> startComicImageExport({
  required BuildContext context,
  required WidgetRef ref,
  required String comicId,
  required ComicImageExportScope scope,
  String? episodeId,
  String? workTitle,
}) async {
  final l10n = AppLocalizations.of(context);
  if (scope == ComicImageExportScope.work) {
    final confirmed = await _confirmWorkExport(context, l10n, workTitle);
    if (confirmed != true || !context.mounted) {
      return null;
    }
  }
  final target = await showComicImageExportDestinationSheet(
    context: context,
    store: ref.read(comicImageExportDestinationStoreProvider),
    pickDirectory: () =>
        ref.read(storageLocationRepositoryProvider).pickDirectory(),
  );
  if (target == null || !context.mounted) {
    return null;
  }
  final result = await showComicImageExportProgressSheet(
    context: context,
    useCase: ref.read(comicImageExportUseCaseProvider),
    comicId: comicId,
    scope: scope,
    target: target,
    episodeId: episodeId,
  );
  if (!context.mounted) {
    return result;
  }
  _showSummary(context, l10n, result);
  return result;
}

Future<bool?> _confirmWorkExport(
  BuildContext context,
  AppLocalizations l10n,
  String? workTitle,
) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.comicExportWork),
      content: Text(
        workTitle == null || workTitle.trim().isEmpty
            ? l10n.comicExportWorkConfirm
            : '${l10n.comicExportWorkConfirm}\n\n${workTitle.trim()}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('comic-export-work-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.commonConfirm),
        ),
      ],
    ),
  );
}

void _showSummary(
  BuildContext context,
  AppLocalizations l10n,
  ComicImageExportResult? result,
) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  final String message;
  if (result == null) {
    message = l10n.comicExportFailed;
  } else if (result.cancelled) {
    message = l10n.comicExportCancelled;
  } else if (result.isEmpty) {
    message = l10n.comicExportNothingToExport;
  } else if (result.failedCount > 0) {
    message = l10n.comicExportPartialResult(
      result.exportedCount,
      result.failedCount,
    );
  } else {
    message = l10n.comicExportSavedTo(
      result.exportedCount,
      result.displayLocation,
    );
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
