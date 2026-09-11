import 'api_http_client.dart';

import '../models/app_settings.dart';

class CameraIntrinsics {
  final Map<String, dynamic> raw;

  const CameraIntrinsics({required this.raw});

  factory CameraIntrinsics.fromJson(Map<String, dynamic> json) {
    return CameraIntrinsics(raw: Map.unmodifiable(json));
  }

  String get cameraPath => _stringValue('camera_path');
  int get width => _intValue('width');
  int get height => _intValue('height');
  double get fx => _doubleValue('fx');
  double get fy => _doubleValue('fy');
  double get cx => _doubleValue('cx');
  double get cy => _doubleValue('cy');
  String get distortionModel => _stringValue('distortion_model');

  String _stringValue(String key) =>
      raw[key] is String ? raw[key] as String : '';
  int _intValue(String key) => raw[key] is num ? (raw[key] as num).toInt() : 0;
  double _doubleValue(String key) =>
      raw[key] is num ? (raw[key] as num).toDouble() : 0.0;
}

class CameraExtrinsics {
  final Map<String, dynamic> raw;

  const CameraExtrinsics({required this.raw});

  factory CameraExtrinsics.fromJson(Map<String, dynamic> json) {
    return CameraExtrinsics(raw: Map.unmodifiable(json));
  }

  String get cameraPath => _stringValue('camera_path');
  String get robotBasePath => _stringValue('robot_base_path');

  List<List<double>> get robotFromCameraOptical {
    final columnVector = raw['column_vector'];
    if (columnVector is! Map<String, dynamic>) return const [];
    final matrix = columnVector['robot_from_camera_optical'];
    if (matrix is! List) return const [];
    return [
      for (final row in matrix)
        if (row is List)
          [
            for (final value in row)
              if (value is num) value.toDouble(),
          ],
    ];
  }

  String _stringValue(String key) =>
      raw[key] is String ? raw[key] as String : '';
}

class RemotePickApiService {
  RemotePickApiService({ApiHttpClient? client})
    : _client = client ?? ApiHttpClient();
  final ApiHttpClient _client;
  void close() => _client.close();

  Future<CameraIntrinsics> fetchCameraIntrinsics(AppSettings settings) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('camera/intrinsics'),
    );
    return CameraIntrinsics.fromJson(json);
  }

  Future<CameraExtrinsics> fetchCameraExtrinsics(AppSettings settings) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('camera/extrinsics'),
    );
    return CameraExtrinsics.fromJson(json);
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    Uri uri, {
    Object? body,
    Set<int> expectedStatusCodes = const {200},
  }) => _client.requestJson(
    method,
    uri,
    body: body,
    expectedStatusCodes: expectedStatusCodes,
    allowEmpty: false,
  );
}
