import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_destination.dart';

/// 用 SharedPreferences 记住上次导出位置。
///
/// 只存目标类型与目录路径两个标量，不存作品或章节；每次导出仍然显式传入目标，
/// 因此取消/失败不会留下半持久状态。
class PreferencesComicImageExportDestinationStore
    implements ComicImageExportDestinationStore {
  PreferencesComicImageExportDestinationStore({
    required PreferencesStore preferencesStore,
  }) : _preferencesStore = preferencesStore;

  final PreferencesStore _preferencesStore;

  @override
  Future<ComicImageExportTarget> readLastTarget() async {
    final destination = (await _preferencesStore.read(
      PreferenceKeys.comicExportDestination,
    ))?.trim();
    if (destination == 'directory') {
      final path = (await _preferencesStore.read(
        PreferenceKeys.comicExportDirectory,
      ))?.trim();
      if (path != null && path.isNotEmpty) {
        return ComicImageExportTarget.directory(path);
      }
    }
    return const ComicImageExportTarget.gallery();
  }

  @override
  Future<void> saveTarget(ComicImageExportTarget target) async {
    switch (target.location) {
      case ComicImageExportLocation.gallery:
        await _preferencesStore.write(
          PreferenceKeys.comicExportDestination,
          'gallery',
        );
      case ComicImageExportLocation.directory:
        final path = target.directoryPath?.trim();
        if (path == null || path.isEmpty) {
          return;
        }
        await _preferencesStore.write(
          PreferenceKeys.comicExportDestination,
          'directory',
        );
        await _preferencesStore.write(
          PreferenceKeys.comicExportDirectory,
          path,
        );
    }
  }
}
