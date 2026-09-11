import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/services/remote_production_api_service.dart';

Map<String, dynamic> catalogJson() => {
  'schema_version': 1,
  'products': [
    for (var id = 1; id <= 5; id++)
      {
        'product_id': id,
        'revision': 0,
        'draft': {'name': '', 'points': []},
        'active_revision': null,
        'active': null,
      },
  ],
  'inspection_defaults': {
    'bolt_head': {
      'camera_id': 'bolt_head_camera',
      'candidate_confidence': 0.4,
      'present_confidence': 0.5,
      'geometry': null,
    },
  },
};

void main() {
  test('five product drafts have no invented point count or active recipe', () {
    final catalog = RecipeCatalog.fromJson(catalogJson());
    expect(catalog.products.length, 5);
    expect(
      catalog.products.every(
        (slot) => slot.active == null && slot.draft.points.isEmpty,
      ),
      isTrue,
    );
    final point = RecipePoint.fromJson({
      'name': '',
      'inspection_id': 'bolt_head',
      'expected_count': null,
      'candidate_confidence': 0.4,
      'present_confidence': 0.5,
      'geometry': null,
    });
    expect(point.toJson()['expected_count'], isNull);
  });
  test('unsupported or missing catalog is rejected', () {
    expect(
      () => RecipeCatalog.fromJson(catalogJson()..['schema_version'] = 2),
      throwsFormatException,
    );
    expect(
      () => RecipeCatalog.fromJson(catalogJson()..['products'] = []),
      throwsFormatException,
    );
  });
  test(
    'failed capture is posted once with the exact session and control epoch',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var count = 0;
      final subscription = server.listen((request) async {
        count++;
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/production/command');
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['action'], 'capture');
        expect(body['session_id'], 'session-1');
        expect(body['control_epoch'], 'boot-1');
        expect(body['inspection_id'], 'bolt_head');
        expect(body['request_id'], isNotEmpty);
        request.response.statusCode = 409;
        request.response.write('{"error":"NOT_READY_FOR_TRIGGER"}');
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final api = RemoteProductionApiService();
      addTearDown(api.close);
      await expectLater(
        api.command(
          AppSettings(detectorBaseUrl: 'http://127.0.0.1:${server.port}'),
          'capture',
          values: {
            'session_id': 'session-1',
            'control_epoch': 'boot-1',
            'inspection_id': 'bolt_head',
          },
        ),
        throwsA(
          isA<ProductionApiException>().having((e) => e.code, 'code', 409),
        ),
      );
      expect(count, 1);
    },
  );
  test('save carries base revision and does not activate', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final paths = <String>[];
    final subscription = server.listen((request) async {
      paths.add(request.uri.path);
      expect(request.method, 'PUT');
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(body['base_revision'], 0);
      expect((body['recipe'] as Map)['name'], '제품 A');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'product_id': 1,
          'revision': 1,
          'draft': body['recipe'],
          'active_revision': null,
          'active': null,
        }),
      );
      await request.response.close();
    });
    addTearDown(subscription.cancel);
    final api = RemoteProductionApiService();
    addTearDown(api.close);
    final saved = await api.save(
      AppSettings(detectorBaseUrl: 'http://127.0.0.1:${server.port}'),
      RecipeCatalog.fromJson(catalogJson()).products.first,
      const ProductRecipe('제품 A', []),
    );
    expect(saved.active, isNull);
    expect(saved.revision, 1);
    expect(paths, ['/api/production/recipes/1']);
  });
}
