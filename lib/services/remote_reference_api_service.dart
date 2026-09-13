import 'api_http_client.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/app_settings.dart';

class RemoteReferenceApiException implements Exception {
  const RemoteReferenceApiException({
    required this.method,
    required this.uri,
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final String method;
  final Uri uri;
  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() =>
      '기준 이미지 API 오류: $method $uri '
      '($statusCode${code.isEmpty ? '' : ', $code'}): $message';
}

class ReferenceCapabilities {
  const ReferenceCapabilities({
    required this.referenceCapture,
    required this.referenceRevisions,
    required this.modelBuild,
    required this.modelActivation,
  });

  final bool referenceCapture;
  final bool referenceRevisions;
  final bool modelBuild;
  final bool modelActivation;

  bool get hasReferenceManagement =>
      referenceCapture || referenceRevisions || modelBuild || modelActivation;

  factory ReferenceCapabilities.fromJson(Map<String, dynamic> json) {
    return ReferenceCapabilities(
      referenceCapture: _requiredBool(json, 'reference_capture'),
      referenceRevisions: _requiredBool(json, 'reference_revisions'),
      modelBuild: _requiredBool(json, 'model_build'),
      modelActivation: _requiredBool(json, 'model_activation'),
    );
  }
}

class ReferenceApiStatus {
  const ReferenceApiStatus({
    required this.apiVersion,
    required this.capabilities,
    required this.deviceState,
    required this.activeModelId,
    required this.cameraClasses,
  });

  final int apiVersion;
  final ReferenceCapabilities capabilities;
  final String deviceState;
  final String? activeModelId;
  final Map<String, List<String>> cameraClasses;

  bool get isRunning => deviceState == 'RUNNING';

  factory ReferenceApiStatus.fromJson(Map<String, dynamic> json) {
    final rawCapabilities = json['capabilities'];
    if (rawCapabilities is! Map) {
      throw const FormatException('capabilities 객체가 필요합니다');
    }
    final rawCameraClasses = json['camera_classes'];
    if (rawCameraClasses is! Map) {
      throw const FormatException('camera_classes 객체가 필요합니다');
    }
    final cameraClasses = <String, List<String>>{};
    for (final entry in rawCameraClasses.entries) {
      if (entry.key is! String ||
          entry.value is! List ||
          (entry.value as List).any((value) => value is! String)) {
        throw const FormatException('camera_classes 항목이 올바르지 않습니다');
      }
      final classes = (entry.value as List).cast<String>();
      if (classes.isEmpty ||
          classes.any((value) => value.isEmpty) ||
          classes.length != classes.toSet().length) {
        throw const FormatException('카메라 분류는 중복되거나 비어 있으면 안 됩니다');
      }
      cameraClasses[entry.key as String] = List.unmodifiable(classes);
    }
    final apiVersion = _requiredInt(json, 'api_version');
    if (apiVersion != 1) {
      throw FormatException('지원하지 않는 기준 이미지 API 버전: $apiVersion');
    }
    final deviceState = _requiredString(json, 'device_state');
    if (!const {'RUNNING', 'MAINTENANCE', 'ERROR'}.contains(deviceState)) {
      throw FormatException('지원하지 않는 장비 상태: $deviceState');
    }
    return ReferenceApiStatus(
      apiVersion: apiVersion,
      capabilities: ReferenceCapabilities.fromJson(
        Map<String, dynamic>.from(rawCapabilities),
      ),
      deviceState: deviceState,
      activeModelId: _nullableString(json, 'active_model_id'),
      cameraClasses: Map.unmodifiable(cameraClasses),
    );
  }
}

enum ReferenceCaptureState {
  queued,
  capturing,
  ready,
  failed,
  interrupted;

  bool get isFinal => this == ready || this == failed || this == interrupted;

  static ReferenceCaptureState parse(String value) => switch (value) {
    'QUEUED' => queued,
    'CAPTURING' => capturing,
    'READY' => ready,
    'FAILED' => failed,
    'INTERRUPTED' => interrupted,
    _ => throw FormatException('지원하지 않는 기준 촬영 상태: $value'),
  };
}

class ReferenceImageInfo {
  const ReferenceImageInfo({
    required this.imageId,
    required this.cameraId,
    required this.cameraSerial,
    required this.width,
    required this.height,
    required this.capturedAtMs,
    required this.sourceTimestampMs,
    required this.url,
    required this.sha256,
  });

  final String imageId;
  final String cameraId;
  final String cameraSerial;
  final int width;
  final int height;
  final int capturedAtMs;
  final num? sourceTimestampMs;
  final String url;
  final String sha256;

  factory ReferenceImageInfo.fromJson(Map<String, dynamic> json) {
    final width = _requiredInt(json, 'width');
    final height = _requiredInt(json, 'height');
    if (width <= 0 || height <= 0) {
      throw const FormatException('이미지 가로·세로 크기는 양수여야 합니다');
    }
    final url = _requiredString(json, 'url');
    if (!url.startsWith('/') || url.startsWith('//')) {
      throw const FormatException('기준 이미지 URL은 상대 경로여야 합니다');
    }
    return ReferenceImageInfo(
      imageId: _requiredString(json, 'image_id'),
      cameraId: _requiredString(json, 'camera_id'),
      cameraSerial: _optionalString(json, 'camera_serial'),
      width: width,
      height: height,
      capturedAtMs: _requiredInt(json, 'captured_at_ms'),
      sourceTimestampMs: _optionalNumber(json, 'source_timestamp_ms'),
      url: url,
      sha256: _requiredString(json, 'sha256'),
    );
  }
}

class ReferenceCapture {
  const ReferenceCapture({
    required this.captureId,
    required this.state,
    required this.image,
    required this.error,
  });

  final String captureId;
  final ReferenceCaptureState state;
  final ReferenceImageInfo? image;
  final String error;

  factory ReferenceCapture.fromJson(Map<String, dynamic> json) {
    final state = ReferenceCaptureState.parse(_requiredString(json, 'state'));
    final rawImage = json['image'];
    if (rawImage != null && rawImage is! Map) {
      throw const FormatException('image 객체가 필요합니다');
    }
    final image = rawImage == null
        ? null
        : ReferenceImageInfo.fromJson(Map<String, dynamic>.from(rawImage));
    if (state == ReferenceCaptureState.ready && image == null) {
      throw const FormatException('촬영 완료 응답에 이미지가 없습니다');
    }
    return ReferenceCapture(
      captureId: _requiredString(json, 'capture_id'),
      state: state,
      image: image,
      error: _errorMessage(json['error']),
    );
  }
}

class ReferenceBox {
  const ReferenceBox(this.x1, this.y1, this.x2, this.y2);

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  bool isValidFor(int width, int height) =>
      x1.isFinite &&
      y1.isFinite &&
      x2.isFinite &&
      y2.isFinite &&
      0 <= x1 &&
      x1 < x2 &&
      x2 <= width &&
      0 <= y1 &&
      y1 < y2 &&
      y2 <= height;

  List<num> toJson() => [x1.round(), y1.round(), x2.round(), y2.round()];

  factory ReferenceBox.fromJson(dynamic json) {
    if (json is! List || json.length != 4 || json.any((v) => v is! num)) {
      throw const FormatException('박스 좌표에는 숫자 4개가 필요합니다');
    }
    return ReferenceBox(
      (json[0] as num).toDouble(),
      (json[1] as num).toDouble(),
      (json[2] as num).toDouble(),
      (json[3] as num).toDouble(),
    );
  }
}

class ReferenceRevisionEntry {
  const ReferenceRevisionEntry({
    required this.className,
    required this.imageId,
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.boxes,
    required this.contextRatio,
  });

  final String className;
  final String imageId;
  final String imageUrl;
  final int width;
  final int height;
  final List<ReferenceBox> boxes;
  final double? contextRatio;

  factory ReferenceRevisionEntry.fromJson(Map<String, dynamic> json) {
    final rawBoxes = json['boxes'];
    if (rawBoxes is! List) throw const FormatException('boxes 목록이 필요합니다');
    return ReferenceRevisionEntry(
      className: _requiredString(json, 'class_name'),
      imageId: _requiredString(json, 'image_id'),
      imageUrl: _requiredString(json, 'image_url'),
      width: _requiredInt(json, 'width'),
      height: _requiredInt(json, 'height'),
      boxes: List.unmodifiable(rawBoxes.map(ReferenceBox.fromJson)),
      contextRatio: _optionalNumber(json, 'context_ratio')?.toDouble(),
    );
  }
}

class ReferenceRevisionSummary {
  const ReferenceRevisionSummary({
    required this.revisionId,
    required this.baseRevisionId,
    required this.createdAtMs,
  });

  final String revisionId;
  final String? baseRevisionId;
  final int createdAtMs;

  factory ReferenceRevisionSummary.fromJson(Map<String, dynamic> json) {
    return ReferenceRevisionSummary(
      revisionId: _requiredString(json, 'revision_id'),
      baseRevisionId: _nullableString(json, 'base_revision_id'),
      createdAtMs: _requiredInt(json, 'created_at_ms'),
    );
  }
}

class ReferenceRevision {
  const ReferenceRevision({
    required this.revisionId,
    required this.baseRevisionId,
    required this.createdAtMs,
    required this.entries,
  });

  final String revisionId;
  final String? baseRevisionId;
  final int createdAtMs;
  final List<ReferenceRevisionEntry> entries;

  factory ReferenceRevision.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    if (rawEntries is! List) {
      throw const FormatException('entries 목록이 필요합니다');
    }
    return ReferenceRevision(
      revisionId: _requiredString(json, 'revision_id'),
      baseRevisionId: _nullableString(json, 'base_revision_id'),
      createdAtMs: _requiredInt(json, 'created_at_ms'),
      entries: List.unmodifiable(
        rawEntries.map(
          (entry) => ReferenceRevisionEntry.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        ),
      ),
    );
  }
}

class ReferenceRevisionList {
  const ReferenceRevisionList({
    required this.revisions,
    required this.nextCursor,
  });

  final List<ReferenceRevisionSummary> revisions;
  final String? nextCursor;

  factory ReferenceRevisionList.fromJson(Map<String, dynamic> json) {
    final rawRevisions = json['revisions'];
    if (rawRevisions is! List) {
      throw const FormatException('revisions 목록이 필요합니다');
    }
    return ReferenceRevisionList(
      revisions: List.unmodifiable(
        rawRevisions.map(
          (revision) => ReferenceRevisionSummary.fromJson(
            Map<String, dynamic>.from(revision as Map),
          ),
        ),
      ),
      nextCursor: _nullableString(json, 'next_cursor'),
    );
  }
}

enum ModelBuildState {
  queued,
  preparing,
  exporting,
  building,
  validating,
  succeeded,
  failed,
  interrupted;

  bool get isFinal =>
      this == succeeded || this == failed || this == interrupted;

  static ModelBuildState parse(String value) => switch (value) {
    'QUEUED' => queued,
    'PREPARING' => preparing,
    'EXPORTING' => exporting,
    'BUILDING' => building,
    'VALIDATING' => validating,
    'SUCCEEDED' => succeeded,
    'FAILED' => failed,
    'INTERRUPTED' => interrupted,
    _ => throw FormatException('지원하지 않는 모델 빌드 상태: $value'),
  };
}

class ModelValidationDetection {
  const ModelValidationDetection({
    required this.className,
    required this.confidence,
    required this.box,
  });

  final String className;
  final double confidence;
  // Original image pixels, x/y/width/height (not the reference box xyxy format).
  final List<double> box;

  factory ModelValidationDetection.fromJson(Map<String, dynamic> json) {
    final rawBox = json['box'];
    final confidence = _optionalNumber(json, 'confidence')?.toDouble();
    if (rawBox is! List ||
        rawBox.length != 4 ||
        rawBox.any((value) => value is! num || !value.isFinite) ||
        (rawBox[2] as num) <= 0 ||
        (rawBox[3] as num) <= 0 ||
        confidence == null ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1) {
      throw const FormatException('검증 결과의 검출 좌표 또는 신뢰도가 올바르지 않습니다');
    }
    return ModelValidationDetection(
      className: _requiredString(json, 'class_name'),
      confidence: confidence,
      box: List.unmodifiable(rawBox.map((value) => (value as num).toDouble())),
    );
  }
}

class ModelValidationResult {
  const ModelValidationResult({
    required this.source,
    required this.className,
    required this.status,
    required this.reason,
    required this.latencyMs,
    this.detections,
    this.imageId,
    this.measurements = const {},
  });

  final String source;
  final String? imageId;
  final String className;
  final String status;
  final String reason;
  final double? latencyMs;
  // null: positions were not recorded; empty: inference found no candidates.
  final List<ModelValidationDetection>? detections;
  final Map<String, dynamic> measurements;

  factory ModelValidationResult.fromJson(Map<String, dynamic> json) {
    final rawDetections = json['detections'];
    final rawMeasurements = json['measurements'];
    if (rawDetections != null && rawDetections is! List) {
      throw const FormatException('검증 결과에 detections 목록이 필요합니다');
    }
    if (rawMeasurements != null && rawMeasurements is! Map) {
      throw const FormatException('검증 결과에 measurements 객체가 필요합니다');
    }
    return ModelValidationResult(
      source: _requiredString(json, 'source'),
      imageId: json['image_id'] == null
          ? null
          : _requiredString(json, 'image_id'),
      className: _requiredString(json, 'class_name'),
      status: _requiredString(json, 'status'),
      reason: _optionalString(json, 'reason'),
      latencyMs: _optionalNumber(json, 'latency_ms')?.toDouble(),
      detections: rawDetections == null
          ? null
          : List.unmodifiable(
              (rawDetections as List).map((value) {
                if (value is! Map) {
                  throw const FormatException('검증 결과에 검출 객체가 필요합니다');
                }
                return ModelValidationDetection.fromJson(
                  Map<String, dynamic>.from(value),
                );
              }),
            ),
      measurements: Map.unmodifiable(
        rawMeasurements == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(rawMeasurements as Map),
      ),
    );
  }
}

class ModelValidation {
  const ModelValidation({
    required this.technicalPassed,
    required this.productionApproved,
    required this.results,
  });

  final bool technicalPassed;
  final bool productionApproved;
  final List<ModelValidationResult> results;

  factory ModelValidation.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'];
    if (rawResults is! List) {
      throw const FormatException('검증 결과 목록이 필요합니다');
    }
    return ModelValidation(
      technicalPassed: _requiredBool(json, 'technical_passed'),
      productionApproved: json['production_approved'] == true,
      results: List.unmodifiable(
        rawResults.map(
          (result) => ModelValidationResult.fromJson(
            Map<String, dynamic>.from(result as Map),
          ),
        ),
      ),
    );
  }
}

class ModelBuild {
  const ModelBuild({
    required this.buildId,
    required this.state,
    required this.referenceRevisionId,
    required this.candidateModelId,
    required this.validation,
    required this.error,
    required this.createdAtMs,
  });

  final String buildId;
  final ModelBuildState state;
  final String referenceRevisionId;
  final String? candidateModelId;
  final ModelValidation? validation;
  final String error;
  final int? createdAtMs;

  factory ModelBuild.fromJson(Map<String, dynamic> json) {
    final rawValidation = json['validation'];
    if (rawValidation != null && rawValidation is! Map) {
      throw const FormatException('validation 객체가 필요합니다');
    }
    return ModelBuild(
      buildId: _requiredString(json, 'build_id'),
      state: ModelBuildState.parse(_requiredString(json, 'state')),
      referenceRevisionId: _requiredString(json, 'reference_revision_id'),
      candidateModelId: _nullableString(json, 'candidate_model_id'),
      validation: rawValidation == null
          ? null
          : ModelValidation.fromJson(Map<String, dynamic>.from(rawValidation)),
      error: _errorMessage(json['error']),
      createdAtMs: _optionalInt(json, 'created_at_ms'),
    );
  }
}

class ReferenceModel {
  const ReferenceModel({
    required this.modelId,
    required this.referenceRevisionId,
    required this.createdAtMs,
    required this.engineSha256,
    required this.metadataSha256,
    required this.technicalPassed,
    required this.reviewRequired,
    required this.buildId,
    required this.validation,
    required this.weightsSha256,
    required this.exportConfigSha256,
    required this.onnxSha256,
  });

  final String modelId;
  final String referenceRevisionId;
  final int createdAtMs;
  final String engineSha256;
  final String metadataSha256;
  final bool technicalPassed;
  final bool reviewRequired;
  final String? buildId;
  final ModelValidation? validation;
  final String? weightsSha256;
  final String? exportConfigSha256;
  final String? onnxSha256;

  factory ReferenceModel.fromJson(Map<String, dynamic> json) {
    final rawValidation = json['validation'];
    if (rawValidation != null && rawValidation is! Map) {
      throw const FormatException('validation 객체가 필요합니다');
    }
    return ReferenceModel(
      modelId: _requiredString(json, 'model_id'),
      referenceRevisionId: _requiredString(json, 'reference_revision_id'),
      createdAtMs: _requiredInt(json, 'created_at_ms'),
      engineSha256: _requiredString(json, 'engine_sha256'),
      metadataSha256: _requiredString(json, 'metadata_sha256'),
      technicalPassed: _requiredBool(json, 'technical_passed'),
      reviewRequired: _requiredBool(json, 'review_required'),
      buildId: _nullableString(json, 'build_id'),
      validation: rawValidation == null
          ? null
          : ModelValidation.fromJson(Map<String, dynamic>.from(rawValidation)),
      weightsSha256: _nullableString(json, 'weights_sha256'),
      exportConfigSha256: _nullableString(json, 'export_config_sha256'),
      onnxSha256: _nullableString(json, 'onnx_sha256'),
    );
  }
}

class ReferenceModelList {
  const ReferenceModelList({required this.models, required this.nextCursor});

  final List<ReferenceModel> models;
  final String? nextCursor;

  factory ReferenceModelList.fromJson(Map<String, dynamic> json) {
    final rawModels = json['models'];
    if (rawModels is! List) throw const FormatException('models 목록이 필요합니다');
    return ReferenceModelList(
      models: List.unmodifiable(
        rawModels.map(
          (model) =>
              ReferenceModel.fromJson(Map<String, dynamic>.from(model as Map)),
        ),
      ),
      nextCursor: _nullableString(json, 'next_cursor'),
    );
  }
}

enum ModelActivationState {
  queued,
  draining,
  loading,
  succeeded,
  rolledBack,
  failed,
  interrupted;

  bool get isFinal =>
      this == succeeded ||
      this == rolledBack ||
      this == failed ||
      this == interrupted;

  static ModelActivationState parse(String value) => switch (value) {
    'QUEUED' => queued,
    'DRAINING' => draining,
    'LOADING' => loading,
    'SUCCEEDED' => succeeded,
    'ROLLED_BACK' => rolledBack,
    'FAILED' => failed,
    'INTERRUPTED' => interrupted,
    _ => throw FormatException('지원하지 않는 모델 적용 상태: $value'),
  };
}

class ModelActivation {
  const ModelActivation({
    required this.activationId,
    required this.state,
    required this.requestedModelId,
    required this.previousModelId,
    required this.activeModelId,
    required this.error,
    required this.createdAtMs,
  });

  final String activationId;
  final ModelActivationState state;
  final String requestedModelId;
  final String previousModelId;
  final String activeModelId;
  final String error;
  final int? createdAtMs;

  factory ModelActivation.fromJson(Map<String, dynamic> json) {
    return ModelActivation(
      activationId: _requiredString(json, 'activation_id'),
      state: ModelActivationState.parse(_requiredString(json, 'state')),
      requestedModelId: _requiredString(json, 'requested_model_id'),
      previousModelId: _requiredString(json, 'previous_model_id'),
      activeModelId: _requiredString(json, 'active_model_id'),
      error: _errorMessage(json['error']),
      createdAtMs: _optionalInt(json, 'created_at_ms'),
    );
  }
}

class RemoteReferenceApiService {
  RemoteReferenceApiService({
    Duration requestTimeout = const Duration(seconds: 10),
    int maxImageBytes = 16 * 1024 * 1024,
  }) : _client = ApiHttpClient(timeout: requestTimeout),
       _maxImageBytes = maxImageBytes;

  final ApiHttpClient _client;
  final int _maxImageBytes;

  void close() => _client.close();

  Future<ReferenceApiStatus> fetchStatus(
    AppSettings settings, {
    required String bearerToken,
  }) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('reference/status'),
      bearerToken: bearerToken,
    );
    return ReferenceApiStatus.fromJson(json);
  }

  Future<ReferenceCapture> requestCapture(
    AppSettings settings,
    String cameraId, {
    required String bearerToken,
    String? requestId,
  }) async {
    final normalizedCameraId = cameraId.trim();
    if (normalizedCameraId.isEmpty) {
      throw const FormatException('camera_id가 비어 있으면 안 됩니다');
    }
    final json = await _requestJson(
      'POST',
      settings.buildApiUri('reference/captures'),
      bearerToken: bearerToken,
      body: {
        'request_id': requestId ?? generateRequestId(),
        'camera_id': normalizedCameraId,
      },
    );
    return ReferenceCapture.fromJson(json);
  }

  Future<ReferenceCapture> fetchCapture(
    AppSettings settings,
    String captureId, {
    required String bearerToken,
  }) async {
    final id = _requireId(captureId, 'capture_id');
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('reference/captures/${Uri.encodeComponent(id)}'),
      bearerToken: bearerToken,
    );
    return ReferenceCapture.fromJson(json);
  }

  Future<Uint8List> fetchImage(
    AppSettings settings,
    ReferenceImageInfo image, {
    required String bearerToken,
  }) => fetchImageUrl(settings, image.url, bearerToken: bearerToken);

  Future<Uint8List> fetchImageUrl(
    AppSettings settings,
    String relativeUrl, {
    required String bearerToken,
  }) async {
    final uri = _relativeApiUri(settings, relativeUrl);
    return _client.send(
      'GET',
      uri,
      accept: 'image/png',
      headers: _authorization(bearerToken),
      read: (response) async {
        if (response.statusCode != HttpStatus.ok) {
          final body = await response.transform(utf8.decoder).join();
          throw _apiException('GET', uri, response.statusCode, body);
        }
        if (response.headers.contentType?.mimeType != 'image/png') {
          throw const FormatException('기준 이미지 응답는 PNG여야 합니다');
        }
        final maxBytes = _maxImageBytes;
        if (response.contentLength > maxBytes) {
          throw const FormatException('기준 이미지가 16 MiB를 초과했습니다');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const FormatException('기준 이미지가 16 MiB를 초과했습니다');
          }
          bytes.add(chunk);
        }
        return bytes.takeBytes();
      },
    );
  }

  Future<ReferenceRevisionList> fetchRevisions(
    AppSettings settings, {
    required String bearerToken,
    int limit = 20,
    String? cursor,
  }) async {
    if (limit < 1 || limit > 100) {
      throw const FormatException('조회 개수는 1~100이어야 합니다');
    }
    final base = settings.buildApiUri('reference/revisions');
    final uri = base.replace(
      queryParameters: {
        'limit': '$limit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final json = await _requestJson('GET', uri, bearerToken: bearerToken);
    return ReferenceRevisionList.fromJson(json);
  }

  Future<ReferenceRevision> fetchRevision(
    AppSettings settings,
    String revisionId, {
    required String bearerToken,
  }) async {
    final id = _requireId(revisionId, 'revision_id');
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('reference/revisions/${Uri.encodeComponent(id)}'),
      bearerToken: bearerToken,
    );
    return ReferenceRevision.fromJson(json);
  }

  /// Saves one image while retaining the explicitly supplied images of the same class.
  Future<ReferenceRevision> createRevision(
    AppSettings settings, {
    required String? baseRevisionId,
    required String className,
    required String imageId,
    required List<ReferenceBox> boxes,
    List<ReferenceRevisionEntry> otherImages = const [],
    required String bearerToken,
    String? requestId,
  }) async {
    if (otherImages.any((entry) => entry.className != className)) {
      throw const FormatException('같은 클래스의 기준 이미지만 함께 저장할 수 있습니다');
    }
    return _replaceClassSamples(
      settings,
      baseRevisionId: baseRevisionId,
      className: className,
      samples: [
        for (final entry in otherImages)
          {
            'image_id': entry.imageId,
            'boxes': (entry.imageId == imageId ? boxes : entry.boxes)
                .map((box) => box.toJson())
                .toList(),
          },
        if (!otherImages.any((entry) => entry.imageId == imageId))
          {
            'image_id': imageId,
            'boxes': boxes.map((box) => box.toJson()).toList(),
          },
      ],
      bearerToken: bearerToken,
      requestId: requestId,
    );
  }

  Future<ReferenceRevision> replaceClassReferences(
    AppSettings settings, {
    required String baseRevisionId,
    required String className,
    required List<ReferenceRevisionEntry> samples,
    required String bearerToken,
    String? requestId,
  }) {
    if (samples.any((entry) => entry.className != className)) {
      throw const FormatException('같은 클래스의 기준 이미지만 함께 저장할 수 있습니다');
    }
    return _replaceClassSamples(
      settings,
      baseRevisionId: baseRevisionId,
      className: className,
      samples: [
        for (final entry in samples)
          {
            'image_id': entry.imageId,
            'boxes': entry.boxes.map((box) => box.toJson()).toList(),
          },
      ],
      bearerToken: bearerToken,
      requestId: requestId,
    );
  }

  Future<ReferenceRevision> _replaceClassSamples(
    AppSettings settings, {
    required String? baseRevisionId,
    required String className,
    required List<Map<String, dynamic>> samples,
    required String bearerToken,
    String? requestId,
  }) async {
    final normalizedClass = _requireId(className, 'class_name');
    if (samples.isEmpty || samples.length > 16) {
      throw const FormatException('클래스별 기준 이미지는 1~16장이 필요합니다');
    }
    final ids = <String>{};
    for (final sample in samples) {
      final id = _requireId(sample['image_id'] as String, 'image_id');
      if (!ids.add(id)) throw const FormatException('같은 이미지를 중복 등록할 수 없습니다');
      final boxes = sample['boxes'] as List;
      if (boxes.isEmpty || boxes.length > 64) {
        throw const FormatException('이미지마다 박스는 1~64개가 필요합니다');
      }
    }
    final json = await _requestJson(
      'POST',
      settings.buildApiUri('reference/revisions'),
      bearerToken: bearerToken,
      body: {
        'request_id': requestId ?? generateRequestId(),
        'base_revision_id': baseRevisionId,
        'entries': [
          for (final sample in samples)
            {'class_name': normalizedClass, ...sample},
        ],
      },
    );
    return ReferenceRevision.fromJson(json);
  }

  Future<ModelBuild> requestModelBuild(
    AppSettings settings, {
    required String referenceRevisionId,
    required String bearerToken,
    String? requestId,
  }) async {
    final revisionId = _requireId(referenceRevisionId, 'reference_revision_id');
    final json = await _requestJson(
      'POST',
      settings.buildApiUri('model/builds'),
      bearerToken: bearerToken,
      body: {
        'request_id': requestId ?? generateRequestId(),
        'reference_revision_id': revisionId,
        'maintenance_confirmed': true,
      },
    );
    return ModelBuild.fromJson(json);
  }

  Future<ModelBuild> fetchModelBuild(
    AppSettings settings,
    String buildId, {
    required String bearerToken,
  }) async {
    final id = _requireId(buildId, 'build_id');
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('model/builds/${Uri.encodeComponent(id)}'),
      bearerToken: bearerToken,
    );
    return ModelBuild.fromJson(json);
  }

  Future<ReferenceModelList> fetchModels(
    AppSettings settings, {
    required String bearerToken,
    int limit = 20,
    String? cursor,
  }) async {
    if (limit < 1 || limit > 100) {
      throw const FormatException('조회 개수는 1~100이어야 합니다');
    }
    final uri = settings
        .buildApiUri('models')
        .replace(
          queryParameters: {
            'limit': '$limit',
            if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          },
        );
    final json = await _requestJson('GET', uri, bearerToken: bearerToken);
    return ReferenceModelList.fromJson(json);
  }

  Future<ModelActivation> requestModelActivation(
    AppSettings settings, {
    required String modelId,
    required String expectedActiveModelId,
    required String bearerToken,
    String? requestId,
  }) async {
    final requested = _requireId(modelId, 'model_id');
    final expected = _requireId(
      expectedActiveModelId,
      'expected_active_model_id',
    );
    final json = await _requestJson(
      'POST',
      settings.buildApiUri('model/activations'),
      bearerToken: bearerToken,
      body: {
        'request_id': requestId ?? generateRequestId(),
        'model_id': requested,
        'expected_active_model_id': expected,
        'review_confirmed': true,
      },
    );
    return ModelActivation.fromJson(json);
  }

  Future<ModelActivation> fetchModelActivation(
    AppSettings settings,
    String activationId, {
    required String bearerToken,
  }) async {
    final id = _requireId(activationId, 'activation_id');
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('model/activations/${Uri.encodeComponent(id)}'),
      bearerToken: bearerToken,
    );
    return ModelActivation.fromJson(json);
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    Uri uri, {
    required String bearerToken,
    Map<String, dynamic>? body,
  }) => _client.requestJson(
    method,
    uri,
    body: body,
    allowEmpty: true,
    headers: _authorization(bearerToken),
    maxRequestBytes: 64 * 1024,
    expectedStatusCodes: const {200, 201, 202},
    error: (status, text, _) => _apiException(method, uri, status, text),
  );
  static RemoteReferenceApiException _apiException(
    String method,
    Uri uri,
    int statusCode,
    String responseBody,
  ) {
    var code = '';
    var message = responseBody;
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map && decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        if (error['code'] is String) code = error['code'] as String;
        if (error['message'] is String) message = error['message'] as String;
      }
    } catch (_) {
      // Preserve a non-JSON server response as the diagnostic message.
    }
    return RemoteReferenceApiException(
      method: method,
      uri: uri,
      statusCode: statusCode,
      code: code,
      message: message.isEmpty ? 'HTTP $statusCode' : message,
    );
  }

  static Map<String, String> _authorization(String bearerToken) {
    if (!RegExp(r'^[A-Za-z0-9_-]{32,256}$').hasMatch(bearerToken)) {
      throw const FormatException('관리 인증 정보가 올바르지 않습니다');
    }
    return {HttpHeaders.authorizationHeader: 'Bearer $bearerToken'};
  }
}

String generateRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

Uri _relativeApiUri(AppSettings settings, String relativeUrl) {
  final relative = Uri.parse(relativeUrl);
  if (relative.hasScheme ||
      relative.hasAuthority ||
      !relativeUrl.startsWith('/')) {
    throw const FormatException('서버 리소스 URL은 상대 경로여야 합니다');
  }
  final base = Uri.parse(
    settings.detectorBaseUrl.contains('://')
        ? settings.detectorBaseUrl
        : 'http://${settings.detectorBaseUrl}',
  );
  return base.replace(path: relative.path, query: relative.query);
}

String _requireId(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw FormatException('$field 항목이 비어 있으면 안 됩니다');
  return normalized;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key 항목에 비어 있지 않은 문자열이 필요합니다');
  }
  return value;
}

String _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return '';
  if (value is! String) throw FormatException('$key 항목에 문자열이 필요합니다');
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key 항목에 문자열이 필요합니다');
  return value.isEmpty ? null : value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key 항목에 불리언 값이 필요합니다');
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite || value != value.roundToDouble()) {
    throw FormatException('$key 항목에 정수가 필요합니다');
  }
  return value.toInt();
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _requiredInt(json, key);
}

num? _optionalNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num || !value.isFinite) {
    throw FormatException('$key 항목에 유한한 숫자가 필요합니다');
  }
  return value;
}

String _errorMessage(dynamic error) {
  if (error == null) return '';
  if (error is String) return error;
  if (error is Map && error['message'] is String) {
    return error['message'] as String;
  }
  throw const FormatException('촬영 오류 응답이 올바르지 않습니다');
}
