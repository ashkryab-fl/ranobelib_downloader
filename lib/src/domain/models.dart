import 'package:html/parser.dart' as html;

typedef Json = Map<String, dynamic>;

Json asMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<dynamic> asList(dynamic value) => value is List ? value : [];
String textOf(dynamic value, [String fallback = '']) =>
    value?.toString() ?? fallback;

String decodeEntities(String value) {
  for (var i = 0; i < 5; i++) {
    // Parse text only: escaped angle brackets must remain visible book text.
    final next = html.parseFragment(value.replaceAll('<', '&lt;')).text ?? '';
    if (next == value) break;
    value = next;
  }
  return value;
}

int naturalCompare(String a, String b) {
  final left = a.split(RegExp(r'[.\-_]'));
  final right = b.split(RegExp(r'[.\-_]'));
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = int.tryParse(left[i]);
    final y = int.tryParse(right[i]);
    final result = x != null && y != null
        ? x.compareTo(y)
        : left[i].compareTo(right[i]);
    if (result != 0) return result;
  }
  return left.length.compareTo(right.length);
}

String extractSlug(String input) {
  final uri = Uri.tryParse(input.trim());
  final hosts = {
    'ranobelib.me',
    'ranobelib.org',
    'www.ranobelib.me',
    'www.ranobelib.org',
  };
  if (uri == null ||
      uri.scheme != 'https' ||
      !hosts.contains(uri.host.toLowerCase()) ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    throw const FormatException('Вставьте HTTPS-ссылку на книгу RanobeLIB.');
  }
  final parts = uri.pathSegments;
  if (parts.length < 3 ||
      parts[0] != 'ru' ||
      (parts[1] != 'book' && parts[1] != 'manga') ||
      !RegExp(r'^[\w-]+$').hasMatch(parts[2])) {
    throw const FormatException(
      'Ссылка должна иметь вид https://ranobelib.me/ru/book/123--name',
    );
  }
  return parts[2];
}

class Novel {
  Novel(this.slug, this.data, this.chapters);
  final String slug;
  final Json data;
  final List<Chapter> chapters;
  final _selectionCache = <String?, List<ChapterSelection>>{};
  String get id => textOf(data['id'], slug);
  String get title =>
      decodeEntities(
            textOf(
              data['rus_name'] ?? data['eng_name'] ?? data['name'],
              'Без названия',
            ),
          )
          .replaceFirst(
            RegExp(r'\s*\((Новелла|Novel)\)\s*$', caseSensitive: false),
            '',
          )
          .trim();
  String get author => asList(data['authors'])
      .map((a) => decodeEntities(textOf(asMap(a)['name'])))
      .where((s) => s.isNotEmpty)
      .join(', ');
  String get cover => textOf(asMap(data['cover'])['default']);
  List<String> get subjects =>
      [...asList(data['genres']), ...asList(data['tags'])]
          .map((g) => decodeEntities(textOf(asMap(g)['name'])))
          .where((s) => s.isNotEmpty)
          .toList();

  Map<String, String> get branchNames {
    final names = <String, Set<String>>{};
    for (final team in asList(data['teams'])) {
      final t = asMap(team);
      final id = textOf(asMap(t['details'])['branch_id'], '0');
      final name = decodeEntities(textOf(t['name']));
      if (name.isNotEmpty) (names[id] ??= {}).add(name);
    }
    for (final chapter in chapters) {
      for (final branch in chapter.branches) {
        final group = names[branch.id] ??= {};
        group.addAll(branch.teams);
      }
    }
    return {
      for (final entry in names.entries)
        entry.key: entry.value.isEmpty
            ? 'Ветка ${entry.key}'
            : entry.value.join(', '),
    };
  }

  late final Map<String, Map<String, ChapterSelection>> chapterChoices =
      _buildChapterChoices();

  Map<String, Map<String, ChapterSelection>> _buildChapterChoices() {
    final ordered = [...chapters]
      ..sort((a, b) {
        final number = naturalCompare(a.number, b.number);
        return number != 0 ? number : a.index.compareTo(b.index);
      });
    final available = <String, Map<String, ChapterSelection>>{};
    for (final ch in ordered) {
      final choices = available[ch.key] ??= {};
      for (final branch in ch.branches) {
        choices.putIfAbsent(branch.id, () => ChapterSelection(ch, branch));
      }
    }
    return Map.unmodifiable({
      for (final entry in available.entries)
        entry.key: Map<String, ChapterSelection>.unmodifiable(entry.value),
    });
  }

  List<ChapterSelection> selectBranch(String? branchId) {
    final cached = _selectionCache[branchId];
    if (cached != null) return cached;
    final available = chapterChoices;
    final chosen = <String, ChapterSelection>{};
    if (branchId != null) {
      for (final entry in available.entries) {
        final selection = entry.value[branchId];
        if (selection != null) chosen[entry.key] = selection;
      }
    } else {
      // Python's default: keep the first available branch across its chapters,
      // then fill any gaps from the next available branch.
      while (chosen.length < available.length) {
        final first = available.entries.firstWhere(
          (e) => !chosen.containsKey(e.key),
        );
        final preferred = first.value.keys.first;
        for (final entry in available.entries) {
          final selection = entry.value[preferred];
          if (!chosen.containsKey(entry.key) && selection != null) {
            chosen[entry.key] = selection;
          }
        }
      }
    }
    final result = chosen.values.toList()
      ..sort((a, b) {
        final volume = naturalCompare(a.chapter.volume, b.chapter.volume);
        if (volume != 0) return volume;
        final number = naturalCompare(a.chapter.number, b.chapter.number);
        return number != 0
            ? number
            : a.chapter.index.compareTo(b.chapter.index);
      });
    return _selectionCache[branchId] = List.unmodifiable(result);
  }
}

class Branch {
  Branch(dynamic value)
    : data = asMap(value),
      id = value is Map ? textOf(value['branch_id'], '0') : textOf(value, '0');
  final Json data;
  final String id;
  bool get moderated => asMap(data['moderation'])['id'] == 0;
  bool get restricted => asMap(data['restricted_view'])['is_open'] == false;
  List<String> get teams {
    final source = asList(data['teams']);
    final values = source.isEmpty ? [asMap(data['team'])] : source;
    return values
        .map((t) => decodeEntities(textOf(asMap(t)['name'])))
        .where((s) => s.isNotEmpty)
        .toList();
  }
}

class Chapter {
  Chapter(this.data, this.branches);
  final Json data;
  final List<Branch> branches;
  String get volume => textOf(data['volume'], '0');
  String get number => textOf(data['number'], '0');
  String get name => decodeEntities(textOf(data['name'])).trim();
  num get index => num.tryParse(textOf(data['index'])) ?? 0;
  String get key => '$volume/$number';
  String get title => 'Глава $number${name.isEmpty ? '' : ' — $name'}';

  static List<Chapter> fromResponse(dynamic value) {
    final result = <Chapter>[];
    for (final raw in asList(value)) {
      final data = asMap(raw);
      final branches = asList(data['branches']).map(Branch.new).toList();
      if (branches.any((b) => b.moderated)) continue;
      branches.removeWhere((b) => b.restricted);
      if (branches.isNotEmpty) result.add(Chapter(data, branches));
    }
    return result;
  }
}

class ChapterSelection {
  const ChapterSelection(this.chapter, this.branch);
  final Chapter chapter;
  final Branch branch;
}

class PreparedChapter {
  const PreparedChapter(this.chapter, this.xhtml);
  final Chapter chapter;
  final String xhtml;
}

class BookImage {
  const BookImage(this.name, this.mime, this.bytes);
  final String name;
  final String mime;
  final List<int> bytes;
}

class SavedBook {
  const SavedBook(this.uri, this.name);
  final String uri;
  final String name;
  String get location => 'Downloads/ranobelib/$name';
}
