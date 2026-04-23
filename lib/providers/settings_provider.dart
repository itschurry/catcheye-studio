import 'package:flutter/material.dart';

import '../models/app_settings.dart';

class SettingsProvider extends ChangeNotifier {
  final AppSettings _settings = AppSettings();

  AppSettings get settings => _settings;

  void updateDetectorBaseUrl(String value) {
    _settings.detectorBaseUrl = value;
    notifyListeners();
  }

  void updateStreamPath(String value) {
    _settings.streamPath = value;
    notifyListeners();
  }

  void updateApiBasePath(String value) {
    _settings.apiBasePath = value;
    notifyListeners();
  }
}
