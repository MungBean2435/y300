/// 导出前刷新章节图片链接的能力。
///
/// 论坛附件链接可能过期（404/403）。导出失败时允许重新解析原帖拿一份新地址，
/// 再对失败页做一次有界重试；具体读取与替换由 data 层实现。
abstract interface class ComicImageExportLinkRefresher {
  /// 返回 `true` 表示章节图片目录已被替换为新的地址列表。
  Future<bool> refresh({
    required String comicId,
    required String episodeId,
    required String sourceTid,
  });
}
