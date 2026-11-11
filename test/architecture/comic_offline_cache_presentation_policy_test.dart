import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bulk cache entries stay exposed with their call paths', () {
    final detailPage = File(
      'lib/features/library_shared/presentation/pages/unified_detail_page.dart',
    ).readAsStringSync();
    final shelfAdapter = File(
      'lib/features/comic/presentation/adapters/comic_shelf_adapter.dart',
    ).readAsStringSync();

    // 详情页把整部缓存作为单按钮主入口，未读缓存收进 more 菜单。
    expect(detailPage, contains('_showsBulkDownloadActions => true'));
    expect(
      detailPage,
      contains('_supportsChapterDownloads && _showsBulkDownloadActions'),
    );
    expect(detailPage, contains("'unified-detail-appbar-download'"));
    expect(detailPage, contains('Future<void> _cacheAllChapters()'));
    expect(detailPage, contains('Future<void> _cacheUnreadChapters()'));
    expect(detailPage, contains("'unified-detail-cache-unread'"));
    expect(detailPage, contains('adapter.downloadUnread(workId: widget.workId)'));
    expect(detailPage, contains('adapter.downloadAll(workId: widget.workId)'));

    expect(
      shelfAdapter,
      contains('_showsBulkDownloadSelectionAction => true'),
    );
    expect(
      shelfAdapter,
      contains('_supportsBulkDownload && _showsBulkDownloadSelectionAction'),
    );
    expect(shelfAdapter, contains('case SelectionActionIds.download:'));
    expect(shelfAdapter, contains('return _runDownload(request);'));
    expect(shelfAdapter, contains('_bulkDownloadUseCaseResolver'));

    expect(
      File(
        'lib/features/comic/domain/services/bulk_download_use_case.dart',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        'lib/features/comic/data/use_cases/bulk_download_use_case_impl.dart',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        'lib/features/comic/data/use_cases/bulk_download_use_case_providers.dart',
      ).existsSync(),
      isTrue,
    );
  });

  test('offline cache terminology does not rename persistence contracts', () {
    final database = <String>[
      'lib/core/persistence/app_database_tables.dart',
      'lib/core/persistence/schema/library_database_schema.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(database, contains("'comic_download_queue'"));
    expect(database, contains('is_downloaded INTEGER'));
    expect(database, contains('downloaded_at INTEGER'));
  });

  test('explicit image and app update downloads keep download semantics', () {
    final simplified = File('lib/l10n/app_zh.arb').readAsStringSync();
    final traditional = File('lib/l10n/app_zh_TW.arb').readAsStringSync();

    expect(simplified, contains('"comicDownloadCurrentImage": "下载当前图片"'));
    expect(simplified, contains('"threadImageDownload": "下载当前图片"'));
    expect(simplified, contains('"appUpdateDownloadInProgress"'));
    expect(traditional, contains('"comicDownloadCurrentImage": "下載目前圖片"'));
    expect(traditional, contains('"threadImageDownload": "下載目前圖片"'));
    expect(traditional, contains('"appUpdateDownloadInProgress"'));
  });
}
