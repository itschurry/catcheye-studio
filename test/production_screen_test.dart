import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/providers/settings_provider.dart';
import 'package:catcheye_studio/screens/production_screen.dart';
import 'package:catcheye_studio/services/remote_production_api_service.dart';
import 'production_api_test.dart' show catalogJson;

class FakeProductionApi extends RemoteProductionApiService {
  RecipeCatalog catalog = RecipeCatalog.fromJson(catalogJson());
  int saves = 0;
  int activations = 0;
  @override
  Future<RecipeCatalog> recipes(AppSettings settings) async => catalog;
  @override
  Future<Map<String, dynamic>> status(AppSettings settings) async => {
    'api_version': 1,
    'control_epoch': 'boot-1',
    'session': null,
    'events': [],
    'error': '',
    'plc': {
      'state': 'DISABLED',
      'enabled': false,
      'error': '',
      'events': [],
      'rx_map': {},
      'tx_map': {},
    },
  };
  @override
  Future<RecipeSlot> save(
    AppSettings settings,
    RecipeSlot slot,
    ProductRecipe recipe,
  ) async {
    saves++;
    if (slot.revision != catalog.products[slot.productId - 1].revision) {
      throw const ProductionApiException(409, 'REVISION_CONFLICT');
    }
    final result = RecipeSlot(
      slot.productId,
      slot.revision + 1,
      recipe,
      null,
      null,
    );
    catalog = RecipeCatalog([
      for (final p in catalog.products)
        if (p.productId == slot.productId) result else p,
    ], catalog.defaults);
    return result;
  }

  @override
  Future<RecipeSlot> activate(AppSettings settings, RecipeSlot slot) async {
    activations++;
    throw const ProductionApiException(400, 'POINT_1: expected_count');
  }
}

void main() {
  testWidgets(
    'refresh does not rebase unsaved edits onto another editor revision',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      addTearDown(settings.dispose);
      final api = FakeProductionApi();
      addTearDown(api.close);
      await tester.binding.setSurfaceSize(const Size(1280, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(home: ProductionScreen(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('recipe-name')), '내 편집');
      api.catalog = RecipeCatalog([
        RecipeSlot(1, 1, const ProductRecipe('다른 편집자 변경', []), null, null),
        ...api.catalog.products.skip(1),
      ], api.catalog.defaults);
      await tester.tap(find.byTooltip('서버 상태 새로고침'));
      await tester.pumpAndSettle();
      expect(find.textContaining('서버 초안이 다른 곳에서 변경됐어'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('save-recipe')));
      await tester.tap(find.byKey(const ValueKey('save-recipe')));
      await tester.pumpAndSettle();
      expect(find.textContaining('REVISION_CONFLICT'), findsOneWidget);
      expect(api.catalog.products.first.draft.name, '다른 편집자 변경');
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets('draft edit and activation error remain reviewable at $width', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      addTearDown(settings.dispose);
      final api = FakeProductionApi();
      addTearDown(api.close);
      await tester.binding.setSurfaceSize(Size(width, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(home: ProductionScreen(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('product-5')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('recipe-name')), '제품 A');
      await tester.tap(find.byKey(const ValueKey('add-point')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('포인트 저장'));
      await tester.pumpAndSettle();
      expect(find.textContaining('기대 미정개'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('save-recipe')));
      await tester.tap(find.byKey(const ValueKey('save-recipe')));
      await tester.pumpAndSettle();
      expect(api.saves, 1);
      expect(
        api.catalog.products.first.draft.points.first.expectedCount,
        isNull,
      );
      expect(api.activations, 0);
      await tester.tap(find.byKey(const ValueKey('activate-recipe')));
      await tester.pumpAndSettle();
      expect(api.activations, 1);
      expect(find.textContaining('POINT_1: expected_count'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
