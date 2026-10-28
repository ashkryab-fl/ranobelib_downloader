import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/api.dart';
import '../../data/auth.dart';
import '../../data/download_storage.dart';
import '../../data/downloader.dart';
import '../../data/epub.dart';
import '../../domain/models.dart';
import 'download_state.dart';

class DownloadCubit extends Cubit<DownloadState> {
  DownloadCubit({
    RanobeApi? api,
    DownloadStorage? storage,
    TokenStore? tokenStore,
  }) : api = api ?? RanobeApi(),
       storage = storage ?? DownloadStorage(),
       super(DownloadState()) {
    auth = RanobeAuth(this.api, store: tokenStore);
  }
  final RanobeApi api;
  final DownloadStorage storage;
  late final RanobeAuth auth;
  Novel? _novel;
  String? _branch;
  List<ChapterSelection> _chapters = [];
  List<Object> _chapterRows = [];
  final _volumeKeys = <String, List<String>>{};
  final _volumeBranchChoices = <String, List<String>>{};
  final _collapsedVolumes = <String>{};
  final _selected = <String>{};
  bool _busy = false;
  bool _saving = false;
  bool _splitByVolume = false;
  String? _error;
  String? _notice;
  DownloadProgress? _progress;
  final _savedBooks = <SavedBook>[];
  Cancellation? _cancel;

  @visibleForTesting
  void setNovelForTesting(Novel value) {
    _novel = value;
    setBranch(null);
  }

  void _emit() {
    if (!isClosed) {
      emit(
        DownloadState(
          novel: _novel,
          branch: _branch,
          chapters: _chapters,
          chapterRows: _chapterRows,
          volumeKeys: _volumeKeys,
          volumeBranchChoices: _volumeBranchChoices,
          collapsedVolumes: _collapsedVolumes,
          selected: _selected,
          busy: _busy,
          saving: _saving,
          splitByVolume: _splitByVolume,
          error: _error,
          notice: _notice,
          progress: _progress,
          savedBooks: _savedBooks,
          user: auth.user == null ? null : Map.unmodifiable(auth.user!),
        ),
      );
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notice = null;
    _cancel = Cancellation();
    _emit();
    try {
      await action();
    } on DownloadCancelled {
      _notice =
          'Загрузка отменена.'
          '${_savedBooks.isEmpty ? '' : ' Сохранено EPUB: ${_savedBooks.length}.'}';
    } catch (e) {
      _error = switch (e) {
        FormatException() => e.message,
        ApiException() => e.message,
        _ => 'Не удалось завершить операцию: $e',
      };
    } finally {
      _busy = false;
      _saving = false;
      _progress = null;
      _cancel = null;
      _emit();
    }
  }

  Future<void> initialize() => run(auth.restore);
  Future<void> load(String input) => run(() async {
    final slug = extractSlug(input);
    // Clear the old selection before loading to avoid downloading the wrong book.
    _novel = null;
    _chapters = [];
    _chapterRows = [];
    _volumeKeys.clear();
    _volumeBranchChoices.clear();
    _collapsedVolumes.clear();
    _selected.clear();
    _branch = null;
    _savedBooks.clear();
    _progress = const DownloadProgress('Загрузка информации о книге…', 0, 0);
    _emit();
    _novel = await api.loadNovel(slug, _cancel!);
    setBranch(null);
    if (_chapters.isEmpty) {
      _notice = 'У этой книги нет доступных глав. Попробуйте войти в аккаунт.';
    }
  });

  void setBranch(String? value) {
    final previous = {for (final s in _chapters) s.chapter.key: s};
    final automatic = _novel?.selectBranch(null) ?? <ChapterSelection>[];
    _branch = value;
    _chapters = value == null
        ? automatic
        : [
            for (final s in automatic)
              _novel!.chapterChoices[s.chapter.key]?[value] ??
                  previous[s.chapter.key] ??
                  s,
          ];
    _rebuildRows();
    final keys = _chapters.map((s) => s.chapter.key).toSet();
    _selected.retainAll(keys);
    if (previous.isEmpty) _selected.addAll(keys);
    _savedBooks.clear();
    _emit();
  }

  void _rebuildRows() {
    _chapterRows = [];
    _volumeKeys.clear();
    _volumeBranchChoices.clear();
    for (final selection in _chapters) {
      final chapter = selection.chapter;
      if (!_volumeKeys.containsKey(chapter.volume)) {
        _chapterRows.add(chapter.volume);
        _volumeKeys[chapter.volume] = [];
      }
      _volumeKeys[chapter.volume]!.add(chapter.key);
      if (!_collapsedVolumes.contains(chapter.volume)) {
        _chapterRows.add(selection);
      }
    }
    for (final entry in _volumeKeys.entries) {
      final choices = _novel!.chapterChoices;
      final first = choices[entry.value.first]!.keys.toSet();
      if (entry.value.every(
        (key) => setEquals(first, choices[key]!.keys.toSet()),
      )) {
        _volumeBranchChoices[entry.key] = first.toList();
      }
    }
  }

  void toggleVolumeExpanded(String volume) {
    if (!_volumeKeys.containsKey(volume)) return;
    if (!_collapsedVolumes.add(volume)) _collapsedVolumes.remove(volume);
    _rebuildRows();
    _emit();
  }

  void setChapterBranch(String key, String branchId) {
    if (_busy || !_chapters.any((s) => s.chapter.key == key)) return;
    final choice = _novel?.chapterChoices[key]?[branchId];
    if (choice == null) return;
    _applyChapterChoices({key: choice});
  }

  void setVolumeBranch(String volume, String branchId) {
    if (_busy || !(_volumeBranchChoices[volume]?.contains(branchId) ?? false)) {
      return;
    }
    _applyChapterChoices({
      for (final key in _volumeKeys[volume]!)
        key: _novel!.chapterChoices[key]![branchId]!,
    });
  }

  void _applyChapterChoices(Map<String, ChapterSelection> choices) {
    _chapters = [for (final s in _chapters) choices[s.chapter.key] ?? s];
    _rebuildRows();
    _savedBooks.clear();
    _emit();
  }

  void toggle(Chapter chapter, bool value) {
    if (value) {
      _selected.add(chapter.key);
    } else {
      _selected.remove(chapter.key);
    }
    _emit();
  }

  void selectAll(bool value, {String? volume}) {
    final keys = _chapters
        .where((s) => volume == null || s.chapter.volume == volume)
        .map((s) => s.chapter.key);
    if (value) {
      _selected.addAll(keys);
    } else {
      _selected.removeAll(keys);
    }
    _emit();
  }

  void accountChanged() => _emit();
  void setSplitByVolume(bool value) {
    if (_busy) return;
    _splitByVolume = value;
    _emit();
  }

  void cancel() {
    if (!_saving) _cancel?.cancel();
  }

  Future<void> logout() => run(() async {
    await auth.logout();
    // Remove account-dependent availability; reloading fetches it for the guest.
    _novel = null;
    _chapters = [];
    _chapterRows = [];
    _volumeKeys.clear();
    _volumeBranchChoices.clear();
    _collapsedVolumes.clear();
    _selected.clear();
    _savedBooks.clear();
    _notice = 'Вы вышли из аккаунта.';
  });

  Future<void> download() => run(() async {
    final book = _novel;
    if (book == null) {
      throw const FormatException('Сначала загрузите информацию о книге.');
    }
    _savedBooks.clear();
    final selections = _chapters
        .where((s) => _selected.contains(s.chapter.key))
        .toList();
    if (selections.isEmpty) {
      throw const FormatException('Выберите хотя бы одну главу.');
    }
    final exports = <String?, List<ChapterSelection>>{};
    if (_splitByVolume) {
      for (final selection in selections) {
        (exports[selection.chapter.volume] ??= []).add(selection);
      }
    } else {
      exports[null] = selections;
    }
    var completed = 0;
    var fileIndex = 0;
    final downloader = BookDownloader(api);
    for (final entry in exports.entries) {
      _cancel!.check();
      final volume = entry.key;
      final bytes = await downloader.download(book, entry.value, _cancel!, (p) {
        _progress = DownloadProgress(
          volume == null
              ? p.message
              : 'EPUB ${fileIndex + 1}/${exports.length} · ${p.message}',
          completed + p.completed,
          selections.length,
        );
        _emit();
      }, volume: volume);
      _cancel!.check();
      _saving = true;
      _progress = DownloadProgress(
        volume == null
            ? 'Сохранение в Downloads/ranobelib…'
            : 'Сохранение тома $volume в Downloads/ranobelib…',
        completed + entry.value.length,
        selections.length,
      );
      _emit();
      try {
        _savedBooks.add(
          await storage.save(
            bytes,
            safeBookFilename(book.title, volume: volume),
          ),
        );
      } finally {
        _saving = false;
        _emit();
      }
      completed += entry.value.length;
      fileIndex++;
    }
    _notice = _savedBooks.length == 1
        ? 'EPUB сохранён.'
        : 'Сохранено EPUB: ${_savedBooks.length}.';
  });

  Future<void> openBook(SavedBook book) => run(() async {
    await storage.open(book);
  });

  @override
  Future<void> close() {
    _cancel?.cancel();
    api.close();
    return super.close();
  }
}
