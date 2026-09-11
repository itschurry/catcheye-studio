import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/app_settings.dart';

const inspectionLabels = {
  'bolt_head': '볼트 머리',
  'stud': '스터드',
  'nut': '너트',
  'nut_hole_alignment': '너트 홀 형상·정렬',
};

class ProductionApiException implements Exception {
  const ProductionApiException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'Inspect 요청 실패 ($code): $message';
}

Map<String, dynamic> productionObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Inspect JSON 객체가 필요해');
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
      throw const FormatException('촬영 포인트 형식이 올바르지 않아');
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
      throw const FormatException('제품 레시피 형식이 올바르지 않아');
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
      throw const FormatException('제품 ID와 레시피 버전이 필요해');
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
        (json['products'] as List).length != 5) {
      throw const FormatException('제품 5종의 레시피 API v1이 필요해');
    }
    final products = [
      for (final item in json['products'] as List)
        RecipeSlot.fromJson(productionObject(item)),
    ];
    for (var i = 0; i < 5; i++) {
      if (products[i].productId != i + 1) {
        throw const FormatException('제품 ID가 일치하지 않아');
      }
    }
    return RecipeCatalog(
      products,
      productionObject(json['inspection_defaults']),
    );
  }
}

class RemoteProductionApiService {
  RemoteProductionApiService({
    HttpClient? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? HttpClient();
  final HttpClient _client;
  final Duration timeout;
  void close() => _client.close(force: true);
  static String requestId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<RecipeCatalog> recipes(AppSettings settings) async =>
      RecipeCatalog.fromJson(await request(settings, 'GET', 'recipes'));
  Future<RecipeSlot> save(
    AppSettings settings,
    RecipeSlot slot,
    ProductRecipe recipe,
  ) async => RecipeSlot.fromJson(
    await request(settings, 'PUT', 'recipes/${slot.productId}', {
      'base_revision': slot.revision,
      'recipe': recipe.toJson(),
    }),
  );
  Future<RecipeSlot> activate(AppSettings settings, RecipeSlot slot) async =>
      RecipeSlot.fromJson(
        await request(settings, 'POST', 'recipes/${slot.productId}/activate', {
          'revision': slot.revision,
        }),
      );
  Future<Map<String, dynamic>> status(AppSettings settings) async {
    final result = await request(settings, 'GET', 'status');
    if (result['api_version'] != 1 ||
        result['events'] is! List ||
        !result.containsKey('session')) {
      throw const FormatException('지원하지 않는 생산 검사 상태 응답이야');
    }
    return result;
  }

  Future<Map<String, dynamic>> command(
    AppSettings settings,
    String action, {
    Map<String, dynamic> values = const {},
  }) => request(settings, 'POST', 'command', {
    ...values,
    'request_id': requestId(),
    'action': action,
  });

  Future<Map<String, dynamic>> request(
    AppSettings settings,
    String method,
    String endpoint, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = settings.buildApiUri('production/$endpoint');
    HttpClientRequest? pending;
    try {
      pending = await _client.openUrl(method, uri).timeout(timeout);
      pending.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        pending.headers.contentType = ContentType.json;
        pending.add(utf8.encode(jsonEncode(body)));
      } else if (method == 'POST') {
        pending.headers.contentLength = 0;
      }
      final response = await pending.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw ProductionApiException(response.statusCode, text);
      }
      return productionObject(jsonDecode(text));
    } catch (_) {
      pending?.abort();
      rethrow; // Never retry an uncertain start/capture/end or use another endpoint.
    }
  }
}
