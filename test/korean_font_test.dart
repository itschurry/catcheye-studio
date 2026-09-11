import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:catcheye_studio/screens/reference_images_screen.dart';
import 'package:catcheye_studio/widgets/status_label.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansCJKkr-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSansCJKkr-Bold.otf'));
    await loader.load();
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets('bundled Korean font renders editor controls at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData.dark().copyWith(
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'NotoSansKR',
            ),
          ),
          home: Scaffold(
            body: Column(
              children: [
                const Text(
                  '기준 이미지 · 왜곡 보정 · 확대·축소',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('Bolt Head · Stud · Nut · Nut Hole · Plain Hole'),
                Expanded(
                  child: ReferenceBoxEditor(
                    imageBytes: base64Decode(
                      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
                    ),
                    imageWidth: 1920,
                    imageHeight: 1200,
                    boxes: const [],
                    onBoxesChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(ReferenceBoxEditor));
      expect(MaterialLocalizations.of(context).cancelButtonLabel, '취소');
      expect(Theme.of(context).textTheme.bodyMedium!.fontFamily, 'NotoSansKR');
      await tester.tap(find.byTooltip('확대'));
      await tester.pump();
      expect(find.text('125%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final weight in [FontWeight.normal, FontWeight.bold]) {
    testWidgets('Korean glyphs render distinct shapes at $weight', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                for (final text in ['가', '한'])
                  RepaintBoundary(
                    key: ValueKey(text),
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: Text(
                        text,
                        style: TextStyle(
                          fontFamily: 'NotoSansKR',
                          fontSize: 32,
                          fontWeight: weight,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pixels = <List<int>>[];
      await tester.runAsync(() async {
        for (final text in ['가', '한']) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(ValueKey(text)),
          );
          final image = await boundary.toImage();
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          pixels.add(bytes!.buffer.asUint8List());
          image.dispose();
        }
      });
      expect(
        pixels[0],
        isNot(orderedEquals(pixels[1])),
        reason:
            'Korean characters must render as different glyphs, not identical missing-glyph boxes',
      );
    });
  }

  test('status labels translate display values without changing raw codes', () {
    expect(statusLabel('NG'), '불량');
    expect(statusLabel('EQUIPMENT_ERROR'), '장비 오류');
    expect(statusLabel('rolledBack'), '이전 모델로 복원됨');
    expect(statusLabel('NEW_STATUS'), contains('NEW_STATUS'));
  });
}
