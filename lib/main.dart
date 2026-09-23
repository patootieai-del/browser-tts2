import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/extraction_service.dart';
import 'services/reader_audio_handler.dart';
import 'services/settings_service.dart';
import 'services/tts_service.dart';
import 'state/chapter_rule_store.dart';
import 'state/element_picker_controller.dart';
import 'state/library_controller.dart';
import 'state/reader_controller.dart';
import 'state/settings_controller.dart';
import 'state/tabs_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };

  if (kDebugMode) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  final settings = SettingsController(SettingsService());
  await settings.load();
  final rules = ChapterRuleStore();
  await rules.load();

  final tts = TtsService();
  await tts.init();

  final reader = ReaderController(
    tts: tts,
    extractor: ExtractionService(),
    rules: rules,
  );
  await reader.applySettings(settings.settings);

  // Foreground service + media session. androidStopForegroundOnPause:false
  // keeps the service (and the process) alive while paused or between chapters.
  await AudioService.init(
    builder: () => ReaderAudioHandler(reader),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.yourname.vox_browser.reading',
      androidNotificationChannelName: 'Reading',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  // App-lifetime objects use .value (never disposed on purpose).
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: rules),
      Provider<TtsService>.value(value: tts),
      ChangeNotifierProvider.value(value: reader),
      ChangeNotifierProvider(create: (_) => LibraryController()),
      ChangeNotifierProvider(create: (_) => ElementPickerController()),
      ChangeNotifierProvider(
          create: (c) => TabsController(c.read<ReaderController>())..restore()),
    ],
    child: const VoxApp(),
  ));
}