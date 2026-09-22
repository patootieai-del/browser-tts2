import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/extraction_service.dart';
import 'services/settings_service.dart';
import 'services/tts_service.dart';
import 'state/library_controller.dart';
import 'state/reader_controller.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWebPlaceholder) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  final settings = SettingsController(SettingsService());
  await settings.load();

  final tts = TtsService();
  await tts.init();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider(
          create: (_) =>
              ReaderController(tts: tts, extractor: ExtractionService())),
      ChangeNotifierProvider(create: (_) => LibraryController()),
    ],
    child: const VoxApp(),
  ));
}

const bool kIsWebPlaceholder = false;
