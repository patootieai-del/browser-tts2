# browser_flutter

A new Flutter project.

## Project Structure

```text
lib/
├── main.dart
├── app.dart
├── core/
│   ├── theme/app_themes.dart
│   └── utils/text_chunker.dart
├── models/
│   ├── bookmark.dart
│   ├── history_entry.dart
│   └── article.dart
├── services/
│   ├── database_service.dart
│   ├── settings_service.dart
│   ├── tts_service.dart
│   └── extraction_service.dart
├── state/
│   ├── settings_controller.dart
│   ├── reader_controller.dart
│   └── library_controller.dart
├── screens/
│   ├── browser_screen.dart
│   ├── reader_screen.dart
│   ├── settings_screen.dart
│   ├── history_screen.dart
│   └── bookmarks_screen.dart
└── widgets/
    ├── url_bar.dart
    ├── tts_control_bar.dart
    └── app_drawer.dart
assets/
└── js/readability.js      # from github.com/mozilla/readability (dist)
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
