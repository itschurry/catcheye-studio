import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsProvider extends ChangeNotifier {
  static const _detectorBaseUrlKey = 'settings.detectorBaseUrl';
  static const _streamPathKey = 'settings.streamPath';
  static const _apiBasePathKey = 'settings.apiBasePath';
  static const _cubeEyeFramerateKey = 'settings.cubeEye.framerate';
  static const _cubeEyeAutoExposureKey = 'settings.cubeEye.autoExposure';
  static const _cubeEyeIlluminationKey = 'settings.cubeEye.illumination';
  static const _cubeEyeDepthRangeMinKey = 'settings.cubeEye.depthRangeMin';
  static const _cubeEyeDepthRangeMaxKey = 'settings.cubeEye.depthRangeMax';

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
        cubeEyeFramerate:
            prefs.getInt(_cubeEyeFramerateKey) ??
            AppSettings.defaultCubeEyeFramerate,
        cubeEyeAutoExposure:
            prefs.getBool(_cubeEyeAutoExposureKey) ??
            AppSettings.defaultCubeEyeAutoExposure,
        cubeEyeIllumination:
            prefs.getBool(_cubeEyeIlluminationKey) ??
            AppSettings.defaultCubeEyeIllumination,
        cubeEyeDepthRangeMin:
            prefs.getInt(_cubeEyeDepthRangeMinKey) ??
            AppSettings.defaultCubeEyeDepthRangeMin,
        cubeEyeDepthRangeMax:
            prefs.getInt(_cubeEyeDepthRangeMaxKey) ??
            AppSettings.defaultCubeEyeDepthRangeMax,
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

  Future<void> updateCubeEyeSettings({
    required int framerate,
    required bool autoExposure,
    required bool illumination,
    required int depthRangeMin,
    required int depthRangeMax,
  }) async {
    _settings.cubeEyeFramerate = framerate;
    _settings.cubeEyeAutoExposure = autoExposure;
    _settings.cubeEyeIllumination = illumination;
    _settings.cubeEyeDepthRangeMin = depthRangeMin;
    _settings.cubeEyeDepthRangeMax = depthRangeMax;
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_detectorBaseUrlKey, _settings.detectorBaseUrl);
    await prefs.setString(_streamPathKey, _settings.streamPath);
    await prefs.setString(_apiBasePathKey, _settings.apiBasePath);
    await prefs.setInt(_cubeEyeFramerateKey, _settings.cubeEyeFramerate);
    await prefs.setBool(_cubeEyeAutoExposureKey, _settings.cubeEyeAutoExposure);
    await prefs.setBool(_cubeEyeIlluminationKey, _settings.cubeEyeIllumination);
    await prefs.setInt(
      _cubeEyeDepthRangeMinKey,
      _settings.cubeEyeDepthRangeMin,
    );
    await prefs.setInt(
      _cubeEyeDepthRangeMaxKey,
      _settings.cubeEyeDepthRangeMax,
    );
  }
}
