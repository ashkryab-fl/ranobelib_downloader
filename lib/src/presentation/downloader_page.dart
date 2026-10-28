import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/auth.dart';
import '../domain/models.dart';
import 'cubit/download_cubit.dart';
import 'cubit/download_state.dart';
import 'login_page.dart';
import 'widgets/chapter_list.dart';

class DownloaderPage extends StatefulWidget {
  const DownloaderPage({super.key});
  @override
  State<DownloaderPage> createState() => _DownloaderPageState();
}

class _DownloaderPageState extends State<DownloaderPage> {
  final _controller = DownloadCubit();
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
    final book = _controller.state.novel;
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
    _controller.close();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<DownloadCubit, DownloadState>(
    bloc: _controller,
    builder: (context, c) {
      final book = c.novel;
      final username = textOf(
        c.user?['username'] ?? c.user?['name'],
        'Аккаунт',
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('RanobeLIB'),
          actions: [
            if (c.user == null)
              TextButton.icon(
                onPressed: c.busy ? null : _login,
                icon: const Icon(Icons.login),
                label: const Text('Войти'),
              )
            else
              PopupMenuButton<String>(
                enabled: !c.busy,
                tooltip: username,
                onSelected: (_) => _logout(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'logout',
                    child: Text('Выйти · $username'),
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
                            'Книга по ссылке',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Вставьте ссылку RanobeLIB, выберите главы и сохраните EPUB.',
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
                              labelText: 'Ссылка на книгу',
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
                              label: const Text('Загрузить информацию'),
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
                                          : () => _controller.openBook(saved),
                                      icon: const Icon(Icons.menu_book),
                                      label: const Text('Открыть EPUB'),
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
                                      onPressed: _controller.cancel,
                                      child: const Text('Отмена'),
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
                                labelText: 'Ветка перевода',
                                helperText:
                                    'Меняет перевод там, где он доступен. Остальные главы остаются без изменений.',
                                helperMaxLines: 3,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'automatic',
                                  child: Text(
                                    'Автоматически · ${book.selectBranch(null).length} глав',
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
                                  : (value) => _controller.setBranch(
                                      value == 'automatic' ? null : value,
                                    ),
                            ),
                            const SizedBox(height: 12),
                            CheckboxListTile(
                              value: c.splitByVolume,
                              onChanged: c.busy
                                  ? null
                                  : (value) => _controller.setSplitByVolume(
                                      value ?? false,
                                    ),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text(
                                'Отдельный EPUB для каждого тома',
                              ),
                              subtitle: const Text(
                                'Номер тома будет добавлен к имени файла.',
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Выбрано ${c.selected.length} из ${c.chapters.length}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                TextButton(
                                  onPressed: c.busy
                                      ? null
                                      : () => _controller.selectAll(
                                          c.selected.length !=
                                              c.chapters.length,
                                        ),
                                  child: Text(
                                    c.selected.length == c.chapters.length
                                        ? 'Снять выделение'
                                        : 'Выбрать все',
                                  ),
                                ),
                              ],
                            ),
                            if (c.chapters.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Text('Нет доступных глав.'),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  ChapterList(controller: _controller, state: c),
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
                    onPressed: c.busy || c.selected.isEmpty
                        ? null
                        : _controller.download,
                    icon: const Icon(Icons.download),
                    label: Text(
                      c.busy
                          ? 'Подождите…'
                          : 'Скачать EPUB · ${c.selected.length} глав',
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
