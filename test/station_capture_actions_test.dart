import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:catcheye_studio/services/remote_capture_api_service.dart';
import 'package:catcheye_studio/widgets/station_capture_actions.dart';

Map<String, dynamic> statusJson(
  String profile, {
  bool ready = true,
  int pending = 0,
}) => {
  'set_id': profile,
  'ready': ready,
  'busy': false,
  'pending_count': pending,
  'max_pending_captures': 4,
  'groups': profile == 'fastener'
      ? {
          'bolt_stud': ['bolt_head', 'stud'],
          'nut': ['nut', 'nut_hole_alignment'],
        }
      : <String, dynamic>{},
  'cameras': {
    for (var i = 0; i < (profile == 'fastener' ? 4 : 2); i++)
      'camera_$i': {'open': false, 'frame_sequence': 0, 'last_error': ''},
  },
};

Widget screen({
  required StationCaptureStatus? status,
  required ValueChanged<StationCaptureTarget> onCapture,
  bool connected = true,
  bool inFlight = false,
}) => MaterialApp(
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(12),
      child: StationCaptureActions(
        status: status,
        connected: connected,
        inFlight: inFlight,
        onCapture: onCapture,
      ),
    ),
  ),
);

void main() {
  test(
    'profile identity is required and component targets do not depend on groups',
    () {
      for (final value in [null, '', 1]) {
        final json = statusJson('fastener')..['set_id'] = value;
        expect(
          () => StationCaptureStatus.fromJson(json),
          throwsFormatException,
        );
      }
      final missing = statusJson('fastener')..remove('set_id');
      expect(
        () => StationCaptureStatus.fromJson(missing),
        throwsFormatException,
      );
      expect(
        () => StationCaptureStatus.fromJson(statusJson('unknown')),
        throwsFormatException,
      );
      for (final profile in ['bolt_stud', 'nut']) {
        final json = statusJson(profile)
          ..['groups'] = {
            'nut': ['nut'],
          };
        expect(StationCaptureStatus.fromJson(json).captureTargets, [
          StationCaptureTarget.all,
        ]);
      }
    },
  );

  for (final width in [320.0, 1280.0]) {
    for (final profile in ['fastener', 'bolt_stud', 'nut']) {
      testWidgets('$profile offers the exact capture buttons at width $width', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final status = StationCaptureStatus.fromJson(statusJson(profile));
        final captured = <StationCaptureTarget>[];
        await tester.pumpWidget(
          screen(status: status, onCapture: captured.add),
        );
        expect(
          find.byType(FilledButton),
          findsNWidgets(profile == 'fastener' ? 3 : 1),
        );
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(
          find.text('All Cameras (${profile == 'fastener' ? 4 : 2})'),
          findsOneWidget,
        );
        for (final target in status.captureTargets) {
          final button = find.byKey(ValueKey('station-capture-${target.path}'));
          final rect = tester.getRect(button);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.height, greaterThanOrEqualTo(40));
          await tester.tap(button);
        }
        expect(captured, status.captureTargets);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'changing profile removes group actions without retaining a selector',
    (tester) async {
      final captured = <StationCaptureTarget>[];
      await tester.pumpWidget(
        screen(
          status: StationCaptureStatus.fromJson(statusJson('fastener')),
          onCapture: captured.add,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('station-capture-bolt-stud')));
      await tester.pumpWidget(
        screen(
          status: StationCaptureStatus.fromJson(statusJson('nut')),
          onCapture: captured.add,
        ),
      );
      expect(
        find.byKey(const ValueKey('station-capture-bolt-stud')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('station-capture-nut')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('station-capture-all')));
      expect(captured, [
        StationCaptureTarget.boltStud,
        StationCaptureTarget.all,
      ]);
    },
  );

  testWidgets('unavailable status never guesses capture capabilities', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(status: null, onCapture: (_) => fail('unexpected capture')),
    );
    expect(find.byType(FilledButton), findsNothing);
  });

  for (final state in ['disconnected', 'inFlight', 'notReady', 'queueFull']) {
    testWidgets('$state disables every capture action', (tester) async {
      final status = StationCaptureStatus.fromJson(
        statusJson(
          'fastener',
          ready: state != 'notReady',
          pending: state == 'queueFull' ? 4 : 0,
        ),
      );
      await tester.pumpWidget(
        screen(
          status: status,
          connected: state != 'disconnected',
          inFlight: state == 'inFlight',
          onCapture: (_) => fail('unexpected capture'),
        ),
      );
      for (final button in tester.widgetList<FilledButton>(
        find.byType(FilledButton),
      )) {
        expect(button.onPressed, isNull);
      }
    });
  }
}
