import 'package:flutter/material.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_destination.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 导出前选择落点：系统相册，或用户选择的文件夹。
///
/// 上次选择会高亮为默认项；目录目标不可用时让用户重新选择，而不是静默回退。
Future<ComicImageExportTarget?> showComicImageExportDestinationSheet({
  required BuildContext context,
  required ComicImageExportDestinationStore store,
  Future<String?> Function()? pickDirectory,
}) {
  return showModalBottomSheet<ComicImageExportTarget>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _ComicImageExportDestinationSheet(
      store: store,
      pickDirectory: pickDirectory,
    ),
  );
}

class _ComicImageExportDestinationSheet extends StatefulWidget {
  const _ComicImageExportDestinationSheet({
    required this.store,
    this.pickDirectory,
  });

  final ComicImageExportDestinationStore store;
  final Future<String?> Function()? pickDirectory;

  @override
  State<_ComicImageExportDestinationSheet> createState() =>
      _ComicImageExportDestinationSheetState();
}

class _ComicImageExportDestinationSheetState
    extends State<_ComicImageExportDestinationSheet> {
  ComicImageExportTarget? _lastTarget;
  bool _pickingDirectory = false;

  @override
  void initState() {
    super.initState();
    _loadLastTarget();
  }

  Future<void> _loadLastTarget() async {
    final target = await widget.store.readLastTarget();
    if (!mounted) {
      return;
    }
    setState(() => _lastTarget = target);
  }

  Future<void> _select(ComicImageExportTarget target) async {
    if (!target.isUsable) {
      return;
    }
    await widget.store.saveTarget(target);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(target);
  }

  Future<void> _pickDirectory() async {
    final picker = widget.pickDirectory;
    if (picker == null || _pickingDirectory) {
      return;
    }
    setState(() => _pickingDirectory = true);
    try {
      final path = await picker();
      final normalized = path?.trim();
      if (!mounted || normalized == null || normalized.isEmpty) {
        return;
      }
      await _select(ComicImageExportTarget.directory(normalized));
    } finally {
      if (mounted) {
        setState(() => _pickingDirectory = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lastTarget = _lastTarget;
    final lastDirectoryPath =
        lastTarget?.location == ComicImageExportLocation.directory
        ? lastTarget?.directoryPath
        : null;
    final lastIsGallery =
        lastTarget?.location == ComicImageExportLocation.gallery;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              l10n.comicExportChooseLocation,
              style: theme.textTheme.titleMedium,
            ),
          ),
          ListTile(
            key: const Key('comic-export-target-gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.comicExportToGallery),
            subtitle: Text(l10n.comicExportToGalleryHint),
            trailing: lastIsGallery ? const Icon(Icons.check) : null,
            onTap: () => _select(const ComicImageExportTarget.gallery()),
          ),
          ListTile(
            key: const Key('comic-export-target-directory'),
            leading: const Icon(Icons.folder_outlined),
            title: Text(l10n.comicExportToDirectory),
            subtitle: Text(
              lastDirectoryPath == null || lastDirectoryPath.isEmpty
                  ? l10n.comicExportPickDirectory
                  : lastDirectoryPath,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _pickingDirectory
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : lastDirectoryPath == null || lastDirectoryPath.isEmpty
                ? null
                : TextButton(
                    key: const Key('comic-export-target-directory-change'),
                    onPressed: _pickDirectory,
                    child: Text(l10n.comicExportChangeDirectory),
                  ),
            onTap: lastDirectoryPath == null || lastDirectoryPath.isEmpty
                ? _pickDirectory
                : () => _select(
                    ComicImageExportTarget.directory(lastDirectoryPath),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Text(
              l10n.comicExportDestinationHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
