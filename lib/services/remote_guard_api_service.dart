import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/roi_config.dart';
import 'roi_config_service.dart';

enum GuardRecordingState { idle, recording, paused }

class GuardRecordingStatus {
  const GuardRecordingStatus({
    required this.state,
    required this.activePath,
    required this.savedPath,
    required this.error,
    required this.writtenFrames,
  });

  final GuardRecordingState state;
  final String activePath;
  final String savedPath;
  final String error;
  final int writtenFrames;

  factory GuardRecordingStatus.fromJson(Map<String, dynamic> json) {
    return GuardRecordingStatus(
      state: switch (json['state'] as String? ?? 'idle') {
        'recording' => GuardRecordingState.recording,
        'paused' => GuardRecordingState.paused,
        _ => GuardRecordingState.idle,
      },
      activePath: json['active_path'] as String? ?? '',
      savedPath: json['saved_path'] as String? ?? '',
      error: json['error'] as String? ?? '',
      writtenFrames: json['written_frames'] as int? ?? 0,
    );
  }
}

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

  Future<GuardRecordingStatus> fetchRecordingStatus(
    AppSettings settings,
  ) async {
    final json = await _requestJson('GET', settings.buildApiUri('recording'));
    return GuardRecordingStatus.fromJson(json);
  }

  Future<GuardRecordingStatus> startRecording(AppSettings settings) {
    return _recordingAction(settings, 'start');
  }

  Future<GuardRecordingStatus> pauseRecording(AppSettings settings) {
    return _recordingAction(settings, 'pause');
  }

  Future<GuardRecordingStatus> resumeRecording(AppSettings settings) {
    return _recordingAction(settings, 'resume');
  }

  Future<GuardRecordingStatus> saveRecording(AppSettings settings) {
    return _recordingAction(settings, 'save');
  }

  Future<GuardRecordingStatus> cancelRecording(AppSettings settings) {
    return _recordingAction(settings, 'cancel');
  }

  Future<GuardRecordingStatus> _recordingAction(
    AppSettings settings,
    String action,
  ) async {
    final json = await _requestJson(
      'POST',
      settings.buildApiUri('recording/$action'),
    );
    return GuardRecordingStatus.fromJson(json);
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
