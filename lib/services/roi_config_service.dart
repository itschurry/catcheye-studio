import 'dart:convert';
import 'dart:io';

import '../models/roi_config.dart';

class RoiConfigService {
  static Future<CameraRoiConfig> loadFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('ROI 설정 파일을 찾을 수 없습니다', path);
    }
    final content = await file.readAsString();
    return fromJsonString(content);
  }

  static CameraRoiConfig fromJsonString(String jsonText) {
    final Map<String, dynamic> json = jsonDecode(jsonText);
    return CameraRoiConfig.fromJson(json);
  }
}
