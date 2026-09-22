import 'package:flutter/foundation.dart';
import '../services/settings_service.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._service);
  final SettingsService _service;

  AppSettings _s = const AppSettings();
  AppSettings get settings => _s;

  Future<void> load() async {
    _s = await _service.load();
    notifyListeners();
  }

  Future<void> update(AppSettings next) async {
    _s = next;
    notifyListeners();
    await _service.save(next);
  }
}
