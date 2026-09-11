import 'api_http_client.dart';

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
  RemoteRecordingApiService({ApiHttpClient? client})
    : _client = client ?? ApiHttpClient();
  final ApiHttpClient _client;
  void close() => _client.close();

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
