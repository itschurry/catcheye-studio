import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/providers/settings_provider.dart';
import 'package:catcheye_studio/screens/inspection_results_screen.dart';
import 'package:catcheye_studio/services/remote_capture_api_service.dart';
import 'package:catcheye_studio/services/remote_capture_image_api_service.dart';
import 'package:catcheye_studio/widgets/station_inspection_image.dart';

StationCaptureResult result(String id, {bool saved = true}) =>
    StationCaptureResult.fromJson({
      'cycle_id': id,
      'state': 'COMPLETED',
      'status': 'NG',
      'set_id': 'fastener',
      'group': 'bolt_stud',
      'requested_at_ms': 1789005000000,
      'finished_at_ms': 1789005002000,
      'storage_path': saved ? 'bolt_stud/2026-09-10/$id' : null,
      'inspections': {
        for (final part in ['bolt_head', 'stud'])
          part: {
            'inspection_id': part,
            'camera_id': '${part}_camera',
            'status': part == 'stud' ? 'ABSENT' : 'PRESENT',
            'reason': part == 'stud' ? 'NO_CANDIDATE' : 'TARGET_CONFIRMED',
            'latency_ms': 700,
            'detections': [],
            if (saved)
              'artifacts': {
                'raw': '$part-raw.png',
                'overlay': '$part-overlay.png',
              },
          },
      },
    });

Future<void> _mount(
  WidgetTester tester,
  _Api api, {
  double width = 1400,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => SettingsProvider(
        initialSettings: AppSettings(
          detectorBaseUrl: 'http://station.test:8090',
        ),
      ),
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          fontFamily: 'NotoSansKR',
        ),
        home: Scaffold(body: InspectionResultsScreen(api: api)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [1400.0, 390.0]) {
    testWidgets(
      'Results shows saved NG evidence and switches raw/overlay at $width px',
      (tester) async {
        final api = _Api();
        await _mount(tester, api, width: width);
        expect(api.images, ['cycle_one/stud/overlay']);
        expect(find.textContaining('Stud 미검출'), findsWidgets);
        expect(find.byType(StationInspectionImage), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        // The first image is visible without scrolling through technical JSON.
        expect(tester.getTopLeft(find.byType(Image)).dy, lessThan(650));
        final image = tester.widget<Image>(find.byType(Image));
        await tester.runAsync(
          () => precacheImage(image.image, tester.element(find.byType(Image))),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('원본'));
        await tester.pumpAndSettle();
        expect(api.images.last, 'cycle_one/stud/raw');
        await tester.tap(find.text('Bolt Head · 검출'));
        await tester.pumpAndSettle();
        expect(api.images.last, 'cycle_one/bolt_head/overlay');
        final count = api.images.length;
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(
          api.images,
          hasLength(count),
          reason: 'status polling must not reload unchanged image evidence',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'archive browser shows capacity, date counts, pagination and latest selection',
    (tester) async {
      final api = _BrowserApi();
      await _mount(tester, api);
      expect(find.text('저장 공간'), findsOneWidget);
      expect(find.text('60% 사용 중'), findsOneWidget);
      expect(find.textContaining('검사 데이터'), findsOneWidget);
      expect(find.text('2026-09-10 (2)'), findsOneWidget);
      await tester.tap(find.text('더 보기'));
      await tester.pumpAndSettle();
      expect(api.pages.last, '2026-09-10/next');
      expect(find.text('더 보기'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-09-09 (1)').last);
      await tester.pumpAndSettle();
      expect(api.pages.last, '2026-09-09/');
      expect(api.images.last, '100-100-1/stud/overlay');
      expect(api.savedPaths.last, 'bolt_stud/2026-09-09/100-100-1');
      await tester.tap(find.byTooltip('최신 결과'));
      await tester.pumpAndSettle();
      expect(api.images.last, '200-200-2/stud/overlay');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late date response cannot replace the newly selected date', (
    tester,
  ) async {
    final api = _BrowserApi();
    await _mount(tester, api);
    api.delayedDate = Completer<StationArchivePage>();
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .onChanged!('2026-09-09');
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .onChanged!('2026-09-10');
    await tester.pumpAndSettle();
    api.delayedDate!.complete(
      StationArchivePage(date: '2026-09-09', results: [result('100-100-1')]),
    );
    await tester.pumpAndSettle();
    expect(api.images.last, '200-200-2/stud/overlay');
    expect(find.text('2026-09-10 (2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'missing image endpoint is explicit and never requests live capture',
    (tester) async {
      final api = _Api()..imageFailure = true;
      await _mount(tester, api, width: 390);
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('Inspect의 이미지 조회 API 적용 여부'), findsOneWidget);
      expect(api.images, ['cycle_one/stud/overlay']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unsaved inspection reports missing evidence without issuing an image request',
    (tester) async {
      final api = _Api()..records = [result('cycle_one', saved: false)];
      await _mount(tester, api);
      expect(api.images, isEmpty);
      expect(find.textContaining('이미지가 저장되지 않았습니다.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late image response cannot overwrite another inspection', (
    tester,
  ) async {
    final api = _Api();
    await _mount(tester, api);
    final delayed = Completer<Uint8List>();
    api.delayed = delayed;
    await tester.tap(find.text('원본'));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    api.delayed = null;
    await tester.tap(find.text('Bolt Head · 검출'));
    await tester.pumpAndSettle();
    delayed.completeError(StateError('stale image failure'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('stale image failure'), findsNothing);
    expect(api.images.last, 'cycle_one/bolt_head/overlay');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('changing device clears the previous device evidence', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = _Api();
    await _mount(tester, api);
    api.records = [result('cycle_new_device')];
    final provider = tester
        .element(find.byType(InspectionResultsScreen))
        .read<SettingsProvider>();
    await provider.updateDetectorBaseUrl('http://other-station.test:8090');
    await tester.pumpAndSettle();
    expect(find.text('검사 결과 · 1건'), findsOneWidget);
    expect(api.images.last, 'cycle_new_device/stud/overlay');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'switching cycle requests the selected cycle instead of the latest one',
    (tester) async {
      final api = _Api()..records = [result('cycle_one'), result('cycle_two')];
      await _mount(tester, api);
      final lists = find.byType(InkWell);
      final secondCycle = find
          .ancestor(
            of: find.text('Bolt Head · Stud 검사 · Stud 미검출').at(1),
            matching: lists,
          )
          .first;
      await tester.tap(secondCycle);
      await tester.pumpAndSettle();
      expect(api.images.last, 'cycle_two/stud/overlay');
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _Api extends RemoteCaptureApiService {
  List<StationCaptureResult> records = [result('cycle_one')];
  final images = <String>[];
  final savedPaths = <String?>[];
  bool imageFailure = false;
  Completer<Uint8List>? delayed;
  @override
  Future<StationArchiveDates> fetchStationArchiveDates(
    AppSettings settings,
  ) async => StationArchiveDates(
    storage: const CaptureStorageInfo(
      path: '/outputs',
      totalBytes: 10000000,
      availableBytes: 4000000,
      usedBytes: 6000000,
      usedPercent: 60,
      captureBytes: 10000,
      captureCount: 4,
    ),
    resultCount: records.length,
    dates: [CaptureDateSummary(date: '2026-09-10', count: records.length)],
  );
  @override
  Future<StationArchivePage> fetchStationArchive(
    AppSettings settings, {
    required String date,
    int limit = 100,
    String? cursor,
  }) async => StationArchivePage(date: date, results: records);
  @override
  Future<Uint8List> fetchStationImage(
    AppSettings settings, {
    required String cycleId,
    required String inspectionId,
    required String kind,
    String? storagePath,
  }) async {
    images.add('$cycleId/$inspectionId/$kind');
    savedPaths.add(storagePath);
    if (imageFailure) {
      throw RemoteCaptureApiException(
        method: 'GET',
        uri: Uri.parse('http://station.test:8090/image'),
        statusCode: 404,
        message: 'unknown or expired cycle_id',
      );
    }
    if (delayed != null) return delayed!.future;
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAGQAAABQCAIAAABga0e4AAAAl0lEQVR4nO3QUQkAIBTAwBfRECYxuRX8G8LBAoybtY8em/zgo2DBgpUHCxasPFiwYOXBggUrDxYsWHmwYMHKgwULVh4sWLDyYMGClQcLFqw8WLBg5cGCBSsPFixYebBgwcqDBQtWHixYsPJgwYKVBwsWrDxYsGDlwYIFKw8WLFh5sGDByoMFC1YeLFiw8mDBgpUHCxasvAvNf9msKaoTQwAAAABJRU5ErkJggg==',
    );
  }

  @override
  Future<StationCaptureAccepted> requestStationCapture(
    AppSettings settings, {
    required StationCaptureTarget target,
  }) => throw StateError('Results must never capture');
  @override
  Future<StationViewerSource> fetchViewerSource(AppSettings settings) =>
      throw StateError('Results must never use preview');
}

class _BrowserApi extends _Api {
  final pages = <String>[];
  Completer<StationArchivePage>? delayedDate;
  @override
  Future<StationArchiveDates> fetchStationArchiveDates(
    AppSettings settings,
  ) async {
    final original = await super.fetchStationArchiveDates(settings);
    return StationArchiveDates(
      storage: original.storage,
      resultCount: 3,
      dates: const [
        CaptureDateSummary(date: '2026-09-10', count: 2),
        CaptureDateSummary(date: '2026-09-09', count: 1),
      ],
    );
  }

  @override
  Future<StationArchivePage> fetchStationArchive(
    AppSettings settings, {
    required String date,
    int limit = 100,
    String? cursor,
  }) async {
    pages.add('$date/${cursor ?? ''}');
    if (date == '2026-09-09' && delayedDate != null) return delayedDate!.future;
    final id = date == '2026-09-09'
        ? '100-100-1'
        : cursor == null
        ? '200-200-2'
        : '200-200-1';
    final saved = StationCaptureResult.fromJson({
      ...result(id).rawJson,
      'storage_path': 'bolt_stud/$date/$id',
      'size_bytes': 1200,
    });
    return StationArchivePage(
      date: date,
      results: [saved],
      nextCursor: date == '2026-09-10' && cursor == null ? 'next' : null,
    );
  }
}
