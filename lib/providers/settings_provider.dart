import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/station_viewer_layout.dart';

class SettingsProvider extends ChangeNotifier {
  static const _detectorBaseUrlKey = 'settings.detectorBaseUrl';
  static const _streamPathKey = 'settings.streamPath';
  static const _apiBasePathKey = 'settings.apiBasePath';
  static const _remoteDeviceKindKey = 'settings.remoteDeviceKind';
  static const _legacyGuardDeviceKind = 'guard';
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
  static const _hssMonitorStreamsKey = 'settings.hssMonitor.streams';
  static const _personRoiAlertDisabledKey = 'settings.personRoiAlertDisabled';
  static const _stationViewerLayoutKey = 'settings.stationViewer.layout';
  static const _stationViewerCameraSlotsKey =
      'settings.stationViewer.cameraSlots';

  final AppSettings _settings;
  int _connectionRevision = 0;

  SettingsProvider({AppSettings? initialSettings})
    : _settings = initialSettings ?? AppSettings();

  static Future<SettingsProvider> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedRemoteDeviceKind = prefs.getString(_remoteDeviceKindKey);
    final remoteDeviceKind = _remoteDeviceKindFromPrefs(storedRemoteDeviceKind);
    if (storedRemoteDeviceKind == _legacyGuardDeviceKind) {
      await prefs.setString(
        _remoteDeviceKindKey,
        RemoteDeviceKind.hss.apiValue,
      );
    }
    return SettingsProvider(
      initialSettings: AppSettings(
        detectorBaseUrl:
            prefs.getString(_detectorBaseUrlKey) ??
            AppSettings.defaultDetectorBaseUrl,
        streamPath:
            prefs.getString(_streamPathKey) ?? AppSettings.defaultStreamPath,
        apiBasePath:
            prefs.getString(_apiBasePathKey) ?? AppSettings.defaultApiBasePath,
        remoteDeviceKind: remoteDeviceKind,
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
        hssMonitorStreams:
            prefs.getStringList(_hssMonitorStreamsKey) ??
            AppSettings.defaultHssMonitorStreams,
        personRoiAlertDisabled:
            prefs.getBool(_personRoiAlertDisabledKey) ??
            AppSettings.defaultPersonRoiAlertDisabled,
        stationViewerLayout: StationViewerLayout.fromName(
          prefs.getString(_stationViewerLayoutKey),
        ),
        stationViewerCameraSlots:
            prefs.getStringList(_stationViewerCameraSlotsKey) ??
            AppSettings.defaultStationViewerCameraSlots,
      ),
    );
  }

  AppSettings get settings => _settings;
  int get connectionRevision => _connectionRevision;

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
    _connectionRevision++;
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

  Future<void> updateHssMonitorStreams(List<String> streams) async {
    _settings.hssMonitorStreams = streams
        .map((stream) => stream.trim())
        .where((stream) => stream.isNotEmpty)
        .toList(growable: false);
    await _save();
    notifyListeners();
  }

  Future<void> updateStationViewerLayout({
    required StationViewerLayout layout,
    required List<String> cameraSlots,
  }) async {
    _settings.stationViewerLayout = layout;
    _settings.stationViewerCameraSlots = List.of(cameraSlots);
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
      _hssMonitorStreamsKey,
      _settings.hssMonitorStreams,
    );
    await prefs.setBool(
      _personRoiAlertDisabledKey,
      _settings.personRoiAlertDisabled,
    );
    await prefs.setString(
      _stationViewerLayoutKey,
      _settings.stationViewerLayout.name,
    );
    await prefs.setStringList(
      _stationViewerCameraSlotsKey,
      _settings.stationViewerCameraSlots,
    );
  }

  static RemoteDeviceKind? _remoteDeviceKindFromPrefs(String? value) {
    if (value == null) {
      return null;
    }
    if (value == _legacyGuardDeviceKind) {
      return RemoteDeviceKind.hss;
    }
    return RemoteDeviceKind.fromApiValue(value);
  }
}
