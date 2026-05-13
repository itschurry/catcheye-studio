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
  final double u;
  final double v;

  const RgbCubeEyeOffset({required this.u, required this.v});

  factory RgbCubeEyeOffset.fromJson(Map<String, dynamic> json) {
    return RgbCubeEyeOffset(
      u: (json['u'] as num).toDouble(),
      v: (json['v'] as num).toDouble(),
    );
  }
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
      body: {'u': offset.u, 'v': offset.v},
    );
    return RgbCubeEyeOffset.fromJson(json);
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
