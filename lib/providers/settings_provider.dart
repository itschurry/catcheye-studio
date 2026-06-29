import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsProvider extends ChangeNotifier {
  static const _detectorBaseUrlKey = 'settings.detectorBaseUrl';
  static const _streamPathKey = 'settings.streamPath';
  static const _apiBasePathKey = 'settings.apiBasePath';
  static const _remoteDeviceKindKey = 'settings.remoteDeviceKind';
  static const _cubeEyeFramerateKey = 'settings.cubeEye.framerate';
  static const _cubeEyeAutoExposureKey = 'settings.cubeEye.autoExposure';
  static const _cubeEyeIlluminationKey = 'settings.cubeEye.illumination';
  static const _cubeEyeDepthRangeMinKey = 'settings.cubeEye.depthRangeMin';
  static const _cubeEyeDepthRangeMaxKey = 'settings.cubeEye.depthRangeMax';
  static const _pointCloudPointSizeKey = 'settings.pointCloud.pointSize';
  static const _pointCloudShowAxisKey = 'settings.pointCloud.showAxis';
  static const _pointCloudAxisScaleKey = 'settings.pointCloud.axisScale';
  static const _pointCloudPaletteKey = 'settings.pointCloud.palette';
  static const _pointCloudDepthMinKey = 'settings.pointCloud.depthMin';
  static const _pointCloudDepthMaxKey = 'settings.pointCloud.depthMax';
  static const _guardMonitorStreamsKey = 'settings.guardMonitor.streams';
  static const _personRoiAlertDisabledKey =
      'settings.personRoiAlertDisabled';

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
        remoteDeviceKind: _remoteDeviceKindFromPrefs(
          prefs.getString(_remoteDeviceKindKey),
        ),
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
        pointCloudPointSize:
            prefs.getDouble(_pointCloudPointSizeKey) ??
            AppSettings.defaultPointCloudPointSize,
        pointCloudShowAxis:
            prefs.getBool(_pointCloudShowAxisKey) ??
            AppSettings.defaultPointCloudShowAxis,
        pointCloudAxisScale:
            prefs.getDouble(_pointCloudAxisScaleKey) ??
            AppSettings.defaultPointCloudAxisScale,
        pointCloudPalette:
            prefs.getString(_pointCloudPaletteKey) ??
            AppSettings.defaultPointCloudPalette,
        pointCloudDepthMin: prefs.getDouble(_pointCloudDepthMinKey),
        pointCloudDepthMax: prefs.getDouble(_pointCloudDepthMaxKey),
        guardMonitorStreams:
            prefs.getStringList(_guardMonitorStreamsKey) ??
            AppSettings.defaultGuardMonitorStreams,
        personRoiAlertDisabled:
            prefs.getBool(_personRoiAlertDisabledKey) ??
            AppSettings.defaultPersonRoiAlertDisabled,
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
    required RemoteDeviceKind remoteDeviceKind,
    required bool personRoiAlertDisabled,
  }) async {
    _settings.streamPath = streamPath;
    _settings.detectorBaseUrl = detectorBaseUrl;
    _settings.remoteDeviceKind = remoteDeviceKind;
    _settings.personRoiAlertDisabled = personRoiAlertDisabled;
    await _save();
    notifyListeners();
  }

  Future<void> updateRemoteDeviceKind(RemoteDeviceKind value) async {
    _settings.remoteDeviceKind = value;
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

  Future<void> updatePointCloudViewerSettings({
    required double pointSize,
    required bool showAxis,
    required double axisScale,
    required String palette,
    required double? depthMin,
    required double? depthMax,
  }) async {
    _settings.pointCloudPointSize = pointSize;
    _settings.pointCloudShowAxis = showAxis;
    _settings.pointCloudAxisScale = axisScale;
    _settings.pointCloudPalette = palette;
    _settings.pointCloudDepthMin = depthMin;
    _settings.pointCloudDepthMax = depthMax;
    await _save();
    notifyListeners();
  }

  Future<void> updateGuardMonitorStreams(List<String> streams) async {
    _settings.guardMonitorStreams = streams
        .map((stream) => stream.trim())
        .where((stream) => stream.isNotEmpty)
        .toList(growable: false);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_detectorBaseUrlKey, _settings.detectorBaseUrl);
    await prefs.setString(_streamPathKey, _settings.streamPath);
    await prefs.setString(_apiBasePathKey, _settings.apiBasePath);
    final remoteDeviceKind = _settings.remoteDeviceKind;
    if (remoteDeviceKind == null) {
      await prefs.remove(_remoteDeviceKindKey);
    } else {
      await prefs.setString(_remoteDeviceKindKey, remoteDeviceKind.apiValue);
    }
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
    await prefs.setDouble(
      _pointCloudPointSizeKey,
      _settings.pointCloudPointSize,
    );
    await prefs.setBool(_pointCloudShowAxisKey, _settings.pointCloudShowAxis);
    await prefs.setDouble(
      _pointCloudAxisScaleKey,
      _settings.pointCloudAxisScale,
    );
    await prefs.setString(_pointCloudPaletteKey, _settings.pointCloudPalette);
    if (_settings.pointCloudDepthMin == null) {
      await prefs.remove(_pointCloudDepthMinKey);
    } else {
      await prefs.setDouble(
        _pointCloudDepthMinKey,
        _settings.pointCloudDepthMin!,
      );
    }
    if (_settings.pointCloudDepthMax == null) {
      await prefs.remove(_pointCloudDepthMaxKey);
    } else {
      await prefs.setDouble(
        _pointCloudDepthMaxKey,
        _settings.pointCloudDepthMax!,
      );
    }
    await prefs.setStringList(
      _guardMonitorStreamsKey,
      _settings.guardMonitorStreams,
    );
    await prefs.setBool(
      _personRoiAlertDisabledKey,
      _settings.personRoiAlertDisabled,
    );
  }

  static RemoteDeviceKind? _remoteDeviceKindFromPrefs(String? value) {
    if (value == null) {
      return null;
    }
    return RemoteDeviceKind.fromApiValue(value);
  }
}
