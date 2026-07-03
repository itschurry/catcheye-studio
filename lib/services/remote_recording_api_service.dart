import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';

enum RemoteRecordingState { idle, recording, paused }

class RemoteRecordingStatus {
  const RemoteRecordingStatus({
    required this.state,
    required this.activePath,
    required this.savedPath,
    required this.error,
    required this.writtenFrames,
  });

  final RemoteRecordingState state;
  final String activePath;
  final String savedPath;
  final String error;
  final int writtenFrames;

  factory RemoteRecordingStatus.fromJson(Map<String, dynamic> json) {
    return RemoteRecordingStatus(
      state: switch (json['state'] as String? ?? 'idle') {
        'recording' => RemoteRecordingState.recording,
        'paused' => RemoteRecordingState.paused,
        _ => RemoteRecordingState.idle,
      },
      activePath: json['active_path'] as String? ?? '',
      savedPath: json['saved_path'] as String? ?? '',
      error: json['error'] as String? ?? '',
      writtenFrames: json['written_frames'] as int? ?? 0,
    );
  }
}

class RemoteRecordingApiService {
  final HttpClient _client = HttpClient();

  Future<RemoteRecordingStatus> fetchStatus(AppSettings settings) async {
    final json = await _requestJson('GET', settings.buildApiUri('recording'));
    return RemoteRecordingStatus.fromJson(json);
  }

  Future<RemoteRecordingStatus> start(AppSettings settings) {
    return _recordingAction(settings, 'start');
  }

  Future<RemoteRecordingStatus> pause(AppSettings settings) {
    return _recordingAction(settings, 'pause');
  }

  Future<RemoteRecordingStatus> resume(AppSettings settings) {
    return _recordingAction(settings, 'resume');
  }

  Future<RemoteRecordingStatus> save(AppSettings settings) {
    return _recordingAction(settings, 'save');
  }

  Future<RemoteRecordingStatus> cancel(AppSettings settings) {
    return _recordingAction(settings, 'cancel');
  }

  Future<RemoteRecordingStatus> _recordingAction(
    AppSettings settings,
    String action,
  ) async {
    final json = await _requestJson(
      'POST',
      settings.buildApiUri('recording/$action'),
    );
    return RemoteRecordingStatus.fromJson(json);
  }

  Future<Map<String, dynamic>> _requestJson(String method, Uri uri) async {
    final request = await _client.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.contentLength = 0;

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
