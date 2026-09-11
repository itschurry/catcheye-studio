import 'package:catcheye_studio/models/production.dart';
import 'package:catcheye_studio/providers/settings_provider.dart';
import 'package:catcheye_studio/screens/production_screen.dart';
import 'package:catcheye_studio/theme/studio_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'production_screen_test.dart' show FakeProductionApi;

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'ROI copy, count lock, hardware reset and draft save at $width',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsProvider();
        addTearDown(settings.dispose);
        final api = FakeProductionApi();
        addTearDown(api.close);
        const geometry = {
          'min_circularity': .8,
          'min_axis_ratio': .8,
          'max_relative_eccentricity': .1,
          'min_arc_detection_rate': .8,
        };
        const roi = InspectionRoi(.25, .25, .5, .5);
        const point = RecipePoint(
          name: '홀 중앙',
          inspectionId: 'nut_hole_alignment',
          expectedCount: 1,
          candidateConfidence: .4,
          presentConfidence: .5,
          geometry: geometry,
          roi: roi,
        );
        api.catalog = RecipeCatalog(
          [
            const RecipeSlot(1, 1, ProductRecipe('제품 A', [point]), null, null),
            ...api.catalog.products.skip(1),
          ],
          {
            ...api.catalog.defaults,
            'nut_hole_alignment': {
              'camera_id': 'hole_camera',
              'candidate_confidence': .4,
              'present_confidence': .5,
              'geometry': geometry,
            },
          },
        );
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
        await tester.ensureVisible(find.text('복제'));
        await tester.tap(find.text('복제'));
        await tester.pumpAndSettle();
        expect(find.textContaining(roi.summary), findsNWidgets(2));
        await tester.ensureVisible(find.text('편집').first);
        await tester.tap(find.text('편집').first);
        await tester.pumpAndSettle();
        final count = tester.widget<TextFormField>(
          find.byKey(const ValueKey('expected-count')),
        );
        expect(count.controller!.text, '1');
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const ValueKey('expected-count')),
                  matching: find.byType(TextField),
                ),
              )
              .readOnly,
          isTrue,
        );
        expect(find.text('검사 영역 설정 · 영상 확인'), findsOneWidget);
        await tester.ensureVisible(
          find.byType(DropdownButtonFormField<String>),
        );
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('볼트 머리').last);
        await tester.pumpAndSettle();
        expect(find.text('전체 프레임'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const ValueKey('expected-count')),
                  matching: find.byType(TextField),
                ),
              )
              .readOnly,
          isFalse,
        );
        await tester.tap(find.text('포인트 저장'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('초안 저장'));
        await tester.tap(find.text('초안 저장'));
        await tester.pumpAndSettle();
        final saved = api.catalog.products.first.draft.points;
        expect(saved[0].roi, isNull);
        expect(saved[0].inspectionId, 'bolt_head');
        expect(saved[1].roi!.toJson(), roi.toJson());
        expect(saved[1].expectedCount, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
