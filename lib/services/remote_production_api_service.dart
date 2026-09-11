import 'api_http_client.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../models/app_settings.dart';

import '../models/production.dart';
export '../models/production.dart';

class ProductionApiException implements Exception {
  const ProductionApiException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'Inspect 요청 실패 ($code): $message';
}

class RemoteProductionApiService {
  RemoteProductionApiService({
    HttpClient? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = ApiHttpClient(client: client, timeout: timeout);
  final ApiHttpClient _client;
  final Duration timeout;
  void close() => _client.close();
  static String requestId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<RecipeCatalog> recipes(AppSettings settings) async =>
      RecipeCatalog.fromJson(await request(settings, 'GET', 'recipes'));
  Future<RecipeSlot> addProduct(AppSettings settings, int count) async =>
      RecipeSlot.fromJson(
        await request(settings, 'POST', 'products', {
          'base_product_count': count,
        }),
      );
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
  Future<ProductionStatus> status(AppSettings settings) async =>
      ProductionStatus.fromJson(await request(settings, 'GET', 'status'));

  Future<List<ProductionCapture>> captures(AppSettings settings) async {
    final response = await request(settings, 'GET', 'captures');
    final items = response['captures'];
    if (items is! List) throw const FormatException('제품 검사 이력 목록이 필요합니다');
    return List.unmodifiable(
      items.map((item) => ProductionCapture.fromJson(productionObject(item))),
    );
  }

  Future<ProductionCapture> command(
    AppSettings settings,
    String action, {
    Map<String, dynamic> values = const {},
  }) async {
    final response = await request(settings, 'POST', 'command', {
      ...values,
      'request_id': requestId(),
      'action': action,
    });
    if (response['accepted'] != true) {
      throw const FormatException('생산 명령이 접수되지 않았습니다');
    }
    return ProductionCapture.fromJson(productionObject(response['capture']));
  }

  Future<Map<String, dynamic>> request(
    AppSettings settings,
    String method,
    String endpoint, [
    Map<String, dynamic>? body,
  ]) async {
    return _client.requestJson(
      method,
      settings.buildApiUri('production/$endpoint'),
      body: body,
      error: (status, body, _) => ProductionApiException(status, body),
    );
  }
}
