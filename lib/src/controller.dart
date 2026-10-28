import 'package:flutter/foundation.dart';

import 'api.dart';
import 'auth.dart';
import 'download_storage.dart';
import 'downloader.dart';
import 'epub.dart';
import 'models.dart';

class DownloadController extends ChangeNotifier {
  DownloadController({
    RanobeApi? api,
    DownloadStorage? storage,
    TokenStore? tokenStore,
  }) : api = api ?? RanobeApi(),
       storage = storage ?? DownloadStorage() {
    auth = RanobeAuth(this.api, store: tokenStore);
  }
  final RanobeApi api;
  final DownloadStorage storage;
  late final RanobeAuth auth;
  Novel? novel;
  String? branch;
  List<ChapterSelection> chapters = [];
  List<Object> chapterRows = [];
  final volumeKeys = <String, List<String>>{};
  final volumeBranchChoices = <String, List<String>>{};
  final collapsedVolumes = <String>{};
  final selected = <String>{};
  bool busy = false;
  bool saving = false;
  bool splitByVolume = false;
  bool _disposed = false;
  String? error;
  String? notice;
  DownloadProgress? progress;
  final savedBooks = <SavedBook>[];
  Cancellation? _cancel;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    notice = null;
    _cancel = Cancellation();
    _emit();
    try {
      await action();
    } on DownloadCancelled {
      notice =
          'Завантаження скасовано.'
          '${savedBooks.isEmpty ? '' : ' Збережено EPUB: ${savedBooks.length}.'}';
    } catch (e) {
      error = switch (e) {
        FormatException() => e.message,
        ApiException() => e.message,
        _ => 'Не вдалося завершити операцію: $e',
      };
    } finally {
      busy = false;
      saving = false;
      progress = null;
      _cancel = null;
      _emit();
    }
  }

  Future<void> initialize() => run(auth.restore);
  Future<void> load(String input) => run(() async {
    final slug = extractSlug(input);
    // Clear the old selection before loading to avoid downloading the wrong book.
    novel = null;
    chapters = [];
    chapterRows = [];
    volumeKeys.clear();
    volumeBranchChoices.clear();
    collapsedVolumes.clear();
    selected.clear();
    branch = null;
    savedBooks.clear();
    progress = const DownloadProgress(
      'Завантаження інформації про книгу…',
      0,
      0,
    );
    _emit();
    novel = await api.loadNovel(slug, _cancel!);
    setBranch(null);
    if (chapters.isEmpty) {
      notice = 'У цієї книги немає доступних глав. Спробуйте увійти в акаунт.';
    }
  });

  void setBranch(String? value) {
    final previous = {for (final s in chapters) s.chapter.key: s};
    final automatic = novel?.selectBranch(null) ?? <ChapterSelection>[];
    branch = value;
    chapters = value == null
        ? automatic
        : [
            for (final s in automatic)
              novel!.chapterChoices[s.chapter.key]?[value] ??
                  previous[s.chapter.key] ??
                  s,
          ];
    _rebuildRows();
    final keys = chapters.map((s) => s.chapter.key).toSet();
    selected.retainAll(keys);
    if (previous.isEmpty) selected.addAll(keys);
    savedBooks.clear();
    _emit();
  }

  void _rebuildRows() {
    chapterRows = [];
    volumeKeys.clear();
    volumeBranchChoices.clear();
    for (final selection in chapters) {
      final chapter = selection.chapter;
      if (!volumeKeys.containsKey(chapter.volume)) {
        chapterRows.add(chapter.volume);
        volumeKeys[chapter.volume] = [];
      }
      volumeKeys[chapter.volume]!.add(chapter.key);
      if (!collapsedVolumes.contains(chapter.volume)) {
        chapterRows.add(selection);
      }
    }
    for (final entry in volumeKeys.entries) {
      final choices = novel!.chapterChoices;
      final first = choices[entry.value.first]!.keys.toSet();
      if (entry.value.every(
        (key) => setEquals(first, choices[key]!.keys.toSet()),
      )) {
        volumeBranchChoices[entry.key] = first.toList();
      }
    }
  }

  String? selectedVolumeBranch(String volume) {
    final branches = chapters
        .where((s) => s.chapter.volume == volume)
        .map((s) => s.branch.id)
        .toSet();
    return branches.length == 1 ? branches.single : null;
  }

  void toggleVolumeExpanded(String volume) {
    if (!volumeKeys.containsKey(volume)) return;
    if (!collapsedVolumes.add(volume)) collapsedVolumes.remove(volume);
    _rebuildRows();
    _emit();
  }

  void setChapterBranch(String key, String branchId) {
    if (busy || !chapters.any((s) => s.chapter.key == key)) return;
    final choice = novel?.chapterChoices[key]?[branchId];
    if (choice == null) return;
    _applyChapterChoices({key: choice});
  }

  void setVolumeBranch(String volume, String branchId) {
    if (busy || !(volumeBranchChoices[volume]?.contains(branchId) ?? false)) {
      return;
    }
    _applyChapterChoices({
      for (final key in volumeKeys[volume]!)
        key: novel!.chapterChoices[key]![branchId]!,
    });
  }

  void _applyChapterChoices(Map<String, ChapterSelection> choices) {
    chapters = [for (final s in chapters) choices[s.chapter.key] ?? s];
    _rebuildRows();
    savedBooks.clear();
    _emit();
  }

  void toggle(Chapter chapter, bool value) {
    if (value) {
      selected.add(chapter.key);
    } else {
      selected.remove(chapter.key);
    }
    _emit();
  }

  void selectAll(bool value, {String? volume}) {
    final keys = chapters
        .where((s) => volume == null || s.chapter.volume == volume)
        .map((s) => s.chapter.key);
    if (value) {
      selected.addAll(keys);
    } else {
      selected.removeAll(keys);
    }
    _emit();
  }

  void accountChanged() => _emit();
  void setSplitByVolume(bool value) {
    if (busy) return;
    splitByVolume = value;
    _emit();
  }

  void cancel() {
    if (!saving) _cancel?.cancel();
  }

  Future<void> logout() => run(() async {
    await auth.logout();
    // Remove account-dependent availability; reloading fetches it for the guest.
    novel = null;
    chapters = [];
    chapterRows = [];
    volumeKeys.clear();
    volumeBranchChoices.clear();
    collapsedVolumes.clear();
    selected.clear();
    savedBooks.clear();
    notice = 'Ви вийшли з акаунту.';
  });

  Future<void> download() => run(() async {
    final book = novel;
    if (book == null) {
      throw const FormatException('Спочатку завантажте інформацію про книгу.');
    }
    savedBooks.clear();
    final selections = chapters
        .where((s) => selected.contains(s.chapter.key))
        .toList();
    if (selections.isEmpty) {
      throw const FormatException('Виберіть хоча б одну главу.');
    }
    final exports = <String?, List<ChapterSelection>>{};
    if (splitByVolume) {
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
        progress = DownloadProgress(
          volume == null
              ? p.message
              : 'EPUB ${fileIndex + 1}/${exports.length} · ${p.message}',
          completed + p.completed,
          selections.length,
        );
        _emit();
      }, volume: volume);
      _cancel!.check();
      saving = true;
      progress = DownloadProgress(
        volume == null
            ? 'Збереження в Downloads/ranobelib…'
            : 'Збереження тому $volume в Downloads/ranobelib…',
        completed + entry.value.length,
        selections.length,
      );
      _emit();
      try {
        savedBooks.add(
          await storage.save(
            bytes,
            safeBookFilename(book.title, volume: volume),
          ),
        );
      } finally {
        saving = false;
        _emit();
      }
      completed += entry.value.length;
      fileIndex++;
    }
    notice = savedBooks.length == 1
        ? 'EPUB збережено.'
        : 'Збережено EPUB: ${savedBooks.length}.';
  });

  Future<void> openBook(SavedBook book) => run(() async {
    await storage.open(book);
  });

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    api.close();
    super.dispose();
  }
}
