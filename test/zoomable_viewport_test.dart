import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:catcheye_studio/models/roi_config.dart';
import 'package:catcheye_studio/providers/roi_config_provider.dart';
import 'package:catcheye_studio/screens/reference_images_screen.dart';
import 'package:catcheye_studio/services/remote_reference_api_service.dart';
import 'package:catcheye_studio/widgets/roi_editor_canvas.dart';
import 'package:catcheye_studio/widgets/zoomable_viewport.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 400, height: 300, child: child)),
  ),
);

Future<void> drag(WidgetTester tester, Offset start, Offset end) async {
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(Offset.lerp(start, end, 0.5)!);
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.moveTo(end);
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.up();
  await tester.pumpAndSettle();
}

TransformationController controller(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!;

void main() {
  testWidgets('wheel anchors zoom at cursor, keeps live updates, and resets', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const ZoomableViewport(child: ColoredBox(color: Colors.red))),
    );
    final origin = tester.getTopLeft(find.byType(InteractiveViewer));
    const focal = Offset(120, 80);
    final before = controller(tester).toScene(focal);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: origin + focal,
        scrollDelta: const Offset(0, -120),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    expect(controller(tester).value.getMaxScaleOnAxis(), greaterThan(1));
    expect(
      (controller(tester).toScene(focal) - before).distance,
      lessThan(0.001),
    );
    final matrix = controller(tester).value.clone();
    await tester.pumpWidget(
      host(const ZoomableViewport(child: ColoredBox(color: Colors.blue))),
    );
    expect(controller(tester).value, matrix);
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(controller(tester).value, Matrix4.identity());
  });

  testWidgets(
    'zoom and pan preserve box image coordinates and move mode never draws',
    (tester) async {
      var boxes = <ReferenceBox>[];
      await tester.pumpWidget(
        host(
          ReferenceBoxEditor(
            imageBytes: base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
            ),
            imageWidth: 1000,
            imageHeight: 500,
            boxes: boxes,
            onBoxesChanged: (value) => boxes = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('확대'));
      await tester.pump();
      await tester.tap(find.byTooltip('이동 모드: 드래그로 이동, 두 손가락으로 확대·축소'));
      await tester.pump();
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final before = controller(tester).value.clone();
      await drag(tester, center, center + const Offset(20, 15));
      expect(controller(tester).value, isNot(before));
      expect(boxes, isEmpty);
      await tester.tap(find.byTooltip('편집 모드: 드래그로 편집'));
      await tester.pump();
      final image = tester.renderObject<RenderBox>(find.byType(Image));
      await drag(
        tester,
        image.localToGlobal(const Offset(100, 60)),
        image.localToGlobal(const Offset(200, 120)),
      );
      expect(boxes, hasLength(1));
      expect(boxes.single.toJson(), [250.0, 150.0, 500.0, 300.0]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zoomed ROI drag moves the original vertex without coordinate drift',
    (tester) async {
      final provider = RoiConfigProvider();
      provider.loadFromConfig(
        CameraRoiConfig(
          cameraId: 'test',
          imageWidth: 1000,
          imageHeight: 500,
          allowedZones: [
            RoiPolygon(
              id: 'zone',
              name: 'Zone',
              points: [
                RoiPoint(x: 250, y: 150),
                RoiPoint(x: 700, y: 150),
                RoiPoint(x: 700, y: 400),
              ],
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        host(
          ChangeNotifierProvider.value(
            value: provider,
            child: const RoiEditorCanvas(),
          ),
        ),
      );
      await tester.tap(find.byTooltip('확대'));
      await tester.pump();
      final canvas = tester.renderObject<RenderBox>(
        find
            .descendant(
              of: find.byType(RoiEditorCanvas),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      await drag(
        tester,
        canvas.localToGlobal(const Offset(100, 60)),
        canvas.localToGlobal(const Offset(160, 100)),
      );
      final point = provider.config.allowedZones.first.points.first;
      expect(point.x, closeTo(400, 0.001));
      expect(point.y, closeTo(250, 0.001));
      expect(tester.takeException(), isNull);
    },
  );
}
