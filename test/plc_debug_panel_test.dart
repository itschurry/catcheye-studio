import 'package:catcheye_studio/theme/studio_theme.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/providers/settings_provider.dart';
import 'package:catcheye_studio/screens/production_screen.dart';
import 'package:catcheye_studio/services/remote_capture_api_service.dart';
import 'package:catcheye_studio/services/remote_production_api_service.dart';
import 'package:catcheye_studio/widgets/plc_debug_panel.dart';
import 'production_api_test.dart' show catalogJson;
import 'production_models_test.dart' show captureJson;

RecipeCatalog debugCatalog() {
  final json = catalogJson();
  for (final product in json['products'] as List) {
    product['active_revision'] = 1;
    product['active'] = {
      'name': '제품 ${product['product_id']}',
      'points': [
        for (var i = 0; i < 2; i++)
          {
            'name': 'P${i + 1}',
            'inspection_id': i == 0 ? 'bolt_head' : 'stud',
            'expected_count': 2,
            'candidate_confidence': .4,
            'present_confidence': .5,
            'geometry': null,
          },
      ],
    };
  }
  return RecipeCatalog.fromJson(json);
}

Map<String, dynamic> debugStatus({
  String source = 'simulator',
  String state = 'CONNECTED',
}) => {
  'api_version': 3,
  'control_epoch': 'boot',
  'capture': null,
  'events': [],
  'error': '',
  'plc': {
    'source': source,
    'simulator_supported': true,
    'state': state,
    'enabled': true,
    'host': source == 'simulator' ? '127.0.0.1' : '192.168.1.50',
    'port': 2500,
    'error': '',
    'events': [],
    'rx_map': <String, dynamic>{},
    'tx_map': {'ok': 0, 'ng': 1, 'heartbeat': 2},
    'tx_words': [0, 1, 1],
    'simulator': source == 'simulator'
        ? {
            'simulator_id': 'sim-1',
            'state': 'IDLE',
            'error': '',
            'request_id': null,
            'result': null,
            'cleared': false,
            'rearmed': true,
            'received_words': [0, 0, 1],
          }
        : null,
  },
};

void main() {
  late RemoteCaptureApiService captureApi;
  setUp(() => captureApi = RemoteCaptureApiService());
  tearDown(() => captureApi.close());
  Future<void> panel(
    WidgetTester tester,
    Map<String, dynamic> status, {
    bool fresh = true,
    double width = 1000,
    void Function(String, int, int, int)? onCapture,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildStudioTheme(),
        home: Scaffold(
          body: PlcDebugPanel(
            catalog: debugCatalog(),
            status: ProductionStatus.fromJson(status),
            fresh: fresh,
            busy: false,
            captureApi: captureApi,
            onConnect: (_) {},
            onDisconnect: () {},
            onConfigure: () {},
            onCapture: onCapture ?? (_, _, _, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selections(WidgetTester tester) async {
    tester
        .widget<DropdownButtonFormField<int>>(
          find.byKey(const ValueKey('debug-product')),
        )
        .onChanged!(5);
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<int>>(
          find.byKey(const ValueKey('debug-point-5')),
        )
        .onChanged!(2);
    tester
        .widget<DropdownButtonFormField<int>>(
          find.byKey(const ValueKey('debug-hardware')),
        )
        .onChanged!(1);
    await tester.pump();
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('GUI selects product 5 point 2 stud at $width', (tester) async {
      List<Object>? shot;
      await panel(
        tester,
        debugStatus(),
        width: width,
        onCapture: (id, product, point, hardware) =>
            shot = [id, product, point, hardware],
      );
      await selections(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('debug-capture')));
      await tester.tap(find.byKey(const ValueKey('debug-capture')));
      expect(shot, ['sim-1', 5, 2, 1]);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('stale status blocks capture and hides ON indicators', (
    tester,
  ) async {
    await panel(tester, debugStatus(), fresh: false);
    await selections(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('debug-capture')))
          .onPressed,
      isNull,
    );
    expect(find.text('Heartbeat ON'), findsNothing);
    expect(find.text('Heartbeat 미확인'), findsOneWidget);
  });
  testWidgets('real PLC mode monitors signals without injection controls', (
    tester,
  ) async {
    await panel(tester, debugStatus(source: 'real'));
    expect(find.byKey(const ValueKey('debug-capture')), findsNothing);
    expect(find.byKey(const ValueKey('debug-product')), findsNothing);
    expect(find.text('NG ON'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('debug-simulator')))
          .onSelected,
      isNull,
    );
  });
  testWidgets('rejected request never displays the previous capture', (
    tester,
  ) async {
    final status = debugStatus();
    status['capture'] = captureJson(origin: 'plc', state: 'COMPLETED')
      ..['request_id'] = 'old-inspect-shot'
      ..['status'] = 'OK';
    status['plc']['request_id'] = 'new-inspect-shot';
    status['plc']['simulator_request_id'] = 'gui-shot';
    status['plc']['error'] = 'HARDWARE_RECIPE_MISMATCH';
    status['plc']['simulator'].addAll({
      'state': 'COMPLETED',
      'request_id': 'gui-shot',
      'result': 'NG',
      'cleared': true,
      'product_id': 1,
      'point_number': 1,
      'hardware_id': 1,
      'received_words': [0, 1, 1],
    });
    await panel(tester, status);
    expect(find.text('이번 요청 결과: NG'), findsOneWidget);
    expect(find.text('HARDWARE_RECIPE_MISMATCH'), findsOneWidget);
    expect(find.textContaining('제품 A · 포인트'), findsNothing);
    status['plc']['request_id'] = 'old-inspect-shot';
    await panel(tester, status);
    expect(find.text('제품 A · 포인트 1 · COMPLETED · OK'), findsOneWidget);
  });
  testWidgets('matched simulator capture loads its saved overlay and counts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    final images = DebugImages();
    addTearDown(settings.dispose);
    addTearDown(images.close);
    final status = debugStatus();
    status['plc']['request_id'] = 'inspect-shot';
    status['plc']['simulator_request_id'] = 'gui-shot';
    status['plc']['simulator'].addAll({
      'state': 'COMPLETED',
      'request_id': 'gui-shot',
      'result': 'NG',
      'cleared': true,
      'product_id': 1,
      'point_number': 1,
      'hardware_id': 0,
    });
    status['capture'] = captureJson(origin: 'plc_simulator', state: 'COMPLETED')
      ..['request_id'] = 'inspect-shot'
      ..['status'] = 'NG'
      ..['results'] = [
        {
          'cycle_id': '1-2-3',
          'state': 'COMPLETED',
          'status': 'NG',
          'set_id': 'fastener',
          'group': 'bolt_stud',
          'inspection_ids': ['bolt_head'],
          'storage_path': 'bolt_head/2026-09-11/1-2-3',
          'inspections': {
            'bolt_head': {
              'inspection_id': 'bolt_head',
              'camera_id': 'bolt_head_camera',
              'status': 'ABSENT',
              'reason': 'COUNT_MISMATCH',
              'expected_count': 3,
              'present_count': 2,
              'artifacts': {'raw': 'raw.png', 'overlay': 'overlay.png'},
            },
          },
        },
      ];
    await tester.binding.setSurfaceSize(const Size(1280, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          theme: buildStudioTheme(),
          home: Scaffold(
            body: PlcDebugPanel(
              catalog: debugCatalog(),
              status: ProductionStatus.fromJson(status),
              fresh: true,
              busy: false,
              captureApi: images,
              onConnect: (_) {},
              onDisconnect: () {},
              onConfigure: () {},
              onCapture: (_, _, _, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('1-2-3')), 400);
    await tester.pumpAndSettle();
    expect(images.paths, ['bolt_head/2026-09-11/1-2-3/bolt_head/overlay']);
    expect(find.textContaining('기대 3 / 검출 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'GUI routes through simulator API without changing real settings',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      final api = DebugApi();
      addTearDown(settings.dispose);
      addTearDown(api.close);
      await tester.binding.setSurfaceSize(const Size(1280, 1100));
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
      await tester.tap(find.widgetWithText(Tab, 'PLC 디버그'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('debug-connect')));
      await tester.pumpAndSettle();
      await selections(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('debug-capture')));
      await tester.tap(find.byKey(const ValueKey('debug-capture')));
      await tester.pumpAndSettle();
      expect(api.calls, ['plc/simulator/connect', 'plc/simulator/capture']);
      expect(api.body, containsPair('simulator_id', 'sim-1'));
      expect(api.body, containsPair('product_id', 5));
      expect(api.body, containsPair('point_number', 2));
      expect(api.body, containsPair('hardware_id', 1));
      expect(api.body!['request_id'], isNotEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class DebugApi extends RemoteProductionApiService {
  Map<String, dynamic> current = debugStatus(
    source: 'real',
    state: 'DISCONNECTED',
  );
  final calls = <String>[];
  Map<String, dynamic>? body;
  @override
  Future<RecipeCatalog> recipes(AppSettings settings) async => debugCatalog();
  @override
  Future<ProductionStatus> status(AppSettings settings) async =>
      ProductionStatus.fromJson(current);
  @override
  Future<Map<String, dynamic>> request(
    AppSettings settings,
    String method,
    String endpoint, [
    Map<String, dynamic>? value,
  ]) async {
    expect(method, 'POST');
    calls.add(endpoint);
    if (endpoint == 'plc/simulator/connect') {
      current = debugStatus();
    } else if (endpoint == 'plc/simulator/capture') {
      body = value;
    } else {
      fail('unexpected mutation $endpoint');
    }
    return {};
  }
}

class DebugImages extends RemoteCaptureApiService {
  final paths = <String>[];
  @override
  Future<Uint8List> fetchStationImage(
    AppSettings settings, {
    required String cycleId,
    required String inspectionId,
    required String kind,
    String? storagePath,
  }) async {
    paths.add('$storagePath/$inspectionId/$kind');
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
    );
  }
}
