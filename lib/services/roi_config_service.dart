import 'dart:convert';
import 'dart:io';

import '../models/roi_config.dart';

class RoiConfigService {
  static Future<CameraRoiConfig> loadFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('ROI config file not found', path);
    }
    final content = await file.readAsString();
    return fromJsonString(content);
  }

  static CameraRoiConfig fromJsonString(String jsonText) {
    final Map<String, dynamic> json = jsonDecode(jsonText);
    return CameraRoiConfig.fromJson(json);
  }
}
