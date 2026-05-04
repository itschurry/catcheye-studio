import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsProvider extends ChangeNotifier {
  static const _detectorBaseUrlKey = 'settings.detectorBaseUrl';
  static const _streamPathKey = 'settings.streamPath';
  static const _apiBasePathKey = 'settings.apiBasePath';

  final AppSettings _settings;

  SettingsProvider({AppSettings? initialSettings})
    : _settings = initialSettings ?? AppSettings();

  static Future<SettingsProvider> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsProvider(
      initialSettings: AppSettings(
        detectorBaseUrl:
            prefs.getString(_detectorBaseUrlKey) ??
            AppSettings.defaultDetectorBaseUrl,
        streamPath:
            prefs.getString(_streamPathKey) ?? AppSettings.defaultStreamPath,
        apiBasePath:
            prefs.getString(_apiBasePathKey) ?? AppSettings.defaultApiBasePath,
      ),
    );
  }

  AppSettings get settings => _settings;

  Future<void> updateDetectorBaseUrl(String value) async {
    _settings.detectorBaseUrl = value;
    await _save();
    notifyListeners();
  }

  Future<void> updateStreamPath(String value) async {
    _settings.streamPath = value;
    await _save();
    notifyListeners();
  }

  Future<void> updateApiBasePath(String value) async {
    _settings.apiBasePath = value;
    await _save();
    notifyListeners();
  }

  Future<void> updateConnectionUrls({
    required String streamPath,
    required String detectorBaseUrl,
  }) async {
    _settings.streamPath = streamPath;
    _settings.detectorBaseUrl = detectorBaseUrl;
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_detectorBaseUrlKey, _settings.detectorBaseUrl);
    await prefs.setString(_streamPathKey, _settings.streamPath);
    await prefs.setString(_apiBasePathKey, _settings.apiBasePath);
  }
}
