import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/comic/data/services/comic_image_export_destination_store.dart';
import 'package:y300/features/comic/domain/services/comic_image_export_destination.dart';

void main() {
  test('defaults to the gallery when nothing was chosen', () async {
    final store = PreferencesComicImageExportDestinationStore(
      preferencesStore: _MemoryPreferencesStore(),
    );

    final target = await store.readLastTarget();

    expect(target.location, ComicImageExportLocation.gallery);
  });

  test('remembers a chosen directory across reads', () async {
    final preferences = _MemoryPreferencesStore();
    final store = PreferencesComicImageExportDestinationStore(
      preferencesStore: preferences,
    );

    await store.saveTarget(
      const ComicImageExportTarget.directory('/storage/emulated/0/Pictures/漫画'),
    );

    final target = await store.readLastTarget();
    expect(target.location, ComicImageExportLocation.directory);
    expect(target.directoryPath, '/storage/emulated/0/Pictures/漫画');
  });

  test('switching back to the gallery drops the stale path', () async {
    final preferences = _MemoryPreferencesStore();
    final store = PreferencesComicImageExportDestinationStore(
      preferencesStore: preferences,
    );

    await store.saveTarget(
      const ComicImageExportTarget.directory('/storage/emulated/0/Exports'),
    );
    await store.saveTarget(const ComicImageExportTarget.gallery());

    final target = await store.readLastTarget();
    expect(target.location, ComicImageExportLocation.gallery);
    expect(target.directoryPath, isNull);
  });

  test('a directory selection without a path is ignored', () async {
    final store = PreferencesComicImageExportDestinationStore(
      preferencesStore: _MemoryPreferencesStore(),
    );

    await store.saveTarget(const ComicImageExportTarget.directory('   '));

    final target = await store.readLastTarget();
    expect(target.location, ComicImageExportLocation.gallery);
  });
}

class _MemoryPreferencesStore implements PreferencesStore {
  final Map<String, Object?> _values = <String, Object?>{};

  @override
  Future<bool> contains<T extends Object>(PreferenceKey<T> key) async {
    return _values.containsKey(key.name);
  }

  @override
  Future<T?> read<T extends Object>(PreferenceKey<T> key) async {
    final value = _values[key.name];
    return value is T ? value : null;
  }

  @override
  Future<void> remove<T extends Object>(PreferenceKey<T> key) async {
    _values.remove(key.name);
  }

  @override
  Future<void> write<T extends Object>(PreferenceKey<T> key, T value) async {
    _values[key.name] = value;
  }
}
