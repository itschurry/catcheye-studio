import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';

class CubeEyeProperties {
  final int framerate;
  final bool autoExposure;
  final bool illumination;
  final int depthRangeMin;
  final int depthRangeMax;

  const CubeEyeProperties({
    required this.framerate,
    required this.autoExposure,
    required this.illumination,
    required this.depthRangeMin,
    required this.depthRangeMax,
  });

  factory CubeEyeProperties.fromJson(Map<String, dynamic> json) {
    return CubeEyeProperties(
      framerate: (json['framerate'] as num).toInt(),
      autoExposure: json['auto_exposure'] as bool,
      illumination: json['illumination'] as bool,
      depthRangeMin: (json['depth_range_min'] as num).toInt(),
      depthRangeMax: (json['depth_range_max'] as num).toInt(),
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
