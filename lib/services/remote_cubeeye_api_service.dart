import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';

class CubeEyeProperties {
  final int framerate;
  final bool autoExposure;
  final bool illumination;
  final int depthRangeMin;
  final int depthRangeMax;
  final Map<String, dynamic> values;

  const CubeEyeProperties({
    required this.framerate,
    required this.autoExposure,
    required this.illumination,
    required this.depthRangeMin,
    required this.depthRangeMax,
    required this.values,
  });

  factory CubeEyeProperties.fromJson(Map<String, dynamic> json) {
    return CubeEyeProperties(
      framerate: (json['framerate'] as num).toInt(),
      autoExposure: json['auto_exposure'] as bool,
      illumination: json['illumination'] as bool,
      depthRangeMin: (json['depth_range_min'] as num).toInt(),
      depthRangeMax: (json['depth_range_max'] as num).toInt(),
      values: Map.unmodifiable(json),
    );
  }
}

class RgbCubeEyeOffset {
  final bool rgbUndistortEnabled;
  final Map<String, double> values;

  const RgbCubeEyeOffset({
    required this.rgbUndistortEnabled,
    this.values = const {},
  });

  factory RgbCubeEyeOffset.fromJson(Map<String, dynamic> json) {
    final values = <String, double>{};
    for (final entry in json.entries) {
      if (entry.key == 'u' || entry.key == 'v') continue;
      final value = entry.value;
      if (value is num) {
        values[entry.key] = value.toDouble();
      }
    }
    return RgbCubeEyeOffset(
      rgbUndistortEnabled: json['rgb_undistort_enabled'] == true,
      values: Map.unmodifiable(values),
    );
  }

  RgbCubeEyeOffset copyWith({
    bool? rgbUndistortEnabled,
    Map<String, double>? values,
  }) {
    return RgbCubeEyeOffset(
      rgbUndistortEnabled: rgbUndistortEnabled ?? this.rgbUndistortEnabled,
      values: values ?? this.values,
    );
  }

  Map<String, Object> toJson() => {
    'rgb_undistort_enabled': rgbUndistortEnabled,
    ...values,
  };
}

class RgbCameraProperties {
  final Map<String, Object> values;

  const RgbCameraProperties({required this.values});

  factory RgbCameraProperties.fromJson(Map<String, dynamic> json) {
    final values = <String, Object>{};
    for (final entry in json.entries) {
      final value = entry.value;
      if (value is bool || value is num || value is String) {
        values[entry.key] = value as Object;
      }
    }
    return RgbCameraProperties(values: Map.unmodifiable(values));
  }
}

class RgbIntrinsicCalibration {
  final int captureCount;
  final double? rmsError;
  final Map<String, double> values;

  const RgbIntrinsicCalibration({
    required this.captureCount,
    required this.values,
    this.rmsError,
  });

  factory RgbIntrinsicCalibration.fromJson(Map<String, dynamic> json) {
    final values = <String, double>{};
    for (final entry in json.entries) {
      final value = entry.value;
      if (value is num) {
        values[entry.key] = value.toDouble();
      }
    }
    return RgbIntrinsicCalibration(
      captureCount: (json['capture_count'] as num).toInt(),
      rmsError: (json['rms_error'] as num?)?.toDouble(),
      values: Map.unmodifiable(values),
    );
  }
}

const rgbIntrinsicA4Board = <String, Object>{
  'pattern_width': 9,
  'pattern_height': 6,
  'square_size_m': 0.020,
};

class PointCloudRoiConfig {
  final bool enabled;
  final bool applyToViewer;
  final double minXM;
  final double maxXM;
  final double minYM;
  final double maxYM;
  final double minZM;
  final double maxZM;

  const PointCloudRoiConfig({
    required this.enabled,
    required this.applyToViewer,
    required this.minXM,
    required this.maxXM,
    required this.minYM,
    required this.maxYM,
    required this.minZM,
    required this.maxZM,
  });

  factory PointCloudRoiConfig.fromJson(Map<String, dynamic> json) {
    return PointCloudRoiConfig(
      enabled: json['enabled'] as bool,
      applyToViewer: json['apply_to_viewer'] as bool,
      minXM: (json['min_x_m'] as num).toDouble(),
      maxXM: (json['max_x_m'] as num).toDouble(),
      minYM: (json['min_y_m'] as num).toDouble(),
      maxYM: (json['max_y_m'] as num).toDouble(),
      minZM: (json['min_z_m'] as num).toDouble(),
      maxZM: (json['max_z_m'] as num).toDouble(),
    );
  }

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'apply_to_viewer': applyToViewer,
    'min_x_m': minXM,
    'max_x_m': maxXM,
    'min_y_m': minYM,
    'max_y_m': maxYM,
    'min_z_m': minZM,
    'max_z_m': maxZM,
  };
}

class RobotCalibration {
  final bool enabled;
  final Map<String, double> values;

  const RobotCalibration({required this.enabled, required this.values});

  factory RobotCalibration.fromJson(Map<String, dynamic> json) {
    final values = <String, double>{};
    for (final entry in json.entries) {
      if (entry.key == 'enabled') continue;
      final value = entry.value;
      if (value is num) {
        values[entry.key] = value.toDouble();
      }
    }
    return RobotCalibration(
      enabled: json['enabled'] as bool,
      values: Map.unmodifiable(values),
    );
  }

  Map<String, Object> toJson() => {'enabled': enabled, ...values};
}

class RemoteCubeEyeApiService {
  final HttpClient _client = HttpClient();

  Future<CubeEyeProperties> fetchProperties(AppSettings settings) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('cubeeye/properties'),
    );
    return CubeEyeProperties.fromJson(json);
  }

  Future<CubeEyeProperties> setProperty(
    AppSettings settings,
    String key,
    Object value,
  ) async {
    final json = await _requestJson(
      'PUT',
      settings.buildApiUri('cubeeye/properties/$key'),
      body: {'value': value},
    );
    return CubeEyeProperties.fromJson(json);
  }

  Future<RgbCubeEyeOffset> fetchRgbCubeEyeOffset(AppSettings settings) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('rgb-cubeeye-offset'),
    );
    return RgbCubeEyeOffset.fromJson(json);
  }

  Future<RgbCubeEyeOffset> setRgbCubeEyeOffset(
    AppSettings settings,
    RgbCubeEyeOffset offset,
  ) async {
    final json = await _requestJson(
      'PUT',
      settings.buildApiUri('rgb-cubeeye-offset'),
      body: offset.toJson(),
    );
    return RgbCubeEyeOffset.fromJson(json);
  }

  Future<RgbCameraProperties> fetchRgbCameraProperties(
    AppSettings settings,
  ) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('rgb-camera/properties'),
    );
    return RgbCameraProperties.fromJson(json);
  }

  Future<RgbCameraProperties> setRgbCameraProperty(
    AppSettings settings,
    String key,
    Object value,
  ) async {
    final json = await _requestJson(
      'PUT',
      settings.buildApiUri('rgb-camera/properties/$key'),
      body: {'value': value},
    );
    return RgbCameraProperties.fromJson(json);
  }

  Future<RgbIntrinsicCalibration> fetchRgbIntrinsicCalibration(
    AppSettings settings,
  ) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('rgb-camera/intrinsic-calibration'),
    );
    return RgbIntrinsicCalibration.fromJson(json);
  }

  Future<RgbIntrinsicCalibration> resetRgbIntrinsicCalibration(
    AppSettings settings,
  ) async {
    final json = await _requestJson(
      'DELETE',
      settings.buildApiUri('rgb-camera/intrinsic-calibration'),
    );
    return RgbIntrinsicCalibration.fromJson(json);
  }

  Future<RgbIntrinsicCalibration> captureRgbIntrinsicCalibration(
    AppSettings settings,
  ) async {
    final json = await _requestJson(
      'POST',
      settings.buildApiUri('rgb-camera/intrinsic-calibration/capture'),
      body: rgbIntrinsicA4Board,
    );
    return RgbIntrinsicCalibration.fromJson(json);
  }

  Future<RgbIntrinsicCalibration> solveRgbIntrinsicCalibration(
    AppSettings settings,
  ) async {
    final json = await _requestJson(
      'POST',
      settings.buildApiUri('rgb-camera/intrinsic-calibration/solve'),
      body: rgbIntrinsicA4Board,
    );
    return RgbIntrinsicCalibration.fromJson(json);
  }

  Future<PointCloudRoiConfig> fetchPointCloudRoi(AppSettings settings) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('pointcloud-roi'),
    );
    return PointCloudRoiConfig.fromJson(json);
  }

  Future<PointCloudRoiConfig> setPointCloudRoi(
    AppSettings settings,
    PointCloudRoiConfig config,
  ) async {
    final json = await _requestJson(
      'PUT',
      settings.buildApiUri('pointcloud-roi'),
      body: config.toJson(),
    );
    return PointCloudRoiConfig.fromJson(json);
  }

  Future<RobotCalibration> fetchRobotCalibration(AppSettings settings) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('robot-calibration'),
    );
    return RobotCalibration.fromJson(json);
  }

  Future<RobotCalibration> setRobotCalibration(
    AppSettings settings,
    RobotCalibration calibration,
  ) async {
    final json = await _requestJson(
      'PUT',
      settings.buildApiUri('robot-calibration'),
      body: calibration.toJson(),
    );
    return RobotCalibration.fromJson(json);
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    Uri uri, {
    Object? body,
  }) async {
    final request = await _client.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      final bodyBytes = utf8.encode(jsonEncode(body));
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);
    }

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      final errorBody = responseBody.isEmpty
          ? response.reasonPhrase
          : responseBody;
      throw HttpException(
        'Request failed (${response.statusCode}) for $uri: $errorBody',
        uri: uri,
      );
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON object response expected');
    }
    return decoded;
  }
}
