import 'dart:io';

import 'package:flutter/material.dart';

import '../models/roi_config.dart';
import '../services/roi_config_service.dart';

class RoiConfigProvider extends ChangeNotifier {
  CameraRoiConfig _config = CameraRoiConfig.defaultConfig();
  String? _filePath;
  bool _isDirty = false;
  int _selectedZoneIndex = -1;
  String? _errorMessage;

  CameraRoiConfig get config => _config;
  String? get filePath => _filePath;
  bool get isDirty => _isDirty;
  int get selectedZoneIndex => _selectedZoneIndex;
  String? get errorMessage => _errorMessage;

  void selectZone(int index) {
    _selectedZoneIndex = index;
    notifyListeners();
  }

  RoiPolygon? get selectedZone {
    if (_selectedZoneIndex >= 0 && _selectedZoneIndex < _config.allowedZones.length) {
      return _config.allowedZones[_selectedZoneIndex];
    }
    return null;
  }

  Future<void> loadFromFile(String path) async {
    try {
      final config = await RoiConfigService.loadFromFile(path);
      loadFromConfig(config, sourceLabel: path);
    } catch (e) {
      _errorMessage = 'Load failed: $e';
      notifyListeners();
    }
  }

  void loadFromConfig(CameraRoiConfig config, {String? sourceLabel}) {
    _config = config;
    _filePath = sourceLabel;
    _isDirty = false;
    _errorMessage = null;
    _selectedZoneIndex = _config.allowedZones.isNotEmpty ? 0 : -1;
    notifyListeners();
  }

  void updateConfig({
    String? cameraId,
    int? imageWidth,
    int? imageHeight,
  }) {
    _config = _config.copyWith(
      cameraId: cameraId,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    _isDirty = true;
    notifyListeners();
  }

  void addZone() {
    final index = _config.allowedZones.length;
    final zone = RoiPolygon(
      id: 'zone_${index + 1}',
      name: 'new_zone_${index + 1}',
      enabled: true,
      points: [
        RoiPoint(x: _config.imageWidth * 0.1, y: _config.imageHeight * 0.1),
        RoiPoint(x: _config.imageWidth * 0.9, y: _config.imageHeight * 0.1),
        RoiPoint(x: _config.imageWidth * 0.9, y: _config.imageHeight * 0.9),
        RoiPoint(x: _config.imageWidth * 0.1, y: _config.imageHeight * 0.9),
      ],
    );
    _config.allowedZones.add(zone);
    _selectedZoneIndex = index;
    _isDirty = true;
    notifyListeners();
  }

  void removeZone(int index) {
    if (index < 0 || index >= _config.allowedZones.length) return;
    _config.allowedZones.removeAt(index);
    if (_selectedZoneIndex >= _config.allowedZones.length) {
      _selectedZoneIndex = _config.allowedZones.length - 1;
    }
    _isDirty = true;
    notifyListeners();
  }

  void toggleZoneEnabled(int index) {
    if (index < 0 || index >= _config.allowedZones.length) return;
    _config.allowedZones[index].enabled = !_config.allowedZones[index].enabled;
    _isDirty = true;
    notifyListeners();
  }

  void updateZone(int index, {String? id, String? name, bool? enabled}) {
    if (index < 0 || index >= _config.allowedZones.length) return;
    final zone = _config.allowedZones[index];
    if (id != null) zone.id = id;
    if (name != null) zone.name = name;
    if (enabled != null) zone.enabled = enabled;
    _isDirty = true;
    notifyListeners();
  }

  void updatePoint(int zoneIndex, int pointIndex, double x, double y) {
    if (zoneIndex < 0 || zoneIndex >= _config.allowedZones.length) return;
    final zone = _config.allowedZones[zoneIndex];
    if (pointIndex < 0 || pointIndex >= zone.points.length) return;
    zone.points[pointIndex] = RoiPoint(x: x, y: y);
    _isDirty = true;
    notifyListeners();
  }

  void addPoint(int zoneIndex, RoiPoint point) {
    if (zoneIndex < 0 || zoneIndex >= _config.allowedZones.length) return;
    _config.allowedZones[zoneIndex].points.add(point);
    _isDirty = true;
    notifyListeners();
  }

  void removePoint(int zoneIndex, int pointIndex) {
    if (zoneIndex < 0 || zoneIndex >= _config.allowedZones.length) return;
    final zone = _config.allowedZones[zoneIndex];
    if (pointIndex < 0 || pointIndex >= zone.points.length) return;
    zone.points.removeAt(pointIndex);
    _isDirty = true;
    notifyListeners();
  }

  Future<void> tryLoadDefault() async {
    final candidates = [
      '/mnt/d/workspace-windows/catcheye-guard/models/roi_cam_default.json',
    ];
    for (final path in candidates) {
      if (await File(path).exists()) {
        await loadFromFile(path);
        return;
      }
    }
  }
}
