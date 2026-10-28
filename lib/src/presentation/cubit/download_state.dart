import '../../data/downloader.dart';
import '../../domain/models.dart';

class DownloadState {
  DownloadState({
    this.novel,
    this.branch,
    List<ChapterSelection> chapters = const [],
    List<Object> chapterRows = const [],
    Map<String, List<String>> volumeKeys = const {},
    Map<String, List<String>> volumeBranchChoices = const {},
    Set<String> collapsedVolumes = const {},
    Set<String> selected = const {},
    this.busy = false,
    this.saving = false,
    this.splitByVolume = false,
    this.error,
    this.notice,
    this.progress,
    List<SavedBook> savedBooks = const [],
    this.user,
  }) : chapters = List.unmodifiable(chapters),
       chapterRows = List.unmodifiable(chapterRows),
       volumeKeys = Map.unmodifiable(
         volumeKeys.map((k, v) => MapEntry(k, List<String>.unmodifiable(v))),
       ),
       volumeBranchChoices = Map.unmodifiable(
         volumeBranchChoices.map(
           (k, v) => MapEntry(k, List<String>.unmodifiable(v)),
         ),
       ),
       collapsedVolumes = Set.unmodifiable(collapsedVolumes),
       selected = Set.unmodifiable(selected),
       savedBooks = List.unmodifiable(savedBooks);
  final Novel? novel;
  final String? branch;
  final List<ChapterSelection> chapters;
  final List<Object> chapterRows;
  final Map<String, List<String>> volumeKeys, volumeBranchChoices;
  final Set<String> collapsedVolumes, selected;
  final bool busy, saving, splitByVolume;
  final String? error, notice;
  final DownloadProgress? progress;
  final List<SavedBook> savedBooks;
  final Map<String, dynamic>? user;

  String? selectedVolumeBranch(String volume) {
    final branches = chapters
        .where((s) => s.chapter.volume == volume)
        .map((s) => s.branch.id)
        .toSet();
    return branches.length == 1 ? branches.single : null;
  }
}
