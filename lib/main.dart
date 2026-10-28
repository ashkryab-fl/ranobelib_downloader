import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'src/auth.dart';
import 'src/chapter_list.dart';
import 'src/controller.dart';
import 'src/login_page.dart';
import 'src/models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RanobeApp());
}

class RanobeApp extends StatelessWidget {
  const RanobeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RanobeLIB Downloader',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff13756a)),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff7f9f8),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: const DownloaderPage(),
  );
}

class DownloaderPage extends StatefulWidget {
  const DownloaderPage({super.key});
  @override
  State<DownloaderPage> createState() => _DownloaderPageState();
}

class _DownloaderPageState extends State<DownloaderPage> {
  final _controller = DownloadController();
  final _url = TextEditingController();
  @override
  void initState() {
    super.initState();
    _controller.api.authorize = _signIn;
    unawaited(_controller.initialize());
  }

  Future<bool> _signIn() async {
    if (!mounted) return false;
    final request = OAuthRequest();
    final result = await Navigator.of(context).push<LoginResult>(
      MaterialPageRoute(builder: (_) => LoginPage(request: request)),
    );
    if (result == null) return false;
    if (result.token != null) {
      await _controller.auth.directToken(result.token!);
    } else if (result.callback != null) {
      await _controller.auth.finish(request, result.callback!);
    }
    _controller.accountChanged();
    return true;
  }

  Future<void> _login() async {
    var signedIn = false;
    final book = _controller.novel;
    await _controller.run(() async {
      signedIn = await _signIn();
    });
    if (signedIn && book != null && mounted) {
      await _controller.load('https://ranobelib.me/ru/book/${book.slug}');
    }
  }

  Future<void> _logout() async {
    await _controller.logout();
    await WebViewCookieManager().clearCookies();
  }

  void _load() {
    FocusScope.of(context).unfocus();
    unawaited(_controller.load(_url.text));
  }

  @override
  void dispose() {
    _controller.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final c = _controller;
      final book = c.novel;
      final username = textOf(
        c.auth.user?['username'] ?? c.auth.user?['name'],
        'Акаунт',
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('RanobeLIB'),
          actions: [
            if (c.auth.user == null)
              TextButton.icon(
                onPressed: c.busy ? null : _login,
                icon: const Icon(Icons.login),
                label: const Text('Увійти'),
              )
            else
              PopupMenuButton<String>(
                enabled: !c.busy,
                tooltip: username,
                onSelected: (_) => _logout(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'logout',
                    child: Text('Вийти · $username'),
                  ),
                ],
                icon: const Icon(Icons.account_circle_outlined),
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Книга за посиланням',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Вставте посилання RanobeLIB, виберіть глави та збережіть EPUB.',
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _url,
                            enabled: !c.busy,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.go,
                            autocorrect: false,
                            onSubmitted: (_) => _load(),
                            decoration: const InputDecoration(
                              labelText: 'Посилання на книгу',
                              hintText: 'https://ranobelib.me/ru/book/…',
                              prefixIcon: Icon(Icons.link),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: c.busy ? null : _load,
                              icon: const Icon(Icons.search),
                              label: const Text('Завантажити інформацію'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text('EPUB · Downloads/ranobelib'),
                              ),
                            ],
                          ),
                          if (c.error != null) _message(c.error!, error: true),
                          if (c.notice != null) _message(c.notice!),
                          for (final saved in c.savedBooks)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.check_circle_outline),
                                    const SizedBox(height: 8),
                                    SelectableText(saved.location),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: c.busy
                                          ? null
                                          : () => c.openBook(saved),
                                      icon: const Icon(Icons.menu_book),
                                      label: const Text('Відкрити EPUB'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (c.progress != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LinearProgressIndicator(
                                    value: c.progress!.fraction,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(c.progress!.message),
                                  if (!c.saving)
                                    TextButton(
                                      onPressed: c.cancel,
                                      child: const Text('Скасувати'),
                                    ),
                                ],
                              ),
                            ),
                          if (book != null) ...[
                            const SizedBox(height: 24),
                            Text(
                              book.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (book.author.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(book.author),
                              ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: c.branch ?? 'automatic',
                              key: ValueKey('${book.slug}:${c.branch}'),
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Гілка перекладу',
                                helperText:
                                    'Перемикає переклад там, де він доступний. Решта глав — без змін.',
                                helperMaxLines: 3,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'automatic',
                                  child: Text(
                                    'Автоматично · ${book.selectBranch(null).length} глав',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                for (final branch in book.branchNames.entries)
                                  if (book.selectBranch(branch.key).isNotEmpty)
                                    DropdownMenuItem(
                                      value: branch.key,
                                      child: Text(
                                        '${branch.value} · ${book.selectBranch(branch.key).length} глав',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                              ],
                              onChanged: c.busy
                                  ? null
                                  : (value) => c.setBranch(
                                      value == 'automatic' ? null : value,
                                    ),
                            ),
                            const SizedBox(height: 12),
                            CheckboxListTile(
                              value: c.splitByVolume,
                              onChanged: c.busy
                                  ? null
                                  : (value) =>
                                        c.setSplitByVolume(value ?? false),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text(
                                'Окремий EPUB для кожного тому',
                              ),
                              subtitle: const Text(
                                'Номер тому буде додано до назви файлу.',
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Вибрано ${c.selected.length} із ${c.chapters.length}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                TextButton(
                                  onPressed: c.busy
                                      ? null
                                      : () => c.selectAll(
                                          c.selected.length !=
                                              c.chapters.length,
                                        ),
                                  child: Text(
                                    c.selected.length == c.chapters.length
                                        ? 'Зняти всі'
                                        : 'Вибрати всі',
                                  ),
                                ),
                              ],
                            ),
                            if (c.chapters.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Text('Доступних глав немає.'),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  ChapterList(controller: c),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: book == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: FilledButton.icon(
                    onPressed: c.busy || c.selected.isEmpty ? null : c.download,
                    icon: const Icon(Icons.download),
                    label: Text(
                      c.busy
                          ? 'Зачекайте…'
                          : 'Завантажити EPUB · ${c.selected.length} глав',
                    ),
                  ),
                ),
              ),
      );
    },
  );

  Widget _message(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: error
              ? Theme.of(context).colorScheme.onErrorContainer
              : Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    ),
  );
}
