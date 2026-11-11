import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/diagnostics/diagnostics_providers.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/providers/comic_reader_service_providers.dart';
import 'package:y300/features/comic/data/services/reader_service_comic_image_export_link_refresher.dart';
import 'package:y300/features/comic/data/services/comic_image_export_destination_store.dart';
import 'package:y300/features/comic/data/services/directory_comic_image_export_writer.dart';
import 'package:y300/features/comic/data/services/gallery_comic_image_export_writer.dart';
import 'package:y300/features/comic/data/use_cases/comic_image_export_use_case_impl.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_destination.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_use_case.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_writer.dart';
import 'package:y300/features/reader_shared/data/export/reader_image_export_providers.dart';

final comicImageExportDestinationStoreProvider =
    Provider<ComicImageExportDestinationStore>((ref) {
      return PreferencesComicImageExportDestinationStore(
        preferencesStore: ref.watch(preferencesStoreProvider),
      );
    });

final comicImageExportUseCaseProvider = Provider<ComicImageExportUseCase>((
  ref,
) {
  return DefaultComicImageExportUseCase(
    comicRepository: ref.watch(comicRepositoryProvider),
    imageCacheService: ref.watch(imageCacheServiceProvider),
    writers: <ComicImageExportWriter>[
      GalleryComicImageExportWriter(
        sink: ref.watch(readerImageExportSinkProvider),
      ),
      const DirectoryComicImageExportWriter(),
    ],
    imageReferer: ref.watch(forumImageRefererProvider),
    log: ref.watch(appLogRecorderProvider),
    linkRefresher: ReaderServiceComicImageExportLinkRefresher(
      comicRepository: ref.watch(comicRepositoryProvider),
      readerService: ref.watch(comicReaderServiceProvider.future),
    ),
  );
});
