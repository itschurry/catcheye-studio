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
      'RemoteReferenceApiException: $method $uri failed '
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
      throw const FormatException('capabilities object expected');
    }
    final rawCameraClasses = json['camera_classes'];
    if (rawCameraClasses is! Map) {
      throw const FormatException('camera_classes object expected');
    }
    final cameraClasses = <String, List<String>>{};
    for (final entry in rawCameraClasses.entries) {
      if (entry.key is! String ||
          entry.value is! List ||
          (entry.value as List).any((value) => value is! String)) {
        throw const FormatException('invalid camera_classes entry');
      }
      final classes = (entry.value as List).cast<String>();
      if (classes.isEmpty ||
          classes.any((value) => value.isEmpty) ||
          classes.length != classes.toSet().length) {
        throw const FormatException(
          'camera classes must be unique and nonempty',
        );
      }
      cameraClasses[entry.key as String] = List.unmodifiable(classes);
    }
    final apiVersion = _requiredInt(json, 'api_version');
    if (apiVersion != 1) {
      throw FormatException('unsupported reference API version: $apiVersion');
    }
    final deviceState = _requiredString(json, 'device_state');
    if (!const {'RUNNING', 'MAINTENANCE', 'ERROR'}.contains(deviceState)) {
      throw FormatException('unsupported device state: $deviceState');
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
    _ => throw FormatException('unsupported reference capture state: $value'),
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
      throw const FormatException('image dimensions must be positive');
    }
    final url = _requiredString(json, 'url');
    if (!url.startsWith('/') || url.startsWith('//')) {
      throw const FormatException('reference image URL must be relative');
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
      throw const FormatException('image object expected');
    }
    final image = rawImage == null
        ? null
        : ReferenceImageInfo.fromJson(Map<String, dynamic>.from(rawImage));
    if (state == ReferenceCaptureState.ready && image == null) {
      throw const FormatException('READY capture must include image');
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
      throw const FormatException('box must contain four numbers');
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
    if (rawBoxes is! List) throw const FormatException('boxes list expected');
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
      throw const FormatException('entries list expected');
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
      throw const FormatException('revisions list expected');
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
    _ => throw FormatException('unsupported model build state: $value'),
  };
}

class ModelValidationResult {
  const ModelValidationResult({
    required this.source,
    required this.className,
    required this.status,
    required this.reason,
    required this.latencyMs,
  });

  final String source;
  final String className;
  final String status;
  final String reason;
  final double? latencyMs;

  factory ModelValidationResult.fromJson(Map<String, dynamic> json) {
    return ModelValidationResult(
      source: _requiredString(json, 'source'),
      className: _requiredString(json, 'class_name'),
      status: _requiredString(json, 'status'),
      reason: _optionalString(json, 'reason'),
      latencyMs: _optionalNumber(json, 'latency_ms')?.toDouble(),
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
      throw const FormatException('validation results list expected');
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
      throw const FormatException('validation object expected');
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
      throw const FormatException('validation object expected');
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
    if (rawModels is! List) throw const FormatException('models list expected');
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
    _ => throw FormatException('unsupported model activation state: $value'),
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
  }) : _requestTimeout = requestTimeout,
       _maxImageBytes = maxImageBytes;

  final HttpClient _client = HttpClient();
  final Duration _requestTimeout;
  final int _maxImageBytes;

  void close() => _client.close(force: true);

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
      throw const FormatException('camera_id must not be empty');
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
    HttpClientRequest? request;
    try {
      request = await _client.getUrl(uri).timeout(_requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'image/png');
      _setAuthorization(request, bearerToken);
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        final responseBody = await response
            .transform(utf8.decoder)
            .join()
            .timeout(_requestTimeout);
        throw _apiException('GET', uri, response.statusCode, responseBody);
      }
      if (response.headers.contentType?.mimeType != 'image/png') {
        throw const FormatException('reference image response must be PNG');
      }
      final declaredLength = response.contentLength;
      if (declaredLength > _maxImageBytes) {
        throw const FormatException('reference image exceeds 16 MiB');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_requestTimeout)) {
        if (bytes.length + chunk.length > _maxImageBytes) {
          request.abort();
          throw const FormatException('reference image exceeds 16 MiB');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } on TimeoutException {
      request?.abort();
      rethrow;
    } catch (_) {
      request?.abort();
      rethrow;
    }
  }

  Future<ReferenceRevisionList> fetchRevisions(
    AppSettings settings, {
    required String bearerToken,
    int limit = 20,
    String? cursor,
  }) async {
    if (limit < 1 || limit > 100) {
      throw const FormatException('limit must be between 1 and 100');
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

  Future<ReferenceRevision> createRevision(
    AppSettings settings, {
    required String? baseRevisionId,
    required String className,
    required String imageId,
    required List<ReferenceBox> boxes,
    required String bearerToken,
    String? requestId,
  }) async {
    final normalizedClass = _requireId(className, 'class_name');
    final normalizedImageId = _requireId(imageId, 'image_id');
    if (boxes.isEmpty || boxes.length > 64) {
      throw const FormatException('between 1 and 64 boxes are required');
    }
    final json = await _requestJson(
      'POST',
      settings.buildApiUri('reference/revisions'),
      bearerToken: bearerToken,
      body: {
        'request_id': requestId ?? generateRequestId(),
        'base_revision_id': baseRevisionId,
        'entries': [
          {
            'class_name': normalizedClass,
            'image_id': normalizedImageId,
            'boxes': boxes.map((box) => box.toJson()).toList(growable: false),
          },
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
      throw const FormatException('limit must be between 1 and 100');
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
  }) async {
    HttpClientRequest? request;
    try {
      request = await _client.openUrl(method, uri).timeout(_requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      _setAuthorization(request, bearerToken);
      if (body == null) {
        if (method == 'POST') request.headers.contentLength = 0;
      } else {
        final encoded = utf8.encode(jsonEncode(body));
        if (encoded.length > 64 * 1024) {
          throw const FormatException('reference request exceeds 64 KiB');
        }
        request.headers.contentType = ContentType.json;
        request.headers.contentLength = encoded.length;
        request.add(encoded);
      }
      final response = await request.close().timeout(_requestTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.created &&
          response.statusCode != HttpStatus.accepted) {
        throw _apiException(method, uri, response.statusCode, responseBody);
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

  static void _setAuthorization(HttpClientRequest request, String bearerToken) {
    if (!RegExp(r'^[A-Za-z0-9_-]{32,256}$').hasMatch(bearerToken)) {
      throw const FormatException('invalid management credential');
    }
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
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
    throw const FormatException('server resource URL must be relative');
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
  if (normalized.isEmpty) throw FormatException('$field must not be empty');
  return normalized;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key nonempty string expected');
  }
  return value;
}

String _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return '';
  if (value is! String) throw FormatException('$key string expected');
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key string expected');
  return value.isEmpty ? null : value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key bool expected');
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite || value != value.roundToDouble()) {
    throw FormatException('$key integer expected');
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
    throw FormatException('$key finite number expected');
  }
  return value;
}

String _errorMessage(dynamic error) {
  if (error == null) return '';
  if (error is String) return error;
  if (error is Map && error['message'] is String) {
    return error['message'] as String;
  }
  throw const FormatException('invalid capture error');
}
