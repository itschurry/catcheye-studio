import '../services/remote_capture_api_service.dart';

const inspectionLabels = {
  'bolt_head': '볼트 머리',
  'stud': '스터드',
  'nut': '너트',
  'nut_hole_alignment': '너트 홀 형상·정렬',
};

const inspectionHardwareIds = {
  'bolt_head': 0,
  'stud': 1,
  'nut': 2,
  'nut_hole_alignment': 3,
};

Map<String, dynamic> productionObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Inspect JSON 객체가 필요합니다');
  }
  return value;
}

class RecipePoint {
  const RecipePoint({
    required this.name,
    required this.inspectionId,
    required this.expectedCount,
    required this.candidateConfidence,
    required this.presentConfidence,
    required this.geometry,
  });
  final String name;
  final String inspectionId;
  final int? expectedCount;
  final double candidateConfidence;
  final double presentConfidence;
  final Map<String, double?>? geometry;

  factory RecipePoint.fromJson(Map<String, dynamic> json) {
    final id = json['inspection_id'];
    if (json['name'] is! String ||
        id is! String ||
        !inspectionLabels.containsKey(id) ||
        (json['expected_count'] != null && json['expected_count'] is! int) ||
        json['candidate_confidence'] is! num ||
        json['present_confidence'] is! num) {
      throw const FormatException('촬영 포인트 형식이 올바르지 않습니다');
    }
    final rawGeometry = json['geometry'];
    return RecipePoint(
      name: json['name'] as String,
      inspectionId: id,
      expectedCount: json['expected_count'] as int?,
      candidateConfidence: (json['candidate_confidence'] as num).toDouble(),
      presentConfidence: (json['present_confidence'] as num).toDouble(),
      geometry: rawGeometry == null
          ? null
          : productionObject(rawGeometry).map(
              (key, value) => MapEntry(
                key,
                value == null ? null : (value as num).toDouble(),
              ),
            ),
    );
  }
  Map<String, dynamic> toJson() => {
    'name': name,
    'inspection_id': inspectionId,
    'expected_count': expectedCount,
    'candidate_confidence': candidateConfidence,
    'present_confidence': presentConfidence,
    'geometry': geometry,
  };
}

class ProductRecipe {
  const ProductRecipe(this.name, this.points);
  final String name;
  final List<RecipePoint> points;
  factory ProductRecipe.fromJson(Map<String, dynamic> json) {
    if (json['name'] is! String || json['points'] is! List) {
      throw const FormatException('제품 레시피 형식이 올바르지 않습니다');
    }
    return ProductRecipe(json['name'] as String, [
      for (final item in json['points'] as List)
        RecipePoint.fromJson(productionObject(item)),
    ]);
  }
  Map<String, dynamic> toJson() => {
    'name': name,
    'points': points.map((p) => p.toJson()).toList(),
  };
}

class RecipeSlot {
  const RecipeSlot(
    this.productId,
    this.revision,
    this.draft,
    this.activeRevision,
    this.active,
  );
  final int productId;
  final int revision;
  final ProductRecipe draft;
  final int? activeRevision;
  final ProductRecipe? active;
  factory RecipeSlot.fromJson(Map<String, dynamic> json) {
    if (json['product_id'] is! int ||
        json['revision'] is! int ||
        (json['active_revision'] != null && json['active_revision'] is! int)) {
      throw const FormatException('제품 ID와 레시피 버전이 필요합니다');
    }
    return RecipeSlot(
      json['product_id'] as int,
      json['revision'] as int,
      ProductRecipe.fromJson(productionObject(json['draft'])),
      json['active_revision'] as int?,
      json['active'] == null
          ? null
          : ProductRecipe.fromJson(productionObject(json['active'])),
    );
  }
}

class RecipeCatalog {
  const RecipeCatalog(this.products, this.defaults);
  final List<RecipeSlot> products;
  final Map<String, dynamic> defaults;
  factory RecipeCatalog.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 ||
        json['products'] is! List ||
        (json['products'] as List).length < 5 ||
        (json['products'] as List).length > 255) {
      throw const FormatException('제품 5~255종의 레시피 API v1이 필요합니다');
    }
    final products = [
      for (final item in json['products'] as List)
        RecipeSlot.fromJson(productionObject(item)),
    ];
    for (var i = 0; i < products.length; i++) {
      if (products[i].productId != i + 1) {
        throw const FormatException('제품 ID가 일치하지 않습니다');
      }
    }
    return RecipeCatalog(
      products,
      productionObject(json['inspection_defaults']),
    );
  }
}

T _field<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! T) throw FormatException('$key 항목의 형식이 올바르지 않습니다');
  return value;
}

String _id(Map<String, dynamic> json, String key) {
  final value = _field<String>(json, key);
  if (value.isEmpty) throw FormatException('$key 항목이 비어 있습니다');
  return value;
}

T? _optional<T>(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _field<T>(json, key);

enum ProductionCaptureState {
  triggering('TRIGGERING'),
  inspecting('INSPECTING'),
  fault('FAULT'),
  completed('COMPLETED'),
  aborted('ABORTED');

  const ProductionCaptureState(this.code);
  final String code;
  static ProductionCaptureState parse(Object? value) =>
      values.where((s) => s.code == value).firstOrNull ??
      (throw FormatException('지원하지 않는 촬영 상태: $value'));
}

class ProductionEvent {
  ProductionEvent.fromJson(Map<String, dynamic> json)
    : atMs = _field<int>(json, 'at_ms'),
      name = _field<String>(json, 'event'),
      detail = Map.unmodifiable(productionObject(json['detail']));
  final int atMs;
  final String name;
  final Map<String, dynamic> detail;
  static List<ProductionEvent> parse(Object? value) {
    if (value is! List) throw const FormatException('이벤트 목록이 필요합니다');
    return List.unmodifiable(
      value.map((e) => ProductionEvent.fromJson(productionObject(e))),
    );
  }
}

class ProductionInspectionSummary {
  ProductionInspectionSummary.fromJson(Map<String, dynamic> json)
    : expectedCount = _optional<int>(json, 'expected_count'),
      presentCount = _optional<int>(json, 'present_count'),
      reason = _field<String>(json, 'reason');
  final int? expectedCount, presentCount;
  final String reason;
}

class ProductionResult {
  ProductionResult.fromJson(Map<String, dynamic> json)
    : capture = StationCaptureResult.fromJson(json),
      reason = _optional<String>(json, 'reason'),
      summaries = List.unmodifiable(
        _inspectionSummaries(
          json,
        ).map((v) => ProductionInspectionSummary.fromJson(productionObject(v))),
      );
  final StationCaptureResult capture;
  final String? reason;
  final List<ProductionInspectionSummary> summaries;
  static Iterable<dynamic> _inspectionSummaries(Map<String, dynamic> json) {
    // Station failures can occur before any per-inspection result exists.
    if (!json.containsKey('inspections') &&
        json['status'] == 'EQUIPMENT_ERROR') {
      return const [];
    }
    return productionObject(json['inspections']).values;
  }
}

class ProductionCapture {
  ProductionCapture.fromJson(Map<String, dynamic> json)
    : id = _id(json, 'capture_id'),
      requestId = _optional<String>(json, 'request_id'),
      productId = _field<int>(json, 'product_id'),
      recipeRevision = _field<int>(json, 'recipe_revision'),
      recipe = ProductRecipe.fromJson(productionObject(json['recipe'])),
      origin = _field<String>(json, 'origin'),
      state = ProductionCaptureState.parse(json['state']),
      status = _field<String>(json, 'status'),
      pointNumber = _field<int>(json, 'point_number'),
      hardwareId = _optional<int>(json, 'hardware_id'),
      error = _field<String>(json, 'error'),
      results = List.unmodifiable(
        _field<List>(
          json,
          'results',
        ).map((v) => ProductionResult.fromJson(productionObject(v))),
      ) {
    if (!{'studio', 'plc', 'plc_simulator'}.contains(origin) ||
        productId < 1 ||
        productId > 255 ||
        pointNumber < 1 ||
        pointNumber > recipe.points.length ||
        results.length > 1 ||
        (hardwareId != null && (hardwareId! < 0 || hardwareId! > 3)) ||
        !{'PENDING', 'OK', 'NG'}.contains(status)) {
      throw const FormatException('촬영 요청 정보가 올바르지 않습니다');
    }
  }
  final String id, origin, status, error;
  final String? requestId;
  final int productId, recipeRevision, pointNumber;
  final int? hardwareId;
  final ProductRecipe recipe;
  final ProductionCaptureState state;
  final List<ProductionResult> results;
  bool get active =>
      state != ProductionCaptureState.completed &&
      state != ProductionCaptureState.aborted;
}

enum PlcConnectionState {
  disabled('DISABLED'),
  disconnected('DISCONNECTED'),
  connecting('CONNECTING'),
  waitingIdle('WAITING_IDLE'),
  connected('CONNECTED'),
  fault('FAULT');

  const PlcConnectionState(this.code);
  final String code;
  static PlcConnectionState parse(Object? value) =>
      values.where((s) => s.code == value).firstOrNull ??
      (throw FormatException('지원하지 않는 PLC 연결 상태: $value'));
}

class PlcSimulatorStatus {
  PlcSimulatorStatus.fromJson(Map<String, dynamic> json)
    : id = _id(json, 'simulator_id'),
      state = _field<String>(json, 'state'),
      requestId = _optional<String>(json, 'request_id'),
      result = _optional<String>(json, 'result'),
      error = _field<String>(json, 'error'),
      cleared = _field<bool>(json, 'cleared'),
      rearmed = _field<bool>(json, 'rearmed'),
      productId = _optional<int>(json, 'product_id'),
      pointNumber = _optional<int>(json, 'point_number'),
      hardwareId = _optional<int>(json, 'hardware_id'),
      receivedWords = PlcStatus._words(json['received_words']) {
    if (!{
          'CONNECTING',
          'IDLE',
          'SENDING',
          'WAITING_RESULT',
          'COMPLETED',
          'FAULT',
        }.contains(state) ||
        (hardwareId != null && (hardwareId! < 0 || hardwareId! > 3)) ||
        (result != null && !{'OK', 'NG'}.contains(result)) ||
        (receivedWords != null &&
            (receivedWords!.length != 3 || receivedWords!.any((v) => v > 1)))) {
      throw const FormatException('PLC 시뮬레이터 상태가 올바르지 않습니다');
    }
  }
  final String id, state, error;
  final String? requestId, result;
  final bool cleared, rearmed;
  final int? productId, pointNumber, hardwareId;
  final List<int>? receivedWords;
  bool get ready => rearmed && {'IDLE', 'COMPLETED'}.contains(state);
}

class PlcStatus {
  PlcStatus.fromJson(Map<String, dynamic> json)
    : source = _optional<String>(json, 'source'),
      simulatorSupported = json['simulator_supported'] == true,
      simulator = json['simulator'] == null
          ? null
          : PlcSimulatorStatus.fromJson(productionObject(json['simulator'])),
      requestId = _optional<String>(json, 'request_id'),
      simulatorRequestId = _optional<String>(json, 'simulator_request_id'),
      state = PlcConnectionState.parse(json['state']),
      enabled = _field<bool>(json, 'enabled'),
      host = _field<String>(json, 'host'),
      port = _field<int>(json, 'port'),
      protocol = _field<String>(json, 'protocol'),
      error = _field<String>(json, 'error'),
      lastRxAtMs = _optional<int>(json, 'last_rx_at_ms'),
      lastTxAtMs = _optional<int>(json, 'last_tx_at_ms'),
      productId = _optional<int>(json, 'product_id'),
      pointNumber = _optional<int>(json, 'point_number'),
      hardwareId = _optional<int>(json, 'hardware_id'),
      events = ProductionEvent.parse(json['events']),
      rxMap = _mapping(json['rx_map']),
      txMap = _mapping(json['tx_map']),
      rxWords = _words(json['rx_words']),
      txWords = _words(json['tx_words']) {
    if ((source != null && !{'real', 'simulator'}.contains(source)) ||
        (hardwareId != null && (hardwareId! < 0 || hardwareId! > 3))) {
      throw const FormatException('PLC 연결 대상 또는 하드웨어 번호가 올바르지 않습니다');
    }
  }
  final String? source, requestId, simulatorRequestId;
  final bool simulatorSupported;
  final PlcSimulatorStatus? simulator;
  final PlcConnectionState state;
  final bool enabled;
  final String host, protocol, error;
  final int port;
  final int? lastRxAtMs, lastTxAtMs, productId, pointNumber, hardwareId;
  final List<ProductionEvent> events;
  final Map<String, int> rxMap, txMap;
  final List<int>? rxWords, txWords;
  bool get canDisconnect => {
    PlcConnectionState.fault,
    PlcConnectionState.connected,
    PlcConnectionState.connecting,
    PlcConnectionState.waitingIdle,
  }.contains(state);
  bool get canConnect => enabled && !canDisconnect;
  static Map<String, int> _mapping(Object? value) => Map.unmodifiable(
    productionObject(value).map((key, value) {
      if (value is! int || value < 0) {
        throw FormatException('$key 신호 위치가 올바르지 않습니다');
      }
      return MapEntry(key, value);
    }),
  );
  static List<int>? _words(Object? value) {
    if (value == null) return null;
    if (value is! List || value.any((w) => w is! int || w < 0 || w > 65535)) {
      throw const FormatException('PLC 워드 목록이 올바르지 않습니다');
    }
    return List<int>.unmodifiable(value);
  }

  Map<String, int> mapping(String direction) =>
      direction == 'rx' ? rxMap : txMap;
  int? word(String direction, int index) {
    final words = direction == 'rx' ? rxWords : txWords;
    return words != null && index >= 0 && index < words.length
        ? words[index]
        : null;
  }
}

class ProductionStatus {
  ProductionStatus.fromJson(Map<String, dynamic> json)
    : controlEpoch = _id(json, 'control_epoch'),
      error = _field<String>(json, 'error'),
      capture = json['capture'] == null
          ? null
          : ProductionCapture.fromJson(productionObject(json['capture'])),
      events = ProductionEvent.parse(json['events']),
      plc = json['plc'] == null
          ? null
          : PlcStatus.fromJson(productionObject(json['plc'])) {
    if (json['api_version'] != 3 || !json.containsKey('capture')) {
      throw const FormatException('지원하지 않는 생산 검사 상태 응답입니다');
    }
  }
  ProductionStatus._(
    this.controlEpoch,
    this.error,
    this.capture,
    this.events,
    this.plc,
  );
  final String controlEpoch, error;
  final ProductionCapture? capture;
  final List<ProductionEvent> events;
  final PlcStatus? plc;
  ProductionStatus withCapture(ProductionCapture capture) =>
      ProductionStatus._(controlEpoch, error, capture, events, plc);
}
