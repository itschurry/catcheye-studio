import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/controllers/station_controller.dart';
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/models/station_viewer_layout.dart';
import 'package:catcheye_studio/services/remote_capture_api_service.dart';
import 'station_capture_actions_test.dart' show statusJson;

class StationApi extends RemoteCaptureApiService {
  final selection = Completer<StationViewerSource>();
  final capture = Completer<StationCaptureAccepted>();
  bool failSource = false, failStatus = false;
  int reads = 0;
  @override
  Future<StationCaptureStatus> fetchStationStatus(AppSettings settings) async {
    reads++;
    if (failStatus) throw StateError('offline');
    return StationCaptureStatus.fromJson(statusJson('fastener'));
  }

  @override
  Future<StationViewerSource> fetchViewerSource(AppSettings settings) async {
    if (failSource) throw StateError('source unknown');
    return StationViewerSource(
      cameraIds: [settings.apiBasePath == '/other' ? 'new' : 'old'],
      cameras: const [],
    );
  }

  @override
  Future<StationViewerSource> setViewerSources(
    AppSettings settings,
    List<String> cameraIds,
  ) => selection.future;
  @override
  Future<StationCaptureAccepted> requestStationCapture(
    AppSettings settings, {
    required StationCaptureTarget target,
  }) => capture.future;
}

void main() {
  late StationApi api;
  late StationController controller;
  late List<String>? selected;
  setUp(() async {
    api = StationApi();
    selected = null;
    controller = StationController(
      api: api,
      selectCameras: (ids) => selected = ids,
      persistLayout: (_, _) async {},
    );
    await controller.initialize(AppSettings());
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() {
    controller.dispose();
    api.close();
  });
  test('selection response from a previous endpoint is ignored', () async {
    final pending = controller.setSources(StationViewerLayout.oneByOne, [
      'obsolete',
    ]);
    await controller.initialize(AppSettings(apiBasePath: '/other'));
    api.selection.complete(
      const StationViewerSource(cameraIds: ['obsolete'], cameras: []),
    );
    await pending;
    expect(selected, ['new']);
    expect(controller.source!.cameraIds, ['new']);
    expect(controller.sourceBusy, isFalse);
  });
  test(
    'capture completion after disconnect creates no cycle and starts no poll',
    () async {
      final pending = controller.capture(StationCaptureTarget.boltHead);
      controller.suspend();
      final reads = api.reads;
      api.capture.complete(
        const StationCaptureAccepted(
          accepted: true,
          cycleId: 'old-cycle',
          error: '',
        ),
      );
      expect(await pending, isFalse);
      await controller.poll();
      expect(controller.cycles, isEmpty);
      expect(api.reads, reads);
    },
  );
  test(
    'failed selection and verification leave the actual source unknown',
    () async {
      final pending = controller.setSources(StationViewerLayout.oneByOne, [
        'unknown',
      ]);
      api.failSource = true;
      api.selection.completeError(StateError('selection failed'));
      await pending;
      expect(controller.source, isNull);
      expect(selected, isEmpty);
      expect(controller.error, contains('실제 선택 확인 실패'));
      expect(controller.sourceBusy, isFalse);
    },
  );
  test('successful poll clears only the recovered poll error', () async {
    api.failStatus = true;
    await controller.poll();
    expect(controller.error, contains('offline'));
    api.failStatus = false;
    await controller.poll();
    expect(controller.error, isNull);
    expect(controller.status!.ready, isTrue);
  });
}
