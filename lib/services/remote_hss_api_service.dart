import 'api_http_client.dart';
import 'dart:convert';

import '../models/app_settings.dart';
import '../models/roi_config.dart';
import 'roi_config_service.dart';

class RemoteHssApiService {
  RemoteHssApiService({ApiHttpClient? client})
    : _client = client ?? ApiHttpClient();
  final ApiHttpClient _client;
  void close() => _client.close();

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
  }) => _client.requestJson(
    method,
    uri,
    body: body,
    expectedStatusCodes: expectedStatusCodes,
    allowEmpty: true,
  );
}
