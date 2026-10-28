import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/presentation/downloader_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RanobeApp());
}

class RanobeApp extends StatelessWidget {
  const RanobeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RanobeLIB Downloader',
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
