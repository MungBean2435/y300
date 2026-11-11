/// 漫画图片导出的目标位置。
enum ComicImageExportLocation {
  /// 系统相册（Android MediaStore / iOS 照片库）。
  gallery,

  /// 用户选择的文件夹。
  directory,
}

/// 一次导出的落盘目标。
///
/// 目标只描述"写到哪"，不包含章节或文件命名规则：那些属于导出用例。
class ComicImageExportTarget {
  const ComicImageExportTarget.gallery()
    : location = ComicImageExportLocation.gallery,
      directoryPath = null;

  const ComicImageExportTarget.directory(String path)
    : location = ComicImageExportLocation.directory,
      directoryPath = path;

  final ComicImageExportLocation location;
  final String? directoryPath;

  /// 可持久化/可比较的身份。目录目标用绝对路径区分，避免两次导出互相覆盖。
  String get identity {
    final path = directoryPath?.trim() ?? '';
    return location == ComicImageExportLocation.gallery
        ? 'gallery'
        : 'directory:$path';
  }

  /// 目标是否完整可用。目录目标缺少路径时调用方必须重新询问位置。
  bool get isUsable {
    if (location == ComicImageExportLocation.gallery) {
      return true;
    }
    return (directoryPath?.trim().isNotEmpty ?? false);
  }

  @override
  bool operator ==(Object other) {
    return other is ComicImageExportTarget &&
        other.location == location &&
        other.directoryPath?.trim() == directoryPath?.trim();
  }

  @override
  int get hashCode => Object.hash(location, directoryPath?.trim());
}

/// 记住上次导出位置，让重复导出不必每次重选目录。
abstract interface class ComicImageExportDestinationStore {
  /// 上次选择；从未选择过时返回相册目标。
  Future<ComicImageExportTarget> readLastTarget();

  Future<void> saveTarget(ComicImageExportTarget target);
}
