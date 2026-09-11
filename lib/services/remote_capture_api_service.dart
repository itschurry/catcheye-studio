import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/app_settings.dart';
import 'remote_capture_image_api_service.dart';

class RemoteCaptureApiException implements Exception {
  final String method;
  final Uri uri;
  final int statusCode;
  final String message;

  const RemoteCaptureApiException({
    required this.method,
    required this.uri,
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => '촬영 API 오류: $method $uri ($statusCode): $message';
}

enum StationCaptureTarget {
  boltHead('bolt-head', '볼트 머리'),
  stud('stud', '스터드'),
  nut('nut', '너트'),
  nutHole('nut-hole', '너트 홀'),
  all('all', '전체 카메라');

  const StationCaptureTarget(this.path, this.label);

  final String path;
  final String label;
}

class StationCaptureAccepted {
  final bool accepted;
  final String cycleId;
  final String error;

  const StationCaptureAccepted({
    required this.accepted,
    required this.cycleId,
    required this.error,
  });

  factory StationCaptureAccepted.fromJson(Map<String, dynamic> json) {
    return StationCaptureAccepted(
      accepted: _requiredBool(json, 'accepted'),
      cycleId: _requiredString(json, 'cycle_id'),
      error: _optionalString(json, 'error'),
    );
  }
}

class StationUndistortion {
  final String cameraId;
  final bool enabled;
  final bool calibrationAvailable;
  final int imageGeneration;
  final bool persistent;

  const StationUndistortion({
    required this.cameraId,
    required this.enabled,
    required this.calibrationAvailable,
    required this.imageGeneration,
    required this.persistent,
  });

  factory StationUndistortion.fromJson(Map<String, dynamic> json) {
    final generation = json['image_generation'];
    if (generation is! int || generation < 0) {
      throw const FormatException('image_generation은 0 이상의 정수여야 해');
    }
    return StationUndistortion(
      cameraId: _requiredString(json, 'camera_id'),
      enabled: _requiredBool(json, 'enabled'),
      calibrationAvailable: _requiredBool(json, 'calibration_available'),
      imageGeneration: generation,
      persistent: _requiredBool(json, 'persistent'),
    );
  }
}

class StationCameraStatus {
  final bool open;
  final int frameSequence;
  final bool? undistortionEnabled;
  final String lastError;

  const StationCameraStatus({
    required this.open,
    required this.frameSequence,
    this.undistortionEnabled,
    required this.lastError,
  });

  factory StationCameraStatus.fromJson(Map<String, dynamic> json) {
    return StationCameraStatus(
      open: _requiredBool(json, 'open'),
      undistortionEnabled: json.containsKey('undistortion_enabled')
          ? _requiredBool(json, 'undistortion_enabled')
          : null,
      frameSequence: _optionalInt(json, 'frame_sequence') ?? 0,
      lastError: _optionalString(json, 'last_error'),
    );
  }
}

class StationCaptureStatus {
  static const supportedSetIds = {'fastener', 'bolt_stud', 'nut'};

  final String setId;
  final bool productionActive;
  final bool ready;
  final bool busy;
  final int pendingCount;
  final int maxPendingCaptures;
  final String activeCycleId;
  final int captureCount;
  final Map<String, List<String>> groups;
  final Map<String, StationCameraStatus> cameras;
  final Map<String, dynamic>? lastResult;
  final String lastError;

  const StationCaptureStatus({
    required this.setId,
    this.productionActive = false,
    required this.ready,
    required this.busy,
    required this.pendingCount,
    required this.maxPendingCaptures,
    required this.activeCycleId,
    required this.captureCount,
    required this.groups,
    required this.cameras,
    required this.lastResult,
    required this.lastError,
  });

  List<StationCaptureTarget> get captureTargets => switch (setId) {
    'fastener' => const [
      StationCaptureTarget.boltHead,
      StationCaptureTarget.stud,
      StationCaptureTarget.nut,
      StationCaptureTarget.nutHole,
    ],
    'bolt_stud' || 'nut' => const [StationCaptureTarget.all],
    _ => throw StateError('지원하지 않는 검사 구성 set_id: $setId'),
  };

  factory StationCaptureStatus.fromJson(Map<String, dynamic> json) {
    final rawGroups = json['groups'];
    if (rawGroups is! Map) {
      throw const FormatException('groups 객체가 필요해');
    }
    final groups = <String, List<String>>{};
    for (final entry in rawGroups.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('검사 그룹이 올바르지 않아');
      }
      final inspectionIds = <String>[];
      for (final value in entry.value as List) {
        if (value is! String) {
          throw const FormatException('검사 ID 문자열이 필요해');
        }
        inspectionIds.add(value);
      }
      groups[entry.key as String] = List.unmodifiable(inspectionIds);
    }

    final rawCameras = json['cameras'];
    if (rawCameras is! Map) {
      throw const FormatException('cameras 객체가 필요해');
    }
    final cameras = <String, StationCameraStatus>{};
    for (final entry in rawCameras.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('검사 카메라 정보가 올바르지 않아');
      }
      cameras[entry.key as String] = StationCameraStatus.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    final rawLastResult = json['last_result'];
    if (rawLastResult != null && rawLastResult is! Map) {
      throw const FormatException('last_result 객체가 필요해');
    }

    final setId = _requiredString(json, 'set_id');
    if (setId.isEmpty) throw const FormatException('set_id가 비어 있으면 안 돼');
    if (!supportedSetIds.contains(setId)) {
      throw FormatException('지원하지 않는 검사 구성 set_id: $setId');
    }
    if (setId == 'fastener' && json['capture_api_version'] != 2) {
      throw const FormatException(
        '독립 검사 API v2가 필요해. Inspect와 Studio를 함께 업데이트해.',
      );
    }
    return StationCaptureStatus(
      setId: setId,
      productionActive: setId == 'fastener'
          ? _requiredBool(json, 'production_active')
          : false,
      ready: _requiredBool(json, 'ready'),
      busy: _requiredBool(json, 'busy'),
      pendingCount: _optionalInt(json, 'pending_count') ?? 0,
      maxPendingCaptures: _optionalInt(json, 'max_pending_captures') ?? 0,
      activeCycleId: _optionalString(json, 'active_cycle_id'),
      captureCount: _optionalInt(json, 'capture_count') ?? 0,
      groups: Map.unmodifiable(groups),
      cameras: Map.unmodifiable(cameras),
      lastResult: rawLastResult == null
          ? null
          : Map.unmodifiable(Map<String, dynamic>.from(rawLastResult as Map)),
      lastError: _optionalString(json, 'last_error'),
    );
  }
}

class StationViewerSource {
  final List<String> cameraIds;
  final List<String> cameras;

  const StationViewerSource({required this.cameraIds, required this.cameras});

  String get cameraId => cameraIds.isEmpty ? '' : cameraIds.first;

  factory StationViewerSource.fromJson(Map<String, dynamic> json) {
    final rawCameras = json['cameras'];
    if (rawCameras is! List || rawCameras.any((value) => value is! String)) {
      throw const FormatException('카메라 문자열 목록이 필요해');
    }
    final rawCameraIds = json['camera_ids'];
    if (rawCameraIds != null &&
        (rawCameraIds is! List ||
            rawCameraIds.any((value) => value is! String))) {
      throw const FormatException('camera_ids 문자열 목록이 필요해');
    }
    final cameraIds = rawCameraIds is List
        ? rawCameraIds.cast<String>()
        : <String>[
            if (_optionalString(json, 'camera_id').isNotEmpty)
              _optionalString(json, 'camera_id'),
          ];
    if (cameraIds.length != cameraIds.toSet().length ||
        cameraIds.any((cameraId) => cameraId.isEmpty)) {
      throw const FormatException('camera_ids는 중복되거나 비어 있으면 안 돼');
    }
    return StationViewerSource(
      cameraIds: List.unmodifiable(cameraIds),
      cameras: List.unmodifiable(rawCameras.cast<String>()),
    );
  }
}

enum StationCycleState {
  queued,
  running,
  completed,
  cancelled,
  expired;

  bool get isFinal => this == completed || this == cancelled || this == expired;

  static StationCycleState parse(String value) {
    return switch (value) {
      'QUEUED' => StationCycleState.queued,
      'RUNNING' => StationCycleState.running,
      'COMPLETED' => StationCycleState.completed,
      'CANCELLED' => StationCycleState.cancelled,
      _ => throw FormatException('지원하지 않는 검사 상태: $value'),
    };
  }
}

class StationInspectionResult {
  final String inspectionId;
  final String cameraId;
  final String cameraSerial;
  final double? sourceTimestampMs;
  final String status;
  final String reason;
  final double? latencyMs;
  final List<dynamic> detections;
  final Map<String, dynamic> measurements;
  final List<String> failedMetrics;
  final Map<String, String> artifacts;
  final String artifactError;

  const StationInspectionResult({
    required this.inspectionId,
    required this.cameraId,
    required this.cameraSerial,
    required this.sourceTimestampMs,
    required this.status,
    required this.reason,
    required this.latencyMs,
    required this.detections,
    required this.measurements,
    required this.failedMetrics,
    this.artifacts = const {},
    this.artifactError = '',
  });

  factory StationInspectionResult.fromJson(Map<String, dynamic> json) {
    final rawArtifacts = json['artifacts'];
    if (rawArtifacts != null &&
        (rawArtifacts is! Map ||
            rawArtifacts.entries.any(
              (entry) => entry.key is! String || entry.value is! String,
            ))) {
      throw const FormatException('검사 artifacts에 문자열 맵이 필요해');
    }
    final detections = json['detections'];
    if (detections != null && detections is! List) {
      throw const FormatException('detections 목록이 필요해');
    }
    final measurements = json['measurements'];
    if (measurements != null && measurements is! Map) {
      throw const FormatException('measurements 객체가 필요해');
    }
    final rawFailedMetrics = measurements is Map
        ? measurements['failed_metrics']
        : null;
    final failedMetrics = rawFailedMetrics is List
        ? rawFailedMetrics.whereType<String>().toList(growable: false)
        : const <String>[];
    return StationInspectionResult(
      inspectionId: _requiredString(json, 'inspection_id'),
      cameraId: _optionalString(json, 'camera_id'),
      cameraSerial: _optionalString(json, 'camera_serial'),
      sourceTimestampMs: _optionalDouble(json, 'source_timestamp_ms'),
      status: _optionalString(json, 'status'),
      reason: _optionalString(json, 'reason'),
      latencyMs: _optionalDouble(json, 'latency_ms'),
      detections: List.unmodifiable(detections as List? ?? const []),
      measurements: Map.unmodifiable(
        measurements == null
            ? const <String, dynamic>{}
            : Map<String, dynamic>.from(measurements as Map),
      ),
      failedMetrics: List.unmodifiable(failedMetrics),
      artifacts: Map.unmodifiable(
        rawArtifacts == null
            ? <String, String>{}
            : Map<String, String>.from(rawArtifacts as Map),
      ),
      artifactError: _optionalString(json, 'artifact_error'),
    );
  }
}

class StationCaptureResult {
  final String cycleId;
  final StationCycleState state;
  final String status;
  final String setId;
  final String group;
  final List<String> inspectionIds;
  final int? requestedAtMs;
  final int? startedAtMs;
  final int? finishedAtMs;
  final Map<String, StationInspectionResult> inspections;
  final Object? artifacts;
  final String artifactError;
  final String error;
  final Map<String, dynamic> rawJson;

  const StationCaptureResult({
    required this.cycleId,
    required this.state,
    required this.status,
    required this.setId,
    required this.group,
    required this.inspectionIds,
    required this.requestedAtMs,
    required this.startedAtMs,
    required this.finishedAtMs,
    required this.inspections,
    required this.artifacts,
    required this.artifactError,
    required this.error,
    required this.rawJson,
  });

  factory StationCaptureResult.pending(String cycleId) {
    return StationCaptureResult(
      cycleId: cycleId,
      state: StationCycleState.queued,
      status: '',
      setId: '',
      group: '',
      inspectionIds: const [],
      requestedAtMs: null,
      startedAtMs: null,
      finishedAtMs: null,
      inspections: const {},
      artifacts: null,
      artifactError: '',
      error: '',
      rawJson: const {},
    );
  }

  factory StationCaptureResult.expired(String cycleId) {
    return StationCaptureResult(
      cycleId: cycleId,
      state: StationCycleState.expired,
      status: '',
      setId: '',
      group: '',
      inspectionIds: const [],
      requestedAtMs: null,
      startedAtMs: null,
      finishedAtMs: null,
      inspections: const {},
      artifacts: null,
      artifactError: '',
      error: '결과 보관 기간이 지났거나 삭제됐거나 장비가 재시작됐어',
      rawJson: const {},
    );
  }

  factory StationCaptureResult.fromJson(Map<String, dynamic> json) {
    final cycleId = _requiredString(json, 'cycle_id');
    final state = StationCycleState.parse(_requiredString(json, 'state'));
    final rawInspections = json['inspections'];
    if (rawInspections != null && rawInspections is! Map) {
      throw const FormatException('inspections 객체가 필요해');
    }
    final inspections = <String, StationInspectionResult>{};
    if (rawInspections is Map) {
      for (final entry in rawInspections.entries) {
        if (entry.key is! String || entry.value is! Map) {
          throw const FormatException('검사 결과가 올바르지 않아');
        }
        inspections[entry.key as String] = StationInspectionResult.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
    }
    final rawInspectionIds = json['inspection_ids'];
    if (rawInspectionIds != null &&
        (rawInspectionIds is! List ||
            rawInspectionIds.any((value) => value is! String))) {
      throw const FormatException('inspection_ids 문자열 목록이 필요해');
    }
    return StationCaptureResult(
      cycleId: cycleId,
      state: state,
      status:
          state == StationCycleState.completed ||
              state == StationCycleState.cancelled
          ? _optionalString(json, 'status')
          : '',
      setId: _optionalString(json, 'set_id'),
      group: _optionalString(json, 'group'),
      inspectionIds: List.unmodifiable(
        (rawInspectionIds as List?)?.cast<String>() ?? const <String>[],
      ),
      requestedAtMs: _optionalInt(json, 'requested_at_ms'),
      startedAtMs: _optionalInt(json, 'started_at_ms'),
      finishedAtMs: _optionalInt(json, 'finished_at_ms'),
      inspections: Map.unmodifiable(inspections),
      artifacts: json['artifacts'],
      artifactError: _optionalString(json, 'artifact_error'),
      error: _optionalString(json, 'error'),
      rawJson: Map.unmodifiable(Map<String, dynamic>.from(json)),
    );
  }

  bool get isEquipmentFault =>
      artifactError.isNotEmpty || status == 'EQUIPMENT_ERROR';

  String get presentationStatus {
    if (state == StationCycleState.cancelled) return 'CANCELLED';
    if (state == StationCycleState.expired) return 'EXPIRED';
    if (state != StationCycleState.completed) return state.name.toUpperCase();
    if (isEquipmentFault) return 'EQUIPMENT_ERROR';
    var aggregate = _normalizeInspectionStatus(status);
    for (final inspection in inspections.values) {
      final candidate = _normalizeInspectionStatus(inspection.status);
      if (_aggregatePriority(candidate) > _aggregatePriority(aggregate)) {
        aggregate = candidate;
      }
    }
    return aggregate.isEmpty ? 'COMPLETED' : aggregate;
  }
}

class StationCaptureResultList {
  final List<StationCaptureResult> results;

  const StationCaptureResultList({required this.results});

  factory StationCaptureResultList.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'];
    if (rawResults is! List) {
      throw const FormatException('results 목록이 필요해');
    }
    final results = <StationCaptureResult>[];
    for (final value in rawResults) {
      if (value is! Map) {
        throw const FormatException('장비 촬영 결과가 올바르지 않아');
      }
      results.add(
        StationCaptureResult.fromJson(Map<String, dynamic>.from(value)),
      );
    }
    return StationCaptureResultList(results: List.unmodifiable(results));
  }
}

class StationArchiveDates {
  const StationArchiveDates({
    required this.storage,
    required this.resultCount,
    required this.dates,
  });
  final CaptureStorageInfo storage;
  final int resultCount;
  final List<CaptureDateSummary> dates;

  factory StationArchiveDates.fromJson(Map<String, dynamic> json) {
    final parsed = CaptureDatesResponse.fromJson(json);
    if (parsed.storage == null || json['storage']['result_count'] is! int) {
      throw const FormatException('검사 저장 공간 및 결과 개수가 필요해');
    }
    if (parsed.dates.any(
          (date) => !_validArchiveDate(date.date) || date.count < 0,
        ) ||
        parsed.dates.map((date) => date.date).toSet().length !=
            parsed.dates.length) {
      throw const FormatException('검사 저장 날짜 목록이 올바르지 않아');
    }
    final dates = [...parsed.dates]..sort((a, b) => b.date.compareTo(a.date));
    return StationArchiveDates(
      storage: parsed.storage!,
      resultCount: json['storage']['result_count'] as int,
      dates: dates,
    );
  }
}

bool _validArchiveDate(String date) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return false;
  final parsed = DateTime.tryParse(date);
  return parsed != null && parsed.toIso8601String().startsWith(date);
}

class StationArchivePage {
  const StationArchivePage({
    required this.date,
    required this.results,
    this.nextCursor,
  });
  final String date;
  final List<StationCaptureResult> results;
  final String? nextCursor;

  factory StationArchivePage.fromJson(Map<String, dynamic> json) {
    final date = json['date'];
    if (date is! String || !_validArchiveDate(date)) {
      throw const FormatException('저장 결과 날짜가 올바르지 않아');
    }
    final results = StationCaptureResultList.fromJson(json).results;
    for (final result in results) {
      final path = result.rawJson['storage_path'];
      final bytes = result.rawJson['size_bytes'];
      if (path is! String ||
          !RegExp(
            r'^(bolt_stud|nut|all|bolt_head|stud|nut_hole_alignment)/\d{4}-\d{2}-\d{2}/[0-9]+-[0-9]+-[0-9]+$',
          ).hasMatch(path) ||
          path.split('/')[1] != date ||
          path.split('/').last != result.cycleId ||
          bytes is! int ||
          bytes < 0 ||
          (result.state != StationCycleState.completed &&
              result.state != StationCycleState.cancelled)) {
        throw const FormatException('저장 결과 경로 또는 파일 크기가 올바르지 않아');
      }
    }
    final cursor = json['next_cursor'];
    if (cursor != null && (cursor is! String || cursor.isEmpty)) {
      throw const FormatException('다음 페이지 커서가 올바르지 않아');
    }
    return StationArchivePage(
      date: date,
      results: results,
      nextCursor: cursor as String?,
    );
  }
}

class RemoteCaptureApiService {
  RemoteCaptureApiService({
    Duration requestTimeout = const Duration(seconds: 10),
  }) : _requestTimeout = requestTimeout;

  final HttpClient _client = HttpClient();
  final Duration _requestTimeout;

  void close() => _client.close(force: true);

  Future<void> requestCapture(AppSettings settings) async {
    await _requestJson(
      'POST',
      settings.buildApiUri(
        settings.remoteDeviceKind == RemoteDeviceKind.inspection
            ? 'capture/all'
            : 'capture/request',
      ),
    );
  }

  Future<StationCaptureAccepted> requestStationCapture(
    AppSettings settings, {
    required StationCaptureTarget target,
  }) async {
    final json = await _requestJson(
      'POST',
      settings.buildApiUri('capture/${target.path}'),
    );
    return StationCaptureAccepted.fromJson(json);
  }

  Future<StationCaptureStatus> fetchStationStatus(AppSettings settings) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('capture/status'),
    );
    return StationCaptureStatus.fromJson(json);
  }

  Future<StationCaptureResult> fetchStationResult(
    AppSettings settings,
    String cycleId,
  ) async {
    final id = cycleId.trim();
    if (id.isEmpty) throw const FormatException('cycle_id가 비어 있으면 안 돼');
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('capture/results/${Uri.encodeComponent(id)}'),
    );
    return StationCaptureResult.fromJson(json);
  }

  Future<StationCaptureResultList> fetchStationResults(
    AppSettings settings,
  ) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('capture/results'),
    );
    return StationCaptureResultList.fromJson(json);
  }

  Future<StationArchiveDates> fetchStationArchiveDates(
    AppSettings settings,
  ) async => StationArchiveDates.fromJson(
    await _requestJson('GET', settings.buildApiUri('capture/archive/dates')),
  );

  Future<StationArchivePage> fetchStationArchive(
    AppSettings settings, {
    required String date,
    int limit = 100,
    String? cursor,
  }) async {
    if (!_validArchiveDate(date) || limit < 1 || limit > 100) {
      throw const FormatException('날짜와 조회 개수(1~100)를 확인해');
    }
    final page = StationArchivePage.fromJson(
      await _requestJson(
        'GET',
        settings
            .buildApiUri('capture/archive')
            .replace(
              queryParameters: {
                'date': date,
                'limit': '$limit',
                'cursor': ?cursor,
              },
            ),
      ),
    );
    if (page.date != date) throw const FormatException('요청 날짜와 응답 날짜가 달라');
    return page;
  }

  Future<Uint8List> fetchStationImage(
    AppSettings settings, {
    required String cycleId,
    required String inspectionId,
    required String kind,
    String? storagePath,
  }) async {
    final identifier = RegExp(r'^[A-Za-z0-9_.-]+$');
    if (!identifier.hasMatch(cycleId) ||
        !identifier.hasMatch(inspectionId) ||
        (kind != 'raw' && kind != 'overlay')) {
      throw const FormatException(
        'cycle_id, inspection_id와 이미지 종류(raw/overlay)가 필요해',
      );
    }
    if (storagePath != null &&
        (!RegExp(
              r'^(bolt_stud|nut|all|bolt_head|stud|nut_hole_alignment)/\d{4}-\d{2}-\d{2}/[0-9]+-[0-9]+-[0-9]+$',
            ).hasMatch(storagePath) ||
            storagePath.split('/').last != cycleId ||
            !_validArchiveDate(storagePath.split('/')[1]))) {
      throw const FormatException('저장 이미지 경로가 요청한 검사와 일치하지 않아');
    }
    final uri = settings
        .buildApiUri(
          storagePath == null
              ? 'capture/results/${Uri.encodeComponent(cycleId)}/image'
              : 'capture/archive/$storagePath/image',
        )
        .replace(
          queryParameters: {'inspection_id': inspectionId, 'kind': kind},
        );
    HttpClientRequest? request;
    const maxBytes = 16 * 1024 * 1024;
    try {
      request = await _client.getUrl(uri).timeout(_requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'image/png');
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(_requestTimeout);
        throw RemoteCaptureApiException(
          method: 'GET',
          uri: uri,
          statusCode: response.statusCode,
          message: body.isEmpty ? response.reasonPhrase : body,
        );
      }
      if (response.headers.contentType?.mimeType != 'image/png') {
        throw const FormatException('저장된 검사 이미지는 PNG여야 해');
      }
      if (response.contentLength > maxBytes) {
        throw const FormatException('저장된 이미지가 16 MiB를 초과했어');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_requestTimeout)) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const FormatException('저장된 이미지가 16 MiB를 초과했어');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (_) {
      request?.abort();
      rethrow;
    }
  }

  Future<StationUndistortion> fetchUndistortion(
    AppSettings settings,
    String cameraId,
  ) => _undistortion(settings, cameraId, null);

  Future<StationUndistortion> setUndistortion(
    AppSettings settings,
    String cameraId,
    bool enabled,
  ) => _undistortion(settings, cameraId, enabled);

  Future<StationUndistortion> _undistortion(
    AppSettings settings,
    String cameraId,
    bool? enabled,
  ) async {
    if (cameraId.trim().isEmpty) {
      throw const FormatException('camera_id가 비어 있으면 안 돼');
    }
    final json = await _requestJson(
      enabled == null ? 'GET' : 'POST',
      settings.buildApiUri(
        'cameras/${Uri.encodeComponent(cameraId)}/undistortion',
      ),
      body: enabled == null ? null : {'enabled': enabled},
    );
    final result = StationUndistortion.fromJson(json);
    if (result.cameraId != cameraId ||
        (enabled != null && result.enabled != enabled)) {
      throw const FormatException('왜곡 보정 응답이 요청한 카메라 또는 모드와 일치하지 않아');
    }
    return result;
  }

  Future<StationViewerSource> fetchViewerSource(AppSettings settings) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('viewer/source'),
    );
    return StationViewerSource.fromJson(json);
  }

  Future<StationViewerSource> setViewerSource(
    AppSettings settings,
    String cameraId,
  ) => setViewerSources(
    settings,
    cameraId.trim().isEmpty ? const [] : [cameraId.trim()],
  );

  Future<StationViewerSource> setViewerSources(
    AppSettings settings,
    List<String> cameraIds,
  ) async {
    final normalized = cameraIds
        .map((cameraId) => cameraId.trim())
        .where((cameraId) => cameraId.isNotEmpty)
        .toList(growable: false);
    if (normalized.length > 4 ||
        normalized.length != normalized.toSet().length) {
      throw const FormatException('camera_ids에는 중복 없이 최대 4개의 카메라 ID를 지정해야 해');
    }
    final json = await _requestJson(
      'POST',
      settings.buildApiUri('viewer/source'),
      body: normalized.length <= 1
          ? {'camera_id': normalized.isEmpty ? '' : normalized.first}
          : {'camera_ids': normalized},
    );
    // The station may acknowledge the POST without repeating the discovery
    // list. Read the authoritative global selection without replaying POST.
    final source = json['cameras'] is! List
        ? await fetchViewerSource(settings)
        : StationViewerSource.fromJson(json);
    if (normalized.length > 1 && !normalized.every(source.cameraIds.contains)) {
      throw const FormatException('장비가 요청한 카메라 선택을 유지하지 않았어');
    }
    return source;
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    HttpClientRequest? request;
    try {
      request = await _client.openUrl(method, uri).timeout(_requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body == null) {
        if (method == 'POST') request.headers.contentLength = 0;
      } else {
        final encoded = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.headers.contentLength = encoded.length;
        request.add(encoded);
      }

      final response = await request.close().timeout(_requestTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw RemoteCaptureApiException(
          method: method,
          uri: uri,
          statusCode: response.statusCode,
          message: responseBody.isEmpty ? response.reasonPhrase : responseBody,
        );
      }

      if (responseBody.isEmpty) return const <String, dynamic>{};
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON 객체 응답이 필요해');
      }
      return decoded;
    } on TimeoutException {
      request?.abort();
      rethrow;
    } catch (_) {
      request?.abort();
      rethrow;
    }
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key 항목에 문자열이 필요해');
  return value;
}

String _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return '';
  if (value is! String) throw FormatException('$key 항목에 문자열이 필요해');
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key 항목에 불리언 값이 필요해');
  return value;
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num) throw FormatException('$key 항목에 숫자가 필요해');
  return value.toInt();
}

double? _optionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num) throw FormatException('$key 항목에 숫자가 필요해');
  return value.toDouble();
}

String _normalizeInspectionStatus(String status) {
  return switch (status) {
    'PRESENT' => 'OK',
    'ABSENT' => 'NG',
    _ => status,
  };
}

int _aggregatePriority(String status) {
  return switch (status) {
    'EQUIPMENT_ERROR' => 4,
    'NG' => 3,
    'RECHECK' => 2,
    'OK' => 1,
    _ => 0,
  };
}
