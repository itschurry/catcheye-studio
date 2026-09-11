import 'package:catcheye_studio/models/production.dart';
import 'package:catcheye_studio/widgets/inspection_roi_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recipe ROI survives serialization and independent point copies', () {
    for (final hardware in inspectionLabels.keys) {
      final point = RecipePoint(
        name: '중앙',
        inspectionId: hardware,
        expectedCount: 1,
        candidateConfidence: .4,
        presentConfidence: .8,
        geometry: null,
        roi: const InspectionRoi(.25, .2, .5, .6),
      );
      final copy = RecipePoint.fromJson(point.toJson());
      expect(copy.roi!.toJson(), point.roi!.toJson());
      final json = point.toJson()..remove('roi');
      expect(RecipePoint.fromJson(json).roi, isNull);
      json['roi'] = null;
      expect(RecipePoint.fromJson(json).toJson()['roi'], isNull);
      json['roi'] = {'x': 0, 'y': 0, 'width': 1, 'height': 1};
      expect(RecipePoint.fromJson(json).roi!.isValid, isTrue);
    }
  });
  test('invalid and incomplete regions fail explicitly', () {
    for (final json in [
      {'x': .9, 'y': 0, 'width': .2, 'height': 1},
      {'x': 0, 'y': 0, 'width': 0, 'height': 1},
      {'x': 0, 'y': 0, 'height': 1},
      {'x': -1, 'y': 0, 'width': 1, 'height': 1},
      {'x': 0, 'y': double.nan, 'width': 1, 'height': 1},
      {'x': 0, 'y': 0, 'width': 1, 'height': double.infinity},
      {'x': 0, 'y': 0, 'width': '1', 'height': 1},
    ]) {
      expect(() => InspectionRoi.fromJson(json), throwsFormatException);
    }
  });
  for (final imageSize in [const Size(1920, 1200), const Size(1200, 1920)]) {
    testWidgets(
      'drag uses image coordinates and handles reverse drag $imageSize',
      (tester) async {
        InspectionRoi? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 400,
                height: 400,
                child: InspectionRoiCanvas(
                  image: const ColoredBox(color: Colors.grey),
                  imageSize: imageSize,
                  roi: null,
                  onChanged: (roi) => selected = roi,
                ),
              ),
            ),
          ),
        );
        final rect = tester.getRect(
          find.byKey(const ValueKey('inspection-roi-image')),
        );
        expect(rect.width / rect.height, closeTo(imageSize.aspectRatio, .0001));
        final start = rect.topLeft + Offset(rect.width * .75, rect.height * .8);
        final end = rect.topLeft + Offset(rect.width * .25, rect.height * .2);
        final gesture = await tester.startGesture(start);
        await gesture.moveTo(end);
        await gesture.up();
        await tester.pump();
        expect(selected, isNotNull);
        expect(selected!.x, closeTo(.25, .0001));
        expect(selected!.y, closeTo(.2, .0001));
        expect(selected!.width, closeTo(.5, .0001));
        expect(selected!.height, closeTo(.6, .0001));
        // Drag outside the image is clamped, never serialized outside [0, 1].
        final outside = await tester.startGesture(rect.center);
        await outside.moveTo(rect.bottomRight + const Offset(100, 100));
        await outside.up();
        await tester.pump();
        expect(selected!.x + selected!.width, 1);
        expect(selected!.y + selected!.height, 1);
        expect(selected!.isValid, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('letterbox padding and clicks do not overwrite ROI', (
    tester,
  ) async {
    var updates = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: InspectionRoiCanvas(
              image: const ColoredBox(color: Colors.grey),
              imageSize: const Size(200, 100),
              roi: const InspectionRoi(.25, .25, .5, .5),
              onChanged: (_) => updates++,
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(
      find.byKey(const ValueKey('inspection-roi-image')),
    );
    await tester.dragFrom(
      rect.topLeft - const Offset(0, 50),
      const Offset(150, 0),
    );
    await tester.tapAt(rect.center);
    await tester.pump();
    expect(updates, 0);
  });
}
