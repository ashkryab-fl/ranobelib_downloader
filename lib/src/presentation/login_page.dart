import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/auth.dart';

class LoginResult {
  const LoginResult({this.callback, this.token});
  final Uri? callback;
  final String? token;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.request});
  final OAuthRequest request;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final WebViewController _web;
  int _progress = 0;
  String? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onNavigationRequest: (navigation) {
            final uri = Uri.tryParse(navigation.url);
            if (uri != null && widget.request.isCallback(uri)) {
              _callback(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onUrlChange: (change) {
            final uri = Uri.tryParse(change.url ?? '');
            if (uri != null && widget.request.isCallback(uri)) _callback(uri);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted && !_finished) {
              setState(
                () => _error =
                    'Не удалось открыть страницу входа. Проверьте интернет или вставьте токен.',
              );
            }
          },
        ),
      )
      ..loadRequest(widget.request.url);
  }

  void _callback(Uri uri) {
    if (_finished || !mounted) return;
    try {
      widget.request.codeFromCallback(uri);
      _finished = true;
      Navigator.of(context).pop(LoginResult(callback: uri));
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pasteToken() async {
    final input = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Вход по токену'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Вставьте access token своего аккаунта RanobeLIB, если вход через сайт не работает.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: input,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Токен',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: const Text('Войти'),
          ),
        ],
      ),
    );
    // Dialog route animation may still reference the text controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (token != null && token.isNotEmpty && mounted && !_finished) {
      _finished = true;
      Navigator.of(context).pop(LoginResult(token: token));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Вход в RanobeLIB')),
    body: SafeArea(
      child: Column(
        children: [
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: () {
                      setState(() => _error = null);
                      _web.loadRequest(widget.request.url);
                    },
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          Expanded(child: WebViewWidget(controller: _web)),
          TextButton.icon(
            onPressed: _pasteToken,
            icon: const Icon(Icons.key),
            label: const Text('Вставить токен'),
          ),
        ],
      ),
    ),
  );
}
