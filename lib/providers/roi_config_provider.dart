import 'dart:io';

import 'package:flutter/material.dart';

import '../models/roi_config.dart';
import '../services/roi_config_service.dart';

class _RoiConfigState {
  CameraRoiConfig config;
  String? filePath;
  bool isDirty;
  int selectedZoneIndex;
  String? errorMessage;

  _RoiConfigState({required this.config})
    : filePath = null,
      isDirty = false,
      selectedZoneIndex = -1,
      errorMessage = null;

  factory _RoiConfigState.initial() {
    return _RoiConfigState(config: CameraRoiConfig.defaultConfig());
  }
}

class RoiConfigProvider extends ChangeNotifier {
  final Map<RoiConfigKind, _RoiConfigState> _states = {
    for (final kind in RoiConfigKind.values) kind: _RoiConfigState.initial(),
  };
  RoiConfigKind _selectedKind = RoiConfigKind.person;

  _RoiConfigState get _state => _states[_selectedKind]!;

  RoiConfigKind get selectedKind => _selectedKind;
  CameraRoiConfig get config => _state.config;
  String? get filePath => _state.filePath;
  bool get isDirty => _state.isDirty;
  int get selectedZoneIndex => _state.selectedZoneIndex;
  String? get errorMessage => _state.errorMessage;

  void selectKind(RoiConfigKind kind) {
    if (_selectedKind == kind) return;
    _selectedKind = kind;
    notifyListeners();
  }

  void selectZone(int index) {
    _state.selectedZoneIndex = index;
    notifyListeners();
  }

  RoiPolygon? get selectedZone {
    if (_state.selectedZoneIndex >= 0 &&
        _state.selectedZoneIndex < _state.config.allowedZones.length) {
      return _state.config.allowedZones[_state.selectedZoneIndex];
    }
    return null;
  }

  Future<void> loadFromFile(String path, {RoiConfigKind? kind}) async {
    try {
      final config = await RoiConfigService.loadFromFile(path);
      loadFromConfig(config, sourceLabel: path, kind: kind);
    } catch (e) {
      _state.errorMessage = 'Load failed: $e';
      notifyListeners();
    }
  }

  void loadFromConfig(
    CameraRoiConfig config, {
    String? sourceLabel,
    RoiConfigKind? kind,
  }) {
    final state = _states[kind ?? _selectedKind]!;
    state.config = config;
    state.filePath = sourceLabel;
    state.isDirty = false;
    state.errorMessage = null;
    state.selectedZoneIndex = state.config.allowedZones.isNotEmpty ? 0 : -1;
    notifyListeners();
  }

  /// Updates image dimensions and scales existing points proportionally.
  /// Does not mark the config as dirty — this is auto-detected from the stream.
  void syncImageSize(int width, int height) {
    if (width <= 0 || height <= 0) return;
    if (_state.config.imageWidth == width &&
        _state.config.imageHeight == height) {
      return;
    }

    final scaleX = _state.config.imageWidth > 0
        ? width / _state.config.imageWidth
        : 1.0;
    final scaleY = _state.config.imageHeight > 0
        ? height / _state.config.imageHeight
        : 1.0;

    final scaledZones = _state.config.allowedZones.map((zone) {
      return zone.copyWith(
        points: zone.points
            .map((p) => RoiPoint(x: p.x * scaleX, y: p.y * scaleY))
            .toList(),
      );
    }).toList();

    _state.config = _state.config.copyWith(
      imageWidth: width,
      imageHeight: height,
      allowedZones: scaledZones,
    );
    notifyListeners();
  }

  void updateConfig({String? cameraId, int? imageWidth, int? imageHeight}) {
    _state.config = _state.config.copyWith(
      cameraId: cameraId,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    _state.isDirty = true;
    notifyListeners();
  }

  void addZone() {
    final index = _state.config.allowedZones.length;
    final zone = RoiPolygon(
      id: 'zone_${index + 1}',
      name: 'new_zone_${index + 1}',
      enabled: true,
      points: [
        RoiPoint(
          x: _state.config.imageWidth * 0.1,
          y: _state.config.imageHeight * 0.1,
        ),
        RoiPoint(
          x: _state.config.imageWidth * 0.9,
          y: _state.config.imageHeight * 0.1,
        ),
        RoiPoint(
          x: _state.config.imageWidth * 0.9,
          y: _state.config.imageHeight * 0.9,
        ),
        RoiPoint(
          x: _state.config.imageWidth * 0.1,
          y: _state.config.imageHeight * 0.9,
        ),
      ],
    );
    _state.config.allowedZones.add(zone);
    _state.selectedZoneIndex = index;
    _state.isDirty = true;
    notifyListeners();
  }

  void removeZone(int index) {
    if (index < 0 || index >= _state.config.allowedZones.length) return;
    _state.config.allowedZones.removeAt(index);
    if (_state.selectedZoneIndex >= _state.config.allowedZones.length) {
      _state.selectedZoneIndex = _state.config.allowedZones.length - 1;
    }
    _state.isDirty = true;
    notifyListeners();
  }

  void toggleZoneEnabled(int index) {
    if (index < 0 || index >= _state.config.allowedZones.length) return;
    _state.config.allowedZones[index].enabled =
        !_state.config.allowedZones[index].enabled;
    _state.isDirty = true;
    notifyListeners();
  }

  void updateZone(int index, {String? id, String? name, bool? enabled}) {
    if (index < 0 || index >= _state.config.allowedZones.length) return;
    final zone = _state.config.allowedZones[index];
    if (id != null) zone.id = id;
    if (name != null) zone.name = name;
    if (enabled != null) zone.enabled = enabled;
    _state.isDirty = true;
    notifyListeners();
  }

  void updatePoint(int zoneIndex, int pointIndex, double x, double y) {
    if (zoneIndex < 0 || zoneIndex >= _state.config.allowedZones.length) return;
    final zone = _state.config.allowedZones[zoneIndex];
    if (pointIndex < 0 || pointIndex >= zone.points.length) return;
    zone.points[pointIndex] = RoiPoint(x: x, y: y);
    _state.isDirty = true;
    notifyListeners();
  }

  void addPoint(int zoneIndex, RoiPoint point) {
    if (zoneIndex < 0 || zoneIndex >= _state.config.allowedZones.length) return;
    _state.config.allowedZones[zoneIndex].points.add(point);
    _state.isDirty = true;
    notifyListeners();
  }

  void removePoint(int zoneIndex, int pointIndex) {
    if (zoneIndex < 0 || zoneIndex >= _state.config.allowedZones.length) return;
    final zone = _state.config.allowedZones[zoneIndex];
    if (pointIndex < 0 || pointIndex >= zone.points.length) return;
    zone.points.removeAt(pointIndex);
    _state.isDirty = true;
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
