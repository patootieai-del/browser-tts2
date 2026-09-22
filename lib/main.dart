import 'package:flutter/foundation.dart';
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
import 'state/tabs_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Never crash the app on an uncaught async error.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };

  if (kDebugMode) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  final settings = SettingsController(SettingsService());
  await settings.load();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      Provider<TtsService>(
        create: (_) => TtsService()..init(),
        dispose: (_, t) => t.dispose(),
      ),
      Provider<ExtractionService>(create: (_) => ExtractionService()),
      ChangeNotifierProvider(
        create: (c) => ReaderController(
          tts: c.read<TtsService>(),
          extractor: c.read<ExtractionService>(),
        )..applySettings(c.read<SettingsController>().settings), // fix #12
      ),
      ChangeNotifierProvider(create: (_) => LibraryController()),
      ChangeNotifierProvider(
        create: (c) => TabsController(c.read<ReaderController>())..restore(),
      ),
    ],
    child: const VoxApp(),
  ));
}