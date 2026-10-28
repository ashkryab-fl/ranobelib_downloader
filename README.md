# RanobeLIB Downloader

Simple Flutter app for Android 10+ that downloads RanobeLIB novels as EPUB.
The Dart implementation is based on the Python reference in `ranobelib-downloader/`.
Python is not required to run the app; its source and existing local data are preserved.

## Use

1. Paste an HTTPS book URL, such as `https://ranobelib.me/ru/book/123--name`.
2. Load the book. Sign in if needed using the site's embedded OAuth page. A token
   input is available if web login is unavailable. Tokens are stored securely,
   restored on launch, and refreshed when the server expires a session.
3. Use automatic translation selection or choose a specific branch in the top
   dropdown. Choosing a branch switches every chapter that offers it and keeps
   the current translation for other chapters. It preserves chapter checkmarks.
   Select individual chapters, entire volumes, or all chapters.
   Translation radio buttons are connected to their chapter with tree lines. When
   every chapter in a volume offers the same branches, one tree for the volume replaces
   the chapter lists. Local translation changes preserve checked chapters and are
   used when exporting EPUB. Tap a volume heading or its arrow to collapse or
   expand it; collapsed volumes retain their selected chapters and translations.
4. Optionally enable **Окремий EPUB для кожного тому** to export selected chapters
   as separate volumes, named `Novel title — Том 2.epub`. Otherwise, one EPUB
   contains all selected chapters.
5. Download the EPUB files. They are saved in public **Downloads/ranobelib** and
   each can be opened in an installed EPUB reader. Existing books are not overwritten.

Keep the app open while downloading. Cancellation interrupts chapter/image
requests and rate-limit waits. Saving the completed file finishes atomically.
Failed chapters or images produce an error rather than silently creating a
partial book. When exporting separate volumes, completed files remain available
if a later volume fails or the download is cancelled. The app only downloads
content accessible to the current account.

## Fixed export policy

- EPUB only; contents grouped by volume, including a nested table of contents.
- Cover and chapter images always downloaded when present.
- Raster images always processed: maximum 800×800, JPEG quality 90; PNG alpha
  and animated GIFs retained. Identical illustrations are embedded once.
- Author, title, summary, genres/tags and publication year retained.
- No added translator information and no persistent book/chapter/image cache.
- Output always `Downloads/ranobelib`; temporary export files are deleted after saving.

Android's [MediaStore Downloads API](https://developer.android.com/reference/android/provider/MediaStore.Downloads)
publishes completed books with `IS_PENDING`. No broad storage permission is needed.
OAuth uses the reference script's client ID, callback and API endpoints, with
PKCE S256 and callback state verification.

## Develop

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The generated APK is `build/app/outputs/flutter-apk/app-release.apk`. The included
release configuration uses the local debug signing key for direct installation;
configure a private release key before store distribution.

`lib/src/api.dart` handles API requests, retries, authorization and rate limits.
`auth.dart` manages OAuth and secure tokens. `models.dart` selects translations
and chapters. `content.dart`, `downloader.dart` and `epub.dart` convert content,
compress images and assemble EPUB 3 with NCX compatibility. `controller.dart`
owns screen state. The Android method channel writes and opens public downloads.

Tests cover URL validation, filtering and branch selection, content/XML safety,
image compression, EPUB structure, OAuth state/PKCE, token rotation, credential
isolation, cancellation and a mocked API-to-EPUB export. They do not prove live
site login or device storage behavior.

For an independent format check, generate a synthetic book and run
[EPUBCheck](https://github.com/w3c/epubcheck):

```sh
dart run tool/epub_fixture.dart
java -jar /path/to/epubcheck.jar build/verification/fixture.epub
```

The original Python project's MIT copyright and license are retained in `LICENSE`.
