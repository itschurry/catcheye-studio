import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';

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
  String toString() =>
      'RemoteCaptureApiException: $method $uri failed ($statusCode): $message';
}

class StationCaptureSelector {
  final String? group;
  final String? inspectionId;

  const StationCaptureSelector._({this.group, this.inspectionId});

  const StationCaptureSelector.all() : this._();

  factory StationCaptureSelector.group(String group) {
    final value = group.trim();
    if (value.isEmpty) {
      throw const FormatException('group must not be empty');
    }
    return StationCaptureSelector._(group: value);
  }

  factory StationCaptureSelector.inspection(String inspectionId) {
    final value = inspectionId.trim();
    if (value.isEmpty) {
      throw const FormatException('inspection_id must not be empty');
    }
    return StationCaptureSelector._(inspectionId: value);
  }

  Map<String, String> toJson() => {
    'group': ?group,
    'inspection_id': ?inspectionId,
  };
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

class StationCameraStatus {
  final bool open;
  final int frameSequence;
  final String lastError;

  const StationCameraStatus({
    required this.open,
    required this.frameSequence,
    required this.lastError,
  });

  factory StationCameraStatus.fromJson(Map<String, dynamic> json) {
    return StationCameraStatus(
      open: _requiredBool(json, 'open'),
      frameSequence: _optionalInt(json, 'frame_sequence') ?? 0,
      lastError: _optionalString(json, 'last_error'),
    );
  }
}

class StationCaptureStatus {
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

  factory StationCaptureStatus.fromJson(Map<String, dynamic> json) {
    final rawGroups = json['groups'];
    if (rawGroups is! Map) {
      throw const FormatException('groups object expected');
    }
    final groups = <String, List<String>>{};
    for (final entry in rawGroups.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('invalid station group');
      }
      final inspectionIds = <String>[];
      for (final value in entry.value as List) {
        if (value is! String) {
          throw const FormatException('inspection ID string expected');
        }
        inspectionIds.add(value);
      }
      groups[entry.key as String] = List.unmodifiable(inspectionIds);
    }

    final rawCameras = json['cameras'];
    if (rawCameras is! Map) {
      throw const FormatException('cameras object expected');
    }
    final cameras = <String, StationCameraStatus>{};
    for (final entry in rawCameras.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('invalid station camera');
      }
      cameras[entry.key as String] = StationCameraStatus.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    final rawLastResult = json['last_result'];
    if (rawLastResult != null && rawLastResult is! Map) {
      throw const FormatException('last_result object expected');
    }

    return StationCaptureStatus(
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
      throw const FormatException('camera string list expected');
    }
    final rawCameraIds = json['camera_ids'];
    if (rawCameraIds != null &&
        (rawCameraIds is! List ||
            rawCameraIds.any((value) => value is! String))) {
      throw const FormatException('camera_ids string list expected');
    }
    final cameraIds = rawCameraIds is List
        ? rawCameraIds.cast<String>()
        : <String>[
            if (_optionalString(json, 'camera_id').isNotEmpty)
              _optionalString(json, 'camera_id'),
          ];
    if (cameraIds.length != cameraIds.toSet().length ||
        cameraIds.any((cameraId) => cameraId.isEmpty)) {
      throw const FormatException('camera_ids must be unique and nonempty');
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
      _ => throw FormatException('unsupported station cycle state: $value'),
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
  });

  factory StationInspectionResult.fromJson(Map<String, dynamic> json) {
    final detections = json['detections'];
    if (detections != null && detections is! List) {
      throw const FormatException('detections list expected');
    }
    final measurements = json['measurements'];
    if (measurements != null && measurements is! Map) {
      throw const FormatException('measurements object expected');
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
      error: 'Result expired, was evicted, or the runtime restarted',
      rawJson: const {},
    );
  }

  factory StationCaptureResult.fromJson(Map<String, dynamic> json) {
    final cycleId = _requiredString(json, 'cycle_id');
    final state = StationCycleState.parse(_requiredString(json, 'state'));
    final rawInspections = json['inspections'];
    if (rawInspections != null && rawInspections is! Map) {
      throw const FormatException('inspections object expected');
    }
    final inspections = <String, StationInspectionResult>{};
    if (rawInspections is Map) {
      for (final entry in rawInspections.entries) {
        if (entry.key is! String || entry.value is! Map) {
          throw const FormatException('invalid inspection result');
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
      throw const FormatException('inspection_ids string list expected');
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

class RemoteCaptureApiService {
  RemoteCaptureApiService({
    Duration requestTimeout = const Duration(seconds: 10),
  }) : _requestTimeout = requestTimeout;

  final HttpClient _client = HttpClient();
  final Duration _requestTimeout;

  void close() => _client.close(force: true);

  Future<void> requestCapture(AppSettings settings) async {
    await _requestJson('POST', settings.buildApiUri('capture/request'));
  }

  Future<StationCaptureAccepted> requestStationCapture(
    AppSettings settings, {
    StationCaptureSelector selector = const StationCaptureSelector.all(),
  }) async {
    final json = await _requestJson(
      'POST',
      settings.buildApiUri('capture/request'),
      body: selector.toJson(),
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
    if (id.isEmpty) throw const FormatException('cycle_id must not be empty');
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('capture/results/${Uri.encodeComponent(id)}'),
    );
    return StationCaptureResult.fromJson(json);
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
      throw const FormatException(
        'camera_ids must contain up to four unique camera IDs',
      );
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
      throw const FormatException(
        'station runtime did not retain the multi-stream camera selection',
      );
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
        throw const FormatException('JSON object response expected');
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
  if (value is! String) throw FormatException('$key string expected');
  return value;
}

String _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return '';
  if (value is! String) throw FormatException('$key string expected');
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key bool expected');
  return value;
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num) throw FormatException('$key number expected');
  return value.toInt();
}

double? _optionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num) throw FormatException('$key number expected');
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
