import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/roi_config.dart';
import 'roi_config_service.dart';

class RemoteGuardApiService {
  final HttpClient _client = HttpClient();

  Future<CameraRoiConfig> fetchRoi(
    AppSettings settings, {
    RoiConfigKind kind = RoiConfigKind.person,
  }) async {
    final json = await _requestJson('GET', settings.buildApiUri(kind.endpoint));
    return RoiConfigService.fromJsonString(jsonEncode(json));
  }

  Future<void> pushRoi(
    AppSettings settings,
    CameraRoiConfig config, {
    RoiConfigKind kind = RoiConfigKind.person,
  }) async {
    await _requestJson(
      'PUT',
      settings.buildApiUri(kind.endpoint),
      body: config.toJson(),
      expectedStatusCodes: const {200, 204},
    );
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    Uri uri, {
    Object? body,
    Set<int> expectedStatusCodes = const {200},
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
    if (!expectedStatusCodes.contains(response.statusCode)) {
      final errorBody = responseBody.isEmpty
          ? response.reasonPhrase
          : responseBody;
      throw HttpException(
        'Request failed (${response.statusCode}) for $uri: $errorBody',
        uri: uri,
      );
    }

    if (responseBody.isEmpty) {
      return const <String, dynamic>{};
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON object response expected');
    }
    return decoded;
  }
}
