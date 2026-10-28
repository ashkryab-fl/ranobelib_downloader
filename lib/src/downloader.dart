import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

import 'api.dart';
import 'content.dart';
import 'epub.dart';
import 'models.dart';

/// Same fixed policy as Python: fit within 800×800, JPEG quality 90.
BookImage compressImage(Uint8List bytes) {
  var decoded = image.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Не вдалося прочитати зображення.');
  }
  if (decoded.width > 800 || decoded.height > 800) {
    final ratio =
        800 / (decoded.width > decoded.height ? decoded.width : decoded.height);
    decoded = image.copyResize(
      decoded,
      width: (decoded.width * ratio).round().clamp(1, 800),
      height: (decoded.height * ratio).round().clamp(1, 800),
      interpolation: image.Interpolation.cubic,
    );
  }
  final animated = decoded.numFrames > 1;
  final alpha = decoded.hasAlpha;
  final extension = animated
      ? 'gif'
      : alpha
      ? 'png'
      : 'jpg';
  final output = animated
      ? image.encodeGif(decoded)
      : alpha
      ? image.encodePng(decoded, level: 9)
      : image.encodeJpg(decoded, quality: 90);
  final hash = sha256.convert(output).toString();
  return BookImage(
    '$hash.$extension',
    'image/${extension == 'jpg' ? 'jpeg' : extension}',
    output,
  );
}

class DownloadProgress {
  const DownloadProgress(this.message, this.completed, this.total);
  final String message;
  final int completed;
  final int total;
  double? get fraction => total == 0 ? null : completed / total;
}

class BookDownloader {
  BookDownloader(this.api);
  final RanobeApi api;

  Future<Uint8List> download(
    Novel novel,
    List<ChapterSelection> selected,
    Cancellation cancel,
    void Function(DownloadProgress) onProgress, {
    String? volume,
  }) async {
    if (selected.isEmpty) {
      throw const FormatException('Виберіть хоча б одну главу.');
    }
    final parser = ContentParser();
    final images = <String, BookImage>{};
    final urlNames = <String, String>{};
    Future<BookImage> fetch(String url) async {
      cancel.check();
      final data = await api.image(url, cancel);
      final compressed = await cancel.bind(compute(compressImage, data));
      cancel.check();
      return compressed;
    }

    onProgress(
      DownloadProgress('Завантаження обкладинки…', 0, selected.length),
    );
    BookImage? cover;
    if (novel.cover.isNotEmpty) {
      final fetched = await fetch(novel.cover);
      cover = BookImage(
        'cover.${fetched.name.split('.').last}',
        fetched.mime,
        fetched.bytes,
      );
    }
    final prepared = <PreparedChapter>[];
    for (var i = 0; i < selected.length; i++) {
      cancel.check();
      final selection = selected[i];
      onProgress(
        DownloadProgress(
          'Том ${selection.chapter.volume} · ${selection.chapter.title}',
          i,
          selected.length,
        ),
      );
      final chapter = await api.chapter(novel.slug, selection, cancel);
      final raw = parser.chapterHtml(chapter);
      if (raw.trim().isEmpty) {
        throw ApiException(
          'Не вдалося прочитати вміст глави ${selection.chapter.number}.',
        );
      }
      final xhtml = await parser.prepare(raw, (url) async {
        final cached = urlNames[url];
        if (cached != null) return cached;
        final downloaded = await fetch(url);
        images.putIfAbsent(downloaded.name, () => downloaded);
        urlNames[url] = downloaded.name;
        return downloaded.name;
      });
      prepared.add(PreparedChapter(selection.chapter, xhtml));
      onProgress(
        DownloadProgress(
          'Завантажено ${i + 1} із ${selected.length} глав',
          i + 1,
          selected.length,
        ),
      );
    }
    cancel.check();
    onProgress(
      DownloadProgress('Створення EPUB…', selected.length, selected.length),
    );
    final bytes = await cancel.bind(
      compute(
        buildEpub,
        EpubInput(
          novel,
          prepared,
          images.values.toList(),
          cover,
          volume: volume,
        ),
      ),
    );
    cancel.check();
    return bytes;
  }
}
