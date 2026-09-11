import 'package:catcheye_studio/theme/studio_theme.dart';
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
  Map<String, dynamic>? lastCapture;
  @override
  Future<RecipeSlot> addProduct(AppSettings settings, int count) async {
    expect(count, catalog.products.length);
    final slot = RecipeSlot(
      count + 1,
      0,
      const ProductRecipe('', []),
      null,
      null,
    );
    catalog = RecipeCatalog([...catalog.products, slot], catalog.defaults);
    return slot;
  }

  @override
  Future<ProductionCapture> command(
    AppSettings settings,
    String action, {
    Map<String, dynamic> values = const {},
  }) async {
    expect(action, 'capture');
    lastCapture = values;
    throw const ProductionApiException(409, 'CAPTURE_BUSY');
  }

  int saves = 0;
  int activations = 0;
  int statusReads = 0;
  @override
  Future<RecipeCatalog> recipes(AppSettings settings) async => catalog;
  @override
  Future<ProductionStatus> status(AppSettings settings) async {
    statusReads++;
    return ProductionStatus.fromJson({
      'api_version': 3,
      'control_epoch': 'boot-1',
      'capture': null,
      'events': [],
      'error': '',
      'plc': {
        'state': 'DISABLED',
        'host': '',
        'port': 0,
        'enabled': false,
        'error': '',
        'events': [],
        'rx_map': <String, dynamic>{},
        'tx_map': <String, dynamic>{},
      },
    });
  }

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
  testWidgets('tab return preserves draft and resumes status reads', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    addTearDown(settings.dispose);
    final api = FakeProductionApi();
    addTearDown(api.close);
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          theme: buildStudioTheme(),
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (context, visible, _) => Offstage(
              offstage: !visible,
              child: ProductionScreen(api: api, active: visible),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('recipe-name')), '편집 중');
    await tester.tap(find.text('PLC 통신 진단'));
    await tester.pumpAndSettle();
    final readsBeforeHide = api.statusReads;
    active.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(api.statusReads, readsBeforeHide);
    expect(
      tester
          .widget<PopScope>(
            find.byWidgetPredicate(
              (widget) => widget is PopScope,
              skipOffstage: false,
            ),
          )
          .canPop,
      isTrue,
    );
    active.value = true;
    await tester.pumpAndSettle();
    expect(api.statusReads, greaterThan(readsBeforeHide));
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
    await tester.tap(find.text('제품 레시피'));
    await tester.pumpAndSettle();
    expect(find.text('편집 중'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

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
          child: MaterialApp(
            theme: buildStudioTheme(),
            home: ProductionScreen(api: api),
          ),
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
      expect(find.textContaining('서버 초안이 다른 곳에서 변경되었습니다'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('save-recipe')));
      await tester.tap(find.byKey(const ValueKey('save-recipe')));
      await tester.pumpAndSettle();
      expect(find.textContaining('REVISION_CONFLICT'), findsOneWidget);
      expect(api.catalog.products.first.draft.name, '다른 편집자 변경');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'products can grow beyond five and manual capture addresses a point directly',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      addTearDown(settings.dispose);
      final api = FakeProductionApi();
      addTearDown(api.close);
      const point = RecipePoint(
        name: 'P1',
        inspectionId: 'bolt_head',
        expectedCount: 3,
        candidateConfidence: .4,
        presentConfidence: .5,
        geometry: null,
      );
      api.catalog = RecipeCatalog([
        RecipeSlot(
          1,
          1,
          const ProductRecipe('A', [point]),
          1,
          const ProductRecipe('A', [point]),
        ),
        ...api.catalog.products.skip(1),
      ], api.catalog.defaults);
      await tester.binding.setSurfaceSize(const Size(1280, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            theme: buildStudioTheme(),
            home: ProductionScreen(api: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-product')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('product-6')), findsOneWidget);
      await tester.tap(find.text('생산 검사'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1. A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1회 촬영'));
      await tester.pumpAndSettle();
      expect(api.lastCapture, {
        'product_id': 1,
        'point_number': 1,
        'hardware_id': 0,
        'control_epoch': 'boot-1',
      });
      expect(find.text('결과 수신 확인'), findsNothing);
      expect(find.text('검사 종료·전체 판정'), findsNothing);
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
          child: MaterialApp(
            theme: buildStudioTheme(),
            home: ProductionScreen(api: api),
          ),
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
